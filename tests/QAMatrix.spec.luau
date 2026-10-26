-- The Phase 1 QA matrix (plan section 6), row by row, on one server:
--   2 clients join          1v1 starts; one active player each side
--   6 clients join          3v3
--   20 clients join         10v10 maximum; no extra active slots
--   21st connection         the place cap (20) stops it; the server never
--                           gives a 21st slot even if asked
--   Mid-round join          enters the current match at once, same timer
--   Rapid PLAY requests     no second avatar or slot
--   AFK 45/60 seconds       warning, then spectator with the slot freed;
--                           moving clears the warning, jumping on the spot
--                           doesn't count
--   Return from AFK         PLAY rechecks the teams and joins the match
--   Equal score at timeout  draw, no winner
--   Timer under lag         the round is 300 server seconds; a client's
--                           countdown comes from the end time, so a
--                           resync agrees with the server whenever it lands
--   Map reload              every active player respawns on the new map's
--                           pads; spawn lookups point at the new map
--   One team empties        the round finishes; the next waits
-- "Switch V repeatedly" is a client row: see ClientShell.spec.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local shared = ReplicatedStorage.Shared
local GameConfig = require(shared.Config.GameConfig)
local RoundClock = require(shared.RoundClock)
local server = game.ServerScriptService.Server
do
	local run = assert(loadstring(server.Bootstrap.Source, "Bootstrap"))
	setfenv(run, setmetatable({ script = server.Bootstrap }, { __index = getfenv() }))
	run()
end
local RoundService = require(server.Services.RoundService)
local TeamService = require(server.Services.TeamService)
local MapService = require(server.Services.MapService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TestControls = require(server.TestControls)
local Remotes = ReplicatedStorage.Remotes

local messages: { [Player]: { any } } = {}
Remotes.UIMessage.FiredToClient:Connect(function(player, payload)
	messages[player] = messages[player] or {}
	table.insert(messages[player], payload)
end)
local function heard(player: Player, kind: string): any
	for _, payload in messages[player] or {} do
		if payload.kind == kind then
			return payload
		end
	end
	return nil
end

local function now(): number
	return workspace:GetServerTimeNow()
end
local function waitFor(condition: () -> boolean, limit: number): boolean
	local deadline = now() + limit
	while not condition() do
		if now() > deadline then
			return false
		end
		task.wait(0.05)
	end
	return true
end
local idle: { [Player]: boolean } = {}
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	-- Everyone walks about unless a test wants them still.
	task.spawn(function()
		local step = 1
		while player.Parent do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and not idle[player] then
				step = -step
				root.CFrame = root.CFrame * CFrame.new(8 * step, 0, 0)
			end
			task.wait(4)
		end
	end)
	task.wait(0.05)
	return player
end
local function play(player: Player)
	Remotes.RequestPlay.OnServerEvent:Fire(player)
end
local function avatars(): { [string]: number }
	local found = {}
	for _, child in workspace:GetChildren() do
		if child:FindFirstChild("Humanoid") then
			found[child.Name] = (found[child.Name] or 0) + 1
		end
	end
	return found
end
local function counts(): (number, number)
	local c = TeamService.counts()
	return c.Stinkers, c.Sharters
end

local everyone = {}
local function add(n: number)
	for _ = 1, n do
		local player = join(`P{#everyone + 1}`, 300 + #everyone + 1)
		table.insert(everyone, player)
		play(player)
		task.wait(0.05)
	end
end

-- 2, 6 and 20.
add(2)
local s, y = counts()
check(s == 1 and y == 1, "2 clients: 1v1")
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 1), "and the round starts")
add(4)
s, y = counts()
check(s == 3 and y == 3, "6 clients: 3v3")
add(14)
s, y = counts()
check(s == 10 and y == 10 and TeamService.activeCount() == 20, "20 clients: 10v10")

-- 21st.
check(GameConfig.MAX_PLAYERS == 20 and GameConfig.MAX_PLAYERS == 2 * GameConfig.MAX_TEAM_SIZE, "the place cap matches two full teams")
local extra = join("Extra", 399)
play(extra)
task.wait(0.1)
check(extra:GetAttribute("State") == "MENU_SPECTATOR" and extra.Character == nil, "no 21st slot")
check(heard(extra, "teamFull") and string.find(heard(extra, "teamFull").text, "full"), "and a clear full message")
check(TeamService.activeCount() == 20, "still 20 active")

-- Mid-round join (a slot opens, the extra player takes it).
local leaver = everyone[20]
leaver.Parent = nil
task.wait(0.6)
play(extra)
task.wait(0.1)
check(extra:GetAttribute("State") == "ACTIVE" and extra.Character ~= nil, "a mid-round PLAY joins at once")
local theirs = Remotes.RoundSnapshot.OnServerInvoke(extra)
local running = RoundService.snapshot()
check(theirs.roundId == running.roundId and theirs.phaseEndTime == running.phaseEndTime, "with the same round and end time")
check(math.abs(RoundClock.remaining(theirs, now()) :: number - ((running.phaseEndTime :: number) - now())) < 1e-6, "so the same timer")
local found = avatars()
for _, player in everyone do
	if player.Parent then
		check(found[player.Name] == 1, `{player.Name} has exactly one avatar`)
	end
end

