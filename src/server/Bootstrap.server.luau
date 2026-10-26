-- Starts the server. Services load in dependency order, none requires one
-- loaded after it, and each start() only wires itself up:
--   MapService            the map in Workspace, spawn lookups
--   MatchScoreService     this round's scores
--   TeamService           active team slots and balancing
--   PlayerLifecycleService  join, PLAY, spawn, spectate, leave
--   AFKService            idle warning and AFK spectating
--   RoundService          WAITING -> ACTIVE -> RESULTS, snapshots to clients
--   TestControls          test-only scoring and timing (Studio / allow-list)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Before anyone can spawn: avatars only come from PLAY.
Players.CharacterAutoLoads = false

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)
local Services = script.Parent.Services
local MapService = require(Services.MapService)
local MatchScoreService = require(Services.MatchScoreService)
local TeamService = require(Services.TeamService)
local PlayerLifecycleService = require(Services.PlayerLifecycleService)
local AFKService = require(Services.AFKService)
local RoundService = require(Services.RoundService)
local TestControls = require(script.Parent.TestControls)

MapService.load(GameConfig.DEFAULT_MAP)
MatchScoreService.reset()
TeamService.start()
PlayerLifecycleService.start()
AFKService.start()
RoundService.start()
TestControls.start()

if Players.MaxPlayers ~= GameConfig.MAX_PLAYERS then
	warn(`[Fart Wars] Max Players is {Players.MaxPlayers}; set it to {GameConfig.MAX_PLAYERS} in Game Settings → Places`)
end
print(`[Fart Wars] server ready: {GameConfig.DEFAULT_MAP}, {RoundService.getMode().displayName}`)
