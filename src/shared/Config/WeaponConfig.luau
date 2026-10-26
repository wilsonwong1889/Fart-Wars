-- Weapons, each by the masterplan's contract: id, damage per hit, fire
-- interval, effective range, projectile behaviour, magazine, effects and
-- unlock rule. Phase 1 has one placeholder; its damage comes off Roblox
-- health, which Phase 2's gas meter replaces (damage becomes gas per hit).
export type Weapon = {
	id: string,
	displayName: string,
	placeholder: boolean,
	damage: number,
	fireInterval: number,
	range: number,
	projectile: "hitscan",
	magazine: number?,
	tracerColor: Color3,
	unlock: "starter",
}

local weapons: { [string]: Weapon } = {
	StarterBlaster = table.freeze({
		id = "StarterBlaster",
		displayName = "Starter Blaster",
		placeholder = true,
		damage = 25, -- four hits
		fireInterval = 0.3,
		range = 160, -- across the whole map
		projectile = "hitscan",
		magazine = nil, -- no reloading yet
		tracerColor = Color3.fromRGB(180, 255, 90),
		unlock = "starter",
	}),
}

return table.freeze({
	default = "StarterBlaster",
	weapons = table.freeze(weapons),
})
