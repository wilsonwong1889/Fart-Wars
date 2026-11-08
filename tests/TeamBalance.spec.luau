-- The team rules on their own (Shared/TeamBalance):
--   * joins fill 1v1, 3v3 and 10v10 evenly, and nobody joins a full team
--   * a choice counts only when it is as balanced as the best placement
--   * friends only break a tie; what's left goes the same way every time
--     (the team behind on score, then team order)
--   * a voluntary switch must make the teams more even
--   * with bots the rules go by the players: alone, either team; ten bots
--     don't fill a team; between players (friends, switches) nothing
--     changes, at every head count; AUTO takes a free slot over a bot's
--   * a round needs enough players and someone on every team
local TeamBalance = require(game.ReplicatedStorage.Shared.TeamBalance)
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

local ORDER = { "Stinkers", "Sharters" }
local MAX = 10

-- N players join one after another with no preferences, with the round
-- score at `scores`.
local function fill(n: number, scores: { [string]: number }): { [string]: number }
	local counts = { Stinkers = 0, Sharters = 0 }
	for _ = 1, n do
		local team = TeamBalance.choose(counts, ORDER, MAX, { scores = scores })
		assert(team, "a slot")
		counts[team] += 1
	end
	return counts
end

for _, scores in { {}, { Stinkers = 5 }, { Sharters = 2 }, { Stinkers = 3, Sharters = 3 } } do
	local two, six, twenty = fill(2, scores), fill(6, scores), fill(20, scores)
	check(two.Stinkers == 1 and two.Sharters == 1, "2 players make a 1v1")
	check(six.Stinkers == 3 and six.Sharters == 3, "6 players make a 3v3")
	check(twenty.Stinkers == 10 and twenty.Sharters == 10, "20 players make a 10v10")
	for n = 1, 20 do
		local counts = fill(n, scores)
		check(math.abs(counts.Stinkers - counts.Sharters) <= 1, `{n} joins stay within one`)
		check(counts.Stinkers <= MAX and counts.Sharters <= MAX, "never more than ten a team")
	end
end

-- Full teams.
local full = { Stinkers = 10, Sharters = 10 }
local team, why = TeamBalance.choose(full, ORDER, MAX, { preferred = "Stinkers" })
check(team == nil and why == "full", "nobody joins when both teams are full")
team, why = TeamBalance.choose({ Stinkers = 10, Sharters = 9 }, ORDER, MAX, { preferred = "Stinkers" })
check(team == "Sharters" and why == "preferenceRejected", "a full team's last open rival gets the join")

-- Preferences.
team, why = TeamBalance.choose({ Stinkers = 2, Sharters = 2 }, ORDER, MAX, { preferred = "Sharters" })
check(team == "Sharters" and why == "preferred", "level teams: the choice counts")
team, why = TeamBalance.choose({ Stinkers = 3, Sharters = 2 }, ORDER, MAX, { preferred = "Stinkers" })
check(team == "Sharters" and why == "preferenceRejected", "a choice that unbalances is refused")
team, why = TeamBalance.choose({ Stinkers = 3, Sharters = 2 }, ORDER, MAX, { preferred = "Sharters" })
check(team == "Sharters" and why == "preferred", "a choice toward the smaller team counts")
team, why = TeamBalance.choose({ Stinkers = 3, Sharters = 2 }, ORDER, MAX, { preferred = "Nonsense" })
check(team == "Sharters" and why == "balance", "an unknown team is ignored")
check(TeamBalance.preferenceAllowed({ Stinkers = 1, Sharters = 1 }, ORDER, MAX, "Stinkers"), "either team when level")
check(not TeamBalance.preferenceAllowed({ Stinkers = 2, Sharters = 1 }, ORDER, MAX, "Stinkers"), "not the bigger team")

