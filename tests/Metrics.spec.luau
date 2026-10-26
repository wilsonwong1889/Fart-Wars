-- Live metrics by segment (masterplan 5.5, and 4.2's free-to-paid check):
--   * segments: new or returning, paying or free (a pass or a receipt
--     before, or a purchase now)
--   * the onboarding funnel: each step once, counted by segment, and sent
--     to Roblox for new players only
--   * fairness: eliminations and deaths by segment
--   * the economy's sources and sinks sent to Roblox with their types
--   * sessions: length buckets, minutes and players who left before their
--     first shot, by segment; concurrent players each minute
--   * a Roblox analytics call that fails is counted; the game carries on
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
local Metrics = require(server.Services.MetricsService)
local Economy = require(server.Services.EconomyService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Shop = require(server.Services.ShopService)
local Team = require(server.Services.TeamService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes

local saved = {
	player_2 = HttpService:JSONEncode({ Sessions = 4, Level = 6, Coins = 900, PassesGranted = { "StarterPack" }, FirstSeen = os.time() - 86400 * 9, LastSeen = os.time() - 86400 }),
	player_3 = HttpService:JSONEncode({ Sessions = 2, Level = 3, Coins = 50, FirstSeen = os.time() - 86400 * 3, LastSeen = os.time() - 86400 * 2 }),
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
local calls: { { any } } = {}
local function record(method: string)
	return function(_, ...)
		table.insert(calls, { method, ... })
	end
end
Metrics.setAnalytics({
	LogOnboardingFunnelStepEvent = record("funnel"),
	LogEconomyEvent = record("economy"),
	LogCustomEvent = record("custom"),
})
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function find(method: string, player: Player, test: ((...any) -> boolean)?): { any }?
	for _, call in calls do
		if call[1] == method and call[2] == player and (not test or test(table.unpack(call, 3))) then
			return call
		end
	end
	return nil
end
local function count(method: string, player: Player?): number
	local n = 0
	for _, call in calls do
		if call[1] == method and (player == nil or call[2] == player) then
			n += 1
		end
	end
	return n
end

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local newbie = join("Newbie", 1) -- first visit, free
local whale = join("Payer", 2) -- returning, has the Starter Pack
local regular = join("Regular", 3) -- returning, free
task.wait(0.5)
check(select(1, Metrics.segments(newbie)) == "new" and select(2, Metrics.segments(newbie)) == "free", "a first visit: new, free")
check(select(1, Metrics.segments(whale)) == "returning" and select(2, Metrics.segments(whale)) == "payer", "a pass from before: returning, paying")
check(select(2, Metrics.segments(regular)) == "free", "no purchases: free")
check(counter("metrics.joins.new") == 1 and counter("metrics.joins.returning") == 2 and counter("metrics.joins.payer") == 1, "joins by segment")

-- The funnel.
check(counter("funnel.new.joined") == 1 and counter("funnel.returning.joined") == 2, "joined, by segment")
check(count("funnel") == 1 and find("funnel", newbie, function(step, name)
	return step == 1 and name == "Joined"
end), "Roblox's onboarding funnel: new players only")
for _, player in { newbie, whale, regular } do
	Lifecycle.requestPlay(player, nil)
end
task.wait(0.3)
check(find("funnel", newbie, function(step)
	return step == 2
end) and counter("funnel.returning.played") == 2, "PLAY")
Remotes.RequestSpectate.OnServerEvent:Fire(newbie)
task.wait(0.2)
Lifecycle.requestPlay(newbie, nil)
task.wait(0.2)
check(count("funnel", newbie) == 2, "each step once")
local call = find("funnel", newbie) :: { any }
local fields = call[5]
check(type(fields) == "table" and fields[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] == "new"
	and fields[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] == "free", "with the segments as custom fields")

-- Fairness: the payer blows up the newbie, then the regular.
if Team.teamOf(whale) == Team.teamOf(newbie) then
	Team.testSetTeam(whale, if Team.teamOf(newbie) == "Stinkers" then "Sharters" else "Stinkers")
end
if Team.teamOf(regular) == Team.teamOf(whale) then
	Team.testSetTeam(regular, if Team.teamOf(whale) == "Stinkers" then "Sharters" else "Stinkers")
end
task.wait(3.2)
Gas.add(newbie, 100, { attacker = whale, cause = "shot", weapon = "GasBlaster" })
task.wait(1.5)
Gas.add(regular, 100, { attacker = whale, cause = "shot", weapon = "GasBlaster" })
task.wait(1.5)
check(counter("fairness.kills.payer") == 2 and counter("fairness.kills.returning") == 2, "the payer's eliminations")
check(counter("fairness.deaths.free") == 2 and counter("fairness.deaths.new") == 1 and counter("fairness.deaths.returning") == 1, "and who they were against")
check(counter("funnel.returning.elimination") == 1, "the first elimination, a funnel step")

-- The economy.
local source = find("economy", whale, function(flow, currency, amount, balance, kind, reason)
	return flow == Enum.AnalyticsEconomyFlowType.Source and currency == "Coins" and amount > 0 and kind == "Gameplay" and reason == "elimination"
end)
check(source and type(source[6]) == "number", "elimination coins: a gameplay source, with the balance")
check(Shop.request(whale, "buy", "weapon", "Spritzer").ok, "the payer buys the Spritzer")
check(find("economy", whale, function(flow, _, amount, _, kind)
	return flow == Enum.AnalyticsEconomyFlowType.Sink and amount == 400 and kind == "Shop"
end), "a shop sink of 400")
check(not find("economy", newbie, function(_, _, _, _, _, reason)
	return reason == "test"
end), "nothing sent for test grants")
check(Economy.grantPurchase(regular, "receipt:t1", 500), "the regular buys coins")
check(select(2, Metrics.segments(regular)) == "payer" and counter("metrics.newPayers") == 1, "and counts as paying from now on")
check(find("economy", regular, function(flow, _, amount, _, kind)
	return flow == Enum.AnalyticsEconomyFlowType.Source and amount == 500 and kind == "IAP"
end), "an IAP source")

-- Analytics failing.
Metrics.setAnalytics({})
Economy.grant(whale, "metrics:fail", "elimination", 5, 0)
task.wait(0.1)
check(counter("metrics.analyticsErrors") >= 1, "a failed analytics call is counted")
local errors = 0
for _, n in Telemetry.snapshot().errors do
	errors += n
end
check(errors == 0, "and nothing else breaks")

-- Sessions.
task.wait(60)
local samples = Telemetry.snapshot().samples
check(samples["metrics.concurrent"] and samples["metrics.concurrent"].average == 3, "concurrent players sampled each minute")
newbie.Parent = nil
whale.Parent = nil
task.wait(0.2)
check(counter("metrics.sessionLength.under5") == 2, "two sessions of 1-5 minutes")
check(counter("metrics.sessions.new") == 1 and counter("metrics.sessions.payer") == 1, "sessions by segment")
check(counter("metrics.leftBeforeFirstShot.new") == 1 and counter("metrics.leftBeforeFirstShot.returning") == 1, "left without firing, by segment")
samples = Telemetry.snapshot().samples
check(samples["metrics.sessionMinutes.payer"] and samples["metrics.sessionMinutes.payer"].average > 1, "minutes by segment")

return { status = "PASS", checks = checks }
