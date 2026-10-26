-- Which map parts the Blender props dress (MapDressing). The meshes come
-- from art/blender/build_props.py (PropArt has their sizes); each part
-- named here gets its prop drawn exactly over it, coloured like the part,
-- while the part itself stays as the invisible hitbox. A prop modelled on
-- one part can dress others of a different size: it is stretched to fit.
--   mesh   the prop (a PropArt name)
--   turn   degrees about the part's up axis from the part to the mesh, for
--          a part whose front isn't its -Z (the mesh's size follows)
--   face   "away": the mesh's front (its -Z) faces away from the centre
--          line z = 0, so the mirrored half's copy turns round instead of
--          facing the wrong way (MapKit.mirror can't turn a mesh round)
export type Rule = { mesh: string, turn: number?, face: "away"? }

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
} :: { [string]: Rule }

-- The Bean Rain pickup (EventService).
MapArt.BEAN = "Bean"

return MapArt
