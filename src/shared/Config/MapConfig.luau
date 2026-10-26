-- One entry per map. MapService builds or clones `template` from
-- ServerStorage.Maps (a Model made in Studio, or a ModuleScript that builds
-- one), checks it against Interfaces/MapBase and puts it in Workspace.
--   spawns: the folder inside the map that holds each team's SpawnLocations
--   bounds: the playable box, centred on `center`
--   modes: the game modes the layout supports
--   zone: the control zone's marker Part (for zone modes such as Gas
--     Control), and the floor ring that shows who holds it
--   theme: lighting and the palette the builder paints with
export type Theme = {
	ground: Color3,
	wall: Color3,
	trim: Color3,
	lanes: { Left: Color3, Center: Color3, Right: Color3 },
	porcelain: Color3,
	bean: Color3,
	beanLabel: Color3,
	barrel: Color3,
	barrelBand: Color3,
	ambient: Color3,
	outdoorAmbient: Color3,
	clockTime: number,
}

export type MapEntry = {
	id: string,
	displayName: string,
	template: string,
	spawns: { [string]: string },
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
		bounds = table.freeze({ center = Vector3.new(0, 30, 0), size = Vector3.new(160, 60, 160) }),
		modes = table.freeze({ "TeamElimination", "GasControl" }),
		-- Porcelain Plaza, around the throne.
		zone = "Zones/ControlZone",
		zoneRing = "Floor/ControlZoneFloor",
		theme = table.freeze({
			ground = Color3.fromRGB(86, 74, 52),
			wall = Color3.fromRGB(70, 62, 86),
			trim = Color3.fromRGB(150, 120, 200),
			lanes = table.freeze({
				Left = Color3.fromRGB(120, 92, 60), -- Bean Alley
				Center = Color3.fromRGB(196, 200, 206), -- Porcelain Plaza
				Right = Color3.fromRGB(92, 120, 70), -- Gas Gutter
			}),
			porcelain = Color3.fromRGB(240, 240, 235),
			bean = Color3.fromRGB(196, 92, 40),
			beanLabel = Color3.fromRGB(240, 210, 120),
			barrel = Color3.fromRGB(70, 110, 60),
			barrelBand = Color3.fromRGB(190, 240, 60),
			ambient = Color3.fromRGB(110, 100, 120),
			outdoorAmbient = Color3.fromRGB(140, 130, 150),
			clockTime = 14.5,
		}),
	}),
}

return table.freeze(maps)
