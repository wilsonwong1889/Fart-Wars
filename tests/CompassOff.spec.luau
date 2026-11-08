-- FeatureFlags.COMPASS off (on as shipped), with the real server and one
-- client: no compass screen, Z and the middle mouse button send nothing,
-- and the server ignores pings (the remote stays declared, carrying
-- nothing), without an error anywhere.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

-- Flip the flag before anything reads it.
local flags = ReplicatedStorage.Shared.Config.FeatureFlags
check(string.find(flags.Source, "COMPASS = true", 1, true) ~= nil, "on as shipped")
local source, replaced = string.gsub(flags.Source, "COMPASS = true", "COMPASS = false")
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
require(server.Services.BotDirector).testSetEnabled(false)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
local CompassUI = require(client.Controllers.CompassController)
local ada = Instance.new("Player")
ada.Name = "Ada"
ada.UserId = 2
ada.Parent = Players
task.wait(0.05)
Lifecycle.requestPlay(me, nil)
Lifecycle.requestPlay(ada, nil)
task.wait(0.5)
check(me:GetAttribute("State") == "ACTIVE" and me.Character, "in the match")
check(me.PlayerGui:FindFirstChild("Compass") == nil, "no compass screen")

local heard = 0
Remotes.Ping.FiredToClient:Connect(function()
	heard += 1
end)
Remotes.Ping.OnServerEvent:Fire(me, Vector3.new(0, 0, -90))
check(heard == 0, "the server ignores pings")
CompassUI.aimSpot = function()
	return Vector3.new(0, 0, -90)
end
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Z, UserInputType = Enum.UserInputType.Keyboard }, false)
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton3 }, false)
check(heard == 0 and not CompassUI.ping(), "and Z and the middle mouse button send none")
RunService:RenderFrame(1 / 60)
RunService.RenderStepped:Fire(1 / 60)
check(next(Telemetry.snapshot().errors) == nil, "nothing broke")

return { status = "PASS", checks = checks }
