-- Switches for whole systems, so a mode or mechanic can be tried, turned
-- off or rolled back without code changes. Read once when the server and
-- clients start.
return table.freeze({
	-- "Rounds": 5-minute rounds with a 15-second intermission (the default).
	-- "Continuous": join and play with instant team assignment, no timer and
	-- no results screen (the masterplan's alternative baseline).
	MATCH_MODE = "Rounds" :: "Rounds" | "Continuous",

	-- The Phase 1 placeholder attack (left click). Phase 2's Gas Blaster
	-- replaces it.
	PLACEHOLDER_BLASTER = true,

	-- Shift: Fart Dash. On for everyone until Phase 3 adds unlocks.
	FART_DASH = true,

	-- A few seconds of protection after each spawn; firing ends it early.
	SPAWN_PROTECTION = true,

	-- Teammates outlined in their team colour.
	TEAMMATE_HIGHLIGHTS = true,

	-- Structured "[FW]" lines in the output for every service event and
	-- rejected request. Counters are kept either way.
	DEBUG_LOGS = true,
})
