-- One bot's mind for one life. BotDirector makes a new one for every
-- spawn and ticks it a few times a second (BotConfig.THINK_SECONDS); a
-- tick never yields (paths are worked out on their own thread). Each tick:
--   * Looking: it keeps an eye on the enemy it's fighting (one ray from its
--     head) and, a few times a second, looks around for a nearer one: a
--     player who's playing, alive, not spawn-protected and not already
--     blowing up, or an enemy bot the same, within its sight range and in
--     front of it (all the way round for a moment after taking gas), with
--     a clear line from its head. A few rays at most each time.
--   * Fighting (only while a round is ACTIVE): it waits its reaction time
--     after first seeing a target, turns to face it and fires the Gas
--     Blaster (CombatService.fireAsBot) at the upper body, or now and then
--     the head, through an error cone that's wider the faster the target
--     crosses its view, the farther away it is, in the first moment of
--     aiming and in mid-air; never faster than the weapon's interval times
--     its multiplier. Meanwhile it strafes, now and then jumps, closes in
--     on far targets and backs up from close ones.
--   * Backing off: at high gas it heads back to its own spawn, still
--     shooting at anyone in sight, until it has recovered.
--   * Getting about: with nobody to fight it walks a path
--     (PathfindingService) to a goal: the control zone in Gas Control
--     (holding it, not chasing out of it), else where it last saw an enemy,
--     else a patrol point in one of the lanes toward the enemy's side. It
--     plans again on a timer; stuck, it jumps, then picks somewhere else.
-- How good it is at all of this is its tuning (BotConfig.tuning).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotConfig = require(Shared.Config.BotConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local States = require(Shared.States)
local Services = script.Parent.Parent.Services
local BotService = require(Services.BotService)
local CombatService = require(Services.CombatService)
local GasService = require(Services.GasService)
local TeamService = require(Services.TeamService)
local PlayerLifecycleService = require(Services.PlayerLifecycleService)
local MapService = require(Services.MapService)
local RoundService = require(Services.RoundService)
local ZoneService = require(Services.ZoneService)

local WEAPON = WeaponConfig.weapons[BotConfig.WEAPON]
-- An R15 avatar, for paths.
local AGENT = { AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 6 }
-- Goals: how long each is worth keeping before choosing again.
local GOAL_SECONDS = { retreat = math.huge, zone = 12, chase = BotConfig.MEMORY_SECONDS, patrol = 30 }

-- An enemy worth shooting right now (a Player or a Bot), and its avatar.
type Foe = { key: any, character: Model, root: BasePart }

type Fields = {
	bot: BotService.Bot,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart,
	tuning: BotConfig.Tuning,
	rng: Random,
	rays: RaycastParams,
	stopped: boolean,
	path: Path?,
	facing: AlignOrientation?,
	-- The fight.
	target: Foe?,
	visible: boolean,
	seenAt: number,
	readyAt: number,
	lastKey: any,
	lastVisibleAt: number,
	lastSeenPosition: Vector3?,
	lastSeenAt: number,
	nextScanAt: number,
	nextShotAt: number,
	shotQueued: boolean,
	alertUntil: number,
	lastGas: number,
	retreating: boolean,
	strafeUntil: number,
	strafeSide: number,
	-- Getting about.
	goal: Vector3?,
	goalKind: string?,
	goalUntil: number,
	waypoints: { PathWaypoint },
	waypointIndex: number,
	jumpedFor: number,
	pathing: boolean,
	repathAt: number,
	moveTarget: Vector3?,
	movedAt: number,
	moving: boolean,
	stuckAt: number,
	stuckFrom: Vector3,
	stuckCount: number,
}

local BotBrain = {}
BotBrain.__index = BotBrain

export type Brain = typeof(setmetatable({} :: Fields, BotBrain))

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function velocity(part: BasePart): Vector3
	return (part.AssemblyLinearVelocity :: Vector3?) or Vector3.zero
end

local function aliveRoot(character: Model?): BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- `key` (a Player or a Bot) as a fair target for `team` now, or nil: on
-- the other team, playing, alive, not protected, not mid-countdown.
local function foe(key: any, team: string): Foe?
	if typeof(key) == "Instance" then
		local player = key :: Player
		local theirs = TeamService.teamOf(player)
		if not theirs or theirs == team or player.Parent ~= Players
			or PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE
			or PlayerLifecycleService.isProtected(player) or GasService.isExploding(player) then
			return nil
		end
		local character = player.Character
		local root = aliveRoot(character)
		return if character and root then { key = player, character = character, root = root } else nil
	end
	local bot = key :: BotService.Bot
	if bot.team == team or BotService.get(bot.id) ~= bot or BotService.isProtected(bot) or BotService.isExploding(bot) then
		return nil
	end
	local root = BotService.rootOf(bot)
	local character = bot.character
	return if character and root then { key = bot, character = character, root = root } else nil
end

-- Where to look and aim on a target: the head, or the upper body.
local function aimPart(target: Foe, head: boolean): BasePart
	local character = target.character
	local part = if head then character:FindFirstChild("Head") else character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if part and part:IsA("BasePart") then part else target.root
end

-- A direction within `degrees` of `direction`, anywhere in that cone alike.
local function spread(direction: Vector3, degrees: number, rng: Random): Vector3
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local turn = rng:NextNumber() * 2 * math.pi
	local side = direction:Cross(Vector3.yAxis)
	if side.Magnitude < 1e-3 then
		side = direction:Cross(Vector3.xAxis)
	end
	side = side.Unit
	local up = side:Cross(direction).Unit
	return (direction + (side * math.cos(turn) + up * math.sin(turn)) * math.tan(angle)).Unit
end

local function centroid(parts: { BasePart }): Vector3?
	if #parts == 0 then
		return nil
	end
	local sum = Vector3.zero
	for _, part in parts do
		sum += part.Position
	end
	return sum / #parts
end

-- Gas Control's zone while a zone mode is on, else nil.
local function activeZone(): BasePart?
	if RoundService.getMode().objective ~= "zone" then
		return nil
	end
	local zone = ZoneService.parts()
	return zone
end

-- The map's lane markers (Zones/Lane*), if it has any.
local function lanes(): { BasePart }
	local map = MapService.current()
	local zones = map and map:FindFirstChild("Zones")
	local list = {}
	if zones then
		for _, child in zones:GetChildren() do
			if child:IsA("BasePart") and string.sub(child.Name, 1, 4) == "Lane" then
				table.insert(list, child)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function BotBrain.new(bot: BotService.Bot, character: Model, tuning: BotConfig.Tuning): Brain
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = character:FindFirstChild("Head")
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	rays.FilterDescendantsInstances = { character }
	local at = now()
	local fields: Fields = {
		bot = bot,
		character = character,
		humanoid = humanoid,
		root = root,
		head = if head and head:IsA("BasePart") then head else root,
		tuning = tuning,
		rng = Random.new(),
		rays = rays,
		stopped = false,
		path = nil,
		facing = nil,
		target = nil,
		visible = false,
		seenAt = at,
		readyAt = at,
		lastKey = nil,
		lastVisibleAt = -math.huge,
		lastSeenPosition = nil,
		lastSeenAt = -math.huge,
		nextScanAt = at,
		nextShotAt = at,
		shotQueued = false,
		alertUntil = at,
		lastGas = 0,
		retreating = false,
		strafeUntil = at,
		strafeSide = 0,
		goal = nil,
		goalKind = nil,
		goalUntil = at,
		waypoints = {},
		waypointIndex = 1,
		jumpedFor = 0,
		pathing = false,
		repathAt = at,
		moveTarget = nil,
		movedAt = -math.huge,
		moving = false,
		stuckAt = at + BotConfig.STUCK_SECONDS,
		stuckFrom = root.Position,
		stuckCount = 0,
	}
	local brain = setmetatable(fields, BotBrain)
	-- Turns it smoothly to face whoever it's fighting (otherwise it faces
	-- where it walks).
	local attachment = root:FindFirstChild("RootAttachment")
	if not (attachment and attachment:IsA("Attachment")) then
		attachment = Instance.new("Attachment")
		attachment.Name = "BotFacing"
		attachment.Parent = root
	end
	local align = Instance.new("AlignOrientation")
	align.Name = "BotFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment :: Attachment
	align.Responsiveness = 25
	align.MaxTorque = math.huge
	align.Enabled = false
	align.Parent = root
	brain.facing = align
	local ok, path = pcall(function()
		return PathfindingService:CreatePath(AGENT)
	end)
	brain.path = if ok then path else nil
	return brain
