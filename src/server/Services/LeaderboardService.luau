-- The weekly leaderboard (LeaderboardConfig), behind FeatureFlags.LEADERBOARD:
-- each player's eliminations and round wins this week, in one
-- OrderedDataStore per board and week.
--   * what counts: an elimination that scored for the round, for the player
--     who got it; a round win for each player on the winning team who
--     played in the round, if a player on the other side played in it too.
--     Bots never count, and neither do kills of or by bots
--     (EliminationService fires Eliminated for players only, with no killer
--     when a bot got the kill), nor Studio's test players (negative IDs).
--   * writes, in batches: counts wait here under the week they were earned
--     in, and go out as one IncrementAsync per player and board every
--     FLUSH_SECONDS, when the player leaves and at shutdown. A count is
--     taken out while it's written, so two writes never send it twice, and
--     put back if the write fails.
--   * reads, on demand and cached: a board's top PAGE_SIZE is read when
--     someone looks and this server's copy is older than CACHE_SECONDS
--     (after a failed read, not again for RETRY_SECONDS). A player's own
--     score is looked up only when the board runs past one page and they're
--     not on it. Counts still waiting show at once for players on this
--     server.
--   * budgets: a request is sent only while this server's budget for its
--     type is above BUDGET_RESERVE; otherwise it waits for the next flush or
--     look.
--   * failures: Studio without API access (or a place never published) stops
--     every request on this server; other errors are counted and retried.
--     Either way the game goes on, nothing warns, and the screen says the
--     leaderboard is napping rather than showing anything wrong.
--   LeaderboardRequest (RemoteFunction): () -> View
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local RateLimit = require(Server.RateLimit)
local TeamService = require(script.Parent.TeamService)
local EliminationService = require(script.Parent.EliminationService)
local RoundService = require(script.Parent.RoundService)

local LeaderboardService = {}

export type Row = { rank: number, userId: number, name: string, value: number, you: boolean }
-- The viewer's own line: their count (nil if it couldn't be found) and
-- rank (nil with a count of 0, or below the top PAGE_SIZE: `beyond`).
export type You = { value: number?, rank: number?, beyond: boolean }
export type BoardView = { id: string, napping: boolean, top: { Row }, you: You }
export type View = {
	ok: boolean,
	-- Why not: "off", "tooFast" or "error".
	reason: string?,
	week: number,
	resetsAt: number,
	serverNow: number,
	boards: { [string]: BoardView },
}

type Counts = { [number]: number }
-- week -> board -> user ID -> count
type Weekly = { [number]: { [string]: Counts } }
type Entry = { userId: number, value: number }
type Page = { week: number, entries: { Entry }, full: boolean, lowest: number, readAt: number }

local BOARDS: { [string]: boolean } = {}
for _, board in LeaderboardConfig.boards do
	BOARDS[board.id] = true
end

-- Counts not yet written; counts being written; the highest stored total
-- seen for each player (from reads and writes).
local pending: Weekly = {}
local writing: Weekly = {}
local stored: Weekly = {}
-- This server's copy of each board (this week's), reads under way, and
-- when a read last failed.
local pages: { [string]: Page } = {}
local reading: { [string]: boolean } = {}
local failedReadAt: { [string]: number } = {}
local names: { [number]: string } = {}
-- DataStores can't be reached from this server at all.
local unavailable = false
local flushing = false
local testStore: ((board: string, week: number) -> any)? = nil
local clock: () -> number = os.time
local budget: (Enum.DataStoreRequestType) -> number = function(kind)
	local ok, left = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
	return if ok and type(left) == "number" then left else math.huge
end
local enabledOverride: boolean? = nil
local limit = RateLimit.new(LeaderboardConfig.REQUEST_SECONDS)
local started = false

-- Test seams: `factory(board, week)` gives the store for a board's week in
-- place of DataStoreService's (with no budget limit unless setBudget sets
-- one); a request budget; a clock (os.time); on or off whatever the flag
-- says (nil: the flag).
function LeaderboardService.setStore(factory: (board: string, week: number) -> any)
	testStore = factory
	budget = function()
		return math.huge
	end
