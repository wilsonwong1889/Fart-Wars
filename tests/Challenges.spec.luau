-- Daily challenges (ChallengeConfig, ChallengeService, PlayStatsService),
-- with one client:
--   * on as shipped; three a day for each player, never two of a kind, the
--     same all day, different for other players and days, and only ones
--     that can be done (no rounds to win in continuous play)
--   * bots: no challenge counts anything a bot can feed (eliminations,
--     assists, streaks); a bot's kill or death counts nothing for anyone and
--     a barrel set off by a bot's blast counts for nobody; one player alone
--     with bots can do every challenge, a round played and won included
--   * progress from real play: rounds and wins (a minute in the round, a
--     minute on the winning team: no switching onto the winners at the
--     end), Fart Dashes, barrels and barrel chain reactions, minutes ACTIVE
--     (the home screen doesn't count)
--   * each pays its coins and XP once, when done, under one grant ID per
--     challenge per day; more of it, the grant again, or a new session pays
--     nothing more
--   * 00:00 UTC: three new ones from zero and the screen told; done again
--     the next day, it pays again
--   * saved: progress and what's paid survive leaving and coming back; an
--     unsaved session counts nothing (outside Studio); a damaged save starts
--     today's three again
--   * the DAILY screen: a card each with its bar, its reward, and DONE &
--     PAID once it's done (nothing to claim), the time to new ones, live
--     updates; with challenges off, none of it
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
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
local Shared = ReplicatedStorage.Shared
local FeatureFlags = require(Shared.Config.FeatureFlags)
local GameConfig = require(Shared.Config.GameConfig)
local ChallengeConfig = require(Shared.Config.ChallengeConfig)
local DailyShopConfig = require(Shared.Config.DailyShopConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local Data = require(server.Services.DataService)
local Challenges = require(server.Services.ChallengeService)
local PlayStats = require(server.Services.PlayStatsService)
local Economy = require(server.Services.EconomyService)
local Rewards = require(server.Services.RewardsService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Team = require(server.Services.TeamService)
local Round = require(server.Services.RoundService)
local Dash = require(server.Services.DashService)
local Barrels = require(server.Services.BarrelService)
local Explosions = require(server.Services.ExplosionService)
local Eliminations = require(server.Services.EliminationService)
local AFK = require(server.Services.AFKService)
local BotDirector = require(server.Services.BotDirector)
local TestControls = require(server.TestControls)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes

local saved = {}
Data.setStore({
	UpdateAsync = function(_, key, transform)
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})
-- The challenges' clock: an hour into a UTC day.
local DAY = 86400
local today = DailyShopConfig.day(2000000000)
local now = today * DAY + 3600
Challenges.setClock(function()
	return now
end)
local REWARD = ChallengeConfig.REWARD

-- What every player has done, as PlayStatsService counted it.
local counted: { { player: Player, stat: string, amount: number } } = {}
PlayStats.Counted:Connect(function(player, stat, amount)
	table.insert(counted, { player = player, stat = stat, amount = amount })
end)
local function countedSince(mark: number, player: Player?, stat: string): number
	local total = 0
	for i = mark + 1, #counted do
		local entry = counted[i]
		if entry.stat == stat and (player == nil or entry.player == player) then
			total += entry.amount
		end
	end
	return total
end
-- What the server told the client in words, and its challenge views.
local toasts, views = {}, {}
Remotes.UIMessage.FiredToClient:Connect(function(player, payload)
	if player.Name == "Me" and payload.kind == "challenge" then
		table.insert(toasts, payload.text)
	end
end)
Remotes.ProgressEvent.FiredToClient:Connect(function(player, event)
	if player.Name == "Me" and type(event) == "table" and event.kind == "challenges" then
		table.insert(views, event)
	end
end)
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end

-- The client, on the home screen.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Controllers = game.StarterPlayer.StarterPlayerScripts.Client.Controllers
local UI = require(Controllers.RewardsController)
task.wait(0.5)
local function data(player: Player?): any
	return assert(Data.get(player or me)).data
end
-- Today's challenges for `player`, chosen for the test.
local function setToday(player: Player, ids: { string })
	Data.update(player, function(d)
		d.Challenges = { day = Challenges.today(), ids = ids, progress = {}, claimed = {} }
	end)
	Challenges.push(player)
end
local function paidFor(player: Player, day: number, id: string): { any }
	local found = {}
	for _, entry in data(player).Ledger do
		if string.sub(entry.id, -#`challenge:{day}:{id}`) == `challenge:{day}:{id}` then
			table.insert(found, entry)
		end
	end
	return found
end
-- Ends the round and waits for its results: at the buzzer, or a moment
-- after while a bot's explosion is still counting down (its point goes in
-- first).
local function toResults()
	Round.testEndPhaseIn(0)
	local limit = os.clock() + 2
	while Round.phase() ~= "RESULTS" and os.clock() < limit do
		task.wait(0.1)
	end
	task.wait(0.2)
end
local function awake(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		for _, player in Players:GetPlayers() do
			AFK.markActive(player)
		end
		task.wait(1)
	end
end

-- On as shipped; today's three.
check(FeatureFlags.CHALLENGES == true and Challenges.enabled(), "on as shipped")
check(Data.defaults().Challenges and Data.migrate({ Coins = 5 }).Challenges.day == 0, "a profile field, filled in for old saves")
local mine = data().Challenges
check(mine.day == today and #mine.ids == ChallengeConfig.PER_DAY, "a new player has today's three")
local picked = ChallengeConfig.pick(me.UserId, today, function()
	return true
end)
check(picked[1].id == mine.ids[1] and picked[2].id == mine.ids[2] and picked[3].id == mine.ids[3], "worked out from the player and the day: the same on any server")
check(#views >= 1 and views[#views].day == today and #views[#views].challenges == 3, "and the client was told")

-- The picks.
local combos, perDay = {}, {}
for user = 1, 40 do
	for day = today, today + 13 do
		local list = ChallengeConfig.pick(user, day, function()
			return true
		end)
		local kinds, ids = {}, {}
		for _, challenge in list do
			check(not kinds[challenge.kind], `never two of a kind ({user}, {day})`)
			kinds[challenge.kind] = true
			table.insert(ids, challenge.id)
		end
		check(#list == 3, "always three")
		local key = table.concat(ids, ",")
		combos[key] = true
		if user == 1 then
			perDay[key] = true
		end
	end
end
local distinct, distinctDays = 0, 0
for _ in combos do
	distinct += 1
end
for _ in perDay do
	distinctDays += 1
end
check(distinct >= 8, `players get different ones: {distinct} combinations`)
check(distinctDays >= 4, `and new ones day to day: {distinctDays} in two weeks`)
local continuous = { MATCH_MODE = "Continuous", FART_DASH = true, GAS_COMBAT = true }
for day = today, today + 20 do
	for _, challenge in ChallengeConfig.pick(1, day, function(c)
		return ChallengeConfig.doable(c, continuous)
	end) do
		check(challenge.stat ~= "rounds" and challenge.stat ~= "wins", "continuous play: no rounds to play or win")
	end
end
for _, challenge in ChallengeConfig.pool do
	check(not table.find({ "eliminations", "assists", "streaks" }, challenge.stat), `{challenge.id} counts nothing a bot can feed`)
	check(ChallengeConfig.doable(challenge, FeatureFlags :: any), `{challenge.id} can be done as shipped`)
	check(challenge.goal > 0 and challenge.text ~= "" and challenge.hint ~= "", `{challenge.id} says what to do`)
end
check(REWARD.coins > 0 and REWARD.xp > 0, "each pays coins and XP")

-- The home screen doesn't count.
setToday(me, { "minutes15", "barrels3", "chain1" })
task.wait(125)
check((data().Challenges.progress.minutes15 or 0) == 0, "two minutes on the home screen: no minutes")

-- One player alone with bots: a round played and won.
setToday(me, { "play3", "win1", "dash30" })
local mark = #counted
Lifecycle.requestPlay(me, nil)
local deadline = os.clock() + 5
while Round.phase() ~= "ACTIVE" and os.clock() < deadline do
	task.wait(0.25)
end
local humans = 0
for _, n in Team.humanCounts() do
	humans += n
end
check(Round.phase() == "ACTIVE" and humans == 1 and Team.activeCount() >= 2, "one player and the bots start a round")
local myTeam = assert(Team.teamOf(me))
local otherTeam = if myTeam == "Stinkers" then "Sharters" else "Stinkers"
check(TestControls.score(myTeam, 50), "my team well ahead")
awake(65)
check(countedSince(mark, me, "minutes") >= 1, "minutes on the battlefield count")
local coinsBefore, xpBefore = data().Coins, data().LifetimeXP
toResults()
check(Round.phase() == "RESULTS" and Round.snapshot().result.winner == myTeam, "my team won")
check(data().Challenges.progress.play3 == 1, "a round played")
check(table.find(data().Challenges.claimed, "win1"), "and won: done")
local paid = paidFor(me, today, "win1")
check(#paid == 1 and paid[1].coins == REWARD.coins and paid[1].xp == REWARD.xp and paid[1].reason == "challenge", "paid its coins and XP once, through a grant")
check(data().Coins >= coinsBefore + REWARD.coins and data().LifetimeXP >= xpBefore + REWARD.xp, "into the wallet")
check(string.find(toasts[#toasts], "WIN A ROUND", 1, true), "and a shout: " .. tostring(toasts[#toasts]))
check(counter("Challenges.done") == 1 and counter("Challenges.done.win1") == 1, "counted")

-- The screen.
UI.openDaily()
task.wait(0.1)
local cards = UI.parts.challengeCards
check(UI.parts.daily.Enabled and UI.parts.challengeSection.Visible ~= false, "the DAILY screen shows the challenges")
check(cards[1].card.Visible and cards[1].text.Text == "Play 3 rounds" and cards[1].count.Text == "1 / 3", "a card each: what to do and how far")
check(math.abs(cards[1].fill.Size.X.Scale - 1 / 3) < 0.01 and cards[1].reward.Visible and not cards[1].claimed.Visible, "its bar, a third full, and its reward")
check(string.find(cards[1].reward.Text, `+{REWARD.coins}`, 1, true) and string.find(cards[1].reward.Text, `+{REWARD.xp} XP`, 1, true), "the reward: " .. cards[1].reward.Text)
check(cards[2].claimed.Visible and not cards[2].reward.Visible and cards[2].fill.Size.X.Scale == 1, "a done one: full, the reward gone")
local doneText = cards[2].claimed.Text
check(string.find(doneText, "DONE", 1, true) and string.find(doneText, "PAID", 1, true) and not string.find(doneText, "CLAIM", 1, true), "and it says it's done and paid, with nothing to claim: " .. doneText)
check(cards[3].text.Text == "Fart Dash 30 times" and cards[3].hint.Text ~= "", "with a tip")
check(string.find(UI.parts.challengeNote.Text, "^New ones in 2%dh %d%dm %d%ds$"), "and the time to new ones: " .. UI.parts.challengeNote.Text)

-- No switching onto the winners at the end.
deadline = os.clock() + 20
while Round.phase() ~= "ACTIVE" and os.clock() < deadline do
	task.wait(0.25)
end
check(Round.phase() == "ACTIVE", "the next round")
TestControls.score(otherTeam, 50)
mark = #counted
awake(65)
Team.testSetTeam(me, otherTeam)
awake(5)
toResults()
check(Round.snapshot().result.winner == otherTeam, "the other team won")
check(countedSince(mark, me, "rounds") == 1 and countedSince(mark, me, "wins") == 0, "a round played, but not won: five seconds on the winners isn't a win")
check(data().Challenges.progress.play3 == 2, "two rounds played")

-- Bots: their kills and deaths count nothing, their barrels count for nobody.
deadline = os.clock() + 20
while Round.phase() ~= "ACTIVE" and os.clock() < deadline do
	task.wait(0.25)
end
check(Round.phase() == "ACTIVE", "with the round live")
mark = #counted
local dummy = Instance.new("Model")
dummy.Name = "[BOT] Dummy"
Instance.new("Humanoid").Parent = dummy
dummy.Parent = workspace
Eliminations.eliminateBot(-1999, dummy, { killer = me, killerTeam = Team.teamOf(me), victimTeam = myTeam, cause = "shot" })
deadline = os.clock() + 6
while not (me.Character and me.Character:FindFirstChildOfClass("Humanoid")) and os.clock() < deadline do
	task.wait(0.2)
end
Eliminations.eliminate(me, assert(me.Character), { killerBot = -1999, killerTeam = myTeam, victimTeam = Team.teamOf(me), cause = "shot" })
task.wait(0.2)
check(countedSince(mark, nil, "eliminations") == 0 and countedSince(mark, nil, "assists") == 0 and countedSince(mark, nil, "streaks") == 0, "a bot's death and a bot's kill count nothing")
Barrels.resetAll()
local barrelModels = Barrels.all()
check(#barrelModels >= 2, "the map has barrels")
local function centre(model: Model): Vector3
	return (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") :: BasePart).Position
end
local function reach(model: Model): number
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local size = if body then body.Size else Vector3.zero
	return GameConfig.BARREL.RADIUS + math.max(size.X, size.Y, size.Z) / 2
end
-- Two barrels side by side, for a chain.
local first, second
for _, a in barrelModels do
	for _, b in barrelModels do
		if a ~= b and not first and (centre(a) - centre(b)).Magnitude <= reach(a) then
			first, second = a, b
		end
	end
end
check(first and second, "barrels sit side by side for chain reactions")
mark = #counted
Explosions.blast({ position = centre(first), radius = 4, gas = 40, ownerBot = -1999, ownerTeam = otherTeam, cause = "chain", depth = 1 })
task.wait(2)
check(Barrels.get(first).state == "gone", "a bot's blast sets a barrel off")
check(countedSince(mark, nil, "barrels") == 0 and countedSince(mark, nil, "chains") == 0, "but counts for nobody")
Barrels.resetAll()

-- Real Fart Dashes, without the bots now.
BotDirector.testSetEnabled(false)
task.wait(4)
mark = #counted
coinsBefore = data().Coins
local cooldown = AbilityConfig.FartDash.cooldownSeconds
local tries = 0
while not table.find(data().Challenges.claimed, "dash30") and tries < 45 do
	tries += 1
	if me.Character then
		Dash.dash(me, Vector3.new(1, 0, 0))
		me.Character:PivotTo(CFrame.new(0, 3, -40))
	end
	task.wait(cooldown + 0.05)
end
check(table.find(data().Challenges.claimed, "dash30") and countedSince(mark, me, "dashes") >= 30, "thirty Fart Dashes: done")
check(#paidFor(me, today, "dash30") == 1, "paid once")
-- Once each: more of it, the grant again, nothing.
local wallet = data().Coins
PlayStats.count(me, "dashes", 30)
check(not Economy.grant(me, `challenge:{today}:dash30`, "challenge", REWARD.coins, REWARD.xp), "the same grant again is refused")
check(data().Coins == wallet and #paidFor(me, today, "dash30") == 1, "more dashes pay nothing more")
PlayStats.count(me, "rounds", 5)
check(data().Coins == wallet + REWARD.coins, "five more rounds finish play3")
PlayStats.count(me, "rounds", 5)
check(data().Coins == wallet + REWARD.coins and #paidFor(me, today, "play3") == 1, "paid once")
check(#data().Challenges.claimed == 3 and counter("Challenges.allDone") == 1, "all three done")
task.wait(1.6)
check(string.find(toasts[#toasts], "ALL 3", 1, true), "and a shout for that: " .. tostring(toasts[#toasts]))
check(UI.parts.challengeNote.Text:find("ALL DONE", 1, true), "the screen says so, live: " .. UI.parts.challengeNote.Text)

-- Barrels and a chain reaction, from a real shot.
setToday(me, { "minutes15", "barrels3", "chain1" })
mark = #counted
check(Barrels.shoot(me, assert(first:FindFirstChild("Barrel") or first.PrimaryPart), GameConfig.BARREL.HEALTH), "a shot sets a barrel off")
task.wait(2.5)
check(countedSince(mark, me, "barrels") >= 2 and countedSince(mark, me, "chains") >= 1, "its blast sets off the next one: two barrels and a chain")
check(table.find(data().Challenges.claimed, "chain1") and #paidFor(me, today, "chain1") == 1, "a chain reaction: done and paid")
check(data().Challenges.progress.barrels3 >= 2, "and the barrels count toward theirs")

-- 00:00 UTC: new ones.
local viewsBefore = #views
now = (today + 1) * DAY + 5
task.wait(1.2)
local tomorrow = data().Challenges
check(tomorrow.day == today + 1 and #tomorrow.claimed == 0 and next(tomorrow.progress) == nil, "a new day: three from zero")
local expected = ChallengeConfig.pick(me.UserId, today + 1, function(c)
	return ChallengeConfig.doable(c, FeatureFlags :: any)
end)
check(tomorrow.ids[1] == expected[1].id and tomorrow.ids[3] == expected[3].id, "the new day's own three")
check(#views > viewsBefore and views[#views].day == today + 1, "the screen was told")
check(cards[1].text.Text == assert(ChallengeConfig.get(tomorrow.ids[1])).text and not cards[1].claimed.Visible, "and shows them")
-- Done again the next day, it pays again (its own grant).
setToday(me, { "dash30", "barrels3", "chain1" })
coinsBefore = data().Coins
PlayStats.count(me, "dashes", 30)
check(data().Coins == coinsBefore + REWARD.coins and #paidFor(me, today + 1, "dash30") == 1, "the next day it pays again, under that day's ID")

-- Saved: progress and what's paid survive leaving.
local saver = Instance.new("Player")
saver.Name = "Saver"
saver.UserId = 7
saver.Parent = Players
task.wait(0.3)
setToday(saver, { "play3", "barrels3", "chain1" })
PlayStats.count(saver, "barrels", 2)
PlayStats.count(saver, "chains", 1)
local saverCoins = data(saver).Coins
check(table.find(data(saver).Challenges.claimed, "chain1") and saverCoins >= REWARD.coins, "done and paid")
saver.Parent = nil
task.wait(0.5)
local stored = HttpService:JSONDecode(saved.player_7)
check(stored.Challenges and stored.Challenges.progress.barrels3 == 2 and table.find(stored.Challenges.claimed, "chain1"), "in the save")
local back = Instance.new("Player")
back.Name = "Saver"
back.UserId = 7
back.Parent = Players
task.wait(0.5)
check(data(back).Challenges.progress.barrels3 == 2 and table.find(data(back).Challenges.claimed, "chain1"), "back again: all there")
PlayStats.count(back, "chains", 3)
check(data(back).Coins == saverCoins, "a new session doesn't pay a done one again")
PlayStats.count(back, "barrels", 1)
check(data(back).Coins == saverCoins + REWARD.coins and #paidFor(back, today + 1, "barrels3") == 1, "and finishes the rest")

-- An unsaved session counts nothing (outside Studio).
assert(Data.get(back)).temporary = true
Rewards.unsavedInStudio = false
PlayStats.count(back, "rounds", 3)
local unsaved = assert(Challenges.view(back))
check(not unsaved.saving and (data(back).Challenges.progress.play3 or 0) == 0, "not saving: nothing counts")
Rewards.unsavedInStudio = true
assert(Data.get(back)).temporary = false
-- A damaged save starts today's three again.
Data.update(back, function(d)
	d.Challenges = { day = "soon", ids = 5 }
end)
local fixed = assert(Challenges.view(back))
check(#fixed.challenges == 3 and data(back).Challenges.day == today + 1, "a damaged save: today's three again")

-- The test command.
local ok, message = TestControls.challenges(me, nil)
check(ok and string.find(message, "Fart Dash 30 times 30/30 (paid)", 1, true), "/fw challenges lists them: " .. message)
ok, message = TestControls.challenges(me, "reset")
check(ok and #data().Challenges.claimed == 0, "/fw challenges reset")
ok, message = TestControls.challenges(me, "done")
check(ok and #data().Challenges.claimed == 3, "/fw challenges done: " .. message)

-- Off: none of it.
TestControls.challenges(me, "reset")
Challenges.testEnable(false)
PlayStats.count(me, "barrels", 3)
check(Challenges.view(me) == nil and Rewards.status(me).challenges == nil, "off: nothing to show")
check(next(data().Challenges.progress) == nil and #data().Challenges.claimed == 0, "and nothing counts")
check(not TestControls.challenges(me, nil), "and the test command says so")
Challenges.testEnable(nil)
UI.closeDaily()

return { status = "PASS", checks = checks }
