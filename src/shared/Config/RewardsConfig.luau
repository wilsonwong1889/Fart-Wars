-- Rewards for coming back and for playing (masterplan 4.1). Values are
-- proposals to tune; everything here is free (no paid random rewards).
local RewardsConfig = {
	-- The daily track, one claim per UTC day. It loops after day 7, and
	-- missing a day doesn't reset it: the next claim is just the next day.
	daily = table.freeze({
		table.freeze({ coins = 100 }),
		table.freeze({ coins = 150 }),
		table.freeze({ coins = 200, spins = 1 }),
		table.freeze({ coins = 250 }),
		table.freeze({ coins = 300 }),
		table.freeze({ coins = 350, spins = 1 }),
		table.freeze({ coins = 500, cosmetic = "StinkSparkle" }),
	}),
	-- Coins instead of a cosmetic the player already owns.
	DUPLICATE_COSMETIC_COINS = 250,

	-- A free spin for every this many minutes of active play (AFK and the
	-- home screen don't count), at most GIFTS_PER_DAY a UTC day.
	GIFT_ACTIVE_MINUTES = 10,
	GIFTS_PER_DAY = 6,
	-- Spins bank up to this many.
	MAX_SPINS = 10,

	-- Playing with friends (masterplan 4.3). The squad bonus: for every
	-- SQUAD_MINUTES of active play with a Roblox friend active on your team
	-- in the same server, SQUAD_COINS and SQUAD_XP, SQUAD_PER_DAY times a
	-- UTC day. The welcome: when a friend's very first session reaches
	-- WELCOME_MINUTES of active play in your server, you both get
	-- WELCOME_COINS, once per newcomer; a player can welcome at most
	-- WELCOMES_PER_DAY newcomers a day (no farming with new accounts).
	SQUAD_MINUTES = 10,
	SQUAD_COINS = 50,
	SQUAD_XP = 50,
	SQUAD_PER_DAY = 3,
	WELCOME_MINUTES = 10,
	WELCOME_COINS = 200,
	WELCOMES_PER_DAY = 3,
	-- How many welcomed newcomers a profile remembers.
	WELCOME_MEMORY = 50,

	-- The free spin. Each prize's chance is its weight over the total, and
	-- the wheel shows every chance as a percentage.
	spin = table.freeze({
		table.freeze({ id = "coins50", label = "50 coins", coins = 50, weight = 40 }),
		table.freeze({ id = "coins100", label = "100 coins", coins = 100, weight = 28 }),
		table.freeze({ id = "xp150", label = "150 XP", xp = 150, weight = 15 }),
		table.freeze({ id = "coins250", label = "250 coins", coins = 250, weight = 11 }),
		table.freeze({ id = "coins1000", label = "1,000 coins", coins = 1000, weight = 5 }),
		table.freeze({ id = "luckyLime", label = "Lucky Lime tracer", cosmetic = "LuckyLime", weight = 1 }),
	}),
}

-- Each spin prize's chance, 0-1.
function RewardsConfig.chance(prize: { weight: number }): number
	local total = 0
	for _, entry in RewardsConfig.spin do
		total += entry.weight
	end
	return prize.weight / total
end

-- The UTC day number of a time (os.time()).
function RewardsConfig.day(at: number): number
	return at // 86400
end

return table.freeze(RewardsConfig)
