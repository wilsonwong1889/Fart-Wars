-- The daily shop: shop-only cosmetics (ProgressionConfig, source "Daily
-- shop") for coins, five at a time. Which five changes every day at 00:00
-- UTC and is the same for everyone: it's worked out from the date alone, so
-- the server (which checks every purchase) and the client (which shows the
-- shop and its countdown) always agree with nothing to send. Each day has
-- one legendary or epic, one epic or rare, one rare and two commons. Only
-- cosmetics: nothing here changes combat.
local DailyShopConfig = {}

DailyShopConfig.SLOTS = 5
DailyShopConfig.DAY_SECONDS = 86400

export type Rarity = "common" | "rare" | "epic" | "legendary"
export type Item = { id: string, rarity: Rarity, price: number }

-- Every cosmetic that can come up, with its rarity and price in coins.
DailyShopConfig.pool = table.freeze({
	table.freeze({ id = "SolarStink", rarity = "legendary", price = 1500 }),
	table.freeze({ id = "GoldBoom", rarity = "legendary", price = 1800 }),
	table.freeze({ id = "PlasmaPuff", rarity = "epic", price = 1000 }),
	table.freeze({ id = "GalaxyTrail", rarity = "epic", price = 1200 }),
	table.freeze({ id = "SilentButDeadly", rarity = "epic", price = 1000 }),
	table.freeze({ id = "BubblegumBlast", rarity = "rare", price = 600 }),
	table.freeze({ id = "LavaTrail", rarity = "rare", price = 700 }),
	table.freeze({ id = "ConfettiBoom", rarity = "rare", price = 800 }),
	table.freeze({ id = "UhOh", rarity = "rare", price = 600 }),
	table.freeze({ id = "OceanBreeze", rarity = "common", price = 200 }),
	table.freeze({ id = "BubbleTrail", rarity = "common", price = 250 }),
	table.freeze({ id = "Beans", rarity = "common", price = 300 }),
	table.freeze({ id = "GoodGame", rarity = "common", price = 200 }),
} :: { Item })

-- What each slot may hold, in order.
DailyShopConfig.slotRarities = table.freeze({
	table.freeze({ "legendary", "epic" }),
	table.freeze({ "epic", "rare" }),
	table.freeze({ "rare" }),
	table.freeze({ "common" }),
	table.freeze({ "common" }),
})

-- How each rarity looks on its tile.
DailyShopConfig.rarities = table.freeze({
	legendary = table.freeze({ label = "LEGENDARY", color = Color3.fromRGB(255, 190, 40) }),
	epic = table.freeze({ label = "EPIC", color = Color3.fromRGB(165, 90, 235) }),
	rare = table.freeze({ label = "RARE", color = Color3.fromRGB(45, 140, 240) }),
	common = table.freeze({ label = "COMMON", color = Color3.fromRGB(130, 128, 150) }),
})

local byId: { [string]: Item } = {}
for _, item in DailyShopConfig.pool do
	byId[item.id] = item
end

function DailyShopConfig.item(id: string): Item?
	return byId[id]
end

-- The day number (days since 1 Jan 1970, UTC) at unix time `now`.
function DailyShopConfig.day(now: number): number
	return now // DailyShopConfig.DAY_SECONDS
end

-- Seconds until the next day's shop.
function DailyShopConfig.secondsLeft(now: number): number
	return DailyShopConfig.DAY_SECONDS - math.floor(now) % DailyShopConfig.DAY_SECONDS
end

-- The shop on day `day`: its items, most expensive first. A small
-- arithmetic shuffle seeded by the day (not Random), so every machine
-- shuffles the same way: Park-Miller, whose products stay exact in a
-- double.
function DailyShopConfig.forDay(day: number): { Item }
	local seed = (day * 7919 + 97) % 2147483646 + 1
	local function nextNumber(): number
		seed = seed * 16807 % 2147483647
		return seed
	end
	local order = table.clone(DailyShopConfig.pool)
	for i = #order, 2, -1 do
		local j = nextNumber() % i + 1
		order[i], order[j] = order[j], order[i]
	end
	local picked: { Item } = {}
	local used: { [string]: boolean } = {}
	for _, allowed in DailyShopConfig.slotRarities do
		for _, item in order do
			if not used[item.id] and table.find(allowed, item.rarity) then
				used[item.id] = true
				table.insert(picked, item)
				break
			end
		end
	end
	table.sort(picked, function(a, b)
		return a.price > b.price
	end)
	return picked
end

-- Today's shop, at unix time `now`.
function DailyShopConfig.today(now: number): { Item }
	return DailyShopConfig.forDay(DailyShopConfig.day(now))
end

-- Whether `id` is for sale at `now`, and its price.
function DailyShopConfig.onSale(id: string, now: number): Item?
	for _, item in DailyShopConfig.today(now) do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- "15:08:46" (or "8:46" under an hour).
function DailyShopConfig.countdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours, minutes = seconds // 3600, seconds % 3600 // 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds % 60)
	end
	return string.format("%d:%02d", minutes, seconds % 60)
end

return table.freeze(DailyShopConfig)