-- Rapid PLAY.
local rapid = everyone[1]
Remotes.RequestSpectate.OnServerEvent:Fire(rapid)
task.wait(0.6)
for _ = 1, 10 do
	Remotes.RequestPlay.OnServerEvent:Fire(rapid)
	Lifecycle.requestPlay(rapid, nil)
end
task.wait(0.1)
check(TeamService.activeCount() == 20 and avatars()[rapid.Name] == 1, "rapid PLAY: one slot, one avatar")

-- AFK: one player stands still (jumping once), another wakes up in time.
local sleeper, napper = everyone[2], everyone[3]
idle[sleeper], idle[napper] = true, true
Remotes.RequestSpectate.OnServerEvent:Fire(sleeper)
Remotes.RequestSpectate.OnServerEvent:Fire(napper)
task.wait(0.6)
play(sleeper)
play(napper)
local started = now()
task.wait(20)
local root = sleeper.Character.HumanoidRootPart
root.CFrame = root.CFrame * CFrame.new(0, 6, 0) -- a jump on the spot
task.wait(started + 44 - now())
check(not heard(sleeper, "afkWarning"), "no warning before 45 seconds")
task.wait(started + 46.5 - now())
local warning = heard(sleeper, "afkWarning")
check(warning and warning.text == "BRO FELL ASLEEP MID-FART!", "the warning at 45 seconds")
check(heard(napper, "afkWarning"), "for both of them")
local napRoot = napper.Character.HumanoidRootPart
napRoot.CFrame = napRoot.CFrame * CFrame.new(10, 0, 0)
task.wait(1.5)
check(heard(napper, "afkClear"), "moving takes the warning down")
local sleeperTeam = sleeper:GetAttribute("TeamId")
local before = TeamService.counts()[sleeperTeam]
task.wait(started + 61.5 - now())
check(sleeper:GetAttribute("State") == "AFK_SPECTATOR", "AFK spectator at 60 seconds")
check(sleeper.Character == nil and sleeper.Team == nil and avatars()[sleeper.Name] == nil, "with the avatar gone")
check(TeamService.counts()[sleeperTeam] == before - 1, "and the slot free")
check(heard(sleeper, "afkMoved"), "and told so")
check(napper:GetAttribute("State") == "ACTIVE", "the one who moved stays")
idle[napper] = nil

-- Return from AFK.
local roundNow = RoundService.snapshot().roundId
play(sleeper)
task.wait(0.1)
check(sleeper:GetAttribute("State") == "ACTIVE" and sleeper.Character ~= nil, "PLAY brings an AFK player back")
check(sleeper:GetAttribute("TeamId") == sleeperTeam, "onto the team that's short")
check(RoundService.snapshot().roundId == roundNow, "in the current match")
idle[sleeper] = nil

-- Equal score at timeout.
TestControls.endPhase(0)
check(waitFor(function()
	return RoundService.phase() == "ACTIVE" and RoundService.snapshot().roundId == roundNow + 1
end, 17), "a fresh round")
TestControls.score("Stinkers", 4)
TestControls.score("Sharters", 4)
TestControls.endPhase(0)
check(waitFor(function()
	return RoundService.phase() == "RESULTS"
end, 1), "results")
local result = RoundService.snapshot().result
check(result.draw and result.winner == nil and result.scores.Stinkers == 4, "4-4: a draw, no winner")

-- Timer under lag.
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 16), "next round")
local round = RoundService.snapshot()
check(round.phaseEndTime - round.phaseStartTime == 300, "300 server seconds")
task.wait(37.3) -- a client that heard nothing for a while...
local late = Remotes.RoundSnapshot.OnServerInvoke(everyone[4])
check(late.phaseEndTime == round.phaseEndTime, "...resyncs to the same end time")
check(math.abs((RoundClock.remaining(round, now()) :: number) - (round.phaseEndTime - now())) < 1e-6, "and even its old snapshot reads true")

-- Map reload (everyone holds still so they're checked where they spawned).
for _, player in Players:GetPlayers() do
	idle[player] = true
end
TestControls.reloadMap()
task.wait(0.2)
local map = workspace:FindFirstChild("Map")
local placed = 0
for _, player in Players:GetPlayers() do
	if player:GetAttribute("State") == "ACTIVE" then
		local team = player:GetAttribute("TeamId")
		local spawn = player.RespawnLocation
		check(spawn and spawn:IsDescendantOf(map) and spawn:GetAttribute("TeamId") == team, `{player.Name} spawned from the new map`)
		local near = false
		for _, pad in MapService.spawns(team) do
			near = near or (pad.Position - player.Character.HumanoidRootPart.Position).Magnitude < 5
		end
		check(near, `{player.Name} is on a pad of their team`)
		placed += 1
	end
end
check(placed == TeamService.activeCount() and placed >= 19, "everyone active was respawned")

-- One team empties.
for _, player in Players:GetPlayers() do
	if player:GetAttribute("TeamId") == "Sharters" then
		Remotes.RequestSpectate.OnServerEvent:Fire(player)
	end
end
task.wait(0.6)
check(TeamService.counts().Sharters == 0, "the Sharters all stepped out")
check(RoundService.phase() == "ACTIVE", "the round carries on")
TestControls.endPhase(0)
check(waitFor(function()
	return RoundService.phase() == "WAITING"
end, 17), "it finishes, then waits")
task.wait(3)
check(RoundService.phase() == "WAITING", "for the minimum population")

return { status = "PASS", checks = checks }