end

function BotBrain.stop(self: Brain)
	if self.stopped then
		return
	end
	self.stopped = true
	self.target = nil
	if self.facing then
		self.facing:Destroy()
		self.facing = nil
	end
	if self.path then
		self.path:Destroy()
		self.path = nil
	end
	if self.character.Parent and self.humanoid.Health > 0 then
		self.humanoid.AutoRotate = true
		self.humanoid:MoveTo(self.root.Position)
	end
end

-- Looking.

-- Close enough and in front of it (or it's alert, or already fighting
-- this one). Also returns how far away.
function BotBrain.inView(self: Brain, target: Foe, at: number): (boolean, number)
	local offset = target.root.Position - self.root.Position
	local distance = offset.Magnitude
	if distance > self.tuning.sightRange then
		return false, distance
	end
	local fighting = self.target ~= nil and self.target.key == target.key
	if at >= self.alertUntil and not fighting then
		local look, toward = flat(self.root.CFrame.LookVector), flat(offset)
		if look.Magnitude > 0.01 and toward.Magnitude > 0.01 and look.Unit:Dot(toward.Unit) < math.cos(math.rad(self.tuning.viewDegrees)) then
			return false, distance
		end
	end
	return true, distance
end

-- Nothing in the way from its head to the target's upper body.
function BotBrain.clearShot(self: Brain, target: Foe): boolean
	local from = self.head.Position
	local result = workspace:Raycast(from, aimPart(target, false).Position - from, self.rays)
	return result == nil or result.Instance:IsDescendantOf(target.character)
