-- Builds the Blender meshes in the game, from the packed copies the art
-- scripts write to Shared.MeshData (art/blender/kit.py's mesh_data), so
-- the guns and the shot effects show as modelled without anyone
-- importing anything. Each mesh is built once on this machine (an
-- EditableMesh) and shown by as many MeshParts as need it.
--
-- Clients only: a mesh built on the server doesn't replicate (Roblox
-- shows a checkerboard), so the server keeps the stand-ins and each
-- client dresses them. If this device can't build meshes, everything
-- falls back to the imports or the stand-ins and status() says why: in a
-- published game EditableMesh is off until Experience Settings ⟩
-- Security ⟩ Allow Mesh / Image APIs is on, and a phone may be out of
-- memory for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(script.Parent.Signal)

local MeshBuilder = {}

export type Entry = { size: Vector3, vertices: number, triangles: number, data: string }

-- What builds the meshes and wraps one for a MeshPart: Roblox's
-- AssetService and Content.fromObject (the specs swap in stand-ins).
MeshBuilder.service = nil :: any
MeshBuilder.content = function(object: any): any
	return (Content :: any).fromObject(object)
end
-- Fires with a set's name (a weapon, or "Shots") once its meshes are built.
MeshBuilder.built = Signal.new()

local templates: { [string]: { [string]: MeshPart } } = {}
local building: { [string]: boolean } = {}
local failed: { [string]: string } = {}
local warned = false

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE: { [number]: number } = {}
for i = 1, #ALPHABET do
	VALUE[string.byte(ALPHABET, i)] = i - 1
end

