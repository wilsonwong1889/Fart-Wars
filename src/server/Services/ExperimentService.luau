-- Experiments (ExperimentConfig, masterplan 4.5): each player's cohorts,
-- the values those cohorts get, and telemetry by cohort for the goals that
-- matter (ten-minute engagement, next-day and day-7 return, session length).
-- A player's variant in each experiment they are enrolled in is the
-- attribute Exp_<key> (for the client); the counters are
-- exp.<key>.<variant>.<metric>.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperimentConfig = require(Shared.Config.ExperimentConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local DataService = require(script.Parent.DataService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local ExperimentService = {}

type Cohort = { variants: { [string]: string }, activeSeconds: number, reachedTen: boolean }
local cohorts: { [Player]: Cohort } = {}
local config = ExperimentConfig
local started = false

-- Test seam: another set of experiments, as ExperimentConfig with other
-- `experiments` (re-assigns everyone here).
function ExperimentService.setConfig(fake: any)
	config = fake
	for _, player in Players:GetPlayers() do
		ExperimentService.assign(player)
	end
end

-- Counts `metric` for every experiment the player is enrolled in.
function ExperimentService.track(player: Player, metric: string, amount: number?)
	local cohort = cohorts[player]
	if not cohort then
		return
	end
	for key, variant in cohort.variants do
		Telemetry.count(`exp.{key}.{variant}.{metric}`, amount)
	end
end

function ExperimentService.assign(player: Player)
	local previous = cohorts[player]
	local cohort: Cohort = {
		variants = {},
		activeSeconds = if previous then previous.activeSeconds else 0,
		reachedTen = if previous then previous.reachedTen else false,
	}
	cohorts[player] = cohort
	for _, experiment in config.experiments do
		local variant = config.assign(experiment, player.UserId)
		if variant then
			cohort.variants[experiment.key] = variant
		end
		player:SetAttribute(`Exp_{experiment.key}`, variant)
	end
end

-- The player's variant in experiment `key` (nil if not enrolled).
function ExperimentService.variant(player: Player, key: string): string?
	local cohort = cohorts[player]
	return if cohort then cohort.variants[key] else nil
end

local function find(key: string): ExperimentConfig.Experiment?
	for _, experiment in config.experiments do
		if experiment.key == key then
			return experiment
		end
	end
	return nil
end

-- The value the player gets for experiment `key`.
function ExperimentService.value(player: Player, key: string): any
	local experiment = find(key)
	if not experiment then
		return nil
	end
	local variant = ExperimentService.variant(player, key)
	for _, entry in experiment.variants do
		if entry.name == variant then
			return entry.value
		end
	end
	return experiment.variants[1].value
end

-- What a shop weapon costs this player.
function ExperimentService.weaponPrice(player: Player, price: number): number
	return config.weaponPrice(price, ExperimentService.value(player, "earlyUnlock"))
end

function ExperimentService.tick(dt: number)
	for player, cohort in cohorts do
		if next(cohort.variants) and PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE then
			cohort.activeSeconds += dt
			if not cohort.reachedTen and cohort.activeSeconds >= 600 then
				cohort.reachedTen = true
				ExperimentService.track(player, "reached10Minutes")
			end
		end
	end
end

function ExperimentService.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(ExperimentService.assign)
	for _, player in Players:GetPlayers() do
		ExperimentService.assign(player)
	end
	DataService.Loaded:Connect(function(player, profile)
		-- A profile can load before this service hears the player joined.
		if not cohorts[player] then
			ExperimentService.assign(player)
		end
		local visit = profile.visit
		ExperimentService.track(player, "sessions")
		if visit then
			ExperimentService.track(player, if visit.returning then "returning" else "newPlayers")
			if visit.nextDay then
				ExperimentService.track(player, "returnedNextDay")
			end
			if visit.d1 then
				ExperimentService.track(player, "D1")
			end
			if visit.d7 then
				ExperimentService.track(player, "D7")
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local cohort = cohorts[player]
		if cohort then
			ExperimentService.track(player, "activeMinutes", math.floor(cohort.activeSeconds / 60))
		end
		cohorts[player] = nil
	end)
	Health.loop("Experiments", 1, ExperimentService.tick)
end

return ExperimentService
