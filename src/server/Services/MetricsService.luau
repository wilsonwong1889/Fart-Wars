-- Live metrics (masterplan 5.5), split the way the decisions need them:
-- new vs returning players and paying vs free players.
--   * the onboarding funnel for new players: joined, PLAY, first shot,
--     first hit, first elimination, 5 and 10 minutes (funnel.<step>, and
--     Roblox's onboarding funnel in the Creator Hub)
--   * fairness: eliminations and deaths by segment (fairness.kills.<seg>,
--     fairness.deaths.<seg>), and by level band (level1to9, level10to24,
--     level25to49, level50, prestige), so paid and veteran advantage shows
--   * sessions: length buckets for the median (metrics.sessionLength.*),
--     sessions and minutes by segment, concurrent players each minute
--   * the economy's sources and sinks, sent on to Roblox's economy events
-- Every call to Roblox's AnalyticsService is protected: if one fails, the
-- game carries on and it is counted (metrics.analyticsErrors). Nothing
-- personal is sent, only the segments.
local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")

local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EliminationService = require(script.Parent.EliminationService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local MetricsService = {}

-- The onboarding funnel, in order. A step's key is a Telemetry.first kind
-- (or "joined" / "played").
MetricsService.FUNNEL = table.freeze({
	{ key = "joined", name = "Joined" },
	{ key = "played", name = "Pressed PLAY" },
	{ key = "shot", name = "First shot" },
	{ key = "hit", name = "First hit" },
	{ key = "elimination", name = "First elimination" },
	{ key = "reached5Minutes", name = "Five minutes played" },
	{ key = "reached10Minutes", name = "Ten minutes played" },
})
-- Session length buckets (upper bound in minutes).
MetricsService.LENGTHS = table.freeze({ 1, 5, 10, 20, 40, math.huge })

type Session = { new: boolean, payer: boolean, joinedAt: number, steps: { [string]: boolean }, played: boolean }
local sessions: { [Player]: Session } = {}
local analytics: any = AnalyticsService
local warned = false
local started = false

-- Test seam: a stand-in AnalyticsService.
function MetricsService.setAnalytics(fake: any)
	analytics = fake
end

local function call(method: string, ...: any)
	local fn = analytics[method]
	local ok, err = pcall(fn, analytics, ...)
	if not ok then
		Telemetry.count("metrics.analyticsErrors")
		if not warned then
			warned = true
			warn(`[FW] AnalyticsService.{method} failed (counted from now on): {tostring(err)}`)
		end
	end
end

-- "new" or "returning", and "payer" or "free".
function MetricsService.segments(player: Player): (string?, string?)
	local session = sessions[player]
	if not session then
		return nil, nil
	end
	return if session.new then "new" else "returning", if session.payer then "payer" else "free"
end

local function fields(player: Player): { [string]: string }
	local age, pay = MetricsService.segments(player)
	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = age or "unknown",
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = pay or "unknown",
	}
end

local function step(player: Player, key: string)
	local session = sessions[player]
	if not session or session.steps[key] then
		return
	end
	for index, entry in MetricsService.FUNNEL do
		if entry.key == key then
			session.steps[key] = true
			local age = if session.new then "new" else "returning"
			Telemetry.count(`funnel.{age}.{key}`)
			if session.new then
				call("LogOnboardingFunnelStepEvent", player, index, entry.name, fields(player))
			end
			return
		end
	end
end

local function both(player: Player): (string, string)
	local age, pay = MetricsService.segments(player)
	return age or "unknown", pay or "unknown"
end

-- Which level band a player is in, for veteran advantage.
function MetricsService.levelBand(player: Player): string
	local rank = player:GetAttribute("Prestige")
	if type(rank) == "number" and rank > 0 then
		return "prestige"
	end
	local level = player:GetAttribute("Level")
	level = if type(level) == "number" then level else 1
	return if level >= 50 then "level50" elseif level >= 25 then "level25to49" elseif level >= 10 then "level10to24" else "level1to9"
end

local function onElimination(elimination: EliminationService.Elimination)
	if not elimination.counted then
		return
	end
	local victimAge, victimPay = both(elimination.victim)
	Telemetry.count(`fairness.deaths.{victimAge}`)
	Telemetry.count(`fairness.deaths.{victimPay}`)
	Telemetry.count(`fairness.deaths.{MetricsService.levelBand(elimination.victim)}`)
	local killer = elimination.killer
	if killer and killer ~= elimination.victim then
		local killerAge, killerPay = both(killer)
		Telemetry.count(`fairness.kills.{killerAge}`)
		Telemetry.count(`fairness.kills.{killerPay}`)
		Telemetry.count(`fairness.kills.{MetricsService.levelBand(killer)}`)
	end
end

-- Roblox's transaction types for our grant reasons.
local TIMED = { daily = true, spin = true, gift = true }

local function onTransaction(player: Player, coins: number, reason: string, balance: number)
	if reason == "test" then
		return
	end
	local session = sessions[player]
	if reason == "purchase" and coins > 0 and session and not session.payer then
		session.payer = true
		Telemetry.count("metrics.newPayers")
	end
	local kind = if reason == "purchase" and coins > 0 then "IAP"
		elseif reason == "purchase" or reason == "refund" then "Shop"
		elseif TIMED[reason] then "TimedReward"
		else "Gameplay"
	local flow = if coins > 0 then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	call("LogEconomyEvent", player, flow, "Coins", math.abs(coins), balance, kind, reason, fields(player))
end

local function lengthBucket(minutes: number): string
	for _, limit in MetricsService.LENGTHS do
		if minutes < limit then
			return if limit == math.huge then "40plus" else `under{limit}`
		end
	end
	return "40plus"
end

local function onLeave(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if not session then
		return
	end
	local minutes = (os.clock() - session.joinedAt) / 60
	local age = if session.new then "new" else "returning"
	local pay = if session.payer then "payer" else "free"
	Telemetry.count(`metrics.sessionLength.{lengthBucket(minutes)}`)
	Telemetry.count(`metrics.sessions.{age}`)
	Telemetry.count(`metrics.sessions.{pay}`)
	Telemetry.sample(`metrics.sessionMinutes.{age}`, minutes)
	Telemetry.sample(`metrics.sessionMinutes.{pay}`, minutes)
	-- First-minute abandonment: left before ever firing.
	if not session.steps.shot then
		Telemetry.count(`metrics.leftBeforeFirstShot.{age}`)
	end
end

function MetricsService.start()
	if started then
		return
	end
	started = true
	DataService.Loaded:Connect(function(player, profile)
		local data = profile.data
		local visit = profile.visit
		sessions[player] = {
			new = visit ~= nil and not visit.returning,
			payer = #data.PassesGranted > 0 or #data.Receipts > 0,
			joinedAt = os.clock(),
			steps = {},
			played = false,
		}
		local age, pay = MetricsService.segments(player)
		Telemetry.count(`metrics.joins.{age}`)
		Telemetry.count(`metrics.joins.{pay}`)
		step(player, "joined")
	end)
	PlayerLifecycleService.Spawned:Connect(function(player)
		step(player, "played")
	end)
	Telemetry.FirstDone:Connect(function(player, kind)
		step(player, kind)
	end)
	EliminationService.Eliminated:Connect(onElimination)
	EconomyService.Transaction:Connect(onTransaction)
	Players.PlayerRemoving:Connect(onLeave)
	Health.loop("Metrics", 60, function()
		Telemetry.sample("metrics.concurrent", #Players:GetPlayers())
	end)
end

return MetricsService
