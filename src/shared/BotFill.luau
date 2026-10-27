-- How many bots a server needs and on which team, as a plain function of
-- the head counts, so the rules are specced without Roblox (BotDirector
-- applies the answer):
--   * no bots at all while no human is in the server
--   * otherwise bots make up the difference to the fill target, counting
--     every human in the server, playing or not (at 4: 1 human, 3 bots;
--     2, 2; 3, 1; 4 or more, none)
--   * the teams' totals (humans + bots) stay level: a bot that has to go
--     comes from the bigger team, a new one joins the smaller, and a tie
--     goes by team order
--   * a team 2 or more ahead of another, with a bot on it, sends a bot
--     across (when humans changed sides or stopped playing)
-- The answer is the smallest change that gets there; applying it and
-- asking again gives an empty plan.
export type Counts = { [string]: number }
export type Move = { from: string, to: string }
export type Plan = {
	-- One entry per bot, by team.
	add: { string },
	remove: { string },
	move: { Move },
	-- Bots on each team once it's done.
	bots: Counts,
}

local BotFill = {}

-- How many bots the server should have.
function BotFill.target(humans: number, fillTo: number): number
	return if humans <= 0 then 0 else math.max(0, fillTo - humans)
end

-- `humans`: everyone in the server; `humanCounts`: the humans playing on
-- each team; `botCounts`: the bots on each team now.
function BotFill.plan(humans: number, humanCounts: Counts, botCounts: Counts, order: { string }, fillTo: number): Plan
	local bots: Counts = {}
	local have = 0
	for _, team in order do
		bots[team] = math.max(0, botCounts[team] or 0)
		have += bots[team]
	end
	local plan: Plan = { add = {}, remove = {}, move = {}, bots = bots }
	if #order == 0 then
		return plan
	end
	local function total(team: string): number
		return (humanCounts[team] or 0) + bots[team]
	end
	-- The biggest team with a bot on it, or the smallest team; the first in
	-- order wins a tie.
	local function biggestWithBot(): string?
		local best: string? = nil
		for _, team in order do
			if bots[team] > 0 and (best == nil or total(team) > total(best)) then
				best = team
			end
		end
		return best
	end
	local function smallest(): string
		local best = order[1]
		for _, team in order do
			if total(team) < total(best) then
				best = team
			end
		end
		return best
	end

	local want = BotFill.target(humans, fillTo)
	while have > want do
		local team = biggestWithBot() :: string
		bots[team] -= 1
		have -= 1
		table.insert(plan.remove, team)
	end
	while have < want do
		local team = smallest()
		bots[team] += 1
		have += 1
		table.insert(plan.add, team)
	end
	-- Each move narrows the gap, so this ends.
	while true do
		local from, to = biggestWithBot(), smallest()
		if not from or total(from) - total(to) < 2 then
			break
		end
		bots[from] -= 1
		bots[to] += 1
		table.insert(plan.move, { from = from, to = to })
	end
	return plan
end

return BotFill
