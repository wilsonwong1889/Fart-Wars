-- The practice yard switched off (FeatureFlags.PRACTICE = false), with the
-- real server and one client on a new, saving profile:
--   * nothing is due, and the first PLAY goes straight to the team screen
--   * no PRACTICE tile on the home screen, no row in Settings
--   * the server refuses to open a yard, whatever the client asks, and
--     says so straight back
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

-- Flip the flag before anything reads it.
local flags = ReplicatedStorage.Shared.Config.FeatureFlags
local source, replaced = string.gsub(flags.Source, "PRACTICE = true", "PRACTICE = false")
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
local Data = require(server.Services.DataService)
local Practice = require(server.Services.PracticeService)
local Telemetry = require(server.Telemetry)
local saved: { [string]: any } = {}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		local result = transform(saved[key])
		if result ~= nil then
			saved[key] = result
		end
		return result
	end,
})

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
task.wait(0.5)
local Home = require(client.Controllers.HomeController)
local Locker = require(client.Controllers.LockerController)
local home = Home.parts

check(Data.isLoaded(me) and not assert(Data.get(me)).temporary, "a new profile, saving")
check(me:GetAttribute("PracticeDue") == false and not Practice.due(me), "with the yard off, nothing is due")
check(home.tiles.Practice and not home.tiles.Practice.Visible, "no PRACTICE tile")
Locker.open("Settings")
check(Locker.parts.content.Settings:FindFirstChild("PracticeRow") == nil, "no PRACTICE YARD in Settings")
Locker.close()

local refused = {}
ReplicatedStorage.Remotes.Practice.FiredToClient:Connect(function(player, kind, why)
	if player == me and kind == "refused" then
		table.insert(refused, why)
	end
end)
ReplicatedStorage.Remotes.Practice.OnServerEvent:Fire(me, "start")
task.wait(0.2)
check(#refused == 1 and refused[1] == "off", "the client is told at once, so a PLAY waiting on it goes on")
check(me:GetAttribute("State") == "MENU_SPECTATOR" and Practice.get(me) == nil and workspace:FindFirstChild("PracticeYards") == nil, "the server opens no yard")
check(((Telemetry.snapshot().rejects.Practice or {}) :: any).off == 1, "and logs the refusal")
local ok, why = Practice.begin(me)
check(not ok and why == "off", "begin says why: " .. tostring(why))

local play = home.play :: GuiButton
play.Activated:Fire()
task.wait(0.1)
check(home.teamSelect.Enabled and me:GetAttribute("State") == "MENU_SPECTATOR", "the first PLAY goes straight to the team screen")

return { status = "PASS", checks = checks }
