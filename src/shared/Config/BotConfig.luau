-- Bots that fill a quiet server (BotDirector, BotBrain). While fewer than
-- FILL_TO people are in the server (and at least one is), bots make up the
-- difference, spread so the teams stay level (BotFill).
-- How well they play is one knob, DIFFICULTY, from 0 (easy) to 1 (hard).
-- Each tuning number below is a pair, { easy, hard }, and a bot uses the
-- point DIFFICULTY of the way between them. The aim at 0.5: a mid-skill
-- player wins a fair 1v1 about half the time (close up a bot is about as
-- quick to finish a fight as a player who lands 40-50% of their shots;
-- far away it's worse). Even at 1 a bot stays within what a good player
-- can do: it takes time to react, misses moving targets, and never fires
-- faster than the weapon allows.
export type Range = { easy: number, hard: number }
export type Tuning = {
	reactionSeconds: number,
	aimErrorDegrees: number,
	speedErrorDegrees: number,
	distanceErrorDegrees: number,
	settleSeconds: number,
	headChance: number,
	fireIntervalMultiplier: number,
	sightRange: number,
	viewDegrees: number,
	strafeChance: number,
	jumpsPerSecond: number,
	backOffGas: number,
}

local function range(easy: number, hard: number): Range
	return table.freeze({ easy = easy, hard = hard })
end

local BotConfig = {
	-- Humans + bots in the server, while at least one human is in it.
	FILL_TO = 4,
	-- 0 easy .. 1 hard (TestControls: /fw bots skill 0.7).
	DIFFICULTY = 0.5,

	-- Shown as "[BOT] <name>" (BotService adds the prefix).
	NAMES = table.freeze({
		"Toots",
		"Sir Toots-a-Lot",
		"Captain Gas",
		"Baron von Bean",
		"Professor Poot",
		"Major Whiff",
		"Duke of Stink",
		"Lil Rumble",
		"Gassy Gus",
		"Windy Wendy",
		"Beanzilla",
		"Squeaky",
		"Thunder Pants",
		"Smelly Kelly",
		"Pungent Pam",
		"Bubbles",
		"Brrrt",
		"Whoopee",
		"Sir Puffs",
		"Lady Fumes",
		"Rooty Tooty",
		"Cloud Nine",
		"Puff Puff",
		"Mister Musk",
	}),
	-- Bots only ever carry this.
	WEAPON = "GasBlaster",
	-- Head colours, so bots on one team don't all look the same (body,
	-- arms and legs are in the team's colours).
	SKIN_TONES = table.freeze({
		Color3.fromRGB(255, 204, 153),
		Color3.fromRGB(234, 184, 146),
		Color3.fromRGB(175, 120, 85),
		Color3.fromRGB(105, 64, 40),
	}),

	-- How often each brain thinks (cheap: no rays every frame), and how
	-- often it looks around for a new target (a few rays each time).
	THINK_SECONDS = 0.125,
	SCAN_SECONDS = 0.3,
	-- At most this many line-of-sight rays per look around, nearest first.
	SCAN_RAYS = 3,
	-- A target out of sight this long is lost; seen again within REACQUIRE
	-- it takes no new reaction time.
	LOSE_SIGHT_SECONDS = 0.6,
	REACQUIRE_SECONDS = 1.5,
	-- Where it last saw an enemy is worth walking to for this long.
	MEMORY_SECONDS = 6,
	-- After taking gas it sees all the way round for a moment (it turns).
	ALERT_SECONDS = 2,
	-- The first shots at a new target are this much wider (x1.5), settling
	-- over the tuning's settleSeconds.
	SETTLE_EXTRA = 0.5,
	-- Shooting in mid-air is this much less accurate.
	AIRBORNE_ERROR = 1.5,
	-- In a fight: closes in when farther than this, backs up when closer
	-- than BACK_UP_STUDS; each strafe lasts STRAFE_SECONDS (min, max).
	CLOSE_IN_STUDS = 60,
	BACK_UP_STUDS = 18,
	STRAFE_SECONDS = table.freeze({ 0.6, 1.4 }),
	-- Backing off (tuning.backOffGas) lasts until gas is down to this.
	RESUME_GAS = 30,
	-- Patrols go this far from its own spawn toward the enemy's (0..1).
	PATROL_DEPTH = table.freeze({ 0.4, 0.8 }),
	-- Paths: planned again this often (sooner when chasing), a waypoint
	-- counts as reached this close, and a bot that moves less than
	-- STUCK_STUDS in STUCK_SECONDS is stuck (it jumps, then goes elsewhere).
	REPATH_SECONDS = 5,
	CHASE_REPATH_SECONDS = 1.5,
	WAYPOINT_STUDS = 3,
	STUCK_SECONDS = 1.5,
	STUCK_STUDS = 2,

	-- Tuning, { easy, hard }; the value at 0.5 in brackets.
	-- From first seeing a target to the first shot [0.51 s]; a mid player
	-- needs about half a second to react and get the crosshair on.
	REACTION_SECONDS = range(0.8, 0.22),
	-- Every shot lands inside a cone around the aim point: this wide at a
	-- still target [2.0 degrees: nearly always hits at 30 studs, rarely at
	-- 100] ...
	AIM_ERROR_DEGREES = range(3.0, 0.7),
	-- ... plus this per 16 studs a second the target moves across its view
	-- [1.8: a strafing target is much harder to hit] ...
	SPEED_ERROR_DEGREES = range(2.6, 1.0),
	-- ... plus this per 100 studs away [0.3].
	DISTANCE_ERROR_DEGREES = range(0.5, 0.1),
	-- How long its aim takes to settle on a new target [0.95 s].
	SETTLE_SECONDS = range(1.4, 0.5),
	-- Chance a shot goes for the head (smaller, so it misses more) [0.2].
	HEAD_CHANCE = range(0.05, 0.35),
	-- Time between shots, times the weapon's fire interval [1.43: about 2.3
	-- shots a second where a player holding the trigger gets 3.3].
	FIRE_INTERVAL_MULTIPLIER = range(1.8, 1.05),
	-- How far it notices enemies, in studs [225 of the map's 480] ...
	SIGHT_RANGE = range(150, 300),
	-- ... within this many degrees either side of where it faces [67.5: a
	-- 135-degree view, about what a third-person camera shows].
	VIEW_DEGREES = range(55, 80),
	-- The share of a fight spent strafing rather than standing [0.5] ...
	STRAFE_CHANCE = range(0.2, 0.8),
	-- ... and jumps a second while fighting [0.17: one every 6 s or so].
	JUMPS_PER_SECOND = range(0.03, 0.3),
	-- Backs off (still shooting) to recover at this much gas; 100 never
	-- [77.5: after the fourth body hit, one more is the end].
	BACK_OFF_GAS = range(100, 55),
}

local function blend(value: Range, difficulty: number): number
	return value.easy + (value.hard - value.easy) * difficulty
end

-- The tuning at `difficulty` (0..1; DIFFICULTY when nil).
function BotConfig.tuning(difficulty: number?): Tuning
	local d = math.clamp(difficulty or BotConfig.DIFFICULTY, 0, 1)
	return table.freeze({
		reactionSeconds = blend(BotConfig.REACTION_SECONDS, d),
		aimErrorDegrees = blend(BotConfig.AIM_ERROR_DEGREES, d),
		speedErrorDegrees = blend(BotConfig.SPEED_ERROR_DEGREES, d),
		distanceErrorDegrees = blend(BotConfig.DISTANCE_ERROR_DEGREES, d),
		settleSeconds = blend(BotConfig.SETTLE_SECONDS, d),
		headChance = blend(BotConfig.HEAD_CHANCE, d),
		fireIntervalMultiplier = blend(BotConfig.FIRE_INTERVAL_MULTIPLIER, d),
		sightRange = blend(BotConfig.SIGHT_RANGE, d),
		viewDegrees = blend(BotConfig.VIEW_DEGREES, d),
		strafeChance = blend(BotConfig.STRAFE_CHANCE, d),
		jumpsPerSecond = blend(BotConfig.JUMPS_PER_SECOND, d),
		backOffGas = blend(BotConfig.BACK_OFF_GAS, d),
	})
end

return table.freeze(BotConfig)
