-- Abilities, each by the masterplan's contract: id, input, duration,
-- cooldown, the states it may be used in, its effects, and who owns it.
-- Fart Dash (Shift) is everyone's. One Q ability at a time, unlocked by
-- level and equipped in the menu, so powerful bonuses never stack; each
-- has a long cooldown and a visible tell so the other side can play
-- around it. Values are proposals to tune.
export type Ability = {
	id: string,
	displayName: string,
	description: string,
	input: Enum.KeyCode,
	durationSeconds: number,
	cooldownSeconds: number,
	-- Player states it can be used in, and conditions that block it.
	allowedStates: { string },
	blockedWhileExploding: boolean,
	allowedWhileProtected: boolean,
	-- Using it ends spawn protection (attacks do, like firing).
	endsProtection: boolean,
	effects: { string },
	ownership: "everyone" | "unlock",
	-- The level that unlocks it (unlock abilities).
	level: number?,
	-- Fart Dash: the client pushes the avatar at `speed`; the server checks,
	-- `checkSeconds` later, that it didn't travel further than
	-- `maxTravelStuds` plus walking allows (or puts it back).
	speed: number?,
	checkSeconds: number?,
	maxTravelStuds: number?,
	-- Recovery Burst: gas vented at once.
	vent: number?,
	-- Gas Pulse: after `durationSeconds` of wind-up, `gas` to every enemy
	-- within `radius` (walls stop it).
	radius: number?,
	gas: number?,
}

local abilities: { [string]: Ability } = {
	FartDash = table.freeze({
		id = "FartDash",
		displayName = "Fart Dash",
		description = "A quick burst of speed along the ground.",
		input = Enum.KeyCode.LeftShift,
		durationSeconds = 0.2,
		cooldownSeconds = 3,
		allowedStates = table.freeze({ "ACTIVE" }),
		blockedWhileExploding = true,
		-- It's movement, not an attack: dashing out of spawn keeps protection.
		allowedWhileProtected = true,
		endsProtection = false,
		effects = table.freeze({ "trail", "dashSound" }),
		ownership = "everyone",
		speed = 70,
		checkSeconds = 0.5,
		maxTravelStuds = 30,
	}),
	RecoveryBurst = table.freeze({
		id = "RecoveryBurst",
		displayName = "Recovery Burst",
		description = "Vent 35% of your gas at once. Everyone sees the puff.",
		input = Enum.KeyCode.Q,
		durationSeconds = 0.5,
		cooldownSeconds = 20,
		allowedStates = table.freeze({ "ACTIVE" }),
		-- Too late once the countdown starts: that's the counterplay.
		blockedWhileExploding = true,
		allowedWhileProtected = true,
		endsProtection = false,
		effects = table.freeze({ "vent", "puff" }),
		ownership = "unlock",
		level = 10,
		vent = 35,
	}),
	GasPulse = table.freeze({
		id = "GasPulse",
		displayName = "Gas Pulse",
		description = "A visible wind-up, then a ring of gas: 15% to every enemy within 12 studs.",
		input = Enum.KeyCode.Q,
		durationSeconds = 0.4, -- the wind-up: time to see it coming
		cooldownSeconds = 25,
		allowedStates = table.freeze({ "ACTIVE" }),
		blockedWhileExploding = true,
		allowedWhileProtected = true,
		endsProtection = true,
		effects = table.freeze({ "ring", "pulseSound" }),
		ownership = "unlock",
		level = 30,
		radius = 12,
		gas = 15,
	}),
}

return table.freeze(abilities)
