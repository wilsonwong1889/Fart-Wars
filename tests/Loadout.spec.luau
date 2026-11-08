-- The loadout screen (LoadoutController), with one client:
--   * every way in reaches it (the home screen, the M menu, the locker's
--     tabs, the old "Abilities" page) and opening a locker page, BACK,
--     PLAY or the menu closing leave it
--   * the weapons in shop order: the hotbar key of each one owned, the
--     level or the shop for the rest; the picked one in the middle with
--     its stats and EQUIP, or the way to get it
--   * Q: a badge while an unlocked ability is new, a picker of the Q
--     abilities (locked ones with their level), equipping one
--   * the look slots: what's on, a picker of what's owned, on and off
--   * the emotes around E: the one E plays lit, picking another, empty
--     spots to the daily shop
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local Data = require(server.Services.DataService)
local Economy = require(server.Services.EconomyService)
local Shop = require(server.Services.ShopService)
local LoadoutService = require(server.Services.LoadoutService)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
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
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Controllers = game.StarterPlayer.StarterPlayerScripts.Client.Controllers
local Locker = require(Controllers.LockerController)
local Loadout = require(Controllers.LoadoutController)
local Home = require(Controllers.HomeController)
local gui = me.PlayerGui
local function click(button: GuiButton)
	button.Activated:Fire()
	task.wait(0.4) -- the answer, and past the rate limit
end
local function data(): any
	return assert(Data.get(me)).data
end
local function xpTo(level: number)
	local need = -data().XP
	for l = data().Level, level - 1 do
		need += ProgressionConfig.xpToNext(l)
	end
	while need > 0 do
		local step = math.min(need, ProgressionConfig.MAX_XP_PER_GRANT)
		Economy.testGrant(me, 0, step)
		need -= step
	end
	task.wait(0.1)
end
local function coins(n: number)
	while n > 0 do
		local step = math.min(n, ProgressionConfig.MAX_COINS_PER_GRANT)
		Economy.testGrant(me, step, 0)
		n -= step
	end
	task.wait(0.1)
end
check(Data.isLoaded(me), "Me's profile is in")
-- (Done with the practice yard already: PLAY goes straight to the teams.)
require(server.Services.PracticeService).testSetDue(me, false)
task.wait(0.2)

-- In and out.
click(Home.parts.pageButtons.Loadout)
local p = Loadout.parts
check(Loadout.isOpen and gui.Loadout.Enabled and not Locker.isOpen, "LOADOUT on the home screen opens it")
click(p.back)
check(not Loadout.isOpen and not gui.Loadout.Enabled, "BACK closes it")
Locker.open("Weapons")
click(Locker.parts.tabs.Loadout)
check(Loadout.isOpen and not Locker.isOpen and not gui.Locker.Enabled, "the locker's LOADOUT tab swaps to it")
Locker.open("Progression")
check(Locker.isOpen and not Loadout.isOpen, "and a locker page swaps back")
Locker.open("Abilities")
check(Loadout.isOpen and not Locker.isOpen, "the old Abilities page is the loadout now")
Locker.close()
check(not Loadout.isOpen, "closing the menu closes it")

-- The weapons.
Locker.open("Loadout")
local rows = p.rows
check(rows.GasBlaster.Key.Visible and rows.GasBlaster.Key.Number.Text == "1" and string.find(rows.GasBlaster.Sub.Text, "EQUIPPED", 1, true), "the Gas Blaster: key 1, equipped")
check(not rows.Spritzer.Key.Visible and rows.Spritzer.Lock.Visible and rows.Spritzer.Lock.Text == "🔒" and rows.Spritzer.Sub.Text == "Level 5", "the Spritzer: level 5 first")
check(Loadout.selected == "GasBlaster" and p.name.Text == "GAS BLASTER" and p.window.Preview:GetAttribute("Weapon") == "GasBlaster", "the equipped one in the middle, turning")
check(p.stats.Gas.Value.Text == "20% (head 25%)" and p.stats.Rate.Value.Text == "3.3/s" and p.description.Text == WeaponConfig.weapons.GasBlaster.description, "with its stats")
check(p.action.Text == "EQUIPPED" and p.action:GetAttribute("Enabled") == false and rows.GasBlaster.Border.Color == Color3.fromRGB(45, 155, 245), "EQUIPPED, and its row picked")
click(rows.Spritzer)
check(Loadout.selected == "Spritzer" and p.name.Text == "SPRITZER" and p.window.Preview:GetAttribute("Weapon") == "Spritzer", "picking a row shows that weapon")
check(p.action.Text == "🔒 LEVEL 5" and p.action:GetAttribute("Enabled") == false, "locked: the level it needs")
xpTo(5)
check(rows.Spritzer.Lock.Text == "🛒" and string.find(rows.Spritzer.Sub.Text, "In the shop", 1, true), "level 5: in the shop")
check(p.action.Text == "GET IT IN THE SHOP" and p.action:GetAttribute("Enabled") ~= false, "and the button says where")
click(p.action)
check(Locker.isOpen and Locker.tab == "Weapons" and Locker.section == "Weapons" and not Loadout.isOpen, "which goes to the shop's weapons")
Locker.close()
coins(WeaponConfig.weapons.Spritzer.price)
check(Shop.request(me, "buy", "weapon", "Spritzer").ok, "bought the Spritzer")
task.wait(0.4)
Locker.open("Loadout")
check(Loadout.selected == "GasBlaster", "opening again starts at the equipped one")
check(rows.Spritzer.Key.Visible and rows.Spritzer.Key.Number.Text == "2" and rows.Spritzer.Swatch.Visible, "the Spritzer: key 2 now")
click(rows.Spritzer)
check(p.action.Text == "EQUIP" and p.action:GetAttribute("Enabled") ~= false, "owned: EQUIP")
click(p.action)
check(data().EquippedWeapon == "Spritzer" and p.status.Text == "Equipped.", "EQUIP: equipped")
check(p.action.Text == "EQUIPPED" and string.find(rows.Spritzer.Sub.Text, "EQUIPPED", 1, true) and not string.find(rows.GasBlaster.Sub.Text, "EQUIPPED", 1, true), "and the rows follow")

