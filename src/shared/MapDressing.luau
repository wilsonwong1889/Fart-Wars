-- Dresses the map with the Blender props (art/blender/build_props.py,
-- Config/MapArt). Every part MapArt names gets its imported mesh from
-- ReplicatedStorage.Assets.Props drawn exactly over it, coloured like it.
-- The part stays where it is, invisible, as what players bump into, shots
-- hit and blasts are stopped by; the mesh can't be hit, touched or
-- collided with, so cover and sightlines are the same with or without the
-- art. Walls, trims and floors are dressed with modules repeated along
-- them (MapDressing.pieces). A prop that isn't imported (or is the wrong
-- way round) leaves its parts as they are. The meshes go in the map's
-- Dressing folder, except inside a model (a GasBarrel), where they stay
-- with their part so the model comes and goes as one.
--
-- Without imports, each client dresses the map itself (dressRuntime) from
-- the packed meshes MeshBuilder builds from MeshData/Props: the same
-- pieces in the same places, on that client only, since a mesh built on
-- the server wouldn't replicate.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapArt = require(Shared.Config.MapArt)
local PropArt = require(Shared.Config.PropArt)
local WeaponModel = require(Shared.WeaponModel)
local MeshBuilder = require(Shared.MeshBuilder)

local MapDressing = {}

-- The MeshData set the map's packed meshes are in.
MapDressing.SET = "Props"

-- The imported mesh for `prop` (a MeshPart named after it in
-- Assets.Props, or the Model the importer made with one inside), or nil
-- and why not.
function MapDressing.imported(prop: string): (MeshPart?, string)
	local art = PropArt[prop]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	local found = props and props:FindFirstChild(prop)
	if found and not found:IsA("MeshPart") then
		found = found:FindFirstChildWhichIsA("MeshPart", true)
		if not found then
			return nil, `no MeshPart in {prop}`
		end
	end
	if not (art and found) then
		return nil, "not imported"
	end
	local meshSize = (found :: any).MeshSize
	if typeof(meshSize) == "Vector3" and meshSize.Magnitude > 0 and not WeaponModel.matches(meshSize, art.size) then
		return nil, `{prop} is the wrong way round (re-import with Forward -Z, Up +Y)`
	end
	return found :: MeshPart, "imported"
end

local function along(axis: Vector3, size: Vector3): number
	return math.abs(axis.X) * size.X + math.abs(axis.Y) * size.Y + math.abs(axis.Z) * size.Z
end

-- Where the mesh goes over `part`, and its size in its own axes.
function MapDressing.placement(part: BasePart, rule: MapArt.Rule): (CFrame, Vector3)
	local degrees = rule.turn or 0
	if rule.long and part.Size.Z > part.Size.X then
		degrees += 90
	end
	local turn = CFrame.Angles(0, math.rad(degrees), 0)
	local at = part.CFrame * turn
	if rule.face == "away" and at.LookVector.Z * at.Position.Z < 0 then
		at *= CFrame.Angles(0, math.pi, 0)
	end
	local size = part.Size
	return at, Vector3.new(along(turn.RightVector, size), along(turn.UpVector, size), along(turn.LookVector, size))
end

export type Piece = { cframe: CFrame, size: Vector3 }

local function count(length: number, module: number): number
	return if module > 0 then math.max(1, math.round(length / module)) else 1
end

