-- The weekly leaderboard (FeatureFlags.LEADERBOARD; LeaderboardService and
-- LeaderboardController): this week's most eliminations and most round
-- wins, from Monday 00:00 UTC to the next Monday. Each board keeps one
-- OrderedDataStore per week, named for the board and the week's Monday
-- ("FartWarsTop_Eliminations_2026-11-09"), so a new week starts from zero
-- without anything being cleared. Key: the user ID; value: the count.
-- Only players count: never bots, kills of or by bots, or a win against a
-- side with no players in the round.
export type Board = { id: string, label: string, icon: string, color: Color3, hint: string }

local LeaderboardConfig = {}

LeaderboardConfig.STORE_PREFIX = "FartWarsTop"

-- The boards, in the order of the screen's tabs; `hint` is your own line
-- while you're not on the board yet.
LeaderboardConfig.boards = table.freeze({
	table.freeze({
		id = "Eliminations",
		label = "ELIMINATIONS",
		icon = "💨",
		color = Color3.fromRGB(150, 230, 60),
		hint = "GAS SOMEONE TO GET ON THE BOARD!",
	}),
	table.freeze({
		id = "Wins",
		label = "ROUND WINS",
		icon = "🏆",
		color = Color3.fromRGB(255, 205, 50),
		hint = "WIN A ROUND TO GET ON THE BOARD!",
	}),
}) :: { Board }

-- Rows on the screen; how far down a board is read (one GetSortedAsync
-- page, 100 at most), which is as far as an exact rank goes.
LeaderboardConfig.SHOWN = 10
LeaderboardConfig.PAGE_SIZE = 100

-- Writes go out in batches: each player's new counts wait on the server
-- and are written every FLUSH_SECONDS (one IncrementAsync per player and
-- board), when they leave and when the server shuts down.
LeaderboardConfig.FLUSH_SECONDS = 60
-- A board is read when someone looks and its copy is older than
-- CACHE_SECONDS; after a failed read, not again for RETRY_SECONDS.
LeaderboardConfig.CACHE_SECONDS = 60
LeaderboardConfig.RETRY_SECONDS = 30
-- Requests left in this server's budget (per request type) that the
-- leaderboard never uses, so other code always has some.
LeaderboardConfig.BUDGET_RESERVE = 5
-- A player asks for the screen at most once every REQUEST_SECONDS; the
-- open screen asks again every REFRESH_SECONDS.
LeaderboardConfig.REQUEST_SECONDS = 2
LeaderboardConfig.REFRESH_SECONDS = 30

local DAY = 86400

-- Weeks are numbered from the one that began on Monday 29 December 1969;
-- each starts at Monday 00:00 UTC. `at` is an os.time().
function LeaderboardConfig.week(at: number): number
	return (at // DAY + 3) // 7
end

-- When `week` starts (os.time).
function LeaderboardConfig.weekStart(week: number): number
	return (week * 7 - 3) * DAY
end

-- When the boards start again after `at`: the next Monday 00:00 UTC.
function LeaderboardConfig.resetsAt(at: number): number
	return LeaderboardConfig.weekStart(LeaderboardConfig.week(at) + 1)
end

-- The OrderedDataStore holding `board` for `week`.
function LeaderboardConfig.storeName(board: string, week: number): string
	local monday = os.date("!*t", LeaderboardConfig.weekStart(week)) :: any
	return string.format("%s_%s_%04d-%02d-%02d", LeaderboardConfig.STORE_PREFIX, board, monday.year, monday.month, monday.day)
end

return table.freeze(LeaderboardConfig)
