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
-- Each life a bot carries one gun of the arsenal (WEAPONS: a weighted pick
-- that leans away from what its teammates already carry) and a Q ability
-- to go with it, and plays that gun the way it's meant to be played.
local WeaponConfig = require(script.Parent.WeaponConfig)

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
	dashesPerSecond: number,
}
-- How a bot fights with one weapon (see WEAPONS).
export type Style = {
	weight: number,
	closeIn: number,
	backUp: number,
	fireRange: number,
	strafe: number,
	jumps: number,
	patrolDepth: { number },
	holdSeconds: { number },
	abilities: { [string]: number },
}

local function range(easy: number, hard: number): Range
	return table.freeze({ easy = easy, hard = hard })
end

local function style(fields: Style): Style
	table.freeze(fields.patrolDepth)
	table.freeze(fields.holdSeconds)
	table.freeze(fields.abilities)
	return table.freeze(fields)
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
	-- The gun a new avatar is built holding (BotDirector); BotService then
	-- hands the life its own pick from WEAPONS.
	WEAPON = "GasBlaster",
	-- How each gun is played, and how often a life carries it.
	--   weight       how likely a life is to pick it; each teammate already
	--                carrying it makes it SAME_WEAPON_FACTOR times as likely,
	--                so a team's bots carry a mix
	--   closeIn,     in a fight it walks in on a target farther than closeIn
	--   backUp       studs and backs off from one nearer than backUp
	--   fireRange    and only fires at one within this (a lob: throws)
	--   strafe,      the tuning's strafing and jumping, times these (aiming
	--   jumps        a Thunderclapper, it mostly stands still)
	--   patrolDepth  how far its patrols go toward the enemy's spawn (0..1)
	--   holdSeconds  how long it waits at each patrol spot, watching
	--   abilities    the weights of its Q ability
	-- Spritzer bots rush in for the close fight, Thunderclapper bots hang
	-- back and hold the long lines, Stink Lobber bots keep to the middle
	-- distance and lob over cover; the Gas Blaster plays as bots always did.
	WEAPONS = table.freeze({
		GasBlaster = style({
			weight = 3,
			closeIn = 60,
			backUp = 18,
			fireRange = 260,
			strafe = 1,
			jumps = 1,
			patrolDepth = { 0.4, 0.8 },
			holdSeconds = { 0, 0 },
			abilities = { RecoveryBurst = 1, GasPulse = 1 },
		}),
		Spritzer = style({
			weight = 2,
			-- Full gas to 45: it closes to well inside that, and doesn't waste
			-- shots past 75 (half gas by 90, nothing after).
			closeIn = 25,
			backUp = 6,
			fireRange = 75,
			strafe = 1,
			jumps = 1,
			patrolDepth = { 0.5, 0.9 },
			holdSeconds = { 0, 0 },
			abilities = { GasPulse = 3, RecoveryBurst = 1 },
		}),
		Thunderclapper = style({
			weight = 2,
			-- Full gas to 240: anyone it can see. It keeps them out past 80.
			closeIn = 200,
			backUp = 80,
			fireRange = 420,
			strafe = 0.4,
			jumps = 0.2,
			patrolDepth = { 0.2, 0.5 },
			holdSeconds = { 6, 12 },
			abilities = { RecoveryBurst = 3, GasPulse = 1 },
		}),
		StinkLobber = style({
			weight = 2,
			-- Thrown up to 150 (about 148 from head height): it closes to 110
			-- and throws from 140, so a throw never has to be its longest.
			closeIn = 110,
			backUp = 30,
			fireRange = 140,
			strafe = 1,
			jumps = 1,
			patrolDepth = { 0.35, 0.7 },
			holdSeconds = { 0, 0 },
			abilities = { RecoveryBurst = 2, GasPulse = 1 },
		}),
	}),
	SAME_WEAPON_FACTOR = 0.35,
	-- Fart Dash (same cooldown and checks as a player's; only on the ground):
	-- in a fight it now and then dashes at a target farther than closeIn
	-- plus a dash's length, or away from one well inside backUp (half a dash
	-- inside), and while backing off away from whoever is in sight within
	-- ESCAPE_STUDS; never into something solid. How often: the tuning's
	-- dashesPerSecond.
	ESCAPE_STUDS = 90,
	-- Q abilities, after its reaction time: Recovery Burst once its gas is
	-- up to VENT_GAS; Gas Pulse with a target in sight within PULSE_STUDS
	-- (the ring reaches 12, and the wind-up is 0.4 s).
	VENT_GAS = 60,
	PULSE_STUDS = 8,
	-- A Stink Lobber throws the low arc when it's clear and the high one when
	-- it isn't (checked with LOB_RAYS rays along each), and goes on throwing
	-- over cover, high, at where it last saw a target for LOB_BLIND_SECONDS.
	LOB_RAYS = 8,
	LOB_BLIND_SECONDS = 2.5,
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
	-- Each strafe lasts STRAFE_SECONDS (min, max); where it closes in and
	-- backs up depends on its gun (WEAPONS).
	STRAFE_SECONDS = table.freeze({ 0.6, 1.4 }),
	-- Backing off (tuning.backOffGas) lasts until gas is down to this.
	RESUME_GAS = 30,
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
	-- The chance a second of a Fart Dash while one would help it (never
	-- inside the cooldown) [0.35: about three seconds after it's ready].
	DASHES_PER_SECOND = range(0.1, 0.6),
}

local function blend(value: Range, difficulty: number): number
	return value.easy + (value.hard - value.easy) * difficulty
end

-- One of `ids`, each `weightOf(id)` likely.
local function pick(rng: Random, ids: { string }, weightOf: (string) -> number): string?
	local total = 0
	for _, id in ids do
		total += math.max(0, weightOf(id))
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, id in ids do
		roll -= math.max(0, weightOf(id))
		if roll < 0 then
			return id
		end
	end
	return ids[#ids]
end

local ABILITY_ORDER = { "RecoveryBurst", "GasPulse" }

-- A life's loadout: a gun by WEAPONS' weights (each of `teammates`, the
-- guns the team's other bots carry, making its own SAME_WEAPON_FACTOR times
-- as likely), and that gun's pick of a Q ability (nil: none).
function BotConfig.pickLoadout(rng: Random, teammates: { string }?): (string, string?)
	local carried: { [string]: number } = {}
	for _, id in teammates or {} do
		carried[id] = (carried[id] or 0) + 1
	end
	local weapon = pick(rng, WeaponConfig.order, function(id)
		local entry = BotConfig.WEAPONS[id]
		return if entry then entry.weight * BotConfig.SAME_WEAPON_FACTOR ^ (carried[id] or 0) else 0
	end) or BotConfig.WEAPON
	local entry = BotConfig.WEAPONS[weapon]
	local ability = if entry
		then pick(rng, ABILITY_ORDER, function(id)
			return entry.abilities[id] or 0
		end)
		else nil
	return weapon, ability
end

-- How `weapon` is fought with (the Gas Blaster's way for one it doesn't know).
function BotConfig.styleOf(weapon: string?): Style
	return BotConfig.WEAPONS[weapon :: any] or BotConfig.WEAPONS[BotConfig.WEAPON]
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
		dashesPerSecond = blend(BotConfig.DASHES_PER_SECOND, d),
	})
end

return table.freeze(BotConfig)
