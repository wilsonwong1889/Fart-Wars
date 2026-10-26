-- Test-only controls for exercising rounds before combat exists. They run
-- on the server only: from the Studio command bar,
--   local T = require(game.ServerScriptService.Server.TestControls)
--   T.score("Stinkers", 3)   T.endPhase(5)   T.reloadMap()   T.idle(player, 44)
-- or as chat commands from a player who may use them (anyone in Studio; in
-- live servers only GameConfig.TEST_CONTROLS.USER_IDS), with /fw or !fw:
--   /fw score stinkers 3   /fw end 5   /fw reloadmap   /fw idle 44
-- Ordinary clients can't reach any of it. Turn GameConfig.TEST_CONTROLS
-- .ENABLED off before any public release.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Services = script.Parent.Services
local MatchScoreService = require(Services.MatchScoreService)
local RoundService = require(Services.RoundService)
local MapService = require(Services.MapService)
local PlayerLifecycleService = require(Services.PlayerLifecycleService)
local Messages = require(script.Parent.Messages)

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

-- Runs one chat command; returns what happened, or nil if it wasn't one.
function TestControls.run(player: Player, text: string): string?
	local words = string.split(string.lower(text), " ")
	if (words[1] ~= "/fw" and words[1] ~= "!fw") or not TestControls.allowed(player) then
		return nil
	end
	local command, ok, message = words[2], false, "commands: score <team> [n], end [seconds], reloadmap, idle [seconds]"
	if command == "score" and words[3] then
		ok, message = TestControls.score(words[3], tonumber(words[4]))
	elseif command == "end" then
		ok, message = TestControls.endPhase(tonumber(words[3]))
	elseif command == "reloadmap" then
		ok, message = TestControls.reloadMap()
	elseif command == "idle" then
		ok, message = TestControls.idle(player, tonumber(words[3]))
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
