-- What players do, counted by name for the challenges that track it: the
-- season's weekly ones (SeasonService) and the daily ones
-- (ChallengeService). This is the one place that turns game events into
-- counts; each challenge system just listens to Counted. Kills of or by
-- bots pay out nothing, and nothing here counts one either:
--   eliminations, assists  a real player's elimination while the round is
--                          live (EliminationService.Eliminated never fires
--                          for a bot's death, and a bot's kill has no killer)
--   streaks                reaching the alpha streak (bot kills build none)
--   dashes                 Fart Dashes the server accepted
--   barrels                gas barrels set off (by a shot or the player's
--                          own blasts; a bot's blast credits nobody)
--   chains                 barrels set off by one of the player's barrels
--   zoneSeconds            seconds holding Gas Control's zone
--   minutes                minutes ACTIVE (AFK, spectating and the home
--                          screen don't count)
--   rounds, wins           rounds with ChallengeConfig.ROUND_SECONDS ACTIVE
--                          in them; won, with that long on the winning team
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChallengeConfig = require(Shared.Config.ChallengeConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Health = require(Server.Health)
local TeamService = require(script.Parent.TeamService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local EliminationService = require(script.Parent.EliminationService)
local DashService = require(script.Parent.DashService)
local BarrelService = require(script.Parent.BarrelService)
local ZoneService = require(script.Parent.ZoneService)
local RoundService = require(script.Parent.RoundService)

local PlayStatsService = {}

-- (player, stat, amount): `player` did `amount` more of `stat`.
PlayStatsService.Counted = Signal.new()

-- Seconds ACTIVE toward the next whole minute, by player.
local activeSeconds: { [Player]: number } = {}
-- This round's seconds ACTIVE, by player and team.
local roundSeconds: { [Player]: { [string]: number } } = {}
local started = false

function PlayStatsService.count(player: Player, stat: string, amount: number?)
	PlayStatsService.Counted:Fire(player, stat, amount or 1)
end
local count = PlayStatsService.count

-- This round's seconds ACTIVE for `player`, by team.
function PlayStatsService.roundSecondsOf(player: Player): { [string]: number }
	return table.clone(roundSeconds[player] or {})
end

-- The round is over: a round played for everyone who was in it long
-- enough, and a win for those that long on the winning team.
function PlayStatsService.finishRound(winner: string?)
	local need = ChallengeConfig.ROUND_SECONDS
	for player, teams in roundSeconds do
		if player.Parent == Players then
			local total = 0
			for _, seconds in teams do
				total += seconds
			end
			if total >= need then
				count(player, "rounds", 1)
			end
			if winner and (teams[winner] or 0) >= need then
				count(player, "wins", 1)
			end
		end
	end
	table.clear(roundSeconds)
end

-- Time ACTIVE: whole minutes, and this round's time by team.
function PlayStatsService.tick(dt: number)
	local live = RoundService.phase() == States.Phase.ACTIVE
	for _, player in Players:GetPlayers() do
		if PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE then
			local seconds = (activeSeconds[player] or 0) + dt
			if seconds >= 60 then
				seconds -= 60
				count(player, "minutes", 1)
			end
			activeSeconds[player] = seconds
			local team = TeamService.teamOf(player)
			if live and team then
				local teams = roundSeconds[player] or {}
				roundSeconds[player] = teams
				teams[team] = (teams[team] or 0) + dt
			end
		end
	end
end

function PlayStatsService.start()
	if started then
		return
	end
	started = true
	EliminationService.Eliminated:Connect(function(elimination)
		if not elimination.counted then
			return
		end
		if elimination.killer and elimination.killer ~= elimination.victim then
			count(elimination.killer, "eliminations", 1)
		end
		for _, helper in elimination.assists do
			count(helper, "assists", 1)
		end
	end)
	EliminationService.Alpha:Connect(function(player)
		count(player, "streaks", 1)
	end)
	DashService.Dashed:Connect(function(player)
		count(player, "dashes", 1)
	end)
	BarrelService.Exploded:Connect(function(owner, chained)
		if owner and owner.Parent == Players then
			count(owner, "barrels", 1)
			if chained then
				count(owner, "chains", 1)
			end
		end
	end)
	ZoneService.Held:Connect(function(player, seconds)
		count(player, "zoneSeconds", seconds)
	end)
	RoundService.PhaseChanged:Connect(function(phase, snapshot)
		if phase == States.Phase.RESULTS then
			local result = snapshot and snapshot.result
			PlayStatsService.finishRound(result and result.winner)
		elseif phase == States.Phase.ACTIVE then
			-- A new round: nothing carries over from the last one.
			table.clear(roundSeconds)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		activeSeconds[player] = nil
		roundSeconds[player] = nil
	end)
	Health.loop("PlayStats", 1, PlayStatsService.tick)
end

return PlayStatsService
