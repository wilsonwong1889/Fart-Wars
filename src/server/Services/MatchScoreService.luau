-- This round's score for each team. Points only count while a round is
-- open, and the game mode decides whether an event is valid. Phase 1 has no
-- combat, so the only events are the test-only ones from TestControls; the
-- Phase 2 Gas Blaster reports eliminations through recordElimination.
-- A kill finished before the buzzer counts though it lands after it: an
-- explosion whose countdown started before the buzzer (GasService and
-- BotService stamp each one) is still taken until the result is (freeze),
-- and RoundService waits for it (landsBy). Nothing newer counts, and
-- nothing newer can start: from the buzzer no gas lands, so a barrel fuse
-- lit or a stink bomb thrown just before it blasts nobody.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local GameModeBase = require(Shared.Interfaces.GameModeBase)
local Signal = require(Shared.Signal)

-- An explosion lands this long after its countdown starts (and a moment
-- more, for the scheduler to get round to it).
local LANDS_AFTER = GameConfig.GAS.EXPLOSION_COUNTDOWN_SECONDS + 0.1

local MatchScoreService = {}

-- Fires after any change to the scores (a point, or a reset).
MatchScoreService.Changed = Signal.new()

local scores: { [string]: number } = {}
local open = false
local closesAt = math.huge
-- A round has ended and the next hasn't been set up (the results).
local ended = false
local mode: GameModeBase.GameMode? = nil
local context: GameModeBase.Context? = nil
-- When the latest explosion countdown this round started (before its
-- buzzer).
local lastCountdownAt = -math.huge

function MatchScoreService.reset()
	ended = false
	for _, team in TeamConfig.order do
		scores[team] = 0
	end
	MatchScoreService.Changed:Fire()
end

-- RoundService opens scoring for a round. Points stop counting at
-- `endsAt` (server time) even before the round loop next looks.
function MatchScoreService.open(roundMode: GameModeBase.GameMode, roundContext: GameModeBase.Context, endsAt: number)
	mode, context, open, closesAt = roundMode, roundContext, true, endsAt
	lastCountdownAt = -math.huge
end

function MatchScoreService.closeAt(endsAt: number)
	closesAt = endsAt
end

function MatchScoreService.freeze()
	open = false
	ended = true
end

-- Whether something happening now counts for the round: anything while
-- it's open, and after the buzzer an explosion whose countdown started
-- before it (`countdownAt`), until the result is taken.
function MatchScoreService.counts(countdownAt: number?): boolean
	if not open then
		return false
	end
	return workspace:GetServerTimeNow() < closesAt or (countdownAt ~= nil and countdownAt < closesAt)
end

function MatchScoreService.isOpen(): boolean
	return MatchScoreService.counts(nil)
end

-- An explosion countdown started at `at` (GasService, BotService).
function MatchScoreService.countdownStarted(at: number)
	if open and at < closesAt and at > lastCountdownAt then
		lastCountdownAt = at
	end
end

-- When the round's result can be taken: at the buzzer, or once the last
-- explosion that was counting down at it has landed, so its point is in.
function MatchScoreService.landsBy(): number
	return math.max(closesAt, lastCountdownAt + LANDS_AFTER)
end

-- The gap between rounds: from a round's buzzer (even before the round
-- loop next looks) until the next one is set up, the results. Nobody
-- fights then. Waiting for players isn't one: that's warm-up.
function MatchScoreService.betweenRounds(): boolean
	return ended or (open and workspace:GetServerTimeNow() >= closesAt)
end

function MatchScoreService.getScores(): { [string]: number }
	return table.clone(scores)
end

-- Adds `points` (1 by default) if the round is open and the mode accepts
-- the event: an elimination, a zone tick, a test point. (An explosion
-- finished before the buzzer counts just after it too: see counts.)
function MatchScoreService.record(event: GameModeBase.ScoreEvent, points: number?): boolean
	if not (MatchScoreService.counts(event.countdownAt) and mode and context) then
		return false
	end
	if not mode:validateScoreEvent(event, context) then
		return false
	end
	scores[event.team] = (scores[event.team] or 0) + (points or 1)
	MatchScoreService.Changed:Fire()
	return true
end

-- An elimination's point (if the mode scores eliminations).
function MatchScoreService.recordElimination(event: GameModeBase.ScoreEvent): boolean
	return MatchScoreService.record(event)
end

-- Test-only: `count` simulated eliminations for `team`. Server code only
-- (TestControls, or the Studio command bar); never reachable from a client.
function MatchScoreService.testAddElimination(team: string, count: number?): (boolean, string)
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return false, "test controls are off (GameConfig.TEST_CONTROLS.ENABLED)"
	end
	if not TeamConfig.teams[team] then
		return false, `no team "{team}"`
	end
	if not MatchScoreService.isOpen() then
		return false, "scores are frozen outside a round"
	end
	local added = 0
	for _ = 1, math.clamp(math.floor(count or 1), 1, 100) do
		if MatchScoreService.recordElimination({ team = team, source = "test" }) then
			added += 1
		end
	end
	return added > 0, `{TeamConfig.teams[team].name} +{added} (now {scores[team]})`
end

MatchScoreService.reset()

return MatchScoreService