-- The bytes in base64 `text` (line breaks and padding ignored).
function MeshBuilder.unpack(text: string): buffer
	local clean = string.gsub(text, "[^%w%+/]", "")
	local count = #clean
	local out = buffer.create(count * 3 // 4)
	local at = 0
	local whole = count - count % 4
	for i = 1, whole, 4 do
		local a, b, c, d = string.byte(clean, i, i + 3)
		local bits = VALUE[a] * 262144 + VALUE[b] * 4096 + VALUE[c] * 64 + VALUE[d]
		buffer.writeu8(out, at, bits // 65536)
		buffer.writeu8(out, at + 1, bits // 256 % 256)
		buffer.writeu8(out, at + 2, bits % 256)
		at += 3
	end
	local rest = count % 4
	if rest >= 2 then
		local a, b, c = string.byte(clean, whole + 1, whole + rest)
		local bits = VALUE[a] * 262144 + VALUE[b] * 4096 + (if c then VALUE[c] * 64 else 0)
		buffer.writeu8(out, at, bits // 65536)
		if rest == 3 then
			buffer.writeu8(out, at + 1, bits // 256 % 256)
		end
	end
	return out
end

-- A packed mesh's vertices (positions round its centre, in studs, and
-- normals) and triangles (1-based vertex indices, three a triangle).
function MeshBuilder.decode(entry: Entry): ({ Vector3 }, { Vector3 }, { number })
	local data = MeshBuilder.unpack(entry.data)
	local count = buffer.readu16(data, 0)
	local triangles = buffer.readu16(data, 2)
	local half = entry.size / 2
	local positions, normals, corners = table.create(count), table.create(count), table.create(triangles * 3)
	local normalsAt = 4 + count * 6
	local trianglesAt = normalsAt + count * 3
	for i = 0, count - 1 do
		local at = 4 + i * 6
		positions[i + 1] = Vector3.new(
			buffer.readi16(data, at) / 32767 * half.X,
			buffer.readi16(data, at + 2) / 32767 * half.Y,
			buffer.readi16(data, at + 4) / 32767 * half.Z
		)
		local n = normalsAt + i * 3
		normals[i + 1] = Vector3.new(buffer.readi8(data, n), buffer.readi8(data, n + 1), buffer.readi8(data, n + 2)).Unit
	end
	for i = 0, triangles * 3 - 1 do
		corners[i + 1] = buffer.readu16(data, trianglesAt + i * 2) + 1
	end
	return positions, normals, corners
end

local function build(service: any, entry: Entry): any
	local positions, normals, corners = MeshBuilder.decode(entry)
	local mesh = service:CreateEditableMesh()
	if not mesh then
		error("out of memory for meshes on this device")
	end
	local vertexIds, normalIds = table.create(#positions), table.create(#positions)
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

-- Builds every mesh in MeshData/`set` (yields; the first time only).
-- True once they're built; false if they can't be here.
function MeshBuilder.prepare(set: string): boolean
	if templates[set] then
		return true
	end
	while building[set] do
		task.wait()
	end
	if templates[set] or failed[set] then
		return templates[set] ~= nil
	end
	building[set] = true
	local ok, why = pcall(function()
		local service = MeshBuilder.service or game:GetService("AssetService")
		local module = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshData"):FindFirstChild(set)
		if not (module and module:IsA("ModuleScript")) then
			error(`no MeshData for {set}`)
		end
		local entries = require(module) :: { [string]: Entry }
		local made = {}
		for name, entry in entries do
			local mesh = build(service, entry)
			local part = service:CreateMeshPartAsync(MeshBuilder.content(mesh), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
			})
			part.Name = name
			made[name] = part
			-- A mesh a frame, so building them doesn't stall the game.
			task.wait()
		end
		templates[set] = made
	end)
	building[set] = nil
	if not ok then
		failed[set] = tostring(why)
		if not warned then
			warned = true
			warn(
				`[Fart Wars] Can't build the Blender meshes on this device ({why}), so the guns and shots are the plain stand-ins. In a published game, turn on Experience Settings > Security > Allow Mesh / Image APIs.`
			)
		end
		return false
	end
	MeshBuilder.built:Fire(set)
	return true
end

-- The built meshes of `set` by name, or nil; starts building them (in the
-- background) the first time they're asked for.
function MeshBuilder.request(set: string): { [string]: MeshPart }?
	if not templates[set] and not building[set] and not failed[set] then
		task.spawn(MeshBuilder.prepare, set)
	end
	return templates[set]
end

-- Whether `set`'s meshes are built.
function MeshBuilder.ready(set: string): boolean
	return templates[set] ~= nil
end

-- A new MeshPart showing mesh `name` of `set`, or nil if it isn't built.
-- Its Size is the mesh's own; set it to stretch it.
function MeshBuilder.copy(set: string, name: string): MeshPart?
	local template = templates[set] and templates[set][name]
	if not template then
		return nil
	end
	local ok, part = pcall(function()
		local made = Instance.new("MeshPart")
		made:ApplyMesh(template)
		made.Size = template.MeshSize
		return made
	end)
	return if ok then part else nil
end

-- Whether meshes can be built here at all (a one-triangle test), and why
-- not: the selftest's check that the setting is on.
function MeshBuilder.probe(): (boolean, string)
	local ok, why = pcall(function()
		local service = MeshBuilder.service or game:GetService("AssetService")
		local mesh = service:CreateEditableMesh()
		if not mesh then
			error("out of memory for meshes on this device")
		end
		local a = mesh:AddVertex(Vector3.new(0, 0, 0))
		local b = mesh:AddVertex(Vector3.new(1, 0, 0))
		local c = mesh:AddVertex(Vector3.new(0, 1, 0))
		mesh:AddTriangle(a, b, c)
		mesh:Destroy()
	end)
	return ok, if ok then "ok" else tostring(why)
end

-- What's been built here, for the selftest and bug reports.
function MeshBuilder.status(): string
	for set, why in failed do
		return `off ({set}: {why})`
	end
	local sets = {}
	for set in templates do
		table.insert(sets, set)
	end
	table.sort(sets)
	if #sets == 0 then
		return if next(building) then "building" else "none built yet"
	end
	return `built: {table.concat(sets, ", ")}`
end

-- Specs only: forget everything built.
function MeshBuilder.reset()
	table.clear(templates)
	table.clear(building)
	table.clear(failed)
	warned = false
end

return MeshBuilder
