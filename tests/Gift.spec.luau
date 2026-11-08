-- Gifts (ShopService.gift and .recipients, the shop's GIFT card and the
-- "A GIFT!" banner), with one client and six players:
--   * who's here: everyone else in the server, never you; friends marked;
--     who has it already; who can't get gifts (not saving, or Roblox's
--     policy on trading items bought with in-game currency)
--   * refused: not in today's shop, yourself, nobody here, a bad target,
--     too few coins, the policy (theirs or yours), not saving or still
--     loading, has it,
--     busy saving their own purchase (what they're buying is theirs
--     already); none of it costs anything
--   * given: your coins, their cosmetic, both saved before the answer,
--     and they're told who it's from; something you own can be a gift too
--   * a save that fails (the payment or the gift): coins back, nothing
--     given; leaving while the payment saves: the same
--   * while a gift is saving, the one getting it waits to buy
--   * the shop: GIFT on a cosmetic's "Buy it?" card (not a weapon's), the
--     list with friends first, only those who can have it picked, BACK,
--     SEND; grey without the coins; someone who leaves drops out
--   * getting one: the banner and a line saying who it's from
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
local Team = require(server.Services.TeamService)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local DailyShopConfig = require(ReplicatedStorage.Shared.Config.DailyShopConfig)

-- The DataStore: a key can fail its next saves, or be slow.
local saved: { [string]: any } = {}
local failKey: string?, failNext = nil, 0
local slowKey: string? = nil
local SLOW_SECONDS = 1
local function copy(value: any): any
	return if value == nil then nil else HttpService:JSONDecode(HttpService:JSONEncode(value))
