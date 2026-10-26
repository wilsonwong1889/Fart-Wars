-- Daily rewards, ten-minute gifts and free spins (masterplan 4.1, 4.5),
-- with one client:
--   * one daily claim per UTC day; the track advances, loops after day 7,
--     and a missed day doesn't reset it; day 3 adds a spin, day 7 a
--     cosmetic (coins if already owned); a second claim the same day, a
--     replayed request or a temporary profile gets nothing
--   * gifts: a free spin per ten minutes of ACTIVE play only, capped per
--     day (the count saved, and reset the next day), banked up to the cap
--   * spins: one per spin, drawn by the published weights (checked over
--     many draws), paid once each, refused with none left
--   * the client: the daily screen (ticks, today, CLAIM, the countdown),
--     its auto-open on the home screen, the spin screen with every chance
--     shown, the top-right buttons
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
local Data = require(server.Services.DataService)
local Rewards = require(server.Services.RewardsService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Telemetry = require(server.Telemetry)
local RewardsConfig = require(ReplicatedStorage.Shared.Config.RewardsConfig)

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
local MenuBar = require(Controllers.MenuBarController)
task.wait(0.5)
local function data(): any
	return assert(Data.get(me)).data
end
local function newDay()
	-- Yesterday's claim, as if a day had passed.
	Data.update(me, function(d)
		d.LastDailyDay = RewardsConfig.day(os.time()) - 1
	end)
	Rewards.publish(me)
	task.wait(0.05)
end

check(me:GetAttribute("DailyReady") == true and me:GetAttribute("DailyDay") == 1, "a new player has day 1 waiting")
check(UI.parts.daily.Enabled, "the daily screen opens by itself on the home screen")
check(UI.parts.claim:GetAttribute("Enabled") ~= false and UI.parts.claim.Text == "CLAIM!", "with CLAIM! ready")

-- Day 1, through the screen.
UI.claim()
check(data().Coins == 100 and data().DailyClaims == 1 and data().DailyTrack == 1, "day 1: 100 coins")
check(me:GetAttribute("DailyReady") == false and me:GetAttribute("DailyDay") == 2, "claimed: day 2 is next")
check(string.find(UI.parts.dailyNote.Text, "Day 1: +100 coins", 1, true), "the screen says what came")
UI.renderDaily()
check(UI.parts.claim.Text == "CLAIMED" and string.find(UI.parts.dailyNote.Text, "Next reward in %d+h %d%dm %d%ds"), "then the countdown to the reset")
check(UI.parts.days[1].done.Visible and not UI.parts.days[2].done.Visible, "day 1 ticked")
local again = Rewards.claimDaily(me)
check(not again.ok and again.reason == "alreadyClaimed" and data().Coins == 100, "a second claim the same day: nothing")
task.wait(0.3) -- past the rate limit
check(Rewards.request(me, 7).reason == "badPayload" and Rewards.request(me, "steal").reason == "badPayload", "junk requests refused")

-- Days 2-7, then the loop.
newDay()
Rewards.claimDaily(me)
newDay()
local day3 = Rewards.claimDaily(me)
check(day3.ok and day3.spins == 1 and data().Spins == 1, "day 3: a free spin with the coins")
-- Missing days: three days off.
Data.update(me, function(d)
	d.LastDailyDay = RewardsConfig.day(os.time()) - 3
end)
Rewards.publish(me)
check(me:GetAttribute("DailyDay") == 4 and me:GetAttribute("DailyReady"), "three days away: still day 4 next, not back to day 1")
Rewards.claimDaily(me)
for _ = 5, 6 do
	newDay()
	Rewards.claimDaily(me)
end
newDay()
local day7 = Rewards.claimDaily(me)
check(day7.ok and day7.cosmetic == "StinkSparkle" and table.find(data().OwnedCosmetics, "StinkSparkle"), "day 7: the Stink Sparkle tracer")
newDay()
check(me:GetAttribute("DailyDay") == 1, "and the track loops")
for _ = 1, 6 do
	Rewards.claimDaily(me)
	newDay()
end
local again7 = Rewards.claimDaily(me)
check(again7.coins == 500 + RewardsConfig.DUPLICATE_COSMETIC_COINS and again7.cosmetic == nil, "day 7 again: coins instead of a tracer already owned")
check(counter("Rewards.dailyClaims") == 14, "every claim counted (the daily claim rate)")

-- Gifts: active play only.
local spinsBefore = data().Spins
task.wait(RewardsConfig.GIFT_ACTIVE_MINUTES * 60 + 5)
check(data().Spins == spinsBefore, "ten minutes on the home screen: no gift")
Lifecycle.requestPlay(me, nil)
task.wait(0.2)
check(UI.parts.daily.Enabled == false, "PLAY closes the daily screen")
check(MenuBar.parts.corner.Visible and string.find(MenuBar.parts.spin.Text, "SPIN"), "the spin button top right")
local function fidget()
	if me.Character then
		me.Character:PivotTo(me.Character:GetPivot() * CFrame.new(6, 0, 0))
	end
end
for _ = 1, RewardsConfig.GIFT_ACTIVE_MINUTES * 2 + 1 do
	task.wait(30)
	fidget()
end
check(data().Spins == spinsBefore + 1 and data().GiftsToday == 1, "ten minutes of play: a free spin")
check(counter("Rewards.gifts") == 1, "counted")
-- The daily cap.
for _ = 2, RewardsConfig.GIFTS_PER_DAY do
	Rewards.testGiftSeconds(me, RewardsConfig.GIFT_ACTIVE_MINUTES * 60)
	task.wait(1.1)
end
check(data().GiftsToday == RewardsConfig.GIFTS_PER_DAY, "up to the day's cap")
Rewards.testGiftSeconds(me, RewardsConfig.GIFT_ACTIVE_MINUTES * 60)
task.wait(1.1)
check(data().GiftsToday == RewardsConfig.GIFTS_PER_DAY and me:GetAttribute("NextGiftSeconds") == nil, "then no more today")
Data.update(me, function(d)
	d.GiftDay = RewardsConfig.day(os.time()) - 1
	d.Spins = RewardsConfig.MAX_SPINS
end)
task.wait(1.1)
check(data().GiftsToday == 0 and Rewards.status(me).giftsLeft == RewardsConfig.GIFTS_PER_DAY, "a new day: gifts again")
check(me:GetAttribute("NextGiftSeconds") == nil, "but not while the bank of spins is full")
Data.update(me, function(d)
	d.Spins = 2
end)
task.wait(1.1)
check(type(me:GetAttribute("NextGiftSeconds")) == "number", "room in the bank: the gift timer runs again")

-- Spins.
local spins = data().Spins
local coins, xp = data().Coins, data().LifetimeXP
local result = Rewards.spin(me)
check(result.ok and data().Spins == spins - 1 and data().SpinsUsed >= 1, "a spin uses one")
check(data().Coins + data().LifetimeXP > coins + xp or result.cosmetic, "and pays its prize: " .. tostring(result.label))
Data.update(me, function(d)
	d.Spins = 0
end)
check(Rewards.spin(me).reason == "noSpins", "no spins: refused")
-- The odds over many draws match the published weights.
local tally = {}
local rng = Random.new(7)
local draws = 20000
for _ = 1, draws do
	local prize = Rewards.draw(rng:NextNumber())
	tally[prize.id] = (tally[prize.id] or 0) + 1
end
for _, prize in RewardsConfig.spin do
	local seen = (tally[prize.id] or 0) / draws
	check(math.abs(seen - RewardsConfig.chance(prize)) < 0.015, `{prize.id}: {seen} vs {RewardsConfig.chance(prize)}`)
end
-- The spin screen shows every chance.
UI.openSpin()
local shown = 0
for _, prize in RewardsConfig.spin do
	local row = UI.parts.prizes[prize.id]
	if row and string.find(row.Chance.Text, "%%") then
		shown += 1
	end
end
check(shown == #RewardsConfig.spin and UI.parts.prizes.coins50.Chance.Text == "40%", "every prize with its chance on the spin screen")
UI.closeSpin()

-- A temporary profile can't claim.
assert(Data.get(me)).temporary = true
newDay()
check(Rewards.claimDaily(me).reason == "notSaving" and Rewards.spin(me).reason == "notSaving", "an unsaved session can't claim or spin")
assert(Data.get(me)).temporary = false

return { status = "PASS", checks = checks }
