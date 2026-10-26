-- Prestige (masterplan 4.4 and 6.2), cosmetic only and off as shipped
-- (FeatureFlags.PRESTIGE). At level REQUIRED_LEVEL a player can start
-- again: their level, XP and coin-bought weapons reset, and so do their
-- coins, except coins bought in the store that they haven't spent. In
-- return: the rank (shown as P1, P2... next to their level), a badge per
-- rank and a cosmetic at some ranks.
--
-- What stays: every cosmetic, lifetime XP and stats, badges, weapon
-- mastery, abilities already unlocked, passes and everything bought with
-- Robux.
--
-- The earlier proposal of +10% power per prestige is NOT built: it would
-- hand veterans a lasting combat edge. POWER_BONUS is here only to record
-- that it is 0; nothing reads it, and changing that needs a balance
-- decision first (docs/roadmap.md).
local PrestigeConfig = {}

PrestigeConfig.REQUIRED_LEVEL = 50
PrestigeConfig.MAX_RANK = 10
PrestigeConfig.POWER_BONUS = 0
-- How long a preview's confirmation stays valid.
PrestigeConfig.CONFIRM_SECONDS = 60

export type Rank = { badge: string, cosmetic: string? }

-- What each rank gives.
PrestigeConfig.ranks = table.freeze({
	[1] = table.freeze({ badge = "Prestige1", cosmetic = "PrestigeFlame" }),
	[2] = table.freeze({ badge = "Prestige2" }),
	[3] = table.freeze({ badge = "Prestige3", cosmetic = "PrestigeTrail" }),
	[4] = table.freeze({ badge = "Prestige4" }),
	[5] = table.freeze({ badge = "Prestige5", cosmetic = "CrownToot" }),
	[6] = table.freeze({ badge = "Prestige6" }),
	[7] = table.freeze({ badge = "Prestige7" }),
	[8] = table.freeze({ badge = "Prestige8" }),
	[9] = table.freeze({ badge = "Prestige9" }),
	[10] = table.freeze({ badge = "Prestige10" }),
}) :: { [number]: Rank }

-- "P3", or "" before the first prestige.
function PrestigeConfig.tag(rank: number?): string
	return if rank and rank > 0 then `P{rank}` else ""
end

return table.freeze(PrestigeConfig)
