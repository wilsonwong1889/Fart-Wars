-- The award cards on the results screen, worked out from the round's real
-- stats. A tally keeps each combatant's numbers for one round, by the id
-- the kill feed uses (a player's UserId, a bot's negative BotId), and
-- compute() picks the winners:
--   TopFragger    the most eliminations
--   ChainMaster   the biggest chain reaction: the most chain and barrel
--                 eliminations in one go (each within CHAIN_GAP_SECONDS of
--                 the one before; a chain's credit only ever goes to the
--                 one player who set it off, so it's never shared)
--   BarrelBuster  the most gas barrels set off
--   TeamPlayer    the most assists
-- Nobody wins an award with 0, and one combatant can win several. A tie
-- goes to the award's own tie-breaker (fewer deaths for Top Fragger and
-- Team Player, more chain eliminations in all for Chain Master, more
-- barrel eliminations for Barrel Buster), then to whoever got to the
-- number first, then to a player over a bot, then to the lower id, so the
-- same round always gives the same awards. Pure: AwardService feeds it
-- during the round, and the specs use it directly.
local RoundAwards = {}

-- Chain and barrel eliminations by one combatant this close together are
-- one chain reaction. A chain's steps are about a second apart (the
-- explosion countdown), plus 0.6 s for each barrel in between, and two
-- barrels in a row is the most the chain's depth cap leaves room for.
RoundAwards.CHAIN_GAP_SECONDS = 3

-- The awards, in the order the cards show.
RoundAwards.ORDER = table.freeze({ "TopFragger", "ChainMaster", "BarrelBuster", "TeamPlayer" })

-- What each award counts, and its tie-breaker (a stat where more wins,
-- or fewer if `fewer`).
type Rule = { stat: string, tiebreak: string, fewer: boolean }
local RULES: { [string]: Rule } = table.freeze({
	TopFragger = table.freeze({ stat = "eliminations", tiebreak = "deaths", fewer = true }),
	ChainMaster = table.freeze({ stat = "bestChain", tiebreak = "chainKills", fewer = false }),
	BarrelBuster = table.freeze({ stat = "barrels", tiebreak = "barrelKills", fewer = false }),
	TeamPlayer = table.freeze({ stat = "assists", tiebreak = "deaths", fewer = true }),
}) :: any

-- One combatant's round.
export type Stats = {
	id: number,
	eliminations: number,
	-- Times eliminated (by anyone or anything that ends a life in gas).
	deaths: number,
	assists: number,
	barrels: number,
	-- Eliminations by chain reactions (cause "chain" or "barrel"), and by
	-- barrels alone.
	chainKills: number,
	barrelKills: number,
	-- The biggest chain reaction, and the one going now (its size and the
	-- time of its last elimination).
	bestChain: number,
	chain: number,
	chainAt: number,
	-- When each stat got to its value (server time), for ties.
	reached: { [string]: number },
}

-- Who someone is when the round ends.
export type Who = { id: number, name: string, team: string?, bot: boolean }

-- One card: the award, its winner and their number.
export type Award = {
	award: string,
	id: number,
	name: string,
	team: string?,
	bot: boolean,
	value: number,
}

-- An elimination as the kill feed has it: ids, and what finished them off.
export type Elimination = {
	at: number,
	victim: number?,
	killer: number?,
	assists: { number }?,
	cause: string,
}

local Tally = {}
Tally.__index = Tally
export type Tally = typeof(setmetatable({} :: { stats: { [number]: Stats } }, Tally))

-- An empty round.
function RoundAwards.new(): Tally
	return setmetatable({ stats = {} }, Tally)
end

local function entry(self: Tally, id: number): Stats
	local stats = self.stats[id]
	if not stats then
		stats = {
			id = id,
			eliminations = 0,
			deaths = 0,
			assists = 0,
			barrels = 0,
			chainKills = 0,
			barrelKills = 0,
			bestChain = 0,
			chain = 0,
			chainAt = -math.huge,
			reached = {},
		}
		self.stats[id] = stats
	end
	return stats
