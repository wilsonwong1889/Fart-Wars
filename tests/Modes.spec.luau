-- The game-mode contract and the client clock:
--   * most points wins; a tie at the top (0-0 included) is a draw
--   * GameModeBase.new insists on an id and times, and fills the defaults
--   * Team Elimination counts test events, and real eliminations only from
--     an active killer on the scoring team against the other team
--   * RoundClock reads the time left from an absolute end time, and formats
--     it rounding up (so 0:00 shows only at the end)
local shared = game.ReplicatedStorage.Shared
local GameModeBase = require(shared.Interfaces.GameModeBase)
local RoundClock = require(shared.RoundClock)
local TeamElimination = require(game.ServerScriptService.Server.Modes.TeamElimination)
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

return { status = "PASS", checks = checks }
