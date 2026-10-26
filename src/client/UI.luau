-- Small helpers for building the screens in code, in one style.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.UIConfig)
local TeamConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.TeamConfig)
local Settings = require(script.Parent.Settings)

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

-- The HUD size (Settings.hudScale): every panel on every screen grows or
-- shrinks around its own anchor, so corner panels stay in their corners.
-- Full-screen backdrops are left alone.
local scaled: { UIScale } = setmetatable({}, { __mode = "v" }) :: any

local function scale(item: Instance)
	if not item:IsA("GuiObject") or item:FindFirstChild("HudScale") then
		return
	end
	if item.Size.X.Scale >= 1 and item.Size.Y.Scale >= 1 then
		return
	end
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "HudScale"
	uiScale.Scale = Settings.hudScale
	uiScale.Parent = item
	table.insert(scaled, uiScale)
end

-- Applies Settings.hudScale everywhere.
function UI.applyScale()
	for _, uiScale in scaled do
		if uiScale.Parent then
			uiScale.Scale = Settings.hudScale
		end
	end
end

-- A ScreenGui in the local player's PlayerGui that survives respawns.
function UI.screen(name: string, displayOrder: number): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local screen = UI.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Parent = playerGui,
	})
	screen.ChildAdded:Connect(function(child)
		-- Once its size is set.
		task.defer(scale, child)
	end)
	return screen
end

-- A team's symbol and a space ("▲ "), or "" with team symbols off.
function UI.teamSymbol(team: string?): string
	local config = team and TeamConfig.teams[team]
	return if config and Settings.teamSymbols then `{config.symbol} ` else ""
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