-- Q.
check(p.ability.AbilityName.Text == "None yet", "no Q ability before level 10")
xpTo(10)
check(p.ability.Badge.Visible and p.ability.Badge.Count.Text == "1", "Recovery Burst unlocked: a badge on Q")
check(Home.parts.pageButtons.Loadout.Badge.Visible, "and on LOADOUT")
click(p.ability)
local options = p.pickerOptions
check(p.picker.Visible and Loadout.picking == "ability" and not p.pickerShop.Visible, "Q: the picker")
check(options.RecoveryBurst:GetAttribute("Enabled") ~= false and options.GasPulse:GetAttribute("Enabled") == false and options.GasPulse.ItemName.Text == "Gas Pulse" and options.GasPulse.Note.Text == "🔒 LEVEL 30" and not options.RecoveryBurst:FindFirstChild("Note"), "Recovery Burst ready, Gas Pulse locked (named, with the level)")
check(not p.ability.Badge.Visible and not Home.parts.pageButtons.Loadout.Badge.Visible, "seen: the badges go")
click(options.RecoveryBurst)
check(not p.picker.Visible and data().EquippedAbility == "RecoveryBurst", "picked: on Q")
check(string.find(p.ability.AbilityName.Text, "Recovery Burst", 1, true), "and shown")

-- The look slots.
check(p.slots.tracer.ItemName.Text == "Default" and p.slots.trail.ItemName.Text == "None" and p.slots.boom.ItemName.Text == "Default", "nothing on yet")
Data.update(me, function(d)
	table.insert(d.OwnedCosmetics, "OceanBreeze")
	table.insert(d.OwnedCosmetics, "LavaTrail")
	table.insert(d.OwnedCosmetics, "Beans")
end)
LoadoutService.push(me)
task.wait(0.1)
click(p.slots.tracer)
check(Loadout.picking == "tracer" and options.None.Border.Thickness == 4 and options.OceanBreeze and not options:FindFirstChild("GoldenGas"), "the tracer picker: nothing on, and what I own")
check(p.pickerShop.Visible, "with the way to the shop")
click(options.OceanBreeze)
check(data().EquippedCosmetic == "OceanBreeze" and p.slots.tracer.ItemName.Text == "Ocean Breeze" and p.slots.tracer.Look:FindFirstChild("Swatch"), "Ocean Breeze on")
click(p.slots.trail)
click(options.LavaTrail)
check(data().EquippedTrail == "LavaTrail" and p.slots.trail.ItemName.Text == "Lava Trail", "Lava Trail on")
click(p.slots.tracer)
check(options.OceanBreeze.Border.Thickness == 4, "the picker marks what's on")
click(options.None)
check(data().EquippedCosmetic == nil and p.slots.tracer.ItemName.Text == "Default", "and off again")
click(p.slots.boom)
check(#options:GetChildren() > 0 and options.None and not options:FindFirstChild("ConfettiBoom"), "no booms owned: only the plain one")
click(p.pickerShop)
check(Locker.isOpen and Locker.section == "Daily" and not Loadout.isOpen, "MORE IN THE SHOP: the daily part")

-- The emotes.
Locker.open("Loadout")
local ring = p.ring
check(ring.Toot and ring.Beans and ring.Toot.Border.Thickness == 4, "Toot and Beans around E, Toot lit")
check(p.centerEmoji.Text == "💨" and string.find(p.emoteName.Text, "Toot", 1, true), "E plays Toot")
local spots = 0
for _, child in ring:GetChildren() do
	if child.Name == "Spot" then
		spots += 1
	end
end
check(spots == 6, `the rest are empty spots ({spots})`)
click(ring.Beans)
check(data().EquippedEmote == "Beans" and p.centerEmoji.Text == "🥫" and ring.Beans.Border.Thickness == 4, "Beans for E")
click(ring:FindFirstChild("Spot"))
check(Locker.isOpen and Locker.section == "Daily" and not Loadout.isOpen, "an empty spot: the daily shop")
Locker.close()

-- The M menu, and PLAY.
Home.play()
Home.pick(nil)
task.wait(0.6)
check(me:GetAttribute("State") == "ACTIVE", "in a match")
Home.setMenu(true)
click(Home.parts.menu:FindFirstChild("Loadout", true))
check(Loadout.isOpen, "the M menu's LOADOUT")
Home.setMenu(false)
check(not Loadout.isOpen, "closing the menu closes it")

return { status = "PASS", checks = checks }
