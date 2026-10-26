-- Dresses the map with the Blender props (art/blender/build_props.py,
-- Config/MapArt). Every part MapArt names gets its imported mesh from
-- ReplicatedStorage.Assets.Props drawn exactly over it, coloured like it.
-- The part stays where it is, invisible, as what players bump into, shots
-- hit and blasts are stopped by; the mesh can't be hit, touched or
-- collided with, so cover and sightlines are the same with or without the
-- art. A prop that isn't imported (or is the wrong way round) leaves its
-- parts as they are. The meshes go in the map's Dressing folder, except
-- inside a model (a GasBarrel), where they stay with their part so the
-- model comes and goes as one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapArt = require(Shared.Config.MapArt)
local PropArt = require(Shared.Config.PropArt)
local WeaponModel = require(Shared.WeaponModel)

local MapDressing = {}

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
	local turn = CFrame.Angles(0, math.rad(rule.turn or 0), 0)
	local at = part.CFrame * turn
	if rule.face == "away" and at.LookVector.Z * at.Position.Z < 0 then
		at *= CFrame.Angles(0, math.pi, 0)
	end
	local size = part.Size
	return at, Vector3.new(along(turn.RightVector, size), along(turn.UpVector, size), along(turn.LookVector, size))
end

-- Dresses every undressed part of `map` that MapArt names and whose prop
-- is imported. Returns how many it dressed.
function MapDressing.dress(map: Instance): number
	local meshes: { [string]: MeshPart | false } = {}
	local dressed = 0
	for _, part in map:GetDescendants() do
		local rule = part:IsA("BasePart") and MapArt.parts[part.Name]
		if not rule or part:GetAttribute("Dressed") or part:GetAttribute("Dresses") then
			continue
		end
		if meshes[rule.mesh] == nil then
			meshes[rule.mesh] = MapDressing.imported(rule.mesh) or false
		end
		local mesh = meshes[rule.mesh]
		if not mesh then
			continue
		end
		local hitbox = part :: BasePart
		local at, size = MapDressing.placement(hitbox, rule)
		local art = mesh:Clone()
		art.Name = `{hitbox.Name}Art`
		art.Size = size
		art.CFrame = at
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
		hitbox.Transparency = 1
		hitbox.CastShadow = false
		hitbox:SetAttribute("Dressed", rule.mesh)
		local parent = hitbox.Parent
		if parent and parent:IsA("Model") and parent ~= map then
			art.Parent = parent
		else
			local folder = map:FindFirstChild("Dressing")
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "Dressing"
				folder.Parent = map
			end
			art.Parent = folder
		end
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
