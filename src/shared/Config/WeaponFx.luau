-- How the weapons move and what comes out of them (the Blender models'
-- animations, done in code so they need no uploaded animation assets):
--   * equip: the gun comes up from DROP degrees below over SECONDS
--   * recoil: each shot kicks the gun back KICK studs and RISE degrees up,
--     settling with a time constant of RECOVER seconds (kicks stack to
--     MAX_RECOIL); the Stink Lobber's big rise is its throw
--   * muzzle: particles from the muzzle (a texture from ArtAssets, tinted
--     the weapon's gas colour); the Thunderclapper adds a flash of light
--     and, for its own shooter, a small camera kick
--   * idle: the gas tank's slow glow
--   * impacts: a puff and sparks where a shot hits something
-- Reduce motion (Settings) keeps a little recoil and none of the rest of
-- the movement; reduced effects halve the particles.
export type Muzzle = { texture: string, count: number, size: number, speed: number, lifetime: number, spread: number?, gravity: number? }
export type Weapon = { kick: number, rise: number, recover: number, muzzle: Muzzle, flash: { brightness: number, range: number, seconds: number }?, cameraKick: number?, sparks: number? }

return table.freeze({
	EQUIP = table.freeze({ SECONDS = 0.3, DROP = 55 }),
	IDLE = table.freeze({ PERIOD = 1.8, GLOW = 0.3 }),
	MAX_RECOIL = 1.6,
	-- With reduce motion, recoil at this share.
	REDUCED_RECOIL = 0.35,
	-- Particles emitted per frame at most, everyone's shots together.
	MAX_PARTICLES_PER_FRAME = 60,
	IMPACT = table.freeze({ texture = "puff", count = 3, size = 0.7, sparks = 2, pool = 8 }),
	weapons = table.freeze({
		GasBlaster = table.freeze({
			kick = 0.22,
			rise = 7,
			recover = 0.12,
			muzzle = table.freeze({ texture = "puff", count = 4, size = 0.55, speed = 7, lifetime = 0.35 }),
		}),
		Spritzer = table.freeze({
			kick = 0.05,
			rise = 1.5,
			recover = 0.05,
			muzzle = table.freeze({ texture = "droplet", count = 4, size = 0.22, speed = 22, lifetime = 0.25, spread = 7, gravity = 30 }),
		}),
		Thunderclapper = table.freeze({
			kick = 0.55,
			rise = 16,
			recover = 0.3,
			muzzle = table.freeze({ texture = "puff", count = 9, size = 1.1, speed = 9, lifetime = 0.5 }),
			flash = table.freeze({ brightness = 3, range = 14, seconds = 0.07 }),
			cameraKick = 1.6,
			sparks = 3,
		}),
		StinkLobber = table.freeze({
			kick = 0.18,
			rise = 24,
			recover = 0.35,
			muzzle = table.freeze({ texture = "puff", count = 6, size = 0.8, speed = 4, lifetime = 0.6 }),
		}),
	}) :: any,
}) :: { EQUIP: { SECONDS: number, DROP: number }, IDLE: { PERIOD: number, GLOW: number }, MAX_RECOIL: number, REDUCED_RECOIL: number, MAX_PARTICLES_PER_FRAME: number, IMPACT: { texture: string, count: number, size: number, sparks: number, pool: number }, weapons: { [string]: Weapon } }
