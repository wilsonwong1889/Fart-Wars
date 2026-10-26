-- Gas Control (Phase 6): hold the control zone in the middle of the map.
-- Every second, a team with players in the zone and no enemies there
-- scores a point (ZoneService); a contested or empty zone scores nothing.
-- Eliminations don't score in this mode: they clear the zone. Most points
-- at the end wins; level scores are a draw.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GameModeBase = require(Shared.Interfaces.GameModeBase)

return GameModeBase.new({
	id = "GasControl",
	displayName = "Gas Control",
	objective = "zone",
	hint = "Hold the plaza with no enemies in it: a point a second.",
	roundSeconds = GameConfig.ROUND_SECONDS,
	intermissionSeconds = GameConfig.INTERMISSION_SECONDS,
	validateScoreEvent = function(_, event: GameModeBase.ScoreEvent, context: GameModeBase.Context): boolean
		if not table.find(context.teamIds, event.team) then
			return false
		end
		return event.source == "zone" or event.source == "test"
	end,
})
