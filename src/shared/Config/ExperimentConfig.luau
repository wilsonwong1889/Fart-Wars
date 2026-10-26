-- Retention experiments (masterplan 4.5): reward timing, early unlock
-- costs and tutorial prompts, each tried on a share of players and compared
-- against a control group in telemetry. Every experiment starts at
-- percent = 0 (nobody enrolled, everyone gets the control value), so
-- nothing changes until someone turns one on here.
--
-- A player's cohort comes from their user ID and the experiment's salt, so
-- it is the same in every server and every session, and needs no saving.
-- Of the players enrolled (percent of everyone), each variant gets its
-- weight's share; "control" is one of the variants, so the comparison is
-- like with like. Change the salt to draw new cohorts.
--
-- Guardrails: experiments only move timing, prices of early unlocks and
-- prompts, never combat power, odds or what Robux buys.
export type Variant = { name: string, weight: number, value: any }
export type Experiment = {
	key: string,
	summary: string,
	percent: number,
	salt: string,
	variants: { Variant },
}

local RewardsConfig = require(script.Parent.RewardsConfig)

local ExperimentConfig = {}

ExperimentConfig.experiments = {
	{
		key = "giftMinutes",
		summary = "Minutes of active play per free-spin gift",
		percent = 0,
		salt = "giftMinutes-1",
		variants = {
			{ name = "control", weight = 1, value = RewardsConfig.GIFT_ACTIVE_MINUTES },
			{ name = "eight", weight = 1, value = 8 },
		},
	},
	{
		key = "earlyUnlock",
		summary = "Price of early shop weapons (at most EARLY_UNLOCK_MAX_PRICE coins)",
		percent = 0,
		salt = "earlyUnlock-1",
		variants = {
			{ name = "control", weight = 1, value = 1 },
			{ name = "cheaper", weight = 1, value = 0.75 },
		},
	},
	{
		key = "tips",
		summary = "Contextual tips on by default (Settings can always change it)",
		percent = 0,
		salt = "tips-1",
		variants = {
			{ name = "control", weight = 1, value = true },
			{ name = "off", weight = 1, value = false },
		},
	},
} :: { Experiment }

-- Shop weapons at or under this price count as early unlocks.
ExperimentConfig.EARLY_UNLOCK_MAX_PRICE = 500

function ExperimentConfig.get(key: string): Experiment?
	for _, experiment in ExperimentConfig.experiments do
		if experiment.key == key then
			return experiment
		end
	end
	return nil
end

-- The value of `variant` in experiment `key` (the control's for anything
-- else, including nil).
function ExperimentConfig.valueOf(key: string, variant: string?): any
	local experiment = ExperimentConfig.get(key)
	if not experiment then
		return nil
	end
	for _, entry in experiment.variants do
		if entry.name == variant then
			return entry.value
		end
	end
	return experiment.variants[1].value
end

-- FNV-1a over the text, 32 bits, then 0..9999.
function ExperimentConfig.bucket(text: string): number
	local hash = 2166136261
	for i = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, i))
		-- hash * 16777619 (2^24 + 403), kept to 32 bits without losing precision
		hash = (bit32.lshift(hash, 24) + hash * 403) % 4294967296
	end
	return hash % 10000
end

-- The variant `userId` is in, or nil if they aren't enrolled.
function ExperimentConfig.assign(experiment: Experiment, userId: number): string?
	if experiment.percent <= 0 or ExperimentConfig.bucket(`{experiment.salt}:in:{userId}`) >= experiment.percent * 100 then
		return nil
	end
	local total = 0
	for _, variant in experiment.variants do
		total += variant.weight
	end
	local roll = ExperimentConfig.bucket(`{experiment.salt}:variant:{userId}`) / 10000 * total
	for _, variant in experiment.variants do
		roll -= variant.weight
		if roll < 0 then
			return variant.name
		end
	end
	return experiment.variants[#experiment.variants].name
end

-- A weapon's price with the earlyUnlock multiplier (in steps of 25 coins).
function ExperimentConfig.weaponPrice(price: number, multiplier: number?): number
	if not multiplier or multiplier == 1 or price <= 0 or price > ExperimentConfig.EARLY_UNLOCK_MAX_PRICE then
		return price
	end
	return math.max(25, math.floor(price * multiplier / 25 + 0.5) * 25)
end

return ExperimentConfig
