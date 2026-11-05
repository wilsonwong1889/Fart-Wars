-- The daily shop (DailyShopConfig, ShopService.buyCosmetic and the shop's
-- Daily part), with one client:
--   * the day's five come from the date alone: the same every time, one
--     legendary or epic, one epic or rare, one rare and two commons, all
--     different, dearest first; it changes day to day and everything comes
--     up within a few weeks; the countdown to the next day
--   * every daily cosmetic is a real cosmetic sold only here, and only a
--     look (a tracer, trail, boom or emote)
--   * buying: only today's, only with the coins, once; saved with the
--     coins taken, or neither
--   * the shop: one page with a rail to each part; the Daily part's tiles
--     by rarity, price or OWNED, "Buy it?" first, the countdown ticking, a
--     new shop at midnight; redrawn where it was scrolled to
--   * a tile's window previews it on the player's gun, bought or not, and
--     says why it can't be bought yet
--   * the lobby: the daily card with today's unowned cosmetics and the time
--     left, a new day at midnight, and the SHOP badge counting them
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
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
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local DailyShopConfig = require(ReplicatedStorage.Shared.Config.DailyShopConfig)

local saved: { [string]: any } = {}
local failNext = 0
local function copy(value: any): any
	return if value == nil then nil else HttpService:JSONDecode(HttpService:JSONEncode(value))
end
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		if failNext > 0 then
			failNext -= 1
			error("503: DataStore request failed (test outage)")
		end
		local result = transform(copy(saved[key]))
		if result ~= nil then
			saved[key] = copy(result)
		end
		return result
	end,
})

-- The rotation.
local DAY = 20000
local function ids(items: { DailyShopConfig.Item }): string
	local out = {}
	for _, item in items do
		table.insert(out, item.id)
	end
	return table.concat(out, ",")
