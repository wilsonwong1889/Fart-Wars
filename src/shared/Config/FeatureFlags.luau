-- Switches for whole systems, so a mode or mechanic can be tried, turned
-- off or rolled back without code changes. Read once when the server and
-- clients start.
return table.freeze({
	-- "Rounds": 5-minute rounds with a 15-second intermission (the default).
	-- "Continuous": join and play with instant team assignment, no timer and
	-- no results screen (the masterplan's alternative baseline).
	MATCH_MODE = "Rounds" :: "Rounds" | "Continuous",

	-- Award cards on the results screen (AwardService): Top Fragger, Chain
	-- Master, Barrel Buster and Team Player, from the round's own stats.
	-- Off: the results show the winner and the scores alone.
	ROUND_AWARDS = true,

	-- Seasons (Phase 6): a free seasonal track with weekly challenges
	-- between SeasonConfig's dates. Off as shipped.
	SEASONS = false,

	-- Daily challenges: three a day for each player, new at 00:00 UTC, on
	-- the DAILY screen; each pays coins and XP once, when it's done
	-- (ChallengeConfig; needs PROGRESSION). Nothing bots do counts.
	CHALLENGES = true,

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

	-- The Settings screen's choices saved to the player's profile and back
	-- on their next visit (SettingsService, SettingsController). Off: they
	-- last the session, as before.
	SAVED_SETTINGS = true,

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

	-- Feedback (FeedbackService): FEEDBACK in the M menu sends the developer
	-- a bug report, idea or anything else (up to 300 characters), with the
	-- version, ping, frame rate and recent errors; admins read the newest
	-- with /fw feedback. Off: no button, and the server refuses reports.
	FEEDBACK = true,

	-- Structured "[FW]" lines in the output for every service event and
	-- rejected request. Counters are kept either way.
	DEBUG_LOGS = true,

	-- Soft shutdown (SoftShutdownService): a server closing with players in
	-- it says "FART WARS JUST GOT AN UPDATE!", saves everyone, then moves
	-- them through a reserved server to a fresh one. Never in Studio or in
	-- private servers. Off: closing servers leave their players to Roblox.
	SOFT_SHUTDOWN = true,
})
