-- The contract every map keeps, so maps can be swapped (and later rotated)
-- without touching the round, team or player code. A map is a Model with:
--   Spawns/<teamId>   SpawnLocations for each team; MapConfig.spawns names
--                     the folder, and there is at least one per team
--   CameraPoints      invisible Parts; each CFrame is a fixed spectator view
--   Bounds            an invisible, non-colliding Part covering the playable box
--   Zones (optional)  invisible marker Parts: lanes, spawn zones, cover lines
-- Every BasePart is anchored. A map module in ServerStorage.Maps returns a
-- MapDefinition; a Model there is used as it is.
local MapConfig = require(script.Parent.Parent.Config.MapConfig)

export type MapDefinition = {
	id: string,
	build: (entry: MapConfig.MapEntry) -> Model,
}

local MapBase = {}

local function resolve(model: Instance, path: string): Instance?
	local current: Instance? = model
	for _, name in string.split(path, "/") do
		current = current and current:FindFirstChild(name)
	end
	return current
end
MapBase.resolve = resolve

-- A team's SpawnLocations, in name order so every server picks the same way.
function MapBase.spawns(model: Instance, entry: MapConfig.MapEntry, teamId: string): { SpawnLocation }
	local folder = entry.spawns[teamId] and resolve(model, entry.spawns[teamId])
	local spawns = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("SpawnLocation") then
				table.insert(spawns, child)
			end
		end
	end
	table.sort(spawns, function(a, b)
		return a.Name < b.Name
	end)
	return spawns
end

function MapBase.cameraPoints(model: Instance): { BasePart }
	local folder = model:FindFirstChild("CameraPoints")
	local points = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(points, child)
			end
		end
	end
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	return points
end

local function inside(position: Vector3, bounds: BasePart): boolean
	local lo = bounds.Position - bounds.Size / 2
	local hi = bounds.Position + bounds.Size / 2
	return position.X >= lo.X and position.X <= hi.X and position.Y >= lo.Y and position.Y <= hi.Y
		and position.Z >= lo.Z and position.Z <= hi.Z
end

-- Everything wrong with a map, so a broken one never reaches a round.
function MapBase.validate(model: Instance, entry: MapConfig.MapEntry, teamIds: { string }): (boolean, { string })
	local problems = {}
	local bounds = model:FindFirstChild("Bounds")
	if not (bounds and bounds:IsA("BasePart")) then
		table.insert(problems, "no Bounds part")
		bounds = nil
	end
	for _, teamId in teamIds do
		local spawns = MapBase.spawns(model, entry, teamId)
		if #spawns == 0 then
			table.insert(problems, `no SpawnLocations for {teamId} at {entry.spawns[teamId] or "(no path)"}`)
		end
		for _, spawn in spawns do
			if bounds and not inside(spawn.Position, bounds :: BasePart) then
				table.insert(problems, `{spawn:GetFullName()} is outside the bounds`)
			end
		end
	end
	if #MapBase.cameraPoints(model) == 0 then
		table.insert(problems, "no CameraPoints")
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and not item.Anchored then
			table.insert(problems, `{item:GetFullName()} isn't anchored`)
		end
	end
	return #problems == 0, problems
end

function MapBase.isDefinition(value: any): boolean
	return type(value) == "table" and type(value.id) == "string" and type(value.build) == "function"
end

return MapBase
