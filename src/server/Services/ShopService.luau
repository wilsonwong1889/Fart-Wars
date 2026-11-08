-- The shop and the locker, through one RemoteFunction:
--   ShopRequest:InvokeServer("buy", "weapon", id)
--   ShopRequest:InvokeServer("buy", "cosmetic", id)  (today's daily shop)
--   ShopRequest:InvokeServer("equip", "weapon" | "ability" | "cosmetic", id?)
--   ShopRequest:InvokeServer("profile", "all")   (the screens' first look)
--   ShopRequest:InvokeServer("redeem", code)      (the admin code: AdminCode)
--   ShopRequest:InvokeServer("recipients", "cosmetic", id)
--       who else in the server could be given it (`recipients`, and
--       `canGift`: whether this player may give gifts at all)
--   ShopRequest:InvokeServer("gift", "cosmetic", id, userId)
--       one of today's cosmetics for someone else here, with your coins
-- returns { ok, reason, message } (and `profile` for "profile"). Nothing
-- the client says about prices, coins or ownership is used: a purchase
-- checks the weapon is for sale, not owned, the player's level and coins
-- (a cosmetic: that it's in today's daily shop, by the server's clock),
-- all on the server. The coins and the weapon change together and are
-- saved before the answer goes back; if the save fails, both are put back
-- and the client is told, so the screen never shows a purchase that
-- didn't stick. One request per player at a time; a profile that isn't
-- saving can't buy. Equipping goes to LoadoutService (owned items only;
-- mid-fight it waits for a respawn).
-- A gift is one of today's cosmetics, paid for with the giver's coins and
-- theirs to keep, for another player in this server who doesn't own it
-- yet (anyone here; friends come first in the list). Both profiles must be
-- saving, and Roblox must allow both accounts to trade items bought with
-- in-game currency (PolicyService: coins can be bought with Robux). The
-- giver's coins are saved first, then the gift; if either save fails the
-- gift is taken back and the coins returned. No messages go with a gift,
-- only the giver's display name.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PolicyService = game:GetService("PolicyService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local DailyShopConfig = require(Shared.Config.DailyShopConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local RateLimit = require(Server.RateLimit)
local AdminCode = require(Server.AdminCode)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ExperimentService = require(script.Parent.ExperimentService)
local LoadoutService = require(script.Parent.LoadoutService)
local TeamService = require(script.Parent.TeamService)

local ShopService = {}

ShopService.MESSAGES = table.freeze({
	bought = "Bought! It's yours.",
	now = "Equipped.",
	respawn = "Equipped: you'll have it when you respawn.",
	busy = "Still working on your last request...",
	loading = "Your progress is still loading.",
	notSaving = "Progress isn't saving this session, so the shop is closed.",
	unknown = "That isn't for sale.",
	owned = "You already own that.",
	level = "You need a higher level for that.",
	coins = "Not enough coins.",
	saveFailed = "Couldn't save the purchase, so you weren't charged. Try again.",
	notOwned = "You don't own that.",
	badPayload = "That request didn't make sense.",
	rateLimited = "Slow down a little.",
	gifted = "Gift sent! It's theirs to keep.",
	giftsOff = "Gifting isn't available on your account.",
	noRecipient = "They aren't in this server any more.",
	recipientOwns = "They already have that one.",
	recipientNotSaving = "Their progress isn't saving this session, so they can't get gifts.",
	recipientLoading = "Their progress is still loading. Try again in a moment.",
	recipientGiftsOff = "They can't get gifts on their account.",
	recipientBusy = "They're in the middle of something. Try again in a moment.",
	recipients = "Pick who gets it.",
})

export type Recipient = { userId: number, owns: boolean, ready: boolean, friend: boolean }
export type Result = {
	ok: boolean,
	reason: string,
	message: string,
	profile: { [string]: any }?,
	recipients: { Recipient }?,
	canGift: boolean?,
}

local busy: { [Player]: boolean } = {}
local limiter = RateLimit.new(0.25)
local purchases = 0
local started = false

local function result(ok: boolean, reason: string): Result
	if not ok then
		Telemetry.count(`Shop.refused.{reason}`)
	end
	return { ok = ok, reason = reason, message = ShopService.MESSAGES[reason] or reason }
end

function ShopService.buy(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile then
		return result(false, "loading")
	elseif profile.temporary or profile.lost then
		return result(false, "notSaving")
	end
	local weapon = WeaponConfig.weapons[id]
	if not weapon or weapon.unlock ~= "shop" then
		return result(false, "unknown")
	end
	local data = profile.data
	if table.find(data.OwnedWeapons, id) then
		return result(false, "owned")
	elseif data.Level < weapon.level then
		return result(false, "level")
	end
	purchases += 1
	local ledgerId = `purchase:{id}:{purchases}`
	local price = ExperimentService.weaponPrice(player, weapon.price)
	if not EconomyService.spend(player, ledgerId, "purchase", price) then
		return result(false, "coins")
	end
	DataService.update(player, function(d)
		table.insert(d.OwnedWeapons, id)
	end)
	if not DataService.save(player) then
		DataService.update(player, function(d)
			local index = table.find(d.OwnedWeapons, id)
			if index then
				table.remove(d.OwnedWeapons, index)
			end
		end)
		EconomyService.refund(player, ledgerId, price)
		LoadoutService.push(player)
		return result(false, "saveFailed")
	end
	Telemetry.count("Shop.purchases")
	Telemetry.count(`Shop.bought.{id}`)
	-- The first purchase rate: Shop.firstPurchases over session.joins.
	if #data.OwnedWeapons == 2 then
		Telemetry.count("Shop.firstPurchases")
		Telemetry.first(player, "purchase")
	end
	Telemetry.log("Shop", "bought", { player = player, weapon = id, price = price })
	LoadoutService.push(player)
	return result(true, "bought")
end

-- The server's clock, for the daily shop (specs move it).
ShopService.now = os.time

-- A cosmetic from today's daily shop, for its price in coins: saved with
-- the coins taken, or neither.
function ShopService.buyCosmetic(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile then
		return result(false, "loading")
	elseif profile.temporary or profile.lost then
		return result(false, "notSaving")
	end
	local item = DailyShopConfig.onSale(id, ShopService.now())
	if not item or not ProgressionConfig.cosmetics[id] then
		return result(false, "unknown")
	end
	if ProgressionConfig.ownsCosmetic(profile.data.OwnedCosmetics, id) then
		return result(false, "owned")
	end
	purchases += 1
	local ledgerId = `purchase:{id}:{purchases}`
	if not EconomyService.spend(player, ledgerId, "purchase", item.price) then
		return result(false, "coins")
	end
	DataService.update(player, function(d)
		table.insert(d.OwnedCosmetics, id)
	end)
	if not DataService.save(player) then
		DataService.update(player, function(d)
			local index = table.find(d.OwnedCosmetics, id)
			if index then
				table.remove(d.OwnedCosmetics, index)
			end
		end)
		EconomyService.refund(player, ledgerId, item.price)
		LoadoutService.push(player)
		return result(false, "saveFailed")
	end
	Telemetry.count("Shop.cosmetics")
	Telemetry.count(`Shop.bought.{id}`)
	Telemetry.log("Shop", "bought", { player = player, cosmetic = id, price = item.price })
	LoadoutService.push(player)
	return result(true, "bought")
end

-- Whether Roblox lets this player trade items bought with in-game currency
-- (a web call, so it's asked once per player, as they join, and kept; a
-- call that fails counts as no, and is asked again next time). Specs
-- replace `policy`.
ShopService.policy = function(player: Player): boolean?
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	if not ok or type(info) ~= "table" then
		return nil
	end
	return info.IsPaidItemTradingAllowed == true
end
local giftPolicy: { [Player]: boolean } = {}

function ShopService.canGift(player: Player): boolean
	if giftPolicy[player] == nil then
		local allowed = ShopService.policy(player)
		if allowed ~= nil and player.Parent == Players then
			giftPolicy[player] = allowed
		end
		return allowed == true
	end
	return giftPolicy[player]
end

local function saving(profile: DataService.Profile?): boolean
	return profile ~= nil and not profile.temporary and not profile.lost
end

-- Everyone else in the server, for the gift list: whether they own `id`
-- already, whether they can get a gift now, and whether they're the
-- player's friend.
function ShopService.recipients(player: Player, id: string): Result
	if not DailyShopConfig.onSale(id, ShopService.now()) or not ProgressionConfig.cosmetics[id] then
		return result(false, "unknown")
	end
	local list: { Recipient } = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local profile = DataService.get(other)
			table.insert(list, {
				userId = other.UserId,
				owns = profile ~= nil and ProgressionConfig.ownsCosmetic(profile.data.OwnedCosmetics, id),
				ready = saving(profile) and ShopService.canGift(other),
				friend = TeamService.areFriends(player, other),
			})
		end
	end
	local answer = result(true, "recipients")
	answer.recipients = list
	answer.canGift = ShopService.canGift(player)
	return answer
end

-- One of today's cosmetics for `userId`, someone else in this server, with
-- the player's coins.
function ShopService.gift(player: Player, id: string, userId: number): Result
	local profile = DataService.get(player)
	if not profile then
		return result(false, "loading")
	elseif not saving(profile) then
		return result(false, "notSaving")
	end
	local item = DailyShopConfig.onSale(id, ShopService.now())
	if not item or not ProgressionConfig.cosmetics[id] then
		return result(false, "unknown")
	end
	local friend = Players:GetPlayerByUserId(userId)
	if not friend or friend == player then
		return result(false, "noRecipient")
	end
	-- The policy calls can wait on the web: everything else is checked after.
	if not ShopService.canGift(player) then
		return result(false, "giftsOff")
	elseif not ShopService.canGift(friend) then
		return result(false, "recipientGiftsOff")
	end
	-- Why they can't have it now, if they can't.
	local function refusal(): string?
		local theirs = DataService.get(friend)
		if friend.Parent ~= Players then
			return "noRecipient"
		elseif not theirs then
			return "recipientLoading"
		elseif not saving(theirs) then
			return "recipientNotSaving"
		elseif ProgressionConfig.ownsCosmetic((theirs :: DataService.Profile).data.OwnedCosmetics, id) then
			return "recipientOwns"
		end
		return nil
	end
	local refused = refusal() or (if busy[friend] then "recipientBusy" else nil)
	if refused then
		return result(false, refused)
	end
	local price = item.price
	purchases += 1
	local ledgerId = `gift:{id}:{friend.UserId}:{purchases}`
	if not EconomyService.spend(player, ledgerId, "giftSent", price) then
		return result(false, "coins")
	end
	-- Their own requests wait until the gift is in (or not).
	busy[friend] = true
	local function giveBack(given: boolean)
		if given then
			DataService.update(friend, function(d)
				local index = table.find(d.OwnedCosmetics, id)
				if index then
					table.remove(d.OwnedCosmetics, index)
				end
			end)
			LoadoutService.push(friend)
		end
		EconomyService.refund(player, ledgerId, price)
		DataService.save(player)
		LoadoutService.push(player)
	end
	local ok, answer = pcall(function(): Result
		-- The payment is saved before anything is given.
		if not DataService.save(player) then
			giveBack(false)
			return result(false, "saveFailed")
		end
		-- They may have left, or stopped saving, while that was written.
		local late = refusal()
		if late then
			giveBack(false)
			return result(false, late)
		end
		DataService.update(friend, function(d)
			table.insert(d.OwnedCosmetics, id)
		end)
		if not DataService.save(friend) then
			giveBack(true)
			return result(false, "saveFailed")
		end
		return result(true, "gifted")
	end)
	busy[friend] = nil
	if not ok then
		error(answer, 0)
	end
	if answer.ok then
		Telemetry.count("Shop.gifts")
		Telemetry.count(`Shop.gifted.{id}`)
		Telemetry.log("Shop", "gifted", { player = player, to = friend.UserId, cosmetic = id, price = price })
		LoadoutService.push(player)
		LoadoutService.push(friend)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local progress = remotes and remotes:FindFirstChild("ProgressEvent")
		if progress then
			(progress :: RemoteEvent):FireClient(friend, { kind = "giftReceived", from = player.DisplayName, item = id })
		end
	end
	return answer
end

-- One request from a client, checked and answered.
function ShopService.request(player: Player, action: unknown, kind: unknown, id: unknown, target: unknown?): Result
	if type(action) ~= "string" or type(kind) ~= "string" or (id ~= nil and (type(id) ~= "string" or #(id :: string) > 40)) then
		Telemetry.reject("ShopRequest", player, "badPayload")
		return result(false, "badPayload")
	end
	if target ~= nil and (type(target) ~= "number" or target ~= target // 1 or target <= 0 or target > 2 ^ 53) then
		Telemetry.reject("ShopRequest", player, "badPayload")
		return result(false, "badPayload")
	end
	if not limiter:allow(player, "shop") then
		Telemetry.reject("ShopRequest", player, "rateLimited")
		return result(false, "rateLimited")
	end
	if action == "profile" then
		local view = LoadoutService.view(player)
		local answer = result(view ~= nil, if view then "profile" else "loading")
		answer.profile = view
		return answer
	elseif action == "recipients" and kind == "cosmetic" and id then
		return ShopService.recipients(player, id :: string)
	end
	if busy[player] then
		return result(false, "busy")
	end
	busy[player] = true
	local ok, answer = pcall(function(): Result
		if action == "buy" and kind == "weapon" and id then
			return ShopService.buy(player, id :: string)
		elseif action == "buy" and kind == "cosmetic" and id then
			return ShopService.buyCosmetic(player, id :: string)
		elseif action == "gift" and kind == "cosmetic" and id and target then
			return ShopService.gift(player, id :: string, target :: number)
		elseif action == "redeem" then
			local redeemed, why = AdminCode.redeem(player, kind)
			return { ok = redeemed, reason = why, message = AdminCode.MESSAGES[why] or why }
		elseif action == "equip" then
			local equipped, why = LoadoutService.equip(player, kind :: string, id :: string?)
			return result(equipped, why)
		end
		Telemetry.reject("ShopRequest", player, "badPayload")
		return result(false, "badPayload")
	end)
	busy[player] = nil
	if not ok then
		Telemetry.error("Shop", answer)
		return result(false, "badPayload")
	end
	return answer :: Result
end

function ShopService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shopRequest = remotes:WaitForChild("ShopRequest") :: RemoteFunction
	shopRequest.OnServerInvoke = function(player, action, kind, id, target)
		Telemetry.count("remote.in.ShopRequest")
		return ShopService.request(player, action, kind, id, target)
	end
	-- Ask Roblox about gifting as each player joins, so the list is quick.
	local function ask(player: Player)
		task.spawn(ShopService.canGift, player)
	end
	Players.PlayerAdded:Connect(ask)
	for _, player in Players:GetPlayers() do
		ask(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		giftPolicy[player] = nil
		limiter:forget(player)
	end)
end

return ShopService
