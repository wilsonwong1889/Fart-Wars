-- The team rules on their own (Shared/TeamBalance):
--   * joins fill 1v1, 3v3 and 10v10 evenly, and nobody joins a full team
--   * a choice counts only when it is as balanced as the best placement
--   * friends only break a tie; what's left goes the same way every time
--     (the team behind on score, then team order)
--   * a voluntary switch must make the teams more even
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

-- Starting.
check(TeamBalance.canStart({ Stinkers = 1, Sharters = 1 }, ORDER, 2), "a 1v1 starts")
check(not TeamBalance.canStart({ Stinkers = 1, Sharters = 0 }, ORDER, 2), "one player doesn't")
check(not TeamBalance.canStart({ Stinkers = 2, Sharters = 0 }, ORDER, 2), "nor two on one team with nobody to face")

return { status = "PASS", checks = checks }