end
check(ids(DailyShopConfig.forDay(DAY)) == ids(DailyShopConfig.forDay(DAY)), "the same day, the same shop: " .. ids(DailyShopConfig.forDay(DAY)))
local seen, changes = {}, 0
for day = DAY, DAY + 59 do
	local items = DailyShopConfig.forDay(day)
	local counts = { common = 0, rare = 0, epic = 0, legendary = 0 }
	local unique = {}
	for i, item in items do
		counts[item.rarity] += 1
		unique[item.id] = true
		seen[item.id] = true
		check(i == 1 or items[i - 1].price >= item.price, `day {day}: dearest first`)
	end
	local distinct = 0
	for _ in unique do
		distinct += 1
	end
	check(#items == DailyShopConfig.SLOTS and distinct == #items, `day {day}: five different items`)
	check(counts.common == 2 and counts.rare >= 1 and counts.legendary <= 1 and counts.legendary + counts.epic >= 1, `day {day}: by rarity: {ids(items)}`)
	if ids(items) ~= ids(DailyShopConfig.forDay(day - 1)) then
		changes += 1
	end
end
check(changes >= 50, `it changes from day to day ({changes} of 60)`)
for _, item in DailyShopConfig.pool do
	check(seen[item.id], `{item.id} comes up within 60 days`)
end
check(DailyShopConfig.day(DAY * 86400 + 86399) == DAY and DailyShopConfig.day((DAY + 1) * 86400) == DAY + 1, "a day runs midnight to midnight, UTC")
check(DailyShopConfig.secondsLeft(DAY * 86400) == 86400 and DailyShopConfig.secondsLeft(DAY * 86400 + 86399) == 1, "the seconds to the next")
check(DailyShopConfig.countdown(54526) == "15:08:46" and DailyShopConfig.countdown(526) == "8:46" and DailyShopConfig.countdown(-3) == "0:00", "the countdown")

-- Only looks, and only here.
local inPool = {}
for _, item in DailyShopConfig.pool do
	local cosmetic = ProgressionConfig.cosmetics[item.id]
	inPool[item.id] = true
	check(cosmetic and cosmetic.source == "Daily shop" and table.find(ProgressionConfig.cosmeticOrder, item.id), `{item.id}: a cosmetic from the daily shop`)
	check(table.find({ "tracer", "trail", "boom", "emote" }, cosmetic.kind) and DailyShopConfig.rarities[item.rarity] and item.price > 0, `{item.id}: a look with a price`)
end
for id, cosmetic in ProgressionConfig.cosmetics do
	check(cosmetic.source ~= "Daily shop" or inPool[id], `{id} is in the rotation`)
end

-- The client.
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
local Home = require(Controllers.HomeController)
local UI = require(game.StarterPlayer.StarterPlayerScripts.Client.UI)
local function click(button: GuiButton)
	button.Activated:Fire()
	task.wait(0.05)
end
local function data(): any
	return assert(Data.get(me)).data
end
local function request(action: any, kind: any, id: any): any
	task.wait(0.3) -- past the rate limit
	return Shop.request(me, action, kind, id)
end
local function coins(n: number)
	while n > 0 do
		local step = math.min(n, ProgressionConfig.MAX_COINS_PER_GRANT)
		Economy.testGrant(me, step, 0)
		n -= step
	end
end
check(Data.isLoaded(me), "Me's profile is in")
task.wait(0.1)

-- Buying, by the server's clock.
local now = DAY * 86400 + 3600
Shop.now = function()
	return now
end
Locker.now = Shop.now
local today = DailyShopConfig.today(now)
local dearest, cheapest = today[1], today[#today]
local notToday
for _, item in DailyShopConfig.pool do
	if not DailyShopConfig.onSale(item.id, now) then
		notToday = item
		break
	end
end
check(request("buy", "cosmetic", notToday.id).reason == "unknown", "not in today's shop: not for sale")
check(request("buy", "cosmetic", "StarterSwirl").reason == "unknown", "the Starter Pack's tracer isn't sold for coins")
check(request("buy", "cosmetic", "Toot").reason == "unknown", "nor is anything else")
check(request("buy", "cosmetic", cheapest.id).reason == "coins", "too few coins: refused")
coins(cheapest.price)
local answer = request("buy", "cosmetic", cheapest.id)
check(answer.ok and answer.reason == "bought", "with the coins: bought")
check(data().Coins == 0 and table.find(data().OwnedCosmetics, cheapest.id), "the coins for the cosmetic")
check(table.find(saved.player_1.OwnedCosmetics, cheapest.id) and saved.player_1.Coins == 0, "saved before the answer")
check(request("buy", "cosmetic", cheapest.id).reason == "owned", "twice: refused")
local other = today[#today - 1]
coins(other.price)
failNext = 3
answer = request("buy", "cosmetic", other.id)
check(not answer.ok and answer.reason == "saveFailed", "a save that fails: no purchase")
check(data().Coins == other.price and not table.find(data().OwnedCosmetics, other.id), "coins back, no cosmetic")
check(not table.find(saved.player_1.OwnedCosmetics, other.id), "nothing half-saved")

-- The shop page.
Locker.open("Weapons", "Daily")
task.wait(0.1)
local p = Locker.parts
check(p.rail.Visible and Locker.section == "Daily" and p.railButtons.Daily.Border.Thickness == 4, "the rail lights the daily part")
check(p.shop.CanvasPosition.Y > 0, "scrolled down to it")
for i, item in today do
	local tile = Locker.card(item.id)
	local rarity = DailyShopConfig.rarities[item.rarity]
	check(tile and tile.LayoutOrder == i and string.find(tile.Kind.Text, rarity.label, 1, true), `{item.id}: a {rarity.label} tile`)
	check(tile.ItemName.Text == ProgressionConfig.cosmetics[item.id].name and tile.Window:FindFirstChild("Swatch"), `{item.id}: its name and its look`)
end
check(Locker.card(cheapest.id).Action.Text == "OWNED" and Locker.card(cheapest.id).Action:GetAttribute("Enabled") == false, "the one bought: OWNED")
check(Locker.card(other.id).Action:GetAttribute("Enabled") ~= false, "one I can afford: ready")
check(Locker.card(dearest.id).Action:GetAttribute("Enabled") == false, "the dearest, too dear for now: greyed")
local dearestName = string.upper(ProgressionConfig.cosmetics[dearest.id].name)
click(Locker.card(dearest.id).Window)
check(p.confirm.Visible and p.confirmTitle.Text == dearestName, "its window previews it anyway")
check(p.confirmPreview:FindFirstChild("Preview") and p.confirmPreview:FindFirstChild("Swatch", true), "on the player's gun")
check(p.confirmLeft.Text == `{UI.commas(dearest.price - data().Coins)} more coins and it's yours.`, "saying what's missing: " .. p.confirmLeft.Text)
check(p.confirmYes:GetAttribute("Enabled") == false and p.confirmNo.Label.Text == "CLOSE", "YES grey, NO says CLOSE")
click(p.confirmYes)
check(p.confirm.Visible and not table.find(data().OwnedCosmetics, dearest.id), "YES does nothing")
click(p.confirmNo)
check(not p.confirm.Visible, "CLOSE closes it")
click(Locker.card(cheapest.id).Window)
check(p.confirmLeft.Text == "You own this one: equip it in your Loadout." and p.confirmYes:GetAttribute("Enabled") == false, "one already owned: it says so")
click(p.confirmNo)
coins(dearest.price - data().Coins)
task.wait(0.1)
check(Locker.buyable() == DailyShopConfig.SLOTS - 1, "the SHOP badge: today's I don't own and can pay for")
check(Home.parts.pageButtons.Weapons.Badge.Count.Text == tostring(DailyShopConfig.SLOTS - 1), "on the home screen")
local buy = Locker.card(dearest.id).Action
check(buy.Text == `💰 {UI.commas(dearest.price)}` and buy:GetAttribute("Enabled") ~= false, "with the coins: its price, ready")
check(p.dailyTimer.Text == "⏳ Refreshes in 23:00:00", "the countdown: " .. p.dailyTimer.Text)
now += 1
Locker.tickDaily()
check(p.dailyTimer.Text == "⏳ Refreshes in 22:59:59", "ticking")
click(buy)
check(p.confirm.Visible and p.confirmKind == "cosmetic" and p.confirmPrice.Text == `💰 {UI.commas(dearest.price)}`, "BUY asks first")
check(p.confirmTitle.Text == `BUY {dearestName}?` and p.confirmPreview:FindFirstChild("Swatch", true), "showing what it is")
check(p.confirmYes:GetAttribute("Enabled") ~= false and p.confirmNo.Label.Text == "NO", "YES ready, NO back to NO")
check(p.confirmLeft.Text == "You'll have 0 coins left.", "and what's left")
click(p.confirmYes)
task.wait(0.5)
check(p.status.Text == "Bought! It's yours." and table.find(data().OwnedCosmetics, dearest.id), "YES: bought")
check(Locker.card(dearest.id).Action.Text == "OWNED", "and the tile says so")
check(Locker.section == "Daily" and p.shop.CanvasPosition.Y > 0, "still at the daily part after the redraw")

-- Midnight.
local badgesChanged = 0
Locker.BadgesChanged:Connect(function()
	badgesChanged += 1
end)
now = (DAY + 1) * 86400 + 2
Locker.tickDaily()
check(badgesChanged > 0, "a new day: the badges count again")
local tomorrow = DailyShopConfig.forDay(DAY + 1)
for _, item in tomorrow do
	check(Locker.card(item.id), `a new day: {item.id}`)
end
check(p.dailyTimer.Text == "⏳ Refreshes in 23:59:58", "counting down again")
Home.parts.offerStart = 1
Home.tickOffers()
local dailyCard = Home.parts.offerRow.DailyShop
local shown = 0
for _, item in tomorrow do
	local owned = ProgressionConfig.ownsCosmetic(data().OwnedCosmetics, item.id)
	if not owned and shown < 3 then
		shown += 1
		check(dailyCard.Items:FindFirstChild(item.id), `the lobby's card: {item.id}`)
	else
		check(not dailyCard.Items:FindFirstChild(item.id), `and not {item.id}`)
	end
end
check(dailyCard.Timer.Text == "23:59:58", "with the time left: " .. dailyCard.Timer.Text)
now += 1
Home.tickOffers()
check(dailyCard.Parent and dailyCard.Timer.Text == "23:59:57", "ticking, without redrawing the card")
if not DailyShopConfig.onSale(notToday.id, now) then
	check(request("buy", "cosmetic", notToday.id).reason == "unknown", "and the server goes by the same day")
end

-- The rail.
click(p.railButtons.Coins)
check(Locker.section == "Coins" and p.railButtons.Coins.Border.Thickness == 4 and p.railButtons.Daily.Border.Thickness == 3, "COINS: lit")
check(Locker.card("Coins1200") and string.find(p.shop.Coins.Note.Text, "nothing you can buy makes your weapons stronger", 1, true), "the coin packs, and the promise")
click(p.railButtons.Featured)
check(Locker.section == "Featured" and p.shop.CanvasPosition.Y < 10, "FEATURED: back to the top")
click(p.railButtons.Weapons)
check(Locker.section == "Weapons" and Locker.card("Spritzer"), "WEAPONS: the guns")
Locker.open("Settings")
check(not p.rail.Visible, "no rail on the other pages")
Locker.close()

return { status = "PASS", checks = checks }
