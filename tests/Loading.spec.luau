-- The loading screen (ReplicatedFirst), on its own:
--   * it takes Roblox's place at once: the FART WARS logo, the tagline and
--     the bar, then a tip from UIConfig and the build once the game's
--     scripts arrive
--   * it says what it's waiting for: the profile (DataStatus "loading"),
--     then the lobby (the home screen), the bar filling as it goes
--   * once the home screen exists it fades and is gone
--   * the background's gradient stays off the group, and text within what
--     Roblox draws
--   * a profile that never loads doesn't trap anyone: after
--     loadingSeconds.stage it moves on anyway
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local UIConfig = require(game:GetService("ReplicatedStorage").Shared.Config.UIConfig)
local ReleaseConfig = require(game:GetService("ReplicatedStorage").Shared.Config.ReleaseConfig)
local checks = 0

local function check(value, message)
	checks += 1
	assert(value, message)
end

local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	task.spawn(fn)
end

local function join(name: string, id: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = id
	Instance.new("PlayerGui").Parent = player
	Players.LocalPlayer = player
	player.Parent = Players
	return player
end

local loadingScript = ReplicatedFirst:FindFirstChild("LoadingScreen", true)
check(loadingScript and loadingScript:IsA("LocalScript"), "a LocalScript in ReplicatedFirst")

-- A normal join.
local me = join("Me", 1)
me:SetAttribute("DataStatus", "loading")
run(loadingScript)
task.wait(0.2)
local screen = me.PlayerGui:FindFirstChild("LoadingScreen")
check(screen and screen.Enabled and screen.DisplayOrder >= 100, "it shows straight away, over everything")
local stage = screen.Group.Stage
check(stage.Logo.FART and stage.Logo.WARS and stage.Tagline.Text == UIConfig.tagline, "the logo and the tagline")
-- What the specs can't see, kept from coming back: a gradient on a
-- CanvasGroup tints all that's in it, and Roblox stops text at size 100.
check(screen.Group:FindFirstChildOfClass("UIGradient") == nil, "no gradient on the group itself")
check(screen.Group.Background:FindFirstChildOfClass("UIGradient"), "it's on the background")
for _, item in screen:GetDescendants() do
	if item:IsA("TextLabel") then
		check(item.TextSize <= 100, `{item.Name}: text Roblox can draw at that size`)
	end
end
check(table.find(UIConfig.loadingTips, stage.Tip.Text) ~= nil, "a tip: " .. stage.Tip.Text)
check(string.find(screen.Group.Version.Text, ReleaseConfig.VERSION, 1, true), "and the build")
check(stage.Status.Text == "Loading your profile...", "waiting for the profile: " .. stage.Status.Text)
local before = stage.Bar.Fill.Size.X.Scale

me:SetAttribute("DataStatus", "ready")
task.wait(0.5)
check(stage.Status.Text == "Joining the lobby...", "then the lobby")
check(stage.Bar.Fill.Size.X.Scale > before, "the bar fills as it goes")
check(me.PlayerGui:FindFirstChild("LoadingScreen"), "still up until the home screen exists")

local tip = stage.Tip.Text
task.wait(UIConfig.loadingSeconds.tip + 0.2)
check(stage.Tip.Text ~= tip, "the tip changes every few seconds")

Instance.new("ScreenGui", me.PlayerGui).Name = "HomeScreen"
task.wait(1 + UIConfig.loadingSeconds.fade)
check(me.PlayerGui:FindFirstChild("LoadingScreen") == nil, "the home screen is there: it fades and is gone")

-- A profile that never loads.
me:Destroy()
local stuck = join("Stuck", 2)
stuck:SetAttribute("DataStatus", "loading")
run(loadingScript)
task.wait(0.2)
local stuckStage = stuck.PlayerGui.LoadingScreen.Group.Stage
task.wait(UIConfig.loadingSeconds.stage + 0.5)
check(stuckStage.Status.Text == "Joining the lobby...", "after loadingSeconds.stage it stops waiting for the profile")
Instance.new("ScreenGui", stuck.PlayerGui).Name = "HomeScreen"
task.wait(1 + UIConfig.loadingSeconds.fade)
check(stuck.PlayerGui:FindFirstChild("LoadingScreen") == nil, "and still gets to the lobby")

return { status = "PASS", checks = checks }
