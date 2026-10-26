-- This round's score for each team. Points only count while a round is
-- open, and the game mode decides whether an event is valid. Phase 1 has no
-- combat, so the only events are the test-only ones from TestControls; the
-- Phase 2 Gas Blaster reports eliminations through recordElimination.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local GameModeBase = require(Shared.Interfaces.GameModeBase)
local Signal = require(Shared.Signal)

local MatchScoreService = {}

-- Fires after any change to the scores (a point, or a reset).
MatchScoreService.Changed = Signal.new()

local scores: { [string]: number } = {}
local open = false
local closesAt = math.huge
local mode: GameModeBase.GameMode? = nil
local context: GameModeBase.Context? = nil

function MatchScoreService.reset()
	for _, team in TeamConfig.order do
		scores[team] = 0
	end
	MatchScoreService.Changed:Fire()
end

-- RoundService opens scoring for a round. Points stop counting at
-- `endsAt` (server time) even before the round loop next looks.
function MatchScoreService.open(roundMode: GameModeBase.GameMode, roundContext: GameModeBase.Context, endsAt: number)
	mode, context, open, closesAt = roundMode, roundContext, true, endsAt
end

function MatchScoreService.closeAt(endsAt: number)
	closesAt = endsAt
end

function MatchScoreService.freeze()
	open = false
end

function MatchScoreService.isOpen(): boolean
	return open and workspace:GetServerTimeNow() < closesAt
end

function MatchScoreService.getScores(): { [string]: number }
	return table.clone(scores)
end

-- Adds `points` (1 by default) if the round is open and the mode accepts
-- the event: an elimination, a zone tick, a test point.
function MatchScoreService.record(event: GameModeBase.ScoreEvent, points: number?): boolean
	if not (MatchScoreService.isOpen() and mode and context) then
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