end
function LeaderboardService.setBudget(fn: (Enum.DataStoreRequestType) -> number)
	budget = fn
end
function LeaderboardService.setClock(fn: () -> number)
	clock = fn
end
function LeaderboardService.testEnable(enabled: boolean?)
	enabledOverride = enabled
end
-- Test seam: forgets every count, copy and name, and tries DataStores again.
function LeaderboardService.testReset()
	table.clear(pending)
	table.clear(writing)
	table.clear(stored)
	table.clear(pages)
	table.clear(reading)
	table.clear(failedReadAt)
	table.clear(names)
	unavailable = false
end

function LeaderboardService.enabled(): boolean
	if enabledOverride ~= nil then
		return enabledOverride
	end
	return FeatureFlags.LEADERBOARD == true
end

-- Whether DataStores turned out to be out of reach on this server.
function LeaderboardService.napping(): boolean
	return unavailable
end

-- This week's number (LeaderboardConfig.week).
function LeaderboardService.week(): number
	return LeaderboardConfig.week(clock())
end

local function counts(weekly: Weekly, week: number, board: string): Counts
	local boards = weekly[week]
	if not boards then
		boards = {}
		weekly[week] = boards
	end
	local list = boards[board]
	if not list then
		list = {}
		boards[board] = list
	end
	return list
end

local function peek(weekly: Weekly, week: number, board: string, userId: number): number?
	local boards = weekly[week]
	local list = boards and boards[board]
	return list and list[userId]
end

local function bump(weekly: Weekly, week: number, board: string, userId: number, amount: number)
	local list = counts(weekly, week, board)
	local value = (list[userId] or 0) + amount
	list[userId] = if value ~= 0 then value else nil
end

local function observe(week: number, board: string, userId: number, value: number)
	local list = counts(stored, week, board)
	list[userId] = math.max(list[userId] or 0, value)
end

-- Not yet in the store: waiting, or on its way.
function LeaderboardService.unsent(userId: number, board: string, week: number?): number
	local at = week or LeaderboardService.week()
	return (peek(pending, at, board, userId) or 0) + (peek(writing, at, board, userId) or 0)
end

-- Counts `amount` (1 by default) of `board` for `player` this week.
function LeaderboardService.add(player: Player, board: string, amount: number?)
	if not (LeaderboardService.enabled() and BOARDS[board]) or unavailable or player.UserId <= 0 then
		return
	end
	bump(pending, LeaderboardService.week(), board, player.UserId, amount or 1)
	Telemetry.count(`Leaderboard.counted.{board}`)
end

local function canSend(kind: Enum.DataStoreRequestType): boolean
	return budget(kind) > LeaderboardConfig.BUDGET_RESERVE
end

local function storeFor(board: string, week: number): any
	if testStore then
		return testStore(board, week)
	end
	return DataStoreService:GetOrderedDataStore(LeaderboardConfig.storeName(board, week))
end

-- An error retrying can't fix: Studio without API access, or a place that
-- was never published (the same signs DataService reads).
local function hopeless(err: any): boolean
	local message = tostring(err)
	for _, sign in { "Studio access", "publish this place", "403" } do
		if string.find(message, sign, 1, true) then
			return true
		end
	end
	return false
end

-- A request that didn't go through: counted and logged, never warned
-- about. A hopeless one stops all requests from this server.
local function failed(what: string, err: any)
	if hopeless(err) then
		if not unavailable then
			unavailable = true
			table.clear(pending)
			Telemetry.log("Leaderboard", "unavailable", { error = tostring(err) })
		end
		return
	end
	Telemetry.log("Leaderboard", `{what}Failed`, { error = tostring(err) })
end

