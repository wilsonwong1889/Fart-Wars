-- Seasons (masterplan 6.3), free track only, behind FeatureFlags.SEASONS
-- (off as shipped). A season runs between real dates; players earn season
-- XP (a share of every XP they earn, plus weekly challenges) and climb
-- tiers, each paying coins, some a cosmetic. Everything is earned by
-- playing normally, nothing is for sale, and nothing changes combat. A
-- premium track would need its own decision (docs/roadmap.md).
--
-- Next season: add an entry with a new id and later dates; profiles from
-- the old season start the new one at tier 0 and keep what they earned.
export type Challenge = { id: string, text: string, stat: string, goal: number, needs: string? }
export type Tier = { coins: number, cosmetic: string?, badge: string? }
export type Season = { id: string, name: string, startsAt: number, endsAt: number }

local SeasonConfig = {}

SeasonConfig.seasons = table.freeze({
	table.freeze({
		id = "S1",
		name = "Season 1: Brainrot Rising",
		startsAt = 1793577600, -- 2 November 2026, 00:00 UTC
		endsAt = 1798416000, -- 28 December 2026, 00:00 UTC
	}),
}) :: { Season }

-- Season XP: this share of every XP point earned, and XP_PER_CHALLENGE
-- for each weekly challenge done.
SeasonConfig.XP_SHARE = 0.2
SeasonConfig.XP_PER_TIER = 750
SeasonConfig.XP_PER_CHALLENGE = 500
SeasonConfig.CHALLENGES_PER_WEEK = 3

-- The tiers: 20, coins each, a cosmetic every five, a badge at the top.
local tiers = {}
for n = 1, 20 do
	tiers[n] = { coins = 100 + 10 * n }
end
tiers[5].cosmetic = "SeasonSpark"
tiers[10].cosmetic = "SludgeTrail"
tiers[15].cosmetic = "ToxicBoom"
tiers[20].cosmetic = "BrainrotGold"
tiers[20].badge = "Season1"
SeasonConfig.tiers = table.freeze(tiers) :: { Tier }

-- The weekly challenge pool. `stat` is what counts; `needs` a system that
-- must be on for the challenge to be offered (so every challenge can be
-- done in normal play).
SeasonConfig.challenges = table.freeze({
	table.freeze({ id = "elims25", text = "Get 25 eliminations", stat = "eliminations", goal = 25 }),
	table.freeze({ id = "assists15", text = "Get 15 assists", stat = "assists", goal = 15 }),
	table.freeze({ id = "dash40", text = "Fart Dash 40 times", stat = "dashes", goal = 40 }),
	table.freeze({ id = "barrels6", text = "Blow up 6 gas barrels", stat = "barrels", goal = 6 }),
	table.freeze({ id = "minutes45", text = "Play for 45 minutes", stat = "minutes", goal = 45 }),
	table.freeze({ id = "streak5", text = "Get a 5-elimination streak", stat = "streaks", goal = 1 }),
	table.freeze({ id = "zone3", text = "Hold the plaza for 3 minutes in Gas Control", stat = "zoneSeconds", goal = 180, needs = "MODE_ROTATION" }),
}) :: { Challenge }

-- The season on at `at` (os.time), if any.
function SeasonConfig.current(seasons: { Season }, at: number): Season?
	for _, season in seasons do
		if at >= season.startsAt and at < season.endsAt then
			return season
		end
	end
	return nil
end

-- The season's week at `at`, from 1.
function SeasonConfig.week(season: Season, at: number): number
	return (at - season.startsAt) // (7 * 86400) + 1
end

-- The tier reached with `xp` season XP (0 to the number of tiers).
function SeasonConfig.tierFor(xp: number): number
	return math.min(#SeasonConfig.tiers, xp // SeasonConfig.XP_PER_TIER)
end

-- This week's challenges: the same for everyone, chosen from the ones
-- that can be done (`available(challenge)`), rotating week to week.
function SeasonConfig.weekly(season: Season, week: number, available: (Challenge) -> boolean): { Challenge }
	local pool = {}
	for _, challenge in SeasonConfig.challenges do
		if available(challenge) then
			table.insert(pool, challenge)
		end
	end
	local picked = {}
	local seed = 0
	for i = 1, #season.id do
		seed += string.byte(season.id, i)
	end
	local start = (seed + (week - 1) * SeasonConfig.CHALLENGES_PER_WEEK) % math.max(#pool, 1)
	for i = 0, math.min(SeasonConfig.CHALLENGES_PER_WEEK, #pool) - 1 do
		table.insert(picked, pool[(start + i) % #pool + 1])
	end
	return picked
end

return table.freeze(SeasonConfig)
