-- The weekly leaderboard (LeaderboardService, LeaderboardController), with
-- one client, against a stand-in OrderedDataStore that sorts like the real
-- one and can fail on demand:
--   * weeks: Monday 00:00 UTC starts one; their numbers, store names and
--     the countdown's words
--   * Studio without API access: nothing is sent without a budget, a
--     refused request stops them all, nothing is counted from then on, the
--     boards nap and nothing warns
--   * what counts, from real play: a player's eliminations that scored;
--     never kills of or by bots, test eliminations, Studio's test players
--     or one between rounds; a round win for the winning team's players
--     who played, not against bots alone; nothing while switched off
--   * batching: counts wait, then go out as one write per player and board
--     a flush (never one a kill), nothing while the budget is down to the
--     reserve, the flush on its own every minute, leaving and shutdown
--   * reading: once per board a minute however many look, and only when
--     someone does; the top 10 with names and shared ranks for ties;
--     counts still waiting shown at once for players here, other servers'
--     at the next read; your rank on the page, past it (looked up once),
--     or not on the board yet; one request every two seconds a player
--   * failures: an outage keeps a write's count for the next flush and an
--     old copy up through a failed read (not retried at once); with no
--     copy, the board naps
--   * a new week: counts from before Monday go to last week's store, even
--     when written after; the new boards start empty; counts from weeks
--     back are dropped
--   * the screen: TOP opens it (the M menu too), rows with avatars and
--     ranks, your line, the tabs, the countdown, the nap; Space doesn't
--     PLAY under it, a click stays on it, and PLAY closes it
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
-- No bots of the director's: this spec brings its own.
require(server.Services.BotDirector).testSetEnabled(false)
local Shared = ReplicatedStorage.Shared
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Config = require(Shared.Config.LeaderboardConfig)
local Data = require(server.Services.DataService)
local Board = require(server.Services.LeaderboardService)
local Bots = require(server.Services.BotService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Elimination = require(server.Services.EliminationService)
local AFK = require(server.Services.AFKService)
local Round = require(server.Services.RoundService)
local Scores = require(server.Services.MatchScoreService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes

local saved = {}
Data.setStore({
	UpdateAsync = function(_, key, transform)
		local result = transform(saved[key])
		if result ~= nil then
			saved[key] = result
		end
		return result
	end,
})
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function quiet(): boolean
	return (Telemetry.snapshot().errors.Leaderboard or 0) == 0
end

-- The leaderboard's clock: Thursday 5 November 2026, 12:00:30 UTC.
local MONDAY = 1793577600 -- 2 November 2026, 00:00 UTC
local now = MONDAY + 3 * 86400 + 12 * 3600 + 30
Board.setClock(function()
	return now
end)
local WEEK = Config.week(now)

-- Weeks.
check(WEEK == 2966 and Config.week(MONDAY) == 2966 and Config.week(MONDAY - 1) == 2965, "a week starts on Monday 00:00 UTC; Sunday 23:59:59 is the week before")
check(Config.weekStart(WEEK) == MONDAY and Config.resetsAt(now) == MONDAY + 7 * 86400, "and runs to the next Monday")
check(Config.week(0) == 0 and Config.weekStart(0) == -3 * 86400, "week 0 began on Monday 29 December 1969")
check(Config.storeName("Eliminations", WEEK) == "FartWarsTop_Eliminations_2026-11-02", "one store per board and week, named for its Monday")
check(Config.storeName("Wins", WEEK + 1) == "FartWarsTop_Wins_2026-11-09", "the next week's")
check(Config.SHOWN == 10 and Config.PAGE_SIZE <= 100 and Config.FLUSH_SECONDS >= 30 and Config.CACHE_SECONDS >= 30, "the top 10; one page; writes and reads at most once a half minute")
check(FeatureFlags.LEADERBOARD == true and Board.enabled(), "on as shipped")

-- The players: me (this client), my foe, and Cy, who stays on the home screen.
local me = Instance.new("Player")
me.Name = "Ada"
me.DisplayName = "Ada"
me.UserId = 101
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
local Screen = require(client.Controllers.LeaderboardController)
local home = require(client.Controllers.HomeController).parts
local MouseLock = require(client.MouseLock)
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local foe = join("Bo", 102)
local cy = join("Cy", 103)
task.wait(0.5)
local function click(button: Instance)
	(button :: GuiButton).Activated:Fire()
	task.wait(0.05)
end
local function awake()
	for _, player in Players:GetPlayers() do
		AFK.markActive(player)
	end
end
local function pause(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		awake()
		task.wait(math.min(1, deadline - os.clock()))
	end
	awake()
end

-- Studio without API access: the stand-in world's DataStoreService has no
-- budget and refuses every request, as Studio does.
local view = Board.view(me)
check(view.ok and view.boards.Eliminations.napping and view.boards.Wins.napping, "no budget: nothing is read, and the boards nap")
check(Board.flush() == 0, "nor written")
local refused = 0
Board.setStore(function()
	local function no()
		refused += 1
		error("502: API Services rejected request with error. Error code: 7 Reason: Studio access to APIs is not allowed.")
	end
	return { IncrementAsync = no, GetSortedAsync = no, GetAsync = no }
end)
view = Board.view(me)
check(view.ok and view.boards.Eliminations.napping and view.boards.Wins.napping and refused == 1, "refused: the boards nap after one request")
check(Board.napping() and counter("Leaderboard.unavailable") == 1, "and this server stops asking")
Board.add(me, "Eliminations")
check(Board.unsent(me.UserId, "Eliminations") == 0, "nothing is counted from then on")
check(Board.flush() == 0 and Board.view(foe).boards.Wins.napping and refused == 1, "no more requests, writes or reads")
check(quiet(), "and nothing warns or counts as an error")
Screen.open()
task.wait(0.1)
local parts = Screen.parts
check(parts.screen.Enabled and parts.nap.Visible and parts.nap.Title.Text == Screen.TEXT.nap, "the screen: LEADERBOARD IS TAKING A NAP")
check(Screen.TEXT.nap == "LEADERBOARD IS TAKING A NAP" and not parts.list.Visible and not parts.you.Visible, "with no rows")
Screen.close()
check(not parts.screen.Enabled and not MouseLock.holds("Leaderboard"), "and closes")

-- A store that works.
Board.testReset()
type Item = { key: string, value: number }
local stores: { [string]: { [string]: number } } = {}
local calls = { IncrementAsync = 0, GetSortedAsync = 0, GetAsync = 0 }
local writes: { { store: string, key: string, delta: number } } = {}
local failWith: string? = nil
local latency = 0
local function data(board: string, week: number): { [string]: number }
	local name = Config.storeName(board, week)
	stores[name] = stores[name] or {}
	return stores[name]
end
Board.setStore(function(board: string, week: number)
	local name = Config.storeName(board, week)
	local values = data(board, week)
	local store = {}
	function store:IncrementAsync(key: string, delta: number): number
		calls.IncrementAsync += 1
		if latency > 0 then
			task.wait(latency)
		end
		if failWith then
			error(failWith)
		end
		assert(type(key) == "string" and tonumber(key) and delta == math.floor(delta), "a user ID and a whole number")
		values[key] = (values[key] or 0) + delta
		table.insert(writes, { store = name, key = key, delta = delta })
		return values[key]
	end
	function store:GetSortedAsync(ascending: boolean, pageSize: number)
		calls.GetSortedAsync += 1
		if failWith then
			error(failWith)
		end
		local items: { Item } = {}
		for key, value in values do
			table.insert(items, { key = key, value = value })
		end
		table.sort(items, function(a, b)
			if a.value ~= b.value then
				return if ascending then a.value < b.value else a.value > b.value
			end
			return a.key < b.key
		end)
		local page = {}
		for i = 1, math.min(#items, pageSize) do
			page[i] = items[i]
		end
		return { IsFinished = #items <= pageSize, GetCurrentPage = function()
			return page
		end }
	end
	function store:GetAsync(key: string): number?
		calls.GetAsync += 1
		if failWith then
			error(failWith)
		end
		return values[key]
	end
	return store
end)
-- Names, as Roblox's UserService gives them.
local UserService = game:GetService("UserService")
local lookups = 0
UserService.GetUserInfosByUserIdsAsync = function(_, ids: { number })
	lookups += 1
	local infos = {}
	for _, id in ids do
		table.insert(infos, { Id = id, Username = `user{id}`, DisplayName = `Stinker{id}` })
	end
	return infos
end
local function writesTo(board: string, week: number, userId: number): { number }
	local list = {}
	for _, write in writes do
		if write.store == Config.storeName(board, week) and write.key == tostring(userId) then
			table.insert(list, write.delta)
		end
	end
	return list
end

-- What counts, from real play. The budget is held at nothing meanwhile,
-- so nothing goes out until it's back.
Board.setBudget(function()
	return 0
end)
local seen: { Elimination.Elimination } = {}
Elimination.Eliminated:Connect(function(elimination)
	table.insert(seen, elimination)
end)
Lifecycle.requestPlay(me, "Stinkers")
Lifecycle.requestPlay(foe, "Sharters")
pause(1)
check(Round.phase() == "ACTIVE" and me:GetAttribute("TeamId") == "Stinkers" and foe:GetAttribute("TeamId") == "Sharters", "a round, Ada against Bo")
-- Waits until `player` is back in a living avatar, and ends their protection.
local function alive(player: Player)
	for _ = 1, 40 do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not Gas.isExploding(player) and Lifecycle.stateOf(player) == "ACTIVE" then
			break
		end
		pause(0.25)
	end
	Lifecycle.endProtection(player)
end
-- A bot on Bo's team, standing in the middle of the map.
local toots = Bots.add("Sharters", "Toots")
local body = Instance.new("Model")
body.Name = toots.name
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(0, 3, 0)
root.Parent = body
local head = Instance.new("Part")
head.Name = "Head"
head.Size = Vector3.new(2, 1, 1)
head.CFrame = CFrame.new(0, 4.5, 0)
head.Parent = body
Instance.new("Humanoid").Parent = body
body.PrimaryPart = root
body.Parent = workspace
Bots.attach(toots, body)
Bots.endProtection(toots)

alive(foe)
check(Gas.add(foe, 100, { attacker = me, cause = "shot", weapon = "GasBlaster" }), "Ada gasses Bo out")
pause(1.5)
local last = seen[#seen]
check(last and last.victim == foe and last.killer == me and last.counted, "an elimination that scored")
check(Board.unsent(me.UserId, "Eliminations") == 1 and Board.unsent(foe.UserId, "Eliminations") == 0, "counts for Ada, waiting on the server")
alive(me)
local before = #seen
check(Gas.add(me, 100, { team = "Sharters", bot = toots.id, cause = "shot", weapon = "GasBlaster" }), "Toots, a bot, gasses Ada out")
pause(1.5)
last = seen[#seen]
check(#seen == before + 1 and last.victim == me and last.killer == nil and last.killerBot == toots.id, "a bot's kill: no killer")
check(Board.unsent(me.UserId, "Eliminations") == 1, "so it counts for nobody")
alive(me)
before = #seen
check(Bots.addGas(toots, 100, { attacker = me, cause = "shot", weapon = "GasBlaster" }), "Ada gasses Toots out")
pause(1.5)
check(not Bots.isAlive(toots) and #seen == before, "a bot's death: no Eliminated")
check(Board.unsent(me.UserId, "Eliminations") == 1, "and no count")
alive(foe)
Elimination.eliminate(foe, foe.Character, { killer = me, cause = "test" })
last = seen[#seen]
check(last.killer == me and last.cause == "test" and last.counted, "a test elimination")
check(Board.unsent(me.UserId, "Eliminations") == 1, "doesn't count")
Board.add({ UserId = -1 } :: any, "Eliminations")
check(Board.unsent(-1, "Eliminations") == 0, "nor do Studio's test players")
Board.testEnable(false)
Board.add(me, "Eliminations")
check(Board.unsent(me.UserId, "Eliminations") == 1 and Board.view(me).reason == "off", "switched off: nothing counts or shows")
Board.testEnable(nil)
check(calls.IncrementAsync == 0 and calls.GetSortedAsync == 0, "nothing sent yet: no budget")

-- Batching.
Board.setBudget(function()
	return Config.BUDGET_RESERVE
end)
check(Board.flush() == 0 and calls.IncrementAsync == 0, "with the budget down to the reserve, nothing goes out")
Board.setBudget(function()
	return Config.BUDGET_RESERVE + 1
end)
check(Board.flush() == 1 and calls.IncrementAsync == 1, "above it: one write")
check(data("Eliminations", WEEK)["101"] == 1 and Board.unsent(me.UserId, "Eliminations") == 0, "Ada's elimination is stored")
for _ = 1, 20 do
	Board.add(me, "Eliminations")
end
check(calls.IncrementAsync == 1 and Board.unsent(me.UserId, "Eliminations") == 20, "20 eliminations: still waiting, no write each")
check(Board.flush() == 1 and calls.IncrementAsync == 2, "one flush: one write")
local mine = writesTo("Eliminations", WEEK, me.UserId)
check(#mine == 2 and mine[2] == 20 and data("Eliminations", WEEK)["101"] == 21, "of all 20 at once")
check(Board.flush() == 0 and calls.IncrementAsync == 2, "nothing waiting: nothing sent")
Board.add(me, "Eliminations")
pause(Config.FLUSH_SECONDS + 1)
check(Board.unsent(me.UserId, "Eliminations") == 0 and data("Eliminations", WEEK)["101"] == 22, "the flush goes out on its own every minute")
check(calls.GetSortedAsync == 0, "and nobody looked, so nothing was read")

-- Round wins.
alive(foe)
check(Scores.testAddElimination("Stinkers", 5) and Round.testEndPhaseIn(0), "Ada's team pulls ahead and the round ends")
pause(0.5)
local result = Round.snapshot().result
check(Round.phase() == "RESULTS" and result and result.winner == "Stinkers", "the Stinkers win")
check(Board.unsent(me.UserId, "Wins") == 1, "a win for Ada, who played")
check(Board.unsent(foe.UserId, "Wins") == 0 and Board.unsent(cy.UserId, "Wins") == 0, "none for Bo (lost) or Cy (didn't play)")
before = #seen
Elimination.eliminate(foe, foe.Character, { killer = me, cause = "shot" })
check(#seen == before + 1 and not seen[#seen].counted, "an elimination between rounds doesn't score")
check(Board.unsent(me.UserId, "Eliminations") == 0, "nor count")
Lifecycle.requestSpectate(foe)
for _ = 1, 40 do
	if Round.phase() == "ACTIVE" then
		break
	end
	pause(1)
end
check(Round.phase() == "ACTIVE" and Lifecycle.stateOf(foe) ~= "ACTIVE", "a new round: Ada against Toots's team alone")
pause(2)
check(Scores.testAddElimination("Stinkers", 2) and Round.testEndPhaseIn(0), "the Stinkers win again")
pause(0.5)
check(Round.phase() == "RESULTS" and Round.snapshot().result.winner == "Stinkers", "over a team of bots")
check(Board.unsent(me.UserId, "Wins") == 1 and counter("Leaderboard.winsOverBots") == 1, "a win over bots alone doesn't count")
Board.flush()
check(data("Wins", WEEK)["101"] == 1 and Board.unsent(me.UserId, "Wins") == 0, "Ada's one win is stored")

-- Reading. Others on the board, from other servers.
local elims = data("Eliminations", WEEK)
for i, value in { 50, 40, 40, 30, 25, 20, 15, 12, 10, 8, 5, 3 } do
	elims[tostring(2000 + i)] = value
end
local wins = data("Wins", WEEK)
for i = 1, 120 do
	wins[tostring(3000 + i)] = i + 1
end
-- Dee won a round on another server earlier this week.
wins["104"] = 1
local sorted = calls.GetSortedAsync
view = Board.view(me)
check(calls.GetSortedAsync == sorted + 2, "a look reads each board once")
local top = view.boards.Eliminations.top
check(#top == 10 and not view.boards.Eliminations.napping, "the top 10")
check(top[1].userId == 2001 and top[1].value == 50 and top[1].rank == 1 and top[1].name == "Stinker2001", "first, by display name")
check(top[2].rank == 2 and top[3].rank == 2 and top[4].rank == 4, "a tie shares its rank, and the next rank skips")
check(top[6].userId == me.UserId and top[6].value == 22 and top[6].you and top[6].name == "Ada", "Ada, sixth with 22")
check(top[10].userId == 2009 and top[10].value == 10, "down to tenth")
local you = view.boards.Eliminations.you
check(you.rank == 6 and you.value == 22 and not you.beyond, "Ada's own line: sixth")
check(lookups == 2, "the names are looked up once a read, in one batch")
check(calls.GetAsync == 0, "Ada's own counts were known already (from her writes)")
view = Board.view(cy)
check(calls.GetSortedAsync == sorted + 2, "another look straight after reads nothing")
check(view.boards.Eliminations.you.value == 0 and view.boards.Eliminations.you.rank == nil, "Cy isn't on the board yet")
check(calls.GetAsync == 1 and view.boards.Wins.you.value == 0, "Cy's wins: looked up, as that board runs past one page")
Board.add(me, "Eliminations", 9)
view = Board.view(me)
top = view.boards.Eliminations.top
check(calls.GetSortedAsync == sorted + 2 and top[4].userId == me.UserId and top[4].value == 31, "Ada's new eliminations show at once, still waiting to be written")
check(view.boards.Eliminations.you.rank == 4, "and move her up")
elims["2010"] = 99
check(Board.view(me).boards.Eliminations.top[1].userId == 2001, "another server's new count waits for the next read")
-- The wins board runs past one page.
you = view.boards.Wins.you
check(you.beyond and you.rank == nil and you.value == 1, "Ada's one win: past the top 100")
check(calls.GetAsync == 1, "without a lookup")
local dee = join("Dee", 104)
task.wait(0.1)
view = Board.view(dee)
check(calls.GetAsync == 2 and view.boards.Wins.you.beyond and view.boards.Wins.you.value == 1, "Dee's win from earlier this week: looked up")
view = Board.view(dee)
check(calls.GetAsync == 2, "once")
check(view.boards.Wins.top[1].value == 121 and #view.boards.Wins.top == 10, "the wins board's top 10")
pause(Config.CACHE_SECONDS + 1)
check(calls.GetSortedAsync == sorted + 2, "a minute without looking: no reads")
view = Board.view(me)
check(calls.GetSortedAsync == sorted + 4, "the next look reads again")
check(view.boards.Eliminations.top[1].userId == 2010 and view.boards.Eliminations.top[1].value == 99, "with the other server's count")
local answer = Remotes.LeaderboardRequest:InvokeServer()
local again = Remotes.LeaderboardRequest:InvokeServer()
check(answer.ok and answer.boards.Eliminations and again.reason == "tooFast", "one request every two seconds a player")

-- Failures.
Board.add(me, "Eliminations")
failWith = "503: DataStore request failed (test outage)"
local writing = calls.IncrementAsync
check(Board.flush() == 0 and calls.IncrementAsync == writing + 1, "a write fails in an outage")
check(Board.unsent(me.UserId, "Eliminations") == 1 and counter("Leaderboard.writeFailed") == 1, "the count is kept for next time")
check(not Board.napping() and quiet(), "the server keeps trying, and nothing warns")
pause(Config.CACHE_SECONDS + 1)
sorted = calls.GetSortedAsync
view = Board.view(me)
check(calls.GetSortedAsync == sorted + 2 and counter("Leaderboard.readFailed") == 2, "the reads fail too")
check(not view.boards.Eliminations.napping and view.boards.Eliminations.top[1].value == 99, "the old copy stays up")
Board.view(me)
check(calls.GetSortedAsync == sorted + 2, "a failed read isn't tried again at once")
failWith = nil
check(Board.flush() == 1 and data("Eliminations", WEEK)["101"] == 32 and Board.unsent(me.UserId, "Eliminations") == 0, "after the outage, the write goes through")
pause(Config.RETRY_SECONDS + 1)
Board.view(me)
check(calls.GetSortedAsync == sorted + 4, "and the reads, a little later")

-- The screen.
Lifecycle.requestSpectate(me)
pause(0.5)
check(home.home.Enabled and Lifecycle.stateOf(me) ~= "ACTIVE", "Ada back on the home screen")
pause(Config.REQUEST_SECONDS)
click(home.home:FindFirstChild("Leaderboard", true))
task.wait(0.2)
check(Screen.isOpen and parts.screen.Enabled and not home.comingSoon.Enabled, "TOP opens the leaderboard")
check(MouseLock.holds("Leaderboard") and MouseLock.holds("HomeScreen"), "with the mouse free")
check(parts.list.Visible and parts.you.Visible and not parts.nap.Visible and not parts.status.Visible, "rows, and Ada's line")
local row1 = parts.rows[1]
check(row1.Visible and row1.Rank.Text == "#1" and row1.PlayerName.Text == "Stinker2010" and row1.Count.Text == "99", "first: rank, name and count")
check(row1.Avatar.Image == "rbxthumb://type=AvatarHeadShot&id=2010&w=150&h=150", "with their avatar")
check(parts.rows[3].Rank.Text == "#3" and parts.rows[4].Rank.Text == "#3", "a tie, shown")
local mineRow = parts.rows[5]
check(mineRow.PlayerName.Text == "Ada (YOU)" and mineRow.Count.Text == "32" and mineRow.BackgroundColor3 ~= row1.BackgroundColor3, "Ada's row stands out")
check(parts.you.Rank.Text == "#5" and parts.you.PlayerName.Text == "YOU" and parts.you.Count.Text == "32", "and her line under the board")
check(parts.you.Avatar.Image == "rbxthumb://type=AvatarHeadShot&id=101&w=150&h=150", "with her avatar")
Screen.render()
local left = Screen.secondsLeft()
check(math.abs(left - (Config.resetsAt(now) - now)) < 2, "the countdown, on the server's clock")
check(parts.countdown.Text == string.format(Screen.TEXT.resets, Screen.countdown(left)) and string.find(parts.countdown.Text, "MONDAY 00:00 UTC", 1, true), "to Monday 00:00 UTC")
check(Screen.countdown(2 * 86400 + 4 * 3600 + 9 * 60 + 30) == "2d 04h 09m" and Screen.countdown(4 * 3600 + 570) == "4h 09m 30s", "days, hours and minutes")
check(Screen.countdown(570) == "9m 30s" and Screen.countdown(-5) == "0m 00s", "minutes and seconds; never below zero")
click(parts.tabs.Wins)
check(Screen.tab == "Wins" and parts.rows[1].Count.Text == "121", "the WINS tab")
check(parts.you.Rank.Text == "#100+" and parts.you.Count.Text == "1", "Ada's one win: past the top 100")
click(parts.tabs.Eliminations)
check(Screen.tab == "Eliminations" and parts.rows[1].Count.Text == "99", "and back")
check(parts.screen.Panel.Active, "a click on the window stays on it")
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Space, UserInputType = Enum.UserInputType.Keyboard }, false)
task.wait(0.05)
check(not home.teamSelect.Enabled and Screen.isOpen, "Space doesn't PLAY under it")
click(parts.screen:FindFirstChild("Close", true))
check(not Screen.isOpen and not MouseLock.holds("Leaderboard"), "X closes it")
-- PLAY closes it.
pause(Config.REQUEST_SECONDS)
Screen.open()
task.wait(0.2)
check(Screen.isOpen, "open over the home screen")
Lifecycle.requestPlay(me, "Stinkers")
pause(0.5)
check(Lifecycle.stateOf(me) == "ACTIVE" and not Screen.isOpen and not MouseLock.holds("Leaderboard"), "PLAY closes it and locks the mouse again")
-- From the M menu in a match.
require(client.Controllers.HomeController).setMenu(true)
click(home.menu:FindFirstChild("Leaderboard", true))
task.wait(0.2)
check(Screen.isOpen and MouseLock.holds("Leaderboard"), "the M menu's LEADERBOARD opens it in a match")
click(parts.screen:FindFirstChild("Close", true))
require(client.Controllers.HomeController).setMenu(false)

-- The week ending with the screen open and no answer from the server.
Lifecycle.requestSpectate(me)
pause(Config.REQUEST_SECONDS)
now = MONDAY + 7 * 86400 - 2 -- Sunday 8 November, 23:59:58
Screen.open()
task.wait(0.2)
check(parts.list.Visible and not parts.nap.Visible, "open two seconds before Monday")
local handler = Remotes.LeaderboardRequest.OnServerInvoke
Remotes.LeaderboardRequest.OnServerInvoke = function()
	error("no answer")
end
task.wait(3)
check(parts.nap.Visible and not parts.list.Visible, "the week over and no answer: it naps, rather than show last week's board")
Remotes.LeaderboardRequest.OnServerInvoke = handler
Screen.close()

-- A new week.
now = MONDAY + 7 * 86400 - 60 -- Sunday 8 November, 23:59
Board.add(me, "Eliminations", 2)
now = MONDAY + 7 * 86400 + 30 -- Monday 9 November, 00:00:30
check(Board.week() == WEEK + 1, "Monday: a new week")
Board.add(me, "Eliminations", 3)
check(Board.unsent(me.UserId, "Eliminations", WEEK) == 2 and Board.unsent(me.UserId, "Eliminations") == 3, "each count under the week it was earned in")
failWith = "503: DataStore request failed (test outage)"
view = Board.view(cy)
check(view.week == WEEK + 1 and view.boards.Eliminations.napping and view.boards.Wins.napping, "no copy of the new week's boards and the reads fail: they nap")
failWith = nil
-- (No budget meanwhile, so the flush on its own leaves both weeks' counts.)
Board.setBudget(function()
	return 0
end)
pause(Config.RETRY_SECONDS + 1)
Board.setBudget(function()
	return math.huge
end)
check(Board.flush() == 2, "the flush writes both weeks")
local lastWeek = writesTo("Eliminations", WEEK, me.UserId)
check(lastWeek[#lastWeek] == 2 and data("Eliminations", WEEK)["101"] == 34, "Sunday's two go to last week's store, written on Monday")
check(writesTo("Eliminations", WEEK + 1, me.UserId)[1] == 3 and data("Eliminations", WEEK + 1)["101"] == 3, "Monday's three to the new one")
view = Board.view(me)
check(view.week == WEEK + 1 and view.resetsAt == MONDAY + 14 * 86400, "counting down to the Monday after")
top = view.boards.Eliminations.top
check(#top == 1 and top[1].userId == me.UserId and top[1].value == 3 and top[1].rank == 1, "the new board starts empty: Ada first with 3")
check(#view.boards.Wins.top == 0 and view.boards.Wins.you.value == 0, "and nobody has won a round yet")
pause(Config.REQUEST_SECONDS)
Screen.open()
task.wait(0.2)
click(parts.tabs.Wins)
check(parts.status.Visible and parts.status.Text == Screen.TEXT.empty, "the screen: nobody's on it yet")
check(parts.you.Rank.Text == "—" and string.find(parts.you.PlayerName.Text, Config.boards[2].hint, 1, true), "and Ada's line says how to get on it")
click(parts.tabs.Eliminations)
Screen.close()
Board.add(me, "Eliminations")
now += 14 * 86400
local dropped = counter("Leaderboard.dropped")
writing = calls.IncrementAsync
check(Board.flush() == 0 and calls.IncrementAsync == writing, "two weeks on, a count still waiting isn't written")
check(counter("Leaderboard.dropped") == dropped + 1, "it's dropped, and counted")

-- Leaving and shutting down.
local week = Board.week()
Board.add(foe, "Eliminations", 4)
foe.Parent = nil
task.wait(0.2)
check(data("Eliminations", week)["102"] == 4 and Board.unsent(foe.UserId, "Eliminations") == 0, "leaving writes what was waiting")
Board.add(cy, "Eliminations", 1)
latency = 2
task.spawn(Board.flush, cy.UserId)
task.wait(0.1)
local started = os.clock()
Board.flushAll()
check(os.clock() - started >= 1.5 and data("Eliminations", week)["103"] == 1, "shutdown waits for a write already under way")
latency = 0
Board.add(me, "Eliminations", 2)
Board.flushAll()
check(data("Eliminations", week)["101"] == 2 and Board.unsent(me.UserId, "Eliminations") == 0, "and writes everything still waiting")
check(Board.unsent(cy.UserId, "Eliminations") == 0, "nothing left over")
check(quiet(), "no errors from the leaderboard all along")

return { status = "PASS", checks = checks }
