-- The client shell against the real server, in one stand-in world (the
-- harness loops remotes back, so this is one client talking to it):
--   * joining shows the home screen over the live battlefield (fixed views)
--   * Coming Soon sections open and close; a team choice reaches the server
--   * PLAY: the home screen goes, the HUD shows your team, the controls card
--     shows once, and the camera follows the avatar in third person
--   * V toggles first/third person, repeatedly, without breaking anything
--   * Shift: Fart Dash (a push the server accepts, then a cooldown); M opens
--     the menu with the mouse freed, and no firing or dashing in it; Tab
--     (held) shows the scoreboard
--   * the crosshair shows in a match; left click fires (the server sees
--     the shot)
--   * the HUD follows the server's scores and clock; the results screen
--     names the winner; the AFK warning shows and clears
--   * SPECTATE from the menu goes back home, and team choices that would
--     unbalance the teams are greyed out
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local TestControls = require(server.TestControls)
local MapBase = require(ReplicatedStorage.Shared.Interfaces.MapBase)

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)

local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
task.wait(0.5)
local HUD = require(client.Controllers.HUDController)
local Home = require(client.Controllers.HomeController)
local Camera = require(client.Controllers.CameraController)
local gui = me.PlayerGui
local hud, home = HUD.parts, Home.parts

local function key(code: Enum.KeyCode, down: boolean)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	if down then
		UserInputService.InputBegan:Fire(input, false)
	else
		UserInputService.InputEnded:Fire(input, false)
	end
end
local function press(code: Enum.KeyCode)
	key(code, true)
	key(code, false)
end
local function frames(seconds: number)
	for _ = 1, math.ceil(seconds / 0.1) do
		task.wait(0.1)
		RunService.Heartbeat:Fire(0.1)
	end
end
local function click(button: GuiButton)
	button.Activated:Fire()
	task.wait(0.05)
end
-- Players walk about (so the AFK check leaves them be) unless held still.
local still: { [Player]: boolean } = {}
local function wander(player: Player)
	task.spawn(function()
		local step = 1
		while player.Parent do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and not still[player] then
				step = -step
				root.CFrame = root.CFrame * CFrame.new(8 * step, 0, 0)
			end
			task.wait(5)
		end
	end)
end
wander(me)

-- The home screen.
for _, name in { "HomeScreen", "HUD", "ResultsScreen", "Scoreboard", "GameMenu", "ComingSoon" } do
	check(gui:FindFirstChild(name), `{name} is built`)
end
check(home.home.Enabled and not hud.results.Enabled and not hud.scoreboard.Enabled, "home screen up, overlays down")
check(home.play.Text == "PLAY", "a PLAY button")
local cam = workspace.CurrentCamera
local views = MapBase.cameraPoints(workspace.Map)
check(cam.CameraType == Enum.CameraType.Scriptable, "the camera spectates")
local onView = false
for _, view in views do
	onView = onView or (view.CFrame.Position - cam.CFrame.Position).Magnitude < 12
end
check(onView, "from one of the map's fixed views")
check(me.Character == nil, "no avatar on the home screen")

local rewards = home.home:FindFirstChild("Rewards", true) :: TextButton
click(rewards)
check(home.comingSoon.Enabled and home.soonTitle.Text == "REWARDS", "Rewards: Coming Soon")
click(home.comingSoon:FindFirstChild("Close", true))
check(not home.comingSoon.Enabled, "and closes")

click(home.teamButtons.Stinkers)
task.wait(0.6)
check(Home.selectedTeam == "Stinkers" and me:GetAttribute("PreferredTeam") == "Stinkers", "the team choice reaches the server")

-- PLAY.
click(home.play)
task.wait(0.2)
check(me:GetAttribute("State") == "ACTIVE" and me:GetAttribute("TeamId") == "Stinkers", "PLAY puts me on my chosen team")
check(not home.home.Enabled, "the home screen goes")
check(hud.yourTeam.Visible and hud.yourTeam.Text == "YOU: SKIBIDI STINKERS", "the HUD says my team")
check(hud.controls.Visible, "the controls card shows")
check(cam.CameraType == Enum.CameraType.Custom and cam.CameraSubject == me.Character.Humanoid, "the camera follows my avatar")
check(me.CameraMode == Enum.CameraMode.Classic and not Camera.firstPerson, "third person by default")
frames(9)
check(not hud.controls.Visible, "the controls card goes after a few seconds")

-- V, repeatedly.
local defaultMin = game.StarterPlayer.CameraMinZoomDistance or 0.5
press(Enum.KeyCode.V)
check(me.CameraMode == Enum.CameraMode.LockFirstPerson, "V: first person")
press(Enum.KeyCode.V)
task.wait(0.05)
check(me.CameraMode == Enum.CameraMode.Classic, "V again: third person")
for _ = 1, 11 do
	press(Enum.KeyCode.V)
end
task.wait(0.05)
check(me.CameraMode == Enum.CameraMode.LockFirstPerson and Camera.firstPerson, "eleven more: first person")
press(Enum.KeyCode.V)
task.wait(0.05)
check(me.CameraMode == Enum.CameraMode.Classic and me.CameraMinZoomDistance == defaultMin, "and back, zoom limits intact")
check(cam.CameraType == Enum.CameraType.Custom, "the camera still follows")

