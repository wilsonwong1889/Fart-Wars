-- Switches for whole systems, so a mode or mechanic can be tried, turned
-- off or rolled back without code changes. Read once when the server and
-- clients start.
return table.freeze({
	-- "Rounds": 5-minute rounds with a 15-second intermission (the default).
	-- "Continuous": join and play with instant team assignment, no timer and
	-- no results screen (the masterplan's alternative baseline).
	MATCH_MODE = "Rounds" :: "Rounds" | "Continuous",

	-- Mode rotation (Phase 6): each round takes the next mode in
	-- GameConfig.MODE_ROTATION that the map supports, once at least
	-- ROTATION_MIN_PLAYERS are on teams; smaller servers stay on
	-- GameConfig.DEFAULT_MODE. Off: every round is the default mode.
	MODE_ROTATION = false,

	-- Gas combat: the Gas Blaster (left click), the gas meter, inflation and
	-- explosions.
	GAS_COMBAT = true,

	-- Shift: Fart Dash, everyone's (the unlockable abilities are on Q).
	FART_DASH = true,

	-- Coins, XP and levels for playing. Off, nothing is paid (stats still
	-- count, and saving still runs): for playtests of the combat alone.
	PROGRESSION = true,

	-- The daily track, ten-minute gifts and free spins (needs PROGRESSION).
	REWARDS = true,

	-- A few seconds of protection after each spawn; firing ends it early.
	SPAWN_PROTECTION = true,

	-- Teammates outlined in their team colour.
	TEAMMATE_HIGHLIGHTS = true,

	-- Structured "[FW]" lines in the output for every service event and
	-- rejected request. Counters are kept either way.
	DEBUG_LOGS = true,
})
