-- Reasons to come back (FeatureFlags.BADGES), against a stand-in Roblox
-- BadgeService and DataStore, with one client:
--   * the config: six badges with what to type in the Creator Hub; UTC
--     dates and the beta window's edges; the beta's boom exclusive (no
--     shop, spin, daily track, pass, season, prestige or level has it, the
--     daily shop never sells it, buying it is refused)
--   * the Beta Tester: joining isn't playing, and playing before the
--     window isn't either; the first spawn in the window earns the badge
--     and the boom, once (a respawn or another visit gives nothing more);
--     after the window, nothing; a tester missing the boom gets it back;
--     the locker shows it locked, then owned, and it equips as a boom
--   * achievements: a first elimination, a first chain (a shot isn't one;
--     a barrel is), levels 10, 25 and 50, once each; a bot's kill earns
--     nobody anything; old profiles catch up as they load (eliminations,
--     levels, a prestige rank)
--   * missing IDs: earned all the same, nothing sent to Roblox, counted,
--     the selftest warns; awarded on the next visit once the ID is set
--   * BadgeService failures: counted, tried again RETRY_SECONDS later and
--     RETRY_ATTEMPTS times a session, then on the next visit; a refusal
--     for a badge they already have counts as theirs; a refusal otherwise
--     is tried again and gets through
--   * the favorite prompt: after the first round won (not lost or drawn),
--     at the results, with the mouse free until it's answered; never again
--     (another win, another visit); ten active minutes mid-round wait for
--     the results or the home screen; never on an unsaved profile
--   * INVITE on the Players screen: Roblox's prompt, or why not
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
-- No bots: the rounds and their winners are the spec's.
require(server.Services.BotDirector).testSetEnabled(false)

