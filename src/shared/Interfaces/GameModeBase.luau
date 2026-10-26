-- The contract every game mode keeps. RoundService runs the clock and the
-- phases; the mode decides which score events count and who won, so a new
-- mode needs no change to the round manager. GameModeBase.new fills in the
-- defaults: most points wins, level scores are a draw.
export type Scores = { [string]: number }
export type Result = { winner: string?, draw: boolean, scores: Scores }
export type ScoreEvent = {
	team: string, -- the team the point goes to
	source: string, -- "elimination", or "test" from the test-only controls
	killer: Player?,
	victim: Player?,
	-- Teams when it happened; a mode uses these over the current ones.
	killerTeam: string?,
	victimTeam: string?,
}
export type Context = {
	roundId: number,
	teamIds: { string },
	teamOf: (Player) -> string?,
}
export type GameMode = {
	id: string,
	displayName: string,
	roundSeconds: number,
	intermissionSeconds: number,
	validateScoreEvent: (GameMode, ScoreEvent, Context) -> boolean,
	computeResult: (GameMode, Scores, { string }) -> Result,
	onRoundStart: (GameMode, Context) -> (),
	onRoundEnd: (GameMode, Context, Result) -> (),
}

local GameModeBase = {}

-- The team with the most points wins; a tie at the top is a draw, so 0-0 is
-- a draw too.
function GameModeBase.mostPointsWins(scores: Scores, teamIds: { string }): Result
	local best, leaders = -math.huge, {}
	for _, team in teamIds do
		local score = scores[team] or 0
		if score > best then
			best, leaders = score, { team }
		elseif score == best then
			table.insert(leaders, team)
		end
	end
	local copy = {}
	for _, team in teamIds do
		copy[team] = scores[team] or 0
	end
	if #leaders == 1 then
		return { winner = leaders[1], draw = false, scores = copy }
	end
	return { winner = nil, draw = true, scores = copy }
end

function GameModeBase.new(definition: { [string]: any }): GameMode
	assert(type(definition.id) == "string", "a game mode needs an id")
	assert(type(definition.roundSeconds) == "number" and definition.roundSeconds > 0, "a game mode needs roundSeconds")
	assert(
		type(definition.intermissionSeconds) == "number" and definition.intermissionSeconds >= 0,
		"a game mode needs intermissionSeconds"
	)
	local mode = {
		id = definition.id,
		displayName = definition.displayName or definition.id,
		roundSeconds = definition.roundSeconds,
		intermissionSeconds = definition.intermissionSeconds,
		validateScoreEvent = definition.validateScoreEvent or function(_, event: ScoreEvent, context: Context)
			return table.find(context.teamIds, event.team) ~= nil
		end,
		computeResult = definition.computeResult or function(_, scores: Scores, teamIds: { string })
			return GameModeBase.mostPointsWins(scores, teamIds)
		end,
		onRoundStart = definition.onRoundStart or function() end,
		onRoundEnd = definition.onRoundEnd or function() end,
	}
	return table.freeze(mode) :: any
end

return GameModeBase
