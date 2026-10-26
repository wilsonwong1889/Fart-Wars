-- The store's server side (masterplan 4.2), on Roblox's MarketplaceService:
--   * coin packs (developer products) through ProcessReceipt. A receipt is
--     paid once: its purchase ID is kept in the profile, a repeat answers
--     "granted" without paying again, and the coins and the ID are saved
--     before Roblox is told the purchase went through. If the player isn't
--     here, their profile isn't loaded or saving, or the save fails (the
--     coins are taken back), Roblox is told "not yet" and retries later.
--   * passes (the Starter Pack): when a player is seen owning one, on
--     joining or right after buying it, its cosmetics and its one-time
--     coins are given, once (the pass is remembered in the profile).
-- Only IDs set in MonetizationConfig count; 0 means not for sale.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LoadoutService = require(script.Parent.LoadoutService)

local MonetizationService = {}

local market: any = MarketplaceService
local catalog = MonetizationConfig
local started = false

local function hook(target: any)
	target.ProcessReceipt = MonetizationService.processReceipt
	local finished = target.PromptGamePassPurchaseFinished
	if finished then
		finished:Connect(function(player: Player, passId: number, purchased: boolean)
			local pass = MonetizationService.passById(passId)
			-- Roblox's word, checked again before anything is given.
			if purchased and pass and MonetizationService.owns(player, pass) then
				MonetizationService.grantPass(player, pass)
			end
		end)
	end
end

-- Test seams: a stand-in MarketplaceService, and another catalog (with IDs).
function MonetizationService.setMarketplace(fake: any)
	market = fake
	if started then
		hook(fake)
	end
end

function MonetizationService.setCatalog(fake: any)
	catalog = fake
end

local function productById(id: number): MonetizationConfig.Product?
	for _, product in catalog.products do
		if product.id ~= 0 and product.id == id then
			return product
		end
	end
	return nil
end

function MonetizationService.passById(id: number): MonetizationConfig.Pass?
	for _, pass in catalog.passes do
		if pass.id ~= 0 and pass.id == id then
			return pass
		end
	end
	return nil
end

-- Roblox's receipt callback. Returns a ProductPurchaseDecision.
function MonetizationService.processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local product = productById(tonumber(info.ProductId) or 0)
	local player = Players:GetPlayerByUserId(tonumber(info.PlayerId) or 0)
	local purchaseId = tostring(info.PurchaseId)
	if not product then
		Telemetry.count("Store.unknownProduct")
		warn(`[FW] a receipt for product {tostring(info.ProductId)}, which MonetizationConfig doesn't list`)
		return notYet
	end
	if not player then
		return notYet
	end
	local profile = DataService.get(player)
	if not profile or profile.temporary or profile.lost then
		Telemetry.count("Store.receiptDeferred")
		return notYet
	end
	if table.find(profile.data.Receipts, purchaseId) then
		Telemetry.count("Store.duplicateReceipts")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local grantId = `receipt:{purchaseId}`
	if not EconomyService.grantPurchase(player, grantId, product.coins) then
		return notYet
	end
	DataService.update(player, function(data)
		table.insert(data.Receipts, purchaseId)
		while #data.Receipts > catalog.RECEIPT_MEMORY do
			table.remove(data.Receipts, 1)
		end
	end)
	if not DataService.save(player) then
		-- Not saved: undo it all, and let Roblox try again.
		DataService.update(player, function(data)
			local index = table.find(data.Receipts, purchaseId)
			if index then
				table.remove(data.Receipts, index)
			end
		end)
		EconomyService.revoke(player, grantId, product.coins)
		Telemetry.count("Store.receiptSaveFailed")
		return notYet
	end
	Telemetry.count("Store.purchases")
	Telemetry.count(`Store.bought.{product.key}`)
	Telemetry.log("Store", "receipt", { player = player, product = product.key })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Gives `pass`'s contents if the player hasn't had them yet.
function MonetizationService.grantPass(player: Player, pass: MonetizationConfig.Pass): boolean
	local profile = DataService.get(player)
	if not profile or profile.temporary or table.find(profile.data.PassesGranted, pass.key) then
		return false
	end
	DataService.update(player, function(data)
		table.insert(data.PassesGranted, pass.key)
		for _, id in pass.cosmetics do
			if not table.find(data.OwnedCosmetics, id) then
				table.insert(data.OwnedCosmetics, id)
			end
		end
	end)
	if pass.coins > 0 then
		EconomyService.grantPurchase(player, `pass:{pass.key}`, pass.coins)
	end
	Telemetry.count(`Store.passGranted.{pass.key}`)
	LoadoutService.push(player)
	task.spawn(DataService.save, player)
	return true
end

-- Whether the player owns `pass` on Roblox (false if Roblox can't say).
function MonetizationService.owns(player: Player, pass: MonetizationConfig.Pass): boolean
	for attempt = 1, 3 do
		local ok, result = pcall(market.UserOwnsGamePassAsync, market, player.UserId, pass.id)
		if ok then
			return result == true
		end
		task.wait(attempt)
	end
	return false
end

-- Checks every pass the player might own and gives what's new.
function MonetizationService.checkPasses(player: Player)
	for _, pass in catalog.passes do
		if pass.id ~= 0 and MonetizationService.owns(player, pass) then
			MonetizationService.grantPass(player, pass)
		end
	end
end

-- What the store shows (IDs, contents), for the client.
function MonetizationService.catalog(): { [string]: any }
	return catalog
end

function MonetizationService.start()
	if started then
		return
	end
	started = true
	hook(market)
	DataService.Loaded:Connect(function(player)
		task.spawn(MonetizationService.checkPasses, player)
	end)
end

return MonetizationService
