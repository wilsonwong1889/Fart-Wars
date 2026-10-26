-- Abilities, each by the masterplan's contract: id, input, duration,
-- cooldown, the states it may be used in, its effects, and who owns it.
-- Phase 2 has one; more (gas resistance, recovery burst, gas pulse) are
-- proposals until approved.
export type Ability = {
	id: string,
	displayName: string,
	input: Enum.KeyCode,
	durationSeconds: number,
	cooldownSeconds: number,
	-- Player states it can be used in, and conditions that block it.
	allowedStates: { string },
	blockedWhileExploding: boolean,
	allowedWhileProtected: boolean,
	effects: { string },
	ownership: "everyone" | "unlock",
	-- Fart Dash: the client pushes the avatar at `speed`; the server checks,
	-- `checkSeconds` later, that it didn't travel further than
	-- `maxTravelStuds` plus walking allows (or puts it back).
	speed: number,
	checkSeconds: number,
	maxTravelStuds: number,
}

local abilities: { [string]: Ability } = {
	FartDash = table.freeze({
		id = "FartDash",
		displayName = "Fart Dash",
		input = Enum.KeyCode.LeftShift,
		durationSeconds = 0.2,
		cooldownSeconds = 3,
		allowedStates = table.freeze({ "ACTIVE" }),
		blockedWhileExploding = true,
		-- It's movement, not an attack: dashing out of spawn keeps protection.
		allowedWhileProtected = true,
		effects = table.freeze({ "trail", "dashSound" }),
		ownership = "everyone", -- unlocks arrive in Phase 3
		speed = 70,
		checkSeconds = 0.5,
		maxTravelStuds = 30,
	}),
}

return table.freeze(abilities)