-- Forgets weeks before last week, which nobody sees any more (a count
-- still waiting for one is dropped, and counted).
local function prune()
	local oldest = LeaderboardService.week() - 1
	for week, boards in pending do
		if week < oldest then
			for _, list in boards do
				for _, amount in list do
					Telemetry.count("Leaderboard.dropped", amount)
				end
			end
			pending[week] = nil
		end
	end
	for week in stored do
		if week < oldest then
			stored[week] = nil
		end
	end
	for board, page in pages do
		if page.week ~= oldest + 1 then
			pages[board] = nil
		end
	end
end

-- Writes the counts waiting (everyone's, or only `userId`'s): one
-- IncrementAsync per player, board and week, oldest week first. It stops
-- at a short budget or a failed write, leaving the rest for next time.
-- Returns how many writes went through.
function LeaderboardService.flush(userId: number?): number
	if unavailable then
		return 0
	end
	prune()
	local jobs = {}
	for week, boards in pending do
		for board, list in boards do
			for id in list do
				if userId == nil or id == userId then
					table.insert(jobs, { week = week, board = board, userId = id })
				end
			end
		end
	end
	table.sort(jobs, function(a, b)
		return a.week < b.week
	end)
	local written = 0
	for _, job in jobs do
		local amount = peek(pending, job.week, job.board, job.userId) or 0
		if amount > 0 then
			if unavailable or not canSend(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
				break
			end
			bump(pending, job.week, job.board, job.userId, -amount)
			bump(writing, job.week, job.board, job.userId, amount)
			local ok, result = pcall(function()
				return storeFor(job.board, job.week):IncrementAsync(tostring(job.userId), amount)
			end)
			bump(writing, job.week, job.board, job.userId, -amount)
			if not ok then
				bump(pending, job.week, job.board, job.userId, amount)
				failed("write", result)
				break
			end
			written += 1
			local total = tonumber(result)
			if total then
				observe(job.week, job.board, job.userId, total)
			end
		end
	end
	if written > 0 then
		Telemetry.count("Leaderboard.writes", written)
	end
	return written
end

local function anyWriting(): boolean
	for _, boards in writing do
		for _, list in boards do
			if next(list) ~= nil then
				return true
			end
		end
	end
	return false
end

-- Shutdown: everything still waiting, and the writes already under way
-- (players who just left), before the server goes.
function LeaderboardService.flushAll()
	LeaderboardService.flush()
	local deadline = os.clock() + 20
	while anyWriting() and os.clock() < deadline do
		task.wait(0.1)
	end
end

-- Display names for `ids` not known yet: players here, then one batched
-- lookup, then one at a time. A name that can't be found shows as "???".
local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] and not Players:GetPlayerByUserId(id) then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				local name = info.DisplayName or info.Username
				if type(name) == "string" and name ~= "" then
					names[info.Id] = name
				end
			end
		end
	end
	for _, id in missing do
		if not names[id] then
			local found, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
			if found and type(name) == "string" then
				names[id] = name
			end
		end
	end
end

local function nameOf(userId: number): string
	local here = Players:GetPlayerByUserId(userId)
	if here then
		return here.DisplayName
	end
	return names[userId] or "???"
end

