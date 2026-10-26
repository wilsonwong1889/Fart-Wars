-- Small helpers for building the screens in code, in one style.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.UIConfig)

local C = UIConfig.colors

local UI = {}

-- Creates `className` with `props`, and parents `children` to it.
function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	instance.Parent = parent
	return instance
end

function UI.corner(radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function UI.stroke(color: Color3?, thickness: number?): UIStroke
	return UI.new("UIStroke", {
		Name = "Border",
		Color = color or C.stroke,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- A top-to-bottom gradient (it tints the background, so use a white one).
function UI.gradient(top: Color3, bottom: Color3): UIGradient
	return UI.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 })
end

-- A chunky game-style box: a gradient of `color`, rounded, thick outline.
function UI.box(name: string, color: Color3, size: UDim2, props: { [string]: any }?): Frame
	local h, s, v = color:ToHSV()
	local box = UI.new("Frame", {
		Name = name,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, {
		UI.corner(12),
		UI.stroke(C.stroke, 3),
		UI.gradient(Color3.fromHSV(h, s * 0.9, math.min(1, v * 1.1)), Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.72)),
	})
	if props then
		for key, value in props do
			(box :: any)[key] = value
		end
	end
	return box
end

function UI.padding(pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return UI.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

function UI.list(direction: Enum.FillDirection, gap: number, align: Enum.HorizontalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

-- A ScreenGui in the local player's PlayerGui that survives respawns.
function UI.screen(name: string, displayOrder: number): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return UI.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Parent = playerGui,
	})
end

function UI.label(text: string, size: number, props: { [string]: any }?): TextLabel
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = UIConfig.font,
		TextColor3 = C.text,
		Size = UDim2.new(1, 0, 0, size + 6),
	})
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	UI.new("UIStroke", { Color = C.stroke, Thickness = math.max(1, size // 14), Parent = label })
	return label
end

function UI.button(text: string, color: Color3, props: { [string]: any }?): TextButton
	local button = UI.new("TextButton", {
		Text = text,
		Font = UIConfig.font,
		TextSize = 22,
		TextColor3 = C.text,
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Size = UDim2.new(0, 220, 0, 48),
	}, { UI.corner(10), UI.stroke(C.stroke, 3) })
	UI.new("UIStroke", {
		Color = C.stroke,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = button,
	})
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	return button
end

-- Greys a button out (and back) without losing its own colour. A greyed
-- button ignores clicks made through UI.onClick.
function UI.setEnabled(button: GuiButton, enabled: boolean)
	if button:GetAttribute("Color") == nil then
		button:SetAttribute("Color", button.BackgroundColor3)
	end
	button:SetAttribute("Enabled", enabled)
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then button:GetAttribute("Color") :: Color3 else C.disabled
end

function UI.onClick(button: GuiButton, handler: () -> ())
	button.Activated:Connect(function()
		if button:GetAttribute("Enabled") ~= false then
			handler()
		end
	end)
end

return UI
