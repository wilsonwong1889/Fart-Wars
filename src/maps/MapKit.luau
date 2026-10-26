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

local MapKit = {}

export type Props = { [string]: any }

-- Turns a cylinder's axis from X to Y.
MapKit.UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

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

-- An anchored part; `props` may set ClassName (a SpawnLocation, say).
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
			if key ~= "ClassName" then
				(p :: any)[key] = value
			end
		end
	end
	p.Parent = parent
	return p
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

-- A part on the Stinkers half and its mirror on the Sharters half. With
-- `tint`, each copy takes its own team's colour.
function MapKit.pair(parent: Instance, name: string, size: Vector3, frame: CFrame, props: Props?, tint: boolean?)
	local function copy(at: CFrame, team: string)
		local p = MapKit.part(parent, name, size, at, props)
		if tint then
			p.Color = TeamConfig.teams[team].color
			p:SetAttribute("TeamTint", team)
		end
		return p
	end
	copy(frame, "Stinkers")
	copy(MapKit.mirror(frame), "Sharters")
end

function MapKit.cylinder(color: Color3, material: Enum.Material?): Props
	return { Shape = Enum.PartType.Cylinder, Color = color, Material = material or Enum.Material.SmoothPlastic }
end

-- Spawn pads at each `x` along z = `z` for the Stinkers, mirrored for the
-- Sharters (Pad1 at the same x on both sides), in Spawns/<team>.
function MapKit.spawnPads(spawns: Instance, xs: { number }, z: number)
	local stinkerPads = MapKit.folder("Stinkers", spawns)
	local sharterPads = MapKit.folder("Sharters", spawns)
	for i, x in xs do
		local frame = CFrame.new(x, 0.5, z)
		local props = { ClassName = "SpawnLocation", Material = Enum.Material.Neon, CanCollide = true }
		MapKit.part(stinkerPads, `Pad{i}`, Vector3.new(6, 1, 6), frame, props).Color = TeamConfig.teams.Stinkers.color
		MapKit.part(sharterPads, `Pad{i}`, Vector3.new(6, 1, 6), MapKit.mirror(frame), props).Color = TeamConfig.teams.Sharters.color
	end
end

-- A gas barrel lying on its side at `spot` (on the ground) and its mirror:
-- a GasBarrel model with Barrel and Band, which BarrelService arms.
function MapKit.gasBarrels(barrels: Instance, spot: Vector3, theme: MapConfig.Theme)
	local barrel = MapKit.cylinder(theme.barrel, Enum.Material.Metal)
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

-- The control zone for zone modes (a marker) and its floor ring (hidden
-- until a zone round turns it on), centred on `center` at ground level.
function MapKit.controlZone(zones: Instance, floor: Instance, center: Vector3, size: Vector3, theme: MapConfig.Theme)
	MapKit.marker(zones, "ControlZone", size, CFrame.new(center.X, size.Y / 2, center.Z))
	local diameter = math.min(size.X, size.Z) + 4
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
