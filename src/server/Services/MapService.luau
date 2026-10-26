-- Puts the map in Workspace and answers questions about it. The template
-- comes from ServerStorage.Maps: a Model made in Studio is cloned as it is;
-- a ModuleScript (like the code-built BrainrotBattlefield) builds one. Either
-- way it has to pass Interfaces/MapBase before anyone plays on it, and its
-- SpawnLocations are set up for their team here, so a Studio-made map only
-- needs the parts in the right folders.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared.Config.MapConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local MapBase = require(Shared.Interfaces.MapBase)
local Signal = require(Shared.Signal)
local MapDressing = require(script.Parent.Parent.MapDressing)

local MapService = {}

-- Fires with the new map once it is in Workspace.
MapService.Loaded = Signal.new()

MapService.random = Random.new()

local current: Model? = nil
local currentEntry: MapConfig.MapEntry? = nil

local function prepareSpawns(model: Model, entry: MapConfig.MapEntry)
	for _, teamId in TeamConfig.order do
		for _, spawn in MapBase.spawns(model, entry, teamId) do
			spawn.TeamColor = BrickColor.new(TeamConfig.teams[teamId].brickColor :: any)
			spawn.Neutral = false
			spawn.AllowTeamChangeOnTouch = false
			-- Spawn protection arrives with combat in Phase 2.
			spawn.Duration = 0
			spawn.Enabled = true
			spawn:SetAttribute("TeamId", teamId)
		end
	end
end

local function applyTheme(theme: MapConfig.Theme)
	Lighting.Ambient = theme.ambient
	Lighting.OutdoorAmbient = theme.outdoorAmbient
	Lighting.ClockTime = theme.clockTime
	Lighting.Brightness = theme.brightness
end

-- Builds or clones the map, checks it and swaps it in for the old one.
-- Errors (and leaves the old map) when the map breaks the contract.
function MapService.load(mapId: string): Model
	local entry = MapConfig[mapId]
	assert(entry, `no MapConfig entry "{mapId}"`)
	local maps = ServerStorage:WaitForChild("Maps")
	local template = maps:FindFirstChild(entry.template)
	assert(template, `no ServerStorage.Maps.{entry.template} for map "{mapId}"`)

	local model: Model
	if template:IsA("ModuleScript") then
		local definition = require(template) :: any
		assert(MapBase.isDefinition(definition), `{template:GetFullName()} doesn't return a MapDefinition`)
		model = definition.build(entry)
	elseif template:IsA("Model") then
		model = template:Clone()
	else
		error(`{template:GetFullName()} is a {template.ClassName}; expected a Model or a ModuleScript`)
	end
	model.Name = "Map"
	model:SetAttribute("MapId", entry.id)
	prepareSpawns(model, entry)

	local ok, problems = MapBase.validate(model, entry, TeamConfig.order)
	if not ok then
		model:Destroy()
		error(`map "{mapId}" breaks the MapBase contract:\n  ` .. table.concat(problems, "\n  "))
	end
	-- The Blender props over the parts they dress; the parts stay as the
	-- hitboxes, so play is the same with or without them.
	MapDressing.dress(model)

	if current then
		current:Destroy()
	end
	-- The whole map stays with every client, even if the place has
	-- streaming on: spectators have no avatar to stream around.
	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	model.Parent = workspace
	current, currentEntry = model, entry
	applyTheme(entry.theme)
	MapService.Loaded:Fire(model, entry)
	return model
end

function MapService.current(): (Model?, MapConfig.MapEntry?)
	return current, currentEntry
end

function MapService.spawns(teamId: string): { SpawnLocation }
	if not (current and currentEntry) then
		return {}
	end
	return MapBase.spawns(current, currentEntry, teamId)
end

-- The team's SpawnLocation farthest from every enemy (any of them when no
-- enemies are on the map), so nobody appears next to the other team.
function MapService.safeSpawn(teamId: string, enemyPositions: { Vector3 }): SpawnLocation?
	local best, bestDistance = {}, -math.huge
	for _, spawn in MapService.spawns(teamId) do
		local nearest = math.huge
		for _, position in enemyPositions do
			nearest = math.min(nearest, (position - spawn.Position).Magnitude)
		end
		if #best == 0 or nearest > bestDistance + 1e-6 then
			best, bestDistance = { spawn }, nearest
		elseif nearest >= bestDistance - 1e-6 then
			table.insert(best, spawn)
		end
	end
	if #best == 0 then
		return nil
	end
	return best[MapService.random:NextInteger(1, #best)]
end

function MapService.cameraPoints(): { BasePart }
	return if current then MapBase.cameraPoints(current) else {}
end

return MapService
