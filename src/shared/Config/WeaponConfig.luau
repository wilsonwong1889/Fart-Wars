-- Weapons, each by the masterplan's contract: id, gas per hit, fire
-- interval, effective range, projectile behaviour, magazine, handling,
-- effects and unlock rule. Each is a different way to play, not a bigger
-- number: the Spritzer melts close targets and fizzles at range, the
-- Thunderclapper hits hard and slowly (and slows you), the Stink Lobber
-- denies ground with a lingering cloud. Prices and levels are proposals to
-- tune from session data. The shop shows all of it; the server checks it.
--
-- Ranges are for Brainrot Battlefield at full size (480 x 480 studs;
-- avatars, walking and blasts at their usual size), measured from its
-- layout: each lane is 480 studs end wall to end wall, the middle lane
-- 336 between the spawn rooms' fronts, and half of all clear sightlines
-- between places you can stand are under 115 studs, nine in ten under 265.
--   Spritzer        full gas to 45, nothing past 90: the fight at the next
--                   bit of cover (half the middle lane's sightlines are
--                   under 75; a divider gap is 36 long, the throne 96)
--   Gas Blaster     full gas to 120 (your spawn room's front to the
--                   throne), half by 260: nine sightlines in ten
--   Thunderclapper  full gas to 240 (the centre line to an end wall), half
--                   by 420: almost every sightline, but not end to end
--   Stink Lobber    thrown up to 150 (two sightlines in three are shorter),
--                   and it needs no sightline: a steeper, shorter throw
--                   clears the throne and the dividers
-- Instant (hitscan) shots lose gas with distance, so a long shot is never
-- as good as a close one: full gas out to `effectiveRange`, then less in a
-- straight line down to `minGasShare` of it at `range`, and nothing past
-- that. A headshot loses the same share, so it stays the better hit. The
-- server measures the distance (CombatService.gasAt).
export type Weapon = {
	id: string,
	displayName: string,
	-- One line on how it plays, for the shop.
	description: string,
	gasPerHit: number,
	headshotGas: number,
	fireInterval: number,
	-- How far a shot reaches (a lob: how far it can be thrown), in studs.
	range: number,
	-- Instant weapons: full gas out to effectiveRange, falling to
	-- minGasShare of it at range.
	effectiveRange: number?,
	minGasShare: number?,
	projectile: "hitscan" | "lob",
	magazine: number?,
	-- Handling: walking speed while it's equipped (studs a second).
	walkSpeed: number,
	tracerColor: Color3,
	fireSound: string, -- AudioConfig key
	unlock: "starter" | "shop",
	-- Coins in the shop, and the level it goes on sale at.
	price: number,
	level: number,
	-- Lobbed weapons: launch speed and drop, the impact splash (gasPerHit
	-- within splashRadius), and the cloud it leaves (cloudGas every
	-- cloudTickSeconds to enemies inside, for cloudSeconds).
	lobSpeed: number?,
	lobGravity: number?,
	splashRadius: number?,
	cloudRadius: number?,
	cloudGas: number?,
	cloudTickSeconds: number?,
	cloudSeconds: number?,
}

local weapons: { [string]: Weapon } = {
	GasBlaster = table.freeze({
		id = "GasBlaster",
		displayName = "Gas Blaster",
		description = "The all-rounder: full gas out to 120 studs, then weaker shots out to 260.",
		gasPerHit = 20, -- five body hits
		headshotGas = 25, -- four to the head
		fireInterval = 0.3,
		range = 260, -- nine sightlines in ten; the long ones are the Thunderclapper's
		effectiveRange = 120,
		minGasShare = 0.5,
		projectile = "hitscan",
		magazine = nil, -- no reloading yet
		walkSpeed = 16,
		tracerColor = Color3.fromRGB(180, 255, 90),
		fireSound = "blaster",
		unlock = "starter",
		price = 0,
		level = 1,
	}),
	Spritzer = table.freeze({
		id = "Spritzer",
		displayName = "Spritzer",
		description = "A rapid spray that melts anyone close and fizzles out past 90 studs.",
		gasPerHit = 7,
		headshotGas = 9,
		fireInterval = 0.1,
		range = 90, -- close quarters: win the fight at the next cover, not across the lane
		effectiveRange = 45,
		minGasShare = 0.5,
		projectile = "hitscan",
		magazine = nil,
		walkSpeed = 16,
		tracerColor = Color3.fromRGB(120, 230, 255),
		fireSound = "spritzer",
		unlock = "shop",
		price = 400,
		level = 5,
	}),
	Thunderclapper = table.freeze({
		id = "Thunderclapper",
		displayName = "Thunderclapper",
		description = "Slow, heavy, long-range blasts: two headshots and they're gone, out to 240 studs. Heavy to carry.",
		gasPerHit = 40,
		headshotGas = 55,
		fireInterval = 1,
		range = 420, -- the longest reach, still short of the arena's 480
		effectiveRange = 240,
		minGasShare = 0.5,
		projectile = "hitscan",
		magazine = nil,
		walkSpeed = 14,
		tracerColor = Color3.fromRGB(255, 170, 60),
		fireSound = "thunderclapper",
		unlock = "shop",
		price = 3000,
		level = 15,
	}),
	StinkLobber = table.freeze({
		id = "StinkLobber",
		displayName = "Stink Lobber",
		description = "Lobs a stink bomb over cover, up to 150 studs. Its cloud gasses anyone who stays in it.",
		gasPerHit = 15, -- the splash
		headshotGas = 15,
		fireInterval = 1.4,
		range = 150, -- medium: past the Spritzer, inside the Gas Blaster's reach
		projectile = "lob",
		magazine = nil,
		walkSpeed = 15,
		tracerColor = Color3.fromRGB(160, 200, 60),
		fireSound = "lobber",
		unlock = "shop",
		price = 7000,
		level = 25,
		-- The farthest throw (about 45 degrees, from head height) lands just
		-- inside its range, peaking about as high as the dividers (42
		-- studs); to clear them or the throne, throw steeper and shorter
		-- (at 55 degrees: about 140 studs, 53 high). Every throw lands inside
		-- ProjectileService's 3-second flight, even straight up (a long one
		-- takes about 2 seconds; the old 121 and 60 burst in the air above
		-- 48 degrees).
		lobSpeed = 104,
		lobGravity = 75,
		splashRadius = 8,
		cloudRadius = 9,
		cloudGas = 5,
		cloudTickSeconds = 0.5,
		cloudSeconds = 4,
	}),
}

-- Shop order.
local order = { "GasBlaster", "Spritzer", "Thunderclapper", "StinkLobber" }

return table.freeze({
	default = "GasBlaster",
	weapons = table.freeze(weapons),
	order = table.freeze(order),
})
