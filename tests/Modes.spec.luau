-- The game-mode contract and the client clock:
--   * most points wins; a tie at the top (0-0 included) is a draw
--   * GameModeBase.new insists on an id and times, and fills the defaults
--   * Team Elimination counts test events, and real eliminations only from
--     an active killer on the scoring team against the other team
--   * RoundClock reads the time left from an absolute end time, and formats
--     it rounding up (so 0:00 shows only at the end)
--   * Gas Control counts zone points (and test ones), never eliminations;
--     most points wins, nobody holding it is a draw
--   * its timing suits 20 players on the full-size map: a capture is
--     quicker with more of a team in it but never instant, alone it's
--     long enough for the others to answer, points come every second,
--     the zone counts often enough for the quickest capture to fill
--     smoothly; the zone is as far from both spawns, and the walk there
--     and a capture leave nearly all the round for holding it
--   * the rotation's modes all exist and fit the default map, and its
--     minimum server size is between a round's start and a full server
local shared = game.ReplicatedStorage.Shared
local GameModeBase = require(shared.Interfaces.GameModeBase)
local RoundClock = require(shared.RoundClock)
local GameConfig = require(shared.Config.GameConfig)
local MapConfig = require(shared.Config.MapConfig)
local TeamElimination = require(game.ServerScriptService.Server.Modes.TeamElimination)
local GasControl = require(game.ServerScriptService.Server.Modes.GasControl)
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

local ORDER = { "Stinkers", "Sharters" }
local win = GameModeBase.mostPointsWins({ Stinkers = 7, Sharters = 5 }, ORDER)
check(win.winner == "Stinkers" and not win.draw, "7-5 is a Stinkers win")
check(win.scores.Stinkers == 7 and win.scores.Sharters == 5, "the result keeps the scores")
local draw = GameModeBase.mostPointsWins({ Stinkers = 4, Sharters = 4 }, ORDER)
check(draw.winner == nil and draw.draw, "4-4 is a draw")
local nil0 = GameModeBase.mostPointsWins({}, ORDER)
check(nil0.draw and nil0.scores.Stinkers == 0 and nil0.scores.Sharters == 0, "0-0 is a draw")

check(not pcall(GameModeBase.new, { roundSeconds = 10, intermissionSeconds = 5 }), "a mode needs an id")
check(not pcall(GameModeBase.new, { id = "X", intermissionSeconds = 5 }), "and a round length")
local custom = GameModeBase.new({ id = "X", roundSeconds = 60, intermissionSeconds = 5 })
check(custom.displayName == "X" and custom:computeResult({ Stinkers = 1 }, ORDER).winner == "Stinkers", "defaults filled in")

check(TeamElimination.id == "TeamElimination", "the Phase 1 mode")
check(TeamElimination.roundSeconds == 300 and TeamElimination.intermissionSeconds == 15, "five minutes, then fifteen seconds")
local a, b, c = Instance.new("Player"), Instance.new("Player"), Instance.new("Player")
local teams = { [a] = "Stinkers", [b] = "Sharters", [c] = "Stinkers" }
local context = { roundId = 1, teamIds = ORDER, teamOf = function(p)
	return teams[p]
end }
check(TeamElimination:validateScoreEvent({ team = "Stinkers", source = "test" }, context), "a test event counts")
check(not TeamElimination:validateScoreEvent({ team = "Nobody", source = "test" }, context), "not for a team that doesn't exist")
check(TeamElimination:validateScoreEvent({ team = "Stinkers", source = "elimination", killer = a, victim = b }, context), "Stinkers take out a Sharter")
check(not TeamElimination:validateScoreEvent({ team = "Stinkers", source = "elimination", killer = a, victim = c }, context), "no points for a teammate")
check(not TeamElimination:validateScoreEvent({ team = "Sharters", source = "elimination", killer = a, victim = b }, context), "the point goes to the killer's team")
check(not TeamElimination:validateScoreEvent({ team = "Stinkers", source = "elimination", killer = a, victim = a }, context), "no points for yourself")
check(not TeamElimination:validateScoreEvent({ team = "Stinkers", source = "client" }, context), "unknown sources don't count")

local snapshot = { phaseEndTime = 1000 } :: any
check(RoundClock.remaining(snapshot, 700) == 300, "300 seconds left")
check(RoundClock.remaining(snapshot, 1200) == 0, "never below zero")
check(RoundClock.remaining({ phaseEndTime = nil } :: any, 5) == nil, "no end while waiting")
check(RoundClock.format(300) == "5:00", "5:00")
check(RoundClock.format(299.2) == "5:00", "rounds up")
check(RoundClock.format(59) == "0:59", "0:59")
check(RoundClock.format(0.01) == "0:01" and RoundClock.format(0) == "0:00", "0:00 only at the end")
check(RoundClock.format(nil) == "--:--", "no time")

