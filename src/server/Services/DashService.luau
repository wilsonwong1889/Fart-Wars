-- Fart Dash (Shift), by its AbilityConfig entry. The client moves its own
-- avatar, as Roblox characters are client-driven, and tells the server
-- (FartDash, with the direction). The server checks the player's state,
-- that they aren't exploding, and the cooldown. For `checkSeconds` it
-- follows the avatar (its middle, every frame), then checks that it
-- didn't travel further than a dash plus walking allows, or through one
-- of the map's walls, and puts back one that did (a wall is flagged for
-- review too). A fair dash isn't taken for a wall: the path is judged as
-- walked, so going round a corner, along a wall, up onto something or off
-- a ledge is fine, and a gap in the server's view of it (lag) is filled
-- by the shortest way round (see clippedThrough). Refused dashes are
-- logged. The cooldown resets with each life. Everyone else sees the
-- trail:
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
-- The check's own measures. A move shorter than SAMPLE_STUDS isn't a new
-- point on the path. Going round a wall, an avatar's middle stays at
-- least CLEARANCE studs from it. The travel allowance grows with the
-- player's ping (the server's view of an avatar is that far behind, at
-- either end of the check), up to MAX_LAG_SECONDS.
local SAMPLE_STUDS = 0.5
local CLEARANCE = 1
local MAX_LAG_SECONDS = 0.5

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

local function level(point: Vector3, height: number): Vector3
	return Vector3.new(point.X, height, point.Z)
end

-- Rays that only meet the map's walls an avatar can't walk through.
local function wallRays(): RaycastParams?
	local map = MapService.current()
	local walls = map and map:FindFirstChild("Walls")
	if not walls then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { walls }
	params.RespectCanCollide = true
	return params
end

-- The wall a level move at `height` from `from` to `to` runs into, unless
-- the same move `jump` studs higher clears it (a wall low enough to jump).
local function blocking(params: RaycastParams, from: Vector3, to: Vector3, height: number, jump: number): BasePart?
	local a, b = level(from, height), level(to, height)
	if (b - a).Magnitude < 0.1 then
		return nil
	end
	local hit = workspace:Raycast(a, b - a, params)
	if not hit then
		return nil
	end
	if jump > 0 and not workspace:Raycast(a + Vector3.new(0, jump, 0), b - a, params) then
		return nil
	end
	return hit.Instance :: BasePart
end

-- The points an avatar's middle passes going round `wall` (CLEARANCE out
-- from each corner), at `height`, in order round it. An upright wall's own
-- corners; anything tilted, the corners of the box it fits in.
local function cornersOf(wall: BasePart, height: number): { Vector3 }
	local frame, half = wall.CFrame, wall.Size / 2
	local corners = {}
	if math.abs(frame.UpVector.Y) > 0.99 then
		local right = horizontal(frame.RightVector).Unit * (half.X + CLEARANCE)
		local back = horizontal(frame.LookVector).Unit * (half.Z + CLEARANCE)
		for _, sign in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			table.insert(corners, level(frame.Position + right * sign[1] + back * sign[2], height))
		end
		return corners
	end
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local point = frame:PointToWorldSpace(half * Vector3.new(x, y, z))
				lo, hi = lo:Min(point), hi:Max(point)
			end
		end
	end
	lo -= Vector3.new(CLEARANCE, 0, CLEARANCE)
	hi += Vector3.new(CLEARANCE, 0, CLEARANCE)
	for _, corner in { { lo.X, lo.Z }, { hi.X, lo.Z }, { hi.X, hi.Z }, { lo.X, hi.Z } } do
		table.insert(corners, Vector3.new(corner[1], height, corner[2]))
	end
	return corners
end

local function routeLength(from: Vector3, via: { Vector3 }, to: Vector3): number
	local length, last = 0, from
	for _, point in via do
		length += horizontal(point - last).Magnitude
		last = point
	end
	return length + horizontal(to - last).Magnitude
