-- Each player's runtime state, and every move between the states:
--   join            -> MENU_SPECTATOR (no avatar; the home screen)
--   PLAY            -> ACTIVE on the team TeamService picks, spawned at once,
--                      even mid-round
--   spectate        -> MENU_SPECTATOR again: avatar removed, slot released
--   idle (AFKService) -> AFK_SPECTATOR, the same way
--   practice yard   -> PRACTICE (PracticeService): an avatar in the yard, no
--                      team slot; spectate or PLAY from there as from home
--   leave           -> forgotten, slot released
-- Characters only exist for ACTIVE and PRACTICE players: Players
-- .CharacterAutoLoads is off, spawns go through here, and an avatar that
-- turns up for anyone else is removed. Every match spawn is at the team's
-- safest pad, with a few seconds of protection (the character's
-- "ProtectedUntil" attribute and a ForceField) that firing ends early; the
-- practice yard has no need of it. A new round's spawns are spread over
-- GameConfig.ROUND_SPAWN_SPREAD_SECONDS, the teams taking turns; until a
-- player's turn, the last round's avatar sits out (awaitingSpawn: counted
-- as protected, and CombatService and AbilityService drop what it tries).
-- In continuous play, joining is PLAY. Clients see their state as the
-- Player's "State" attribute.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Messages = require(Server.Messages)
local RateLimit = require(Server.RateLimit)
local Spread = require(Server.Spread)
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local MapService = require(script.Parent.MapService)

local PlayerState = States.Player