-- Shift, left click, M and Tab.
local Combat = require(client.Controllers.CombatController)
local combat = Combat.parts
local root = me.Character.HumanoidRootPart
local dashes, shots = 0, 0
ReplicatedStorage.Remotes.FartDash.OnServerEvent:Connect(function()
	dashes += 1
end)
ReplicatedStorage.Remotes.FireWeapon.OnServerEvent:Connect(function()
	shots += 1
end)
me.Character.Humanoid.FloorMaterial = Enum.Material.Grass
RunService.RenderStepped:Fire(0.016)
check(combat.crosshair.Visible and not UserInputService.MouseIconEnabled, "a crosshair instead of the cursor")
check(combat.dash.Text == "FART DASH READY (SHIFT)", "the dash is ready")
press(Enum.KeyCode.LeftShift)
check(dashes == 1 and root:FindFirstChild("FartDash") and root.FartDash:IsA("LinearVelocity"), "Shift: a Fart Dash push, sent to the server")
press(Enum.KeyCode.LeftShift)
check(dashes == 1, "not again until the cooldown is up")
RunService.RenderStepped:Fire(0.016)
check(string.find(combat.dash.Text, "FART DASH %ds"), "the meter counts down")
UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
task.wait(0.05)
UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
check(shots == 1, "a left click fires one shot")
press(Enum.KeyCode.M)
check(home.menu.Enabled and home.resume.Modal, "M opens the menu with the mouse free")
RunService.RenderStepped:Fire(0.016)
check(not combat.crosshair.Visible and UserInputService.MouseIconEnabled, "with the cursor back")
task.wait(0.4)
UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
task.wait(0.05)
check(shots == 1, "no firing in the menu")
press(Enum.KeyCode.M)
check(not home.menu.Enabled, "M closes it")
key(Enum.KeyCode.Tab, true)
check(hud.scoreboard.Enabled, "Tab shows the scoreboard")
check(hud.columns.Stinkers:FindFirstChild("Me"), "with me under the Stinkers")
key(Enum.KeyCode.Tab, false)
check(not hud.scoreboard.Enabled, "and lets go")

-- A rival starts a round; the HUD follows the server.
local rival = Instance.new("Player")
rival.Name = "Rival"
rival.UserId = 2
rival.Parent = Players
wander(rival)
task.wait(0.1)
ReplicatedStorage.Remotes.RequestPlay.OnServerEvent:Fire(rival)
frames(1)
check(hud.phase.Text == "ROUND" and (hud.time.Text == "5:00" or hud.time.Text == "4:59"), "the round clock starts at 5:00")
check(hud.left.Count.Text == "1/10" and hud.right.Count.Text == "1/10", "1v1 on the HUD")
TestControls.score("Stinkers", 2)
frames(0.3)
check(hud.left.Score.Text == "2" and hud.right.Score.Text == "0", "the score")
frames(60)
check(hud.time.Text == "4:00" or hud.time.Text == "3:59", "a minute later the clock says so")

-- The AFK warning (Rival keeps moving; I stand still).
still[me] = true
TestControls.idle(me, 44)
frames(2)
check(hud.afk.Visible and hud.afk.Title.Text == "BRO FELL ASLEEP MID-FART!", "the AFK warning")
check(string.find(hud.afkCountdown.Text, "spectators in 1%d?s"), "with a countdown")
local root = me.Character.HumanoidRootPart
root.CFrame = root.CFrame * CFrame.new(12, 0, 0)
frames(1.5)
check(not hud.afk.Visible and me:GetAttribute("State") == "ACTIVE", "moving clears it")
still[me] = nil

-- Results.
TestControls.endPhase(0)
frames(0.5)
check(hud.results.Enabled and hud.resultTitle.Text == "SKIBIDI STINKERS WIN!", "the results name the winner")
check(hud.resultYou.Text == "Your team won!" and hud.resultScores.Text == "2  —  0", "with my result and the score")
check(string.find(hud.resultNext.Text, "Next round in 0:1"), "and the countdown")
frames(16)
check(not hud.results.Enabled and hud.left.Score.Text == "0", "the next round: results gone, scores reset")

-- Spectate from the menu, then the team picker.
press(Enum.KeyCode.M)
click(home.spectate)
task.wait(0.2)
check(me:GetAttribute("State") == "MENU_SPECTATOR" and home.home.Enabled, "SPECTATE goes back home")
check(me.Character == nil and cam.CameraType == Enum.CameraType.Scriptable, "avatar gone, live view back")
check(home.teamButtons.Stinkers:GetAttribute("Enabled") ~= false, "0v1: the Stinkers can have me")
check(home.teamButtons.Sharters:GetAttribute("Enabled") == false, "the Sharters can't (0v2)")
click(home.teamButtons.Sharters)
check(Home.selectedTeam == "Stinkers", "clicking a greyed team does nothing")
check(string.find(home.status.Text, "Round in progress"), "the status line says what's on")

return { status = "PASS", checks = checks }