end

local function bump(stats: Stats, key: string, at: number)
	local counts = stats :: any
	counts[key] += 1
	stats.reached[key] = at
end

-- One elimination: the killer's, the victim's death and each helper's
-- assist. A chain or barrel elimination also builds the killer's chain
-- reaction, which ends once CHAIN_GAP_SECONDS pass without another.
function Tally.elimination(self: Tally, e: Elimination)
	if e.victim then
		bump(entry(self, e.victim), "deaths", e.at)
	end
	local killer = e.killer
	if killer and killer ~= e.victim then
		local stats = entry(self, killer)
		bump(stats, "eliminations", e.at)
		if e.cause == "chain" or e.cause == "barrel" then
			bump(stats, "chainKills", e.at)
			if e.cause == "barrel" then
				bump(stats, "barrelKills", e.at)
			end
			stats.chain = if e.at - stats.chainAt <= RoundAwards.CHAIN_GAP_SECONDS then stats.chain + 1 else 1
			stats.chainAt = e.at
			if stats.chain > stats.bestChain then
				stats.bestChain = stats.chain
				stats.reached.bestChain = e.at
			end
		end
	end
	for _, helper in e.assists or {} do
		if helper ~= killer and helper ~= e.victim then
			bump(entry(self, helper), "assists", e.at)
		end
	end
end

-- A gas barrel `id` set off (shot it last, or set it off with a chain).
function Tally.barrel(self: Tally, id: number, at: number)
	bump(entry(self, id), "barrels", at)
end

-- A copy of `id`'s numbers this round, or nil if they haven't any.
function Tally.statsOf(self: Tally, id: number): Stats?
	local stats = self.stats[id]
	if not stats then
		return nil
	end
	local copy = table.clone(stats)
	copy.reached = table.clone(stats.reached)
	return copy
end

-- Whether `a` beats `b` for the award `rule` decides.
local function beats(rule: Rule, a: Stats, b: Stats, whoA: Who, whoB: Who): boolean
	local va, vb = (a :: any)[rule.stat], (b :: any)[rule.stat]
	if va ~= vb then
		return va > vb
	end
	local ta, tb = (a :: any)[rule.tiebreak], (b :: any)[rule.tiebreak]
	if ta ~= tb then
		return if rule.fewer then ta < tb else ta > tb
	end
	local ra, rb = a.reached[rule.stat] or math.huge, b.reached[rule.stat] or math.huge
	if ra ~= rb then
		return ra < rb
	end
	if whoA.bot ~= whoB.bot then
		return not whoA.bot
	end
	if math.abs(a.id) ~= math.abs(b.id) then
		return math.abs(a.id) < math.abs(b.id)
	end
	return a.id > b.id
end

-- The round's awards, in ORDER: for each, the best of those `lookup`
-- still finds (it gives each id's name, team and whether it's a bot, or
-- nil for someone who has left, who can't win), as long as their number
-- isn't 0. An award nobody earned is left out, so an empty round has none.
function RoundAwards.compute(tally: Tally, lookup: (number) -> Who?): { Award }
	local present: { [number]: Who } = {}
	for id in tally.stats do
		local who = lookup(id)
		if who then
			present[id] = who
		end
	end
	local awards: { Award } = {}
	for _, award in RoundAwards.ORDER do
		local rule = RULES[award]
		local best: Stats? = nil
		for id, who in present do
			local stats = tally.stats[id]
			if (stats :: any)[rule.stat] > 0 and (best == nil or beats(rule, stats, best, who, present[best.id])) then
				best = stats
			end
		end
		if best then
			local who = present[best.id]
			table.insert(awards, {
				award = award,
				id = best.id,
				name = who.name,
				team = who.team,
				bot = who.bot,
				value = (best :: any)[rule.stat],
			})
		end
	end
	return awards
end

return RoundAwards
