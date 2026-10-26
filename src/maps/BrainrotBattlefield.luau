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
-- Gas barrels sit in the contested middle, never by a spawn; each is a
-- GasBarrel model (Barrel and Band) that BarrelService makes explosive.
-- The pieces (mirroring, pads, barrels, markers, the control zone) come
-- from MapKit, so the next arena is built the same way.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared.Config.MapConfig)

local HALF = 80 -- half the arena's width and length
local BOUNDARY_HEIGHT = 24
local SPAWN_WALL_HEIGHT = 16
local DIVIDER_HEIGHT = 14
local DIVIDER_X = 26
-- Divider wall segments along Z (the gaps between them join the lanes).
local DIVIDER_SEGMENTS = { { -45, -24 }, { -12, 12 }, { 24, 45 } }
local MapKit = require(script.Parent.MapKit)
local UPRIGHT = MapKit.UPRIGHT
local mirror = MapKit.mirror
local folder = MapKit.folder
local part = MapKit.part
local marker = MapKit.marker
local pair = MapKit.pair
local cylinder = MapKit.cylinder

type Props = MapKit.Props

local function build(entry: MapConfig.MapEntry): Model
	local theme = entry.theme
	local model = Instance.new("Model")
	model.Name = "BrainrotBattlefield"

	local floorFolder = folder("Floor", model)
	local walls = folder("Walls", model)
	local cover = folder("Cover", model)
	local barrels = folder("Barrels", model)
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

	MapKit.spawnPads(spawns, { -15, -5, 5, 15 }, -66)

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
	for _, spot in {
		Vector3.new(66, 0, -12),
		Vector3.new(70, 0, -16),
		Vector3.new(-70, 0, -14),
		Vector3.new(12, 0, -16),
		Vector3.new(-18, 0, -14),
		Vector3.new(36, 0, -28),
	} do
		MapKit.gasBarrels(barrels, spot, theme)
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
	-- Gas Control's zone: Porcelain Plaza around the throne (the same
	-- distance from both spawns), and the floor ring that shows who holds
	-- it (hidden unless a zone mode is on).
	MapKit.controlZone(zones, floorFolder, Vector3.zero, Vector3.new(36, 12, 40), theme)

	-- Fixed views for the home screen's live battlefield, all from outside
	-- the walls so they show the whole field and favour nobody.
	local views = {
		{ Vector3.new(-100, 70, -100), Vector3.new(0, 0, 0) },
		{ Vector3.new(110, 45, 0), Vector3.new(0, 4, 0) },
		{ Vector3.new(100, 70, 100), Vector3.new(0, 0, 0) },
		{ Vector3.new(0, 120, -20), Vector3.new(0, 0, 0) },
	}
	MapKit.cameraViews(cameras, views)

	marker(model, "Bounds", entry.bounds.size, CFrame.new(entry.bounds.center))
	model.PrimaryPart = model:FindFirstChild("Bounds") :: BasePart
	return model
end

return {
	id = "BrainrotBattlefield",
	build = build,
	mirror = mirror,
}
