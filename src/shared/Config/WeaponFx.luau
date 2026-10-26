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
--   * shot: what the shot looks like (ShotFx, the Blender meshes in
--     Config/ShotArt): a glowing gas bolt `width` across and up to
--     `length` long streaks from the muzzle at `speed` studs a second to
--     where the shot stopped; the muzzle flashes a burst `burst` studs
--     across; a splat `splat` across sticks where it hit a wall or floor.
--     A width of 0 draws no bolt (the Stink Lobber's bomb is its own).
-- Reduce motion (Settings) keeps a little recoil and none of the rest of
-- the movement; reduced effects halve the particles. Either leaves out
-- the bursts and splats (the bolt always shows where the shot went).
export type Muzzle = { texture: string, count: number, size: number, speed: number, lifetime: number, spread: number?, gravity: number? }
export type Shot = { width: number, length: number, speed: number, burst: number, splat: number }
export type Weapon = { kick: number, rise: number, recover: number, muzzle: Muzzle, shot: Shot, flash: { brightness: number, range: number, seconds: number }?, cameraKick: number?, sparks: number? }

return table.freeze({
	EQUIP = table.freeze({ SECONDS = 0.3, DROP = 55 }),
	IDLE = table.freeze({ PERIOD = 1.8, GLOW = 0.3 }),
	MAX_RECOIL = 1.6,
	-- With reduce motion, recoil at this share.
	REDUCED_RECOIL = 0.35,
	-- Particles emitted per frame at most, everyone's shots together.
	MAX_PARTICLES_PER_FRAME = 60,
	IMPACT = table.freeze({ texture = "puff", count = 3, size = 0.7, sparks = 2, pool = 8 }),
	-- The shots (ShotFx): pools of bursts and splats, how long each shows,
	-- and the glow round a bolt (that many times its width, see-through).
	SHOT = table.freeze({
		BURSTS = 8,
		SPLATS = 12,
		BURST_SECONDS = 0.08,
		SPLAT_SECONDS = 0.9,
		SPLAT_TRANSPARENCY = 0.1,
		GLOW = 2.4,
		GLOW_TRANSPARENCY = 0.7,
	}),
	weapons = table.freeze({
		GasBlaster = table.freeze({
			kick = 0.22,
			rise = 7,
			recover = 0.12,
			muzzle = table.freeze({ texture = "puff", count = 4, size = 0.55, speed = 7, lifetime = 0.35 }),
			shot = table.freeze({ width = 0.3, length = 6, speed = 600, burst = 1.3, splat = 1.5 }),
		}),
		Spritzer = table.freeze({
			kick = 0.05,
			rise = 1.5,
			recover = 0.05,
			muzzle = table.freeze({ texture = "droplet", count = 4, size = 0.22, speed = 22, lifetime = 0.25, spread = 7, gravity = 30 }),
			shot = table.freeze({ width = 0.12, length = 3, speed = 900, burst = 0.55, splat = 0.7 }),
		}),
		Thunderclapper = table.freeze({
			kick = 0.55,
			rise = 16,
			recover = 0.3,
			muzzle = table.freeze({ texture = "puff", count = 9, size = 1.1, speed = 9, lifetime = 0.5 }),
			shot = table.freeze({ width = 0.5, length = 9, speed = 520, burst = 2.2, splat = 2.6 }),
			flash = table.freeze({ brightness = 3, range = 14, seconds = 0.07 }),
			cameraKick = 1.6,
			sparks = 3,
		}),
		StinkLobber = table.freeze({
			kick = 0.18,
			rise = 24,
			recover = 0.35,
			muzzle = table.freeze({ texture = "puff", count = 6, size = 0.8, speed = 4, lifetime = 0.6 }),
			shot = table.freeze({ width = 0, length = 0, speed = 1, burst = 1.0, splat = 0 }),
		}),
	}) :: any,
}) :: {
	EQUIP: { SECONDS: number, DROP: number },
	IDLE: { PERIOD: number, GLOW: number },
	MAX_RECOIL: number,
	REDUCED_RECOIL: number,
	MAX_PARTICLES_PER_FRAME: number,
	IMPACT: { texture: string, count: number, size: number, sparks: number, pool: number },
	SHOT: {
		BURSTS: number,
		SPLATS: number,
		BURST_SECONDS: number,
		SPLAT_SECONDS: number,
		SPLAT_TRANSPARENCY: number,
		GLOW: number,
		GLOW_TRANSPARENCY: number,
	},
	weapons: { [string]: Weapon },
}
