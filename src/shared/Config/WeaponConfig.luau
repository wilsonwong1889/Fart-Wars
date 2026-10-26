-- Weapons, each by the masterplan's contract: id, gas per hit, fire
-- interval, effective range, projectile behaviour, magazine, handling,
-- effects and unlock rule. Each is a different way to play, not a bigger
-- number: the Spritzer melts close targets and fizzles at range, the
-- Thunderclapper hits hard and slowly (and slows you), the Stink Lobber
-- denies ground with a lingering cloud. Prices and levels are proposals to
-- tune from session data. The shop shows all of it; the server checks it.
export type Weapon = {
	id: string,
	displayName: string,
	-- One line on how it plays, for the shop.
	description: string,
	gasPerHit: number,
	headshotGas: number,
	fireInterval: number,
	range: number,
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
		description = "The all-rounder: steady shots at any range.",
		gasPerHit = 20, -- five body hits
		headshotGas = 25, -- four to the head
		fireInterval = 0.3,
		range = 160, -- across the whole map
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
		description = "A rapid spray that melts anyone close and fizzles out past 60 studs.",
		gasPerHit = 7,
		headshotGas = 9,
		fireInterval = 0.1,
		range = 60,
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
		description = "Slow, heavy blasts that reward a steady aim: two headshots and they're gone. Heavy to carry.",
		gasPerHit = 40,
		headshotGas = 55,
		fireInterval = 1,
		range = 220,
		projectile = "hitscan",
		magazine = nil,
		walkSpeed = 14,
		tracerColor = Color3.fromRGB(255, 170, 60),
		fireSound = "thunderclapper",
		unlock = "shop",
		price = 1200,
		level = 15,
	}),
	StinkLobber = table.freeze({
		id = "StinkLobber",
		displayName = "Stink Lobber",
		description = "Lobs a stink bomb over cover; it leaves a cloud that gasses anyone who stays in it. Holds doorways and lanes.",
		gasPerHit = 15, -- the splash
		headshotGas = 15,
		fireInterval = 1.4,
		range = 90,
		projectile = "lob",
		magazine = nil,
		walkSpeed = 15,
		tracerColor = Color3.fromRGB(160, 200, 60),
		fireSound = "lobber",
		unlock = "shop",
		price = 2500,
		level = 25,
		lobSpeed = 70,
		lobGravity = 60,
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
