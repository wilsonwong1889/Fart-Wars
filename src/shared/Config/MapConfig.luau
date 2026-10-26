-- One entry per map. MapService builds or clones `template` from
-- ServerStorage.Maps (a Model made in Studio, or a ModuleScript that builds
-- one), checks it against Interfaces/MapBase and puts it in Workspace.
--   spawns: the folder inside the map that holds each team's SpawnLocations
--   scale: how many times bigger the map is built than its layout's
--     numbers (the builder lays it out, then MapKit.scale grows it)
--   bounds: the playable box, centred on `center`, at full size
--   modes: the game modes the layout supports
--   zone: the control zone's marker Part (for zone modes such as Gas
--     Control), and the floor ring that shows who holds it
--   theme: lighting and the palette the builder paints with (bright toy
--     colours on studded plastic, like building bricks)
export type Theme = {
	ground: Color3,
	wall: Color3,
	wallTop: Color3,
	trim: Color3,
	crate: Color3,
	lanes: { Left: Color3, Center: Color3, Right: Color3 },
	porcelain: Color3,
	bean: Color3,
	beanLabel: Color3,
	barrel: Color3,
	barrelBand: Color3,
	ambient: Color3,
	outdoorAmbient: Color3,
	clockTime: number,
	brightness: number,
}

export type MapEntry = {
	id: string,
	displayName: string,
	template: string,
	spawns: { [string]: string },
	scale: number,
	bounds: { center: Vector3, size: Vector3 },
	modes: { string },
	zone: string?,
	zoneRing: string?,
	theme: Theme,
}

local maps: { [string]: MapEntry } = {
	BrainrotBattlefield = table.freeze({
		id = "BrainrotBattlefield",
		displayName = "Brainrot Battlefield",
		template = "BrainrotBattlefield",
		spawns = table.freeze({ Stinkers = "Spawns/Stinkers", Sharters = "Spawns/Sharters" }),
		-- Three times the 160-stud layout, room for 20 (avatars stay their size).
		scale = 3,
		bounds = table.freeze({ center = Vector3.new(0, 90, 0), size = Vector3.new(480, 180, 480) }),
		modes = table.freeze({ "TeamElimination", "GasControl" }),
		-- Porcelain Plaza, around the throne.
		zone = "Zones/ControlZone",
		zoneRing = "Floor/ControlZoneFloor",
		theme = table.freeze({
			ground = Color3.fromRGB(88, 196, 64), -- grass-green baseplate
			wall = Color3.fromRGB(236, 132, 124), -- salmon brick
			wallTop = Color3.fromRGB(96, 214, 74), -- grassy plates on the walls
			trim = Color3.fromRGB(176, 140, 255), -- the throne's lid and seat
			crate = Color3.fromRGB(245, 146, 64),
			lanes = table.freeze({
				Left = Color3.fromRGB(255, 200, 150), -- Bean Alley
				Center = Color3.fromRGB(204, 198, 246), -- Porcelain Plaza
				Right = Color3.fromRGB(58, 170, 76), -- Gas Gutter
			}),
			porcelain = Color3.fromRGB(250, 250, 250),
			bean = Color3.fromRGB(255, 122, 44),
			beanLabel = Color3.fromRGB(255, 222, 92),
			barrel = Color3.fromRGB(64, 176, 84),
			barrelBand = Color3.fromRGB(222, 255, 72),
			ambient = Color3.fromRGB(150, 150, 165),
			outdoorAmbient = Color3.fromRGB(190, 190, 205),
			clockTime = 13,
			brightness = 2.5,
		}),
	}),
}

return table.freeze(maps)