export type SessionStats = { plays: number, roundsPlayed: number, afkMoves: number, switches: number }
export type Runtime = {
	userId: number,
	state: string,
	teamId: string?,
	joinedAt: number,
	lastMeaningfulActivityAt: number,
	-- Time spent ACTIVE while a round was running: the later "played at
	-- least 60 seconds" reward rule counts this, not time connected.
	activeSecondsThisRound: number,
	currentRoundId: number,
	preferredTeam: string?,
	sessionStats: SessionStats,
	-- Bumped by every spawn and every move off a team, so a spawn or
	-- respawn that finishes late can tell it has been overtaken.
	spawnToken: number,
	lastSpawnAt: number?,
	-- The spawn (its token) whose avatar is loading right now, if any.
	loadingSpawn: number?,
	-- A new round began and this player's spawn in it hasn't come yet (the
	-- round's spawns are spread out).
	roundSpawnPending: boolean,
	-- Disconnected on leaving: a connection on the Player that refers back
	-- to it would keep a departed player in memory.
	characterAdded: RBXScriptConnection?,
}

local PlayerLifecycleService = {}

-- (player, state, previous): fires on every state change. A player who
-- leaves fires with state nil.
PlayerLifecycleService.StateChanged = Signal.new()
-- (player, character): a fresh avatar is on its pad.
PlayerLifecycleService.Spawned = Signal.new()
-- (player, character): an active player's avatar died. Per-life state
-- (streaks, cooldowns, gas) resets on this.
PlayerLifecycleService.Died = Signal.new()
-- (player, character?): an ACTIVE player is about to lose their slot and
-- avatar (spectating, AFK or leaving), while both still exist.
PlayerLifecycleService.Leaving = Signal.new()
-- (player, character): an avatar is about to be replaced by a fresh one (a
-- team switch, a new round, a map reload), while it still exists.
PlayerLifecycleService.Replacing = Signal.new()

local runtimes: { [Player]: Runtime } = {}
local limiter = RateLimit.new(GameConfig.REQUEST_COOLDOWN_SECONDS)
local roundId = 0
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

function PlayerLifecycleService.get(player: Player): Runtime?
	return runtimes[player]
end

function PlayerLifecycleService.stateOf(player: Player): string?
	local runtime = runtimes[player]
	return runtime and runtime.state
end

local function setState(player: Player, runtime: Runtime, state: string)
	local previous = runtime.state
	runtime.state = state
	runtime.teamId = TeamService.teamOf(player)
	player:SetAttribute("State", state)
	if previous ~= state then
		PlayerLifecycleService.StateChanged:Fire(player, state, previous)
	end
end

-- Whether a player in `state` keeps an avatar.
local function keepsAvatar(state: string?): boolean
	return state == PlayerState.ACTIVE or state == PlayerState.PRACTICE
end

local function removeCharacter(player: Player)
	player:SetAttribute("RespawnAt", nil)
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
end

-- Spawn protection (bots get the same: BotService).

function PlayerLifecycleService.protect(character: Model)
	if not FeatureFlags.SPAWN_PROTECTION then
		return
	end
	character:SetAttribute("ProtectedUntil", now() + GameConfig.SPAWN_PROTECTION_SECONDS)
	local field = Instance.new("ForceField")
	field.Name = "SpawnProtection"
	field.Visible = true
	field.Parent = character
	task.delay(GameConfig.SPAWN_PROTECTION_SECONDS, function()
		if field.Parent then
			field:Destroy()
		end
	end)
end

-- Whether a new round has begun and this player's spawn in it hasn't come
-- yet: the last round's avatar sits out till then.
function PlayerLifecycleService.awaitingSpawn(player: Player): boolean
	local runtime = runtimes[player]
	return runtime ~= nil and runtime.roundSpawnPending and runtime.state == PlayerState.ACTIVE
end

-- Protected: a fresh spawn's few seconds, and an avatar waiting out a new
-- round's spawns (nothing gasses it, and bots leave it alone).
function PlayerLifecycleService.isProtected(player: Player): boolean
	if PlayerLifecycleService.awaitingSpawn(player) then
		return true
	end
	local character = player.Character
	local protectedUntil = character and character:GetAttribute("ProtectedUntil")
	return type(protectedUntil) == "number" and now() < protectedUntil
end

-- Attacking gives up the rest of the protection.
function PlayerLifecycleService.endProtection(player: Player)
	local character = player.Character
	if character and character:GetAttribute("ProtectedUntil") ~= nil then
		character:SetAttribute("ProtectedUntil", nil)
		local field = character:FindFirstChild("SpawnProtection")
		if field then
			field:Destroy()
		end
	end
end

-- Where the live enemy bots of `teamId` stand. BotService fills this in
-- (it loads after this service).
PlayerLifecycleService.enemyBotPositions = function(_teamId: string): { Vector3 }
	return {}
end

-- Where everyone against `teamId` stands, players and bots, so a spawn
-- isn't picked on top of them.
function PlayerLifecycleService.enemyPositions(teamId: string): { Vector3 }
	local positions = {}
	for _, other in Players:GetPlayers() do
		local otherTeam = TeamService.teamOf(other)
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if otherTeam and otherTeam ~= teamId and root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	for _, position in PlayerLifecycleService.enemyBotPositions(teamId) do
		table.insert(positions, position)
	end
	return positions
end

-- Gives an ACTIVE player a fresh avatar at their team's safest spawn.
-- LoadCharacterAsync yields; if the player spectated, left or was spawned again
-- meanwhile, this spawn gives way.
local function spawnPlayer(player: Player, runtime: Runtime)
	runtime.spawnToken += 1
	local teamId = TeamService.teamOf(player)
	if not teamId then
		runtime.roundSpawnPending = false
		return
	end
	runtime.teamId = teamId
	local previous = player.Character
	if previous then
		PlayerLifecycleService.Replacing:Fire(player, previous)
	end
	player.RespawnLocation = MapService.safeSpawn(teamId, PlayerLifecycleService.enemyPositions(teamId)) :: any
	local token = runtime.spawnToken
	runtime.loadingSpawn = token
	local ok, err = pcall(player.LoadCharacterAsync, player)
	if runtime.loadingSpawn == token then
		runtime.loadingSpawn = nil
	end
	-- The new avatar is in (or isn't coming): a round's wait is over.
	runtime.roundSpawnPending = false
	if not ok then
		warn(`[Lifecycle] couldn't spawn {player.Name}: {err}`)
	end
	-- The body this life replaces: Roblox only takes it out of the world,
	-- and what still holds it (its Died handler, its gun) would keep it in
	-- memory for good, one more every respawn. Gone once anything finishing
	-- with it (the replaced body's explosion) has.
	if previous and previous ~= player.Character then
		task.delay(2, function()
			if previous.Parent == nil then
				previous:Destroy()
			end
		end)
	end
	-- Spectated while it loaded: the avatar that just arrived goes too. (A
	-- newer spawn replaces this one by itself.)
	if runtimes[player] == runtime and runtime.state ~= PlayerState.ACTIVE then
		removeCharacter(player)
		return
	end
	local character = player.Character
	if character and runtimes[player] == runtime then
		runtime.lastSpawnAt = now()
		PlayerLifecycleService.protect(character)
		Telemetry.log("Lifecycle", "spawned", { player = player, team = teamId })
		PlayerLifecycleService.Spawned:Fire(player, character)
	end
end

-- A fresh avatar at the team's spawn for an ACTIVE player (team switches,
-- test controls).
function PlayerLifecycleService.respawn(player: Player)
	local runtime = runtimes[player]
	if runtime and runtime.state == PlayerState.ACTIVE then
		spawnPlayer(player, runtime)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local runtime = runtimes[player]
	player:SetAttribute("RespawnAt", nil)
	if not runtime or not keepsAvatar(runtime.state) then
		-- Nobody off a team (or out of the practice yard) keeps an avatar
		-- (Studio can auto-load one before the server turns that off).
		task.defer(function()
			if player.Character == character and not keepsAvatar(PlayerLifecycleService.stateOf(player)) then
				removeCharacter(player)
			end
		end)
		return
	end
	-- Hats and hair don't stop shots (or hide the head from a headshot).
	local function ignoreAccessory(item: Instance)
		if item:IsA("Accessory") then
			for _, part in item:GetDescendants() do
				if part:IsA("BasePart") then
					part.CanCollide = false
					part.CanQuery = false
				end
			end
		elseif item:IsA("BasePart") and item:FindFirstAncestorOfClass("Accessory") then
			item.CanCollide = false
			item.CanQuery = false
		end
	end
	for _, item in character:GetDescendants() do
		ignoreAccessory(item)
	end
	character.DescendantAdded:Connect(ignoreAccessory)
	if runtime.state == PlayerState.PRACTICE then
		-- The practice yard looks after its own avatar (PracticeService).
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local token = runtime.spawnToken
	humanoid.Died:Connect(function()
		Telemetry.log("Lifecycle", "died", { player = player })
		if runtime.lastSpawnAt and now() - runtime.lastSpawnAt < GameConfig.SPAWN_DEATH_SECONDS then
			Telemetry.count("Lifecycle.spawnDeaths")
		end
		PlayerLifecycleService.Died:Fire(player, character)
		-- When the next life starts, so the screen can count down to it
		-- (cleared as the new avatar arrives).
		if runtimes[player] == runtime and runtime.state == PlayerState.ACTIVE then
			player:SetAttribute("RespawnAt", now() + GameConfig.RESPAWN_SECONDS)
		end
		task.wait(GameConfig.RESPAWN_SECONDS)
		if runtimes[player] == runtime and runtime.state == PlayerState.ACTIVE and runtime.spawnToken == token and player.Character == character then
			spawnPlayer(player, runtime)
		end
	end)
end

local function teamName(team: string): string
	return TeamConfig.teams[team].name
end

-- PLAY: a slot on the team the rules pick (`preferred` when it doesn't
-- unbalance the teams; otherwise the home screen choice), and an avatar.
function PlayerLifecycleService.requestPlay(player: Player, preferred: unknown)
	local runtime = runtimes[player]
	if not runtime or runtime.state == PlayerState.ACTIVE then
		return
	end
	local wanted = if type(preferred) == "string" and TeamConfig.teams[preferred] then preferred else runtime.preferredTeam
	local team, why = TeamService.assign(player, wanted)
	if not team then
		Messages.send(
			player,
			"teamFull",
			`Both teams are full ({GameConfig.MAX_TEAM_SIZE}v{GameConfig.MAX_TEAM_SIZE}). You're spectating; press PLAY again when a slot opens.`
		)
		return
	end
	if runtime.currentRoundId ~= roundId then
		runtime.activeSecondsThisRound = 0
		runtime.currentRoundId = roundId
	end
	runtime.lastMeaningfulActivityAt = now()
	runtime.sessionStats.plays += 1
	setState(player, runtime, PlayerState.ACTIVE)
	if why == "preferenceRejected" and wanted then
		Messages.send(player, "team", `{teamName(wanted)} would make the teams uneven, so you're on {teamName(team)}.`, { team = team })
	else
		Messages.send(player, "team", `You're on {teamName(team)}!`, { team = team })
	end
	spawnPlayer(player, runtime)
end

-- The practice yard (PracticeService): off the home screen into PRACTICE,
-- an avatar at `at` with no team slot, no spawn protection and no Spawned
-- (it isn't a match spawn); called again in the yard, a fresh avatar there.
-- LoadCharacterAsync yields; if the player left, spectated, played or was
-- sent to the yard again meanwhile, this gives way. Returns the avatar.
function PlayerLifecycleService.enterPractice(player: Player, at: CFrame): Model?
	local runtime = runtimes[player]
	if not runtime or runtime.state == PlayerState.ACTIVE then
		return nil
	end
	runtime.spawnToken += 1
	local token = runtime.spawnToken
	setState(player, runtime, PlayerState.PRACTICE)
	player.RespawnLocation = nil
	local ok, err = pcall(player.LoadCharacterAsync, player)
	if not ok then
		warn(`[Lifecycle] couldn't put {player.Name} in the practice yard: {err}`)
	end
	if runtimes[player] ~= runtime or runtime.spawnToken ~= token then
		-- Overtaken: whatever came after looks after the avatar (a spectate
		-- or a leave removes it; a match spawn replaces it).
		if runtimes[player] == runtime and not keepsAvatar(runtime.state) then
			removeCharacter(player)
		end
		return nil
	end
	local character = player.Character
	if not character then
		return nil
	end
	character:PivotTo(at)
	Telemetry.log("Lifecycle", "practiceSpawned", { player = player })
	return character
end

-- Takes a player off their team: avatar gone, slot free for someone else.
function PlayerLifecycleService.toSpectator(player: Player, state: string): boolean
	local runtime = runtimes[player]
	if not runtime or (state ~= PlayerState.MENU_SPECTATOR and state ~= PlayerState.AFK_SPECTATOR) then
		return false
	end
	if runtime.state == PlayerState.ACTIVE then
		PlayerLifecycleService.Leaving:Fire(player, player.Character)
		TeamService.release(player)
	elseif runtime.state == state then
		return false
	end
	runtime.spawnToken += 1
	runtime.roundSpawnPending = false
	removeCharacter(player)
	if state == PlayerState.AFK_SPECTATOR then
		runtime.sessionStats.afkMoves += 1
	end
	setState(player, runtime, state)
	return true
end

function PlayerLifecycleService.requestSpectate(player: Player)
	local runtime = runtimes[player]
	if runtime and keepsAvatar(runtime.state) then
		PlayerLifecycleService.toSpectator(player, PlayerState.MENU_SPECTATOR)
	end
end

-- On the home screen: remembers the team choice for PLAY (nil = auto).
-- In a match: a voluntary switch, only when it evens the teams out.
function PlayerLifecycleService.requestTeam(player: Player, team: unknown)
	local runtime = runtimes[player]
	if not runtime or (team ~= nil and not (type(team) == "string" and TeamConfig.teams[team])) then
		return
	end
	local wanted = team :: string?
	if runtime.state ~= PlayerState.ACTIVE then
		runtime.preferredTeam = wanted
		player:SetAttribute("PreferredTeam", wanted)
		return
	end
	if wanted == nil or wanted == TeamService.teamOf(player) then
		return
	end
	if TeamService.switch(player, wanted) then
		runtime.teamId = wanted
		runtime.sessionStats.switches += 1
		Messages.send(player, "team", `You switched to {teamName(wanted)}.`, { team = wanted })
		spawnPlayer(player, runtime)
	else
		Messages.send(player, "denied", "Switching now would make the teams less even.")
	end
end

-- Round hooks (RoundService).

-- Whether the player's avatar is still loading, or arrived under
-- SPAWN_PROTECTION_SECONDS ago: they're at their spawn already.
local function freshlySpawned(runtime: Runtime, at: number): boolean
	return runtime.loadingSpawn ~= nil
		or (runtime.lastSpawnAt ~= nil and at - runtime.lastSpawnAt < GameConfig.SPAWN_PROTECTION_SECONDS)
end

-- A player's spawn in a new round, if it's still to come (a team switch
-- or a spectate meanwhile has seen to it).
local function roundSpawn(player: Player)
	local runtime = runtimes[player]
	if runtime and runtime.roundSpawnPending and runtime.state == PlayerState.ACTIVE then
		spawnPlayer(player, runtime)
	end
end

-- A new round: everyone's round stats start again and every active player
-- starts from their team's spawn, spread over ROUND_SPAWN_SPREAD_SECONDS
-- with the teams taking turns (all at once, every client was sent every
-- avatar in one frame). Each waits out its turn in the last round's
-- avatar, sitting out (awaitingSpawn). One who has only just got to their
-- spawn (PLAY under the results a moment before) keeps that avatar: a
-- second straight after the first was a double drop.
function PlayerLifecycleService.beginRound(id: number)
	roundId = id
	local at = now()
	local byTeam: { [string]: { Player } } = {}
	for player, runtime in runtimes do
		runtime.activeSecondsThisRound = 0
		runtime.currentRoundId = id
		if runtime.state == PlayerState.ACTIVE and not freshlySpawned(runtime, at) then
			runtime.roundSpawnPending = true
			local team = TeamService.teamOf(player) or ""
			byTeam[team] = byTeam[team] or {}
			table.insert(byTeam[team], player)
		end
	end
	-- In a known order before the shuffle, so a test run goes the same way
	-- every time.
	local groups = {}
	for _, team in TeamConfig.order do
		table.insert(groups, byTeam[team] or {})
	end
	table.insert(groups, byTeam[""] or {})
	for _, group in groups do
		table.sort(group, function(a, b)
			return a.UserId < b.UserId
		end)
	end
	Spread.over(GameConfig.ROUND_SPAWN_SPREAD_SECONDS, Spread.alternate(groups), roundSpawn)
end

-- Adds round time to everyone ACTIVE (spectators' clocks are paused).
function PlayerLifecycleService.accrue(seconds: number)
	for _, runtime in runtimes do
		if runtime.state == PlayerState.ACTIVE then
			runtime.activeSecondsThisRound += seconds
		end
	end
end

-- The round is over: who took part and for how long, by user ID.
function PlayerLifecycleService.finishRound(): { [number]: number }
	local participation = {}
	for _, runtime in runtimes do
		if runtime.currentRoundId == roundId and runtime.activeSecondsThisRound > 0 then
			runtime.sessionStats.roundsPlayed += 1
			participation[runtime.userId] = runtime.activeSecondsThisRound
		end
	end
	return participation
end

-- Every ACTIVE player again from a spawn (after the map is swapped).
function PlayerLifecycleService.respawnAll()
	for player, runtime in runtimes do
		if runtime.state == PlayerState.ACTIVE then
			task.spawn(spawnPlayer, player, runtime)
		end
	end
end

local function onJoin(player: Player)
	if runtimes[player] then
		return
	end
	local at = now()
	local runtime: Runtime = {
		userId = player.UserId,
		state = PlayerState.MENU_SPECTATOR,
		teamId = nil,
		joinedAt = at,
		lastMeaningfulActivityAt = at,
		activeSecondsThisRound = 0,
		currentRoundId = roundId,
		preferredTeam = nil,
		sessionStats = { plays = 0, roundsPlayed = 0, afkMoves = 0, switches = 0 },
		spawnToken = 0,
		roundSpawnPending = false,
	}
	runtimes[player] = runtime
	player.Neutral = true
	player:SetAttribute("State", runtime.state)
	runtime.characterAdded = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	Telemetry.joined(player)
	PlayerLifecycleService.StateChanged:Fire(player, runtime.state, nil)
	if FeatureFlags.MATCH_MODE == "Continuous" then
		-- No home screen gate: straight onto a team.
		task.defer(PlayerLifecycleService.requestPlay, player, nil)
	end
end

local function onLeave(player: Player)
	local runtime = runtimes[player]
	if not runtime then
		return
	end
	runtime.spawnToken += 1
	if runtime.state == PlayerState.ACTIVE then
		PlayerLifecycleService.Leaving:Fire(player, player.Character)
	end
	TeamService.release(player)
	removeCharacter(player)
	if runtime.characterAdded then
		runtime.characterAdded:Disconnect()
	end
	runtimes[player] = nil
	limiter:forget(player)
	Telemetry.left(player)
	PlayerLifecycleService.StateChanged:Fire(player, nil, runtime.state)
end

function PlayerLifecycleService.start()
	if started then
		return
	end
	started = true
	Players.CharacterAutoLoads = false
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestPlay = remotes:WaitForChild("RequestPlay") :: RemoteEvent
	local requestTeam = remotes:WaitForChild("RequestTeam") :: RemoteEvent
	local requestSpectate = remotes:WaitForChild("RequestSpectate") :: RemoteEvent

	-- Clients only state intent; everything is re-checked here.
	requestPlay.OnServerEvent:Connect(Telemetry.guard("Lifecycle", function(player, preferred)
		if limiter:allow(player, "play") then
			PlayerLifecycleService.requestPlay(player, preferred)
		else
			Telemetry.reject("RequestPlay", player, "rateLimited")
		end
	end))
	requestTeam.OnServerEvent:Connect(Telemetry.guard("Lifecycle", function(player, team)
		if limiter:allow(player, "team") then
			PlayerLifecycleService.requestTeam(player, team)
		else
			Telemetry.reject("RequestTeam", player, "rateLimited")
		end
	end))
	requestSpectate.OnServerEvent:Connect(Telemetry.guard("Lifecycle", function(player)
		if limiter:allow(player, "spectate") then
			PlayerLifecycleService.requestSpectate(player)
		else
			Telemetry.reject("RequestSpectate", player, "rateLimited")
		end
	end))

	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	MapService.Loaded:Connect(PlayerLifecycleService.respawnAll)
end

return PlayerLifecycleService