-- The meshes that dress `part`: one over the whole of it, or for a
-- module (PropArt's `tile`), as many as fit along each tiled axis, each
-- stretched a little so they come out even. On a map built `scale` times
-- bigger than its layout, the modules are that much bigger too, so a wall
-- keeps its bricks' proportions.
function MapDressing.pieces(part: BasePart, rule: MapArt.Rule, scale: number?): { Piece }
	local at, size = MapDressing.placement(part, rule)
	local art = PropArt[rule.mesh]
	local tile = art and art.tile
	if not tile then
		return { { cframe = at, size = size } }
	end
	tile *= scale or 1
	local nx, ny, nz = count(size.X, tile.X), count(size.Y, tile.Y), count(size.Z, tile.Z)
	local piece = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	local pieces = {}
	for i = 1, nx do
		for j = 1, ny do
			for k = 1, nz do
				local offset = Vector3.new((i - 0.5) * piece.X, (j - 0.5) * piece.Y, (k - 0.5) * piece.Z) - size / 2
				table.insert(pieces, { cframe = at * CFrame.new(offset), size = piece })
			end
		end
	end
	return pieces
end

-- The parts of `map` MapArt names that nothing has dressed yet, with
-- their rules.
local function undressed(map: Instance): { { part: BasePart, rule: MapArt.Rule } }
	local found = {}
	for _, part in map:GetDescendants() do
		local rule = part:IsA("BasePart") and MapArt.parts[part.Name]
		if rule and not part:GetAttribute("Dressed") and not part:GetAttribute("Dresses") then
			table.insert(found, { part = part :: BasePart, rule = rule })
		end
	end
	return found
end

-- Draws fresh copies of a mesh (from `make`) over `hitbox`, one a piece,
-- coloured like it and never in the way. Returns them.
local function drawOver(map: Instance, hitbox: BasePart, rule: MapArt.Rule, make: () -> MeshPart?): { MeshPart }
	local scale = map:GetAttribute("Scale")
	local parent = hitbox.Parent
	local folder = if parent and parent:IsA("Model") and parent ~= map then parent else map:FindFirstChild("Dressing")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Dressing"
		folder.Parent = map
	end
	local arts = {}
	for _, piece in MapDressing.pieces(hitbox, rule, if type(scale) == "number" then scale else nil) do
		local art = make()
		if not art then
			break
		end
		art.Name = `{hitbox.Name}Art`
		art.Size = piece.size
		art.CFrame = piece.cframe
		art.Color = hitbox.Color
		art.Material = hitbox.Material
		art.Reflectance = hitbox.Reflectance
		art.Transparency = hitbox.Transparency
		art.CastShadow = hitbox.CastShadow
		art.Anchored = true
		art.CanCollide = false
		art.CanQuery = false
		art.CanTouch = false
		art:SetAttribute("Dresses", hitbox.Name)
		art:SetAttribute("Prop", rule.mesh)
		art.Parent = folder
		table.insert(arts, art)
	end
	return arts
end

-- Dresses every undressed part of `map` that MapArt names and whose prop
-- is imported. Returns how many parts it dressed.
function MapDressing.dress(map: Instance): number
	local meshes: { [string]: MeshPart | false } = {}
	local dressed = 0
	for _, found in undressed(map) do
		local hitbox, rule = found.part, found.rule
		if meshes[rule.mesh] == nil then
			meshes[rule.mesh] = MapDressing.imported(rule.mesh) or false
		end
		local mesh = meshes[rule.mesh]
		if not mesh then
			continue
		end
		drawOver(map, hitbox, rule, function()
			return (mesh :: MeshPart):Clone()
		end)
		hitbox.Transparency = 1
		hitbox.CastShadow = false
		hitbox:SetAttribute("Dressed", rule.mesh)
		dressed += 1
	end
	return dressed
end

-- Dresses `map` on this client only, from the meshes MeshBuilder built
-- from MeshData/Props, wherever the server couldn't (no imports). The part
-- is hidden here only, by LocalTransparencyModifier, which the server's
-- updates never overwrite; its art follows the part's own Transparency, so
-- a barrel's art goes and comes back with the barrel. Returns how many
-- parts it dressed: none until the meshes are built.
function MapDressing.dressRuntime(map: Instance): number
	if not MeshBuilder.ready(MapDressing.SET) then
		return 0
	end
	local dressed = 0
	for _, found in undressed(map) do
		local hitbox, rule = found.part, found.rule
		local arts = drawOver(map, hitbox, rule, function()
			return MeshBuilder.copy(MapDressing.SET, rule.mesh)
		end)
		if #arts == 0 then
			continue
		end
		hitbox.LocalTransparencyModifier = 1
		hitbox.CastShadow = false
		hitbox:SetAttribute("Dressed", rule.mesh)
		hitbox:GetPropertyChangedSignal("Transparency"):Connect(function()
			for _, art in arts do
				art.Transparency = hitbox.Transparency
			end
		end)
		dressed += 1
	end
	return dressed
end

-- A fresh copy of `prop`'s mesh for something made on the fly (the Bean
-- Rain's beans), or nil when it isn't imported.
function MapDressing.copy(prop: string): MeshPart?
	local mesh = MapDressing.imported(prop)
	return if mesh then mesh:Clone() else nil
end

return MapDressing
