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
--     after first seeing a target, turns to face it and fires the gun its
--     life carries (CombatService.fireAsBot) at the upper body, or now and
--     then the head, through an error cone that's wider the faster the
--     target crosses its view, the farther away it is, in the first moment
--     of aiming and in mid-air; never faster than the gun's interval times
--     its multiplier, and only inside the gun's reach (BotConfig.WEAPONS).
--     A Stink Lobber throws instead: the arc that lands on them, the low
--     one if nothing's in the way, else the high one, and for a moment
--     after they duck behind cover it goes on lobbing, high, at where it
--     saw them last. Meanwhile it strafes, now and then jumps, closes in
--     on targets farther than its gun likes and backs up from nearer ones
--     (a Spritzer up close, a Thunderclapper far off), and now and then
--     Fart Dashes in, or away, with a player's cooldown.
--   * Q: Recovery Burst once its gas is high, Gas Pulse with a target close
--     enough to catch in the ring (AbilityService.useAsBot).
--   * Backing off: at high gas it heads back to its own spawn, still
--     shooting at anyone in sight (and dashing away now and then), until it
--     has recovered.
--   * Getting about: with nobody to fight it walks a path
--     (PathfindingService) to a goal: the control zone in Gas Control
--     (holding it, not chasing out of it), else where it last saw an enemy,
--     else a patrol point in one of the lanes toward the enemy's side (not
--     so far for a Thunderclapper, which waits at each one, watching). It
--     plans again on a timer; stuck, it jumps, then picks somewhere else.
-- How good it is at all of this is its tuning (BotConfig.tuning); its gun
-- changes where it fights, never how well it aims or how fast it reacts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotConfig = require(Shared.Config.BotConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
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
local DashService = require(Services.DashService)
local AbilityService = require(Services.AbilityService)
local ProjectileService = require(Services.ProjectileService)

local DASH = AbilityConfig.FartDash
-- How far a Fart Dash goes.
local DASH_STUDS = (DASH.speed :: number) * DASH.durationSeconds
-- A lob is aimed this far below the target's middle (about its knees): on
-- the way down it hits them or lands at their feet.
local LOB_DROP = 2
-- An arc that hits something within this of where it's aimed lands there.
local LOB_NEAR_STUDS = 6
-- With no arc that gets there clear, it looks again after this.
local LOB_RETRY_SECONDS = 0.5
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
	-- This life's gun and how it's fought with, and its Q ability.
	weapon: WeaponConfig.Weapon,
	style: BotConfig.Style,
	ability: AbilityConfig.Ability?,
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
	-- Which way the fight's range last moved it: 1 in, -1 back, 0 neither.
	intent: number,
	nextDashAt: number,
	nextAbilityAt: number,
	-- When it vents, now that its gas is high (its reaction time on).
	ventAt: number?,
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
	-- Waiting at a patrol spot until then, looking that way.
	holdUntil: number,
	holdLook: Vector3?,
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
	local weapon = BotService.weaponOf(bot)
	local fields: Fields = {
		bot = bot,
		character = character,
		humanoid = humanoid,
		root = root,
		head = if head and head:IsA("BasePart") then head else root,
		tuning = tuning,
		weapon = weapon,
		style = BotConfig.styleOf(weapon.id),
		ability = if bot.ability then AbilityConfig[bot.ability] else nil,
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
		intent = 0,
		nextDashAt = at,
		nextAbilityAt = at,
		ventAt = nil,
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
		holdUntil = -math.huge,
		holdLook = nil,
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

-- Where a Stink Lobber goes on throwing at a target that has gone behind
-- cover (still in the fight, seen in the last LOB_BLIND_SECONDS): where it
-- saw them last. Nil for any other gun, or with a target in sight.
function BotBrain.blindPoint(self: Brain, at: number): Vector3?
	local seen = self.lastSeenPosition
	if self.weapon.projectile ~= "lob" or self.visible or not seen or at - self.lastVisibleAt > BotConfig.LOB_BLIND_SECONDS then
		return nil
	end
	if not (self.lastKey ~= nil and foe(self.lastKey, self.bot.team)) then
		return nil
	end
	return seen - Vector3.new(0, LOB_DROP, 0)
end

-- Lines up the next shot when it's due before the next tick (none at a
-- target out of its gun's reach).
function BotBrain.trigger(self: Brain, at: number)
	if self.shotQueued or at < self.readyAt - BotConfig.THINK_SECONDS then
		return
	end
	local target = self.target
	if target and self.visible then
		if flat(target.root.Position - self.root.Position).Magnitude > self.style.fireRange then
			return
		end
	elseif not self:blindPoint(at) then
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

-- How wide (degrees) the cone a shot lands in is, `distance` away along
-- `line` with the target moving at `relative` to it.
function BotBrain.errorCone(self: Brain, at: number, line: Vector3, distance: number, relative: Vector3): number
	local t = self.tuning
	local sideways = (relative - line * relative:Dot(line)).Magnitude
	local cone = t.aimErrorDegrees + t.speedErrorDegrees * sideways / 16 + t.distanceErrorDegrees * distance / 100
	local settling = math.clamp(1 - (at - self.seenAt) / t.settleSeconds, 0, 1)
	cone *= 1 + BotConfig.SETTLE_EXTRA * settling
	if self.humanoid.FloorMaterial == Enum.Material.Air then
		cone *= BotConfig.AIRBORNE_ERROR
	end
	return cone
end

function BotBrain.shoot(self: Brain)
	if RoundService.phase() ~= States.Phase.ACTIVE or BotService.isExploding(self.bot) then
		return
	end
	local at = now()
	local fired = if self.weapon.projectile == "lob" then self:throw(at) else self:fire(at)
	if fired == nil then
		return -- nothing to shoot at in reach
	end
	-- Timed from when the shot really went, so it's never sooner than the
	-- weapon allows however the frames fall.
	local interval = self.weapon.fireInterval
	local wait = if fired then math.max(interval + 0.02, interval * self.tuning.fireIntervalMultiplier * self.rng:NextNumber(0.92, 1.12)) else 0.1
	self.nextShotAt = now() + wait
end

-- An instant gun's shot at the target in sight. Nil when there's none
-- within the gun's reach.
function BotBrain.fire(self: Brain, at: number): boolean?
	local target = self.target
	local fresh = if target and self.visible then foe(target.key, self.bot.team) else nil
	if not fresh then
		return nil
	end
	local from = self.head.Position
	local offset = aimPart(fresh, self.rng:NextNumber() < self.tuning.headChance).Position - from
	local distance = offset.Magnitude
	if distance < 0.5 or distance > math.min(self.weapon.range, self.style.fireRange) then
		return nil
	end
	local line = offset / distance
	-- Its own movement counts too: shooting on the move is harder.
	local relative = velocity(fresh.root) - velocity(self.root)
	return CombatService.fireAsBot(self.bot, spread(line, self:errorCone(at, line, distance, relative), self.rng))
end

-- The two ways (unit directions) to throw a lob from `from` that comes down
-- on `point`, low arc first, at the weapon's speed and gravity, each nil if
-- it can't (out of reach, or a flight longer than ProjectileService lets
-- a throw fly).
function BotBrain.arcs(from: Vector3, point: Vector3, weapon: WeaponConfig.Weapon): (Vector3?, Vector3?)
	local speed, gravity = weapon.lobSpeed :: number, weapon.lobGravity :: number
	local offset = point - from
	local across = flat(offset)
	local d = across.Magnitude
	if d < 1 then
		return nil, nil
	end
	local v2 = speed * speed
	local square = v2 * v2 - gravity * (gravity * d * d + 2 * offset.Y * v2)
	if square < 0 then
		return nil, nil
	end
	local root = math.sqrt(square)
	local horizontal = across / d
	local function launch(tangent: number): Vector3?
		local direction = (horizontal + Vector3.new(0, tangent, 0)).Unit
		local flight = d / (speed * flat(direction).Magnitude)
		return if flight < ProjectileService.MAX_FLIGHT_SECONDS - 0.05 then direction else nil
	end
	return launch((v2 - root) / (gravity * d)), launch((v2 + root) / (gravity * d))
end

-- Whether a lob thrown `direction` from `from` comes down on `point` with
-- nothing in its way (LOB_RAYS rays along the arc; it may hit `through`,
-- who it's thrown at).
function BotBrain.arcClear(self: Brain, from: Vector3, direction: Vector3, point: Vector3, through: Model?): boolean
	local weapon = self.weapon
	local launch = direction * (weapon.lobSpeed :: number)
	local fall = Vector3.new(0, -(weapon.lobGravity :: number) / 2, 0)
	local flight = flat(point - from).Magnitude / math.max(flat(launch).Magnitude, 1e-3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if through then { self.character, through } else { self.character }
	local last = from
	for i = 1, BotConfig.LOB_RAYS do
		local t = flight * i / BotConfig.LOB_RAYS
		local here = from + launch * t + fall * t * t
		local hit = workspace:Raycast(last, here - last, params)
		if hit then
			return (hit.Position - point).Magnitude <= LOB_NEAR_STUDS
		end
		last = here
	end
	return true
end

-- Which way to throw at `point`: the low arc when it's clear (the high one
-- first when `high`, to get over cover), else the other; nil if neither
-- gets there.
function BotBrain.lobAim(self: Brain, from: Vector3, point: Vector3, high: boolean, through: Model?): Vector3?
	local low, steep = BotBrain.arcs(from, point, self.weapon)
	local first, second = low, steep
	if high then
		first, second = steep, low
	end
	for _, direction in { first, second } do
		if direction and self:arcClear(from, direction, point, through) then
			return direction
		end
	end
	return nil
end

-- A stink bomb at the target in sight, or (high, over cover) at where it
-- went out of sight. Nil when there's nothing to throw at within reach, or
-- no arc gets there (it looks again in a moment).
function BotBrain.throw(self: Brain, at: number): boolean?
	local point, mover, through = nil, nil, nil
	local target = self.target
	local fresh = if target and self.visible then foe(target.key, self.bot.team) else nil
	if fresh then
		point = fresh.root.Position - Vector3.new(0, LOB_DROP, 0)
		mover, through = fresh.root, fresh.character
	else
		point = self:blindPoint(at)
	end
	if not point then
		return nil
	end
	local from = self.head.Position
	local distance = flat(point - from).Magnitude
	if distance > self.style.fireRange or distance < 3 then
		return nil
	end
	local direction = self:lobAim(from, point, fresh == nil, through)
	if not direction then
		self.nextShotAt = math.max(self.nextShotAt, at + LOB_RETRY_SECONDS)
		return nil
	end
	local line = (point - from).Unit
	local relative = (if mover then velocity(mover) else Vector3.zero) - velocity(self.root)
	return CombatService.fireAsBot(self.bot, spread(direction, self:errorCone(at, line, (point - from).Magnitude, relative), self.rng))
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

-- Which way its gun wants the fight's range to go, `distance` studs from
-- the target: 1 closer (not when holding the zone: it doesn't chase out of
-- it), -1 back, 0 it's where it wants to be.
function BotBrain.rangeIntent(self: Brain, distance: number, holdZone: boolean): number
	if distance > self.style.closeIn and not holdZone then
		return 1
	elseif distance < self.style.backUp then
		return -1
	end
	return 0
end

-- Now and then (the tuning's dashesPerSecond; never inside the cooldown,
-- only from the ground) a Fart Dash along `direction`, if nothing solid is
-- in the way. Returns whether it dashed.
function BotBrain.maybeDash(self: Brain, at: number, dt: number, direction: Vector3): boolean
	if not FeatureFlags.FART_DASH or at < self.nextDashAt or self.humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	local along = flat(direction)
	if along.Magnitude < 0.1 or self.rng:NextNumber() >= self.tuning.dashesPerSecond * dt then
		return false
	end
	if workspace:Raycast(self.root.Position, along.Unit * DASH_STUDS, self.rays) then
		return false
	end
	local dashed = DashService.dashAsBot(self.bot, along.Unit)
	self.nextDashAt = now() + (if dashed then DASH.cooldownSeconds else 0.5)
	return dashed
end

-- Holding ground in a fight: strafing, now and then a jump, closing in on
-- a target farther than its gun likes and backing up from a nearer one,
-- now and then with a dash.
function BotBrain.skirmish(self: Brain, at: number, dt: number, holdZone: boolean)
	local target = self.target :: Foe
	local style = self.style
	local offset = flat(target.root.Position - self.root.Position)
	local distance = offset.Magnitude
	local toward = if distance > 0.1 then offset / distance else Vector3.zAxis
	local side = Vector3.new(-toward.Z, 0, toward.X)
	if at >= self.strafeUntil then
		local seconds = BotConfig.STRAFE_SECONDS
		self.strafeUntil = at + self.rng:NextNumber(seconds[1], seconds[2])
		self.strafeSide = if self.rng:NextNumber() < self.tuning.strafeChance * style.strafe then (if self.rng:NextNumber() < 0.5 then -1 else 1) else 0
		if self.strafeSide ~= 0 and self:blocked(side * self.strafeSide) then
			self.strafeSide = -self.strafeSide
		end
	end
	local intent = self:rangeIntent(distance, holdZone)
	self.intent = intent
	local move = side * self.strafeSide + toward * intent
	if move.Magnitude > 0.1 then
		self.moving = true
		self.moveTarget = nil
		self.humanoid:MoveTo(self.root.Position + move.Unit * 8)
	else
		self:moveTo(self.root.Position, at)
	end
	if self.rng:NextNumber() < self.tuning.jumpsPerSecond * style.jumps * dt then
		self.humanoid.Jump = true
	end
	-- A dash in only when it won't overshoot where the gun likes to be; out
	-- only when the target is well inside where it backs off.
	if intent > 0 and distance - style.closeIn > DASH_STUDS then
		self:maybeDash(at, dt, toward)
	elseif intent < 0 and style.backUp - distance > DASH_STUDS / 2 then
		self:maybeDash(at, dt, -toward)
	end
end

-- Backing off with someone in sight and near: now and then a dash away (on
-- along its way home, if that's away from them).
function BotBrain.escape(self: Brain, at: number, dt: number, target: Foe)
	local away = flat(self.root.Position - target.root.Position)
	if away.Magnitude < 0.1 or away.Magnitude > BotConfig.ESCAPE_STUDS then
		return
	end
	local heading = if self.moveTarget then flat(self.moveTarget - self.root.Position) else Vector3.zero
	local direction = if heading.Magnitude > 1 and heading.Unit:Dot(away.Unit) > 0 then heading else away
	self:maybeDash(at, dt, direction)
end

-- Its Q ability, where it helps, after its reaction time: Recovery Burst
-- once its gas is up to VENT_GAS; Gas Pulse with the target in sight close
-- enough to catch in the ring, once it's ready to fire on them.
function BotBrain.useAbility(self: Brain, at: number)
	local ability = self.ability
	if not ability or at < self.nextAbilityAt then
		return
	end
	local wanted = false
	if ability.vent then
		if BotService.gasOf(self.bot) >= BotConfig.VENT_GAS then
			self.ventAt = self.ventAt or at + self.tuning.reactionSeconds * self.rng:NextNumber(0.85, 1.2)
			wanted = at >= (self.ventAt :: number)
		else
			self.ventAt = nil
		end
	elseif ability.radius then
		local target = self.target
		wanted = target ~= nil and self.visible and at >= self.readyAt
			and (target.root.Position - self.root.Position).Magnitude <= BotConfig.PULSE_STUDS
	end
	if wanted then
		local used = AbilityService.useAsBot(self.bot)
		self.nextAbilityAt = now() + (if used then ability.cooldownSeconds else 1)
		self.ventAt = nil
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
	local depth = self.style.patrolDepth
	local along = home:Lerp(away, self.rng:NextNumber(depth[1], depth[2]))
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
		local zone = activeZone() :: BasePart
		local size = zone.Size
		return zone.CFrame:PointToWorldSpace(Vector3.new(self.rng:NextNumber(-0.35, 0.35) * size.X, -size.Y / 2, self.rng:NextNumber(-0.35, 0.35) * size.Z))
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

-- Waiting at a patrol spot (its gun's holdSeconds), with nothing better
-- to do.
function BotBrain.holding(self: Brain, at: number): boolean
	return at < self.holdUntil and self.goalKind == "patrol" and not self.retreating and self:wantedGoal(at) == "patrol"
end

function BotBrain.travel(self: Brain, at: number)
	if self:holding(at) then
		self:moveTo(self.root.Position, at)
		return
	end
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
		-- nothing more to see; in the zone, another spot next tick; on
		-- patrol, another once it has waited its gun's while, watching the
		-- enemy's side.
		if self.goalKind == "chase" then
			self.lastSeenPosition = nil
		elseif self.goalKind == "patrol" then
			local hold = self.style.holdSeconds
			if hold[2] > 0 then
				self.holdUntil = at + self.rng:NextNumber(hold[1], hold[2])
				self.holdLook = self:enemySide()
			end
		end
		if self.goalKind ~= "retreat" then
			self.goal = nil
		end
		self:moveTo(self.root.Position, at)
	end
end

-- The middle of the enemy's spawns (nil on a map without them).
function BotBrain.enemySide(self: Brain): Vector3?
	local theirs = {}
	for _, other in TeamConfig.order do
		if other ~= self.bot.team then
			for _, spawn in MapService.spawns(other) do
				table.insert(theirs, spawn)
			end
		end
	end
	return centroid(theirs)
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
	local active = RoundService.phase() == States.Phase.ACTIVE
	if active then
		self:look(at)
		self:trigger(at)
		self:useAbility(at)
	else
		self.target, self.visible = nil, false
	end
	self.moving = false
	local target = if self.visible then self.target else nil
	-- It faces whoever it's fighting, where it's lobbing at someone gone
	-- behind cover, or (waiting on patrol) the enemy's side.
	local blind = if target or not active then nil else self:blindPoint(at)
	self:face(if target then target.root.Position elseif blind then blind elseif self:holding(at) then self.holdLook else nil)
	local zone = activeZone()
	if target and not self.retreating and not (zone and not ZoneService.inside(self.root.Position, zone)) then
		self:skirmish(at, dt, zone ~= nil)
	else
		-- Backing off, or on the way to the zone, it still faces (and shoots
		-- at) whoever is in sight; backing off, it may dash away from them.
		if target and self.retreating then
			self:escape(at, dt, target)
		end
		self:travel(at)
	end
	self:checkStuck(at)
end

return BotBrain
