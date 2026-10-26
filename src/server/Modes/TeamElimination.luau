-- Phase 1's only mode: two teams, five minutes, the team with the most
-- validated eliminations wins and level scores are a draw. Combat arrives in
-- Phase 2; until then the test-only controls supply the eliminations.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GameModeBase = require(Shared.Interfaces.GameModeBase)

return GameModeBase.new({
	id = "TeamElimination",
	displayName = "Team Elimination",
	roundSeconds = GameConfig.ROUND_SECONDS,
	intermissionSeconds = GameConfig.INTERMISSION_SECONDS,
	validateScoreEvent = function(_, event: GameModeBase.ScoreEvent, context: GameModeBase.Context): boolean
		if not table.find(context.teamIds, event.team) then
			return false
		end
		if event.source == "test" then
			return true
		end
		if event.source ~= "elimination" then
			return false
		end
		-- A real elimination: an active killer on the scoring team took out
		-- an active player on the other one.
		local killer, victim = event.killer, event.victim
		if not (killer and victim) or killer == victim then
			return false
		end
		local killerTeam, victimTeam = context.teamOf(killer), context.teamOf(victim)
		return killerTeam == event.team and victimTeam ~= nil and victimTeam ~= killerTeam
	end,
})
