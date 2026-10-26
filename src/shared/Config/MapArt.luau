-- Which map parts the Blender props dress (MapDressing). The meshes come
-- from art/blender/build_props.py (PropArt has their sizes); each part
-- named here gets its prop drawn exactly over it, coloured like the part,
-- while the part itself stays as the invisible hitbox. A prop modelled on
-- one part can dress others of a different size: it is stretched to fit.
-- A prop PropArt marks as a module (`tile`: walls, trims, floors) is
-- repeated along the part instead, as many times as fit, each stretched
-- a little to come out even, so a 164-stud wall isn't one stretched mesh.
--   mesh   the prop (a PropArt name)
--   turn   degrees about the part's up axis from the part to the mesh, for
--          a part whose front isn't its -Z (the mesh's size follows)
--   long   turn the mesh a further 90 degrees when the part is longer
--          along Z than X, so a wall module runs along the wall
--   face   "away": the mesh's front (its -Z) faces away from the centre
--          line z = 0, so the mirrored half's copy turns round instead of
--          facing the wrong way (MapKit.mirror can't turn a mesh round)
export type Rule = { mesh: string, turn: number?, long: boolean?, face: "away"? }

local MapArt = {}

MapArt.parts = {
	-- Porcelain Plaza's throne: two toilets back to back.
	ThroneTank = { mesh = "ToiletTank", face = "away" },
	ThroneLid = { mesh = "TankLid" },
	ThroneBowl = { mesh = "ToiletBowl" },
	ThroneSeat = { mesh = "ToiletSeat" },
	-- Gas Gutter's sideways toilet: its bowl is to the tank's -X.
	GutterTank = { mesh = "ToiletTank", turn = 90 },
	GutterBowl = { mesh = "ToiletBowl" },
	-- Bean Alley.
	BeanCan = { mesh = "BeanCan" },
	BeanLabel = { mesh = "BeanLabel" },
	-- Cover.
	PlazaWall = { mesh = "CoverWall" },
	AlleyWall = { mesh = "CoverWall" },
	Crate = { mesh = "Crate" },
	-- Inside each GasBarrel model.
	Barrel = { mesh = "GasBarrel" },
	Band = { mesh = "BarrelBand" },
	-- Walls (modules along the wall) and the neon trims on top of them.
	SideWall = { mesh = "TallWall", long = true },
	EndWall = { mesh = "TallWall", long = true },
	Divider = { mesh = "Wall", long = true },
	SpawnFront = { mesh = "Wall", long = true },
	SpawnSide = { mesh = "Wall", long = true },
	SpawnBack = { mesh = "Wall", long = true },
	SideTrim = { mesh = "WallTrim", long = true },
	EndTrim = { mesh = "WallTrim", long = true },
	SpawnFrontTrim = { mesh = "WallTrim", long = true },
	-- Floors (modules both ways).
	Ground = { mesh = "GroundTile" },
	LaneCenterFloor = { mesh = "PlazaTiles" },
	LaneLeftFloor = { mesh = "Flagstones" },
	LaneRightFloor = { mesh = "Flagstones" },
	SpawnFloor = { mesh = "SpawnTiles" },
	-- The SpawnLocations.
	Pad1 = { mesh = "SpawnPad" },
	Pad2 = { mesh = "SpawnPad" },
	Pad3 = { mesh = "SpawnPad" },
	Pad4 = { mesh = "SpawnPad" },
} :: { [string]: Rule }

-- The Bean Rain pickup (EventService).
MapArt.BEAN = "Bean"

return MapArt
