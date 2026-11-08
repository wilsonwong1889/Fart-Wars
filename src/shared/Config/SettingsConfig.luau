-- The Settings screen's choices that are kept in the player's profile
-- (DataService's Settings field): each one's default and the values it can
-- take. Settings.luau starts from these defaults; the server checks every
-- save against this list (SettingsService) and every load (DataService).
-- Only the choices a player has picked themselves are saved, so the rest
-- stay at their defaults (and the "tips" experiment can still start tips
-- off for someone who never picked).
--   toggle   on or off
--   steps    a number from its list (the screen's - and + walk along it)
--   choice   a name from its list (- and + go round it)
local SettingsConfig = {}

export type Setting = {
	kind: "toggle" | "steps" | "choice",
	default: any,
	steps: { number }?,
	choices: { string }?,
}

local function toggle(default: boolean): Setting
	return table.freeze({ kind = "toggle", default = default }) :: any
end

local function steps(default: number, list: { number }): Setting
	return table.freeze({ kind = "steps", default = default, steps = table.freeze(list) }) :: any
end

SettingsConfig.settings = table.freeze({
	-- On or off (Settings.luau says what each one does).
	reducedEffects = toggle(false),
	sound = toggle(true),
	lowDetail = toggle(false),
	reduceMotion = toggle(false),
	teamSymbols = toggle(true),
	tips = toggle(true),
	lockMouse = toggle(true),
	-- The game's sound effects, 0 to 1 in quarters; the HUD's size.
	volume = steps(1, { 0, 0.25, 0.5, 0.75, 1 }),
	hudScale = steps(1, { 0.8, 0.9, 1, 1.1, 1.25 }),
	-- The camera's field of view in degrees, in first and third person
	-- (70 is Roblox's own, and the home screen's shots keep it).
	fieldOfView = steps(70, { 60, 65, 70, 75, 80, 85, 90, 95, 100, 105, 110 }),
	-- How fast the camera turns with the mouse, times the player's own
	-- Roblox camera sensitivity (Roblox doesn't let a game change that one).
	sensitivity = steps(1, { 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.3, 1.4, 1.5, 1.75, 2, 2.5, 3 }),
	-- The crosshair's size (times the usual) and colour (crosshairColors).
	crosshairSize = steps(1, { 0.75, 1, 1.25, 1.5, 2 }),
	crosshairColor = table.freeze({
		kind = "choice",
		default = "White",
		choices = table.freeze({ "White", "Green", "Yellow", "Cyan", "Pink", "Red" }),
	}) :: Setting,
} :: { [string]: Setting })

-- The crosshair's colours by name. White is the HUD's text colour, the
-- crosshair's colour before it could be picked.
SettingsConfig.crosshairColors = table.freeze({
	White = Color3.fromRGB(245, 242, 250),
	Green = Color3.fromRGB(120, 255, 90),
	Yellow = Color3.fromRGB(255, 225, 60),
	Cyan = Color3.fromRGB(70, 225, 255),
	Pink = Color3.fromRGB(255, 110, 215),
	Red = Color3.fromRGB(255, 75, 75),
})

-- How many choices this build has (the most one save can carry).
local count = 0
for _ in SettingsConfig.settings do
	count += 1
end
SettingsConfig.COUNT = count
-- A saved Settings table keeps at most this many entries, and names and
-- text no longer than MAX_TEXT: room for a newer build's choices.
SettingsConfig.MAX_SAVED = 64
SettingsConfig.MAX_TEXT = 40

-- `value` as setting `key` keeps it (a step exactly as listed), or nil if
-- `key` isn't a setting or can't have that value.
function SettingsConfig.check(key: unknown, value: unknown): any
	local setting = if type(key) == "string" then SettingsConfig.settings[key] else nil
	if not setting then
		return nil
	elseif setting.kind == "toggle" then
		return if type(value) == "boolean" then value else nil
	elseif setting.kind == "choice" then
		return if type(value) == "string" and table.find(setting.choices :: { string }, value) then value else nil
	end
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	for _, step in setting.steps :: { number } do
		if math.abs(step - value) < 1e-6 then
			return step
		end
	end
	return nil
end

-- A save from a client: only settings this build has, each with a value it
-- can take. Anything else and the whole save is refused (nil).
function SettingsConfig.clean(payload: unknown): { [string]: any }?
	if type(payload) ~= "table" then
		return nil
	end
	local clean = {}
	local entries = 0
	for key, value in payload :: { [any]: any } do
		entries += 1
		local checked = SettingsConfig.check(key, value)
		if entries > SettingsConfig.COUNT or checked == nil then
			return nil
		end
		clean[key] = checked
	end
	return clean
end

-- The choices in a saved Settings table that this build can use, checked.
function SettingsConfig.known(saved: unknown): { [string]: any }
	local known = {}
	if type(saved) == "table" then
		for key in SettingsConfig.settings do
			local value = SettingsConfig.check(key, (saved :: any)[key])
			if value ~= nil then
				known[key] = value
			end
		end
	end
	return known
end

-- A saved Settings table as it's loaded: this build's choices checked (a
-- damaged one is dropped, back to its default), anything else (a newer
-- build's choice) kept as it was if it's a plain value, so going back a
-- version and forward again loses nothing.
function SettingsConfig.tidy(saved: unknown): { [string]: any }
	local tidy = {}
	if type(saved) ~= "table" then
		return tidy
	end
	local entries = 0
	for key, value in saved :: { [any]: any } do
		if type(key) ~= "string" or #key > SettingsConfig.MAX_TEXT then
			continue
		end
		local keep = nil
		if SettingsConfig.settings[key] then
			keep = SettingsConfig.check(key, value)
		elseif
			type(value) == "boolean"
			or (type(value) == "number" and value == value and math.abs(value) ~= math.huge)
			or (type(value) == "string" and #value <= SettingsConfig.MAX_TEXT)
		then
			keep = value
		end
		if keep ~= nil then
			entries += 1
			if entries > SettingsConfig.MAX_SAVED then
				break
			end
			tidy[key] = keep
		end
	end
	return tidy
end

-- The value `by` steps (-1 or +1) on from `current` for a steps or choice
-- setting: steps stop at the ends of the list, choices go round.
function SettingsConfig.step(key: string, current: any, by: number): any
	local setting = SettingsConfig.settings[key]
	if setting.kind == "choice" then
		local choices = setting.choices :: { string }
		local index = table.find(choices, current) or 1
		return choices[(index - 1 + by) % #choices + 1]
	end
	local list = setting.steps :: { number }
	-- From the nearest step, should `current` be between two.
	local index, best = 1, math.huge
	for i, step in list do
		local gap = math.abs(step - (tonumber(current) or setting.default))
		if gap < best then
			index, best = i, gap
		end
	end
	return list[math.clamp(index + by, 1, #list)]
end

return table.freeze(SettingsConfig)
