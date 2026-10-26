-- Fart Dash (Shift). The client moves its own avatar, as Roblox characters
-- are client-driven, and tells the server (FartDash, with the direction).
-- The server checks the cooldown, and CHECK_SECONDS later that the avatar
-- didn't travel further than a dash plus walking allows; one that did is
-- put back where it started. Too-early dashes are refused and logged. The
-- cooldown resets with each life.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)

local DASH = GameConfig.FART_DASH

local DashService = {}

local lastDash: { [Player]: number } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function reject(player: Player, reason: string)
	Telemetry.reject("FartDash", player, reason)
end

local function horizontal(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function DashService.dash(player: Player, direction: unknown): boolean
	if not FeatureFlags.FART_DASH then
		reject(player, "disabled")
		return false
	end
	if typeof(direction) ~= "Vector3" or (direction :: Vector3).Magnitude ~= (direction :: Vector3).Magnitude then
		reject(player, "badPayload")
		return false
	end
	if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE then
		reject(player, "notActive")
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		reject(player, "dead")
		return false
	end
	local at = now()
	local previous = lastDash[player]
	if previous and at - previous < DASH.COOLDOWN_SECONDS * GameConfig.FIRE_INTERVAL_TOLERANCE then
		reject(player, "cooldown")
		return false
	end
	lastDash[player] = at
	AFKService.markActive(player)
	Telemetry.count("Dash.dashes")

	local start = root.CFrame
	local life = character
	task.delay(DASH.CHECK_SECONDS, function()
		if player.Character ~= life or not root.Parent then
			return
		end
		local travelled = horizontal(root.Position - start.Position).Magnitude
		local allowed = DASH.MAX_TRAVEL_STUDS + GameConfig.WALK_SPEED * DASH.CHECK_SECONDS
		if travelled > allowed then
			reject(player, "tooFar")
			life:PivotTo(start)
		end
	end)
	return true
end

function DashService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fartDash = remotes:WaitForChild("FartDash") :: RemoteEvent
	fartDash.OnServerEvent:Connect(Telemetry.guard("Dash", DashService.dash))
	PlayerLifecycleService.Died:Connect(function(player)
		lastDash[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastDash[player] = nil
	end)
end

return DashService
