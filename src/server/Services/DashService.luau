-- Fart Dash (Shift), by its AbilityConfig entry. The client moves its own
-- avatar, as Roblox characters are client-driven, and tells the server
-- (FartDash, with the direction). The server checks the player's state,
-- that they aren't exploding, and the cooldown; `checkSeconds` later it
-- checks that the avatar didn't travel further than a dash plus walking
-- allows, or through one of the map's walls, and puts back one that did
-- (a wall is flagged for review too). Refused dashes are logged. The
-- cooldown resets with each life. Everyone else sees the trail:
--   CombatEvent { kind = "dash", player, from, direction }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Cadence = require(Server.Cadence)
local MapService = require(script.Parent.MapService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)
local GasService = require(script.Parent.GasService)

local DASH = AbilityConfig.FartDash
local CHECK_SECONDS = DASH.checkSeconds :: number
local MAX_TRAVEL = DASH.maxTravelStuds :: number

local DashService = {}

-- (player): a Fart Dash the server accepted.
DashService.Dashed = Signal.new()

local cadences: { [Player]: Cadence.State } = {}
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

-- Whether one of the map's walls stands between two points.
function DashService.throughWall(from: Vector3, to: Vector3): boolean
	local map = MapService.current()
	local walls = map and map:FindFirstChild("Walls")
	if not walls or (to - from).Magnitude < 0.1 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { walls }
	return workspace:Raycast(from, to - from, params) ~= nil
end

function DashService.dash(player: Player, direction: unknown): boolean
	if not FeatureFlags.FART_DASH then
		reject(player, "disabled")
		return false
	end
	local aim = if typeof(direction) == "Vector3" then direction :: Vector3 else nil
	if not aim or aim.Magnitude ~= aim.Magnitude or aim.Magnitude > 1e3 then
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
	local cadence = cadences[player] or Cadence.new()
	cadences[player] = cadence
	local slack = math.max(DASH.cooldownSeconds * (1 - GameConfig.FIRE_INTERVAL_TOLERANCE), GameConfig.FIRE_SLACK_SECONDS)
	if not Cadence.take(cadence, DASH.cooldownSeconds, slack, at) then
		reject(player, "cooldown")
		return false
	end
	AFKService.markActive(player)
	Telemetry.count("Dash.dashes")
	DashService.Dashed:Fire(player)

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
		elseif DashService.throughWall(start.Position, root.Position) then
			reject(player, "throughWall")
			Telemetry.flag(player, "dashThroughWall")
			character:PivotTo(start)
		end
	end)
	return true
end

-- A Fart Dash ready again at once (Bean Rain's beans), on the server and
-- on the player's own screen.
function DashService.refill(player: Player)
	cadences[player] = nil
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatEvent = remotes:WaitForChild("CombatEvent") :: RemoteEvent
	combatEvent:FireClient(player, { kind = "dashRefill" })
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
		cadences[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		cadences[player] = nil
	end)
end

return DashService
