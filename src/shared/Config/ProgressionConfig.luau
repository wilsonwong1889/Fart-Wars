-- Coins, XP, levels and what they unlock. All values are the masterplan's
-- proposals: starting points to tune from real session data, not
-- approved numbers. Coins are spendable; XP only ever goes up.
export type Grant = { coins: number, xp: number }
export type Unlock = {
	kind: "weapon" | "ability" | "cosmetic" | "cap",
	id: string?,
	-- What the level-up says.
	text: string,
}

local ProgressionConfig = {
	-- Per event. `chainBonus` is on top of the elimination for a chain or
	-- barrel kill.
	grants = table.freeze({
		elimination = table.freeze({ coins = 10, xp = 20 }),
		assist = table.freeze({ coins = 5, xp = 10 }),
		chainBonus = table.freeze({ coins = 5, xp = 0 }),
		alpha = table.freeze({ coins = 50, xp = 100 }),
	}) :: { [string]: Grant },

	-- Once per session, for time actually spent ACTIVE (AFK and spectating
	-- never count).
	participation = table.freeze({
		table.freeze({ minutes = 5, coins = 25, xp = 50 }),
		table.freeze({ minutes = 10, coins = 75, xp = 100 }),
	}),

	MAX_LEVEL = 50,

	-- What each level unlocks. Weapons become buyable in the shop; abilities
	-- and cosmetics are granted.
	unlocks = table.freeze({
		[1] = table.freeze({ kind = "weapon", id = "GasBlaster", text = "Gas Blaster" }),
		[5] = table.freeze({ kind = "weapon", id = "Spritzer", text = "Spritzer in the shop" }),
		[10] = table.freeze({ kind = "ability", id = "RecoveryBurst", text = "Recovery Burst (Q)" }),
		[15] = table.freeze({ kind = "weapon", id = "Thunderclapper", text = "Thunderclapper in the shop" }),
		[20] = table.freeze({ kind = "cosmetic", id = "GoldenGas", text = "Golden Gas tracers" }),
		[25] = table.freeze({ kind = "weapon", id = "StinkLobber", text = "Stink Lobber in the shop" }),
		[30] = table.freeze({ kind = "ability", id = "GasPulse", text = "Gas Pulse (Q)" }),
		[40] = table.freeze({ kind = "cosmetic", id = "RainbowRot", text = "Rainbow Rot tracers" }),
		[50] = table.freeze({ kind = "cap", text = "1,000 coins + Alpha Farter badge" }),
	}) :: { [number]: Unlock },
	CAP_REWARD = table.freeze({ coins = 1000, badge = "Alpha Farter" }),
	-- Past level 50, every this much XP pays out again.
	CAP_REPEAT_XP = 5000,
	CAP_REPEAT_COINS = 250,

	-- Weapon mastery: eliminations with a weapon, and the coins and badge
	-- each milestone pays (once).
	mastery = table.freeze({
		table.freeze({ eliminations = 25, coins = 100, badge = "Bronze" }),
		table.freeze({ eliminations = 75, coins = 250, badge = "Silver" }),
		table.freeze({ eliminations = 150, coins = 500, badge = "Gold" }),
		table.freeze({ eliminations = 300, coins = 1000, badge = "Platinum" }),
	}),

	-- Cosmetics, nothing that changes combat, four kinds: tracers (your
	-- shots' colour), trails (your Fart Dash puffs), emotes (E) and booms
	-- (the explosions of players you eliminate). `source` says how to get
	-- one; `free` ones everybody has.
	cosmetics = table.freeze({
		GoldenGas = table.freeze({ id = "GoldenGas", kind = "tracer", name = "Golden Gas", tracerColor = Color3.fromRGB(255, 200, 40), source = "Level 20" }),
		RainbowRot = table.freeze({ id = "RainbowRot", kind = "tracer", name = "Rainbow Rot", tracerColor = Color3.fromRGB(200, 90, 255), source = "Level 40" }),
		StinkSparkle = table.freeze({ id = "StinkSparkle", kind = "tracer", name = "Stink Sparkle", tracerColor = Color3.fromRGB(255, 120, 200), source = "Daily day 7" }),
		LuckyLime = table.freeze({ id = "LuckyLime", kind = "tracer", name = "Lucky Lime", tracerColor = Color3.fromRGB(170, 255, 120), source = "Free spin" }),
		StarterSwirl = table.freeze({ id = "StarterSwirl", kind = "tracer", name = "Starter Swirl", tracerColor = Color3.fromRGB(90, 220, 255), source = "Starter Pack" }),
		LimeTrail = table.freeze({ id = "LimeTrail", kind = "trail", name = "Lime Trail", trailColor = Color3.fromRGB(150, 255, 90), source = "Starter Pack" }),
		Toot = table.freeze({ id = "Toot", kind = "emote", name = "Toot", emoji = "💨", text = "TOOT!", free = true, source = "Everyone" }),
		VictoryToot = table.freeze({ id = "VictoryToot", kind = "emote", name = "Victory Toot", emoji = "🎺", text = "VICTORY TOOT!", source = "Starter Pack" }),
		PrestigeFlame = table.freeze({ id = "PrestigeFlame", kind = "tracer", name = "Prestige Flame", tracerColor = Color3.fromRGB(255, 110, 40), source = "Prestige 1" }),
		PrestigeTrail = table.freeze({ id = "PrestigeTrail", kind = "trail", name = "Prestige Trail", trailColor = Color3.fromRGB(190, 120, 255), source = "Prestige 3" }),
		CrownToot = table.freeze({ id = "CrownToot", kind = "emote", name = "Crown Toot", emoji = "👑", text = "ROYAL TOOT!", source = "Prestige 5" }),
		-- Season 1 (SeasonConfig). Booms colour the explosions of the players
		-- you eliminate.
		SeasonSpark = table.freeze({ id = "SeasonSpark", kind = "boom", name = "Spark Boom", boomColor = Color3.fromRGB(255, 230, 90), source = "Season 1, tier 5" }),
		SludgeTrail = table.freeze({ id = "SludgeTrail", kind = "trail", name = "Sludge Trail", trailColor = Color3.fromRGB(110, 150, 40), source = "Season 1, tier 10" }),
		ToxicBoom = table.freeze({ id = "ToxicBoom", kind = "boom", name = "Toxic Boom", boomColor = Color3.fromRGB(170, 60, 255), source = "Season 1, tier 15" }),
		BrainrotGold = table.freeze({ id = "BrainrotGold", kind = "tracer", name = "Brainrot Gold", tracerColor = Color3.fromRGB(255, 180, 0), source = "Season 1, tier 20" }),
		-- The daily shop's (DailyShopConfig): bought with coins on the day
		-- they're in it.
		OceanBreeze = table.freeze({ id = "OceanBreeze", kind = "tracer", name = "Ocean Breeze", tracerColor = Color3.fromRGB(60, 170, 255), source = "Daily shop" }),
		BubblegumBlast = table.freeze({ id = "BubblegumBlast", kind = "tracer", name = "Bubblegum Blast", tracerColor = Color3.fromRGB(255, 110, 190), source = "Daily shop" }),
		PlasmaPuff = table.freeze({ id = "PlasmaPuff", kind = "tracer", name = "Plasma Puff", tracerColor = Color3.fromRGB(120, 90, 255), source = "Daily shop" }),
		SolarStink = table.freeze({ id = "SolarStink", kind = "tracer", name = "Solar Stink", tracerColor = Color3.fromRGB(255, 150, 30), source = "Daily shop" }),
		BubbleTrail = table.freeze({ id = "BubbleTrail", kind = "trail", name = "Bubble Trail", trailColor = Color3.fromRGB(160, 220, 255), source = "Daily shop" }),
		LavaTrail = table.freeze({ id = "LavaTrail", kind = "trail", name = "Lava Trail", trailColor = Color3.fromRGB(255, 90, 40), source = "Daily shop" }),
		GalaxyTrail = table.freeze({ id = "GalaxyTrail", kind = "trail", name = "Galaxy Trail", trailColor = Color3.fromRGB(140, 80, 255), source = "Daily shop" }),
		ConfettiBoom = table.freeze({ id = "ConfettiBoom", kind = "boom", name = "Confetti Boom", boomColor = Color3.fromRGB(255, 100, 200), source = "Daily shop" }),
		GoldBoom = table.freeze({ id = "GoldBoom", kind = "boom", name = "Gold Boom", boomColor = Color3.fromRGB(255, 200, 40), source = "Daily shop" }),
		Beans = table.freeze({ id = "Beans", kind = "emote", name = "Beans!", emoji = "🥫", text = "BEANS!", source = "Daily shop" }),
		GoodGame = table.freeze({ id = "GoodGame", kind = "emote", name = "GG", emoji = "🤝", text = "GG!", source = "Daily shop" }),
		UhOh = table.freeze({ id = "UhOh", kind = "emote", name = "Uh Oh", emoji = "💦", text = "UH OH...", source = "Daily shop" }),
		SilentButDeadly = table.freeze({ id = "SilentButDeadly", kind = "emote", name = "Silent but Deadly", emoji = "🤫", text = "SILENT BUT DEADLY...", source = "Daily shop" }),
		-- The beta's (BadgeConfig): given once to everyone who plays during
		-- the beta, and never anything else. `exclusive`: no shop, spin,
		-- track or pass may ever have it.
		BetaBoom = table.freeze({ id = "BetaBoom", kind = "boom", name = "OG Beta Boom", boomColor = Color3.fromRGB(40, 255, 200), source = "PC beta testers", exclusive = true }),
	}),
	-- Cosmetics in the order the locker shows them.
	cosmeticOrder = table.freeze({ "GoldenGas", "RainbowRot", "StinkSparkle", "LuckyLime", "StarterSwirl", "LimeTrail", "Toot", "VictoryToot", "PrestigeFlame", "PrestigeTrail", "CrownToot", "SeasonSpark", "SludgeTrail", "ToxicBoom", "BrainrotGold", "OceanBreeze", "BubblegumBlast", "PlasmaPuff", "SolarStink", "BubbleTrail", "LavaTrail", "GalaxyTrail", "ConfettiBoom", "GoldBoom", "Beans", "GoodGame", "UhOh", "SilentButDeadly", "BetaBoom" }),

	-- Sanity limits on any one transaction, and how many recent ones each
	-- profile keeps for audits.
	MAX_COINS_PER_GRANT = 2000,
	MAX_XP_PER_GRANT = 2000,
	LEDGER_SIZE = 20,
	-- Combat coins (eliminations, assists, chains, streaks) above this in a
	-- minute get the player logged for review. A full six-player chain
	-- with a streak is about 140.
	ANOMALY_COINS_PER_MINUTE = 300,
}

-- Whether `owned` (a profile's OwnedCosmetics) includes cosmetic `id`.
function ProgressionConfig.ownsCosmetic(owned: { string }, id: string): boolean
	local cosmetic = ProgressionConfig.cosmetics[id]
	return cosmetic ~= nil and (cosmetic.free == true or table.find(owned, id) ~= nil)
end

-- XP from `level` to the next: 100 for the first levels, then rising ever
-- faster (730 at level 24, 4,090 at 49). Pacing: docs/economy.md.
function ProgressionConfig.xpToNext(level: number): number
	return math.round((100 + 0.25 * (level - 1) ^ 2.5) / 10) * 10
end

return table.freeze(ProgressionConfig)
