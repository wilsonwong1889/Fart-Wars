-- What shots look like on this screen (WeaponFx's `shot` settings; the
-- Blender meshes in Config/ShotArt, art/blender/build_shots.py):
--   * bolt: each hitscan shot streaks as a glowing gas bolt, a hot core in
--     a softer glow, from the gun's muzzle to where the shot stopped, and
--     slides into whatever it hit
--   * burst: the muzzle flashes a cartoon burst, turned a random way
--   * splat: where a shot hits a wall, the floor or cover, a splat sticks
--     to the surface for a moment and fades (never on a player)
-- With the meshes imported into ReplicatedStorage.Assets.Effects these are
-- the Blender shapes; until then glowing parts stand in. Each comes from a
-- fixed pool (GameConfig.BUDGET.MAX_TRACERS bolts, WeaponFx.SHOT's bursts
-- and splats), reused oldest first, so a server full of Spritzers costs a
-- fixed number of parts; none can be hit, touched or collided with.
-- Reduced effects and reduce motion leave out the bursts and splats; the
-- bolt always shows, since it says where the shot went.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponFx = require(Shared.Config.WeaponFx)
local ShotArt = require(Shared.Config.ShotArt)
local WeaponModel = require(Shared.WeaponModel)
local Settings = require(script.Parent.Settings)

local SHOT = WeaponFx.SHOT
local WHITE = Color3.new(1, 1, 1)

local ShotFx = {}

-- The pools (for budgets and tests): each bolt is a "Tracer" part in
-- Workspace with its "Glow" inside; bursts and splats are in ShotFx.
ShotFx.tracers = {} :: { BasePart }
ShotFx.bursts = {} :: { BasePart }
ShotFx.splats = {} :: { BasePart }

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
}
type Flash = { start: number, full: Vector3, seconds: number, transparency: number }

local now = 0
local bolts: { [BasePart]: Bolt } = {}
local flashes: { [BasePart]: Flash } = {}
local nextTracer, nextBurst, nextSplat = 0, 0, 0
local folder: Folder? = nil

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

-- A glowing part for the pool: the Blender mesh `mesh` if it's imported,
-- otherwise a plain part of `shape`.
local function make(name: string, mesh: string, shape: Enum.PartType, parent: Instance): BasePart
	local template = WeaponModel.effect(mesh)
	local part: BasePart = if template then template:Clone() else Instance.new("Part")
	if not template then
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
	part:SetAttribute("ArtSource", if template then "mesh" else "part")
	part.Parent = parent
	return part
end

local function hide(part: BasePart)
	part.Transparency = 1
	local glow = part:FindFirstChild("Glow")
	if glow and glow:IsA("BasePart") then
		glow.Transparency = 1
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
	nextTracer = nextTracer % GameConfig.BUDGET.MAX_TRACERS + 1
	local part = ShotFx.tracers[nextTracer]
	if not part or not part.Parent then
		part = make("Tracer", "GasBolt", Enum.PartType.Block, workspace)
		make("Glow", "GasBolt", Enum.PartType.Block, part)
		ShotFx.tracers[nextTracer] = part
	end
	local glow = part:FindFirstChild("Glow") :: BasePart
	-- A hot core, nearly white, in a glow of the shot's colour.
	part.Color = color:Lerp(WHITE, 0.55)
	part.Transparency = 0
	glow.Color = color
	glow.Transparency = SHOT.GLOW_TRANSPARENCY
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
	nextBurst = nextBurst % SHOT.BURSTS + 1
	local part = ShotFx.bursts[nextBurst]
	if not part or not part.Parent then
		part = make("Burst", "MuzzleBurst", Enum.PartType.Ball, fxFolder())
		ShotFx.bursts[nextBurst] = part
	end
	local art = ShotArt.MuzzleBurst
	local full = if part:GetAttribute("ArtSource") == "mesh" then art.size * (size / art.size.X) else Vector3.new(1, 1, 1) * size * 0.6
	part.Color = color:Lerp(WHITE, 0.3)
	part.CFrame = at * CFrame.Angles(0, 0, math.random() * 2 * math.pi)
	part.Size = full * 0.55
	part.Transparency = 0
	bolts[part] = nil
	flashes[part] = { start = now, full = full, seconds = SHOT.BURST_SECONDS, transparency = 0 }
	expire(part, SHOT.BURST_SECONDS + 0.1)
	return part
end

-- A splat where a shot that came along `direction` hit at `position`,
-- `size` studs across, in `color`: stuck flat to the surface it hit (none
-- on a player, or with nothing there).
function ShotFx.splat(position: Vector3, direction: Vector3, color: Color3, size: number): BasePart?
	if reduced() or size <= 0 or direction.Magnitude < 1e-3 then
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
	nextSplat = nextSplat % SHOT.SPLATS + 1
	local part = ShotFx.splats[nextSplat]
	if not part or not part.Parent then
		part = make("Splat", "Splat", Enum.PartType.Cylinder, fxFolder())
		ShotFx.splats[nextSplat] = part
	end
	local normal = result.Normal
	local at = result.Position + normal * 0.04
	local up = if math.abs(normal.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	-- Facing out of the surface (the mesh faces -Z), turned a random way.
	local frame = CFrame.lookAt(at, at + normal, up) * CFrame.Angles(0, 0, math.random() * 2 * math.pi)
	local full: Vector3
	if part:GetAttribute("ArtSource") == "mesh" then
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
	return part
end

-- One frame: bolts fly on, bursts and splats pop out and fade.
function ShotFx.step(dt: number)
	now += dt
	for part, bolt in bolts do
		if not place(bolt) then
			hide(part)
		end
	end
	for part, flash in flashes do
		local t = (now - flash.start) / flash.seconds
		if t >= 1 then
			hide(part)
		else
			-- Out to full size in the first eighth (a burst: half), then
			-- fading over the second half.
			local grow = if flash.seconds < 0.2 then 2 else 8
			part.Size = flash.full * (0.6 + 0.4 * math.min(1, t * grow))
			part.Transparency = flash.transparency + (1 - flash.transparency) * math.max(0, t * 2 - 1)
		end
	end
end

-- Test-only: forget the pools, so the next shots make them again (from
-- the meshes, if they've been imported since).
function ShotFx.clear()
	for _, pool in { ShotFx.tracers, ShotFx.bursts, ShotFx.splats } do
		for _, part in pool do
			part:Destroy()
		end
		table.clear(pool)
	end
	table.clear(bolts)
	table.clear(flashes)
	nextTracer, nextBurst, nextSplat = 0, 0, 0
end

-- What's showing (for tests): bolts flying, and bursts and splats.
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

return ShotFx
