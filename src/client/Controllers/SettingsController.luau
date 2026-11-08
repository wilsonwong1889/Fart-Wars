-- Keeps the Settings screen's choices in the player's profile, so they're
-- back next visit (SettingsService on the server, SettingsRequest):
--   * on joining, once the profile has loaded (the DataStatus attribute),
--     the saved choices are fetched and put into Settings, with their
--     effects (low detail, HUD size; the camera, crosshair and sounds read
--     Settings themselves every time)
--   * a choice made on the Settings screen (choose) is saved SAVE_DELAY
--     seconds after the last change, with every choice the player has
--     picked; a save the server turned away as too soon, or one that got
--     lost, is tried again
--   * a choice made before the saved ones arrive wins over the saved one,
--     and goes in the next save
-- Only picked choices are saved, so the rest stay at their defaults. On a
-- profile that isn't saving (DataStatus "unsaved"), or with
-- FeatureFlags.SAVED_SETTINGS off, choices last the session.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.SettingsConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Signal = require(Shared.Signal)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Settings = require(Client.Settings)
local Detail = require(Client.Detail)
local UI = require(Client.UI)

local SettingsController = {}

-- Seconds after the last change before saving (longer than the server's
-- SettingsService.SAVE_GAP, so it never turns an honest client away), and
-- between asks while the profile is still loading.
SettingsController.SAVE_DELAY = 1.5
SettingsController.RETRY_SECONDS = 1.5
-- How long to wait for the profile before giving up for the session.
SettingsController.LOAD_WAIT_SECONDS = 120
-- Tries at a save the server didn't take before waiting for the next change.
SettingsController.SAVE_TRIES = 3

-- "loading" until the saved choices are in; then "saving" (choices save),
-- "unsaved" (the profile isn't saving), "failed" (they couldn't be
-- fetched) or "off" (the flag): in those three, choices last the session.
SettingsController.state = "loading"
-- (state): the saved choices are in Settings, or the load gave up.
SettingsController.Loaded = Signal.new()

local started = false
-- Picked choices not saved yet, the latest change, a save waiting to go,
-- and how many times in a row the server didn't take one.
local dirty = false
local lastChange = 0
local waiting = false
local tries = 0
-- Bumped by every load and reset, so an older load stops.
local loads = 0

local function remote(): RemoteFunction
	return ClientState.remote("SettingsRequest") :: RemoteFunction
end

-- What the game doesn't read from Settings each time: low detail's
-- shadows and the HUD's size.
function SettingsController.apply()
	Detail.apply()
	UI.applyScale()
end

-- Every choice the player has picked, as SettingsConfig keeps it.
function SettingsController.choices(): { [string]: any }
	local picked = {}
	for key in SettingsConfig.settings do
		if Settings.chosen[key] then
			local value = SettingsConfig.check(key, (Settings :: any)[key])
			if value ~= nil then
				picked[key] = value
			end
		end
	end
	return picked
end

local schedule: () -> ()

-- Sends the picked choices now, if any are new and the profile saves.
-- Returns whether the server took them.
function SettingsController.save(): boolean
	if not dirty or SettingsController.state ~= "saving" then
		return false
	end
	dirty = false
	local request = remote()
	local ok, answer = pcall(request.InvokeServer, request, "save", SettingsController.choices())
	if ok and type(answer) == "table" and answer.ok == true then
		tries = 0
		return true
	end
	-- Too soon, or lost on the way: again shortly. Anything else won't get
	-- better by asking again.
	local again = not ok or (type(answer) == "table" and answer.reason == "rateLimited")
	if again and tries < SettingsController.SAVE_TRIES then
		tries += 1
		dirty = true
		lastChange = os.clock()
		schedule()
	end
	return false
end

-- A save SAVE_DELAY seconds after the latest change.
schedule = function()
	if waiting then
		return
	end
	waiting = true
	task.spawn(function()
		while os.clock() < lastChange + SettingsController.SAVE_DELAY do
			task.wait(lastChange + SettingsController.SAVE_DELAY - os.clock())
		end
		waiting = false
		SettingsController.save()
	end)
end

-- The player picks `value` for `key` on the Settings screen: it's theirs
-- now (a default no longer changes it), and it's saved shortly.
function SettingsController.choose(key: string, value: any)
	(Settings :: any)[key] = value
	Settings.chosen[key] = true
	if SettingsConfig.settings[key] then
		dirty = true
		tries = 0
		lastChange = os.clock()
		if SettingsController.state == "saving" then
			schedule()
		end
	end
end

-- The saved choices into Settings, except any picked already this visit.
local function take(saved: { [string]: any })
	for key, value in SettingsConfig.known(saved) do
		if not Settings.chosen[key] then
			(Settings :: any)[key] = value
			Settings.chosen[key] = true
		end
	end
	SettingsController.apply()
end

-- Fetches the saved choices once the profile has loaded, and puts them
-- into Settings. Returns whether they came.
function SettingsController.load(): boolean
	loads += 1
	local token = loads
	SettingsController.state = "loading"
	local player = Players.LocalPlayer
	local request = remote()
	local deadline = os.clock() + SettingsController.LOAD_WAIT_SECONDS
	local state = "failed"
	while os.clock() < deadline do
		local status = player:GetAttribute("DataStatus")
		if status == "ready" or status == "unsaved" then
			local ok, answer = pcall(request.InvokeServer, request, "get")
			if token ~= loads then
				return false
			end
			local reason = if ok and type(answer) == "table" then answer.reason else nil
			if ok and type(answer) == "table" and answer.ok == true and type(answer.settings) == "table" then
				take(answer.settings)
				state = if status == "ready" then "saving" else "unsaved"
				break
			elseif reason ~= "loading" and reason ~= "rateLimited" then
				state = if reason == "off" then "off" else "failed"
				break
			end
			task.wait(SettingsController.RETRY_SECONDS)
		else
			task.wait(0.25)
		end
		if token ~= loads then
			return false
		end
	end
	SettingsController.state = state
	SettingsController.Loaded:Fire(state)
	-- Choices picked while they loaded.
	if dirty and state == "saving" then
		schedule()
	end
	return state == "saving" or state == "unsaved"
end

-- A line for the Settings screen: whether its choices stick.
function SettingsController.note(): string
	local state = SettingsController.state
	if state == "saving" then
		return "💾 Saved to your profile: your settings stick around like a bad smell."
	elseif state == "loading" then
		return "Sniffing out your saved settings..."
	elseif state == "unsaved" then
		return "Progress isn't saving this session, so these settings won't stick."
	elseif state == "failed" then
		return "Couldn't load your saved settings, so these last this session."
	end
	return ""
end

-- Specs only: every choice back to its default, none picked, nothing
-- waiting to save, and not loaded (as on joining).
function SettingsController.reset()
	loads += 1
	for key, setting in SettingsConfig.settings do
		(Settings :: any)[key] = setting.default
	end
	table.clear(Settings.chosen)
	dirty, tries = false, 0
	SettingsController.state = "loading"
	SettingsController.apply()
end

function SettingsController.start()
	if started then
		return
	end
	started = true
	if not FeatureFlags.SAVED_SETTINGS then
		SettingsController.state = "off"
		return
	end
	task.spawn(SettingsController.load)
end

return SettingsController
