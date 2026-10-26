-- Server-wide rules for Phase 1. Times are in seconds, distances in studs.
-- The server reads these; clients only use them to explain what is happening.
local GameConfig = {
	PLACE_NAME = "Fart Wars - Development",

	-- Max Players is a place setting (Game Settings → Places), not a script
	-- property: set it to this. Two full teams use every slot.
	MAX_PLAYERS = 20,
	MAX_TEAM_SIZE = 10,
	MIN_ACTIVE_PLAYERS = 2,

	ROUND_SECONDS = 300,
	INTERMISSION_SECONDS = 15,

	AFK_WARNING_SECONDS = 45,
	AFK_SPECTATE_SECONDS = 60,
	-- An active avatar has to travel this far across the ground from where it
	-- last proved activity; jumping or turning on the spot doesn't count.
	AFK_MOVE_STUDS = 6,

	RESPAWN_SECONDS = 3,
	-- Requests from one player closer together than this are dropped.
	REQUEST_COOLDOWN_SECONDS = 0.5,
	-- How often the round loop and the AFK check run.
	ROUND_TICK_SECONDS = 0.25,
	AFK_TICK_SECONDS = 1,

	WALK_SPEED = 16,
	SPRINT_SPEED = 24,

	DEFAULT_MAP = "BrainrotBattlefield",
	DEFAULT_MODE = "TeamElimination",

	-- Test-only scoring and timing controls (TestControls.luau). They work in
	-- Studio, and in live servers only for these user IDs. Turn ENABLED off
	-- before any public release.
	TEST_CONTROLS = table.freeze({
		ENABLED = true,
		USER_IDS = table.freeze({}) :: { number },
	}),
}

return table.freeze(GameConfig)
