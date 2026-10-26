-- Starts the server. Services load in dependency order, none requires one
-- loaded after it, and each start() only wires itself up:
--   DataService           player profiles: load, autosave, save on leave
--   MapService            the map in Workspace, spawn lookups
--   MatchScoreService     this round's scores
--   TeamService           active team slots and balancing
--   PlayerLifecycleService  join, PLAY, spawn, spectate, leave
--   AFKService            idle warning and AFK spectating
--   ExperimentService     retention experiments: cohorts, values, telemetry
--   EliminationService    each death credited once; streaks; the alpha call
--   GasService            the gas meter, recovery, countdowns, explosions
--   CombatService         the Gas Blaster: shots and hits
--   ExplosionService      blasts and chain reactions
--   BarrelService         gas barrels
--   DashService           Fart Dash checks
--   AbilityService        the Q ability (Recovery Burst, Gas Pulse)
--   ProjectileService     stink bombs and their clouds
--   EconomyService        coins, XP, levels, unlocks, mastery, stats
--   LoadoutService        equipped weapon, ability and cosmetic; applied on spawn
--   ShopService           buying and equipping (ShopRequest)
--   RewardsService        the daily track, ten-minute gifts, free spins
--   SocialService         playing with friends: squad bonus, welcomes
--   MonetizationService   the store: coin packs (receipts) and passes
--   PrestigeService       prestige: preview, confirm, reset (flagged off)
--   MetricsService        live metrics by segment, the onboarding funnel
--   RoundService          WAITING -> ACTIVE -> RESULTS (or one continuous
--                         match), the mode each round, snapshots to clients
--   ZoneService           Gas Control's zone: who holds it, its points
--   SeasonService         the free seasonal track and weekly challenges
--   EventService          live events: Bean Rain (flagged off)
--   TestControls          test-only commands (Studio / allow-list)
-- Telemetry (logs, counters, rejected requests, flags) is used by all of
-- them; Moderation (started first, so banned players are turned away
-- before anything else) acts on the flags and takes player reports;
-- Health runs the service loops and checks the server's health.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Before anyone can spawn: avatars only come from PLAY.
Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Services = script.Parent.Services
local DataService = require(Services.DataService)
local MapService = require(Services.MapService)
local MatchScoreService = require(Services.MatchScoreService)
local TeamService = require(Services.TeamService)
local PlayerLifecycleService = require(Services.PlayerLifecycleService)
local AFKService = require(Services.AFKService)
local ExperimentService = require(Services.ExperimentService)
local EliminationService = require(Services.EliminationService)
local GasService = require(Services.GasService)
local CombatService = require(Services.CombatService)
local ExplosionService = require(Services.ExplosionService)
local BarrelService = require(Services.BarrelService)
local DashService = require(Services.DashService)
local AbilityService = require(Services.AbilityService)
local ProjectileService = require(Services.ProjectileService)
local EconomyService = require(Services.EconomyService)
local LoadoutService = require(Services.LoadoutService)
local ShopService = require(Services.ShopService)
local RewardsService = require(Services.RewardsService)
local SocialService = require(Services.SocialService)
local MonetizationService = require(Services.MonetizationService)
local PrestigeService = require(Services.PrestigeService)
local MetricsService = require(Services.MetricsService)
local RoundService = require(Services.RoundService)
local ZoneService = require(Services.ZoneService)
local SeasonService = require(Services.SeasonService)
local EventService = require(Services.EventService)
local TestControls = require(script.Parent.TestControls)
local Moderation = require(script.Parent.Moderation)
local Health = require(script.Parent.Health)
local ReleaseConfig = require(Shared.Config.ReleaseConfig)

Moderation.start()
Health.start({ probe = DataService.probe })
DataService.start()
MapService.load(GameConfig.DEFAULT_MAP)
MatchScoreService.reset()
TeamService.start()
PlayerLifecycleService.start()
AFKService.start()
ExperimentService.start()
EliminationService.start()
GasService.start()
CombatService.start()
ExplosionService.start()
BarrelService.start()
DashService.start()
AbilityService.start()
ProjectileService.start()
EconomyService.start()
LoadoutService.start()
ShopService.start()
RewardsService.start()
SocialService.start()
MonetizationService.start()
PrestigeService.start()
MetricsService.start()
RoundService.start()
ZoneService.start()
SeasonService.start()
EventService.start()
TestControls.start()

if Players.MaxPlayers ~= GameConfig.MAX_PLAYERS then
	warn(`[Fart Wars] Max Players is {Players.MaxPlayers}; set it to {GameConfig.MAX_PLAYERS} in Game Settings → Places`)
end
print(`[Fart Wars] server ready: v{ReleaseConfig.label(ReleaseConfig.channel(game.PlaceId))}, {GameConfig.DEFAULT_MAP}, {RoundService.getMode().displayName}, {FeatureFlags.MATCH_MODE}`)
