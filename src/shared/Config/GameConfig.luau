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
	-- Invulnerable this long after spawning, unless they fire first.
	SPAWN_PROTECTION_SECONDS = 3,
	-- A shot may come this much sooner than the weapon's fire interval
	-- (network jitter) before the server drops it.
	FIRE_INTERVAL_TOLERANCE = 0.85,

	-- Shift. The client pushes the avatar at SPEED for SECONDS; the server
	-- checks the cooldown and, CHECK_SECONDS later, that it didn't travel
	-- further than a dash plus walking allows (or puts it back).
	FART_DASH = table.freeze({
		COOLDOWN_SECONDS = 3,
		SPEED = 70,
		SECONDS = 0.2,
		CHECK_SECONDS = 0.5,
		MAX_TRAVEL_STUDS = 30,
	}),

	-- A player with more rejected requests than this in a minute is logged
	-- as abnormal (a broken client or an exploit).
	ABNORMAL_REJECTS_PER_MINUTE = 30,
	-- Requests from one player closer together than this are dropped.
	REQUEST_COOLDOWN_SECONDS = 0.5,
	-- How often the round loop and the AFK check run.
	ROUND_TICK_SECONDS = 0.25,
	AFK_TICK_SECONDS = 1,

	WALK_SPEED = 16,

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
