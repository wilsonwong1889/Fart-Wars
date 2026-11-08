-- Brainrot Battlefield v0: the Phase 1 blockout, built from code so it lives
-- in Git. A Model named BrainrotBattlefield placed here in Studio replaces it
-- (MapService uses whichever is in ServerStorage.Maps).
--
-- Laid out on a 160 x 160 grid, then built MapConfig's `scale` times bigger
-- (480 x 480 studs at 3; every number below is the layout's). Ground at
-- y = 0. The Skibidi Stinkers spawn at the -Z end
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
-- Low cover (the plaza and alley walls, the crates) is laid out at avatar
-- height and marked KeepHeight, so the scaling spreads it across but
-- leaves it that low: something to duck behind, shoot past and lob
-- over. The tall cover (the throne, the bean cans, the Gutter's toilet),
-- the dividers and the walls grow with everything else.
-- Each lane has a gate across its entrance, up on the walls' tops out of
-- everyone's reach: its name on a sign that reads both ways, in its own
-- colours and light, under a landmark (a bean can, a toilet roll, a gas
-- vent), so you know where you are on a field this big.
-- Launch pads (FeatureFlags.LAUNCH_PADS) fart you forward and up, so a
-- fight comes sooner without the map shrinking: four a half, at the start
-- of each side lane and at the spawn room's front corners.
-- The pieces (mirroring, pads, barrels, launch pads, markers, the control
-- zone, signs) come from MapKit, so the next arena is built the same way.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared.Config.MapConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)

local HALF = 80 -- half the arena's width and length
local BOUNDARY_HEIGHT = 24
local SPAWN_WALL_HEIGHT = 16
local DIVIDER_HEIGHT = 14
local DIVIDER_X = 26
-- Divider wall segments along Z (the gaps between them join the lanes).
local DIVIDER_SEGMENTS = { { -45, -24 }, { -12, 12 }, { 24, 45 } }
-- Low walls: an avatar's height, which is what the Blender cover wall is
-- modelled at (PropArt's CoverWall), so its mesh only stretches across.
local LOW_WALL_HEIGHT = 5
-- The lane gates: across the lanes just inside where the dividers start,
-- their beams' tops level with the side walls'.
local GATE_Z = -42
local GATE_TOP = BOUNDARY_HEIGHT
local MapKit = require(script.Parent.MapKit)
local UPRIGHT = MapKit.UPRIGHT
local mirror = MapKit.mirror
local folder = MapKit.folder
local part = MapKit.part
local marker = MapKit.marker
local pair = MapKit.pair
local cylinder = MapKit.cylinder
local decor = MapKit.decor

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

	-- Studded plastic, like building bricks (MapKit studs plastic blocks).
	local wall: Props = { Color = theme.wall, Material = Enum.Material.Plastic }
	local wallTop: Props = { Color = theme.wallTop, Material = Enum.Material.Plastic }
	local trim: Props = { Color = theme.trim, Material = Enum.Material.Neon }
	-- Low cover keeps its layout height when the map is scaled up.
	local lowWall: Props = { Color = theme.wall, Material = Enum.Material.Plastic, KeepHeight = true }

	-- Ground and the three lane strips (colour only; they're walkable too).
	part(floorFolder, "Ground", Vector3.new(HALF * 2, 4, HALF * 2), CFrame.new(0, -2, 0), {
		Color = theme.ground,
		Material = Enum.Material.Plastic,
	})
	for name, x in { Left = -53, Center = 0, Right = 53 } do
		part(floorFolder, `Lane{name}Floor`, Vector3.new(if name == "Center" then 50 else 52, 0.2, 90), CFrame.new(x, 0.1, 0), {
			Color = theme.lanes[name],
			Material = Enum.Material.Plastic,
		})
	end

	-- Boundary: the ends are mirrored; each side wall spans both halves,
	-- corners included, and the end walls and trims stop against them, so
	-- no two walls overlap (overlapping faces flicker).
	pair(walls, "EndWall", Vector3.new(HALF * 2, BOUNDARY_HEIGHT, 2), CFrame.new(0, BOUNDARY_HEIGHT / 2, -HALF - 1), wall)
	for _, x in { -HALF - 1, HALF + 1 } do
		part(walls, "SideWall", Vector3.new(2, BOUNDARY_HEIGHT, HALF * 2 + 4), CFrame.new(x, BOUNDARY_HEIGHT / 2, 0), wall)
		part(walls, "SideTrim", Vector3.new(2.4, 1, HALF * 2 + 4.4), CFrame.new(x, BOUNDARY_HEIGHT + 0.5, 0), wallTop)
	end
	pair(walls, "EndTrim", Vector3.new(HALF * 2 - 0.4, 1, 2.4), CFrame.new(0, BOUNDARY_HEIGHT + 0.5, -HALF - 1), wallTop)

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
	-- The front stops against the side walls (which fill the corners), so
	-- the two don't overlap.
	pair(walls, "SpawnFront", Vector3.new(48, SPAWN_WALL_HEIGHT, 2), CFrame.new(0, SPAWN_WALL_HEIGHT / 2, -57), wall)
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

	-- Cover comes in two heights. Tall cover (the throne, the bean cans, the
	-- Gutter's toilet) hides you whole and grows with the map like the
	-- walls. Low cover (the plaza and alley walls, the crates) is laid out
	-- at an avatar's height and keeps it: you duck behind it, shoot past
	-- its ends or jump to fire over it, and a lob clears it easily. Grown
	-- 3x it would have been 15-18 studs of wall nobody could see past.

	-- Porcelain Plaza: the throne (two giant toilets back to back across the
	-- centre line) and low cover on the way to it.
	local porcelain = cylinder(theme.porcelain)
	pair(cover, "ThroneTank", Vector3.new(16, 14, 4), CFrame.new(0, 7, -2), { Color = theme.porcelain, Material = Enum.Material.SmoothPlastic })
	pair(cover, "ThroneLid", Vector3.new(17, 1, 5), CFrame.new(0, 14.5, -2), trim)
	pair(cover, "ThroneBowl", Vector3.new(6, 12, 12), CFrame.new(0, 3, -10) * UPRIGHT, porcelain)
	pair(cover, "ThroneSeat", Vector3.new(1, 13, 13), CFrame.new(0, 6.5, -10) * UPRIGHT, cylinder(theme.trim, Enum.Material.Neon))
	for _, spot in { Vector3.new(-14, 0, -30), Vector3.new(14, 0, -22), Vector3.new(-6, 0, -44) } do
		pair(cover, "PlazaWall", Vector3.new(10, LOW_WALL_HEIGHT, 2), CFrame.new(spot.X, LOW_WALL_HEIGHT / 2, spot.Z), lowWall)
	end

	-- Bean Alley: bean cans tall enough to hide behind, with a label band,
	-- and a low wall (as low as the plaza's, so the same mesh fits it).
	local bean = cylinder(theme.bean)
	local label = cylinder(theme.beanLabel)
	for _, spot in { Vector3.new(-53, 0, -32), Vector3.new(-40, 0, -14), Vector3.new(-66, 0, -6) } do
		pair(cover, "BeanCan", Vector3.new(10, 8, 8), CFrame.new(spot.X, 5, spot.Z) * UPRIGHT, bean)
		pair(cover, "BeanLabel", Vector3.new(4, 8.4, 8.4), CFrame.new(spot.X, 5, spot.Z) * UPRIGHT, label)
	end
	pair(cover, "AlleyWall", Vector3.new(14, LOW_WALL_HEIGHT, 2), CFrame.new(-56, LOW_WALL_HEIGHT / 2, -20), lowWall)

	-- Gas Gutter: a sideways toilet, crates, and barrel clusters (decor).
	-- The crates are low cover at the 6 studs the Blender crate is modelled
	-- at: just over an avatar's head, low enough to jump onto or lob over.
	pair(cover, "GutterTank", Vector3.new(4, 10, 12), CFrame.new(60, 5, -26), { Color = theme.porcelain, Material = Enum.Material.SmoothPlastic })
	pair(cover, "GutterBowl", Vector3.new(5, 9, 9), CFrame.new(54, 2.5, -26) * UPRIGHT, porcelain)
	for _, spot in { Vector3.new(40, 0, -36), Vector3.new(46, 0, -8) } do
		pair(cover, "Crate", Vector3.new(8, 6, 8), CFrame.new(spot.X, 3, spot.Z), {
			Color = theme.crate,
			Material = Enum.Material.Plastic,
			KeepHeight = true,
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

	-- Launch pads: giant whoopee cushions that fart whoever steps on one
	-- along a fixed arc to its landing spot (LaunchPads), each half's
	-- mirrored onto the other. Two catch players coming out of the spawn
	-- corridor up a side lane, at its start beside the spawn room, and
	-- throw them up the lane to just short of its gap into the plaza; two
	-- sit in front of the spawn room at its corners, where the walk from
	-- the corridors comes round, and throw them into Porcelain Plaza short
	-- of the throne. The side lanes' stand off the spawn room's side walls,
	-- so the walk round to the plaza pads passes them by. Every arc stays
	-- on its own half, under the gates, clear of the walls and cover, and
	-- lands on open ground (the Map spec flies them all).
	if FeatureFlags.LAUNCH_PADS then
		local pads = folder("LaunchPads", model)
		MapKit.launchPad(pads, "Alley", Vector3.new(-34, 0, -62), Vector3.new(-33, 0, -22), 10)
		MapKit.launchPad(pads, "Gutter", Vector3.new(34, 0, -62), Vector3.new(30, 0, -22), 10)
		MapKit.launchPad(pads, "PlazaLeft", Vector3.new(-21, 0, -51), Vector3.new(-4, 0, -26), 9)
		MapKit.launchPad(pads, "PlazaRight", Vector3.new(21, 0, -51), Vector3.new(4, 0, -26), 9)
	end

	-- Lane gates (Landmarks): one across each half's lane entrances at
	-- z = GATE_Z, resting on the dividers' and side walls' tops. Coming out
	-- of a spawn's corridor into a side lane you see that lane's sign up
	-- ahead; the plaza's shows through the gaps beside the spawn room. Each
	-- sign reads both ways, so a lane has its name from either end. It is
	-- all decor (MapKit.decor) and all of it is above the dividers, out of
	-- everyone's reach: it never blocks a shot, a path or a line of sight
	-- anyone plays along, nobody can get stuck in it, and the walls still
	-- do all the hiding of the spawns (their sightline check counts only
	-- walls and cover).
	local landmarks = folder("Landmarks", model)
	local BEAM = 2 -- the beams' and the pipe's thickness
	local DEPTH = 4 -- the posts', beams' and roll's depth along Z
	local SIGN_BOTTOM = 16 -- two studs above the dividers
	-- A side lane's beam spans from its divider post to the side wall.
	local sideX = (HALF + DIVIDER_X + 1) / 2
	local sideLength = HALF - DIVIDER_X - 1
	local beamY = GATE_TOP - BEAM / 2

	-- A post on each divider's top, carrying the beams on either side.
	local postHeight = GATE_TOP + 2 - DIVIDER_HEIGHT
	for _, x in { -DIVIDER_X, DIVIDER_X } do
		pair(landmarks, "GatePost", Vector3.new(2, postHeight, DEPTH), CFrame.new(x, DIVIDER_HEIGHT + postHeight / 2, GATE_Z), decor(theme.wall, Enum.Material.Plastic))
	end

	-- A lane's sign hanging at `x` from its gate down to SIGN_BOTTOM, with a
	-- neon trim along its bottom that lights it in the lane's accent colour.
	local function laneSign(name: string, text: string, x: number, width: number, top: number, board: Color3, words: Color3, accent: Color3)
		local height = top - SIGN_BOTTOM
		local signs = { pair(landmarks, `{name}Sign`, Vector3.new(width, height, 1), CFrame.new(x, SIGN_BOTTOM + height / 2, GATE_Z), decor(board)) }
		for _, sign in signs do
			MapKit.sign(sign, text, words)
		end
		local glows = { pair(landmarks, `{name}Glow`, Vector3.new(width + 0.4, 0.6, 1.2), CFrame.new(x, SIGN_BOTTOM - 0.3, GATE_Z), decor(accent, Enum.Material.Neon, { CastShadow = false })) }
		for _, glow in glows do
			MapKit.light(glow, accent, 20)
		end
	end

	-- Bean Alley: a brick beam, an orange sign, and a giant bean can on top.
	pair(landmarks, "AlleyBeam", Vector3.new(sideLength, BEAM, DEPTH), CFrame.new(-sideX, beamY, GATE_Z), decor(theme.wallTop, Enum.Material.Plastic))
	laneSign("Alley", "BEAN ALLEY", -sideX, 30, GATE_TOP - BEAM, theme.bean, theme.beanLabel, theme.beanLabel)
	local canAt = CFrame.new(-sideX, GATE_TOP + 4, GATE_Z) * UPRIGHT
	pair(landmarks, "AlleyCan", Vector3.new(8, 6, 6), canAt, decor(theme.bean, nil, { Shape = Enum.PartType.Cylinder }))
	pair(landmarks, "AlleyCanLabel", Vector3.new(3.5, 6.4, 6.4), canAt, decor(theme.beanLabel, nil, { Shape = Enum.PartType.Cylinder }))

	-- Porcelain Plaza: a giant toilet roll between the posts, its paper
	-- hanging down as the sign (its top tucked inside the roll).
	pair(landmarks, "PlazaRoll", Vector3.new(DIVIDER_X * 2 - 2, DEPTH, DEPTH), CFrame.new(0, GATE_TOP - DEPTH / 2, GATE_Z), decor(theme.porcelain, nil, { Shape = Enum.PartType.Cylinder }))
	laneSign("Plaza", "PORCELAIN PLAZA", 0, 30, GATE_TOP - DEPTH + 1, theme.porcelain, theme.trim, theme.trim)

	-- Gas Gutter: a gas pipe, a green sign, and a vent on top puffing gas.
	pair(landmarks, "GutterPipe", Vector3.new(sideLength, BEAM, BEAM), CFrame.new(sideX, beamY, GATE_Z), decor(theme.barrel, nil, { Shape = Enum.PartType.Cylinder }))
	laneSign("Gutter", "GAS GUTTER", sideX, 30, GATE_TOP - BEAM, theme.barrel, theme.barrelBand, theme.barrelBand)
	pair(landmarks, "GutterVent", Vector3.new(6, 3, 3), CFrame.new(sideX, GATE_TOP + 2, GATE_Z) * UPRIGHT, decor(theme.barrel, nil, { Shape = Enum.PartType.Cylinder }))
	pair(landmarks, "GutterVentRim", Vector3.new(0.6, 3.6, 3.6), CFrame.new(sideX, GATE_TOP + 4.7, GATE_Z) * UPRIGHT, decor(theme.barrelBand, Enum.Material.Neon, {
		Shape = Enum.PartType.Cylinder,
		CastShadow = false,
	}))
	local puffs = { pair(landmarks, "GutterPuff", Vector3.new(6, 6, 6), CFrame.new(sideX, GATE_TOP + 7.5, GATE_Z), decor(theme.barrelBand, Enum.Material.Neon, {
		Shape = Enum.PartType.Ball,
		Transparency = 0.35,
		CastShadow = false,
	})) }
	for _, puff in puffs do
		MapKit.light(puff, theme.barrelBand, 16)
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
	-- it (hidden unless a zone mode is on). A circle 20 out from the
	-- centre (60 at full size): the throne and the ground all round it,
	-- with room in front of and behind the bowls to get from one side to
	-- the other inside the zone, 15 short of the dividers so the gaps
	-- between the lanes stay outside it. Six high (18): standing and
	-- jumping count, flying over or up on the bowls doesn't.
	MapKit.controlZone(zones, floorFolder, Vector3.zero, 20, 6, theme)

	-- Fixed views for the home screen's live battlefield, all from outside
	-- the walls so they show the whole field and favour nobody.
	local views = {
		{ Vector3.new(-100, 70, -100), Vector3.new(0, 0, 0) },
		{ Vector3.new(110, 45, 0), Vector3.new(0, 4, 0) },
		{ Vector3.new(100, 70, 100), Vector3.new(0, 0, 0) },
		{ Vector3.new(0, 120, -20), Vector3.new(0, 0, 0) },
	}
	MapKit.cameraViews(cameras, views)

	MapKit.scale(model, entry.scale)
	-- The bounds are already full size.
	marker(model, "Bounds", entry.bounds.size, CFrame.new(entry.bounds.center))
	model.PrimaryPart = model:FindFirstChild("Bounds") :: BasePart
	return model
end

return {
	id = "BrainrotBattlefield",
	build = build,
	mirror = mirror,
}
