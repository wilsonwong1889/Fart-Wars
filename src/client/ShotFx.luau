-- What shots look like on this screen (WeaponFx's `shot` settings; the
-- Blender meshes in Config/ShotArt, art/blender/build_shots.py):
--   * bolt: each hitscan shot streaks as a glowing gas bolt, a hot core in
--     a softer glow, from the gun's muzzle to where the shot stopped,
--     lighting what it passes, leaving a trail of smoke, and slides into
--     whatever it hit
--   * burst: the muzzle flashes a cartoon burst, turned a random way
--   * ring: a shock ring spreads from the muzzle, and from where a shot hits
--   * splat: where a shot hits a wall, the floor or cover, a splat sticks
--     to the surface for a moment and fades (never on a player)
-- These are the Blender shapes: imported into ReplicatedStorage.Assets.
-- Effects, or else built here (MeshBuilder) as soon as they can be; until
-- then (or on a device that can't build meshes) glowing parts stand in.
-- Each comes from a fixed pool (GameConfig.BUDGET.MAX_TRACERS bolts,
-- WeaponFx.SHOT's bursts, rings and splats), reused oldest first, so a
-- server full of Spritzers costs a fixed number of parts; none can be hit,
-- touched or collided with. Reduced effects and reduce motion leave out
-- the bursts, rings, splats, lights and trails; the bolt always shows,
-- since it says where the shot went.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponFx = require(Shared.Config.WeaponFx)
local ShotArt = require(Shared.Config.ShotArt)
local ArtAssets = require(Shared.Config.ArtAssets)
local WeaponModel = require(Shared.WeaponModel)
local MeshBuilder = require(Shared.MeshBuilder)
local Settings = require(script.Parent.Settings)

local SHOT = WeaponFx.SHOT
local WHITE = Color3.new(1, 1, 1)
-- The smoke a bolt leaves: pale, whatever the shot's colour.
local SMOKE = Color3.fromRGB(226, 232, 214)

local ShotFx = {}

-- The pools (for budgets and tests): each bolt is a "Tracer" part in
-- Workspace with its "Glow" and "Light" inside; bursts, rings and splats
-- are in ShotFx.
ShotFx.tracers = {} :: { BasePart }
ShotFx.bursts = {} :: { BasePart }
ShotFx.rings = {} :: { BasePart }
ShotFx.splats = {} :: { BasePart }
-- Trail puffs emitted (for budgets and tests).
ShotFx.trailed = 0

type Bolt = {
	part: BasePart,
	glow: BasePart,
	from: Vector3,
	direction: Vector3,
	distance: number,
	length: number,
	width: number,
	speed: number,
	start: number,
	-- The trail: a puff every `spacing` studs (0: none), laid as far as
	-- `trailed`, from `emitter`.
	spacing: number,
	trailed: number,
	emitter: ParticleEmitter?,
}
-- A burst or splat pops out to `full` and fades; a ring spreads to it.
type Flash = { start: number, full: Vector3, seconds: number, transparency: number, spread: boolean? }

local now = 0
local bolts: { [BasePart]: Bolt } = {}
local flashes: { [BasePart]: Flash } = {}
local nextTracer, nextBurst, nextRing, nextSplat = 0, 0, 0, 0
local trailThisFrame = 0
local folder: Folder? = nil
local trailEmitters: { [string]: ParticleEmitter } = {}
local trailAt: Attachment? = nil

local function reduced(): boolean
	return Settings.reducedEffects or Settings.lowDetail or Settings.reduceMotion
end

local function fxFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "ShotFx"
	made.Parent = workspace
	folder = made
	return made
end

-- A glowing part for the pool: the Blender mesh `mesh` (imported, or
-- built here), otherwise a plain part of `shape`.
local function make(name: string, mesh: string, shape: Enum.PartType, parent: Instance): BasePart
	local imported = WeaponModel.effect(mesh)
	local built = if imported then nil else MeshBuilder.copy("Shots", mesh)
	local part: BasePart = if imported then imported:Clone() elseif built then built else Instance.new("Part")
	if not (imported or built) then
		(part :: Part).Shape = shape
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part:SetAttribute("ArtSource", if imported then "mesh" elseif built then "runtime" else "part")
	part.Parent = parent
	return part
end

local function meshed(part: BasePart): boolean
	return part:GetAttribute("ArtSource") ~= "part"
end

local function hide(part: BasePart)
	part.Transparency = 1
	local glow = part:FindFirstChild("Glow")
	if glow and glow:IsA("BasePart") then
		glow.Transparency = 1
	end
	local light = part:FindFirstChild("Light")
	if light and light:IsA("PointLight") then
		light.Enabled = false
	end
	bolts[part] = nil
	flashes[part] = nil
end

-- Hides `part` after `seconds` unless it has been reused since: the
-- frames (ShotFx.step) normally do it first, but not in a minimised window.
local function expire(part: BasePart, seconds: number)
	local token = ((part:GetAttribute("Shown") or 0) :: number) + 1
	part:SetAttribute("Shown", token)
	task.delay(seconds, function()
		if part:GetAttribute("Shown") == token then
			hide(part)
		end
	end)
end

-- The emitter for trail puffs of `texture` ("puff", or the Spritzer's
-- "droplet"), on one attachment the trail moves along the bolt.
local function trailEmitter(texture: string): ParticleEmitter
	local existing = trailEmitters[texture]
	if existing and existing.Parent then
		return existing
	end
	if not (trailAt and trailAt.Parent) then
		local anchor = Instance.new("Part")
		anchor.Name = "Trail"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new()
		anchor.Parent = fxFolder()
		local attachment = Instance.new("Attachment")
		attachment.Parent = anchor
		trailAt = attachment
	end
	local drops = texture == "droplet"
	local particles = Instance.new("ParticleEmitter")
	particles.Name = texture
	particles.Texture = ArtAssets.effect(texture)
	particles.Rate = 0
	particles.Color = ColorSequence.new(SMOKE)
	particles.LightEmission = 0.2
	particles.Lifetime = if drops then NumberRange.new(0.25, 0.4) else NumberRange.new(0.45, 0.8)
	particles.Speed = NumberRange.new(0.3, if drops then 3 else 1.2)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Size = if drops
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.05) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.1) })
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	particles.Rotation = NumberRange.new(0, 360)
	particles.RotSpeed = NumberRange.new(-60, 60)
	particles.Drag = 3
	particles.Acceleration = Vector3.new(0, if drops then -30 else 1.5, 0)
	particles.Parent = trailAt
	trailEmitters[texture] = particles
	return particles
