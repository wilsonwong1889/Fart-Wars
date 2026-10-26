-- Brainrot Battlefield v0: the Phase 1 blockout, built from code so it lives
-- in Git. A Model named BrainrotBattlefield placed here in Studio replaces it
-- (MapService uses whichever is in ServerStorage.Maps).
--
-- 160 x 160 studs, ground at y = 0. The Skibidi Stinkers spawn at the -Z end
-- and the Sigma Sharters at +Z; everything on one half is mirrored onto the
-- other across z = 0, so neither side has a better layout. Three lanes run
-- along Z, split by divider walls at x = ±26 that each have two gaps:
--   Bean Alley (x < -26)   giant bean cans and low walls
--   Porcelain Plaza (|x| < 26)   the back-to-back toilet throne at the centre
--   Gas Gutter (x > 26)    toxic barrel clusters and crates
-- Each spawn room is walled on its front and sides with its doors at the
-- back, onto a corridor along the end wall that opens into the side lanes,
-- so nothing out in the lanes or the enemy half can see the spawn pads.
-- Barrels sit in the contested middle, never by a spawn; they're
-- decoration only until Phase 2 makes them explode.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeamConfig = require(Shared.Config.TeamConfig)
local MapConfig = require(Shared.Config.MapConfig)

local HALF = 80 -- half the arena's width and length
local BOUNDARY_HEIGHT = 24
local SPAWN_WALL_HEIGHT = 16
local DIVIDER_HEIGHT = 14
local DIVIDER_X = 26
-- Divider wall segments along Z (the gaps between them join the lanes).
local DIVIDER_SEGMENTS = { { -45, -24 }, { -12, 12 }, { 24, 45 } }
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder's axis from X to Y

