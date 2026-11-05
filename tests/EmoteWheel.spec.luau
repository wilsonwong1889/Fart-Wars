-- E (EmoteWheelController, LoadoutService.emote), with one client:
--   * off the field E does nothing
--   * a tap plays the emote equipped in the Loadout
--   * held, a wheel of the emotes owned, in the Loadout's order, with the
--     mouse free; the mouse's direction picks one and letting go plays it,
--     once, without changing what's equipped
--   * in the middle, or on an empty spot, letting go plays nothing
--   * the menu closes it; it doesn't open over a screen
--   * the server plays only an emote the player owns
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
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
require(server.Services.BotDirector).testSetEnabled(false)
local Data = require(server.Services.DataService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local LoadoutService = require(server.Services.LoadoutService)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HttpService = game:GetService("HttpService")

local saved: { [string]: any } = {}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
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
local Wheel = require(client.Controllers.EmoteWheelController)
local Locker = require(client.Controllers.LockerController)
local MouseLock = require(client.MouseLock)
local gui = me.PlayerGui
local p = Wheel.parts

local played = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if event.kind == "emote" and player == me then
		table.insert(played, event.emote)
	end
end)
local function key(code: Enum.KeyCode, down: boolean)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	if down then
		UserInputService.InputBegan:Fire(input, false)
	else
		UserInputService.InputEnded:Fire(input, false)
	end
end
local E = Enum.KeyCode.E
local function hold()
	key(E, true)
	task.wait(Wheel.HOLD_SECONDS + 0.05)
end
local function letGo()
	key(E, false)
	task.wait(0.05)
end
local function pastTheLimit()
	task.wait(3.1)
end
-- Puts the mouse `offset` from the middle of the screen.
local function mouse(offset: Vector2)
	Wheel.mouse = function()
		return offset
	end
	Wheel.update()
end

-- Off the field.
hold()
check(not Wheel.isOpen and not gui.EmoteWheel.Enabled, "on the home screen: no wheel")
letGo()
check(#played == 0, "and no emote")

Data.update(me, function(d)
	table.insert(d.OwnedCosmetics, "Beans")
	table.insert(d.OwnedCosmetics, "GoodGame")
end)
LoadoutService.push(me)
Lifecycle.requestPlay(me, nil)
task.wait(0.3)

-- A tap.
key(E, true)
key(E, false)
task.wait(0.05)
check(#played == 1 and played[1] == "Toot", "a tap: the equipped emote")
task.wait(Wheel.HOLD_SECONDS + 0.05)
check(not Wheel.isOpen, "and no wheel after it")

-- Held.
pastTheLimit()
hold()
check(Wheel.isOpen and gui.EmoteWheel.Enabled, "held: the wheel")
check(MouseLock.holds("EmoteWheel"), "the mouse free")
check(table.concat(Wheel.emotes, ",") == "Toot,Beans,GoodGame", "the emotes owned: " .. table.concat(Wheel.emotes, ","))
check(p.spots[1].Emoji.Text == "💨" and p.spots[2].Emoji.Text == "🥫" and p.spots[3].Emoji.Text == "🤝", "each with its face")
check(p.spots[4].Emoji.Text == "", "the rest empty")
check(p.name.Text == "Let go here to cancel", "nothing picked yet")
check(Wheel.pick(Vector2.new(0, -150)) == "Toot", "up: the first")
check(Wheel.pick(Vector2.new(106, -106)) == "Beans", "up and right: the second")
check(Wheel.pick(Vector2.new(150, 0)) == "GoodGame", "right: the third")
check(Wheel.pick(Vector2.new(0, 150)) == nil, "down: an empty spot")
check(Wheel.pick(Vector2.new(20, -20)) == nil, "near the middle: nothing")
mouse(Vector2.new(120, -120))
check(Wheel.picked == "Beans" and p.name.Text == "Beans!", "pointing at one: its name")
check(p.spots[2].Border.Thickness == 5 and p.spots[1].Border.Thickness == 3, "lit")
letGo()
check(#played == 2 and played[2] == "Beans", "letting go plays it")
check(not Wheel.isOpen and not gui.EmoteWheel.Enabled and not MouseLock.holds("EmoteWheel"), "the wheel gone, the mouse back")
check(me:GetAttribute("Emote") == "Toot", "what's equipped hasn't changed")

-- Nothing picked.
pastTheLimit()
hold()
mouse(Vector2.zero)
letGo()
check(#played == 2, "let go in the middle: nothing")
hold()
mouse(Vector2.new(0, 150))
letGo()
check(#played == 2, "on an empty spot: nothing")

-- Other screens.
hold()
key(Enum.KeyCode.M, true)
key(Enum.KeyCode.M, false)
check(not Wheel.isOpen, "the menu closes it")
letGo()
check(#played == 2, "and letting go then plays nothing")
key(Enum.KeyCode.M, true)
key(Enum.KeyCode.M, false)
Locker.open("Settings")
hold()
check(not Wheel.isOpen, "no wheel over an open screen")
letGo()
Locker.close()

-- The server decides.
local before = #played
pastTheLimit()
check(not LoadoutService.emote(me, "SilentButDeadly"), "an emote not owned: refused")
pastTheLimit()
check(not LoadoutService.emote(me, "GoldenGas"), "a tracer isn't an emote")
pastTheLimit()
check(not LoadoutService.emote(me, 12), "nor is a number")
check(#played == before, "none of them played")
pastTheLimit()
check(LoadoutService.emote(me, "GoodGame") and played[before + 1] == "GoodGame", "one owned: played")

return { status = "PASS", checks = checks }
