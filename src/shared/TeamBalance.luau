-- The team rules, as plain functions of the active player counts, so the
-- server decides with them and the client greys out choices with the same
-- answer. "Spread" is the gap between the biggest and smallest team.
--   * nobody joins a full team
--   * a join goes where it leaves the smallest spread
--   * a player's choice counts only when it is as balanced as the best
--     placement (with two teams: only when the teams are level, or toward
--     the smaller one)
--   * friends break a tie, never more
--   * a voluntary switch has to make the spread smaller
export type Counts = { [string]: number }
export type Why = "full" | "preferred" | "preferenceRejected" | "balance" | "friends" | "random"
export type Options = {
	preferred: string?,
	-- How many of the player's friends are active on each team.
	friends: Counts?,
	random: Random?,
}

local TeamBalance = {}

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

-- The teams a new player could join without unbalancing more than needed.
function TeamBalance.bestTeams(counts: Counts, order: { string }, maxSize: number): { string }
	local best, teams = math.huge, {}
	for _, team in order do
		if (counts[team] or 0) < maxSize then
			local after = TeamBalance.spreadAfterJoin(counts, order, team)
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
function TeamBalance.preferenceAllowed(counts: Counts, order: { string }, maxSize: number, team: string): boolean
	return table.find(TeamBalance.bestTeams(counts, order, maxSize), team) ~= nil
end

-- The team a joining player goes to, and why. nil when every team is full.
function TeamBalance.choose(counts: Counts, order: { string }, maxSize: number, options: Options?): (string?, Why)
	local opts: Options = options or {}
	local candidates = TeamBalance.bestTeams(counts, order, maxSize)
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

	-- Tied. Friends first, then the smallest team (only differs with more
	-- than two teams), then chance.
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
	local fewest = math.huge
	for _, team in candidates do
		fewest = math.min(fewest, counts[team] or 0)
	end
	local smallest = {}
	for _, team in candidates do
		if (counts[team] or 0) == fewest then
			table.insert(smallest, team)
		end
	end
	local pick = if #smallest == 1 then smallest[1] else smallest[(opts.random or Random.new()):NextInteger(1, #smallest)]
	return pick, if rejected then "preferenceRejected" elseif #smallest == 1 then "balance" else "random"
end

-- Whether an active player may move from `from` to `to`: only when it
-- makes the teams more even. Nobody is ever moved without asking.
function TeamBalance.canSwitch(counts: Counts, order: { string }, maxSize: number, from: string, to: string): boolean
	if from == to or not table.find(order, to) or (counts[to] or 0) >= maxSize or (counts[from] or 0) < 1 then
		return false
	end
	local after = table.clone(counts)
	after[from] = (after[from] or 0) - 1
	after[to] = (after[to] or 0) + 1
	return spread(after, order) < spread(counts, order)
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
