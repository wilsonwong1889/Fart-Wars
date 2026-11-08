-- The windows over the home screen and the match, with one client:
--   * a click on a window never reaches what's under it: its panel, or
--     the full-screen dim behind it, takes the click (Active), and no
--     full-screen dim lets one through (a click on the free spin's note
--     used to press PLAY under it)
--   * PLAY closes the daily reward and the free spin; a spin still going
--     lands out of sight, and the wallet catches up
local Players = game:GetService("Players")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
-- No bots: PLAY picks a team freely (bots count toward the lock).
require(server.Services.BotDirector).testSetEnabled(false)
local Data = require(server.Services.DataService)
local RewardsService = require(server.Services.RewardsService)
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
check(Data.isLoaded(me), "the profile loaded")
local Controllers = client.Controllers
local home = require(Controllers.HomeController).parts
local Locker = require(Controllers.LockerController)
local Loadout = require(Controllers.LoadoutController)
local Rewards = require(Controllers.RewardsController)
local PlayersScreen = require(Controllers.PlayersController)
local Season = require(Controllers.SeasonController)
local Prestige = require(Controllers.PrestigeController)

local function click(button: Instance)
	(button :: GuiButton).Activated:Fire()
	task.wait(0.05)
end

-- Every window, and what takes its clicks.
local windows = {
	{ "TeamSelect", home.teamSelect },
	{ "ComingSoon", home.comingSoon },
	{ "GameMenu", home.menu },
	{ "Locker", Locker.parts.screen },
	{ "Loadout", Loadout.parts.screen },
	{ "Players", PlayersScreen.parts.screen },
	{ "DailyRewards", Rewards.parts.daily },
	{ "SpinWheel", Rewards.parts.wheel },
	{ "Season", Season.parts.screen },
	{ "Prestige", Prestige.parts.screen },
}
local FULL = UDim2.new(1, 0, 1, 0)
for _, entry in windows do
	local name, screen = entry[1], entry[2]
	check(screen ~= nil and screen:IsA("ScreenGui"), `{name} is built`)
	local takes = false
	for _, child in screen:GetChildren() do
		if child:IsA("GuiObject") then
			if child.Size == FULL then
				check(child.Active, `{name}: its {child.Name} covers the screen, so it takes the clicks`)
				takes = true
			elseif (child.Name == "Panel" or child.Name == "Card") and child.Active then
				takes = true
			end
		end
	end
	check(takes, `{name}: a click on it never reaches what's under it`)
end

-- PLAY closes the daily reward and the free spin, even mid-spin.
if Rewards.parts.daily.Enabled then
	click(Rewards.parts.daily:FindFirstChild("Close", true))
end
Data.update(me, function(d)
	d.Spins = 1
end)
RewardsService.publish(me)
Rewards.openDaily()
Rewards.openSpin()
check(Rewards.parts.daily.Enabled and Rewards.parts.wheel.Enabled, "the daily reward and the free spin, open at home")
task.wait(0.3) -- past the rate limit
task.spawn(Rewards.spin)
task.wait(1)
check(Rewards.busy and assert(Data.get(me)).data.Spins == 0, "a spin going, paid for")
click(home.play)
click(home.teamButtons.Stinkers)
task.wait(0.6)
check(me:GetAttribute("State") == "ACTIVE", "in the match")
check(not Rewards.parts.daily.Enabled and not Rewards.parts.wheel.Enabled, "PLAY closed both")
while Rewards.busy do
	task.wait(0.1)
end
local data = assert(Data.get(me)).data
check(data.Spins == 0, "the spin was spent")
check(me:GetAttribute("Coins") == data.Coins and me:GetAttribute("LifetimeXP") == data.LifetimeXP, "it landed out of sight, and the wallet caught up")
check(not Rewards.parts.wheel.Enabled, "without the window coming back")

return { status = "PASS", checks = checks }