-- Friends break ties only.
team, why = TeamBalance.choose({ Stinkers = 2, Sharters = 2 }, ORDER, MAX, { friends = { Sharters = 1 } })
check(team == "Sharters" and why == "friends", "a friend breaks a tie")
team, why = TeamBalance.choose({ Stinkers = 3, Sharters = 2 }, ORDER, MAX, { friends = { Stinkers = 3 } })
check(team == "Sharters" and why == "balance", "friends never outweigh balance")
team, why = TeamBalance.choose({ Stinkers = 2, Sharters = 2 }, ORDER, MAX, { preferred = "Stinkers", friends = { Sharters = 2 } })
check(team == "Stinkers" and why == "preferred", "the player's own choice comes before friends")
team, why = TeamBalance.choose({ Stinkers = 4, Sharters = 4 }, ORDER, MAX, { scores = { Stinkers = 6, Sharters = 2 } })
check(team == "Sharters" and why == "behind", "a tie goes to the team behind on score")
team, why = TeamBalance.choose({ Stinkers = 4, Sharters = 4 }, ORDER, MAX, { friends = { Stinkers = 1 }, scores = { Stinkers = 6 } })
check(team == "Stinkers" and why == "friends", "friends come before the score")
for _ = 1, 20 do
	team, why = TeamBalance.choose({ Stinkers = 4, Sharters = 4 }, ORDER, MAX, { scores = { Stinkers = 1, Sharters = 1 } })
	check(team == "Stinkers" and why == "order", "level on everything: the first team, every time")
end

-- Switching.
check(TeamBalance.canSwitch({ Stinkers = 5, Sharters = 3 }, ORDER, MAX, "Stinkers", "Sharters"), "5v3: moving across evens it")
check(not TeamBalance.canSwitch({ Stinkers = 4, Sharters = 3 }, ORDER, MAX, "Stinkers", "Sharters"), "4v3: moving across only flips it")
check(not TeamBalance.canSwitch({ Stinkers = 3, Sharters = 3 }, ORDER, MAX, "Stinkers", "Sharters"), "3v3: no switching")
check(not TeamBalance.canSwitch({ Stinkers = 2, Sharters = 0 }, ORDER, MAX, "Stinkers", "Stinkers"), "not to your own team")
check(TeamBalance.canSwitch({ Stinkers = 2, Sharters = 0 }, ORDER, MAX, "Stinkers", "Sharters"), "2v0: someone can even it out")
check(not TeamBalance.canSwitch({ Stinkers = 10, Sharters = 10 }, ORDER, MAX, "Stinkers", "Sharters"), "never into a full team")

-- Bots. Their slots are open to anyone (the bot crosses over or leaves), so
-- told which of the counts are bots, the rules go by the players alone.
local function teams(stinkers: number, sharters: number): { [string]: number }
	return { Stinkers = stinkers, Sharters = sharters }
