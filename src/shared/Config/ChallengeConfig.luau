-- Daily challenges (FeatureFlags.CHALLENGES): three a day for each player,
-- new at 00:00 UTC (the daily shop's day, DailyShopConfig.day). Each pays
-- REWARD once, the moment it's done (ChallengeService). Progress is saved,
-- so a challenge can be finished over several sessions and servers that day.
--
-- Servers are often mostly bots, and kills of or by bots pay out nothing,
-- so every challenge here can be done by one player alone with bots, and
-- nothing a bot does or suffers counts toward any of them: rounds played
-- and won (a round takes its five minutes whoever is in it), Fart Dashes,
-- and gas barrels (shot by the player, or set off by their own blasts). No
-- challenge counts eliminations or gas, which need real enemies.
export type Challenge = {
	id: string,
	-- What it says on the DAILY screen and when it's done, and a tip.
	text: string,
	hint: string,
	-- What counts (PlayStatsService) and how much of it.
	stat: string,
	goal: number,
	-- Challenges of the same kind are never on the same day.
	kind: string,
}

local ChallengeConfig = {}

ChallengeConfig.PER_DAY = 3

-- Each challenge pays this once, when it's done (docs/economy.md).
ChallengeConfig.REWARD = table.freeze({ coins = 40, xp = 75 })

-- A round counts as played with at least this many seconds ACTIVE in it,
-- and as won with that long on the winning team (no last-second team
-- switches onto the winners).
ChallengeConfig.ROUND_SECONDS = 60

-- The pool. Kinds: "time" (playing), "win", "dash", "barrels", "chain".
ChallengeConfig.pool = table.freeze({
	table.freeze({ id = "play3", text = "Play 3 rounds", hint = "A round counts after a minute in it", stat = "rounds", goal = 3, kind = "time" }),
	table.freeze({ id = "minutes15", text = "Play for 15 minutes", hint = "On the battlefield. AFK doesn't count, bro", stat = "minutes", goal = 15, kind = "time" }),
	table.freeze({ id = "win1", text = "Win a round", hint = "Be on the winning team for a minute or more", stat = "wins", goal = 1, kind = "win" }),
	table.freeze({ id = "dash30", text = "Fart Dash 30 times", hint = "Shift to dash. Brrrrt!", stat = "dashes", goal = 30, kind = "dash" }),
	table.freeze({ id = "barrels3", text = "Blow up 3 gas barrels", hint = "Shoot the green barrels till they go boom", stat = "barrels", goal = 3, kind = "barrels" }),
	table.freeze({ id = "chain1", text = "Start a barrel chain reaction", hint = "Blow up a barrel right next to another one", stat = "chains", goal = 1, kind = "chain" }),
}) :: { Challenge }

-- What must be on for a stat to count: a FeatureFlags switch, or "Rounds"
-- (FeatureFlags.MATCH_MODE; continuous play has no rounds to play or win).
ChallengeConfig.needs = table.freeze({
	rounds = "Rounds",
	wins = "Rounds",
	dashes = "FART_DASH",
	barrels = "GAS_COMBAT",
	chains = "GAS_COMBAT",
}) :: { [string]: string }

local byId: { [string]: Challenge } = {}
for _, challenge in ChallengeConfig.pool do
	byId[challenge.id] = challenge
end

function ChallengeConfig.get(id: string): Challenge?
	return byId[id]
end

-- Whether `challenge` can be done with `flags` (FeatureFlags).
function ChallengeConfig.doable(challenge: Challenge, flags: { [string]: any }): boolean
	local need = ChallengeConfig.needs[challenge.stat]
	if need == "Rounds" then
		return flags.MATCH_MODE == "Rounds"
	end
	return need == nil or flags[need] == true
end

-- The player's challenges on UTC day `day`, from the doable ones, worked
-- out from the user ID and the day alone: the same on every server all
-- day, different from day to day and from player to player. A small
-- arithmetic shuffle (Park-Miller, as the daily shop's), never two of a
-- kind, listed in the pool's order.
function ChallengeConfig.pick(userId: number, day: number, doable: (Challenge) -> boolean): { Challenge }
	local seed = (day * 7919 + (userId % 2147483646) * 31 + 97) % 2147483646 + 1
	local function nextNumber(): number
		seed = seed * 16807 % 2147483647
		return seed
	end
	-- Neighbouring seeds start out alike; a few steps apart them.
	for _ = 1, 3 do
		nextNumber()
	end
	local order: { Challenge } = {}
	for _, challenge in ChallengeConfig.pool do
		if doable(challenge) then
			table.insert(order, challenge)
		end
	end
	for i = #order, 2, -1 do
		local j = nextNumber() % i + 1
		order[i], order[j] = order[j], order[i]
	end
	local picked: { Challenge } = {}
	local kinds: { [string]: boolean } = {}
	for _, challenge in order do
		if #picked < ChallengeConfig.PER_DAY and not kinds[challenge.kind] then
			kinds[challenge.kind] = true
			table.insert(picked, challenge)
		end
	end
	local rank: { [string]: number } = {}
	for i, challenge in ChallengeConfig.pool do
		rank[challenge.id] = i
	end
	table.sort(picked, function(a, b)
		return rank[a.id] < rank[b.id]
	end)
	return picked
end

return table.freeze(ChallengeConfig)
