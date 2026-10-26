-- Dresses held guns in the Blender meshes on this client. The server
-- builds every held gun from the stand-in pieces (a mesh built on the
-- server wouldn't replicate), so once this client has built a weapon's
-- meshes (MeshBuilder) it hides that gun's pieces, here only, and welds
-- the meshes to its Handle in their place, in a Folder named Skin. A gun
-- made of imported meshes is left as it is. Nothing here replicates or
-- changes what the server sees.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponModel = require(Shared.WeaponModel)
local MeshBuilder = require(Shared.MeshBuilder)

local WeaponSkin = {}

-- Dresses `tool` if its weapon's meshes are built here (and starts
-- building them if not). True once it's dressed.
function WeaponSkin.dress(tool: Tool): boolean
	if tool:FindFirstChild("Skin") then
		return true
	end
	local weapon = tool:GetAttribute("Weapon")
	local handle = tool:FindFirstChild("Handle")
	if type(weapon) ~= "string" or tool:GetAttribute("ArtSource") ~= "pieces" or not (handle and handle:IsA("BasePart")) then
		return false
	end
	if not MeshBuilder.request(weapon) then
		return false
	end
	local parts, source = WeaponModel.parts(weapon, handle.CFrame, false, true)
	if source ~= "runtime" then
		for _, part in parts do
			part:Destroy()
		end
		return false
	end
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= handle and child:GetAttribute("Role") then
			child.Transparency = 1
			child:SetAttribute("Hidden", true)
		end
	end
	local skin = Instance.new("Folder")
	skin.Name = "Skin"
	for _, part in parts do
		part.Parent = skin
		WeaponModel.attach(handle, part)
	end
	skin.Parent = tool
	return true
end

-- The parts `tool` shows: its Skin once dressed, otherwise its own.
function WeaponSkin.parts(tool: Tool): { BasePart }
	local skin = tool:FindFirstChild("Skin")
	local parts = {}
	for _, child in (skin or tool):GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Role") and not child:GetAttribute("Hidden") then
			table.insert(parts, child)
		end
	end
	return parts
end

return WeaponSkin
