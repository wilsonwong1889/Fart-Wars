-- The round's awards (FeatureFlags.ROUND_AWARDS): Top Fragger, Chain
-- Master, Barrel Buster and Team Player, from what really happened. While a
-- round is live it keeps every combatant's numbers (RoundAwards does the
-- maths): eliminations, deaths and assists from EliminationService.Credited
-- (players and bots alike, by the ids the kill feed uses) and barrels from
-- BarrelService.Exploded (the player or bot who set each one off). When the round
-- ends RoundService asks for the winners and sends them with the results.
-- Only players still in the server and bots still in the game can win: one
-- who has left isn't there to collect it, so the next best gets it.
-- Continuous play has no results screen, so nothing is kept there.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Server = script.Parent.Parent
local RoundAwards = require(Server.RoundAwards)
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local MatchScoreService = require(script.Parent.MatchScoreService)
local EliminationService = require(script.Parent.EliminationService)
local BotService = require(script.Parent.BotService)
local BarrelService = require(script.Parent.BarrelService)

local AwardService = {}

local tally = RoundAwards.new()
local enabledOverride: boolean? = nil
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Whether there are awards at all (the flag, or the test seam over it).
function AwardService.enabled(): boolean
	local on = if enabledOverride ~= nil then enabledOverride else FeatureFlags.ROUND_AWARDS
	return on == true and FeatureFlags.MATCH_MODE ~= "Continuous"
end

-- Only a live round counts: not the intermission, not waiting. A kill
-- finished before the buzzer that lands just after it counts here as it
-- does in the score (`countdownAt`, MatchScoreService.counts).
local function counting(countdownAt: number?): boolean
	return AwardService.enabled() and MatchScoreService.counts(countdownAt)
end

-- A new round: everyone back to nothing.
function AwardService.reset()
	tally = RoundAwards.new()
end

-- Who `id` is now: a player in the server or a bot in the game, or nil.
local function lookup(id: number): RoundAwards.Who?
	local player = Players:GetPlayerByUserId(id)
	if player then
		return { id = id, name = player.DisplayName, team = TeamService.teamOf(player), bot = false }
	end
	local bot = BotService.get(id)
	if bot then
		return { id = id, name = bot.name, team = bot.team, bot = true }
	end
	return nil
end

-- The winners for the round so far, in the cards' order (none for an award
-- nobody earned); nil with awards off.
function AwardService.awards(): { RoundAwards.Award }?
	if not AwardService.enabled() then
		return nil
	end
	local awards = RoundAwards.compute(tally, lookup)
	for _, award in awards do
		Telemetry.count(`Awards.{award.award}.{if award.bot then "bot" else "player"}`)
	end
	return awards
end

-- `id`'s numbers this round (a copy), or nil if they haven't any.
function AwardService.statsOf(id: number): RoundAwards.Stats?
	return tally:statsOf(id)
end

-- Test seam: awards on or off whatever FeatureFlags says (nil: the flag).
function AwardService.testSetEnabled(on: boolean?)
	enabledOverride = on
end

function AwardService.start()
	if started then
		return
	end
	started = true
	EliminationService.Credited:Connect(function(credit: EliminationService.Credit)
		if counting(credit.countdownAt) then
			tally:elimination({
				at = now(),
				victim = credit.victim,
				killer = credit.killer,
				assists = credit.assists,
				cause = credit.cause,
			})
		end
	end)
	BarrelService.Exploded:Connect(function(owner: Player?, _chained: boolean, ownerBot: number?)
		if owner and owner.Parent == Players and counting() then
			tally:barrel(owner.UserId, now())
		elseif ownerBot and counting() then
			tally:barrel(ownerBot, now())
		end
	end)
end

return AwardService