end

function BotBrain.engage(self: Brain, target: Foe, at: number)
	-- Seen again just after losing it: no new reaction time.
	local again = target.key == self.lastKey and at - self.lastVisibleAt <= BotConfig.REACQUIRE_SECONDS
	if not again then
		self.seenAt = at
		self.readyAt = at + self.tuning.reactionSeconds * self.rng:NextNumber(0.85, 1.2)
	end
	self.target = target
	self.lastKey = target.key
	self.visible = true
	self.lastVisibleAt = at
	self.lastSeenPosition = target.root.Position
	self.lastSeenAt = at
end

function BotBrain.look(self: Brain, at: number)
	local team = self.bot.team
	local current = self.target and foe(self.target.key, team)
	self.target = current
	self.visible = false
	if current then
		if self:inView(current, at) and self:clearShot(current) then
			self.visible = true
			self.lastVisibleAt = at
			self.lastSeenPosition = current.root.Position
			self.lastSeenAt = at
		elseif at - self.lastVisibleAt > BotConfig.LOSE_SIGHT_SECONDS then
			self.target = nil
		end
	end
	if not self.target then
		-- Nobody to fight: look around now.
		self.nextScanAt = math.min(self.nextScanAt, at)
	end
	if at < self.nextScanAt then
		return
	end
	self.nextScanAt = at + BotConfig.SCAN_SECONDS
	local candidates: { { target: Foe, distance: number } } = {}
	local function consider(key: any)
		local target = foe(key, team)
		if target and not (self.target and self.target.key == key) then
			local ok, distance = self:inView(target, at)
			if ok then
				table.insert(candidates, { target = target, distance = distance })
			end
		end
	end
	for _, player in Players:GetPlayers() do
		consider(player)
	end
	for _, bot in BotService.all() do
		consider(bot)
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	-- Only worth switching for someone clearly nearer than a target in sight.
	local fighting = self.target
	local keep = if fighting and self.visible then (fighting.root.Position - self.root.Position).Magnitude * 0.7 else math.huge
	for i = 1, math.min(#candidates, BotConfig.SCAN_RAYS) do
		local candidate = candidates[i]
		if candidate.distance >= keep then
			break
		end
		if self:clearShot(candidate.target) then
			self:engage(candidate.target, at)
			return
		end
	end
end

-- Fighting.

-- Lines up the next shot when it's due before the next tick.
function BotBrain.trigger(self: Brain, at: number)
	if self.shotQueued or not (self.target and self.visible) or at < self.readyAt - BotConfig.THINK_SECONDS then
		return
	end
	local due = math.max(self.nextShotAt, self.readyAt)
	if due > at + BotConfig.THINK_SECONDS then
		return
	end
	self.shotQueued = true
	task.delay(math.max(0, due - at), function()
		self.shotQueued = false
		if not self.stopped then
			self:shoot()
		end
	end)
end

function BotBrain.shoot(self: Brain)
	local target = self.target
	if not (target and self.visible) or RoundService.phase() ~= States.Phase.ACTIVE or BotService.isExploding(self.bot) then
		return
	end
	local fresh = foe(target.key, self.bot.team)
	if not fresh then
		return
	end
	local at = now()
	local t = self.tuning
	local from = self.head.Position
	local offset = aimPart(fresh, self.rng:NextNumber() < t.headChance).Position - from
	local distance = offset.Magnitude
	if distance < 0.5 or distance > WEAPON.range then
		return
	end
	local line = offset / distance
	-- Its own movement counts too: shooting on the move is harder.
	local relative = velocity(fresh.root) - velocity(self.root)
	local sideways = (relative - line * relative:Dot(line)).Magnitude
	local cone = t.aimErrorDegrees + t.speedErrorDegrees * sideways / 16 + t.distanceErrorDegrees * distance / 100
	local settling = math.clamp(1 - (at - self.seenAt) / t.settleSeconds, 0, 1)
	cone *= 1 + BotConfig.SETTLE_EXTRA * settling
	if self.humanoid.FloorMaterial == Enum.Material.Air then
		cone *= BotConfig.AIRBORNE_ERROR
	end
	local fired = CombatService.fireAsBot(self.bot, spread(line, cone, self.rng))
	-- Timed from when the shot really went, so it's never sooner than the
	-- weapon allows however the frames fall.
	local wait = if fired then math.max(WEAPON.fireInterval + 0.02, WEAPON.fireInterval * t.fireIntervalMultiplier * self.rng:NextNumber(0.92, 1.12)) else 0.1
	self.nextShotAt = now() + wait
end

function BotBrain.face(self: Brain, point: Vector3?)
	local align = self.facing
	if not align then
		return
	end
	local direction = if point then flat(point - self.root.Position) else Vector3.zero
	if direction.Magnitude > 0.1 then
		align.CFrame = CFrame.lookAt(Vector3.zero, direction.Unit)
		align.Enabled = true
		self.humanoid.AutoRotate = false
	elseif not point and align.Enabled then
		align.Enabled = false
		self.humanoid.AutoRotate = true
	end
end

-- Something solid within a few studs that way.
function BotBrain.blocked(self: Brain, direction: Vector3): boolean
	return workspace:Raycast(self.root.Position, direction.Unit * 6, self.rays) ~= nil
end

-- Holding ground in a fight: strafing, now and then a jump, closing in on
-- a far target (not when holding the zone) and backing up from a close one.
function BotBrain.skirmish(self: Brain, at: number, dt: number, holdZone: boolean)
	local target = self.target :: Foe
	local offset = flat(target.root.Position - self.root.Position)
	local distance = offset.Magnitude
	local toward = if distance > 0.1 then offset / distance else Vector3.zAxis
	local side = Vector3.new(-toward.Z, 0, toward.X)
	if at >= self.strafeUntil then
		local seconds = BotConfig.STRAFE_SECONDS
		self.strafeUntil = at + self.rng:NextNumber(seconds[1], seconds[2])
		self.strafeSide = if self.rng:NextNumber() < self.tuning.strafeChance then (if self.rng:NextNumber() < 0.5 then -1 else 1) else 0
		if self.strafeSide ~= 0 and self:blocked(side * self.strafeSide) then
			self.strafeSide = -self.strafeSide
		end
	end
	local move = side * self.strafeSide
	if distance > BotConfig.CLOSE_IN_STUDS and not holdZone then
		move += toward
	elseif distance < BotConfig.BACK_UP_STUDS then
		move -= toward
	end
	if move.Magnitude > 0.1 then
		self.moving = true
		self.moveTarget = nil
		self.humanoid:MoveTo(self.root.Position + move.Unit * 8)
	else
		self:moveTo(self.root.Position, at)
	end
	if self.rng:NextNumber() < self.tuning.jumpsPerSecond * dt then
		self.humanoid.Jump = true
	end
end

-- Getting about.

function BotBrain.moveTo(self: Brain, point: Vector3, at: number)
	-- MoveTo gives up after 8 seconds; the same spot needn't be sent again
	-- before then.
	local last = self.moveTarget
	if last and (last - point).Magnitude < 1 and at - self.movedAt < 3 then
		return
	end
	self.moveTarget = point
	self.movedAt = at
	self.humanoid:MoveTo(point)
end

-- What to walk toward, most pressing first.
function BotBrain.wantedGoal(self: Brain, at: number): string
	if self.retreating then
		return "retreat"
	elseif activeZone() then
		return "zone"
	elseif self.lastSeenPosition and at - self.lastSeenAt < BotConfig.MEMORY_SECONDS then
		return "chase"
	end
	return "patrol"
end

-- A spot in one of the lanes, part of the way from its own spawn to the
-- enemy's (or the map's middle, on a map without lanes or spawns).
function BotBrain.patrolPoint(self: Brain): Vector3
	local team = self.bot.team
	local theirs = {}
	for _, other in TeamConfig.order do
		if other ~= team then
			for _, spawn in MapService.spawns(other) do
				table.insert(theirs, spawn)
			end
		end
	end
	local home, away = centroid(MapService.spawns(team)), centroid(theirs)
	if not (home and away) then
		local map = MapService.current()
		local middle = if map then map:GetPivot().Position else self.root.Position
		return Vector3.new(middle.X, self.root.Position.Y, middle.Z)
	end
	local along = home:Lerp(away, self.rng:NextNumber(BotConfig.PATROL_DEPTH[1], BotConfig.PATROL_DEPTH[2]))
	local axis = flat(away - home)
	local list = lanes()
	if axis.Magnitude < 1 or #list == 0 then
		return along
	end
	axis = axis.Unit
	local across = Vector3.new(-axis.Z, 0, axis.X)
	local lane = list[self.rng:NextInteger(1, #list)]
	local width = math.abs(across.X) * lane.Size.X + math.abs(across.Z) * lane.Size.Z
	return along + across * (across:Dot(lane.Position - along) + self.rng:NextNumber(-0.3, 0.3) * width)
end

function BotBrain.pickGoal(self: Brain, kind: string): Vector3
	if kind == "retreat" then
		-- Its own nearest spawn.
		local best, bestDistance = nil, math.huge
		for _, spawn in MapService.spawns(self.bot.team) do
			local distance = (spawn.Position - self.root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = spawn, distance
			end
		end
		return if best then best.Position else self:patrolPoint()
	elseif kind == "zone" then
		-- Open ground somewhere in the zone, never inside the throne.
		return ZoneService.spot(self.rng) or self:patrolPoint()
	elseif kind == "chase" and self.lastSeenPosition then
		return self.lastSeenPosition
	end
	return self:patrolPoint()
end

-- Works out a path to the goal on its own thread; until it's in (or if
-- there's none), the bot walks straight at the goal.
function BotBrain.plan(self: Brain, at: number)
	local goal = self.goal
	local path = self.path
	self.repathAt = at + (if self.goalKind == "chase" then BotConfig.CHASE_REPATH_SECONDS else BotConfig.REPATH_SECONDS)
	if self.pathing or not (goal and path) then
		return
	end
	self.pathing = true
	local from = self.root.Position
	task.spawn(function()
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		self.pathing = false
		if self.stopped or self.goal ~= goal then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			self.waypoints = path:GetWaypoints()
			-- The first waypoint is where it started.
			self.waypointIndex = 2
			self.jumpedFor = 0
		else
			-- No way there it can find: straight at it for a moment, then
			-- somewhere else.
			self.waypoints = {}
			self.goalUntil = math.min(self.goalUntil, now() + 3)
		end
	end)
end

function BotBrain.setGoal(self: Brain, kind: string, at: number)
	self.goal = self:pickGoal(kind)
	self.goalKind = kind
	self.goalUntil = at + GOAL_SECONDS[kind]
	self.waypoints = {}
	self.waypointIndex = 1
	self:plan(at)
end

-- Walks the path (or straight at the goal); false once it's there.
function BotBrain.follow(self: Brain, at: number): boolean
	local goal = self.goal
	if not goal then
		return false
	end
	local point = goal
	if #self.waypoints > 0 then
		local waypoint = self.waypoints[self.waypointIndex]
		while waypoint and flat(waypoint.Position - self.root.Position).Magnitude < BotConfig.WAYPOINT_STUDS do
			self.waypointIndex += 1
			waypoint = self.waypoints[self.waypointIndex]
		end
		if not waypoint then
			return false
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump and self.jumpedFor ~= self.waypointIndex then
			self.jumpedFor = self.waypointIndex
			self.humanoid.Jump = true
		end
		point = waypoint.Position
	elseif flat(goal - self.root.Position).Magnitude < BotConfig.WAYPOINT_STUDS then
		return false
	end
	self.moving = true
	self:moveTo(point, at)
	return true
end

function BotBrain.travel(self: Brain, at: number)
	local kind = self:wantedGoal(at)
	if not self.goal or kind ~= self.goalKind or at >= self.goalUntil then
		self:setGoal(kind, at)
	elseif kind == "chase" and self.lastSeenPosition and (self.lastSeenPosition - self.goal).Magnitude > 8 and at >= self.repathAt then
		-- It has seen them somewhere else since.
		self:setGoal(kind, at)
	elseif at >= self.repathAt then
		self:plan(at)
	end
	if not self:follow(at) then
		-- There. Backing off, it waits at its spawn; chasing, there's
		-- nothing more to see; in the zone or on patrol, another spot next
		-- tick.
		if self.goalKind == "chase" then
			self.lastSeenPosition = nil
		end
		if self.goalKind ~= "retreat" then
			self.goal = nil
		end
		self:moveTo(self.root.Position, at)
	end
end

-- Stuck: a jump first, then somewhere else to go.
function BotBrain.checkStuck(self: Brain, at: number)
	if at < self.stuckAt then
		return
	end
	if self.moving and flat(self.root.Position - self.stuckFrom).Magnitude < BotConfig.STUCK_STUDS then
		self.stuckCount += 1
		self.humanoid.Jump = true
		if self.stuckCount >= 2 then
			self.stuckCount = 0
			if self.goalKind == "chase" then
				self.lastSeenPosition = nil
			end
			self.goal = nil
			self.strafeSide = -self.strafeSide
		end
	else
		self.stuckCount = 0
	end
	self.stuckFrom = self.root.Position
	self.stuckAt = at + BotConfig.STUCK_SECONDS
end

-- Backing off at high gas, until it has recovered; taking gas also makes
-- it look all the way round for a moment.
function BotBrain.senseGas(self: Brain, at: number)
	local gas = BotService.gasOf(self.bot)
	if gas > self.lastGas then
		self.alertUntil = at + BotConfig.ALERT_SECONDS
	end
	self.lastGas = gas
	if self.retreating and gas <= BotConfig.RESUME_GAS then
		self.retreating = false
		self.goal = nil
	elseif not self.retreating and gas >= self.tuning.backOffGas then
		self.retreating = true
		self.goal = nil
	end
end

function BotBrain.tick(self: Brain, dt: number)
	if self.stopped or not (self.character.Parent and self.humanoid.Health > 0 and BotService.isAlive(self.bot)) then
		return
	end
	local at = now()
	self:senseGas(at)
	-- Between rounds nobody fights: it just walks about.
	if RoundService.phase() == States.Phase.ACTIVE then
		self:look(at)
		self:trigger(at)
	else
		self.target, self.visible = nil, false
	end
	self.moving = false
	local target = if self.visible then self.target else nil
	self:face(if target then target.root.Position else nil)
	local zone = activeZone()
	if target and not self.retreating and not (zone and not ZoneService.inside(self.root.Position, zone)) then
		self:skirmish(at, dt, zone ~= nil)
	else
		-- Backing off, or on the way to the zone, it still faces (and shoots
		-- at) whoever is in sight.
		self:travel(at)
	end
	self:checkStuck(at)
end

return BotBrain