-- Reads `board`'s top for `week` into this server's copy, with the names of
-- the ones the screen shows.
local function read(board: string, week: number)
	reading[board] = true
	local ok, result = pcall(function()
		return storeFor(board, week):GetSortedAsync(false, LeaderboardConfig.PAGE_SIZE):GetCurrentPage()
	end)
	if not ok or type(result) ~= "table" then
		reading[board] = nil
		failedReadAt[board] = os.clock()
		failed("read", if ok then "no page" else result)
		return
	end
	local entries: { Entry } = {}
	local lowest = math.huge
	for _, item in result do
		local userId = type(item) == "table" and tonumber(item.key)
		local value = type(item) == "table" and tonumber(item.value)
		if userId and userId > 0 and value and value >= 1 then
			value = math.floor(value)
			table.insert(entries, { userId = userId, value = value })
			lowest = math.min(lowest, value)
			observe(week, board, userId, value)
		end
	end
	local shown = {}
	for i = 1, math.min(#entries, LeaderboardConfig.SHOWN) do
		table.insert(shown, entries[i].userId)
	end
	resolveNames(shown)
	pages[board] = {
		week = week,
		entries = entries,
		full = #result >= LeaderboardConfig.PAGE_SIZE,
		lowest = if #entries > 0 then lowest else 0,
		readAt = os.clock(),
	}
	failedReadAt[board] = nil
	reading[board] = nil
	Telemetry.count("Leaderboard.reads")
end

-- This server's copy of `board` for `week`, read again first if it's old
-- (unless a read failed a moment ago or the budget is short: then the old
-- copy). Nil while there's no copy of this week's at all.
local function pageFor(board: string, week: number): Page?
	local page = pages[board]
	local current = page ~= nil and page.week == week
	if unavailable or (current and os.clock() - (page :: Page).readAt < LeaderboardConfig.CACHE_SECONDS) then
		return if current then page else nil
	end
	if reading[board] then
		local deadline = os.clock() + 10
		while reading[board] and os.clock() < deadline do
			task.wait(0.1)
		end
	else
		local failedAt = failedReadAt[board]
		local resting = failedAt ~= nil and os.clock() - failedAt < LeaderboardConfig.RETRY_SECONDS
		if not resting and canSend(Enum.DataStoreRequestType.GetSortedAsync) then
			read(board, week)
		end
	end
	page = pages[board]
	return if page and page.week == week then page else nil
end

-- The stored total for `userId` as far as this server can tell without
-- asking: seen in a read or a write, or 0 when the whole board fits in the
-- page and they're not on it. Nil when it can't tell.
local function known(board: string, week: number, userId: number, page: Page): number?
	local value = peek(stored, week, board, userId)
	if value == nil and not page.full then
		value = 0
	end
	return value
end

-- Looks up the viewer's own stored total (the board runs past the page and
-- they're not on it).
local function lookup(board: string, week: number, userId: number)
	if unavailable or not canSend(Enum.DataStoreRequestType.GetAsync) then
		return
	end
	local ok, result = pcall(function()
		return storeFor(board, week):GetAsync(tostring(userId))
	end)
	if not ok then
		failed("lookup", result)
		return
	end
	observe(week, board, userId, math.max(0, math.floor(tonumber(result) or 0)))
end

-- One board as `player` sees it: the top SHOWN (ties share a rank) and
-- their own line. The stored copy, with the counts of players on this
-- server brought up to date.
local function boardView(player: Player, board: string, week: number): BoardView
	local page = pageFor(board, week)
	if not page then
		return { id = board, napping = true, top = {}, you = { beyond = false } }
	end
	local me = player.UserId
	if page.full and peek(stored, week, board, me) == nil then
		lookup(board, week, me)
	end
	local values: { [number]: number } = {}
	for _, entry in page.entries do
		values[entry.userId] = entry.value
	end
	for _, here in Players:GetPlayers() do
		local base = known(board, week, here.UserId, page)
		if base then
			local value = math.max(base, values[here.UserId] or 0) + LeaderboardService.unsent(here.UserId, board, week)
			if value > 0 then
				values[here.UserId] = value
			end
		end
	end
	local list: { Entry } = {}
	for userId, value in values do
		table.insert(list, { userId = userId, value = value })
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	local top: { Row } = {}
	local rank = 0
	for i = 1, math.min(#list, LeaderboardConfig.SHOWN) do
		local entry = list[i]
		if i == 1 or entry.value ~= list[i - 1].value then
			rank = i
		end
		table.insert(top, { rank = rank, userId = entry.userId, name = nameOf(entry.userId), value = entry.value, you = entry.userId == me })
	end
	local you: You
	local mine = values[me]
	if mine then
		if page.full and mine < page.lowest then
			-- Below the page: others the page doesn't hold could be ahead.
			you = { value = mine, beyond = true }
		else
			local ahead = 0
			for _, entry in list do
				if entry.value > mine then
					ahead += 1
				end
			end
			you = { value = mine, rank = ahead + 1, beyond = false }
		end
	elseif known(board, week, me, page) ~= nil then
		you = { value = 0, beyond = false }
	else
		-- Not on a full page, and the lookup didn't answer.
		you = { beyond = true }
	end
	return { id = board, napping = false, top = top, you = you }
end

-- The boards this match mode can fill (continuous play has no rounds to win).
local function boardsInPlay(): { string }
	local ids = {}
	for _, board in LeaderboardConfig.boards do
		if board.id ~= "Wins" or FeatureFlags.MATCH_MODE ~= "Continuous" then
			table.insert(ids, board.id)
		end
	end
	return ids
end

-- What the leaderboard screen shows `player`.
function LeaderboardService.view(player: Player): View
	local now = clock()
	local week = LeaderboardConfig.week(now)
	local view: View = {
		ok = LeaderboardService.enabled(),
		reason = nil,
		week = week,
		resetsAt = LeaderboardConfig.resetsAt(now),
		serverNow = now,
		boards = {},
	}
	if not view.ok then
		view.reason = "off"
		return view
	end
	for _, board in boardsInPlay() do
		view.boards[board] = boardView(player, board, week)
	end
	return view
end

-- A round's win, for the players on the winning team who played in it: as
-- long as a player on another team played in it too (a win over bots alone
-- doesn't count).
local function countWins(result: any)
	if type(result) ~= "table" or result.draw or type(result.winner) ~= "string" then
		return
	end
	local played = RoundService.lastParticipation()
	local winners, opponents = {}, 0
	for _, team in TeamConfig.order do
		for _, member in TeamService.members(team) do
			if (played[member.UserId] or 0) > 0 then
				if team == result.winner then
					table.insert(winners, member)
				else
					opponents += 1
				end
			end
		end
	end
	if #winners > 0 and opponents == 0 then
		Telemetry.count("Leaderboard.winsOverBots")
		return
	end
	for _, winner in winners do
		LeaderboardService.add(winner, "Wins")
	end
end

local function request(player: Player): View
	if not limit:allow(player, "view") then
		local now = clock()
		return { ok = false, reason = "tooFast", week = LeaderboardConfig.week(now), resetsAt = LeaderboardConfig.resetsAt(now), serverNow = now, boards = {} }
	end
	return LeaderboardService.view(player)
end

function LeaderboardService.start()
	if started then
		return
	end
	started = true
	EliminationService.Eliminated:Connect(function(elimination)
		local killer = elimination.killer
		if elimination.counted and killer and killer ~= elimination.victim and elimination.cause ~= "test" then
			LeaderboardService.add(killer, "Eliminations")
		end
	end)
	RoundService.PhaseChanged:Connect(function(phase, snapshot)
		if phase == States.Phase.RESULTS then
			countWins(snapshot and snapshot.result)
		end
	end)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LeaderboardRequest") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player)
		Telemetry.count("remote.in.LeaderboardRequest")
		local ok, answer = pcall(request, player)
		if not ok then
			Telemetry.error("Leaderboard", answer)
			local now = clock()
			return { ok = false, reason = "error", week = LeaderboardConfig.week(now), resetsAt = LeaderboardConfig.resetsAt(now), serverNow = now, boards = {} }
		end
		return answer
	end
	Players.PlayerRemoving:Connect(function(player)
		limit:forget(player)
		task.spawn(LeaderboardService.flush, player.UserId)
	end)
	-- The batch: one flush a FLUSH_SECONDS, never two at once.
	Health.loop("Leaderboard", LeaderboardConfig.FLUSH_SECONDS, function()
		if flushing then
			return
		end
		flushing = true
		task.spawn(function()
			local ok, err = pcall(LeaderboardService.flush)
			flushing = false
			if not ok then
				error(err, 0)
			end
		end)
	end)
	game:BindToClose(LeaderboardService.flushAll)
end

return LeaderboardService
