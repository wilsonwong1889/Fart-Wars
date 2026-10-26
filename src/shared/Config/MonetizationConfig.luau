-- The store (masterplan 4.2): cosmetics and convenience only, never combat
-- power, and every item's contents shown in full (no fake discounts or
-- timers). Prices are set on Roblox, not here.
--
-- To sell something, create it in the Creator Dashboard (your experience →
-- Monetization → Passes / Developer Products) and paste its ID below. An ID
-- of 0 means "not set up": the store shows the item as unavailable and the
-- server never grants it.
export type Pass = {
	key: string,
	id: number,
	name: string,
	-- What the store lists, line by line.
	contents: { string },
	cosmetics: { string },
	-- Coins given once, the first time the pass is seen.
	coins: number,
}
export type Product = { key: string, id: number, name: string, coins: number }

local passes: { Pass } = {
	table.freeze({
		key = "StarterPack",
		id = 0,
		name = "Starter Pack",
		contents = table.freeze({
			"Starter Swirl tracer (your shots' colour)",
			"Lime Trail (your Fart Dash puffs)",
			"Victory Toot emote (E)",
			"500 coins, once",
		}),
		cosmetics = table.freeze({ "StarterSwirl", "LimeTrail", "VictoryToot" }),
		coins = 500,
	}),
}

-- Coin packs (developer products: buy as often as you like).
local products: { Product } = {
	table.freeze({ key = "Coins500", id = 0, name = "500 coins", coins = 500 }),
	table.freeze({ key = "Coins1200", id = 0, name = "1,200 coins", coins = 1200 }),
	table.freeze({ key = "Coins3000", id = 0, name = "3,000 coins", coins = 3000 }),
}

return table.freeze({
	passes = table.freeze(passes),
	products = table.freeze(products),
	-- How many granted purchase IDs each profile remembers (Roblox retries
	-- an unacknowledged receipt; a remembered one is never paid twice).
	RECEIPT_MEMORY = 100,
})
