-- Roblox badges and the beta window, behind FeatureFlags.BADGES
-- (AchievementService awards them, on the server).
--
-- Each badge is made once in the Creator Hub (the experience > Engagement >
-- Badges > Create a Badge), with the name and description below and a
-- 512 x 512 image; then its ID goes in `id` here. While an ID is 0 that
-- badge is never awarded (players still earn it, and get it once the ID is
-- set) and /fw selftest warns.
--
-- The beta: anyone who plays (spawns onto the field) between BETA_FIRST_DAY
-- and BETA_LAST_DAY, both included, in UTC, is a Beta Tester once: the
-- Beta Tester badge and BETA_COSMETIC, which nothing sells and nothing else
-- gives (but the admin code, which never works on the live place).
export type Badge = {
	key: string,
	-- The Roblox badge ID (0 until it's made).
	id: number,
	-- What to type in the Creator Hub.
	name: string,
	description: string,
	-- How it's earned, for the selftest and the docs.
	how: string,
	-- Level badges: the level that earns them.
	level: number?,
}

local BadgeConfig = {}

BadgeConfig.badges = table.freeze({
	BetaTester = table.freeze({
		key = "BetaTester",
		id = 0,
		name = "Beta Tester",
		description = "OG STINKER! Played Fart Wars during the PC beta. Respect the gas.",
		how = "play during the beta",
	}),
	FirstElimination = table.freeze({
		key = "FirstElimination",
		id = 0,
		name = "First Gassing",
		description = "BRO GASSED SOMEONE! Your first elimination. It only gets stinkier from here.",
		how = "a first elimination of a player",
	}),
	FirstChain = table.freeze({
		key = "FirstChain",
		id = 0,
		name = "Chain Reaction",
		description = "ONE FART SET OFF ANOTHER! An elimination by a chain reaction or a gas barrel.",
		how = "a first chain or barrel elimination",
	}),
	Level10 = table.freeze({
		key = "Level10",
		id = 0,
		name = "Level 10 Tooter",
		description = "REACHED LEVEL 10! The gas is getting serious.",
		how = "reach level 10",
		level = 10,
	}),
	Level25 = table.freeze({
		key = "Level25",
		id = 0,
		name = "Level 25 Stink Veteran",
		description = "LEVEL 25! Certified stink veteran. Your teammates can smell the experience.",
		how = "reach level 25",
		level = 25,
	}),
	Level50 = table.freeze({
		key = "Level50",
		id = 0,
		name = "Level 50 Alpha Farter",
		description = "MAXED OUT AT LEVEL 50! BRO IS THE ALPHA FARTER.",
		how = "reach level 50",
		level = 50,
	}),
}) :: { [string]: Badge }
-- In the order the selftest lists them.
BadgeConfig.order = table.freeze({ "BetaTester", "FirstElimination", "FirstChain", "Level10", "Level25", "Level50" })

-- The beta window (UTC dates, both days included). Placeholders until the
-- beta's real dates are known: set them before it opens.
BadgeConfig.BETA_FIRST_DAY = "2026-11-01"
BadgeConfig.BETA_LAST_DAY = "2027-01-31"
-- The beta's cosmetic (ProgressionConfig): a boom, never sold.
BadgeConfig.BETA_COSMETIC = "BetaBoom"

-- A badge Roblox didn't take is tried again this long after, at most
-- RETRY_ATTEMPTS times a session; still not through, it waits for the
-- player's next visit.
BadgeConfig.RETRY_SECONDS = 60
BadgeConfig.RETRY_ATTEMPTS = 5

-- The favorite prompt: once ever, after the player's first round win or
-- this many minutes of active play, whichever comes first; shown between
-- rounds or on the home screen, never mid-fight.
BadgeConfig.FAVORITE_MINUTES = 10

-- Unix time at 00:00 UTC on `date` ("YYYY-MM-DD").
function BadgeConfig.utc(date: string): number
	local y, m, d = string.match(date, "^(%d%d%d%d)-(%d%d)-(%d%d)$")
	assert(y and m and d, `"{date}" isn't a YYYY-MM-DD date`)
	local year, month, day = tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number
	assert(month >= 1 and month <= 12 and day >= 1 and day <= 31, `"{date}" isn't a real date`)
	-- Days since 1970-01-01 in the proleptic Gregorian calendar, counting
	-- years from March so the leap day comes last.
	if month <= 2 then
		year -= 1
	end
	local era = year // 400
	local yearOfEra = year - era * 400
	local dayOfYear = (153 * ((month + 9) % 12) + 2) // 5 + day - 1
	local dayOfEra = yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
	return (era * 146097 + dayOfEra - 719468) * 86400
end

-- The beta window as Unix times: from its first second to the first
-- second after it.
function BadgeConfig.betaWindow(): (number, number)
	return BadgeConfig.utc(BadgeConfig.BETA_FIRST_DAY), BadgeConfig.utc(BadgeConfig.BETA_LAST_DAY) + 86400
end

-- Whether `at` (Unix time) is in the beta.
function BadgeConfig.inBeta(at: number): boolean
	local opens, closes = BadgeConfig.betaWindow()
	return at >= opens and at < closes
end

return table.freeze(BadgeConfig)
