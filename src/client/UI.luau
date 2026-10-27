-- Small helpers for building the screens in code, in one style.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

-- 12345 -> "12,345".
function UI.commas(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	formatted = string.gsub(formatted, "^(%-?),", "%1")
	return formatted
end

-- A glossy fill: light across the top half, a crisp line, darker below.
local function gloss(color: Color3): ColorSequence
	local h, s, v = color:ToHSV()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(h, s * 0.7, math.min(1, v * 1.2))),
		ColorSequenceKeypoint.new(0.46, Color3.fromHSV(h, s * 0.85, math.min(1, v * 1.08))),
		ColorSequenceKeypoint.new(0.54, color),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.68)),
	})
end

-- Grows a little under the pointer and squashes when pressed, then settles
-- back (a click usually opens something over it, and the pointer's leaving
-- isn't reported then).
function UI.springy(item: GuiObject, hover: number?)
	local press = UI.new("UIScale", { Name = "Press", Parent = item })
	local over = hover or 1.06
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function to(scale: number)
		TweenService:Create(press, info, { Scale = scale }):Play()
	end
	item.MouseEnter:Connect(function()
		to(over)
	end)
	item.MouseLeave:Connect(function()
		to(1)
	end)
	if item:IsA("GuiButton") then
		item.MouseButton1Down:Connect(function()
			to(0.92)
		end)
		item.MouseButton1Up:Connect(function()
			to(1)
		end)
	end
end

-- A quick bounce, to say "this changed".
function UI.pop(item: GuiObject, size: number?)
	local press = item:FindFirstChild("Press") :: UIScale? or UI.new("UIScale", { Name = "Press", Parent = item })
	press.Scale = size or 1.18
	TweenService:Create(press, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Dresses a transparent button as a chunky game button: a glossy fill in
-- `color`, a thick outline ("Border", on the button so it can be lit) and
-- the springy feel. The button keeps its own Text for reading; "Label"
-- shows it, outlined, above the fill.
local function skin(button: TextButton, color: Color3, radius: number)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.TextTransparency = 1
	button:SetAttribute("Color", color)
	UI.corner(radius).Parent = button
	UI.stroke(C.stroke, 3).Parent = button
	UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = button,
	}, { UI.corner(radius), UI.new("UIGradient", { Name = "Gloss", Color = gloss(color), Rotation = 90 }) })
	UI.springy(button)
end

-- Repaints a chunky button or tile.
function UI.paint(button: GuiButton, color: Color3)
	local fill = button:FindFirstChild("Fill")
	if fill then
		(fill :: any).Gloss.Color = gloss(color)
	else
		button.BackgroundColor3 = color
	end
end

-- A big game button: `icon` (an emoji) on the left, the words beside it.
function UI.chunky(text: string, color: Color3, icon: string?, props: { [string]: any }?): TextButton
	local button = UI.new("TextButton", {
		Text = text,
		Font = UIConfig.font,
		TextSize = 26,
		Size = UDim2.new(0, 220, 0, 64),
	})
	skin(button, color, 14)
	local label = UI.label(text, 26, {
		Name = "Label",
		Size = UDim2.new(1, if icon then -60 else -16, 1, 0),
		Position = UDim2.new(0, if icon then 52 else 8, 0, 0),
		ZIndex = 2,
		Parent = button,
	})
	if icon then
		UI.label(icon, 32, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.new(0, 40, 0, 40),
			ZIndex = 2,
			Parent = button,
		})
	end
	-- The label follows the button's own text, size and colour.
	button:GetPropertyChangedSignal("Text"):Connect(function()
		label.Text = button.Text
	end)
	button:GetPropertyChangedSignal("TextSize"):Connect(function()
		label.TextSize = button.TextSize
	end)
	button:GetPropertyChangedSignal("TextColor3"):Connect(function()
		label.TextColor3 = button.TextColor3
	end)
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	return button
end

-- A square icon button: the emoji big, a short word under it.
function UI.tile(icon: string, caption: string, color: Color3, props: { [string]: any }?): TextButton
	local button = UI.new("TextButton", {
		Text = caption,
		Font = UIConfig.font,
		TextSize = 14,
		Size = UDim2.new(0, 72, 0, 72),
	})
	skin(button, color, 16)
	UI.label(icon, 34, {
		Name = "Icon",
		Position = UDim2.new(0, 0, 0, 6),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 2,
		Parent = button,
	})
	local label = UI.label(caption, 14, {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 3, 1, -5),
		Size = UDim2.new(1, -6, 0, 16),
		TextScaled = true,
		ZIndex = 2,
		Parent = button,
	})
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	button:GetPropertyChangedSignal("Text"):Connect(function()
		label.Text = button.Text
	end)
	return button
end

-- The red bubble on a button's corner: a count, "!", or nothing (hidden).
function UI.setBadge(button: GuiObject, value: (number | string)?)
	local badge = button:FindFirstChild("Badge") :: Frame?
	if not badge then
		badge = UI.new("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.new(0, 30, 0, 30),
			BackgroundColor3 = Color3.fromRGB(235, 40, 50),
			ZIndex = 5,
			Parent = button,
		}, {
			UI.corner(15),
			UI.stroke(Color3.new(1, 1, 1), 2.5),
			UI.label("", 18, { Name = "Count", Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 }),
		})
	end
	local frame = badge :: Frame
	local text = if type(value) == "number" then (if value > 99 then "99+" elseif value > 0 then tostring(value) else "") else value or ""
	if text ~= "" and (frame :: any).Count.Text ~= text then
		UI.pop(frame, 1.4)
	end
	(frame :: any).Count.Text = text
	frame.Visible = text ~= ""
end

-- Greys a button out (and back) without losing its own colour. A greyed
-- button ignores clicks made through UI.onClick.
function UI.setEnabled(button: GuiButton, enabled: boolean)
	if button:GetAttribute("Color") == nil then
		button:SetAttribute("Color", button.BackgroundColor3)
	end
	button:SetAttribute("Enabled", enabled)
	if button:FindFirstChild("Fill") then
		UI.paint(button, if enabled then button:GetAttribute("Color") :: Color3 else C.disabled)
		return
	end
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
