-- Dresses the map in the Blender props on this client when the server
-- couldn't (they aren't imported): builds the packed meshes once
-- (MeshBuilder, MeshData/Props) and dresses each map as it arrives
-- (MapDressing.dressRuntime). Nothing here replicates or changes what the
-- server sees; the map's parts stay the hitboxes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MeshBuilder = require(Shared.MeshBuilder)
local MapDressing = require(Shared.MapDressing)

local MapArtController = {}

-- A second pass this long after a map arrives, for any part that
-- replicated after the rest.
MapArtController.SETTLE_SECONDS = 2

local started = false

local function currentMap(): Instance?
	local map = workspace:FindFirstChild("Map")
	return if map and map:IsA("Model") then map else nil
end

-- Dresses `map` if the meshes are built (and starts building them if not).
-- Builds nothing when the server already dressed it with imports, so the
-- small mesh budget stays for what needs it.
function MapArtController.dress(map: Instance): number
	if not MapDressing.needsDressing(map) then
		return 0
	end
	MeshBuilder.request(MapDressing.SET)
	return MapDressing.dressRuntime(map)
end

function MapArtController.start()
	if started then
		return
	end
	started = true
	MeshBuilder.built:Connect(function(set)
		local map = currentMap()
		if set == MapDressing.SET and map and MapDressing.needsDressing(map) then
			MapDressing.dressRuntime(map)
		end
	end)
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Map" and child:IsA("Model") then
			task.defer(MapArtController.dress, child)
			task.delay(MapArtController.SETTLE_SECONDS, function()
				if child.Parent then
					MapArtController.dress(child)
				end
			end)
		end
	end)
	local map = currentMap()
	if map then
		MapArtController.dress(map)
	end
end

return MapArtController
