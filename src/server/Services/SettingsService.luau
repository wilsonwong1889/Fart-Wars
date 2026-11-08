-- The Settings screen's choices, kept in the player's profile (the
-- Settings field, DataService), through one RemoteFunction:
--   SettingsRequest:InvokeServer("get")            the saved choices
--   SettingsRequest:InvokeServer("save", choices)  { [name]: value }
-- returns { ok, reason } (and `settings` for "get"). A save carries the
-- choices the player has picked, and every one is checked against
-- SettingsConfig: an unknown name, a wrong type or a value the screen
-- can't make refuses the whole save. A save adds to what's saved (a choice
-- is never un-picked), at most one every SAVE_GAP seconds per player, and
-- goes to the DataStore with the rest of the profile (the autosave, or
-- leaving). Off with FeatureFlags.SAVED_SETTINGS.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.SettingsConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local RateLimit = require(Server.RateLimit)
local DataService = require(script.Parent.DataService)

local SettingsService = {}

-- The least time between two saves (or two gets) from one player. The
-- client waits longer than this after a change before it saves.
SettingsService.SAVE_GAP = 1

export type Result = { ok: boolean, reason: string, settings: { [string]: any }? }

local limiter = RateLimit.new(SettingsService.SAVE_GAP)
local started = false

local function result(ok: boolean, reason: string): Result
	if not ok then
		Telemetry.count(`Settings.refused.{reason}`)
	end
	return { ok = ok, reason = reason }
end

-- The choices `player` has saved, checked (nil until their profile loads).
function SettingsService.get(player: Player): { [string]: any }?
	local profile = DataService.get(player)
	return if profile then SettingsConfig.known(profile.data.Settings) else nil
end

-- One request from a client, checked and answered.
function SettingsService.request(player: Player, action: unknown, payload: unknown): Result
	local choices = nil
	if action == "save" then
		choices = SettingsConfig.clean(payload)
	end
	if not (action == "get" or choices) then
		Telemetry.reject("SettingsRequest", player, "badPayload")
		return result(false, "badPayload")
	end
	if not FeatureFlags.SAVED_SETTINGS then
		return result(false, "off")
	end
	if not limiter:allow(player, action :: string) then
		Telemetry.reject("SettingsRequest", player, "rateLimited")
		return result(false, "rateLimited")
	end
	if not DataService.isLoaded(player) then
		return result(false, "loading")
	end
	if action == "get" then
		local answer = result(true, "loaded")
		answer.settings = SettingsService.get(player)
		return answer
	end
	DataService.update(player, function(data)
		for key, value in choices :: { [string]: any } do
			data.Settings[key] = value
		end
	end)
	Telemetry.count("Settings.saves")
	return result(true, "saved")
end

function SettingsService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local settingsRequest = remotes:WaitForChild("SettingsRequest") :: RemoteFunction
	settingsRequest.OnServerInvoke = function(player, action, payload)
		Telemetry.count("remote.in.SettingsRequest")
		return SettingsService.request(player, action, payload)
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
end

return SettingsService
