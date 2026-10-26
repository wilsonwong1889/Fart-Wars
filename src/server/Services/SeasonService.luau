-- Seasons (SeasonConfig; masterplan 6.3), behind FeatureFlags.SEASONS.
-- While a season is on, every player earns season XP (a share of their XP
-- and XP_PER_CHALLENGE per weekly challenge done) and is paid each tier
-- they reach, once (grant IDs carry the season and tier). This week's
-- challenges count eliminations, assists, Fart Dashes, barrels, minutes
-- of play, streaks and zone time. A new week starts the challenge counts
-- again; a new season starts the track again (what was earned stays).
-- Clients hear about it through ProgressEvent { kind = "season", ... } and
-- the SeasonTier / SeasonXP attributes; Workspace's SeasonActive says
-- whether a season is on.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local SeasonConfig = require(Shared.Config.SeasonConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LoadoutService = require(script.Parent.LoadoutService)
local EliminationService = require(script.Parent.EliminationService)
local DashService = require(script.Parent.DashService)
local BarrelService = require(script.Parent.BarrelService)
local ZoneService = require(script.Parent.ZoneService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local SeasonService = {}

local seasons = SeasonConfig.seasons
local enabledOverride: boolean? = nil
local clock: (() -> number) = os.time
local activeSeconds: { [Player]: number } = {}
local started = false

-- Test seams: other seasons, a clock, and on/off whatever the flag says.
function SeasonService.setSeasons(list: { SeasonConfig.Season })
	seasons = list
end
function SeasonService.setClock(fn: () -> number)
	clock = fn
end
function SeasonService.testEnable(enabled: boolean?)
	enabledOverride = enabled
	workspace:SetAttribute("SeasonActive", SeasonService.current() ~= nil)
end

local function enabled(): boolean
	if enabledOverride ~= nil then
		return enabledOverride
	end
	return FeatureFlags.SEASONS
end

-- The season on now (nil when seasons are off or between seasons).
function SeasonService.current(): SeasonConfig.Season?
	if not enabled() then
		return nil
	end
	return SeasonConfig.current(seasons, clock())
end

local function available(challenge: SeasonConfig.Challenge): boolean
	return challenge.needs == nil or (FeatureFlags :: any)[challenge.needs] == true
end

-- This week's challenges for the current season.
function SeasonService.challenges(): { SeasonConfig.Challenge }
	local season = SeasonService.current()
	if not season then
		return {}
	end
	return SeasonConfig.weekly(season, SeasonConfig.week(season, clock()), available)
end

local function saving(player: Player): any?
	local profile = DataService.get(player)
	return if profile and not profile.temporary then profile.data else nil
end

-- Brings a profile up to the current season and week.
local function sync(player: Player, season: SeasonConfig.Season): any?
	local data = saving(player)
	if not data then
		return nil
	end
	local week = SeasonConfig.week(season, clock())
	if data.SeasonId ~= season.id then
		DataService.update(player, function(d)
			d.SeasonId = season.id
			d.SeasonXP = 0
			d.SeasonTier = 0
			d.SeasonWeek = week
			d.SeasonProgress = {}
			d.SeasonDone = {}
		end)
	elseif data.SeasonWeek ~= week then
		DataService.update(player, function(d)
			d.SeasonWeek = week
			d.SeasonProgress = {}
			d.SeasonDone = {}
		end)
	end
	return data
end

-- What the season screen shows, for one player.
function SeasonService.view(player: Player): { [string]: any }?
	local season = SeasonService.current()
	if not season then
		return nil
	end
	local data = sync(player, season)
	local challenges = {}
	for _, challenge in SeasonService.challenges() do
		table.insert(challenges, {
			id = challenge.id,
			text = challenge.text,
			goal = challenge.goal,
			progress = if data then math.min(challenge.goal, data.SeasonProgress[challenge.stat] or 0) else 0,
			done = data ~= nil and table.find(data.SeasonDone, challenge.id) ~= nil,
		})
	end
	return {
		kind = "season",
		id = season.id,
		name = season.name,
		endsAt = season.endsAt,
		serverNow = clock(),
		xp = if data then data.SeasonXP else 0,
		tier = if data then data.SeasonTier else 0,
		challenges = challenges,
		saving = data ~= nil,
	}
end

local function push(player: Player)
	local view = SeasonService.view(player)
	if view and player.Parent == Players then
		(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProgressEvent") :: RemoteEvent):FireClient(player, view)
	end
	local data = saving(player)
	player:SetAttribute("SeasonTier", if view and data then data.SeasonTier else nil)
	player:SetAttribute("SeasonXP", if view and data then data.SeasonXP else nil)
end
SeasonService.push = push

-- Pays every tier reached and not yet paid.
local function payTiers(player: Player, season: SeasonConfig.Season, data: any)
	local reached = SeasonConfig.tierFor(data.SeasonXP)
	local changedLoadout = false
	while data.SeasonTier < reached do
		local tier = data.SeasonTier + 1
		local reward = SeasonConfig.tiers[tier]
		DataService.update(player, function(d)
			d.SeasonTier = tier
			if reward.cosmetic and not table.find(d.OwnedCosmetics, reward.cosmetic) then
				table.insert(d.OwnedCosmetics, reward.cosmetic)
				changedLoadout = true
			end
			if reward.badge and not table.find(d.Badges, reward.badge) then
				table.insert(d.Badges, reward.badge)
			end
		end)
		EconomyService.grant(player, `season:{season.id}:tier{tier}`, "season", reward.coins, 0)
		Telemetry.count("Season.tiers")
		Telemetry.count(`Season.reachedTier.{tier}`)
	end
	if changedLoadout then
		LoadoutService.push(player)
	end
end

-- Adds season XP (for XP earned, or a challenge).
function SeasonService.addXP(player: Player, amount: number)
	local season = SeasonService.current()
	local data = season and sync(player, season :: SeasonConfig.Season)
	if not (season and data) or amount <= 0 then
		return
	end
	DataService.update(player, function(d)
		d.SeasonXP += math.floor(amount)
	end)
	payTiers(player, season, data)
	push(player)
end

-- Counts `amount` of `stat` toward this week's challenges.
function SeasonService.count(player: Player, stat: string, amount: number?)
	local season = SeasonService.current()
	local data = season and sync(player, season :: SeasonConfig.Season)
	if not (season and data) then
		return
	end
	local relevant = false
	for _, challenge in SeasonService.challenges() do
		if challenge.stat == stat and not table.find(data.SeasonDone, challenge.id) then
			relevant = true
		end
	end
	if not relevant then
		return
	end
	DataService.update(player, function(d)
		d.SeasonProgress[stat] = (d.SeasonProgress[stat] or 0) + (amount or 1)
	end)
	local finished = 0
	for _, challenge in SeasonService.challenges() do
		if challenge.stat == stat and not table.find(data.SeasonDone, challenge.id) and data.SeasonProgress[stat] >= challenge.goal then
			DataService.update(player, function(d)
				table.insert(d.SeasonDone, challenge.id)
			end)
			finished += 1
			Telemetry.count("Season.challenges")
			Telemetry.count(`Season.challenge.{challenge.id}`)
		end
	end
	if finished > 0 then
		SeasonService.addXP(player, finished * SeasonConfig.XP_PER_CHALLENGE)
	else
		push(player)
	end
end

function SeasonService.tick(dt: number)
	if not SeasonService.current() then
		return
	end
	for _, player in Players:GetPlayers() do
		if PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE then
			local seconds = (activeSeconds[player] or 0) + dt
			if seconds >= 60 then
				seconds -= 60
				SeasonService.count(player, "minutes", 1)
			end
			activeSeconds[player] = seconds
		end
	end
end

function SeasonService.start()
	if started then
		return
	end
	started = true
	workspace:SetAttribute("SeasonActive", SeasonService.current() ~= nil)
	EconomyService.XPGained:Connect(function(player, xp, reason)
		if reason ~= "test" and reason ~= "season" then
			SeasonService.addXP(player, xp * SeasonConfig.XP_SHARE)
		end
	end)
	EliminationService.Eliminated:Connect(function(elimination)
		if not elimination.counted then
			return
		end
		if elimination.killer and elimination.killer ~= elimination.victim then
			SeasonService.count(elimination.killer, "eliminations", 1)
		end
		for _, helper in elimination.assists do
			SeasonService.count(helper, "assists", 1)
		end
	end)
	EliminationService.Alpha:Connect(function(player)
		SeasonService.count(player, "streaks", 1)
	end)
	DashService.Dashed:Connect(function(player)
		SeasonService.count(player, "dashes", 1)
	end)
	BarrelService.Exploded:Connect(function(owner)
		if owner and owner.Parent == Players then
			SeasonService.count(owner, "barrels", 1)
		end
	end)
	ZoneService.Held:Connect(function(player, seconds)
		SeasonService.count(player, "zoneSeconds", seconds)
	end)
	DataService.Loaded:Connect(function(player)
		push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		activeSeconds[player] = nil
	end)
	Health.loop("Season", 1, function(dt)
		SeasonService.tick(dt)
		workspace:SetAttribute("SeasonActive", SeasonService.current() ~= nil)
	end)
end

return SeasonService
