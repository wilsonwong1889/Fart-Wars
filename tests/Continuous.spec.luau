-- Continuous play (FeatureFlags.MATCH_MODE = "Continuous"), with the real
-- server and one client:
--   * joining is PLAY: a team, an avatar and the starter weapon straight
--     away, no home screen in the way
--   * one match with no end time starts with the server: never WAITING,
--     never RESULTS, the HUD says LIVE
--   * eliminations score as they happen; nothing resets them
--   * the round test control has nothing to end; spectating and PLAY still
--     work
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

-- Flip the flag before anything reads it.
local flags = ReplicatedStorage.Shared.Config.FeatureFlags
local source, replaced = string.gsub(flags.Source, 'MATCH_MODE = "Rounds"', 'MATCH_MODE = "Continuous"')
assert(replaced == 1, "the flag line moved")
flags.Source = source

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local RoundService = require(server.Services.RoundService)
local Scores = require(server.Services.MatchScoreService)
local TestControls = require(server.TestControls)
local Lifecycle = require(server.Services.PlayerLifecycleService)

task.wait(0.5)
check(RoundService.phase() == "ACTIVE", "the match is on from the start")
local snapshot = RoundService.snapshot()
check(snapshot.phaseEndTime == nil and snapshot.matchMode == "Continuous", "with no end time")

-- A client joins.
local me = Instance.new("Player")
me.Name = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
task.wait(0.5)
check(me:GetAttribute("State") == "ACTIVE" and me:GetAttribute("TeamId") ~= nil, "joining puts me on a team")
check(me.Character and me:GetAttribute("Weapon") == "StarterBlaster", "with an avatar and the starter weapon")
local client = game.StarterPlayer.StarterPlayerScripts.Client
local HUD = require(client.Controllers.HUDController)
local Home = require(client.Controllers.HomeController)
local Combat = require(client.Controllers.CombatController)
for _ = 1, 3 do
	task.wait(0.1)
	RunService.Heartbeat:Fire(0.1)
	RunService.RenderStepped:Fire(0.1)
end
check(not Home.parts.home.Enabled, "no home screen in the way")
check(HUD.parts.time.Text == "LIVE" and HUD.parts.phase.Text == "LIVE MATCH", "the HUD says LIVE")
check(Combat.parts.crosshair.Visible, "crosshair up")

-- An opponent arrives the same way.
local rival = Instance.new("Player")
rival.Name = "Rival"
rival.UserId = 2
rival.Parent = Players
task.wait(0.2)
check(rival:GetAttribute("State") == "ACTIVE" and rival:GetAttribute("TeamId") ~= me:GetAttribute("TeamId"), "a rival on the other team")

-- Scores run on, and nothing ends.
local mine = me:GetAttribute("TeamId")
check(TestControls.score(mine, 2), "eliminations count")
local ok = TestControls.endPhase(0)
check(not ok, "there's no round to end")
for _ = 1, 8 do
	-- keep both avatars moving so the AFK check leaves them be
	for _, p in { me, rival } do
		p.Character:PivotTo(p.Character:GetPivot() * CFrame.new(8, 0, 0))
	end
	task.wait(50)
end
check(RoundService.phase() == "ACTIVE" and RoundService.snapshot().phaseEndTime == nil, "400 seconds on: still the same match")
check(Scores.getScores()[mine] == 2, "and the score stands")
check(me:GetAttribute("State") == "ACTIVE", "still playing")

-- Spectate and PLAY still work.
ReplicatedStorage.Remotes.RequestSpectate.OnServerEvent:Fire(me)
task.wait(0.2)
check(me:GetAttribute("State") == "MENU_SPECTATOR" and Home.parts.home.Enabled, "spectating shows the home screen")
task.wait(1)
Lifecycle.requestPlay(me, nil)
task.wait(0.2)
check(me:GetAttribute("State") == "ACTIVE" and me.Character ~= nil, "PLAY brings me back")

return { status = "PASS", checks = checks }
