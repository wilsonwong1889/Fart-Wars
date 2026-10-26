-- Test-only controls for exercising rounds, spawning and combat. They run
-- on the server only: from the Studio command bar,
--   local T = require(game.ServerScriptService.Server.TestControls)
--   T.score("Stinkers", 3)   T.endPhase(5)   T.reloadMap()   T.idle(player, 44)
--   T.spawn(player)   T.team(player, "sharters")   T.resetGas(player)
--   T.gas(player, 95)   T.weapon(player, "GasBlaster")   T.stats()
-- or as chat commands from a player who may use them (anyone in Studio; in
-- live servers only GameConfig.TEST_CONTROLS.USER_IDS), with /fw or !fw:
--   /fw score stinkers 3   /fw end 5   /fw reloadmap   /fw idle 44
--   /fw spawn   /fw team sharters   /fw resetgas   /fw gas 95
--   /fw weapon gasblaster   /fw stats
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
			CombatService.setWeapon(player, weaponId)
			return true, `{player.Name} has the {weaponId}`
		end
	end
	return false, `no weapon "{id}"`
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
	return true,
		`shots {counters["Combat.shots"] or 0}, hits {counters["Combat.hits"] or 0}, eliminations {counters["Elimination.elimination"] or 0}, rejected {rejected}, errors {errored}`
end

-- Runs one chat command; returns what happened, or nil if it wasn't one.
function TestControls.run(player: Player, text: string): string?
	local words = string.split(string.lower(text), " ")
	if (words[1] ~= "/fw" and words[1] ~= "!fw") or not TestControls.allowed(player) then
		return nil
	end
	local command, ok, message = words[2], false,
		"commands: score <team> [n], end [seconds], reloadmap, idle [seconds], spawn, team <team>, resetgas, gas <n>, weapon <id>, stats"
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
