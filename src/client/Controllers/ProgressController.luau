-- Progression on the client. It only shows: coins, level and XP come from
-- the player's attributes, which the server sets.
--   * the level bar along the bottom (while playing): LV n, a segmented XP
--     bar with the numbers, the next level; the next goal bottom right
--     ("NEXT: Level 5: Spritzer in the shop"); coins are in the top right
--   * small "+10 coins  +20 XP  Elimination" lines stacked bottom right,
--     gone after a moment; nothing in the middle of the screen mid-fight
--   * a short LEVEL UP banner with what it unlocked, and mastery badges
--   * whether progress is saving: "Loading progress..." while the profile
--     loads, a warning if this session won't save (DataStatus attribute)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local Audio = require(Client.Audio)

local C = UIConfig.colors
local MAX_LINES = 4

local ProgressController = {}

ProgressController.parts = {} :: { [string]: any }

local player = Players.LocalPlayer
local bannerToken = 0
local started = false

local function number(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function commas(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return if string.sub(formatted, 1, 1) == "," then string.sub(formatted, 2) else formatted
end

-- The next thing to work toward, from this level.
function ProgressController.nextGoal(level: number): string
	if level >= ProgressionConfig.MAX_LEVEL then
		return `Every {commas(ProgressionConfig.CAP_REPEAT_XP)} XP: {ProgressionConfig.CAP_REPEAT_COINS} coins`
	end
	for target = level + 1, ProgressionConfig.MAX_LEVEL do
		local unlock = ProgressionConfig.unlocks[target]
		if unlock then
			return `Level {target}: {unlock.text}`
		end
	end
	return `Level {ProgressionConfig.MAX_LEVEL}`
end

local function build()
	local p = ProgressController.parts
	local screen = UI.screen("Progress", 5)
	p.screen = screen

	-- The level bar along the bottom: LV n, the XP bar, n + 1.
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(0, 470, 0, 20),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	p.panel = panel
	p.level = UI.label("LV 1", 18, {
		Name = "Level",
		Size = UDim2.new(0, 56, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local bar = UI.new("Frame", {
		Name = "XPBar",
		Position = UDim2.new(0, 58, 0.5, -6),
		Size = UDim2.new(1, -96, 0, 12),
		BackgroundColor3 = Color3.fromRGB(30, 26, 40),
		Parent = panel,
	}, { UI.corner(6), UI.stroke(C.stroke, 2) })
	p.xpFill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = bar,
	}, { UI.corner(6), UI.gradient(Color3.fromRGB(80, 190, 255), Color3.fromRGB(20, 120, 230)) })
	-- Notches, like a segmented bar.
	for i = 1, 9 do
		UI.new("Frame", {
			Name = "Notch",
			Position = UDim2.new(i / 10, -1, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = C.stroke,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = bar,
		})
	end
	p.xpText = UI.label("0 / 100 XP", 11, {
		Name = "Text",
		Size = UDim2.new(1, 0, 1, 0),
		Font = UIConfig.bodyFont,
		ZIndex = 3,
		Parent = bar,
	})
	p.nextLevel = UI.label("2", 18, {
		Name = "NextLevel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 34, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})
	-- The next goal and whether progress is saving: bottom right.
	p.goal = UI.label("", 14, {
		Name = "Goal",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -28),
		Size = UDim2.new(0, 300, 0, 18),
		Font = UIConfig.bodyFont,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		Parent = screen,
	})
	p.status = UI.label("", 13, {
		Name = "Status",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -10),
		Size = UDim2.new(0, 300, 0, 16),
		Font = UIConfig.bodyFont,
		TextColor3 = C.warning,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = screen,
	})

	local lines = UI.new("Frame", {
		Name = "Rewards",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -52),
		Size = UDim2.new(0, 260, 0, 4 * 26),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	local layout = UI.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = lines
	p.lines = lines

	local banner = UI.new("Frame", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.new(0, 420, 0, 84),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	p.banner = banner
	p.bannerTitle = UI.label("LEVEL UP!", 40, { Name = "Title", TextColor3 = C.accent, Parent = banner })
	p.bannerDetail = UI.label("", 20, {
		Name = "Detail",
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 0, 26),
		TextWrapped = true,
		Parent = banner,
	})
end

local function refresh()
	local p = ProgressController.parts
	local level = number("Level", 1)
	local xp = number("XP", 0)
	local need = math.max(1, number("XPToNext", ProgressionConfig.xpToNext(level)))
	local rank = number("Prestige", 0)
	p.level.Text = if rank > 0 then `P{rank} · LV {level}` else `LV {level}`
	p.nextLevel.Text = if level >= ProgressionConfig.MAX_LEVEL then "★" else tostring(level + 1)
	p.xpFill.Size = UDim2.new(math.clamp(xp / need, 0, 1), 0, 1, 0)
	p.xpText.Text = `{commas(xp)} / {commas(need)} XP`
	p.goal.Text = `NEXT: {ProgressController.nextGoal(level)}`
	local status = player:GetAttribute("DataStatus")
	local active = FeatureFlags.PROGRESSION and ClientState.isActive()
	-- (On the home screen too: worth knowing before playing.)
	p.status.Visible = FeatureFlags.PROGRESSION and (status == "loading" or status == "unsaved")
	p.status.Text = if status == "loading" then "Loading progress..." else "Progress isn't saving this session"
	p.panel.Visible = active
	p.goal.Visible = active
end

-- One line above the panel (a reward, or a tip, for `seconds`); the oldest
-- goes when there are too many.
function ProgressController.line(text: string, color: Color3?, seconds: number?, name: string?)
	local p = ProgressController.parts
	local shown: { TextLabel } = {}
	for _, child in p.lines:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(shown, child)
		end
	end
	table.sort(shown, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #shown >= MAX_LINES do
		local oldest = table.remove(shown, 1) :: TextLabel
		oldest:Destroy()
	end
	local order = (p.lines:GetAttribute("Next") or 0) + 1
	p.lines:SetAttribute("Next", order)
	local label = UI.label(text, 18, {
		Name = name or "Line",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = color or C.text,
		Parent = p.lines,
	})
	task.delay(seconds or UIConfig.rewardSeconds, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

local function banner(title: string, detail: string)
	local p = ProgressController.parts
	bannerToken += 1
	local token = bannerToken
	p.bannerTitle.Text = title
	p.bannerDetail.Text = detail
	p.banner.Visible = true
	task.delay(UIConfig.levelUpSeconds, function()
		if bannerToken == token then
			p.banner.Visible = false
		end
	end)
end

local function onEvent(event: any)
	if type(event) ~= "table" then
		return
	end
	if event.kind == "grant" then
		local parts = {}
		if (event.coins or 0) > 0 then
			table.insert(parts, `+{commas(event.coins)} coins`)
		end
		if (event.xp or 0) > 0 then
			table.insert(parts, `+{commas(event.xp)} XP`)
		end
		if #parts > 0 then
			local reason = UIConfig.rewardReasons[event.reason] or ""
			ProgressController.line(`{table.concat(parts, "  ")}  {reason}`)
			Audio.play("coins")
		end
	elseif event.kind == "levelUp" then
		local detail = if event.repeated
			then `+{event.coins} coins`
			elseif event.unlocks and #event.unlocks > 0 then `Unlocked: {table.concat(event.unlocks, ", ")}`
			else ProgressController.nextGoal(event.level)
		banner(if event.repeated then "LEVEL 50 BONUS!" else `LEVEL {event.level}!`, detail)
		Audio.play("levelUp")
	elseif event.kind == "gift" then
		ProgressController.line("🎡 A free spin for playing! Open it top right.", Color3.fromRGB(200, 160, 255), 5)
		Audio.play("coins")
	elseif event.kind == "mastery" then
		ProgressController.line(`{event.badge} mastery: {event.eliminations} eliminations`, C.accent)
	end
end

function ProgressController.start()
	if started then
		return
	end
	started = true
	build()
	refresh()
	for _, name in { "Coins", "Level", "XP", "XPToNext", "DataStatus", "Prestige" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	ClientState.StateChanged:Connect(refresh)
	local remote = ClientState.remote("ProgressEvent") :: RemoteEvent
	remote.OnClientEvent:Connect(onEvent)
end

return ProgressController