-- Gas Control.
check(GasControl.id == "GasControl" and GasControl.displayName == "Gas Control" and GasControl.objective == "zone", "Gas Control is about the zone")
check(GasControl.roundSeconds == 300 and GasControl.intermissionSeconds == 15, "in the same five-minute rounds")
check(string.find(string.lower(GasControl.hint), "plaza", 1, true) ~= nil, "its hint says where: " .. GasControl.hint)
check(GasControl:validateScoreEvent({ team = "Stinkers", source = "zone" }, context), "zone points count")
check(GasControl:validateScoreEvent({ team = "Sharters", source = "test" }, context), "and test ones")
check(not GasControl:validateScoreEvent({ team = "Stinkers", source = "elimination", killer = a, victim = b }, context), "eliminations never do")
check(not GasControl:validateScoreEvent({ team = "Stinkers", source = "elimination", killerBot = -1001, victimBot = -1002, killerTeam = "Stinkers", victimTeam = "Sharters" }, context), "nor bots'")
check(not GasControl:validateScoreEvent({ team = "Nobody", source = "zone" }, context), "nor points for a team that doesn't exist")
check(not GasControl:validateScoreEvent({ team = "Stinkers", source = "client" }, context), "nor anything else")
check(GasControl:computeResult({ Stinkers = 87, Sharters = 120 }, ORDER).winner == "Sharters", "most points wins")
check(GasControl:computeResult({}, ORDER).draw, "nobody held it: a draw")

-- Its timing, for 20 players on the full-size map.
local ZONE = GameConfig.ZONE
local times = ZONE.CAPTURE_SECONDS
for i = 2, #times do
	check(times[i] < times[i - 1], `{i} of a team take it quicker than {i - 1}`)
end
check(times[1] >= 5 and times[1] <= 8, `alone, it takes long enough for the others to answer ({times[1]}s)`)
check(times[#times] >= 2 and #times <= GameConfig.MAX_TEAM_SIZE, `a crowd is quicker, never instant ({times[#times]}s for {#times} or more)`)
check(ZONE.POINTS == 1 and ZONE.POINT_SECONDS == 1, "a point a second while it's held")
check(times[#times] / ZONE.TICK_SECONDS >= 10, "the zone counts often enough for the quickest capture to fill smoothly")
check(ZONE.POINT_SECONDS % ZONE.TICK_SECONDS == 0, "and lands on every point")
local MapService = require(game.ServerScriptService.Server.Services.MapService)
local map = MapService.load(GameConfig.DEFAULT_MAP)
local entry = MapConfig[GameConfig.DEFAULT_MAP]
local zone = map.Zones:FindFirstChild("ControlZone") :: BasePart
check(zone and entry.zone == "Zones/ControlZone", "the default map has the zone")
local radius = math.min(zone.Size.Y, zone.Size.Z) / 2
local walks = {}
for _, team in ORDER do
	local nearest = math.huge
	for _, pad in MapService.spawns(team) do
		nearest = math.min(nearest, ((pad.Position - zone.Position) * Vector3.new(1, 0, 1)).Magnitude - radius)
	end
	table.insert(walks, nearest)
end
check(math.abs(walks[1] - walks[2]) < 1e-3, "the zone is as far from both spawns")
-- By the lanes it's at most twice as far as in a straight line.
local walkSeconds = 2 * walks[1] / GameConfig.WALK_SPEED
check(walkSeconds + times[1] < GasControl.roundSeconds / 10, `walking there and taking it alone (about {math.ceil(walkSeconds + times[1])}s) leaves nearly all the round to hold it`)
check(walks[1] > radius, "and the spawns are well clear of it")

-- The rotation.
for _, id in GameConfig.MODE_ROTATION do
	local module = game.ServerScriptService.Server.Modes:FindFirstChild(id)
	check(module and table.find(entry.modes, id), `{id} exists and the default map lists it`)
	local mode = require(module) :: any
	check(mode.objective ~= "zone" or entry.zone ~= nil, `{id} has a zone on the default map`)
end
check(table.find(GameConfig.MODE_ROTATION, GameConfig.DEFAULT_MODE), "the default mode takes its turn too")
check(GameConfig.ROTATION_MIN_PLAYERS > GameConfig.MIN_ACTIVE_PLAYERS and GameConfig.ROTATION_MIN_PLAYERS < GameConfig.MAX_PLAYERS, "rotation starts above a round's minimum and below a full server")

return { status = "PASS", checks = checks }
