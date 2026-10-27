-- Uploads the Blender meshes (src/shared/MeshData) to Roblox as Mesh assets,
-- owned by whoever is logged in to Studio, so the game can use real mesh
-- assets instead of building them at runtime. Run from Studio's command bar
-- (AssetService:CreateAssetAsync works there and in local plugins, not in
-- the Assistant or in game), with the repository served on localhost:
--
--   python3 -m http.server 34999 --bind 127.0.0.1      (in the repository)
--
-- then paste into View > Command Bar:
--
--   local H = game:GetService("HttpService") local was = H.HttpEnabled H.HttpEnabled = true local s = H:GetAsync("http://127.0.0.1:34999/scripts/upload_meshes.luau") H.HttpEnabled = was loadstring(s)()
--
-- Each asset ID is kept in ServerStorage.FWMeshAssetIds (JSON, "<set>/<mesh>"
-- = id) as it's made, so a run that stops can be started again and skips
-- what's done. Copy the IDs into src/shared/Config/MeshAssets.luau, then
-- delete the StringValue. Roblox allows 30 uploads a minute.
local Http = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local ServerStorage = game:GetService("ServerStorage")

local BASE = "http://127.0.0.1:34999/"
local SETS = { "Props", "GasBlaster", "Spritzer", "StinkLobber", "Thunderclapper", "Shots" }
local GAP_SECONDS = 2.1

local wasEnabled = Http.HttpEnabled
Http.HttpEnabled = true
local builderSource = Http:GetAsync(BASE .. "src/shared/MeshBuilder.luau")
local sources = {}
for _, set in SETS do
	sources[set] = Http:GetAsync(BASE .. "src/shared/MeshData/" .. set .. ".luau")
end
Http.HttpEnabled = wasEnabled

-- MeshBuilder for its decoder, with a stand-in for the Signal it requires.
local load = assert(loadstring(builderSource, "MeshBuilder"))
setfenv(load, setmetatable({
	script = { Parent = {} },
	require = function()
		return { new = function() return { Fire = function() end } end }
	end,
}, { __index = getfenv() }))
local MeshBuilder = load()

local store = ServerStorage:FindFirstChild("FWMeshAssetIds")
if not store then
	store = Instance.new("StringValue")
	store.Name = "FWMeshAssetIds"
	store.Value = "{}"
	store.Parent = ServerStorage
end
local ids = Http:JSONDecode(store.Value)

local function build(entry): EditableMesh
	local positions, normals, corners = MeshBuilder.decode(entry)
	local mesh = AssetService:CreateEditableMesh()
	assert(mesh, "Studio has no memory left for meshes; restart it and run this again")
	local vertexIds, normalIds = {}, {}
	for i, position in positions do
		vertexIds[i] = mesh:AddVertex(position)
		normalIds[i] = mesh:AddNormal(normals[i])
	end
	for i = 1, #corners, 3 do
		local a, b, c = corners[i], corners[i + 1], corners[i + 2]
		local face = mesh:AddTriangle(vertexIds[a], vertexIds[b], vertexIds[c])
		mesh:SetFaceNormals(face, { normalIds[a], normalIds[b], normalIds[c] })
	end
	return mesh
end

local made, skipped, failed = 0, 0, 0
for _, set in SETS do
	local entries = assert(loadstring(sources[set], set))()
	local names = {}
	for name in entries do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local key = `{set}/{name}`
		if ids[key] then
			skipped += 1
			continue
		end
		local mesh = build(entries[name])
		local ok, result, detail = pcall(function()
			return AssetService:CreateAssetAsync(mesh, Enum.AssetType.Mesh, {
				Name = `FartWars {set} {name}`,
				Description = `Fart Wars: the {name} mesh ({set}), generated from art/blender in the Fart-Wars repository.`,
			})
		end)
		mesh:Destroy()
		if ok and result == Enum.CreateAssetResult.Success then
			ids[key] = detail
			store.Value = Http:JSONEncode(ids)
			made += 1
			print(`[FW upload] {key} = {detail}`)
		else
			failed += 1
			warn(`[FW upload] {key} failed: {if ok then `{result} {detail}` else result}`)
			if not ok and string.find(tostring(result), "not available", 1, true) then
				warn("[FW upload] CreateAssetAsync is off: File > Beta Features > CreateAssetAsync Luau API, then restart Studio")
				break
			end
		end
		task.wait(GAP_SECONDS)
	end
end
print(`[FW upload] done: {made} uploaded, {skipped} already done, {failed} failed`)
