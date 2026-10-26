-- How the weapons move and what comes out of them (the Blender models'
-- animations, done in code so they need no uploaded animation assets):
--   * equip: the gun swings up from DROP degrees below over SECONDS,
--     overshooting a little, and a light gun twirls `twirl` degrees round
--     its barrel on the way
--   * recoil: each shot kicks the gun back `kick` studs and `rise` degrees
--     up, and up to `twist` degrees to a side; springs (`frequency` Hz,
--     `damping`: under 1 overshoots) bring it back; kicks stack to
--     MAX_RECOIL. The Stink Lobber's big rise is its throw
--   * idle and walking: the gun sways slowly (IDLE) and bobs with its
--     holder's steps (WALK)
--   * moving parts (`parts`, by the part's name in WeaponArt): a "slide"
--     pumps back `amount` studs and returns over `seconds` on every shot;
--     a "swing" (the gauge's needle) turns up to `amount` degrees as the
--     gun's PRESSURE drops with each shot, and back as it recovers; a
--     "reload" (the Stink Lobber's bomb) is gone when thrown and grows
--     back over the last `amount` of `seconds`. Each turns and scales
--     round its own centre, or round `pivot`'s
--   * the gas: the tank and vents pulse slowly and flash on every shot;
--     after a burst of shots the barrel smokes (HEAT)
--   * muzzle: particles from the muzzle (a texture from ArtAssets, tinted
--     the weapon's gas colour), sparks, a flash of light that lights the
--     room (`flash`), and for the shooter's own shots a camera kick
--     (`cameraKick` degrees)
--   * shot: what the shot looks like (ShotFx, the Blender meshes in
--     Config/ShotArt): a glowing gas bolt `width` across and up to
--     `length` long streaks from the muzzle at `speed` studs a second to
--     where the shot stopped, lighting what it passes (`light`: its
--     light's range) and leaving a trail of smoke (a puff every `trail`
--     studs; droplets for the Spritzer); the muzzle flashes a burst
--     `burst` studs across and a shock ring `ring` across spreads from
--     it; a splat `splat` across sticks where it hit a wall or floor, with
--     a ring, a puff, sparks and a flash of light (IMPACT). A width of 0
--     draws no bolt (the Stink Lobber's bomb is its own)
--   * hits: a player your shot hits flashes white for a moment (HIT)
-- Reduce motion (Settings) keeps a little recoil and none of the rest of
-- the gun's movement (no camera kick, sway or twirl; the moving parts
-- only show where they are). Reduced effects halve the particles and
-- leave out the bursts, rings, splats, lights, trails and smoke: the bolt
-- always shows where the shot went.
export type Muzzle = { texture: string, count: number, size: number, speed: number, lifetime: number, spread: number?, gravity: number? }
export type Shot = {
	width: number,
	length: number,
	speed: number,
	burst: number,
	splat: number,
	ring: number,
	trail: number,
	trailTexture: string?,
	light: number,
}
export type Motion = { kind: string, amount: number, seconds: number, pivot: string? }
export type Weapon = {
	kick: number,
	rise: number,
	twist: number,
	frequency: number,
	damping: number,
	twirl: number,
	muzzle: Muzzle,
	shot: Shot,
	flash: { brightness: number, range: number, seconds: number }?,
	cameraKick: number?,
	sparks: number?,
	parts: { [string]: Motion }?,
}

return table.freeze({
	EQUIP = table.freeze({ SECONDS = 0.35, DROP = 55 }),
	-- The tank's glow (a cycle every PERIOD seconds, up to GLOW less
	-- bright) and the slow sway (SWAY degrees, a cycle every SWAY_PERIOD).
	IDLE = table.freeze({ PERIOD = 1.8, GLOW = 0.3, SWAY = 0.6, SWAY_PERIOD = 3.4 }),
	-- Walking: BOB studs down and ROLL degrees side to side, RATE steps a
	-- second at walking speed (16).
	WALK = table.freeze({ BOB = 0.06, ROLL = 2.5, RATE = 1.8 }),
	-- Each shot drops a gun's pressure by DROP (of 1); it comes back at
	-- RECOVER a second.
	PRESSURE = table.freeze({ DROP = 0.2, RECOVER = 0.6 }),
	-- Each shot heats the barrel by SHOT; it cools at COOL a second; over
	-- 1 it smokes, SMOKE puffs a second for each unit of heat over.
	HEAT = table.freeze({ SHOT = 0.35, COOL = 0.7, SMOKE = 5, MAX = 3 }),
	MAX_RECOIL = 1.6,
	-- With reduce motion, recoil at this share.
	REDUCED_RECOIL = 0.35,
	-- Particles emitted per frame at most, everyone's shots together.
	MAX_PARTICLES_PER_FRAME = 60,
	-- Where a shot hits: puffs and sparks, a light `light` studs across
	-- for LIGHT_SECONDS, and a ring the size of the weapon's splat.
	IMPACT = table.freeze({ texture = "puff", count = 4, size = 0.7, sparks = 4, pool = 8, light = 9, LIGHT_SECONDS = 0.08 }),
	-- A player hit by your shot flashes white for SECONDS.
	HIT = table.freeze({ SECONDS = 0.14, TRANSPARENCY = 0.35 }),
	-- The shots (ShotFx): pools of bursts, rings and splats, how long each
	-- shows, the glow round a bolt (that many times its width,
	-- see-through), its light, and how many trail puffs a frame at most.
	SHOT = table.freeze({
		BURSTS = 8,
		RINGS = 8,
		SPLATS = 12,
		BURST_SECONDS = 0.08,
		RING_SECONDS = 0.2,
		RING_TRANSPARENCY = 0.3,
		SPLAT_SECONDS = 0.9,
		SPLAT_TRANSPARENCY = 0.1,
		GLOW = 2.4,
		GLOW_TRANSPARENCY = 0.7,
		BOLT_LIGHT = 1.5,
		TRAIL_PER_FRAME = 24,
	}),
	weapons = table.freeze({
		GasBlaster = table.freeze({
			kick = 0.24,
			rise = 8,
			twist = 2.5,
			frequency = 5.5,
			damping = 0.45,
			twirl = 360,
			muzzle = table.freeze({ texture = "puff", count = 4, size = 0.55, speed = 7, lifetime = 0.35 }),
			shot = table.freeze({ width = 0.3, length = 6, speed = 600, burst = 1.3, splat = 1.5, ring = 1.2, trail = 3, light = 7 }),
			flash = table.freeze({ brightness = 2, range = 10, seconds = 0.05 }),
			cameraKick = 0.4,
			sparks = 2,
			parts = table.freeze({
				Pump = table.freeze({ kind = "slide", amount = 0.16, seconds = 0.22 }),
				Needle = table.freeze({ kind = "swing", amount = 70, seconds = 0 }),
			}),
		}),
		Spritzer = table.freeze({
			kick = 0.06,
			rise = 1.8,
			twist = 1.2,
			frequency = 9,
			damping = 0.5,
			twirl = 360,
			muzzle = table.freeze({ texture = "droplet", count = 4, size = 0.22, speed = 22, lifetime = 0.25, spread = 7, gravity = 30 }),
			shot = table.freeze({ width = 0.12, length = 3, speed = 900, burst = 0.55, splat = 0.7, ring = 0, trail = 5, trailTexture = "droplet", light = 0 }),
			flash = table.freeze({ brightness = 1.2, range = 6, seconds = 0.03 }),
			cameraKick = 0.12,
			parts = table.freeze({
				Pump = table.freeze({ kind = "slide", amount = 0.1, seconds = 0.09 }),
			}),
		}),
		Thunderclapper = table.freeze({
			kick = 0.55,
			rise = 16,
			twist = 4,
			frequency = 3.5,
			damping = 0.4,
			twirl = 0,
			muzzle = table.freeze({ texture = "puff", count = 9, size = 1.1, speed = 9, lifetime = 0.5 }),
			shot = table.freeze({ width = 0.5, length = 9, speed = 520, burst = 2.2, splat = 2.6, ring = 2.6, trail = 2, light = 11 }),
			flash = table.freeze({ brightness = 3, range = 14, seconds = 0.07 }),
			cameraKick = 1.6,
			sparks = 3,
		}),
		StinkLobber = table.freeze({
			kick = 0.18,
			rise = 24,
			twist = 2,
			frequency = 3,
			damping = 0.5,
			twirl = 0,
			muzzle = table.freeze({ texture = "puff", count = 6, size = 0.8, speed = 4, lifetime = 0.6 }),
			shot = table.freeze({ width = 0, length = 0, speed = 1, burst = 1.0, splat = 0, ring = 1.4, trail = 0, light = 0 }),
			cameraKick = 0.5,
			parts = table.freeze({
				Bomb = table.freeze({ kind = "reload", amount = 0.4, seconds = 1.4 }),
				Fuse = table.freeze({ kind = "reload", amount = 0.4, seconds = 1.4, pivot = "Bomb" }),
			}),
		}),
	}) :: any,
}) :: {
	EQUIP: { SECONDS: number, DROP: number },
	IDLE: { PERIOD: number, GLOW: number, SWAY: number, SWAY_PERIOD: number },
	WALK: { BOB: number, ROLL: number, RATE: number },
	PRESSURE: { DROP: number, RECOVER: number },
	HEAT: { SHOT: number, COOL: number, SMOKE: number, MAX: number },
	MAX_RECOIL: number,
	REDUCED_RECOIL: number,
	MAX_PARTICLES_PER_FRAME: number,
	IMPACT: { texture: string, count: number, size: number, sparks: number, pool: number, light: number, LIGHT_SECONDS: number },
	HIT: { SECONDS: number, TRANSPARENCY: number },
	SHOT: {
		BURSTS: number,
		RINGS: number,
		SPLATS: number,
		BURST_SECONDS: number,
		RING_SECONDS: number,
		RING_TRANSPARENCY: number,
		SPLAT_SECONDS: number,
		SPLAT_TRANSPARENCY: number,
		GLOW: number,
		GLOW_TRANSPARENCY: number,
		BOLT_LIGHT: number,
		TRAIL_PER_FRAME: number,
	},
	weapons: { [string]: Weapon },
}
