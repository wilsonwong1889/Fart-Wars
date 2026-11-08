-- The pieces maps are built from (masterplan 6.1's map pipeline), so a
-- new arena reuses the same spawn, cover, barrel and marker prefabs and
-- keeps the same rules: everything anchored, markers out of the way of
-- players, rays and touches, and one half mirrored onto the other across
-- z = 0 so neither team has the better side. Not a map itself:
-- MapConfig never lists it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeamConfig = require(Shared.Config.TeamConfig)
local MapConfig = require(Shared.Config.MapConfig)
local UIConfig = require(Shared.Config.UIConfig)

local MapKit = {}

export type Props = { [string]: any }

-- Turns a cylinder's axis from X to Y.
MapKit.UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- The attribute (and `props` key) that marks a part laid out at avatar
-- height: MapKit.scale grows it across but not up. It's for low cover, the
-- walls and crates players shoot and lob over, which would otherwise come
-- out three times taller than the avatars behind them.
MapKit.KEEP_HEIGHT = "KeepHeight"

-- The furthest a light reaches (Roblox's limit), which MapKit.scale stops at.
MapKit.MAX_LIGHT_RANGE = 60

-- A sign's canvas width in pixels. TextScaled words top out at 100 pixels
-- tall, so the canvas has to stay this size whatever the sign's, or the
-- words on a big sign would come out small.
local SIGN_PIXELS = 600
-- The outline round a sign's words, so they read against any board.
local SIGN_STROKE = Color3.fromRGB(35, 30, 45)

-- The other half's copy of a CFrame: reflected across z = 0. The rotation
-- is conjugated by the reflection, which mirrors any shape that is
-- symmetric front to back in its own space (blocks and cylinders).
function MapKit.mirror(frame: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:GetComponents()
	return CFrame.new(x, y, -z, r00, r01, -r02, r10, r11, -r12, -r20, -r21, r22)
end

function MapKit.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- An anchored part; `props` may set ClassName (a SpawnLocation, say) and
-- KeepHeight (true: low cover, see MapKit.KEEP_HEIGHT). A plastic block
-- gets studs on top, like a building brick.
function MapKit.part(parent: Instance, name: string, size: Vector3, frame: CFrame, props: Props?): BasePart
	local className = if props and props.ClassName then props.ClassName else "Part"
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = frame
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for key, value in props do
			if key == MapKit.KEEP_HEIGHT then
				p:SetAttribute(MapKit.KEEP_HEIGHT, value)
			elseif key ~= "ClassName" then
				(p :: any)[key] = value
			end
		end
	end
	if MapKit.studded(p) then
		p.TopSurface = Enum.SurfaceType.Studs
	end
	p.Parent = parent
	return p
end

-- Whether a part gets studs: a plastic block (not a cylinder or a ball).
function MapKit.studded(p: BasePart): boolean
	return p.Material == Enum.Material.Plastic and not (p:IsA("Part") and (p :: Part).Shape ~= Enum.PartType.Block)
end

-- A marker part: invisible, never in the way of players, rays or touches.
function MapKit.marker(parent: Instance, name: string, size: Vector3, frame: CFrame): BasePart
	return MapKit.part(parent, name, size, frame, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

-- A part on the Stinkers half and its mirror on the Sharters half, both
-- returned (the Stinkers' first). With `tint`, each copy takes its own
-- team's colour.
function MapKit.pair(parent: Instance, name: string, size: Vector3, frame: CFrame, props: Props?, tint: boolean?): (BasePart, BasePart)
	local function copy(at: CFrame, team: string)
		local p = MapKit.part(parent, name, size, at, props)
		if tint then
			p.Color = TeamConfig.teams[team].color
			p:SetAttribute("TeamTint", team)
		end
		return p
	end
	return copy(frame, "Stinkers"), copy(MapKit.mirror(frame), "Sharters")
end

-- Decor: a part that is only to look at. Players walk and shoot through it
-- and it never stops a blast or a raycast, so keep it out of reach (up on
-- the walls, above everyone's heads) where seeing through it can't matter.
function MapKit.decor(color: Color3, material: Enum.Material?, extra: Props?): Props
	local props: Props = {
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}
	for key, value in extra or {} do
		props[key] = value
	end
	return props
end

-- Writes `text` on a sign's front and back (its -Z and +Z faces), in the
-- game's display font with a dark outline, lit the same whatever the
-- lighting, so it reads from either way down a lane.
function MapKit.sign(part: BasePart, text: string, color: Color3)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = `{face.Name}Sign`
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		-- The board's own proportions, so the words aren't stretched.
		gui.CanvasSize = Vector2.new(SIGN_PIXELS, math.round(SIGN_PIXELS * part.Size.Y / part.Size.X))
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Name"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.92, 0.8)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = UIConfig.font
		label.TextColor3 = color
		label.TextStrokeColor3 = SIGN_STROKE
		label.TextStrokeTransparency = 0
		label.Parent = gui
		gui.Parent = part
	end
end

-- A coloured lamp in `part` (a neon trim, say), reaching `range` studs in
-- the layout (MapKit.scale stretches it with the map). No shadows: they
-- cost the most and an accent light doesn't need them.
function MapKit.light(part: BasePart, color: Color3, range: number, brightness: number?): PointLight
	local lamp = Instance.new("PointLight")
	lamp.Color = color
	lamp.Range = range
	lamp.Brightness = brightness or 2
	lamp.Shadows = false
	lamp.Parent = part
	return lamp
end

function MapKit.cylinder(color: Color3, material: Enum.Material?): Props
	return { Shape = Enum.PartType.Cylinder, Color = color, Material = material or Enum.Material.SmoothPlastic }
end

-- Spawn pads at each `x` along z = `z` for the Stinkers, mirrored for the
-- Sharters (Pad1 at the same x on both sides), in Spawns/<team>. Avatars
-- start the way their pad faces, so both face the middle of the map.
function MapKit.spawnPads(spawns: Instance, xs: { number }, z: number)
	local stinkerPads = MapKit.folder("Stinkers", spawns)
	local sharterPads = MapKit.folder("Sharters", spawns)
	for i, x in xs do
		local frame = CFrame.new(x, 0.5, z)
		local props = { ClassName = "SpawnLocation", Material = Enum.Material.Neon, CanCollide = true }
		MapKit.part(stinkerPads, `Pad{i}`, Vector3.new(6, 1, 6), frame * CFrame.Angles(0, math.pi, 0), props).Color = TeamConfig.teams.Stinkers.color
		MapKit.part(sharterPads, `Pad{i}`, Vector3.new(6, 1, 6), MapKit.mirror(frame), props).Color = TeamConfig.teams.Sharters.color
	end
end

-- A gas barrel lying on its side at `spot` (on the ground) and its mirror:
-- a GasBarrel model with Barrel and Band, which BarrelService arms.
function MapKit.gasBarrels(barrels: Instance, spot: Vector3, theme: MapConfig.Theme)
	local barrel = MapKit.cylinder(theme.barrel)
	local band = MapKit.cylinder(theme.barrelBand, Enum.Material.Neon)
	local frame = CFrame.new(spot.X, 2.5, spot.Z) * MapKit.UPRIGHT
	for _, at in { frame, MapKit.mirror(frame) } do
		local gasBarrel = Instance.new("Model")
		gasBarrel.Name = "GasBarrel"
		local body = MapKit.part(gasBarrel, "Barrel", Vector3.new(5, 4, 4), at, barrel)
		MapKit.part(gasBarrel, "Band", Vector3.new(0.6, 4.2, 4.2), at, band)
		gasBarrel.PrimaryPart = body
		gasBarrel.Parent = barrels
	end
end

-- Fixed spectator views: { from, lookAt } each.
function MapKit.cameraViews(cameras: Instance, views: { { Vector3 } })
	for i, view in views do
		MapKit.marker(cameras, `View{i}`, Vector3.new(1, 1, 1), CFrame.lookAt(view[1], view[2]))
	end
end

-- Scales a built map by `factor` about the ground at the origin: every
-- part's size and position, markers, camera points and barrels included,
-- so the mirror across z = 0 still holds. Two kinds of part grow only
-- across and keep their height and where they stand:
--   * one lying on the ground and at most a stud tall (a floor strip, a
--     spawn pad, the zone ring), so it stays something you walk on rather
--     than a step
--   * one marked KeepHeight (low cover), laid out at avatar height, so a
--     wall an avatar can hide behind stays that low instead of becoming
--     one nobody can shoot or lob over
-- Lights reach `factor` times further, up to Roblox's limit, so a lamp
-- still lights what it lit in the layout. Rotations must be quarter turns
-- (all the kit makes). The map keeps the factor as its Scale attribute, so
-- the dressing's modules grow with it.
function MapKit.scale(model: Model, factor: number)
	if factor == 1 then
		return
	end
	model:SetAttribute("Scale", factor)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = item.CFrame:GetComponents()
			-- World up in the part's own axes picks out its vertical side.
			local up = Vector3.new(math.abs(r10), math.abs(r11), math.abs(r12))
			local size = item.Size
			local height = up.X * size.X + up.Y * size.Y + up.Z * size.Z
			local flat = height <= 1 and math.abs(y - height / 2) <= 0.5
			if flat or item:GetAttribute(MapKit.KEEP_HEIGHT) == true then
				item.Size = size * (Vector3.new(1, 1, 1) - up) * factor + size * up
			else
				item.Size = size * factor
				y *= factor
			end
			item.CFrame = CFrame.new(x * factor, y, z * factor, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		elseif item:IsA("Light") then
			local light = item :: any
			light.Range = math.min(light.Range * factor, MapKit.MAX_LIGHT_RANGE)
		end
	end
end

-- The control zone for zone modes and its floor ring (hidden until a zone
-- round turns it on), centred on `center` at ground level: a round marker
-- `radius` out and `height` up (an upright cylinder, invisible and in
-- nobody's way) and a ring exactly as wide, so standing on the ring is
-- standing in the zone (ZoneService checks the cylinder).
function MapKit.controlZone(zones: Instance, floor: Instance, center: Vector3, radius: number, height: number, theme: MapConfig.Theme)
	local diameter = radius * 2
	MapKit.part(zones, "ControlZone", Vector3.new(height, diameter, diameter), CFrame.new(center.X, height / 2, center.Z) * MapKit.UPRIGHT, {
		Shape = Enum.PartType.Cylinder,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	MapKit.part(floor, "ControlZoneFloor", Vector3.new(0.2, diameter, diameter), CFrame.new(center.X, 0.25, center.Z) * MapKit.UPRIGHT, {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = theme.porcelain,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

return MapKit
