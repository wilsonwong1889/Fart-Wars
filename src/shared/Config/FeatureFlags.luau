-- Switches for whole systems, so a mode or mechanic can be tried, turned
-- off or rolled back without code changes. Read once when the server and
-- clients start.
return table.freeze({
	-- "Rounds": 5-minute rounds with a 15-second intermission (the default).
	-- "Continuous": join and play with instant team assignment, no timer and
	-- no results screen (the masterplan's alternative baseline).
	MATCH_MODE = "Rounds" :: "Rounds" | "Continuous",

	-- Seasons (Phase 6): a free seasonal track with weekly challenges
	-- between SeasonConfig's dates. Off as shipped.
	SEASONS = false,

	-- Live events (Phase 6): Bean Rain now and then in a round, always
	-- announced first (EventConfig). Off as shipped.
	EVENTS = false,

	-- Prestige (Phase 6): start again from level 50 for a rank, badges and
	-- cosmetics (no power). Off until its design is signed off
	-- (PrestigeConfig, docs/roadmap.md).
	PRESTIGE = false,

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

	-- Launch pads: giant whoopee cushions on the map that fart whoever
	-- steps on one forward and up, toward the fight (LaunchPadConfig).
	-- Off: the map has none.
	LAUNCH_PADS = true,

	-- Coins, XP and levels for playing. Off, nothing is paid (stats still
	-- count, and saving still runs): for playtests of the combat alone.
	PROGRESSION = true,

	-- The daily track, ten-minute gifts and free spins (needs PROGRESSION).
	REWARDS = true,

	-- A few seconds of protection after each spawn; firing ends it early.
	SPAWN_PROTECTION = true,

	-- Teammates outlined in their team colour.
	TEAMMATE_HIGHLIGHTS = true,

	-- Floating gas numbers ("+20%", gold for a headshot) where your own
	-- shots land.
	GAS_NUMBERS = true,

	-- "CHAIN x2!" pop-ups for chain reactions, from the server's count, and
	-- a smaller line for players near one.
	CHAIN_CALLOUTS = true,

	-- Bots (BotDirector): while fewer than BotConfig.FILL_TO people are in
	-- the server (and at least one is), "[BOT]" players fill it up, keeping
	-- the teams level; each human who joins takes a bot's place. Kills of or
	-- by bots score team points but pay out nothing. Off: never any bots.
	BOTS = true,

	-- Structured "[FW]" lines in the output for every service event and
	-- rejected request. Counters are kept either way.
	DEBUG_LOGS = true,
})