end

-- Puffs along the bolt from where its trail got to up to `upTo` studs
-- from the muzzle, within this frame's budget.
local function lay(bolt: Bolt, upTo: number)
	local emitter = bolt.emitter
	local attachment = trailAt
	if not (emitter and attachment) or bolt.spacing <= 0 then
		return
	end
	while bolt.trailed + bolt.spacing <= upTo and trailThisFrame < SHOT.TRAIL_PER_FRAME do
		bolt.trailed += bolt.spacing
		attachment.WorldPosition = bolt.from + bolt.direction * bolt.trailed
		emitter:Emit(1)
		trailThisFrame += 1
		ShotFx.trailed += 1
	end
	-- Past the budget, the rest of this stretch goes without.
	if bolt.trailed < upTo - bolt.spacing then
		bolt.trailed = upTo - bolt.spacing
	end
end

-- Puts a bolt where it is now. False once it has gone into its target.
local function place(bolt: Bolt): boolean
	local travelled = bolt.length + (now - bolt.start) * bolt.speed
	local head = math.min(bolt.distance, travelled)
	local tail = math.min(bolt.distance, math.max(0, travelled - bolt.length))
	local span = head - tail
	if span <= 0.02 then
		return false
	end
	local middle = bolt.from + bolt.direction * ((head + tail) / 2)
	local frame = CFrame.lookAt(middle, middle + bolt.direction)
	bolt.part.CFrame = frame
	bolt.part.Size = Vector3.new(bolt.width, bolt.width, span)
	local glow = bolt.width * SHOT.GLOW
	bolt.glow.CFrame = frame
	bolt.glow.Size = Vector3.new(glow, glow, span + bolt.width)
	lay(bolt, tail)
	return true
end