end
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		if key == failKey and failNext > 0 then
			failNext -= 1
			error("503: DataStore request failed (test outage)")
		end
		if key == slowKey then
			task.wait(SLOW_SECONDS)
		end
		local result = transform(copy(saved[key]))
		if result ~= nil then
			saved[key] = copy(result)
		end
		return result
	end,
})
-- Me and Pal are friends. Nat's account can't trade (Roblox's policy).
Team.checkFriends = function(a, b)
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return low == 1 and high == 2
end
Shop.policy = function(player: Player): boolean?
	return player.UserId ~= 4
end

local DAY = 20000
local now = DAY * 86400 + 3600
Shop.now = function()
	return now
end
local today = DailyShopConfig.today(now)
local dearest, third, second, cheapest = today[1], today[#today - 2], today[#today - 1], today[#today]
local notToday
for _, item in DailyShopConfig.pool do
	if not DailyShopConfig.onSale(item.id, now) then
		notToday = item
		break
	end
end

-- The client is Me's.
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
local Progress = require(Controllers.ProgressController)
local UI = require(game.StarterPlayer.StarterPlayerScripts.Client.UI)
Locker.now = Shop.now

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local pal = join("Pal", 2)
local sam = join("Sam", 3)
local nat = join("Nat", 4)
local tim = join("Tim", 6)
task.wait(0.5)
assert(Data.get(tim)).temporary = true

local function data(player: Player): any
	return assert(Data.get(player)).data
end
local function owns(player: Player, id: string): boolean
	return ProgressionConfig.ownsCosmetic(data(player).OwnedCosmetics, id)
end
local function savedOwns(userId: number, id: string): boolean
	local entry = saved[`player_{userId}`]
	return entry ~= nil and table.find(entry.OwnedCosmetics, id) ~= nil
end
local function coins(player: Player, n: number)
	while n > 0 do
		local step = math.min(n, ProgressionConfig.MAX_COINS_PER_GRANT)
		Economy.testGrant(player, step, 0)
		n -= step
	end
end
local function request(player: Player, action: any, kind: any, id: any, target: any?): any
	task.wait(0.3) -- past the rate limit
	return Shop.request(player, action, kind, id, target)
end
local function click(button: GuiButton)
	button.Activated:Fire()
	task.wait(0.05)
end
local function byUser(answer: any): { [number]: any }
	local out = {}
	for _, entry in answer.recipients or {} do
		out[entry.userId] = entry
	end
	return out
end
local gifts = {}
ReplicatedStorage.Remotes.ProgressEvent.FiredToClient:Connect(function(player, event)
	if type(event) == "table" and event.kind == "giftReceived" then
		table.insert(gifts, { player = player, event = event })
	end
end)
for _, player in { me, pal, sam, nat, tim } do
	check(Data.isLoaded(player), `{player.Name}'s profile is in`)
end

-- Who's here.
local answer = request(me, "recipients", "cosmetic", cheapest.id)
check(answer.ok and answer.canGift == true, "the list, and I can give gifts")
local here = byUser(answer)
check(here[1] == nil, "not me")
check(here[2] and here[2].friend and here[2].ready and not here[2].owns, "Pal: a friend, ready")
check(here[3] and not here[3].friend and here[3].ready, "Sam: not a friend, ready all the same")
check(here[4] and not here[4].ready, "Nat: Roblox doesn't let that account trade")
check(here[6] and not here[6].ready, "Tim: not saving this session")
check(request(me, "recipients", "cosmetic", notToday.id).reason == "unknown", "only today's cosmetics")

-- Refused, and free.
check(request(me, "gift", "cosmetic", cheapest.id, 2).reason == "coins", "too few coins")
coins(me, cheapest.price * 3)
local start = data(me).Coins
check(request(me, "gift", "cosmetic", notToday.id, 2).reason == "unknown", "not in today's shop")
check(request(me, "gift", "cosmetic", "Toot", 2).reason == "unknown", "not a shop cosmetic")
check(request(me, "gift", "cosmetic", cheapest.id, 1).reason == "noRecipient", "not to myself")
check(request(me, "gift", "cosmetic", cheapest.id, 999).reason == "noRecipient", "not to someone who isn't here")
check(request(me, "gift", "cosmetic", cheapest.id, -1001).reason == "badPayload", "not to a bot")
check(request(me, "gift", "cosmetic", cheapest.id, "2").reason == "badPayload", "a target that isn't a number")
check(request(me, "gift", "cosmetic", cheapest.id, 2.5).reason == "badPayload", "or isn't whole")
check(request(me, "gift", "cosmetic", cheapest.id).reason == "badPayload", "a gift for nobody")
check(request(me, "gift", "cosmetic", cheapest.id, 4).reason == "recipientGiftsOff", "Nat can't get gifts")
check(request(me, "gift", "cosmetic", cheapest.id, 6).reason == "recipientNotSaving", "Tim isn't saving")
slowKey = "player_8"
local ned = join("Ned", 8)
task.wait(0.1)
check(not Data.isLoaded(ned) and request(me, "gift", "cosmetic", cheapest.id, 8).reason == "recipientLoading", "Ned is still loading")
task.wait(SLOW_SECONDS)
slowKey = nil
ned.Parent = nil
task.wait(0.1)
coins(nat, cheapest.price)
check(request(nat, "gift", "cosmetic", cheapest.id, 2).reason == "giftsOff", "and Nat can't give them")
check(data(me).Coins == start and data(nat).Coins == cheapest.price, "none of that cost anything")
check(not owns(pal, cheapest.id), "nor gave anything")

-- Given.
answer = request(me, "gift", "cosmetic", cheapest.id, 2)
check(answer.ok and answer.reason == "gifted" and answer.message == Shop.MESSAGES.gifted, "a gift: " .. tostring(answer.reason))
check(data(me).Coins == start - cheapest.price, "paid with my coins")
check(owns(pal, cheapest.id) and not owns(me, cheapest.id), "Pal has it; I don't")
check(saved.player_1.Coins == start - cheapest.price and savedOwns(2, cheapest.id), "both saved before the answer")
check(#gifts == 1 and gifts[1].player == pal and gifts[1].event.from == "Me", "Pal is told it's from me")
check(gifts[1].event.item == cheapest.id, "and what it is")
check(request(me, "gift", "cosmetic", cheapest.id, 2).reason == "recipientOwns", "twice: Pal has it already")
check(request(pal, "buy", "cosmetic", cheapest.id).reason == "owned", "and Pal can't buy it now")
check(byUser(request(me, "recipients", "cosmetic", cheapest.id))[2].owns == true, "the list says Pal has it")
check(request(me, "buy", "cosmetic", cheapest.id).ok, "I can still buy my own")
check(request(me, "gift", "cosmetic", cheapest.id, 3).ok and owns(sam, cheapest.id), "and give one I own")
check(data(me).Coins == start - cheapest.price * 3 and data(me).Coins == 0, "three paid for")

-- A save that fails.
coins(me, second.price)
start = data(me).Coins
failKey, failNext = "player_1", 3
answer = request(me, "gift", "cosmetic", second.id, 2)
check(answer.reason == "saveFailed", "the payment didn't save")
check(data(me).Coins == start and not owns(pal, second.id) and not savedOwns(2, second.id), "so nothing happened")
failKey, failNext = "player_2", 3
answer = request(me, "gift", "cosmetic", second.id, 2)
check(answer.reason == "saveFailed", "the gift didn't save")
check(data(me).Coins == start and saved.player_1.Coins == start, "coins back, and saved back")
check(not owns(pal, second.id) and not savedOwns(2, second.id), "nothing half-given")
failKey, failNext = nil, 0

-- Busy.
coins(pal, second.price)
slowKey = "player_2"
local palAnswer
task.wait(0.3)
task.spawn(function()
	palAnswer = Shop.request(pal, "buy", "cosmetic", second.id)
end)
check(request(me, "gift", "cosmetic", second.id, 2).reason == "recipientOwns", "what Pal is buying is Pal's already")
check(request(me, "gift", "cosmetic", third.id, 2).reason == "recipientBusy", "and anything else waits till it's saved")
task.wait(SLOW_SECONDS)
slowKey = nil
check(palAnswer and palAnswer.ok and owns(pal, second.id), "Pal's purchase went through")
check(data(me).Coins == start, "and mine wasn't taken")
slowKey = "player_1"
local mine
task.wait(0.3)
task.spawn(function()
	mine = Shop.request(me, "gift", "cosmetic", second.id, 3)
end)
coins(sam, second.price)
check(request(sam, "buy", "cosmetic", second.id).reason == "busy", "while a gift for Sam saves, Sam waits")
task.wait(SLOW_SECONDS)
slowKey = nil
check(mine and mine.ok and owns(sam, second.id), "then has it")
check(data(sam).Coins == second.price, "without paying")

-- Leaving while the payment saves.
local lea = join("Lea", 7)
task.wait(0.3)
coins(me, third.price)
start = data(me).Coins
slowKey = "player_1"
mine = nil
task.spawn(function()
	mine = Shop.request(me, "gift", "cosmetic", third.id, 7)
end)
task.wait(0.2)
lea.Parent = nil
task.wait(SLOW_SECONDS * 2)
slowKey = nil
check(mine and mine.reason == "noRecipient", "Lea left: " .. tostring(mine and mine.reason))
check(data(me).Coins == start and saved.player_1.Coins == start, "coins back")
check(not savedOwns(7, third.id), "and Lea didn't get it")

-- The shop.
coins(sam, third.price)
check(request(sam, "buy", "cosmetic", third.id).ok, "Sam buys the third himself")
Locker.open("Weapons", "Daily")
task.wait(0.1)
local p = Locker.parts
Locker.confirmBuy("Spritzer")
check(p.confirm.Visible and not p.confirmGift.Visible and p.confirmCard.Size.Y.Offset == 330, "a weapon can't be a gift")
Locker.closeConfirm()
task.wait(0.3)
click(Locker.card(third.id).Window)
check(p.confirm.Visible and p.confirmGift.Visible and p.confirmCard.Size.Y.Offset == 396, "a cosmetic's card has GIFT")
check(p.confirmGift:GetAttribute("Enabled") ~= false, "with the coins: ready")
click(p.confirmGift)
task.wait(0.1)
local name = string.upper(ProgressionConfig.cosmetics[third.id].name)
check(not p.confirm.Visible and p.gift.Visible and p.giftTitle.Text == `GIFT {name}`, "GIFT: the list")
check(string.find(p.giftPrice.Text, `💰 {UI.commas(third.price)}`, 1, true) ~= nil, "what it costs: " .. p.giftPrice.Text)
local function row(userId: number): any
	return p.giftList:FindFirstChild(`Row{userId}`)
end
check(row(2) and row(3) and row(4) and row(6) and not row(1), "everyone else here")
check(row(2).LayoutOrder == 1 and row(2).Tag.Text == "FRIEND", "my friend first")
check(row(3).Tag.Text == "HAS IT" and row(3):GetAttribute("Enabled") == false, "Sam has it")
check(row(4).Tag.Text == "CAN'T GET GIFTS" and row(4):GetAttribute("Enabled") == false, "Nat can't")
check(row(6).Tag.Text == "CAN'T GET GIFTS", "nor Tim")
check(p.giftLeft.Text == "Pick who gets it." and p.giftSend:GetAttribute("Enabled") == false, "SEND waits for a pick")
click(row(4))
check(p.giftTarget == nil, "Nat can't be picked")
click(row(2))
check(p.giftTarget == 2 and row(2).Border.Thickness == 3, "Pal picked")
check(p.giftLeft.Text == `Pal gets it. You'll have {data(me).Coins - third.price} coins left.`, "says who and what's left: " .. p.giftLeft.Text)
check(p.giftSend:GetAttribute("Enabled") ~= false, "SEND ready")
click(p.giftBack)
check(not p.gift.Visible and p.confirm.Visible and p.confirmId == third.id, "BACK: the card again")
task.wait(0.3)
click(p.confirmGift)
task.wait(0.1)
click(row(2))
task.wait(0.3) -- a person takes longer than the rate limit to pick
click(p.giftSend)
task.wait(0.3)
check(not p.gift.Visible and owns(pal, third.id), "SEND: Pal has it: " .. p.status.Text)
check(p.status.Text == Shop.MESSAGES.gifted, "the shop says so: " .. p.status.Text)

-- Grey without the coins; someone leaving drops out.
check(data(me).Coins < dearest.price, "I can't afford the dearest")
click(Locker.card(dearest.id).Window)
check(p.confirmGift.Visible and p.confirmGift:GetAttribute("Enabled") == false, "GIFT grey without the coins")
Locker.closeConfirm()
task.wait(0.3)
Locker.openGift(cheapest.id)
task.wait(0.1)
check(row(3) and row(3).Tag.Text == "HAS IT", "Sam's in the list")
sam.Parent = nil
task.wait(0.1)
check(row(3) == nil, "until he leaves")
Locker.close()
check(not p.gift.Visible, "closing the locker closes it")

-- Getting one.
coins(pal, dearest.price)
check(not owns(me, dearest.id), "I don't have the dearest")
check(request(pal, "gift", "cosmetic", dearest.id, 1).ok and owns(me, dearest.id), "Pal gives it to me")
task.wait(0.1)
local dearestName = ProgressionConfig.cosmetics[dearest.id].name
check(Progress.parts.banner.Visible and Progress.parts.bannerTitle.Text == "🎁 A GIFT!", "the banner")
check(Progress.parts.bannerDetail.Text == `Pal gave you {dearestName}!`, "who it's from: " .. Progress.parts.bannerDetail.Text)
local line = false
for _, child in Progress.parts.lines:GetChildren() do
	if child:IsA("TextLabel") and string.find(child.Text, "equip it in your Loadout", 1, true) then
		line = true
	end
end
check(line, "and where to equip it")
check(Locker.profile and table.find(Locker.profile.ownedCosmetics, dearest.id), "the locker knows")

return { status = "PASS", checks = checks }
