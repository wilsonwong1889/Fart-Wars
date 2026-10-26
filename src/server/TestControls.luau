-- Test-only controls for exercising rounds, spawning and combat. They run
-- on the server only: from the Studio command bar,
--   local T = require(game.ServerScriptService.Server.TestControls)
--   T.score("Stinkers", 3)   T.endPhase(5)   T.reloadMap()   T.idle(player, 44)
--   T.spawn(player)   T.team(player, "sharters")   T.resetGas(player)
--   T.gas(player, 95)   T.weapon(player, "GasBlaster")   T.barrels()   T.stats()
--   T.coins(player, 500)   T.xp(player, 1000)   T.profile(player)
--   T.ability(player, "GasPulse")   T.selftest(player)
-- or as chat commands from a player who may use them (anyone in Studio; in
-- live servers only GameConfig.TEST_CONTROLS.USER_IDS), with /fw or !fw:
--   /fw score stinkers 3   /fw end 5   /fw reloadmap   /fw idle 44
--   /fw spawn   /fw team sharters   /fw resetgas   /fw gas 95
--   /fw weapon gasblaster   /fw barrels   /fw stats
--   /fw coins 500   /fw xp 1000   /fw profile   /fw ability gaspulse
--   /fw selftest   /fw daily   /fw spins 3
-- Ordinary clients can't reach any of it. Turn GameConfig.TEST_CONTROLS
-- .ENABLED off before any public release.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local States = require(Shared.States)
local Services = script.Parent.Services
local MatchScoreService = require(Services.MatchScoreService)
local RoundService = require(Services.RoundService)
local MapService = require(Services.MapService)
local TeamService = require(Services.TeamService)
local PlayerLifecycleService = require(Services.PlayerLifecycleService)
local CombatService = require(Services.CombatService)
local GasService = require(Services.GasService)
local BarrelService = require(Services.BarrelService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local LoadoutService = require(Services.LoadoutService)
local RewardsService = require(Services.RewardsService)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local MapBase = require(Shared.Interfaces.MapBase)
local TeamConfig = require(Shared.Config.TeamConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local AudioConfig = require(Shared.Config.AudioConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Messages = require(script.Parent.Messages)
local Telemetry = require(script.Parent.Telemetry)

local TestControls = {}

local ALIASES = {
	stinkers = "Stinkers",
	skibidi = "Stinkers",
	green = "Stinkers",
	sharters = "Sharters",
	sigma = "Sharters",
	yellow = "Sharters",
}

-- Server code may always use them while they're on; a player only in
-- Studio or by user ID.
function TestControls.allowed(player: Player?): boolean
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return false
	end
	if player == nil then
		return true
	end
	return RunService:IsStudio() or table.find(GameConfig.TEST_CONTROLS.USER_IDS, player.UserId) ~= nil
end

function TestControls.score(team: string, count: number?): (boolean, string)
	local id = ALIASES[string.lower(team)] or team
	return MatchScoreService.testAddElimination(id, count)
end

function TestControls.endPhase(seconds: number?): (boolean, string)
	return RoundService.testEndPhaseIn(seconds or 3)
end

function TestControls.reloadMap(): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	local _, entry = MapService.current()
	local ok, err = pcall(MapService.load, if entry then entry.id else GameConfig.DEFAULT_MAP)
	return ok, if ok then "map reloaded" else tostring(err)
end

-- Pretends `player` has been idle for `seconds`, to check the AFK warning
-- and move without waiting a minute.
function TestControls.idle(player: Player, seconds: number?): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	local runtime = PlayerLifecycleService.get(player)
	if not runtime then
		return false, "no such player"
	end
	runtime.lastMeaningfulActivityAt = workspace:GetServerTimeNow() - (seconds or GameConfig.AFK_WARNING_SECONDS - 1)
	return true, `{player.Name} counts as idle for {seconds or GameConfig.AFK_WARNING_SECONDS - 1}s`
end

-- A fresh avatar on the team's spawn (or PLAY, from the home screen).
function TestControls.spawn(player: Player): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	if PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE then
		PlayerLifecycleService.respawn(player)
	else
		PlayerLifecycleService.requestPlay(player, nil)
	end
	return true, `{player.Name} spawned`
end

-- Moves an active player to a team whatever the balance, and respawns them.
function TestControls.team(player: Player, team: string): (boolean, string)
	local id = ALIASES[string.lower(team)] or team
	if not (TestControls.allowed(nil) and TeamService.testSetTeam(player, id)) then
		return false, `can't put {player.Name} on "{team}" (playing? a team? full?)`
	end
	PlayerLifecycleService.respawn(player)
	return true, `{player.Name} is on {id}`
end

-- Empties a player's gas meter.
function TestControls.resetGas(player: Player): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	GasService.reset(player)
	return true, `{player.Name}'s gas is empty`
end

-- Sets a player's gas (100 starts their countdown, with no killer).
function TestControls.gas(player: Player, value: number?): (boolean, string)
	if not (TestControls.allowed(nil) and value) then
		return false, "usage: gas <0-100>"
	end
	if not GasService.testSetGas(player, value) then
		return false, `can't set {player.Name}'s gas (playing? exploding?)`
	end
	return true, `{player.Name} has {math.clamp(value, 0, 100)}% gas`
end

function TestControls.weapon(player: Player, id: string): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	for weaponId in WeaponConfig.weapons do
		if string.lower(weaponId) == string.lower(id) then
			-- Given for real (it's in the profile) once the profile is in.
			if not LoadoutService.testGive(player, "weapon", weaponId) then
				CombatService.setWeapon(player, weaponId)
			end
			return true, `{player.Name} has the {weaponId}`
		end
	end
	return false, `no weapon "{id}"`
end

-- Rewards: today's daily claim open again, or free spins.
function TestControls.daily(player: Player): (boolean, string)
	if not (TestControls.allowed(nil) and DataService.update(player, function(d)
		d.LastDailyDay = 0
	end)) then
		return false, "no profile yet"
	end
	RewardsService.publish(player)
	return true, `{player.Name} can claim a daily reward again`
end

function TestControls.spins(player: Player, count: number?): (boolean, string)
	local n = math.clamp(math.floor(count or 1), 1, 10)
	if not (TestControls.allowed(nil) and DataService.update(player, function(d)
		d.Spins += n
	end)) then
		return false, "no profile yet"
	end
	RewardsService.publish(player)
	return true, `{player.Name} gets {n} free spin{if n == 1 then "" else "s"}`
end

-- Unlocks and equips a Q ability.
function TestControls.ability(player: Player, id: string): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	for abilityId, ability in AbilityConfig do
		if string.lower(abilityId) == string.lower(id) and ability.input == Enum.KeyCode.Q then
			if LoadoutService.testGive(player, "ability", abilityId) then
				return true, `{player.Name} has {ability.displayName} on Q`
			end
			return false, `{player.Name}'s profile is still loading`
		end
	end
	return false, `no Q ability "{id}"`
end

-- Every gas barrel back, full.
function TestControls.barrels(): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	BarrelService.resetAll()
	return true, `{#BarrelService.all()} barrels reset`
end

-- Coins and XP through the normal grant path (ledger, level-ups, unlocks),
-- in grants no bigger than the per-grant limit.
local function testGrants(player: Player, coins: number, xp: number): boolean
	local limitCoins, limitXP = ProgressionConfig.MAX_COINS_PER_GRANT, ProgressionConfig.MAX_XP_PER_GRANT
	while coins > 0 or xp > 0 do
		local c, x = math.min(coins, limitCoins), math.min(xp, limitXP)
		if not EconomyService.testGrant(player, c, x) then
			return false
		end
		coins -= c
		xp -= x
	end
	return true
end

function TestControls.coins(player: Player, amount: number?): (boolean, string)
	if not (TestControls.allowed(nil) and amount and amount > 0) then
		return false, "usage: coins <n>"
	end
	local ok = testGrants(player, math.floor(amount), 0)
	return ok, if ok then `{player.Name} gets {math.floor(amount)} coins` else "refused (is progression on?)"
end

function TestControls.xp(player: Player, amount: number?): (boolean, string)
	if not (TestControls.allowed(nil) and amount and amount > 0) then
		return false, "usage: xp <n>"
	end
	local ok = testGrants(player, 0, math.floor(amount))
	return ok, if ok then `{player.Name} gets {math.floor(amount)} XP` else "refused (is progression on?)"
end

-- The player's saved progress at a glance.
function TestControls.profile(player: Player): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	local profile = DataService.get(player)
	if not profile then
		return false, `{player.Name}'s profile is still loading`
	end
	local d = profile.data
	return true,
		`{player.Name}: level {d.Level} ({d.XP}/{EconomyService.xpToNext(d)} XP, {d.LifetimeXP} lifetime), {d.Coins} coins, `
			.. `{d.TotalEliminations} eliminations, {d.TotalDeaths} deaths, best streak {d.BestStreak}, `
			.. `weapons {table.concat(d.OwnedWeapons, "/")}, abilities {if #d.UnlockedAbilities > 0 then table.concat(d.UnlockedAbilities, "/") else "none"}, `
			.. (if profile.temporary then "NOT SAVING (temporary profile)" else "saving")
end

-- The remotes the game expects (default.project.json declares them).
local REMOTES = {
	RequestPlay = "RemoteEvent",
	RequestTeam = "RemoteEvent",
	RequestSpectate = "RemoteEvent",
	RoundSnapshot = "RemoteFunction",
	RoundUpdate = "RemoteEvent",
	TeamUpdate = "RemoteEvent",
	UIMessage = "RemoteEvent",
	FireWeapon = "RemoteEvent",
	FartDash = "RemoteEvent",
	CombatEvent = "RemoteEvent",
	ProgressEvent = "RemoteEvent",
	UseAbility = "RemoteEvent",
	ShopRequest = "RemoteFunction",
	ProfileUpdate = "RemoteEvent",
	RewardsRequest = "RemoteFunction",
}

-- Checks, on the real server, what the specs can't: the place's settings,
-- the map, the remotes and teams, DataStore access, the chat system, and
-- the release switches. Prints one line per check; returns the tally.
function TestControls.selftest(player: Player?): (boolean, string)
	if not TestControls.allowed(nil) then
		return false, "test controls are off"
	end
	local results: { { string } } = {}
	local function report(status: string, name: string, detail: string)
		table.insert(results, { status, name, detail })
		print(`[FW] selftest {status} {name}: {detail}`)
	end
	local function expect(ok: boolean, name: string, good: string, bad: string, severity: string?)
		report(if ok then "OK" else severity or "FAIL", name, if ok then good else bad)
	end

	expect(Players.MaxPlayers == GameConfig.MAX_PLAYERS, "Max Players", `{Players.MaxPlayers}`, `{Players.MaxPlayers}; set it to {GameConfig.MAX_PLAYERS} in Game Settings > Places`)
	expect(Players.CharacterAutoLoads == false, "Character auto-loading", "off", "on: avatars would spawn without PLAY")
	expect(workspace.StreamingEnabled == false, "Streaming", "off", "on: the code-built map and spawn checks expect it off")
	local map, entry = MapService.current()
	if map and entry then
		local ok, problems = MapBase.validate(map, entry, TeamConfig.order)
		expect(ok, "Map", `{entry.id} loaded and valid`, table.concat(problems, "; "))
	else
		report("FAIL", "Map", "no map loaded")
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local missing = {}
	for name, className in REMOTES do
		local remote = remotes and remotes:FindFirstChild(name)
		if not (remote and remote.ClassName == className) then
			table.insert(missing, name)
		end
	end
	table.sort(missing)
	expect(#missing == 0, "Remotes", "all 15 present", `missing or wrong: {table.concat(missing, ", ")}`)
	local teamsOk = true
	for _, id in TeamConfig.order do
		teamsOk = teamsOk and game:GetService("Teams"):FindFirstChild(TeamConfig.teams[id].name) ~= nil
	end
	expect(teamsOk, "Teams", "both teams exist", "a team is missing from the Teams service")
	local stored, why = DataService.probe()
	expect(stored, "DataStores", why, `{why} (in Studio: publish, then Game Settings > Security > Enable Studio Access to API Services)`, "WARN")
	if player then
		local status = player:GetAttribute("DataStatus")
		expect(status == "ready", "Your profile", "loaded and saving", `{tostring(status)}: progress won't save this session`, "WARN")
	end
	local chatOk, chatVersion = pcall(function()
		return game:GetService("TextChatService").ChatVersion
	end)
	if chatOk and chatVersion == Enum.ChatVersion.TextChatService then
		expect(TestControls.chatCommand, "Chat", "TextChatService, with /fw as a chat command", "TextChatService, but /fw couldn't be registered: use the command bar", "WARN")
	else
		report("OK", "Chat", if chatOk then `{chatVersion} (/fw via Chatted)` else "legacy chat")
	end
	expect(FeatureFlags.MATCH_MODE == "Rounds" and FeatureFlags.GAS_COMBAT and FeatureFlags.PROGRESSION, "Feature flags", `{FeatureFlags.MATCH_MODE}, combat and progression on`, `MATCH_MODE {FeatureFlags.MATCH_MODE}, GAS_COMBAT {FeatureFlags.GAS_COMBAT}, PROGRESSION {FeatureFlags.PROGRESSION}`, "WARN")
	report("WARN", "Release", `test controls on (allow-list: {#GameConfig.TEST_CONTROLS.USER_IDS}); turn GameConfig.TEST_CONTROLS.ENABLED off before a public release`)
	local silent = 0
	for _, id in AudioConfig :: any do
		if id == "" then
			silent += 1
		end
	end
	expect(silent == 0, "Sounds", "every slot has a sound", `{silent} empty AudioConfig slots (silent until uploaded)`, "WARN")
	local errors = 0
	for _, n in Telemetry.snapshot().errors do
		errors += n
	end
	expect(errors == 0, "Errors", "none so far", `{errors} so far; see the output and /fw stats`)

	local tally = { OK = 0, WARN = 0, FAIL = 0 }
	for _, result in results do
		tally[result[1]] += 1
	end
	return tally.FAIL == 0, `selftest: {tally.OK} ok, {tally.WARN} warnings, {tally.FAIL} failures (one line each in the output)`
end

-- A short summary of the server's counters (all of it goes to the output).
function TestControls.stats(): (boolean, string)
	local snapshot = Telemetry.snapshot()
	local rejected, errored = 0, 0
	for _, reasons in snapshot.rejects do
		for _, n in reasons do
			rejected += n
		end
	end
	for _, n in snapshot.errors do
		errored += n
	end
	local counters = snapshot.counters
	print("[FW] stats", game:GetService("HttpService"):JSONEncode(snapshot))
	local coins, xp = 0, 0
	for key, n in counters do
		if string.sub(key, 1, 14) == "Economy.coins." then
			coins += n
		elseif string.sub(key, 1, 11) == "Economy.xp." then
			xp += n
		end
	end
	local eliminations = counters["Elimination.elimination"] or 0
	local perMinute = eliminations / math.max(1, snapshot.uptimeSeconds / 60)
	return true,
		`shots {counters["Combat.shots"] or 0}, hits {counters["Combat.hits"] or 0}, eliminations {eliminations} ({string.format("%.1f", perMinute)}/min), `
			.. `barrel kills {counters["Elimination.cause.barrel"] or 0}, chain kills {counters["Elimination.cause.chain"] or 0}, `
			.. `spawn deaths {counters["Lifecycle.spawnDeaths"] or 0}, dashes {counters["Dash.dashes"] or 0}, `
			.. `gas recovered {math.floor(counters["Gas.recovered"] or 0)}%, coins granted {coins}, XP granted {xp}, `
			.. `temporary profiles {counters["Data.temporaryProfiles"] or 0}, save failures {counters["Data.saveFailures"] or 0}, `
			.. `rejected {rejected}, errors {errored}`
end

-- Runs one chat command; returns what happened, or nil if it wasn't one.
function TestControls.run(player: Player, text: string): string?
	local words = string.split(string.lower(text), " ")
	if (words[1] ~= "/fw" and words[1] ~= "!fw") or not TestControls.allowed(player) then
		return nil
	end
	local command, ok, message = words[2], false,
		"commands: score <team> [n], end [seconds], reloadmap, idle [seconds], spawn, team <team>, resetgas, gas <n>, weapon <id>, barrels, coins <n>, xp <n>, profile, ability <id>, daily, spins [n], selftest, stats"
	if command == "score" and words[3] then
		ok, message = TestControls.score(words[3], tonumber(words[4]))
	elseif command == "end" then
		ok, message = TestControls.endPhase(tonumber(words[3]))
	elseif command == "reloadmap" then
		ok, message = TestControls.reloadMap()
	elseif command == "idle" then
		ok, message = TestControls.idle(player, tonumber(words[3]))
	elseif command == "spawn" then
		ok, message = TestControls.spawn(player)
	elseif command == "team" and words[3] then
		ok, message = TestControls.team(player, words[3])
	elseif command == "resetgas" then
		ok, message = TestControls.resetGas(player)
	elseif command == "gas" then
		ok, message = TestControls.gas(player, tonumber(words[3]))
	elseif command == "weapon" and words[3] then
		ok, message = TestControls.weapon(player, words[3])
	elseif command == "barrels" then
		ok, message = TestControls.barrels()
	elseif command == "ability" and words[3] then
		ok, message = TestControls.ability(player, words[3])
	elseif command == "coins" then
		ok, message = TestControls.coins(player, tonumber(words[3]))
	elseif command == "xp" then
		ok, message = TestControls.xp(player, tonumber(words[3]))
	elseif command == "profile" then
		ok, message = TestControls.profile(player)
	elseif command == "daily" then
		ok, message = TestControls.daily(player)
	elseif command == "spins" then
		ok, message = TestControls.spins(player, tonumber(words[3]))
	elseif command == "selftest" then
		ok, message = TestControls.selftest(player)
	elseif command == "stats" then
		ok, message = TestControls.stats()
	end
	Messages.send(player, "test", (if ok then "TEST: " else "TEST failed: ") .. message)
	return message
end

-- Whether /fw arrives as a TextChatService command (set by start).
TestControls.chatCommand = false

function TestControls.start()
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return
	end
	-- The same message can come both ways (a chat command and Chatted).
	local lastText: { [Player]: { text: string, at: number } } = setmetatable({}, { __mode = "k" }) :: any
	local function heard(player: Player, text: string)
		local last = lastText[player]
		if last and last.text == text and os.clock() - last.at < 1 then
			return
		end
		lastText[player] = { text = text, at = os.clock() }
		TestControls.run(player, text)
	end
	-- TextChatService (the current chat) delivers /fw only to a command.
	TestControls.chatCommand = pcall(function()
		local command = Instance.new("TextChatCommand")
		command.Name = "FartWarsTestControls"
		command.PrimaryAlias = "/fw"
		command.SecondaryAlias = "!fw"
		command.AutocompleteVisible = false
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				heard(player, text)
			end
		end)
		command.Parent = game:GetService("TextChatService")
	end)
	-- Legacy chat (and anything said in chat).
	local listening: { [Player]: RBXScriptConnection } = {}
	local function listen(player: Player)
		if not listening[player] then
			listening[player] = player.Chatted:Connect(function(text)
				heard(player, text)
			end)
		end
	end
	Players.PlayerAdded:Connect(listen)
	-- A connection that refers back to its player would keep them in memory.
	Players.PlayerRemoving:Connect(function(player)
		local connection = listening[player]
		listening[player] = nil
		if connection then
			connection:Disconnect()
		end
	end)
	for _, player in Players:GetPlayers() do
		listen(player)
	end
end

return TestControls
