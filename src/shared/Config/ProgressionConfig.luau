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

	-- Cosmetics, nothing that changes combat, three kinds: tracers (your
	-- shots' colour), trails (your Fart Dash puffs) and emotes (E). `source`
	-- says how to get one; `free` ones everybody has.
	cosmetics = table.freeze({
		GoldenGas = table.freeze({ id = "GoldenGas", kind = "tracer", name = "Golden Gas", tracerColor = Color3.fromRGB(255, 200, 40), source = "Level 20" }),
		RainbowRot = table.freeze({ id = "RainbowRot", kind = "tracer", name = "Rainbow Rot", tracerColor = Color3.fromRGB(200, 90, 255), source = "Level 40" }),
		StinkSparkle = table.freeze({ id = "StinkSparkle", kind = "tracer", name = "Stink Sparkle", tracerColor = Color3.fromRGB(255, 120, 200), source = "Daily day 7" }),
		LuckyLime = table.freeze({ id = "LuckyLime", kind = "tracer", name = "Lucky Lime", tracerColor = Color3.fromRGB(170, 255, 120), source = "Free spin" }),
		StarterSwirl = table.freeze({ id = "StarterSwirl", kind = "tracer", name = "Starter Swirl", tracerColor = Color3.fromRGB(90, 220, 255), source = "Starter Pack" }),
		LimeTrail = table.freeze({ id = "LimeTrail", kind = "trail", name = "Lime Trail", trailColor = Color3.fromRGB(150, 255, 90), source = "Starter Pack" }),
		Toot = table.freeze({ id = "Toot", kind = "emote", name = "Toot", emoji = "💨", text = "TOOT!", free = true, source = "Everyone" }),
		VictoryToot = table.freeze({ id = "VictoryToot", kind = "emote", name = "Victory Toot", emoji = "🎺", text = "VICTORY TOOT!", source = "Starter Pack" }),
	}),
	-- Cosmetics in the order the locker shows them.
	cosmeticOrder = table.freeze({ "GoldenGas", "RainbowRot", "StinkSparkle", "LuckyLime", "StarterSwirl", "LimeTrail", "Toot", "VictoryToot" }),

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

-- XP from `level` to the next: 100 at level 1, rising on a gentle curve.
function ProgressionConfig.xpToNext(level: number): number
	return math.round((100 + 40 * (level - 1) ^ 1.25) / 10) * 10
end

return table.freeze(ProgressionConfig)
