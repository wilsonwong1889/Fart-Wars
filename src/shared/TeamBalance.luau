-- The team rules, as plain functions of the active player counts, so the
-- server decides with them and the client greys out choices with the same
-- answer. "Spread" is the gap between the biggest and smallest team.
-- The rules keep the humans fair. Bots hold slots too, but any human may
-- take a bot's slot: the bot crosses over or leaves, and BotFill levels
-- the teams again. So when the caller says how many of the counts are bots
-- (`bots`), the spread is between the humans alone, and a team is full
-- only when humans fill it. With no bots it's the same either way.
--   * nobody joins a full team
--   * a join goes where it leaves the smallest spread
--   * a player's choice counts only when it is as balanced as the best
--     placement (with two teams: only when the teams are level, or toward
--     the smaller one)
--   * friends break a tie, never more
--   * any tie left goes the same way every time: to the smaller team
--     (fewest humans, then fewest overall, so no bot has to move), then
--     the team behind on score, then the first team in order
--   * a voluntary switch has to make the spread smaller
export type Counts = { [string]: number }
export type Why = "full" | "preferred" | "preferenceRejected" | "balance" | "friends" | "behind" | "order"
export type Options = {
	preferred: string?,
	-- How many of the player's friends are active on each team.
	friends: Counts?,
	-- This round's score for each team.
	scores: Counts?,
	-- How many of the counts on each team are bots (none when nil).
	bots: Counts?,
}

local TeamBalance = {}

-- The humans on each team: the counts less the bots.
function TeamBalance.humans(counts: Counts, order: { string }, bots: Counts?): Counts
	local humans = {}
	for _, team in order do
		local botsHere = if bots then bots[team] or 0 else 0
		humans[team] = math.max(0, (counts[team] or 0) - botsHere)
	end
	return humans
end

local function spread(counts: Counts, order: { string }): number
	local low, high = math.huge, -math.huge
	for _, team in order do
		local n = counts[team] or 0
		low = math.min(low, n)
		high = math.max(high, n)
	end
	return if #order == 0 then 0 else high - low
end
TeamBalance.spread = spread

-- The spread if one more player joined `team`.
function TeamBalance.spreadAfterJoin(counts: Counts, order: { string }, team: string): number
	local after = table.clone(counts)
	after[team] = (after[team] or 0) + 1
	return spread(after, order)
end

-- The teams a new player could join without unbalancing the humans more
-- than needed (`bots`: how many of the counts are bots, whose slots are
-- open to them).
function TeamBalance.bestTeams(counts: Counts, order: { string }, maxSize: number, bots: Counts?): { string }
	local humans = TeamBalance.humans(counts, order, bots)
	local best, teams = math.huge, {}
	for _, team in order do
		if humans[team] < maxSize then
			local after = TeamBalance.spreadAfterJoin(humans, order, team)
			if after < best then
				best, teams = after, { team }
			elseif after == best then
				table.insert(teams, team)
			end
		end
	end
	return teams
end

-- Whether picking `team` on the home screen would be honoured right now.
function TeamBalance.preferenceAllowed(counts: Counts, order: { string }, maxSize: number, team: string, bots: Counts?): boolean
	return table.find(TeamBalance.bestTeams(counts, order, maxSize, bots), team) ~= nil
end

-- The teams in `list` with the fewest by `counts` (players, or points),
-- in `list`'s order.
local function fewestIn(list: { string }, counts: Counts): { string }
	local fewest = math.huge
	for _, team in list do
		fewest = math.min(fewest, counts[team] or 0)
	end
	local kept = {}
	for _, team in list do
		if (counts[team] or 0) == fewest then
			table.insert(kept, team)
		end
	end
	return kept
end

-- The team a joining player goes to, and why. nil when every team is full.
function TeamBalance.choose(counts: Counts, order: { string }, maxSize: number, options: Options?): (string?, Why)
	local opts: Options = options or {}
	local candidates = TeamBalance.bestTeams(counts, order, maxSize, opts.bots)
	if #candidates == 0 then
		return nil, "full"
	end
	local preferred = opts.preferred
	local rejected = false
	if preferred ~= nil and table.find(order, preferred) then
		if table.find(candidates, preferred) then
			return preferred, "preferred"
		end
		rejected = true
	end
	if #candidates == 1 then
		return candidates[1], if rejected then "preferenceRejected" else "balance"
	end

	-- Tied. Friends first, then the smallest team (fewest humans: only
	-- differs with more than two teams; then fewest overall: only differs
	-- with bots, and takes the free slot over a bot's), then the team behind
	-- on score, then team order.
	local friends = opts.friends or {}
	local mostFriends = 0
	for _, team in candidates do
		mostFriends = math.max(mostFriends, friends[team] or 0)
	end
	if mostFriends > 0 then
		local withFriends = {}
		for _, team in candidates do
			if (friends[team] or 0) == mostFriends then
				table.insert(withFriends, team)
			end
		end
		if #withFriends == 1 then
			return withFriends[1], if rejected then "preferenceRejected" else "friends"
		end
		candidates = withFriends
	end
	local smallest = fewestIn(fewestIn(candidates, TeamBalance.humans(counts, order, opts.bots)), counts)
	if #smallest == 1 then
		return smallest[1], if rejected then "preferenceRejected" else "balance"
	end
	local behind = fewestIn(smallest, opts.scores or {})
	-- `smallest` kept `order`'s order, so the first one left is first in order.
	return behind[1], if rejected then "preferenceRejected" elseif #behind == 1 then "behind" else "order"
end

-- Whether an active player may move from `from` to `to`: only when it
-- makes the humans more even (a bot on `to` makes room). Nobody is ever
-- moved without asking.
function TeamBalance.canSwitch(counts: Counts, order: { string }, maxSize: number, from: string, to: string, bots: Counts?): boolean
	local humans = TeamBalance.humans(counts, order, bots)
	if from == to or not table.find(order, to) or humans[to] >= maxSize or (humans[from] or 0) < 1 then
		return false
	end
	local after = table.clone(humans)
	after[from] -= 1
	after[to] += 1
	return spread(after, order) < spread(humans, order)
end

-- Whether a round can start: enough active players, and nobody alone on
-- the battlefield without an opponent.
function TeamBalance.canStart(counts: Counts, order: { string }, minPlayers: number): boolean
	local total = 0
	for _, team in order do
		local n = counts[team] or 0
		if n == 0 then
			return false
		end
		total += n
	end
	return total >= minPlayers
end

return TeamBalance
