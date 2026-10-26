-- Starts the server. Services load in dependency order, none requires one
-- loaded after it, and each start() only wires itself up:
--   DataService           player profiles: load, autosave, save on leave
--   MapService            the map in Workspace, spawn lookups
--   MatchScoreService     this round's scores
--   TeamService           active team slots and balancing
--   PlayerLifecycleService  join, PLAY, spawn, spectate, leave
--   AFKService            idle warning and AFK spectating
--   EliminationService    each death credited once; streaks; the alpha call
--   GasService            the gas meter, recovery, countdowns, explosions
--   CombatService         the Gas Blaster: shots and hits
--   ExplosionService      blasts and chain reactions
--   BarrelService         gas barrels
--   DashService           Fart Dash checks
--   EconomyService        coins, XP, levels, unlocks, mastery, stats
--   RoundService          WAITING -> ACTIVE -> RESULTS (or one continuous
--                         match), snapshots to clients
--   TestControls          test-only commands (Studio / allow-list)
-- Telemetry (logs, counters, rejected requests) is used by all of them.
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
local EliminationService = require(Services.EliminationService)
local GasService = require(Services.GasService)
local CombatService = require(Services.CombatService)
local ExplosionService = require(Services.ExplosionService)
local BarrelService = require(Services.BarrelService)
local DashService = require(Services.DashService)
local EconomyService = require(Services.EconomyService)
local RoundService = require(Services.RoundService)
local TestControls = require(script.Parent.TestControls)

DataService.start()
MapService.load(GameConfig.DEFAULT_MAP)
MatchScoreService.reset()
TeamService.start()
PlayerLifecycleService.start()
AFKService.start()
EliminationService.start()
GasService.start()
CombatService.start()
ExplosionService.start()
BarrelService.start()
DashService.start()
EconomyService.start()
RoundService.start()
TestControls.start()

if Players.MaxPlayers ~= GameConfig.MAX_PLAYERS then
	warn(`[Fart Wars] Max Players is {Players.MaxPlayers}; set it to {GameConfig.MAX_PLAYERS} in Game Settings → Places`)
end
print(`[Fart Wars] server ready: {GameConfig.DEFAULT_MAP}, {RoundService.getMode().displayName}, {FeatureFlags.MATCH_MODE}`)
