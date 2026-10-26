-- Test-only controls for exercising rounds, spawning and combat. They run
-- on the server only: from the Studio command bar,
--   local T = require(game.ServerScriptService.Server.TestControls)
--   T.score("Stinkers", 3)   T.endPhase(5)   T.reloadMap()   T.idle(player, 44)
--   T.spawn(player)   T.team(player, "sharters")   T.resetGas(player)
--   T.gas(player, 95)   T.weapon(player, "GasBlaster")   T.barrels()   T.stats()
--   T.coins(player, 500)   T.xp(player, 1000)   T.profile(player)
--   T.ability(player, "GasPulse")
-- or as chat commands from a player who may use them (anyone in Studio; in
-- live servers only GameConfig.TEST_CONTROLS.USER_IDS), with /fw or !fw:
--   /fw score stinkers 3   /fw end 5   /fw reloadmap   /fw idle 44
--   /fw spawn   /fw team sharters   /fw resetgas   /fw gas 95
--   /fw weapon gasblaster   /fw barrels   /fw stats
--   /fw coins 500   /fw xp 1000   /fw profile   /fw ability gaspulse
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
local AbilityConfig = require(Shared.Config.AbilityConfig)
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

-- Coins and XP through the normal grant path (ledger, level-ups, unlocks).
function TestControls.coins(player: Player, amount: number?): (boolean, string)
	if not (TestControls.allowed(nil) and amount) then
		return false, "usage: coins <n>"
	end
	local ok = EconomyService.testGrant(player, math.floor(amount), 0)
	return ok, if ok then `{player.Name} gets {math.floor(amount)} coins` else "refused (over the per-grant limit?)"
end

function TestControls.xp(player: Player, amount: number?): (boolean, string)
	if not (TestControls.allowed(nil) and amount) then
		return false, "usage: xp <n>"
	end
	local ok = EconomyService.testGrant(player, 0, math.floor(amount))
	return ok, if ok then `{player.Name} gets {math.floor(amount)} XP` else "refused (over the per-grant limit?)"
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
		"commands: score <team> [n], end [seconds], reloadmap, idle [seconds], spawn, team <team>, resetgas, gas <n>, weapon <id>, barrels, coins <n>, xp <n>, profile, ability <id>, stats"
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
	elseif command == "stats" then
		ok, message = TestControls.stats()
	end
	Messages.send(player, "test", (if ok then "TEST: " else "TEST failed: ") .. message)
	return message
end

function TestControls.start()
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return
	end
	local function listen(player: Player)
		player.Chatted:Connect(function(text)
			TestControls.run(player, text)
		end)
	end
	Players.PlayerAdded:Connect(listen)
	for _, player in Players:GetPlayers() do
		listen(player)
	end
end

return TestControls
