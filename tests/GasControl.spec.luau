-- Gas Control and mode rotation (masterplan 6.1), with one client:
--   * a Gas Control round: the mode in the snapshot and on the HUD, the
--     zone ring shown; a team alone in the zone scores a point a second, a
--     contested or empty zone scores nothing; eliminations don't score;
--     holders earn a little, capped per round; most points wins
--   * the HUD's zone line in words (not just colour)
--   * rotation: off by default; on, small servers stay on the default mode
--     and bigger ones take turns; a map without a zone fails validation
--   * /fw mode
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local MapConfig = require(Shared.Config.MapConfig)
local MapBase = require(Shared.Interfaces.MapBase)
local Round = require(server.Services.RoundService)
local Zone = require(server.Services.ZoneService)
local Scores = require(server.Services.MatchScoreService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Team = require(server.Services.TeamService)
local Data = require(server.Services.DataService)
local Telemetry = require(server.Telemetry)
local TestControls = require(server.TestControls)

check(FeatureFlags.MODE_ROTATION == false and GameConfig.DEFAULT_MODE == "TeamElimination", "as shipped: no rotation, Team Elimination")
check(table.find(MapConfig.BrainrotBattlefield.modes, "GasControl") and MapConfig.BrainrotBattlefield.zone, "the map supports Gas Control")
check(TestControls.mode("gascontrol") and not TestControls.mode("nope"), "/fw mode picks the next round's mode")

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local HUD = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.HUDController)
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.05)
	return player
end
local foe = join("Foe", 2)
Lifecycle.requestPlay(me, "Stinkers")
Lifecycle.requestPlay(foe, "Sharters")
task.wait(0.5)
Team.testSetTeam(me, "Stinkers")
Team.testSetTeam(foe, "Sharters")
local snapshot = Round.snapshot()
check(Round.phase() == "ACTIVE" and snapshot.mode == "GasControl" and snapshot.objective == "zone" and snapshot.modeName == "Gas Control", "a Gas Control round")
task.wait(1.2)
local zone, ring = Zone.parts()
check(zone and ring and ring.Transparency < 1, "the zone ring shows")
check(Zone.isActive() and workspace:GetAttribute("ZoneActive") == true and workspace:GetAttribute("ZoneOwner") == nil, "an empty zone")
check(Scores.getScores().Stinkers == 0 and Scores.getScores().Sharters == 0, "scores nothing")
HUD.renderZone()
check(HUD.parts.zone.Visible and HUD.parts.zone.Text == "STAND IN THE PLAZA TO SCORE", "the HUD says what to do")
game:GetService("RunService").Heartbeat:Fire(0.2)
check(HUD.parts.phase.Text == "GAS CONTROL", "and which mode it is")

-- Holding it. Spots are the map layout's, built MapConfig's scale bigger.
local S = MapConfig.BrainrotBattlefield.scale
local function put(player: Player, x: number, z: number)
	player.Character:PivotTo(CFrame.new(x * S, 3, z * S))
end
task.wait(3.2) -- past spawn protection
put(me, 14, 0)
put(foe, 0, 60)
task.wait(5.05)
local held = Scores.getScores().Stinkers
check(held >= 4 and held <= 6 and Scores.getScores().Sharters == 0, `alone in the zone: a point a second ({held})`)
check(workspace:GetAttribute("ZoneOwner") == "Stinkers" and workspace:GetAttribute("Zone_Stinkers") == 1, "published")
HUD.renderZone()
check(HUD.parts.zone.Text == "STINKERS HOLD THE PLAZA · +1 A SECOND", "the HUD says who holds it, in words")
check(ring.Color == require(Shared.Config.TeamConfig).teams.Stinkers.color, "and the ring in their colour")
-- Contested.
put(foe, -14, 0)
task.wait(1.1)
local before = Scores.getScores()
task.wait(4)
local after = Scores.getScores()
check(after.Stinkers == before.Stinkers and after.Sharters == before.Sharters, "both teams in it: nobody scores")
check(workspace:GetAttribute("ZoneContested") == true, "contested")
HUD.renderZone()
check(HUD.parts.zone.Text == "PLAZA CONTESTED (1 v 1)", "the HUD shows the standoff")
-- Eliminations clear the zone but don't score.
Gas.add(foe, 100, { attacker = me, cause = "shot", weapon = "GasBlaster" })
task.wait(1.1)
local afterBang = Scores.getScores()
check(afterBang.Stinkers <= after.Stinkers + 1, "an elimination isn't a point in Gas Control")
task.wait(3)
check(Scores.getScores().Stinkers > afterBang.Stinkers, "but the zone is ours again")

-- Holding rewards: a few a round.
-- (Moving about in the zone, so nobody counts as AFK.)
for i = 1, math.ceil(GameConfig.ZONE.REWARD_SECONDS * (GameConfig.ZONE.REWARDS_PER_ROUND + 3) / 20) do
	task.wait(20)
	put(me, 14, if i % 2 == 0 then 0 else 8)
end
local zoneGrants = 0
for _, line in assert(Data.get(me)).data.Ledger do
	if line.reason == "zone" then
		zoneGrants += 1
	end
end
check(zoneGrants >= 1, "holding the zone pays, through the ledger")
check((Telemetry.snapshot().counters["Economy.coins.zone"] or 0) == GameConfig.ZONE.COINS * GameConfig.ZONE.REWARDS_PER_ROUND, "up to the round's cap")

-- The result.
Round.testEndPhaseIn(0)
task.wait(0.5)
local result = Round.snapshot().result
check(Round.phase() == "RESULTS" and result and result.winner == "Stinkers", "most zone points wins")
task.wait(1.2)
check(not Zone.isActive() and ring.Transparency == 1 and not HUD.parts.zone.Visible, "between rounds the zone is off")

-- Rotation. (Foe stood still all round and went AFK: back in.)
Lifecycle.requestPlay(foe, "Sharters")
task.wait(0.2)
Round.testEndPhaseIn(0)
task.wait(0.5)
check(Round.snapshot().mode == "TeamElimination", "without rotation, the default mode")
task.wait(1.2)
check(not Zone.isActive() and workspace:GetAttribute("ZoneActive") == false, "no zone in Team Elimination")
Round.testRotation(true)
Round.testEndPhaseIn(0)
task.wait(0.5)
Round.testEndPhaseIn(0)
task.wait(0.5)
check(Round.snapshot().mode == "TeamElimination", `rotation on, but under {GameConfig.ROTATION_MIN_PLAYERS} players: the default`)
for i = 3, 6 do
	local extra = join(`P{i}`, i)
	Lifecycle.requestPlay(extra, nil)
end
task.wait(0.5)
local seen = {}
for _ = 1, 4 do
	Round.testEndPhaseIn(0)
	task.wait(0.5)
	Round.testEndPhaseIn(0)
	task.wait(0.5)
	table.insert(seen, Round.snapshot().mode)
end
check(seen[1] ~= seen[2] and seen[1] == seen[3] and seen[2] == seen[4] and table.find(seen, "GasControl"), `six players: the modes take turns ({table.concat(seen, ", ")})`)
Round.testRotation(nil)

-- A map that lists a zone must have one.
local bare = Instance.new("Model")
local ok, problems = MapBase.validate(bare, MapConfig.BrainrotBattlefield, { "Stinkers", "Sharters" })
check(not ok and string.find(table.concat(problems, ";"), "no control zone part", 1, true), "a missing zone fails validation")

return { status = "PASS", checks = checks }