local Shared = ReplicatedStorage.Shared
local FeatureFlags = require(Shared.Config.FeatureFlags)
local BadgeConfig = require(Shared.Config.BadgeConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local DailyShopConfig = require(Shared.Config.DailyShopConfig)
local RewardsConfig = require(Shared.Config.RewardsConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local SeasonConfig = require(Shared.Config.SeasonConfig)
local PrestigeConfig = require(Shared.Config.PrestigeConfig)
local Services = server.Services
local Data = require(Services.DataService)
local Achievements = require(Services.AchievementService)
local Economy = require(Services.EconomyService)
local Lifecycle = require(Services.PlayerLifecycleService)
local Team = require(Services.TeamService)
local Eliminations = require(Services.EliminationService)
local Rounds = require(Services.RoundService)
local Scores = require(Services.MatchScoreService)
local Shop = require(Services.ShopService)
local TestControls = require(server.TestControls)
local Telemetry = require(server.Telemetry)

local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end

-- The config.
check(FeatureFlags.BADGES == true and Achievements.enabled(), "on as shipped")
local listed = 0
for key, badge in BadgeConfig.badges do
	listed += 1
	check(badge.key == key and type(badge.id) == "number" and badge.id >= 0 and badge.id == math.floor(badge.id), `{key}: its key and a whole-number ID`)
	check(#badge.name > 0 and #badge.name <= 50 and #badge.description > 0 and #badge.description <= 1000, `{key}: a name and a description for the Creator Hub`)
	check(table.find(BadgeConfig.order, key), `{key} is in the order`)
end
check(listed == 6 and #BadgeConfig.order == 6, "six badges")
check(BadgeConfig.badges.Level10.level == 10 and BadgeConfig.badges.Level25.level == 25 and BadgeConfig.badges.Level50.level == 50, "levels 10, 25 and 50")
check(BadgeConfig.utc("1970-01-01") == 0 and BadgeConfig.utc("2000-03-01") == 951868800, "UTC dates as Unix times")
check(BadgeConfig.utc("2026-11-02") == 1793577600 and BadgeConfig.utc("2026-12-28") == 1798416000, "the same days as SeasonConfig's")
check(BadgeConfig.utc("2028-02-29") + 86400 == BadgeConfig.utc("2028-03-01"), "leap days")
check(not pcall(BadgeConfig.utc, "1 Nov 2026") and not pcall(BadgeConfig.utc, "2026-13-01"), "a date that isn't one is refused")
local opens, closes = BadgeConfig.betaWindow()
check(opens == BadgeConfig.utc(BadgeConfig.BETA_FIRST_DAY) and closes == BadgeConfig.utc(BadgeConfig.BETA_LAST_DAY) + 86400 and closes > opens, "the window: from the first day's start to the last day's end")
check(not BadgeConfig.inBeta(opens - 1) and BadgeConfig.inBeta(opens), "it opens at 00:00 UTC on the first day")
check(BadgeConfig.inBeta(closes - 1) and not BadgeConfig.inBeta(closes), "and closes after the last day, all of it")

local boom = BadgeConfig.BETA_COSMETIC
local cosmetic = ProgressionConfig.cosmetics[boom]
check(cosmetic and cosmetic.id == boom and cosmetic.kind == "boom" and cosmetic.exclusive == true and typeof(cosmetic.boomColor) == "Color3", "the beta's cosmetic: a boom, marked exclusive")
check(table.find(ProgressionConfig.cosmeticOrder, boom), "the locker lists it")
local sources: { { string } } = {}
for _, item in DailyShopConfig.pool do
	table.insert(sources, { "the daily shop", item.id })
end
for day, reward in RewardsConfig.daily do
	table.insert(sources, { `daily day {day}`, reward.cosmetic })
end
for _, prize in RewardsConfig.spin do
	table.insert(sources, { "the spin", prize.cosmetic })
end
for _, pass in MonetizationConfig.passes do
	for _, id in pass.cosmetics do
		table.insert(sources, { pass.name, id })
	end
end
for tier, reward in SeasonConfig.tiers do
	table.insert(sources, { `season tier {tier}`, reward.cosmetic })
end
for rank, reward in PrestigeConfig.ranks do
	table.insert(sources, { `prestige {rank}`, reward.cosmetic })
end
for level, entry in ProgressionConfig.unlocks do
	table.insert(sources, { `level {level}`, if entry.kind == "cosmetic" then entry.id else nil })
end
for _, source in sources do
	local id = source[2]
	check(id == nil or not ProgressionConfig.cosmetics[id].exclusive, `{source[1]} never gives an exclusive cosmetic`)
end
local today = DailyShopConfig.day(os.time())
local sold = false
for day = today, today + 400 do
	for _, item in DailyShopConfig.forDay(day) do
		sold = sold or item.id == boom
	end
end
check(not sold, "the daily shop never has it, any day for a year")

-- The stand-ins. Saves are JSON, as in Roblox; a key in `unavailable` gets
-- an unsaved profile.
local saved: { [string]: string } = {}
local unavailable: { [string]: boolean } = {}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		if unavailable[key] then
			error("502: API Services rejected request with error. Error code: 7 Reason: Studio access to APIs is not allowed.")
		end
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})
local function edit(userId: number, change: (any) -> ())
	local profile = HttpService:JSONDecode(saved[`player_{userId}`])
	change(profile)
	saved[`player_{userId}`] = HttpService:JSONEncode(profile)
end
-- Roblox's badges: who has which, award calls by user, and trouble on demand.
local IDS = { BetaTester = 101, FirstElimination = 102, FirstChain = 103, Level10 = 110, Level25 = 125, Level50 = 150 }
local roblox = {
	owned = {} :: { [string]: boolean },
	awards = {} :: { [number]: number },
	broken = {} :: { [number]: boolean },
	refusing = false,
	disabled = {} :: { [number]: boolean },
}
local function owns(userId: number, badgeId: number): boolean
	return roblox.owned[`{userId}:{badgeId}`] == true
end
local function awards(userId: number): number
	return roblox.awards[userId] or 0
end
Achievements.setApi({
	award = function(userId: number, badgeId: number): boolean
		roblox.awards[userId] = awards(userId) + 1
		task.wait(0.2)
		if roblox.broken[userId] then
			error("HTTP 503 (Service Unavailable)")
		end
		if roblox.refusing or owns(userId, badgeId) then
			return false
		end
		roblox.owned[`{userId}:{badgeId}`] = true
		return true
	end,
	owns = function(userId: number, badgeId: number): boolean
		task.wait(0.1)
		if roblox.broken[userId] then
			error("HTTP 503 (Service Unavailable)")
		end
		return owns(userId, badgeId)
	end,
	info = function(badgeId: number)
		return { Name = tostring(badgeId), IsEnabled = not roblox.disabled[badgeId] }
	end,
})
local function withIds(ids: { [string]: number }): any
	local testing = table.clone(BadgeConfig) :: any
	local badges = {}
	for key, badge in BadgeConfig.badges do
		local copy = table.clone(badge) :: any
		copy.id = ids[key] or 0
		badges[key] = copy
	end
	testing.badges = badges
	return testing
end
Achievements.setConfig(withIds(IDS))
-- The beta window's clock: before it to start with.
local unix = opens - 3600
Achievements.setClock(function()
	return unix
end)

-- What the server told the clients.
local heardKinds: { [number]: { string } } = {}
ReplicatedStorage.Remotes.ProgressEvent.FiredToClient:Connect(function(player: Player, event: any)
	if type(event) == "table" and (event.kind == "favorite" or event.kind == "beta") then
		heardKinds[player.UserId] = heardKinds[player.UserId] or {}
		table.insert(heardKinds[player.UserId], event.kind)
	end
end)
local function heard(player: Player, kind: string): number
	local n = 0
	for _, each in heardKinds[player.UserId] or {} do
		n += if each == kind then 1 else 0
	end
	return n
end

-- The client.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Client = game.StarterPlayer.StarterPlayerScripts.Client
local Favorite = require(Client.Controllers.FavoriteController)
local Locker = require(Client.Controllers.LockerController)
local PlayersScreen = require(Client.Controllers.PlayersController)
local Progress = require(Client.Controllers.ProgressController)
local MouseLock = require(Client.MouseLock)
local prompts = 0
local answered = Instance.new("BindableEvent")
Favorite.prompt = function()
	prompts += 1
end
Favorite.answered = function()
	return answered.Event
end

local function data(player: Player): any
	return assert(Data.get(player)).data
end
local function has(list: { string }, key: string): boolean
	return table.find(list, key) ~= nil
end
local function copies(list: { string }, key: string): number
	local n = 0
	for _, each in list do
		n += if each == key then 1 else 0
	end
	return n
end
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local placement: { [Player]: string } = {}
local function place(player: Player, team: string)
	placement[player] = team
	Lifecycle.requestPlay(player, team)
	Team.testSetTeam(player, team)
end
-- `seconds` of play, everyone on their team and moving now and then (so
-- nobody goes AFK).
-- Back and forth, far enough each time to count as moving (AFKService).
local sway = 10
local function play(seconds: number)
	local left = seconds
	while left > 0 do
		local step = math.min(5, left)
		task.wait(step)
		left -= step
		sway = -sway
		for player, team in placement do
			if player.Parent == Players and Lifecycle.stateOf(player) == "ACTIVE" then
				if Team.teamOf(player) ~= team then
					Team.testSetTeam(player, team)
				end
				if player.Character then
					player.Character:PivotTo(player.Character:GetPivot() * CFrame.new(sway, 0, 0))
				end
			end
		end
	end
end
local function grid(): Instance?
	Locker.open("Progression")
	task.wait(0.1)
	return Locker.parts.content:FindFirstChild(boom, true)
end

-- Before the beta, and joining without playing.
task.wait(0.5)
check(Data.isLoaded(me) and data(me).FavoritePromptAt == 0 and #data(me).BadgesEarned == 0 and #data(me).BadgesAwarded == 0, "a new profile: nothing earned, no prompt yet")
local early = join("Early", 20)
task.wait(0.5)
place(early, "Sharters")
task.wait(1)
check(Lifecycle.stateOf(early) == "ACTIVE" and not has(data(early).BadgesEarned, "BetaTester") and not has(data(early).OwnedCosmetics, boom), "playing before the beta: no Beta Tester")
unix = opens + 3600
task.wait(1)
check(not has(data(me).BadgesEarned, "BetaTester") and not has(data(me).OwnedCosmetics, boom), "in the beta, but joining isn't playing")
local button = grid()
check(button and button.Text == "PC BETA TESTERS" and button:GetAttribute("Enabled") == false, "the locker shows the boom, locked: PC BETA TESTERS")
Locker.close()
check(not Shop.request(me, "buy", "cosmetic", boom).ok, "and it can't be bought")

-- Playing in the beta. My PLAY starts a round, which spawns Early again
-- (Early's avatar is a few seconds old by then: a round leaves one that
-- has only just come, under the spawn protection's 3 seconds, alone).
task.wait(1.5)
place(me, "Stinkers")
task.wait(1.5)
check(Lifecycle.stateOf(me) == "ACTIVE" and Rounds.phase() == "ACTIVE", "I'm playing, and a round is on")
check(has(data(me).BadgesEarned, "BetaTester") and has(data(me).OwnedCosmetics, boom), "playing in the beta: a Beta Tester, with the boom")
check(heard(me, "beta") == 1, "told so")
local line = Progress.parts.lines:FindFirstChild("Beta")
check(line and string.find(line.Text, "OG BETA TESTER", 1, true) and string.find(line.Text, cosmetic.name, 1, true), "a line says so: " .. tostring(line and line.Text))
check(has(data(me).BadgesAwarded, "BetaTester") and owns(1, IDS.BetaTester) and awards(1) == 1, "the Beta Tester badge, through Roblox, once")
check(has(data(early).BadgesEarned, "BetaTester") and has(data(early).OwnedCosmetics, boom), "Early's spawn for the round, now in the beta: a Beta Tester")
check(counter("Badges.awarded") == 2 and counter("Badges.earned.BetaTester") == 2, "both counted")
Lifecycle.respawn(me)
Lifecycle.respawn(early)
task.wait(1.5)
check(awards(1) == 1 and heard(me, "beta") == 1 and copies(data(me).OwnedCosmetics, boom) == 1, "a respawn: nothing more")
check(awards(20) == 1 and heard(early, "beta") == 1 and copies(data(early).OwnedCosmetics, boom) == 1, "for Early either")
button = grid()
check(button and button.Text == cosmetic.name and button:GetAttribute("Enabled") ~= false, "the locker: mine to equip")
;(button :: GuiButton).Activated:Fire()
task.wait(0.5)
check(data(me).EquippedBoom == boom and me:GetAttribute("Boom") == boom, "equipped as my boom")
Locker.close()

-- Achievements.
local foe = join("Foe", 2)
task.wait(0.5)
place(foe, "Sharters")
play(5)
check(Rounds.phase() == "ACTIVE", "a round is on")
Eliminations.eliminate(foe, foe.Character, { killer = me, cause = "shot", weapon = "GasBlaster" })
task.wait(1)
check(has(data(me).BadgesAwarded, "FirstElimination") and owns(1, IDS.FirstElimination) and awards(1) == 2, "a first elimination: the badge")
check(not has(data(me).BadgesEarned, "FirstChain"), "a shot isn't a chain")
check(not has(data(foe).BadgesEarned, "FirstElimination"), "and the one eliminated earns nothing")
play(5)
Eliminations.eliminate(foe, foe.Character, { killer = me, cause = "chain" })
task.wait(1)
check(has(data(me).BadgesAwarded, "FirstChain") and owns(1, IDS.FirstChain) and awards(1) == 3, "a first chain reaction: the badge")
play(5)
Eliminations.eliminate(foe, foe.Character, { killer = me, cause = "barrel" })
task.wait(1)
check(awards(1) == 3 and copies(data(me).BadgesEarned, "FirstChain") == 1, "more eliminations and chains: nothing more")
play(5)
Eliminations.eliminate(me, me.Character, { killerBot = -1, killerTeam = "Sharters", cause = "shot" })
task.wait(1)
check(#data(foe).BadgesEarned == 1 and awards(2) == 1, "a bot's kill: nobody earns anything")
local function levelTo(player: Player, level: number)
	while data(player).Level < level do
		Economy.testGrant(player, 0, 2000)
		task.wait(0.05)
	end
	task.wait(1)
end
levelTo(me, 10)
check(has(data(me).BadgesAwarded, "Level10") and not has(data(me).BadgesEarned, "Level25") and awards(1) == 4, "level 10: its badge")
levelTo(me, 25)
check(has(data(me).BadgesAwarded, "Level25") and not has(data(me).BadgesEarned, "Level50") and awards(1) == 5, "level 25")
levelTo(me, 50)
check(has(data(me).BadgesAwarded, "Level50") and awards(1) == 6, "level 50")
Economy.testGrant(me, 0, 2000)
task.wait(1)
check(awards(1) == 6 and #data(me).BadgesEarned == 6 and #data(me).BadgesAwarded == 6, "every badge once, past the cap too")

-- Old profiles catch up as they load.
saved.player_30 = HttpService:JSONEncode({ Sessions = 4, Level = 27, TotalEliminations = 12 })
saved.player_31 = HttpService:JSONEncode({ Sessions = 9, Level = 3, Prestige = 2 })
local vet, prestiged = join("Vet", 30), join("Pres", 31)
task.wait(1.5)
local vetData = data(vet)
check(has(vetData.BadgesAwarded, "FirstElimination") and has(vetData.BadgesAwarded, "Level10") and has(vetData.BadgesAwarded, "Level25"), "a veteran: the elimination and level badges they'd earned")
check(not has(vetData.BadgesEarned, "Level50") and not has(vetData.BadgesEarned, "FirstChain") and not has(vetData.BadgesEarned, "BetaTester"), "not what they hadn't (or haven't played for yet)")
check(has(data(prestiged).BadgesAwarded, "Level50") and has(data(prestiged).BadgesAwarded, "Level10"), "a prestige rank: they've been to level 50")
vet.Parent = nil
prestiged.Parent = nil

-- The favorite prompt: the first round my team wins.
check(Rounds.phase() == "ACTIVE" and prompts == 0 and data(me).FavoritePromptAt == 0, "mid-round: no prompt")
Scores.testAddElimination("Stinkers", 3)
Rounds.testEndPhaseIn(0)
task.wait(1)
check(Rounds.phase() == "RESULTS", "the round's over")
check(heard(me, "favorite") == 1 and prompts == 1 and Favorite.shown == 1 and data(me).FavoritePromptAt > 0, "my team won: the favorite prompt, at the results")
check(heard(foe, "favorite") == 0 and heard(early, "favorite") == 0 and data(foe).FavoritePromptAt == 0, "not for the team that lost")
check(MouseLock.holds("Favorite"), "the mouse is free while it's up")
answered:Fire(Enum.AvatarPromptResult.Success)
task.wait(0.5)
check(not MouseLock.holds("Favorite"), "answered: the mouse goes back")
play(20)
check(Rounds.phase() == "ACTIVE", "the next round")
Scores.testAddElimination("Stinkers", 2)
Rounds.testEndPhaseIn(0)
task.wait(1)
check(heard(me, "favorite") == 1 and prompts == 1, "another win: never asked again")
play(20)
Rounds.testEndPhaseIn(0)
task.wait(1)
check(heard(foe, "favorite") == 0 and heard(early, "favorite") == 0, "a draw: nobody won")
play(20)

-- Missing IDs.
Achievements.setConfig(withIds({}))
local skipped = counter("Badges.skippedNoId")
local newbie = join("Newbie", 3)
task.wait(0.5)
place(newbie, "Sharters")
task.wait(1.5)
check(has(data(newbie).BadgesEarned, "BetaTester") and has(data(newbie).OwnedCosmetics, boom), "no badge IDs yet: still a Beta Tester, with the boom")
check(awards(3) == 0 and not has(data(newbie).BadgesAwarded, "BetaTester"), "nothing sent to Roblox")
check(counter("Badges.skippedNoId") == skipped + 1, "skipped, and counted")
local function selftestLine(lines: { { string } }, name: string): { string }?
	for _, each in lines do
		if each[2] == name then
			return each
		end
	end
	return nil
end
local idLine = selftestLine(Achievements.checks(), "Badge IDs")
check(idLine and idLine[1] == "WARN" and string.find(idLine[3], "6 of 6", 1, true) and string.find(idLine[3], "Beta Tester", 1, true), "the selftest warns: " .. tostring(idLine and idLine[3]))
local ran, tally = TestControls.selftest(nil)
check(type(ran) == "boolean" and string.find(tally, "warnings", 1, true), "and /fw selftest runs with it: " .. tostring(tally))
Achievements.setConfig(withIds(IDS))
newbie.Parent = nil
task.wait(1)
local newbie2 = join("Newbie", 3)
task.wait(1.5)
check(has(data(newbie2).BadgesAwarded, "BetaTester") and owns(3, IDS.BetaTester) and awards(3) == 1, "the ID set: awarded on the next visit")
check(copies(data(newbie2).OwnedCosmetics, boom) == 1 and heard(newbie2, "beta") == 1, "and the boom isn't given twice")
local ok = selftestLine(Achievements.checks(), "Badges")
check(ok and ok[1] == "OK" and selftestLine(Achievements.checks(), "Badge IDs") == nil, "every ID set: the selftest's happy")
roblox.disabled[IDS.FirstChain] = true
local off = selftestLine(Achievements.checks(), "Badges")
check(off and off[1] == "WARN" and string.find(off[3], "Chain Reaction", 1, true) and string.find(off[3], "disabled", 1, true), "a badge switched off in the Creator Hub: the selftest says which")
roblox.disabled[IDS.FirstChain] = nil
local window = selftestLine(Achievements.checks(), "Beta window")
check(window and window[1] == "OK" and string.find(window[3], "open", 1, true), "the beta window: open")

-- BadgeService failures, and ten minutes of play (all at once: they take
-- time). Flaky's awards fail; Nope's are refused; Old has the badge from
-- before; Tim and Uma play ten minutes; Tmp plays on an unsaved profile.
roblox.broken[4] = true
roblox.refusing = true
roblox.owned[`5:{IDS.BetaTester}`] = true
unavailable.player_8 = true
local failed = counter("Badges.awardFailed")
local flaky, nope = join("Flaky", 4), join("Nope", 9)
task.wait(0.5)
place(flaky, "Stinkers")
place(nope, "Stinkers")
task.wait(1.5)
roblox.refusing = false
check(has(data(flaky).BadgesEarned, "BetaTester") and not has(data(flaky).BadgesAwarded, "BetaTester") and awards(4) == 1, "Roblox failing: earned all the same, not through")
check(not has(data(nope).BadgesAwarded, "BetaTester") and awards(9) == 1, "Roblox saying no: not through either")
check(counter("Badges.awardFailed") == failed + 2, "both counted")
local old = join("Old", 5)
local tim, uma, tmp = join("Tim", 6), join("Uma", 7), join("Tmp", 8)
task.wait(1)
check(Data.get(tmp) and assert(Data.get(tmp)).temporary, "Tmp's profile won't save")
place(old, "Sharters")
place(tim, "Sharters")
place(uma, "Sharters")
place(tmp, "Stinkers")
task.wait(1.5)
check(has(data(old).BadgesAwarded, "BetaTester") and counter("Badges.alreadyOwned") == 1, "a badge they had already: theirs, counted")
play(BadgeConfig.RETRY_SECONDS - 15)
check(awards(4) == 1 and awards(9) == 1, "not tried again at once")
play(20)
check(awards(4) == 2, "tried again a minute later")
check(has(data(nope).BadgesAwarded, "BetaTester") and awards(9) == 2, "and a refusal goes through on its retry")
play(BadgeConfig.RETRY_SECONDS * (BadgeConfig.RETRY_ATTEMPTS - 2) + 10)
check(awards(4) == BadgeConfig.RETRY_ATTEMPTS and counter("Badges.retryNextVisit") == 1, `{BadgeConfig.RETRY_ATTEMPTS} tries a session`)
play(BadgeConfig.RETRY_SECONDS * 2)
check(awards(4) == BadgeConfig.RETRY_ATTEMPTS and not has(data(flaky).BadgesAwarded, "BetaTester"), "then it waits for the next visit")
roblox.broken[4] = nil
flaky.Parent = nil
task.wait(1)
local flaky2 = join("Flaky", 4)
task.wait(1.5)
check(has(data(flaky2).BadgesAwarded, "BetaTester") and owns(4, IDS.BetaTester) and awards(4) == BadgeConfig.RETRY_ATTEMPTS + 1, "Roblox back, the next visit: awarded")

-- Ten minutes, landing mid-round: the prompt waits.
local minutes = BadgeConfig.FAVORITE_MINUTES * 60
while Economy.activeSecondsOf(tim) < minutes - 30 do
	play(5)
end
check(heard(tim, "favorite") == 0 and heard(uma, "favorite") == 0, "under ten minutes: no prompt")
-- A fresh round (this one a draw), so the ten minutes land in the middle of the next.
while Rounds.phase() ~= "ACTIVE" do
	play(1)
end
Rounds.testEndPhaseIn(0)
while Rounds.phase() ~= "ACTIVE" do
	play(1)
end
while Economy.activeSecondsOf(tim) < minutes + 5 do
	play(1)
end
check(Rounds.phase() == "ACTIVE", "ten minutes in, mid-round")
check(heard(tim, "favorite") == 0 and heard(uma, "favorite") == 0 and data(tim).FavoritePromptAt == 0, "mid-fight: no prompt yet")
Lifecycle.requestSpectate(uma)
task.wait(2)
check(Lifecycle.stateOf(uma) == "MENU_SPECTATOR" and heard(uma, "favorite") == 1 and data(uma).FavoritePromptAt > 0, "Uma goes to the home screen: asked there")
check(heard(tim, "favorite") == 0, "Tim's still fighting")
Rounds.testEndPhaseIn(0)
task.wait(2)
check(Rounds.phase() == "RESULTS" and heard(tim, "favorite") == 1 and data(tim).FavoritePromptAt > 0, "the round over: Tim's asked at the results")
check(heard(tmp, "favorite") == 0 and assert(Data.get(tmp)).data.FavoritePromptAt == 0, "never on a profile that won't save")
check(heard(foe, "favorite") == 1 and heard(me, "favorite") == 1 and prompts == 1, "everyone else here long enough: once each")

-- Another visit: nothing again, and the beta over.
local timAt = data(tim).FavoritePromptAt
tim.Parent = nil
task.wait(1)
unix = closes + 3600
edit(6, function(profile)
	local index = table.find(profile.OwnedCosmetics, boom)
	if index then
		table.remove(profile.OwnedCosmetics, index)
	end
end)
local tim2 = join("Tim", 6)
task.wait(1.5)
check(data(tim2).FavoritePromptAt == timAt and has(data(tim2).BadgesAwarded, "BetaTester"), "Tim's back: the prompt and the badge remembered")
check(has(data(tim2).OwnedCosmetics, boom) and heard(tim2, "beta") == 2, "a Beta Tester missing the boom gets it back, after the beta too")
place(tim2, "Sharters")
play(20)
Rounds.testEndPhaseIn(0)
task.wait(2)
check(heard(tim2, "favorite") == 1, "and isn't asked again")
local late = join("Late", 10)
task.wait(0.5)
place(late, "Stinkers")
task.wait(1.5)
check(Lifecycle.stateOf(late) == "ACTIVE" and not has(data(late).BadgesEarned, "BetaTester") and not has(data(late).OwnedCosmetics, boom), "after the beta: no Beta Tester")
check(copies(data(me).OwnedCosmetics, boom) == 1, "but the testers keep the boom")
window = selftestLine(Achievements.checks(), "Beta window")
check(window and window[1] == "WARN" and string.find(window[3], "over", 1, true), "the selftest says the beta's over")

-- INVITE on the Players screen.
local invites = 0
PlayersScreen.canInvite = function()
	return true
end
PlayersScreen.promptInvite = function()
	invites += 1
end
PlayersScreen.open()
local invite = PlayersScreen.parts.screen:FindFirstChild("Invite", true)
check(invite and invite:IsA("TextButton") and invite.Text == "INVITE", "INVITE on the Players screen")
;(invite :: GuiButton).Activated:Fire()
task.wait(0.1)
check(invites == 1 and PlayersScreen.parts.inviteNote.Text == "", "Roblox's invite prompt")
PlayersScreen.canInvite = function()
	return false
end
;(invite :: GuiButton).Activated:Fire()
task.wait(0.1)
check(invites == 1 and PlayersScreen.parts.inviteNote.Text == PlayersScreen.INVITE_MESSAGES.unavailable, "invites not allowed: it says so")
PlayersScreen.canInvite = function()
	error("HTTP 500")
end
check(PlayersScreen.invite() == "unavailable" and invites == 1, "Roblox failing to say: the same")
PlayersScreen.canInvite = function()
	return true
end
PlayersScreen.promptInvite = function()
	error("the prompt failed")
end
check(PlayersScreen.invite() == "error" and PlayersScreen.parts.inviteNote.Text == PlayersScreen.INVITE_MESSAGES.error, "a prompt that fails: try again")
PlayersScreen.close()
PlayersScreen.open()
check(PlayersScreen.parts.inviteNote.Text == "", "opened again: no old note")
check(string.find(PlayersScreen.parts.empty.Text, "INVITE", 1, true), "with nobody here, the empty list suggests it")
PlayersScreen.close()

return { status = "PASS", checks = checks }
