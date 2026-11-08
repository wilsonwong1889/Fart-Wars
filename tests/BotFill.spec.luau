-- Filling a quiet server with bots (Shared/BotFill), at BotConfig's fill
-- target of 4:
--   * nobody in the server, no bots; 1 human -> 3 bots, 2 -> 2, 3 -> 1,
--     4 or more -> none, counting humans who aren't playing too
--   * the bots keep the teams level: one human's side gets 1 of the 3, two
--     humans on one team get both bots against them, two apart one each
--   * a human leaving, spectating or joining changes as little as it can,
--     and a joining human takes a bot's place (on level teams, from the
--     side with fewer humans, where they'll be sent); one who picks the
--     side with more bots sends a bot across
--   * every head count: the teams end as level as bots can make them, and
--     asking again changes nothing
--   * BotConfig: 0.5 by default, and at any difficulty no quicker or surer
--     than a person
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local BotFill = require(Shared.BotFill)
local BotConfig = require(Shared.Config.BotConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local TeamBalance = require(Shared.TeamBalance)
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

local ORDER = TeamConfig.order
local FILL = BotConfig.FILL_TO
check(FILL == 4 and ORDER[1] == "Stinkers" and ORDER[2] == "Sharters", "fill to 4; Stinkers first in order")

local function teams(stinkers: number, sharters: number): { [string]: number }
	return { Stinkers = stinkers, Sharters = sharters }
end
-- `humans` in the server, `playing` of them on each team, `bots` there now.
local function fill(humans: number, playing, bots)
	return BotFill.plan(humans, playing, bots or teams(0, 0), ORDER, FILL)
end
local function is(counts, stinkers: number, sharters: number): boolean
	return counts.Stinkers == stinkers and counts.Sharters == sharters
end
local function empty(plan): boolean
	return #plan.add == 0 and #plan.remove == 0 and #plan.move == 0
end

-- How many.
check(BotFill.target(0, 4) == 0 and BotFill.target(1, 4) == 3 and BotFill.target(2, 4) == 2, "0 -> 0, 1 -> 3, 2 -> 2")
check(BotFill.target(3, 4) == 1 and BotFill.target(4, 4) == 0 and BotFill.target(9, 4) == 0, "3 -> 1, 4 or more -> 0")
local plan = fill(0, teams(0, 0), teams(2, 1))
check(is(plan.bots, 0, 0) and #plan.remove == 3, "the last human gone: every bot goes")

-- One human.
plan = fill(1, teams(1, 0))
check(is(plan.bots, 1, 2) and #plan.add == 3, "1 human: 3 bots, 1 on their side (2v2)")
plan = fill(1, teams(0, 1))
check(is(plan.bots, 2, 1), "the same on the other side")
plan = fill(1, teams(0, 0))
check(is(plan.bots, 2, 1), "1 human on the home screen: 3 bots, the extra by team order")

-- Two.
plan = fill(2, teams(2, 0))
check(is(plan.bots, 0, 2), "2 humans on one team: both bots against them")
plan = fill(2, teams(1, 1))
check(is(plan.bots, 1, 1), "2 humans apart: a bot each")
plan = fill(2, teams(0, 0))
check(is(plan.bots, 1, 1), "2 humans not playing yet: a bot each")

-- Three.
plan = fill(3, teams(2, 1))
check(is(plan.bots, 0, 1), "3 humans, 2v1: the bot evens it")
plan = fill(3, teams(3, 0))
check(is(plan.bots, 0, 1), "3 humans on one team: the one bot against them")
plan = fill(3, teams(1, 1))
check(is(plan.bots, 1, 0), "2 playing, 1 watching: the bot by team order")

-- Four or more.
plan = fill(4, teams(2, 2), teams(1, 1))
check(is(plan.bots, 0, 0) and #plan.remove == 2, "a 4th human: the bots go")
check(empty(fill(7, teams(4, 3))), "7 humans: no bots")

-- A human leaving.
plan = fill(1, teams(1, 0), teams(1, 1))
check(is(plan.bots, 1, 2) and #plan.add == 1 and plan.add[1] == "Sharters" and #plan.move == 0, "1v1 with a bot each, one leaves: a bot takes their place")
plan = fill(1, teams(1, 0), teams(0, 2))
check(is(plan.bots, 1, 2) and plan.add[1] == "Stinkers" and #plan.add == 1, "two on one team, one leaves: a bot beside the one left")
plan = fill(3, teams(1, 2))
check(is(plan.bots, 1, 0) and plan.add[1] == "Stinkers", "2v2 humans, one leaves: one bot, on their side")

-- A human spectating (still in the server, so still counted).
check(empty(fill(2, teams(0, 1), teams(1, 1))), "1v1 with a bot each, one spectates: nothing moves (1v2 is as level as it gets)")
check(empty(fill(1, teams(0, 0), teams(1, 2))), "the only human spectates: the bots stay")
plan = fill(2, teams(0, 0), teams(0, 2))
check(is(plan.bots, 1, 1) and #plan.move == 1 and plan.move[1].from == "Sharters" and plan.move[1].to == "Stinkers", "both humans on one team spectate: a bot crosses over")
plan = fill(1, teams(0, 1), teams(3, 0))
check(is(plan.bots, 2, 1) and #plan.move == 1 and #plan.add == 0, "a 3v1 is evened with a move, not a swap of bots")

-- A human joining: a bot goes from the team they'll then join (TeamBalance
-- keeps the humans level, so on level teams that's the side with fewer).
plan = fill(2, teams(1, 0), teams(1, 2))
check(is(plan.bots, 1, 1) and #plan.remove == 1 and plan.remove[1] == "Sharters", "a 2nd human arrives, teams level: a bot goes from the side with no human")
local counts = teams(1 + plan.bots.Stinkers, 0 + plan.bots.Sharters)
local joined, why = TeamBalance.choose(counts, ORDER, 10, { bots = plan.bots })
check(joined == "Sharters" and why == "balance", "PLAY puts them where the bot was, against the first human")
check(empty(fill(2, teams(1, 1), plan.bots)), "and then nothing changes: 2v2, a bot each")
plan = fill(2, teams(1, 0), teams(2, 1))
check(is(plan.bots, 1, 1) and plan.remove[1] == "Stinkers", "teams not level: the bigger one loses the bot, as before")
plan = fill(3, teams(1, 1), teams(1, 1))
check(is(plan.bots, 0, 1) and plan.remove[1] == "Stinkers", "humans level too: by team order")

-- A human picking the side that's fuller only because of bots: one crosses.
plan = fill(1, teams(1, 0), teams(2, 1))
check(is(plan.bots, 1, 2) and #plan.move == 1 and plan.move[1].from == "Stinkers" and #plan.add + #plan.remove == 0, "alone, onto the 2-bot side: a bot crosses over, 2v2")
plan = BotFill.plan(1, teams(1, 0), teams(10, 9), ORDER, 20)
check(is(plan.bots, 9, 10) and #plan.move == 1 and #plan.add + #plan.remove == 0, "into a team of ten bots (fill 20): one crosses over, 10v10")
check(empty(BotFill.plan(1, teams(1, 0), plan.bots, ORDER, 20)), "and stays")

-- Every head count: as level as it can be, the right number, and settled.
local cases = 0
for humans = 0, 6 do
	for stinkers = 0, humans do
		for sharters = 0, humans - stinkers do
			for botsA = 0, 4 do
				for botsB = 0, 4 do
					cases += 1
					local playing = teams(stinkers, sharters)
					local p = fill(humans, playing, teams(botsA, botsB))
					local want = BotFill.target(humans, FILL)
					local after = p.bots
					local label = `{humans} humans ({stinkers}v{sharters} playing), bots {botsA}/{botsB}`
					check(after.Stinkers >= 0 and after.Sharters >= 0 and after.Stinkers + after.Sharters == want, `{label}: {want} bots`)
					check(#p.add + #p.remove == math.abs(botsA + botsB - want) and (#p.add == 0 or #p.remove == 0), `{label}: only the bots needed come or go`)
					local gap = math.abs(stinkers - sharters)
					local best = if want >= gap then (want - gap) % 2 else gap - want
					check(math.abs((stinkers + after.Stinkers) - (sharters + after.Sharters)) == best, `{label}: as level as {want} bots make it`)
					check(empty(fill(humans, playing, after)), `{label}: asking again changes nothing`)
				end
			end
		end
	end
end
check(cases > 500, "every case tried")

-- The difficulty.
check(BotConfig.DIFFICULTY == 0.5, "bots play at 50%")
local mid = BotConfig.tuning()
check(mid.reactionSeconds == BotConfig.tuning(0.5).reactionSeconds, "the default is DIFFICULTY")
check(math.abs(mid.reactionSeconds - (BotConfig.REACTION_SECONDS.easy + BotConfig.REACTION_SECONDS.hard) / 2) < 1e-9, "0.5 is halfway")
local easy, hard = BotConfig.tuning(0), BotConfig.tuning(1)
check(hard.reactionSeconds < easy.reactionSeconds and hard.aimErrorDegrees < easy.aimErrorDegrees, "harder reacts sooner and aims better")
check(hard.fireIntervalMultiplier < easy.fireIntervalMultiplier and hard.sightRange > easy.sightRange, "harder fires faster and sees further")
check(hard.headChance > easy.headChance and hard.backOffGas < easy.backOffGas, "harder goes for heads and backs off sooner")
check(BotConfig.tuning(5).reactionSeconds == hard.reactionSeconds and BotConfig.tuning(-1).reactionSeconds == easy.reactionSeconds, "out of range is clamped")
for step = 0, 10 do
	local t = BotConfig.tuning(step / 10)
	check(t.reactionSeconds >= 0.2, "never reacts quicker than a person")
	check(t.fireIntervalMultiplier >= 1, "never fires faster than the weapon")
	check(t.aimErrorDegrees >= 0.5 and t.speedErrorDegrees > 0, "never perfect aim, worse on moving targets")
	check(t.headChance <= 0.5 and t.viewDegrees <= 90 and t.backOffGas <= 100, "human-sized head chance, view and nerve")
end
local seen = {}
for _, name in BotConfig.NAMES do
	check(not seen[name] and #name > 0 and #name <= 16, `"{name}": a short name, used once`)
	seen[name] = true
end
check(#BotConfig.NAMES >= FILL, "enough names for a full server")

return { status = "PASS", checks = checks, cases = cases }
