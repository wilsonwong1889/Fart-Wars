-- The store and cosmetics (masterplan 4.2), against a stand-in
-- MarketplaceService and DataStore, with one client:
--   * a coin pack's receipt pays once: saved before "granted"; a repeated
--     receipt is granted without paying again; an unknown product, a
--     player who isn't here, an unsaved session or a failed save answer
--     "not yet" (with the coins taken back), and Roblox's retry then pays
--     once; only the latest receipts are remembered
--   * a pass (the Starter Pack) is given once when the player is seen to
--     own it, on joining or after buying (checked with Roblox first)
--   * its cosmetics: a tracer, a Fart Dash trail and an emote, equipped
--     into their own slots; E shows the emote over your head, a few
--     seconds apart
--   * the client: the Store tab (contents, unavailable until IDs are set)
--     and the cosmetics grid
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
local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Signal)
local Data = require(server.Services.DataService)
local Store = require(server.Services.MonetizationService)
local Loadout = require(server.Services.LoadoutService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes

local saved = {}
local failNext = 0
Data.setStore({
	UpdateAsync = function(_, key, transform)
		if failNext > 0 then
			failNext -= 1
			error("503: DataStore request failed (test outage)")
		end
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})
local owned: { [string]: boolean } = {}
local market = {
	PromptGamePassPurchaseFinished = Signal.new(),
	UserOwnsGamePassAsync = function(_, userId: number, passId: number)
		return owned[`{userId}:{passId}`] == true
	end,
}
Store.setMarketplace(market)
local StarterPack = {
	key = "StarterPack",
	id = 111,
	name = "Starter Pack",
	contents = { "a", "b", "c", "d" },
	cosmetics = { "StarterSwirl", "LimeTrail", "VictoryToot" },
	coins = 500,
}
Store.setCatalog({
	passes = { StarterPack },
	products = { { key = "Coins500", id = 201, name = "500 coins", coins = 500 } },
	RECEIPT_MEMORY = 100,
})
check(market.ProcessReceipt == Store.processReceipt, "the receipt callback is Roblox's ProcessReceipt")
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet

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
local Effects = require(Controllers.EffectsController)
local function data(player: Player?): any
	return assert(Data.get(player or me)).data
end
task.wait(0.5)

-- Coin packs.
local function receipt(purchaseId: string, productId: number?, playerId: number?): any
	return Store.processReceipt({ PlayerId = playerId or me.UserId, ProductId = productId or 201, PurchaseId = purchaseId })
end
check(receipt("p1") == Granted and data().Coins == 500, "a 500-coin pack: paid")
check(table.find(data().Receipts, "p1") and saved.player_1 and string.find(saved.player_1, "p1", 1, true), "and saved before Roblox hears 'granted'")
check(receipt("p1") == Granted and data().Coins == 500 and counter("Store.duplicateReceipts") == 1, "the same receipt again: granted, not paid twice")
check(receipt("p2", 999) == NotYet and data().Coins == 500, "a product the game doesn't sell: not yet")
check(receipt("p3", 201, 424242) == NotYet, "a player who isn't here: not yet (Roblox retries)")
failNext = 3
check(receipt("p4") == NotYet, "a save that fails: not yet")
check(data().Coins == 500 and not table.find(data().Receipts, "p4"), "and the coins are taken back")
check(receipt("p4") == Granted and data().Coins == 1000, "Roblox's retry pays it, once")
assert(Data.get(me)).temporary = true
check(receipt("p5") == NotYet, "an unsaved session: not yet")
assert(Data.get(me)).temporary = false
for i = 1, 105 do
	Data.update(me, function(d)
		table.insert(d.Receipts, `old{i}`)
	end)
end
receipt("p6")
check(#data().Receipts == 100 and data().Receipts[100] == "p6", "only the latest 100 receipts are kept")
check(counter("Store.purchases") == 3, "purchases counted")

-- The Starter Pack.
check(not table.find(data().PassesGranted, "StarterPack"), "no pass yet")
market.PromptGamePassPurchaseFinished:Fire(me, 111, true)
task.wait(0.1)
check(not table.find(data().PassesGranted, "StarterPack"), "a 'purchased' Roblox can't confirm gives nothing")
owned["1:111"] = true
local before = data().Coins
market.PromptGamePassPurchaseFinished:Fire(me, 111, true)
task.wait(0.1)
check(table.find(data().PassesGranted, "StarterPack") and data().Coins == before + 500, "bought: the pack and its 500 coins")
for _, id in StarterPack.cosmetics do
	check(table.find(data().OwnedCosmetics, id), `and the {id}`)
end
Store.checkPasses(me)
check(data().Coins == before + 500, "seen again: nothing more")
-- Owned before joining.
local lou = Instance.new("Player")
lou.Name = "Lou"
lou.UserId = 2
owned["2:111"] = true
lou.Parent = Players
task.wait(0.5)
check(table.find(data(lou).PassesGranted, "StarterPack") and data(lou).Coins == 500, "a pass owned before joining is given on joining")
lou.Parent = nil
task.wait(0.5)
local lou2 = Instance.new("Player")
lou2.Name = "Lou"
lou2.UserId = 2
lou2.Parent = Players
task.wait(0.5)
check(data(lou2).Coins == 500, "and only once, across sessions")

-- Cosmetic slots.
Lifecycle.requestPlay(me, nil)
task.wait(0.2)
check(Loadout.equip(me, "cosmetic", "LimeTrail") and me:GetAttribute("Trail") == "LimeTrail", "the Lime Trail on Fart Dash")
check(Loadout.equip(me, "cosmetic", "StarterSwirl") and me:GetAttribute("Tracer") == "StarterSwirl" and me:GetAttribute("Trail") == "LimeTrail", "a tracer in its own slot")
check(me:GetAttribute("Emote") == "Toot", "everyone has the Toot emote")
check(Loadout.equip(me, "cosmetic", "VictoryToot") and me:GetAttribute("Emote") == "VictoryToot", "the Victory Toot instead")
check(not Loadout.equip(me, "cosmetic", "LuckyLime"), "a cosmetic not owned can't be equipped")
check(Loadout.equip(me, "trail", nil) and me:GetAttribute("Trail") == nil, "the trail off again")
-- Emotes.
local emotes = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if event.kind == "emote" and player == me then
		table.insert(emotes, event)
	end
end)
task.wait(3.1)
Remotes.Emote.OnServerEvent:Fire(me)
task.wait(0.05)
check(#emotes == 1 and emotes[1].emote == "VictoryToot", "E: everyone sees the emote")
check(me.Character.Head:FindFirstChild("Emote"), "over my head on screen")
Remotes.Emote.OnServerEvent:Fire(me)
task.wait(0.05)
check(#emotes == 1, "again at once: too soon")
check(Effects.emote(me.UserId, "GoldenGas") == nil, "a tracer isn't an emote")

-- The client's store and cosmetics.
Locker.open("Store")
task.wait(0.1)
local content = Locker.parts.content
check(content:FindFirstChild("StarterPack") and content.StarterPack.Action.Text == "OWNED", "the store: the Starter Pack, owned")
check(content.Coins.Coins500.Action.Text == "UNAVAILABLE", "coin packs unavailable until their IDs are set")
Locker.open("Progression")
task.wait(0.1)
local grid = content.Stats.Cosmetics
check(grid.VictoryToot.Text == "🎺 Victory Toot ✓" and grid.StarterSwirl.Text == "Starter Swirl ✓", "the cosmetics grid: equipped ones ticked")
check(grid.LuckyLime.Text == "FREE SPIN", "one not owned says where it comes from")
Locker.close()

return { status = "PASS", checks = checks }
