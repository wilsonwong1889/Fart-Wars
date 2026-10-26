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
	-- Network slack for anything on an interval (shots, Fart Dash): two
	-- requests may arrive this much closer together than the interval
	-- (15% of it, and never less than FIRE_SLACK_SECONDS), but over time
	-- nobody gets more than one per interval (see Cadence).
	FIRE_INTERVAL_TOLERANCE = 0.85,
	FIRE_SLACK_SECONDS = 0.05,

	-- The gas meter, which replaces health. Hits fill it; at 100 a short
	-- countdown, then the player explodes. Percentages throughout.
	GAS = table.freeze({
		-- 0-24 normal, then slight inflation, obvious inflation, critical
		-- warning; 100 explodes.
		STAGES = table.freeze({ 25, 50, 75, 100 }),
		-- No recovery until this long after the last gas taken; then it
		-- drains at this rate. Taking gas stops it again.
		RECOVERY_DELAY_SECONDS = 5,
		RECOVERY_PER_SECOND = 5,
		EXPLOSION_COUNTDOWN_SECONDS = 1,
		-- Enemies who added gas this recently (besides the killer) assist.
		ASSIST_WINDOW_SECONDS = 10,
		TICK_SECONDS = 0.1,
	}),

	-- An exploding player blasts gas onto the killer's enemies nearby (with
	-- a clear line to them), which can set off more players and barrels:
	-- a chain, cut off after CHAIN_MAX_DEPTH steps. At most PER_TICK blasts
	-- resolve every TICK_SECONDS, so a big chain spreads over a few frames.
	-- Performance budgets (masterplan 5.2). At most MAX_CLOUDS stink clouds
	-- at once on the server (a new one ends the oldest early); on each
	-- client, at most MAX_TRACERS shot tracers and MAX_EFFECT_PARTS other
	-- effect parts at once (the oldest goes first).
	BUDGET = table.freeze({
		MAX_CLOUDS = 16,
		MAX_TRACERS = 24,
		MAX_EFFECT_PARTS = 120,
	}),

	EXPLOSION = table.freeze({
		RADIUS = 14,
		CHAIN_GAS = 40,
		CHAIN_MAX_DEPTH = 4,
		PER_TICK = 6,
		TICK_SECONDS = 0.05,
	}),

	-- Gas barrels: shots take HEALTH away (each shot its gas per hit); at 0
	-- the fuse burns for FUSE_SECONDS, then the barrel blasts GAS onto the
	-- enemies of whoever fired the last shot, within RADIUS of its side
	-- (16 from the centre of the original 5-stud barrel). It's back
	-- RESPAWN_SECONDS later.
	BARREL = table.freeze({
		HEALTH = 40,
		FUSE_SECONDS = 0.6,
		RADIUS = 13.5,
		GAS = 40,
		RESPAWN_SECONDS = 20,
	}),

	-- A death this soon after spawning counts as a spawn death (a playtest
	-- metric for spawn camping).
	SPAWN_DEATH_SECONDS = 5,

	-- Eliminations in a row without dying. At ALPHA_AT the whole server
	-- hears ALPHA_TEXT, once; announcements are at least ANNOUNCE_GAP apart.
	STREAK = table.freeze({
		ALPHA_AT = 5,
		ALPHA_TEXT = "BRO IS THE ALPHA FART!",
		ANNOUNCE_GAP_SECONDS = 3,
	}),

	-- Shooting is suspicious (logged, not punished) above this accuracy over
	-- at least SHOTS shots in a minute.
	SUSPICIOUS_ACCURACY = table.freeze({ SHOTS = 30, RATIO = 0.9 }),

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
	-- The rotation, when FeatureFlags.MODE_ROTATION is on, and the server
	-- size it starts at (below it, the default mode: a stable queue for
	-- small servers).
	MODE_ROTATION = table.freeze({ "TeamElimination", "GasControl" }),
	ROTATION_MIN_PLAYERS = 6,
	-- Gas Control's zone: every TICK_SECONDS, a team alone in it scores
	-- POINTS; a player holding it earns COINS and XP every REWARD_SECONDS,
	-- at most REWARDS_PER_ROUND times a round.
	ZONE = table.freeze({
		TICK_SECONDS = 1,
		POINTS = 1,
		REWARD_SECONDS = 10,
		COINS = 2,
		XP = 5,
		REWARDS_PER_ROUND = 15,
	}),

	-- Test-only scoring and timing controls (TestControls.luau). They work in
	-- Studio, and in live servers only for these user IDs. Turn ENABLED off
	-- before any public release.
	TEST_CONTROLS = table.freeze({
		ENABLED = true,
		USER_IDS = table.freeze({}) :: { number },
	}),

	-- Moderation hooks. Suspicious behaviour (an abnormal rate of refused
	-- requests, near-perfect accuracy, impossible movement, anomalous coin
	-- gains, dashing through walls) is flagged for review. KICK_AT_FLAGS
	-- kicks a player who collects that many flags in a session; 0 never
	-- kicks (review only, the default until the checks are tuned on real
	-- players). BANNED_USER_IDS can't join.
	MODERATION = table.freeze({
		KICK_AT_FLAGS = 0,
		BANNED_USER_IDS = table.freeze({}) :: { number },
		-- Player reports (the Players screen): the reasons offered, how many
		-- a player can send a session (one per person reported), and how
		-- many different players reporting someone in one server flags them
		-- for review (the flag counts toward KICK_AT_FLAGS like any other).
		REPORT_REASONS = table.freeze({ "Cheating", "Harassment", "Griefing", "Other" }),
		REPORTS_PER_SESSION = 5,
		REPORTS_TO_FLAG = 3,
	}),
}

return table.freeze(GameConfig)
