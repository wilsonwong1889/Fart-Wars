-- Prints Brainrot Battlefield as MapService loads it, dressed with every
-- Blender prop (stand-in MeshParts of each prop's size), one LAYOUT line
-- per visible part, for art/blender/build_props.py's map renders. Run it
-- with `python3 scripts/map_layout.py`, which writes the lines to
-- art/export/props/layout.txt.
--   LAYOUT name prop shape material r g b transparency cframe(12) size(3)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PropArt = require(ReplicatedStorage.Shared.Config.PropArt)
local MapService = require(game.ServerScriptService.Server.Services.MapService)

local props = ReplicatedStorage.Assets.Props
for name, art in PropArt do
	local mesh = Instance.new("MeshPart")
	mesh.Name = name
	mesh.MeshSize = art.size
	mesh.Size = art.size
	mesh.Parent = props
end

local map = MapService.load("BrainrotBattlefield")
local lines = 0
for _, item in map:GetDescendants() do
	if item:IsA("BasePart") and item.Transparency < 1 then
		local shape = (item :: any).Shape
		local color = item.Color
		local numbers = { item.CFrame:GetComponents() }
		for i, n in numbers do
			numbers[i] = string.format("%.4f", n)
		end
		print(string.format(
			"LAYOUT %s %s %s %s %d %d %d %.3f %s %.4f %.4f %.4f",
			item.Name,
			item:GetAttribute("Prop") or "-",
			if item:IsA("MeshPart") then "Mesh" elseif shape then shape.Name else "Block",
			item.Material.Name,
			math.round(color.R * 255),
			math.round(color.G * 255),
			math.round(color.B * 255),
			item.Transparency,
			table.concat(numbers, " "),
			item.Size.X,
			item.Size.Y,
			item.Size.Z
		))
		lines += 1
	end
end

return { status = "PASS", checks = 0, lines = lines }