-- The other half's copy of a CFrame: reflected across z = 0. The rotation
-- is conjugated by the reflection, which mirrors any shape that is
-- symmetric front to back in its own space (blocks and cylinders).
local function mirror(frame: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:GetComponents()
	return CFrame.new(x, y, -z, r00, r01, -r02, r10, r11, -r12, -r20, -r21, r22)
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

type Props = { [string]: any }

local function part(parent: Instance, name: string, size: Vector3, frame: CFrame, props: Props?): BasePart
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
local function marker(parent: Instance, name: string, size: Vector3, frame: CFrame): BasePart
	return part(parent, name, size, frame, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

-- A part on the Stinkers half and its mirror on the Sharters half. With
-- `tint`, each copy takes its own team's colour.
local function pair(parent: Instance, name: string, size: Vector3, frame: CFrame, props: Props?, tint: boolean?)
	local function copy(at: CFrame, team: string)
		local p = part(parent, name, size, at, props)
		if tint then
			p.Color = TeamConfig.teams[team].color
			p:SetAttribute("TeamTint", team)
		end
		return p
	end
	copy(frame, "Stinkers")
	copy(mirror(frame), "Sharters")
end

local function cylinder(color: Color3, material: Enum.Material?): Props
	return { Shape = Enum.PartType.Cylinder, Color = color, Material = material or Enum.Material.SmoothPlastic }
end

local function build(entry: MapConfig.MapEntry): Model
	local theme = entry.theme
	local model = Instance.new("Model")
	model.Name = "BrainrotBattlefield"

	local floorFolder = folder("Floor", model)
	local walls = folder("Walls", model)
	local cover = folder("Cover", model)
	local decor = folder("Decor", model)
	local zones = folder("Zones", model)
	local cameras = folder("CameraPoints", model)
	local spawns = folder("Spawns", model)

	local wall: Props = { Color = theme.wall, Material = Enum.Material.Concrete }
	local trim: Props = { Color = theme.trim, Material = Enum.Material.Neon }

	-- Ground and the three lane strips (colour only; they're walkable too).
	part(floorFolder, "Ground", Vector3.new(HALF * 2, 4, HALF * 2), CFrame.new(0, -2, 0), {
		Color = theme.ground,
		Material = Enum.Material.Ground,
	})
	for name, x in { Left = -53, Center = 0, Right = 53 } do
		part(floorFolder, `Lane{name}Floor`, Vector3.new(if name == "Center" then 50 else 52, 0.2, 90), CFrame.new(x, 0.1, 0), {
			Color = theme.lanes[name],
			Material = if name == "Center" then Enum.Material.Marble else Enum.Material.Slate,
		})
	end

	-- Boundary: the ends are mirrored; each side wall spans both halves.
	pair(walls, "EndWall", Vector3.new(HALF * 2 + 4, BOUNDARY_HEIGHT, 2), CFrame.new(0, BOUNDARY_HEIGHT / 2, -HALF - 1), wall)
	for _, x in { -HALF - 1, HALF + 1 } do
		part(walls, "SideWall", Vector3.new(2, BOUNDARY_HEIGHT, HALF * 2 + 4), CFrame.new(x, BOUNDARY_HEIGHT / 2, 0), wall)
		part(walls, "SideTrim", Vector3.new(2.4, 1, HALF * 2 + 4), CFrame.new(x, BOUNDARY_HEIGHT + 0.5, 0), trim)
	end
	pair(walls, "EndTrim", Vector3.new(HALF * 2 + 4, 1, 2.4), CFrame.new(0, BOUNDARY_HEIGHT + 0.5, -HALF - 1), trim)

	-- Lane dividers, each with two gaps. The middle segment straddles z = 0
	-- and is its own mirror.
	for _, x in { -DIVIDER_X, DIVIDER_X } do
		for _, segment in DIVIDER_SEGMENTS do
			local from, to = segment[1], segment[2]
			local size = Vector3.new(2, DIVIDER_HEIGHT, to - from)
			local frame = CFrame.new(x, DIVIDER_HEIGHT / 2, (from + to) / 2)
			if from < 0 and to > 0 then
				part(walls, "Divider", size, frame, wall)
			elseif to <= 0 then
				pair(walls, "Divider", size, frame, wall)
			end
		end
	end

	-- Spawn rooms: interior x -24..24, z -74..-58 (mirrored for the
	-- Sharters). Solid front and sides; two doors in the back wall
	-- (x ±17..24) open onto the corridor along the end wall (z -80..-76),
	-- which leads out to both side lanes.
	pair(walls, "SpawnFront", Vector3.new(52, SPAWN_WALL_HEIGHT, 2), CFrame.new(0, SPAWN_WALL_HEIGHT / 2, -57), wall)
	pair(walls, "SpawnFrontTrim", Vector3.new(52.4, 1, 2.4), CFrame.new(0, SPAWN_WALL_HEIGHT + 0.5, -57), {
		Material = Enum.Material.Neon,
	}, true)
	for _, x in { -25, 25 } do
		pair(walls, "SpawnSide", Vector3.new(2, SPAWN_WALL_HEIGHT, 20), CFrame.new(x, SPAWN_WALL_HEIGHT / 2, -66), wall)
	end
	pair(walls, "SpawnBack", Vector3.new(34, SPAWN_WALL_HEIGHT, 2), CFrame.new(0, SPAWN_WALL_HEIGHT / 2, -75), wall)
	pair(floorFolder, "SpawnFloor", Vector3.new(48, 0.2, 16), CFrame.new(0, 0.1, -66), {
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
	}, true)

	local stinkerPads = folder("Stinkers", spawns)
	local sharterPads = folder("Sharters", spawns)
	for i, x in { -15, -5, 5, 15 } do
		local frame = CFrame.new(x, 0.5, -66)
		local props = { ClassName = "SpawnLocation", Material = Enum.Material.Neon, CanCollide = true }
		part(stinkerPads, `Pad{i}`, Vector3.new(6, 1, 6), frame, props).Color = TeamConfig.teams.Stinkers.color
		-- The mirror keeps the pad order: Pad1 is at the same x on both sides.
		part(sharterPads, `Pad{i}`, Vector3.new(6, 1, 6), mirror(frame), props).Color = TeamConfig.teams.Sharters.color
	end

	-- Porcelain Plaza: the throne (two giant toilets back to back across the
	-- centre line) and low cover on the way to it.
	local porcelain = cylinder(theme.porcelain, Enum.Material.Marble)
	pair(cover, "ThroneTank", Vector3.new(16, 14, 4), CFrame.new(0, 7, -2), { Color = theme.porcelain, Material = Enum.Material.Marble })
	pair(cover, "ThroneLid", Vector3.new(17, 1, 5), CFrame.new(0, 14.5, -2), trim)
	pair(cover, "ThroneBowl", Vector3.new(6, 12, 12), CFrame.new(0, 3, -10) * UPRIGHT, porcelain)
	pair(cover, "ThroneSeat", Vector3.new(1, 13, 13), CFrame.new(0, 6.5, -10) * UPRIGHT, cylinder(theme.trim, Enum.Material.Neon))
	for _, spot in { Vector3.new(-14, 0, -30), Vector3.new(14, 0, -22), Vector3.new(-6, 0, -44) } do
		pair(cover, "PlazaWall", Vector3.new(10, 5, 2), CFrame.new(spot.X, 2.5, spot.Z), wall)
	end

	-- Bean Alley: bean cans tall enough to hide behind, with a label band.
	local bean = cylinder(theme.bean, Enum.Material.Metal)
	local label = cylinder(theme.beanLabel)
	for _, spot in { Vector3.new(-53, 0, -32), Vector3.new(-40, 0, -14), Vector3.new(-66, 0, -6) } do
		pair(cover, "BeanCan", Vector3.new(10, 8, 8), CFrame.new(spot.X, 5, spot.Z) * UPRIGHT, bean)
		pair(cover, "BeanLabel", Vector3.new(4, 8.4, 8.4), CFrame.new(spot.X, 5, spot.Z) * UPRIGHT, label)
	end
	pair(cover, "AlleyWall", Vector3.new(14, 6, 2), CFrame.new(-56, 3, -20), wall)

	-- Gas Gutter: a sideways toilet, crates, and barrel clusters (decor).
	pair(cover, "GutterTank", Vector3.new(4, 10, 12), CFrame.new(60, 5, -26), { Color = theme.porcelain, Material = Enum.Material.Marble })
	pair(cover, "GutterBowl", Vector3.new(5, 9, 9), CFrame.new(54, 2.5, -26) * UPRIGHT, porcelain)
	for _, spot in { Vector3.new(40, 0, -36), Vector3.new(46, 0, -8) } do
		pair(cover, "Crate", Vector3.new(8, 6, 8), CFrame.new(spot.X, 3, spot.Z), {
			Color = Color3.fromRGB(120, 90, 50),
			Material = Enum.Material.WoodPlanks,
		})
	end
	local barrel = cylinder(theme.barrel, Enum.Material.Metal)
	local band = cylinder(theme.barrelBand, Enum.Material.Neon)
	for _, spot in {
		Vector3.new(66, 0, -12),
		Vector3.new(70, 0, -16),
		Vector3.new(-70, 0, -14),
		Vector3.new(12, 0, -16),
		Vector3.new(-18, 0, -14),
		Vector3.new(36, 0, -28),
	} do
		pair(decor, "Barrel", Vector3.new(5, 4, 4), CFrame.new(spot.X, 2.5, spot.Z) * UPRIGHT, barrel)
		pair(decor, "BarrelBand", Vector3.new(0.6, 4.2, 4.2), CFrame.new(spot.X, 2.5, spot.Z) * UPRIGHT, band)
	end

	-- Zones: where players walk (the lanes and the plazas joining them) and
	-- each team's spawn area.
	marker(zones, "LaneLeft", Vector3.new(52, 10, 160), CFrame.new(-53, 5, 0))
	marker(zones, "LaneCenter", Vector3.new(50, 10, 160), CFrame.new(0, 5, 0))
	marker(zones, "LaneRight", Vector3.new(52, 10, 160), CFrame.new(53, 5, 0))
	local stinkerZone = marker(zones, "SpawnZone", Vector3.new(52, 10, 24), CFrame.new(0, 5, -68))
	stinkerZone:SetAttribute("TeamId", "Stinkers")
	local sharterZone = marker(zones, "SpawnZone", Vector3.new(52, 10, 24), mirror(CFrame.new(0, 5, -68)))
	sharterZone:SetAttribute("TeamId", "Sharters")

	-- Fixed views for the home screen's live battlefield, all from outside
	-- the walls so they show the whole field and favour nobody.
	local views = {
		{ Vector3.new(-100, 70, -100), Vector3.new(0, 0, 0) },
		{ Vector3.new(110, 45, 0), Vector3.new(0, 4, 0) },
		{ Vector3.new(100, 70, 100), Vector3.new(0, 0, 0) },
		{ Vector3.new(0, 120, -20), Vector3.new(0, 0, 0) },
	}
	for i, view in views do
		marker(cameras, `View{i}`, Vector3.new(1, 1, 1), CFrame.lookAt(view[1], view[2]))
	end

	marker(model, "Bounds", entry.bounds.size, CFrame.new(entry.bounds.center))
	model.PrimaryPart = model:FindFirstChild("Bounds") :: BasePart
	return model
end

return {
	id = "BrainrotBattlefield",
	build = build,
	mirror = mirror,
}
