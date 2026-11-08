-- Gas Control (Phase 6): hold the control zone in the middle of the map
-- (ZoneService). A team alone in it takes it in a few seconds; the team
-- that holds it scores a point a second while no enemy is in it. A
-- contested or empty zone scores nothing. Eliminations don't score in
-- this mode: they clear the zone. Most points at the end wins; level
-- scores are a draw.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GameModeBase = require(Shared.Interfaces.GameModeBase)

return GameModeBase.new({
	id = "GasControl",
	displayName = "Gas Control",
	objective = "zone",
	hint = "Take the plaza, then keep enemies out of it: a point a second.",
	roundSeconds = GameConfig.ROUND_SECONDS,
	intermissionSeconds = GameConfig.INTERMISSION_SECONDS,
	validateScoreEvent = function(_, event: GameModeBase.ScoreEvent, context: GameModeBase.Context): boolean
		if not table.find(context.teamIds, event.team) then
			return false
		end
		return event.source == "zone" or event.source == "test"
	end,
})