end
local h = TeamBalance.humans(teams(3, 2), ORDER, teams(1, 2))
check(h.Stinkers == 2 and h.Sharters == 0, "the players are the counts less the bots")
check(TeamBalance.humans(teams(3, 2), ORDER).Stinkers == 3, "no bots: everyone's a player")
-- Alone on the home screen, 3 bots: 2v1.
check(not TeamBalance.preferenceAllowed(teams(2, 1), ORDER, MAX, "Stinkers"), "counted as players, 2v1 bots would lock the Stinkers (the bug)")
check(TeamBalance.preferenceAllowed(teams(2, 1), ORDER, MAX, "Stinkers", teams(2, 1)), "alone with bots: the side with more is open")
check(TeamBalance.preferenceAllowed(teams(2, 1), ORDER, MAX, "Sharters", teams(2, 1)), "and so is the other")
team, why = TeamBalance.choose(teams(2, 1), ORDER, MAX, { preferred = "Stinkers", bots = teams(2, 1) })
check(team == "Stinkers" and why == "preferred", "picking the side with more bots is honoured")
team, why = TeamBalance.choose(teams(2, 1), ORDER, MAX, { bots = teams(2, 1) })
check(team == "Sharters" and why == "balance", "AUTO takes the free slot, so no bot has to move")
team, why = TeamBalance.choose(teams(2, 2), ORDER, MAX, { bots = teams(2, 2), scores = { Stinkers = 4 } })
check(team == "Sharters" and why == "behind", "level all round: the team behind on score, as before")
-- A team of bots isn't full; a team of players is.
team, why = TeamBalance.choose(teams(10, 9), ORDER, MAX, { preferred = "Stinkers", bots = teams(10, 9) })
check(team == "Stinkers" and why == "preferred", "ten bots don't fill a team: I take a bot's place")
team, why = TeamBalance.choose(teams(10, 10), ORDER, MAX, { preferred = "Stinkers", bots = teams(0, 10) })
check(team == "Sharters" and why == "preferenceRejected", "ten players do; the bots' side takes me")
team, why = TeamBalance.choose(full, ORDER, MAX, { bots = teams(0, 0) })
check(team == nil and why == "full", "twenty players: full")
-- Between players nothing changes.
check(not TeamBalance.preferenceAllowed(teams(1, 2), ORDER, MAX, "Stinkers", teams(0, 2)), "a 2nd player can't stack on the first (2v0 players)")
team, why = TeamBalance.choose(teams(1, 2), ORDER, MAX, { preferred = "Stinkers", friends = { Stinkers = 1 }, bots = teams(0, 2) })
check(team == "Sharters" and why == "preferenceRejected", "not even with a friend there: they go against them, where the bots are")
team, why = TeamBalance.choose(teams(2, 2), ORDER, MAX, { friends = { Sharters = 1 }, bots = teams(1, 1) })
check(team == "Sharters" and why == "friends", "1v1 players: a friend breaks the tie")
team, why = TeamBalance.choose(teams(2, 1), ORDER, MAX, { friends = { Stinkers = 1 }, bots = teams(1, 0) })
check(team == "Stinkers" and why == "friends", "a friend comes before the free slot")
-- Switching goes by the players too.
check(TeamBalance.canSwitch(teams(2, 2), ORDER, MAX, "Stinkers", "Sharters", teams(0, 2)), "2v0 players against bots: one may cross to even it")
check(not TeamBalance.canSwitch(teams(2, 2), ORDER, MAX, "Stinkers", "Sharters"), "(counted as players: 2v2 -> 1v3)")
check(not TeamBalance.canSwitch(teams(2, 2), ORDER, MAX, "Stinkers", "Sharters", teams(1, 2)), "alone, a switch evens nothing")
check(TeamBalance.canSwitch(full, ORDER, MAX, "Stinkers", "Sharters", teams(7, 10)), "3v0 players: into ten bots, one makes room")
-- Every head count up to 10 a side: the lock, AUTO and switching with bots
-- are exactly the players' own.
local cases = 0
for humansS = 0, MAX do
	for humansY = 0, MAX do
		for botsS = 0, MAX - humansS do
			for botsY = 0, MAX - humansY do
				cases += 1
				local counts, bots, players = teams(humansS + botsS, humansY + botsY), teams(botsS, botsY), teams(humansS, humansY)
				local label = `{humansS}v{humansY} players, bots {botsS}/{botsY}`
				for _, side in ORDER do
					check(TeamBalance.preferenceAllowed(counts, ORDER, MAX, side, bots) == TeamBalance.preferenceAllowed(players, ORDER, MAX, side), `{label}: {side} locked as for the players alone`)
				end
				local auto = TeamBalance.choose(counts, ORDER, MAX, { bots = bots })
				local alone = TeamBalance.choose(players, ORDER, MAX)
				check((auto == nil) == (alone == nil), `{label}: full only when players fill both`)
				if auto then
					check(TeamBalance.preferenceAllowed(players, ORDER, MAX, auto), `{label}: AUTO never unbalances the players`)
					local other = if auto == "Stinkers" then "Sharters" else "Stinkers"
					local tied = TeamBalance.preferenceAllowed(players, ORDER, MAX, other)
					check(not tied or counts[auto] <= counts[other], `{label}: players level, AUTO takes the side with fewer`)
				end
				check(
					TeamBalance.canSwitch(counts, ORDER, MAX, "Stinkers", "Sharters", bots) == TeamBalance.canSwitch(players, ORDER, MAX, "Stinkers", "Sharters")
						and TeamBalance.canSwitch(counts, ORDER, MAX, "Sharters", "Stinkers", bots) == TeamBalance.canSwitch(players, ORDER, MAX, "Sharters", "Stinkers"),
					`{label}: switching as for the players alone`
				)
			end
		end
	end
end
check(cases == 66 * 66, "every case tried")

-- Starting.
check(TeamBalance.canStart({ Stinkers = 1, Sharters = 1 }, ORDER, 2), "a 1v1 starts")
check(not TeamBalance.canStart({ Stinkers = 1, Sharters = 0 }, ORDER, 2), "one player doesn't")
check(not TeamBalance.canStart({ Stinkers = 2, Sharters = 0 }, ORDER, 2), "nor two on one team with nobody to face")

return { status = "PASS", checks = checks }
