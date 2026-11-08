-- Pings (FeatureFlags.COMPASS): a player marks a spot (Z, or the middle
-- mouse button, on the crosshair) and their team sees it for a few
-- seconds, with a sound. Team-only: it goes to the pinger's teammates (and
-- back to the pinger), never to the other team or to spectators. The
-- client only says where; the server checks that it's a real spot inside
-- the map, that the pinger is in the match on a team, and that they aren't
-- pinging faster than CompassConfig.ping allows. Refusals are logged like
-- every other remote's.
--   Ping (client -> server)   position: Vector3
--   Ping (server -> team)     { from = userId, position, endsAt (server time) }
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CompassConfig = require(Shared.Config.CompassConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local RateLimit = require(Server.RateLimit)
local MapService = require(script.Parent.MapService)
local TeamService = require(script.Parent.TeamService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local PING = CompassConfig.ping

local PingService = {}

local limiter = RateLimit.new(PING.cooldownSeconds - PING.slackSeconds)
local started = false

local function remote(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ping") :: RemoteEvent
end

local function finite(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

-- Whether `position` is inside the current map's bounds (give or take the
-- margin).
function PingService.inMap(position: Vector3): boolean
	local _, entry = MapService.current()
	if not entry then
		return false
	end
	local half = entry.bounds.size / 2 + Vector3.one * PING.boundsMargin
	local offset = position - entry.bounds.center
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- A ping at `position` from `player`: true if their team was told, false
-- (and the reason logged) if it was refused.
function PingService.ping(player: Player, position: unknown): boolean
	local function refuse(reason: string): boolean
		Telemetry.reject("Ping", player, reason)
		return false
	end
	if typeof(position) ~= "Vector3" or not finite(position :: Vector3) then
		return refuse("badPayload")
	end
	local spot = position :: Vector3
	local team = TeamService.teamOf(player)
	if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE or not team then
		return refuse("notActive")
	end
	if not PingService.inMap(spot) then
		return refuse("outOfBounds")
	end
	-- Only well-formed pings count toward the limit.
	if not limiter:allow(player, "ping") then
		return refuse("rateLimited")
	end
	local payload = { from = player.UserId, position = spot, endsAt = workspace:GetServerTimeNow() + PING.seconds }
	local event = remote()
	local told = 0
	for _, member in TeamService.members(team :: string) do
		event:FireClient(member, payload)
		told += 1
	end
	Telemetry.count("Ping.sent")
	Telemetry.count("Ping.told", told)
	return true
end

function PingService.start()
	if started or not FeatureFlags.COMPASS then
		return
	end
	started = true
	remote().OnServerEvent:Connect(Telemetry.guard("Ping", function(player, position)
		PingService.ping(player, position)
	end))
end

return PingService
