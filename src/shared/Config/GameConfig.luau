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
	EXPLOSION = table.freeze({
		RADIUS = 14,
		CHAIN_GAS = 40,
		CHAIN_MAX_DEPTH = 4,
		PER_TICK = 6,
		TICK_SECONDS = 0.05,
	}),

	-- Gas barrels: shots take HEALTH away (each shot its gas per hit); at 0
	-- the fuse burns for FUSE_SECONDS, then the barrel blasts GAS onto the
	-- enemies of whoever fired the last shot, within RADIUS. It's back
	-- RESPAWN_SECONDS later.
	BARREL = table.freeze({
		HEALTH = 40,
		FUSE_SECONDS = 0.6,
		RADIUS = 16,
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

	-- Test-only scoring and timing controls (TestControls.luau). They work in
	-- Studio, and in live servers only for these user IDs. Turn ENABLED off
	-- before any public release.
	TEST_CONTROLS = table.freeze({
		ENABLED = true,
		USER_IDS = table.freeze({}) :: { number },
	}),
}

return table.freeze(GameConfig)
