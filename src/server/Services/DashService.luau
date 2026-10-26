-- Fart Dash (Shift), by its AbilityConfig entry. The client moves its own
-- avatar, as Roblox characters are client-driven, and tells the server
-- (FartDash, with the direction). The server checks the player's state,
-- that they aren't exploding, and the cooldown; `checkSeconds` later it
-- checks that the avatar didn't travel further than a dash plus walking
-- allows, and puts back one that did. Refused dashes are logged. The
-- cooldown resets with each life. Everyone else sees the trail:
--   CombatEvent { kind = "dash", player, from, direction }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)
local GasService = require(script.Parent.GasService)

local DASH = AbilityConfig.FartDash
local CHECK_SECONDS = DASH.checkSeconds :: number
local MAX_TRAVEL = DASH.maxTravelStuds :: number

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
	local aim = if typeof(direction) == "Vector3" then direction :: Vector3 else nil
	if not aim or aim.Magnitude ~= aim.Magnitude then
		reject(player, "badPayload")
		return false
	end
	if not table.find(DASH.allowedStates, PlayerLifecycleService.stateOf(player) or "") then
		reject(player, "notActive")
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		reject(player, "dead")
		return false
	end
	if (DASH.blockedWhileExploding and GasService.isExploding(player))
		or (not DASH.allowedWhileProtected and PlayerLifecycleService.isProtected(player))
	then
		reject(player, "prohibited")
		return false
	end
	local at = now()
	local previous = lastDash[player]
	if previous and at - previous < DASH.cooldownSeconds * GameConfig.FIRE_INTERVAL_TOLERANCE then
		reject(player, "cooldown")
		return false
	end
	lastDash[player] = at
	AFKService.markActive(player)
	Telemetry.count("Dash.dashes")

	local start = root.CFrame
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatEvent = remotes:WaitForChild("CombatEvent") :: RemoteEvent
	local flat = horizontal(aim)
	combatEvent:FireAllClients({
		kind = "dash",
		player = player.UserId,
		from = start.Position,
		direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero,
	})
	task.delay(CHECK_SECONDS, function()
		if player.Character ~= character or not root.Parent then
			return
		end
		local travelled = horizontal(root.Position - start.Position).Magnitude
		local allowed = MAX_TRAVEL + GameConfig.WALK_SPEED * CHECK_SECONDS
		if travelled > allowed then
			reject(player, "tooFar")
			character:PivotTo(start)
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
