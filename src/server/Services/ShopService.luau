-- The shop and the locker, through one RemoteFunction:
--   ShopRequest:InvokeServer("buy", "weapon", id)
--   ShopRequest:InvokeServer("equip", "weapon" | "ability" | "cosmetic", id?)
--   ShopRequest:InvokeServer("profile", "all")   (the screens' first look)
-- returns { ok, reason, message } (and `profile` for "profile"). Nothing
-- the client says about prices, coins or ownership is used: a purchase
-- checks the weapon is for sale, not owned, the player's level and coins,
-- all on the server. The coins and the weapon change together and are
-- saved before the answer goes back; if the save fails, both are put back
-- and the client is told, so the screen never shows a purchase that
-- didn't stick. One request per player at a time; a profile that isn't
-- saving can't buy. Equipping goes to LoadoutService (owned items only;
-- mid-fight it waits for a respawn).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local RateLimit = require(Server.RateLimit)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ExperimentService = require(script.Parent.ExperimentService)
local LoadoutService = require(script.Parent.LoadoutService)

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
})

export type Result = { ok: boolean, reason: string, message: string, profile: { [string]: any }? }

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

-- One request from a client, checked and answered.
function ShopService.request(player: Player, action: unknown, kind: unknown, id: unknown): Result
	if type(action) ~= "string" or type(kind) ~= "string" or (id ~= nil and (type(id) ~= "string" or #(id :: string) > 40)) then
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
	end
	if busy[player] then
		return result(false, "busy")
	end
	busy[player] = true
	local ok, answer = pcall(function(): Result
		if action == "buy" and kind == "weapon" and id then
			return ShopService.buy(player, id :: string)
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
	shopRequest.OnServerInvoke = function(player, action, kind, id)
		return ShopService.request(player, action, kind, id)
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		limiter:forget(player)
	end)
end

return ShopService
