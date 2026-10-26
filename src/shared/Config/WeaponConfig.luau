-- Weapons, each by the masterplan's contract: id, gas per hit, fire
-- interval, effective range, projectile behaviour, magazine, effects and
-- unlock rule. More archetypes (rapid spray, heavy burst, area denial)
-- arrive with the shop in Phase 3.
export type Weapon = {
	id: string,
	displayName: string,
	gasPerHit: number,
	headshotGas: number,
	fireInterval: number,
	range: number,
	projectile: "hitscan",
	magazine: number?,
	tracerColor: Color3,
	fireSound: string, -- AudioConfig key
	unlock: "starter",
}

local weapons: { [string]: Weapon } = {
	GasBlaster = table.freeze({
		id = "GasBlaster",
		displayName = "Gas Blaster",
		gasPerHit = 20, -- five body hits
		headshotGas = 25, -- four to the head
		fireInterval = 0.3,
		range = 160, -- across the whole map
		projectile = "hitscan",
		magazine = nil, -- no reloading yet
		tracerColor = Color3.fromRGB(180, 255, 90),
		fireSound = "blaster",
		unlock = "starter",
	}),
}

return table.freeze({
	default = "GasBlaster",
	weapons = table.freeze(weapons),
})
