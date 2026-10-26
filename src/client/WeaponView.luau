-- A weapon in a ViewportFrame, for the hotbar and the locker: the same
-- model the game holds (the imported Blender meshes, or the stand-in),
-- seen from its right side with the barrel pointing right. spin() turns
-- it in place for the locker's slow rotation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponModel = require(ReplicatedStorage:WaitForChild("Shared").WeaponModel)
local UI = require(script.Parent.UI)

local WeaponView = {}

local FIELD_OF_VIEW = 30

-- A ViewportFrame showing `weaponId`, with `props` applied.
function WeaponView.new(weaponId: string, props: { [string]: any }?): ViewportFrame
	local viewport = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(165, 160, 185),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.4),
	})
	if props then
		for key, value in props do
			if key ~= "Parent" then
				(viewport :: any)[key] = value
			end
		end
	end
	local model, center, size = WeaponModel.model(weaponId)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	-- Far enough back that the longest side fits, with a margin.
	local extent = math.max(size.Z, size.Y * 1.6)
	local distance = (extent / 2) / math.tan(math.rad(FIELD_OF_VIEW / 2)) * 1.12
	camera.CFrame = CFrame.lookAt(center + Vector3.new(distance, distance * 0.18, 0), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport:SetAttribute("Weapon", weaponId)
	viewport:SetAttribute("CenterX", center.X)
	viewport:SetAttribute("CenterY", center.Y)
	viewport:SetAttribute("CenterZ", center.Z)
	viewport:SetAttribute("Angle", 0)
	if props and props.Parent then
		viewport.Parent = props.Parent
	end
	return viewport
end

-- Turns the model in `viewport` to `angle` degrees about its centre.
function WeaponView.spin(viewport: ViewportFrame, angle: number)
	local model = viewport:FindFirstChildOfClass("Model")
	if not model then
		return
	end
	local function number(name: string): number
		local value = viewport:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	local center = Vector3.new(number("CenterX"), number("CenterY"), number("CenterZ"))
	local previous = number("Angle")
	local turn = CFrame.new(center) * CFrame.Angles(0, math.rad(angle - previous), 0) * CFrame.new(-center)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CFrame = turn * part.CFrame
		end
	end
	viewport:SetAttribute("Angle", angle)
end

return WeaponView
