-- The loading screen: the first thing a player sees, from ReplicatedFirst,
-- in place of Roblox's own. The two-tone FART WARS logo over a dark
-- background, the tagline, a tip every few seconds, a thick yellow bar and
-- what it's actually waiting for:
--   "Loading the battlefield..."  until the game has loaded
--   "Loading your profile..."     until the server has the player's data
--                                 (the DataStatus attribute stops being
--                                 "loading")
--   "Joining the lobby..."        until the home screen is built
-- Each stage gives up after UIConfig.loadingSeconds.stage, so a slow server
-- never traps anyone here; then it fades and is gone. It runs before the
-- rest of the client, so it builds its own screen (the client's UI helpers
-- aren't loaded yet) and reads the tips once ReplicatedStorage arrives.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(12, 10, 18)
local GREEN = Color3.fromRGB(139, 232, 58)
local GOLD = Color3.fromRGB(255, 201, 40)
-- Until the tips and timings arrive with the rest of the game.
local STAGE_SECONDS, TIP_SECONDS, FADE_SECONDS = 15, 4, 0.5
local LOGO_SCALE = 1.5

pcall(ReplicatedFirst.RemoveDefaultLoadingScreen, ReplicatedFirst)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = props.Parent
	return instance
end

local function outlined(text: string, size: number, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = FONT,
		TextSize = size,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, size + 8),
	}, { new("UIStroke", { Color = INK, Thickness = math.max(2, size // 12) }) })
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

-- A logo word: its colour as a top-to-bottom shine, a thick outline, and a
-- dark copy just below it for depth. Roblox stops text at size 100, so the
-- word is drawn at 100 and scaled up; `width` fits it at that size.
local function logoWord(text: string, width: number, color: Color3, parent: Instance, order: number)
	local h, s, v = color:ToHSV()
	local holder = new("Frame", {
		Name = text,
		LayoutOrder = order,
		Size = UDim2.new(0, width, 0, 113),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { new("UIScale", { Scale = LOGO_SCALE }) })
	-- (A frame's rotation doesn't turn its children, so each label tilts.)
	outlined(text, 100, {
		Name = "Shadow",
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 1, 0),
		Rotation = -4,
		TextColor3 = INK,
		Parent = holder,
	})
	outlined(text, 100, {
		Name = "Word",
		Size = UDim2.new(1, 0, 1, 0),
		Rotation = -4,
		Parent = holder,
	})
	local word = holder.Word
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromHSV(h, s * 0.6, math.min(1, v * 1.2)), Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.75)),
		Parent = word,
	})
end

local screen = new("ScreenGui", {
	Name = "LoadingScreen",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 100,
	Parent = playerGui,
})
local group = new("CanvasGroup", {
	Name = "Group",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Active = true,
	Parent = screen,
})
-- Its own frame: a gradient on the group itself would tint all that's in it.
new("Frame", {
	Name = "Background",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	ZIndex = 0,
	Parent = group,
}, {
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(44, 30, 72), INK),
	}),
})
-- Everything is laid out on a 1280 x 720 stage scaled to fit the screen.
local stage = new("Frame", {
	Name = "Stage",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 1280, 0, 720),
	BackgroundTransparency = 1,
	Parent = group,
})
local fit = new("UIScale", { Parent = stage })
local function refit()
	local size = group.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		fit.Scale = math.min(size.X / 1280, size.Y / 720)
	end
end
group:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
refit()

local logo = new("Frame", {
	Name = "Logo",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 140),
	Size = UDim2.new(0, 980, 0, 180),
	BackgroundTransparency = 1,
	Parent = stage,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 26),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
logoWord("FART", 236, GREEN, logo, 1)
logoWord("WARS", 268, GOLD, logo, 2)
outlined("Skibidi Stinkers vs Sigma Sharters", 28, {
	Name = "Tagline",
	Position = UDim2.new(0, 0, 0, 340),
	Parent = stage,
})
local tip = outlined("", 24, {
	Name = "Tip",
	Position = UDim2.new(0, 0, 0, 496),
	Parent = stage,
})
local bar = new("Frame", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 556),
	Size = UDim2.new(0, 560, 0, 34),
	BackgroundColor3 = Color3.fromRGB(20, 17, 28),
	Parent = stage,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 17) }),
	new("UIStroke", { Color = GOLD, Thickness = 4 }),
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
	}),
})
local fill = new("Frame", {
	Name = "Fill",
	Size = UDim2.new(0.04, 0, 1, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Parent = bar,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 12) }),
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 226, 102), Color3.fromRGB(224, 154, 16)),
	}),
})
local status = outlined("Loading the battlefield...", 26, {
	Name = "Status",
	Position = UDim2.new(0, 0, 0, 602),
	Parent = stage,
})
local version = new("TextLabel", {
	Name = "Version",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 18, 1, -12),
	Size = UDim2.new(0, 400, 0, 18),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(185, 178, 204),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = group,
})

local function progress(fraction: number)
	TweenService:Create(fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(math.clamp(fraction, 0.04, 1), 0, 1, 0),
	}):Play()
end

-- Waits until `ready()` or `seconds` have gone by, whichever is first.
local function waitFor(ready: () -> boolean, seconds: number)
	local waited = 0
	while not ready() and waited < seconds do
		task.wait(0.1)
		waited += 0.1
	end
end

local done = false

local function startTips(tips: { string })
	if #tips == 0 then
		return
	end
	task.spawn(function()
		local index = math.random(1, #tips)
		while not done do
			tip.Text = tips[index]
			index = index % #tips + 1
			task.wait(TIP_SECONDS)
		end
	end)
end

progress(0.1)
waitFor(function()
	return game:IsLoaded()
end, STAGE_SECONDS)
progress(0.4)

-- The tips, timings and version come with the rest of the game.
local shared = ReplicatedStorage:WaitForChild("Shared", STAGE_SECONDS)
local config = shared and shared:FindFirstChild("Config")
if config then
	local ok, UIConfig = pcall(require, config:WaitForChild("UIConfig", STAGE_SECONDS) :: any)
	if ok and type(UIConfig) == "table" then
		local seconds = UIConfig.loadingSeconds
		STAGE_SECONDS, TIP_SECONDS, FADE_SECONDS = seconds.stage, seconds.tip, seconds.fade
		startTips(UIConfig.loadingTips)
	end
	local okRelease, ReleaseConfig = pcall(require, config:WaitForChild("ReleaseConfig", STAGE_SECONDS) :: any)
	if okRelease and type(ReleaseConfig) == "table" then
		version.Text = `v{ReleaseConfig.label(workspace:GetAttribute("ReleaseChannel") :: any)} · PC beta`
	end
end

status.Text = "Loading your profile..."
waitFor(function()
	local data = player:GetAttribute("DataStatus")
	return data ~= nil and data ~= "loading"
end, STAGE_SECONDS)
progress(0.75)

status.Text = "Joining the lobby..."
waitFor(function()
	return playerGui:FindFirstChild("HomeScreen") ~= nil
end, STAGE_SECONDS)
progress(1)
task.wait(0.4)

done = true
local fade = TweenService:Create(group, TweenInfo.new(FADE_SECONDS), { GroupTransparency = 1 })
fade:Play()
task.wait(FADE_SECONDS)
screen:Destroy()
