-- The two teams. `id` is what the code and remotes use; `name` is what
-- players see. `brickColor` is the Roblox Team colour (the player list and
-- SpawnLocations match on it); `color` is the exact UI colour.
export type Team = {
	id: string,
	name: string,
	shortName: string,
	color: Color3,
	darkColor: Color3,
	brickColor: string,
}

local teams: { [string]: Team } = {
	Stinkers = table.freeze({
		id = "Stinkers",
		name = "Skibidi Stinkers",
		shortName = "STINKERS",
		color = Color3.fromRGB(102, 255, 51), -- toxic green
		darkColor = Color3.fromRGB(28, 92, 16),
		brickColor = "Lime green",
	}),
	Sharters = table.freeze({
		id = "Sharters",
		name = "Sigma Sharters",
		shortName = "SHARTERS",
		color = Color3.fromRGB(255, 221, 26), -- bright yellow
		darkColor = Color3.fromRGB(110, 92, 0),
		brickColor = "New Yeller",
	}),
}

return table.freeze({
	-- Display order: left side of the HUD first.
	order = table.freeze({ "Stinkers", "Sharters" }),
	teams = table.freeze(teams),
})
