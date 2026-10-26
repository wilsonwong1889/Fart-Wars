-- Playing with friends and retention experiments (masterplan 4.3, 4.5),
-- with one client:
--   * the squad bonus: ten active minutes with a Roblox friend on your team
--     pays you both; not for a friend on the other team or someone who
--     isn't a friend; a few a day
--   * the welcome: a newcomer's first ten active minutes with a friend here
--     pays them both once; never again for that newcomer, never between two
--     new accounts, never past the welcomer's daily cap (and again the next
--     day), and nothing for a newcomer with no friend here
--   * co-play counted for the retention numbers
--   * cohorts: the same for a user every time, a share of players by
--     percent, variants by weight, nobody at 0 % (as shipped)
--   * an experiment's values reach the gift timer, early shop prices (the
--     server's price is what's paid and what the shop shows) and the tips
--     default (until the player picks in Settings); telemetry by cohort
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
local RewardsConfig = require(Shared.Config.RewardsConfig)
local ExperimentConfig = require(Shared.Config.ExperimentConfig)
local Data = require(server.Services.DataService)
local Team = require(server.Services.TeamService)
local Social = require(server.Services.SocialService)
local Experiments = require(server.Services.ExperimentService)
local Rewards = require(server.Services.RewardsService)
local Shop = require(server.Services.ShopService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Telemetry = require(server.Telemetry)

local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end

-- Cohorts, as configured.
for _, experiment in ExperimentConfig.experiments do
	check(experiment.percent == 0, `{experiment.key} ships switched off`)
end
local gift = ExperimentConfig.experiments[1]
local nobody = true
for id = 1, 2000 do
	nobody = nobody and ExperimentConfig.assign(gift, id) == nil
end
check(nobody, "at 0 %: nobody enrolled")
local half = table.clone(gift)
half.percent = 50
local enrolled, eight, same = 0, 0, 0
local other = table.clone(half)
other.salt = "another-salt"
for id = 1, 20000 do
	local variant = ExperimentConfig.assign(half, id)
	if variant then
		enrolled += 1
		eight += if variant == "eight" then 1 else 0
	end
	if (variant == nil) == (ExperimentConfig.assign(other, id) == nil) then
		same += 1
	end
end
check(math.abs(enrolled / 20000 - 0.5) < 0.02, `at 50 %: about half enrolled ({enrolled})`)
check(math.abs(eight / enrolled - 0.5) < 0.03, `split between the variants by weight ({eight} of {enrolled})`)
check(math.abs(same / 20000 - 0.5) < 0.03, "a new salt draws new cohorts")
check(ExperimentConfig.assign(half, 4242) == ExperimentConfig.assign(half, 4242), "a user's cohort is the same every time")
check(ExperimentConfig.weaponPrice(400, 0.75) == 300 and ExperimentConfig.weaponPrice(1200, 0.75) == 1200, "cheaper early unlocks only")
check(ExperimentConfig.weaponPrice(400, nil) == 400 and ExperimentConfig.weaponPrice(0, 0.75) == 0, "and no change otherwise")

-- Everyone here in the variants (as if at 100 %).
local function only(key: string, variant: string)
	local experiment = table.clone(assert(ExperimentConfig.get(key)))
	experiment.percent = 100
	local variants = {}
	for _, entry in experiment.variants do
		table.insert(variants, { name = entry.name, value = entry.value, weight = if entry.name == variant then 1 else 0 })
	end
	experiment.variants = variants
	return experiment
end
local testing = table.clone(ExperimentConfig)
testing.experiments = { only("giftMinutes", "eight"), only("earlyUnlock", "cheaper"), only("tips", "off") }
Experiments.setConfig(testing)

-- Profiles: Me has played before; the rest are new.
local saved = {
	player_1 = HttpService:JSONEncode({ Sessions = 3, Level = 5, Coins = 1000, FirstSeen = os.time() - 86400 * 5, LastSeen = os.time() - 86400 * 2 }),
}
Data.setStore({
	UpdateAsync = function(_, key, transform)
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})
-- Roblox friendships: Me with Bea, Dot and Hal; Eve with Flo.
local friendships = { ["1:2"] = true, ["1:4"] = true, ["1:8"] = true, ["6:7"] = true }
Team.checkFriends = function(a, b)
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return friendships[`{low}:{high}`] == true
end

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
local Locker = require(Controllers.LockerController)
local Settings = require(game.StarterPlayer.StarterPlayerScripts.Client.Settings)

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local bea = join("Bea", 2)
local cal = join("Cal", 3)
task.wait(0.5)
local function data(player: Player): any
	return assert(Data.get(player)).data
end
check(Team.areFriends(me, bea) and Team.areFriends(bea, me) and not Team.areFriends(me, cal), "friendships looked up as players join")

-- Who plays where.
local placement: { [Player]: string } = {}
local function place(player: Player, team: string)
	placement[player] = team
	Lifecycle.requestPlay(player, team)
	Team.testSetTeam(player, team)
end
local function play(minutes: number)
	for _ = 1, minutes * 2 do
		task.wait(30)
		for player, team in placement do
			if player.Parent == Players then
				if Team.teamOf(player) ~= team then
					Lifecycle.requestPlay(player, team)
					Team.testSetTeam(player, team)
				end
				if player.Character then
					player.Character:PivotTo(player.Character:GetPivot() * CFrame.new(6, 0, 0))
				end
			end
		end
	end
	task.wait(1.5)
end
place(me, "Stinkers")
place(bea, "Stinkers")
place(cal, "Sharters")
task.wait(0.2)
check(Social.squadmate(me) == bea and Social.squadmate(bea) == me and Social.squadmate(cal) == nil, "Bea and I are a squad")

-- The experiments, live.
check(me:GetAttribute("Exp_giftMinutes") == "eight" and me:GetAttribute("Exp_tips") == "off", "my cohorts, as attributes")
check(Settings.tips == false, "tips start off in the 'off' cohort")
check(Locker.priceOf("Spritzer") == 300 and Locker.profile.prices.Spritzer == 300, "the Spritzer costs me 300, not 400")
Locker.open("Weapons")
task.wait(0.1)
local shown = false
for _, box in Locker.parts.content:GetDescendants() do
	if box:IsA("TextButton") and box.Text == "BUY 300" then
		shown = true
	end
end
check(shown, "and the shop says so")
Locker.close()
local coins = data(me).Coins
check(Shop.request(me, "buy", "weapon", "Spritzer").ok, "bought")
check(data(me).Coins == coins - 300, "for 300 coins")
local entry = data(me).Ledger[#data(me).Ledger]
check(entry.reason == "purchase" and entry.coins == -300, "in the ledger at 300")
check(Rewards.status(me).nextGiftSeconds <= 8 * 60, "gifts every eight minutes in the 'eight' cohort")

-- Ten minutes together.
play(RewardsConfig.SQUAD_MINUTES)
check(data(me).SquadToday == 1 and data(bea).SquadToday == 1, "ten minutes as a squad: a bonus each")
check(data(cal).SquadToday == 0, "nothing for Cal, who isn't a friend")
check(counter("social.squadBonuses") == 2, "counted")
local found = 0
for _, line in data(bea).Ledger do
	if line.reason == "squad" and line.coins == RewardsConfig.SQUAD_COINS and line.xp == RewardsConfig.SQUAD_XP then
		found += 1
	end
end
check(found == 1, "paid through the ledger")
check(data(bea).WelcomedBy == 1 and table.find(data(me).WelcomedFriends, 2), "Bea's first ten minutes with me here: welcomed")
check(data(me).WelcomesToday == 1 and counter("social.welcomes") == 1, "once")
local welcomed = 0
for _, line in data(me).Ledger do
	if line.reason == "welcome" and line.coins == RewardsConfig.WELCOME_COINS then
		welcomed += 1
	end
end
check(welcomed == 1, "the welcome paid me once")
check(data(cal).WelcomedBy == 0, "Cal, with no friend here: no welcome")
check(counter("social.sessionsWithFriend") == 2 and counter("social.friendCoplaySeconds") > 1000, "co-play counted")
check(counter("exp.giftMinutes.eight.returning") >= 1 and counter("exp.tips.off.newPlayers") >= 2, "telemetry by cohort: who joined")
check(counter("exp.earlyUnlock.cheaper.reached10Minutes") >= 2, "and who played ten minutes")

-- Apart, then the cap.
place(bea, "Sharters")
place(cal, "Stinkers")
-- Newcomers: Dot (my friend), Eve and Flo (friends with each other only).
local dot, eve, flo = join("Dot", 4), join("Eve", 6), join("Flo", 7)
task.wait(0.5)
Data.update(me, function(d)
	d.WelcomesToday = RewardsConfig.WELCOMES_PER_DAY
end)
place(dot, "Sharters")
place(eve, "Sharters")
place(flo, "Sharters")
play(RewardsConfig.SQUAD_MINUTES)
check(data(me).SquadToday == 1 and data(bea).SquadToday == 1, "a friend on the other team: no squad bonus")
check(data(eve).SquadToday == 1 and data(flo).SquadToday == 1, "Eve and Flo, friends on one team: a squad")
check(data(eve).WelcomedBy == 0 and data(flo).WelcomedBy == 0, "but two new accounts can't welcome each other")
check(data(dot).WelcomedBy == 0, "my welcomes for today are used up: Dot waits")
Data.update(me, function(d)
	d.WelcomeDay -= 1
end)
task.wait(1.5)
check(data(dot).WelcomedBy == 1 and data(me).WelcomesToday == 1, "a new day: Dot welcomed")
Data.update(me, function(d)
	d.SquadToday = RewardsConfig.SQUAD_PER_DAY
end)
place(bea, "Stinkers")
place(cal, "Sharters")
play(RewardsConfig.SQUAD_MINUTES)
check(data(me).SquadToday == RewardsConfig.SQUAD_PER_DAY and data(bea).SquadToday == 2, "together again: Bea's bonus, but mine are used up today")

-- Bea's next visit.
bea.Parent = nil
task.wait(0.5)
local bea2 = join("Bea", 2)
task.wait(0.5)
place(bea2, "Stinkers")
local before = counter("social.welcomes")
play(RewardsConfig.WELCOME_MINUTES)
check(data(bea2).Sessions == 2 and data(bea2).WelcomedBy == 1 and counter("social.welcomes") == before, "a newcomer is welcomed once, ever")
check(counter("social.leftWithFriend") >= 1, "sessions with friends counted as they end")

-- Settings win over the experiment.
Locker.open("Settings")
task.wait(0.1)
local button = Locker.parts.content.Settings.TipsRow:FindFirstChild("Tips")
check(button and button.Text == "TIPS: OFF", "the Settings screen shows tips off")
Locker.close()
Settings.tips = true
Settings.chosen.tips = true
me:SetAttribute("Exp_tips", "off")
me:SetAttribute("Exp_tips", nil)
me:SetAttribute("Exp_tips", "off")
check(Settings.tips == true, "once picked in Settings, the experiment doesn't change it")

-- Back to the shipped experiments: nobody enrolled.
Experiments.setConfig(ExperimentConfig)
check(me:GetAttribute("Exp_giftMinutes") == nil and Experiments.value(me, "giftMinutes") == RewardsConfig.GIFT_ACTIVE_MINUTES, "as shipped: the control for everyone")
check(Experiments.weaponPrice(me, 400) == 400, "full prices")

return { status = "PASS", checks = checks }