end

-- How long the shortest clear way from `from` to `to` round `wall` is
-- (past one of its corners, or two neighbouring ones), at `height`, if
-- there's one no longer than `budget` studs; nil if not.
local function around(params: RaycastParams, wall: BasePart, from: Vector3, to: Vector3, height: number, jump: number, budget: number): number?
	local corners = cornersOf(wall, height)
	local routes = {}
	for i, corner in corners do
		local nextCorner = corners[i % #corners + 1]
		for _, via in { { corner }, { corner, nextCorner }, { nextCorner, corner } } do
			table.insert(routes, { via = via, length = routeLength(from, via, to) })
		end
	end
	table.sort(routes, function(a, b)
		return a.length < b.length
	end)
	for _, route in routes do
		if route.length > budget then
			return nil
		end
		local clear, last = true, from
		for _, point in route.via do
			if blocking(params, last, point, height, jump) then
				clear = false
				break
			end
			last = point
		end
		if clear and not blocking(params, last, to, height, jump) then
			return route.length
		end
	end
	return nil
end

-- The wall standing between two points, or nil. The move is tested level
-- at the higher point's height (so stepping up onto something or off a
-- ledge is a move over what's below), and walls an avatar can walk
-- through (CanCollide off) or jump over (`jump` studs) don't count.
function DashService.throughWall(from: Vector3, to: Vector3, jump: number?): BasePart?
	local params = wallRays()
	if not params then
		return nil
	end
	return blocking(params, from, to, math.max(from.Y, to.Y), jump or 0)
end

-- The wall an avatar went through on its way along `path` (its middle,
-- oldest first), or nil. Only a path with a wall between its ends can
-- have gone through one; then each step is tested as throughWall tests a
-- move (never higher than a jump above both ends, so going over a wall
-- the avatar couldn't have jumped is still through it), and a step that
-- runs into a wall is fine if going round it (one corner, or both at an
-- end) keeps the whole path within `allowance` studs along the ground:
-- the server's view of an avatar comes in steps, and under lag a step can
-- cut a corner the avatar really walked round.
function DashService.clippedThrough(path: { Vector3 }, allowance: number, jump: number?): BasePart?
	local params = wallRays()
	if not params or #path < 2 then
		return nil
	end
	local leap = jump or 0
	local first, last = path[1], path[#path]
	local ceiling = math.max(first.Y, last.Y) + leap
	if not blocking(params, first, last, math.max(first.Y, last.Y), leap) then
		return nil
	end
	local rest = 0
	for i = 1, #path - 1 do
		rest += horizontal(path[i + 1] - path[i]).Magnitude
	end
	local walked = 0
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local step = horizontal(b - a).Magnitude
		rest -= step
		local height = math.min(math.max(a.Y, b.Y), ceiling)
		local wall = blocking(params, a, b, height, leap)
		if wall then
			local detour = around(params, wall, a, b, height, leap, allowance - walked - rest)
			if not detour then
				return wall
			end
			walked += detour
		else
			walked += step
		end
	end
	return nil
end

-- The player's network ping in seconds (nil if Roblox can't say).
-- Replaceable in tests.
DashService.pingOf = function(player: Player): number?
	local ok, ping = pcall(player.GetNetworkPing, player)
	return if ok and type(ping) == "number" then ping else nil
end

-- How far along the ground an avatar can get between a dash and its
-- check: the dash, walking the rest of the time, and walking for as long
-- as the server's view of it can be behind (its ping, up to
-- MAX_LAG_SECONDS).
function DashService.allowance(player: Player): number
	local lag = math.clamp(DashService.pingOf(player) or 0, 0, MAX_LAG_SECONDS)
	return MAX_TRAVEL + GameConfig.WALK_SPEED * (CHECK_SECONDS + lag)
end

-- How high the avatar's jump goes.
local function jumpOf(humanoid: Humanoid): number
	if humanoid.UseJumpPower then
		return humanoid.JumpPower ^ 2 / (2 * workspace.Gravity)
	end
	return humanoid.JumpHeight
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
	task.spawn(function()
		-- Follow the avatar until the check (a respawn or a death ends it).
		local path = { start.Position }
		local checkAt = now() + CHECK_SECONDS
		repeat
			task.wait()
			if player.Character ~= character or not root.Parent or humanoid.Health <= 0 then
				return
			end
			local here = root.Position
			if (here - path[#path]).Magnitude >= SAMPLE_STUDS then
				table.insert(path, here)
			end
		until now() >= checkAt
		local finish = root.Position
		if finish ~= path[#path] then
			table.insert(path, finish)
		end
		local travelled = horizontal(finish - start.Position).Magnitude
		local allowed = DashService.allowance(player)
		if travelled > allowed then
			reject(player, "tooFar")
			character:PivotTo(start)
			return
		end
		local wall = DashService.clippedThrough(path, allowed, jumpOf(humanoid))
		if wall then
			reject(player, "throughWall")
			Telemetry.flag(player, "dashThroughWall", `{wall.Name}, {math.floor(travelled + 0.5)} studs`)
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

-- Bots (BotBrain) dash here, on a player's rules: alive, not exploding,
-- the same cooldown (fresh with each life). The server moves bots, so it
-- pushes the avatar the way a client pushes its own; everyone sees the
-- trail ("dash", with the bot's id), and `checkSeconds` later the same
-- check puts back one that went too far or through a wall. Returns
-- whether it dashed.
local BotService = require(script.Parent.BotService)
local botCadences: { [Model]: Cadence.State } = setmetatable({}, { __mode = "k" }) :: any

function DashService.dashAsBot(bot: BotService.Bot, direction: Vector3): boolean
	if not FeatureFlags.FART_DASH or typeof(direction) ~= "Vector3" then
		return false
	end
	local flat = horizontal(direction)
	local character = bot.character
	local root = BotService.rootOf(bot)
	if flat.Magnitude < 0.01 or flat.Magnitude ~= flat.Magnitude or not (character and root) then
		return false
	end
	if (DASH.blockedWhileExploding and BotService.isExploding(bot))
		or (not DASH.allowedWhileProtected and BotService.isProtected(bot))
	then
		return false
	end
	local cadence = botCadences[character] or Cadence.new()
	botCadences[character] = cadence
	local slack = math.max(DASH.cooldownSeconds * (1 - GameConfig.FIRE_INTERVAL_TOLERANCE), GameConfig.FIRE_SLACK_SECONDS)
	if not Cadence.take(cadence, DASH.cooldownSeconds, slack, now()) then
		Telemetry.count("Dash.botCooldown")
		return false
	end
	Telemetry.count("Dash.botDashes")
	local unit = flat.Unit
	local start = root.CFrame
	local attachment = Instance.new("Attachment")
	attachment.Name = "FartDashAttachment"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Name = "FartDash"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	push.LineDirection = unit
	push.LineVelocity = DASH.speed :: number
	push.MaxForce = math.huge
	push.Parent = root
	task.delay(DASH.durationSeconds, function()
		push:Destroy()
		attachment:Destroy()
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatEvent = remotes:WaitForChild("CombatEvent") :: RemoteEvent
	combatEvent:FireAllClients({ kind = "dash", player = bot.id, from = start.Position, direction = unit })
	task.delay(CHECK_SECONDS, function()
		if bot.character ~= character or not root.Parent then
			return
		end
		local travelled = horizontal(root.Position - start.Position).Magnitude
		if travelled > MAX_TRAVEL + GameConfig.WALK_SPEED * CHECK_SECONDS then
			Telemetry.count("Dash.botTooFar")
			character:PivotTo(start)
		elseif DashService.throughWall(start.Position, root.Position) then
			Telemetry.count("Dash.botThroughWall")
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
		cadences[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		cadences[player] = nil
	end)
end

return DashService