-- A shot from `from` (the muzzle) to `to`, in `color`, drawn as `style`
-- (a weapon's WeaponFx shot settings). Returns the bolt, or nil when the
-- shot is too short to see or the weapon draws none.
function ShotFx.bolt(from: Vector3, to: Vector3, color: Color3, style: WeaponFx.Shot): BasePart?
	local offset = to - from
	local distance = offset.Magnitude
	if distance < 0.5 or style.width <= 0 then
		return nil
	end
	MeshBuilder.request("Shots")
	nextTracer = nextTracer % GameConfig.BUDGET.MAX_TRACERS + 1
	local part = ShotFx.tracers[nextTracer]
	if not part or not part.Parent then
		part = make("Tracer", "GasBolt", Enum.PartType.Block, workspace)
		make("Glow", "GasBolt", Enum.PartType.Block, part)
		local light = Instance.new("PointLight")
		light.Name = "Light"
		light.Shadows = false
		light.Enabled = false
		light.Parent = part
		ShotFx.tracers[nextTracer] = part
	end
	local glow = part:FindFirstChild("Glow") :: BasePart
	-- A hot core, nearly white, in a glow of the shot's colour.
	part.Color = color:Lerp(WHITE, 0.55)
	part.Transparency = 0
	glow.Color = color
	glow.Transparency = SHOT.GLOW_TRANSPARENCY
	local light = part:FindFirstChild("Light") :: PointLight
	light.Color = color
	light.Brightness = SHOT.BOLT_LIGHT
	light.Range = style.light
	light.Enabled = style.light > 0 and not reduced()
	local trails = style.trail > 0 and not reduced()
	local bolt: Bolt = {
		part = part,
		glow = glow,
		from = from,
		direction = offset / distance,
		distance = distance,
		length = math.min(style.length, distance),
		width = style.width,
		speed = style.speed,
		start = now,
		spacing = if trails then style.trail else 0,
		trailed = 0,
		emitter = if trails then trailEmitter(style.trailTexture or "puff") else nil,
	}
	flashes[part] = nil
	bolts[part] = bolt
	place(bolt)
	expire(part, distance / style.speed + 0.25)
	return part
end

-- The muzzle's flash at `at` (its -Z down the barrel), `size` studs
-- across, in `color`.
function ShotFx.burst(at: CFrame, color: Color3, size: number): BasePart?
	if reduced() or size <= 0 then
		return nil
	end
	MeshBuilder.request("Shots")
	nextBurst = nextBurst % SHOT.BURSTS + 1
	local part = ShotFx.bursts[nextBurst]
	if not part or not part.Parent then
		part = make("Burst", "MuzzleBurst", Enum.PartType.Ball, fxFolder())
		ShotFx.bursts[nextBurst] = part
	end
	local art = ShotArt.MuzzleBurst
	local full = if meshed(part) then art.size * (size / art.size.X) else Vector3.new(1, 1, 1) * size * 0.6
	part.Color = color:Lerp(WHITE, 0.3)
	part.CFrame = at * CFrame.Angles(0, 0, math.random() * 2 * math.pi)
	part.Size = full * 0.55
	part.Transparency = 0
	bolts[part] = nil
	flashes[part] = { start = now, full = full, seconds = SHOT.BURST_SECONDS, transparency = 0 }
	expire(part, SHOT.BURST_SECONDS + 0.1)
	return part
end

-- A shock ring spreading at `at` (facing along its -Z: down the barrel,
-- or out of a surface) to `size` studs across, in `color`.
function ShotFx.ring(at: CFrame, color: Color3, size: number): BasePart?
	if reduced() or size <= 0 then
		return nil
	end
	MeshBuilder.request("Shots")
	nextRing = nextRing % SHOT.RINGS + 1
	local part = ShotFx.rings[nextRing]
	if not part or not part.Parent then
		part = make("Ring", "ShockRing", Enum.PartType.Cylinder, fxFolder())
		ShotFx.rings[nextRing] = part
	end
	local frame = at
	local full: Vector3
	if meshed(part) then
		local art = ShotArt.ShockRing
		local scale = size / art.size.X
		full = Vector3.new(size, size, math.max(0.04, art.size.Z * scale))
	else
		-- A thin disc: a cylinder's axis is its X, so turn X to face out.
		frame *= CFrame.Angles(0, math.pi / 2, 0)
		full = Vector3.new(0.04, size, size)
	end
	part.Color = color:Lerp(WHITE, 0.4)
	part.CFrame = frame
	part.Size = full * 0.25
	part.Transparency = SHOT.RING_TRANSPARENCY
	bolts[part] = nil
	flashes[part] = { start = now, full = full, seconds = SHOT.RING_SECONDS, transparency = SHOT.RING_TRANSPARENCY, spread = true }
	expire(part, SHOT.RING_SECONDS + 0.1)
	return part
end

-- Where a shot that came along `direction` hit at `position`: the surface
-- there, facing out of it (its -Z), or nil if it's a player or there's
-- nothing there.
function ShotFx.surface(position: Vector3, direction: Vector3): CFrame?
	if direction.Magnitude < 1e-3 then
		return nil
	end
	local along = direction.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fxFolder() }
	local result = workspace:Raycast(position - along * 0.6, along * 1.2, params)
	if not result then
		return nil
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	local normal = result.Normal
	local at = result.Position + normal * 0.04
	local up = if math.abs(normal.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	return CFrame.lookAt(at, at + normal, up)
end

-- A splat where a shot that came along `direction` hit at `position`,
-- `size` studs across, in `color`: stuck flat to the surface it hit (none
-- on a player, or with nothing there), with a ring `ring` across.
function ShotFx.splat(position: Vector3, direction: Vector3, color: Color3, size: number, ring: number?): BasePart?
	if reduced() or size <= 0 then
		return nil
	end
	local surface = ShotFx.surface(position, direction)
	if not surface then
		return nil
	end
	MeshBuilder.request("Shots")
	nextSplat = nextSplat % SHOT.SPLATS + 1
	local part = ShotFx.splats[nextSplat]
	if not part or not part.Parent then
		part = make("Splat", "Splat", Enum.PartType.Cylinder, fxFolder())
		ShotFx.splats[nextSplat] = part
	end
	-- Turned a random way.
	local frame = surface * CFrame.Angles(0, 0, math.random() * 2 * math.pi)
	local full: Vector3
	if meshed(part) then
		local art = ShotArt.Splat
		local scale = size / math.max(art.size.X, art.size.Y)
		full = Vector3.new(art.size.X * scale, art.size.Y * scale, math.max(0.05, art.size.Z * scale))
	else
		-- A disc: a cylinder's axis is its X, so turn X to face out.
		frame *= CFrame.Angles(0, math.pi / 2, 0)
		full = Vector3.new(0.06, size * 0.8, size * 0.8)
	end
	part.Color = color
	part.CFrame = frame
	part.Size = full * 0.6
	part.Transparency = SHOT.SPLAT_TRANSPARENCY
	bolts[part] = nil
	flashes[part] = { start = now, full = full, seconds = SHOT.SPLAT_SECONDS, transparency = SHOT.SPLAT_TRANSPARENCY }
	expire(part, SHOT.SPLAT_SECONDS + 0.1)
	if ring and ring > 0 then
		ShotFx.ring(surface * CFrame.new(0, 0, -0.02), color, ring)
	end
	return part
end

-- One frame: bolts fly on, trailing smoke; bursts and splats pop out and
-- fade; rings spread.
function ShotFx.step(dt: number)
	now += dt
	trailThisFrame = 0
	for part, bolt in bolts do
		if not place(bolt) then
			lay(bolt, bolt.distance)
			hide(part)
		end
	end
	for part, flash in flashes do
		local t = (now - flash.start) / flash.seconds
		if t >= 1 then
			hide(part)
		elseif flash.spread then
			-- Out fast, then slowing, fading all the way.
			local out = 1 - (1 - t) * (1 - t)
			part.Size = flash.full * (0.25 + 0.75 * out)
			part.Transparency = flash.transparency + (1 - flash.transparency) * t
		else
			-- Out to full size in the first eighth (a burst: half), then
			-- fading over the second half.
			local grow = if flash.seconds < 0.2 then 2 else 8
			part.Size = flash.full * (0.6 + 0.4 * math.min(1, t * grow))
			part.Transparency = flash.transparency + (1 - flash.transparency) * math.max(0, t * 2 - 1)
		end
	end
end

-- Forget the pools, so the next shots make them again: from the meshes,
-- if they've been imported or built since.
function ShotFx.clear()
	for _, pool in { ShotFx.tracers, ShotFx.bursts, ShotFx.rings, ShotFx.splats } do
		for _, part in pool do
			part:Destroy()
		end
		table.clear(pool)
	end
	table.clear(bolts)
	table.clear(flashes)
	nextTracer, nextBurst, nextRing, nextSplat = 0, 0, 0, 0
end

-- What's showing (for tests): bolts flying, and bursts, rings and splats.
function ShotFx.showing(): (number, number)
	local flying, shown = 0, 0
	for _ in bolts do
		flying += 1
	end
	for _ in flashes do
		shown += 1
	end
	return flying, shown
end

-- Once the shot meshes are built here, the pools start again with them.
MeshBuilder.built:Connect(function(set: string)
	if set == "Shots" then
		ShotFx.clear()
	end
end)

return ShotFx
