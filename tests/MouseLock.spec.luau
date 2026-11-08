-- Freeing the mouse from the crosshair (MouseLock), with one client:
--   * reasons: two at once keep it free until both let go, clearing one
--     keeps it free, and Changed fires only when free/locked really changes
--   * Left Alt frees it and locks it again (MouseUnlockPressed too), and
--     does nothing while typing in chat or a text box
--   * every screen with buttons frees it under its own name while it's open
--     and lets go however it closes: the home screen, Coming Soon, the M
--     menu, the locker (from the menu, the top right buttons, the menu
--     closing, PLAY or spectating), Players, Daily Rewards, the free spin,
--     Season and Prestige; in a match with nothing open it's locked
--   * Settings: the 3RD PERSON MOUSE LOCK toggle flips Settings.lockMouse
--   * the controls card lists ALT
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

local client = game.StarterPlayer.StarterPlayerScripts.Client
local MouseLock = require(client.MouseLock)

-- Reasons, on their own.
local fired: { boolean } = {}
MouseLock.Changed:Connect(function(free)
	table.insert(fired, free)
end)
check(not MouseLock.isFree() and #fired == 0, "locked to start with")
MouseLock.setFree("a", true)
check(MouseLock.isFree() and MouseLock.holds("a") and #fired == 1 and fired[1] == true, "one reason frees it, once")
MouseLock.setFree("b", true)
check(MouseLock.holds("b") and #fired == 1, "a second reason: no change to announce")
MouseLock.setFree("a", false)
check(MouseLock.isFree() and not MouseLock.holds("a") and MouseLock.holds("b") and #fired == 1, "clearing one keeps it free")
MouseLock.setFree("a", false)
check(#fired == 1, "clearing it again changes nothing")
MouseLock.setFree("b", false)
check(not MouseLock.isFree() and #fired == 2 and fired[2] == false, "the last one: locked, announced once")
MouseLock.toggleKey()
check(MouseLock.holds("key") and MouseLock.isFree() and #fired == 3, "the key frees it")
MouseLock.toggleKey()
check(not MouseLock.holds("key") and not MouseLock.isFree() and #fired == 4, "and locks it again")
MouseLock.setFree("a", true)
MouseLock.reset()
check(not MouseLock.isFree() and not MouseLock.holds("a"), "reset: locked, nothing asking")

-- The game.
Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
-- No bots: these checks pick a team freely (bots count toward the lock).
require(server.Services.BotDirector).testSetEnabled(false)

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(client.ClientBootstrap)
task.wait(0.5)
local Controllers = client.Controllers
local Home = require(Controllers.HomeController)
local Locker = require(Controllers.LockerController)
local Loadout = require(Controllers.LoadoutController)
local Rewards = require(Controllers.RewardsController)
local PlayersScreen = require(Controllers.PlayersController)
local Season = require(Controllers.SeasonController)
local Prestige = require(Controllers.PrestigeController)
local MenuBar = require(Controllers.MenuBarController)
local HUD = require(Controllers.HUDController)
local Input = require(Controllers.InputController)
local Settings = require(client.Settings)
local home = Home.parts

local function click(button: Instance)
	(button :: GuiButton).Activated:Fire()
	task.wait(0.05)
end
local function press(code: Enum.KeyCode, typing: boolean?)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	UserInputService.InputBegan:Fire(input, typing == true)
	UserInputService.InputEnded:Fire(input, typing == true)
	task.wait(0.05)
end

-- Each screen's reason, and whether it's showing. A reason held means
-- that screen is up, and the other way round, at every check below.
local screens = {
	HomeScreen = function()
		return home.home.Enabled
	end,
	ComingSoon = function()
		return home.comingSoon.Enabled
	end,
	GameMenu = function()
		return home.menu.Enabled
	end,
	Locker = function()
		return Locker.parts.screen.Enabled
	end,
	Loadout = function()
		return Loadout.parts.screen.Enabled
	end,
	Players = function()
		return PlayersScreen.parts.screen.Enabled
	end,
	DailyRewards = function()
		return Rewards.parts.daily.Enabled
	end,
	SpinWheel = function()
		return Rewards.parts.wheel.Enabled
	end,
	Season = function()
		return Season.parts.screen.Enabled
	end,
	Prestige = function()
		return Prestige.parts.screen.Enabled
	end,
}
local function matches(message: string)
	for reason, showing in screens do
		check(MouseLock.holds(reason) == showing(), `{message}: {reason} frees the mouse exactly while it shows`)
	end
end
-- Only these screens are open (and so free the mouse).
local function only(message: string, open: { string })
	matches(message)
	for reason in screens do
		check(MouseLock.holds(reason) == (table.find(open, reason) ~= nil), `{message}: {reason}`)
	end
	check(MouseLock.isFree() == (#open > 0 or MouseLock.holds("key")), `{message}: free or locked`)
end

-- The home screen frees it; so do the screens on top of it.
if Rewards.parts.daily.Enabled then
	only("a claim waiting: the home screen and Daily Rewards", { "HomeScreen", "DailyRewards" })
	click(Rewards.parts.daily:FindFirstChild("Close", true))
end
only("the home screen", { "HomeScreen" })
-- TOP's Coming Soon card stands in for a section still to come (with the
-- leaderboard switched off; Leaderboard.spec checks its own screen).
require(Controllers.LeaderboardController).testEnable(false)
click(home.home:FindFirstChild("Leaderboard", true))
only("Coming Soon from home", { "HomeScreen", "ComingSoon" })
click(home.comingSoon:FindFirstChild("Close", true))
only("Coming Soon closed", { "HomeScreen" })
click(home.home:FindFirstChild("Players", true))
only("Players from home", { "HomeScreen", "Players" })
click(PlayersScreen.parts.screen:FindFirstChild("Close", true))
only("Players closed", { "HomeScreen" })
Rewards.openDaily()
only("Daily Rewards from home", { "HomeScreen", "DailyRewards" })

-- PLAY: the screens go, and so does the free mouse.
click(home.play)
click(home.teamButtons.Stinkers)
task.wait(0.6)
check(me:GetAttribute("State") == "ACTIVE", "in the match")
only("in a match, nothing open: locked", {})

-- Left Alt.
local unlocks = 0
Input.MouseUnlockPressed:Connect(function()
	unlocks += 1
end)
check(UIConfig.keys.unlockMouse == Enum.KeyCode.LeftAlt, "Left Alt is the unlock key")
press(Enum.KeyCode.LeftAlt)
check(MouseLock.isFree() and MouseLock.holds("key") and unlocks == 1, "Alt frees the mouse")
press(Enum.KeyCode.LeftAlt)
check(not MouseLock.isFree() and not MouseLock.holds("key") and unlocks == 2, "Alt again locks it")
press(Enum.KeyCode.LeftAlt, true)
check(not MouseLock.isFree() and unlocks == 2, "Alt while typing in chat does nothing")
press(Enum.KeyCode.LeftAlt)
press(Enum.KeyCode.M)
check(MouseLock.holds("key") and MouseLock.holds("GameMenu"), "the key and the menu, both")
press(Enum.KeyCode.M)
check(MouseLock.isFree() and MouseLock.holds("key"), "the menu closing leaves the key's free mouse alone")
press(Enum.KeyCode.LeftAlt)
only("Alt locks it again", {})

-- The M menu and the screens it opens.
press(Enum.KeyCode.M)
only("M: the menu", { "GameMenu" })
click(home.menu:FindFirstChild("Weapons", true))
only("the locker from the menu", { "GameMenu", "Locker" })
click(Locker.parts.screen:FindFirstChild("Close", true))
only("the locker closed: the menu still frees it", { "GameMenu" })
click(home.menu:FindFirstChild("Settings", true))
press(Enum.KeyCode.M)
only("M with the locker open closes both", {})
press(Enum.KeyCode.M)
click(home.menu:FindFirstChild("Leaderboard", true))
only("Coming Soon from the menu", { "GameMenu", "ComingSoon" })
click(home.comingSoon:FindFirstChild("Close", true))
only("Coming Soon's OK", { "GameMenu" })
click(home.menu:FindFirstChild("Leaderboard", true))
click(home.resume)
only("RESUME closes the menu and Coming Soon", {})
press(Enum.KeyCode.M)
click(home.menu:FindFirstChild("Players", true))
only("Players from the menu", { "GameMenu", "Players" })
click(PlayersScreen.parts.screen:FindFirstChild("Close", true))
click(home.menu:FindFirstChild("Rewards", true))
only("Daily Rewards from the menu", { "GameMenu", "DailyRewards" })
click(Rewards.parts.daily:FindFirstChild("Close", true))
click(home.resume)
only("all closed", {})

-- The top right buttons.
check(MenuBar.parts.corner.Visible, "the top right buttons show in a match")
click(MenuBar.parts.buttons.Settings)
only("SETTINGS: the locker", { "Locker" })
local list = Locker.parts.content.Settings
local toggle = list.LockMouseRow.LockMouse
check(Settings.lockMouse and toggle.Text == "3RD PERSON MOUSE LOCK: ON", "the mouse lock setting, on")
check(string.find(list.LockMouseRow.Note.Text, "Alt frees the mouse", 1, true), "its note says Alt frees the mouse")
click(toggle)
toggle = Locker.parts.content.Settings.LockMouseRow.LockMouse
check(not Settings.lockMouse and Settings.chosen.lockMouse and toggle.Text == "3RD PERSON MOUSE LOCK: OFF", "off, and chosen")
click(toggle)
toggle = Locker.parts.content.Settings.LockMouseRow.LockMouse
check(Settings.lockMouse and toggle.Text == "3RD PERSON MOUSE LOCK: ON", "and on again")
only("the setting doesn't touch the screens' reasons", { "Locker" })
click(Locker.parts.screen:FindFirstChild("Close", true))
only("locker closed", {})
click(MenuBar.parts.buttons.Loadout)
only("LOADOUT: its own screen", { "Loadout" })
click(Loadout.parts.back)
only("its BACK", {})
click(MenuBar.parts.spin)
only("the free spin", { "SpinWheel" })
click(Rewards.parts.wheel:FindFirstChild("Close", true))
click(MenuBar.parts.daily)
only("the daily reward", { "DailyRewards" })
click(Rewards.parts.daily:FindFirstChild("Close", true))
Season.open()
only("Season", { "Season" })
click(Season.parts.screen:FindFirstChild("Close", true))
Prestige.open()
only("Prestige", { "Prestige" })
click(Prestige.parts.screen:FindFirstChild("Cancel", true))
only("Prestige's CANCEL", {})
-- Prestige from the locker's Progression tab: the locker hands over.
Locker.open("Progression")
Locker.close()
Prestige.open()
only("the locker hands over to Prestige", { "Prestige" })
Prestige.close()

-- Two screens at once: closing one keeps the other's.
click(MenuBar.parts.buttons.Weapons)
click(MenuBar.parts.spin)
only("the locker and the spin", { "Locker", "SpinWheel" })
click(Rewards.parts.wheel:FindFirstChild("Close", true))
only("the spin closed, the locker still up", { "Locker" })

-- Leaving the match closes what was open, and the reasons go with it.
press(Enum.KeyCode.M)
only("the menu over the locker", { "GameMenu", "Locker" })
click(home.menu:FindFirstChild("Spectate", true))
task.wait(0.3)
check(me:GetAttribute("State") ~= "ACTIVE", "SPECTATE leaves the match")
only("spectating: just the home screen", { "HomeScreen" })
click(home.play)
click(home.teamButtons.Stinkers)
task.wait(0.6)
only("back in the match", {})
press(Enum.KeyCode.M)
click(home.menu:FindFirstChild("Leaderboard", true))
click(MenuBar.parts.buttons.Loadout)
only("menu, Coming Soon and the loadout", { "GameMenu", "ComingSoon", "Loadout" })
-- Moved out by the server (not a button): the menu closes itself.
ReplicatedStorage.Remotes.RequestSpectate.OnServerEvent:Fire(me)
task.wait(0.3)
check(me:GetAttribute("State") ~= "ACTIVE", "out of the match")
only("the server moving me out clears every screen's reason", { "HomeScreen" })

-- The controls card.
local listed = false
for _, row in UIConfig.controls do
	listed = listed or (row[1] == "ALT" and string.find(string.lower(row[2]), "mouse") ~= nil)
end
check(listed, "the controls list has ALT for the mouse")
local onCard = false
for _, label in HUD.parts.controls:GetChildren() do
	onCard = onCard or (label:IsA("TextLabel") and string.sub(label.Text, 1, 3) == "ALT")
end
check(onCard, "and the controls card shows it")

return { status = "PASS", checks = checks }
