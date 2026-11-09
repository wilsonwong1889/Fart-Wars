-- The client shell against the real server, in one stand-in world (the
-- harness loops remotes back, so this is one client talking to it):
--   * joining shows the home screen over the live battlefield (fixed views)
--   * TOP opens the weekly leaderboard; switched off, it says Coming Soon
--   * PLAY asks for a team (each card with its count, locked when unfair);
--     picking one joins it: the home screen goes, the HUD shows your team,
--     the hotbar your weapon, the top right your coins and the menu, the
--     controls card shows once, and the camera follows the avatar
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
local UIConfig = require(game:GetService("ReplicatedStorage").Shared.Config.UIConfig)
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
-- No bots: these checks count the players themselves.
require(server.Services.BotDirector).testSetEnabled(false)
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

local Leaderboard = require(client.Controllers.LeaderboardController)
local top = home.home:FindFirstChild("Leaderboard", true) :: TextButton
click(top)
check(Leaderboard.isOpen and gui.Leaderboard.Enabled and not home.comingSoon.Enabled, "TOP: this week's leaderboard")
click(Leaderboard.parts.screen:FindFirstChild("Close", true))
check(not Leaderboard.isOpen and not gui.Leaderboard.Enabled, "and closes")
Leaderboard.testEnable(false)
click(top)
check(home.comingSoon.Enabled and home.soonTitle.Text == "LEADERBOARD", "switched off: Coming Soon")
click(home.comingSoon:FindFirstChild("Close", true))
check(not home.comingSoon.Enabled, "and closes")
Leaderboard.testEnable(nil)

-- The lobby: the battlefield blurred, LOADOUT, SHOP and LEVELS, today's
-- cosmetics and the other offers two at a time, the bubble for a
-- first-timer, and Space.
local Lighting = game:GetService("Lighting")
local Locker = require(client.Controllers.LockerController)
check(Lighting.MenuBlur.Size == UIConfig.menuBlur, "the battlefield blurs behind the home screen")
check(home.pageButtons.Loadout.Name == "Loadout" and home.pageButtons.Weapons.Name == "Shop" and home.pageButtons.Progression.Name == "Levels", "LOADOUT, SHOP and LEVELS down the left")
local Loadout = require(client.Controllers.LoadoutController)
click(home.pageButtons.Loadout)
check(Loadout.isOpen and gui.Loadout.Enabled and not Locker.isOpen, "LOADOUT opens the loadout screen")
press(Enum.KeyCode.Space)
check(not home.teamSelect.Enabled, "Space doesn't PLAY under it")
click(Loadout.parts.back)
check(not Loadout.isOpen and not gui.Loadout.Enabled, "BACK closes it")
click(home.pageButtons.Weapons)
check(Locker.isOpen and Locker.tab == "Weapons" and Locker.section == "Featured", "SHOP: the shop, from the top")
Locker.close()
local function shownOffers(): { string }
	local cards = {}
	for _, child in home.offerRow:GetChildren() do
		if child:IsA("TextButton") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local names = {}
	for _, card in cards do
		table.insert(names, card.Name)
	end
	return names
end
-- (No profile here yet, so no weapon offer: the Shop spec has those.)
check(home.featured.Heading.Text == "TODAY IN THE SHOP", "the panel: today in the shop")
check(home.featured.Visible and table.concat(shownOffers(), ",") == "DailyShop,StarterPack", "today's cosmetics and the Starter Pack: " .. table.concat(shownOffers(), ","))
local dailyCard = home.offerRow.DailyShop
local dailyItems = 0
for _, tile in dailyCard.Items:GetChildren() do
	if tile:IsA("Frame") then
		dailyItems += 1
		check(tile.Window:FindFirstChild("Swatch") and tile.ItemName.Text ~= "", "each with its look and name")
	end
end
check(dailyItems == 3 and string.find(dailyCard.Timer.Text, ":", 1, true), "three of them, and the time left: " .. dailyCard.Timer.Text)
click(dailyCard)
check(Locker.isOpen and Locker.section == "Daily", "the daily card opens the shop's daily part")
Locker.close()
check(home.offerRow.StarterPack.Action.Label.Text == "SEE STORE", "the pack sends you to the store (no pass ID yet)")
check(home.nextOffer.Visible, "three offers: arrows")
click(home.offerRow.StarterPack)
check(Locker.isOpen and Locker.tab == "Weapons" and Locker.section == "Featured", "a card opens what it's about: the pack, at the shop's top")
Locker.close()
click(home.home.Wallet.Plus)
check(Locker.isOpen and Locker.section == "Coins" and Locker.parts.shop.CanvasPosition.Y > 0, "+ by the coins: the coin packs")
Locker.close()
me:SetAttribute("LifetimeXP", 0)
check(home.firstTip.Visible, "a first-timer gets the bubble pointing at PLAY")
press(Enum.KeyCode.Space)
check(home.teamSelect.Enabled and not home.firstTip.Visible, "Space is PLAY, and the bubble goes")
home.teamSelect.Enabled = false
Locker.open("Settings")
press(Enum.KeyCode.F)
check(not home.teamSelect.Enabled, "not while another screen is open")
Locker.close()

-- PLAY, then choose a team.
click(home.play)
check(home.teamSelect.Enabled and me:GetAttribute("State") == "MENU_SPECTATOR", "PLAY asks for a team first")
check(home.teamButtons.Stinkers.Count.Text == "0" and not home.teamButtons.Stinkers.Lock.Visible, "each team's card: its count, unlocked")
click(home.teamButtons.Stinkers)
task.wait(0.6)
check(Home.selectedTeam == "Stinkers" and me:GetAttribute("PreferredTeam") == "Stinkers", "the team choice reaches the server")
check(me:GetAttribute("State") == "ACTIVE" and me:GetAttribute("TeamId") == "Stinkers", "picking a team joins it")
check(not home.teamSelect.Enabled, "the team screen goes")
local Controllers = game.StarterPlayer.StarterPlayerScripts.Client.Controllers
local Hotbar = require(Controllers.HotbarController)
local MenuBar = require(Controllers.MenuBarController)
Hotbar.renderAbility()
check(Hotbar.parts.bar.Visible and Hotbar.parts.slots[1]:GetAttribute("Weapon") == "GasBlaster", "the hotbar: the Gas Blaster in slot 1")
check(Hotbar.parts.slots[1].Border.Color == UIConfig.colors.text and Hotbar.parts.slots[2]:GetAttribute("Weapon") == nil, "in hand, and nothing else owned yet")
check(not Hotbar.pick(2), "an empty slot does nothing")
check(MenuBar.parts.corner.Visible and MenuBar.parts.buttons.Loadout and MenuBar.parts.buttons.Weapons and MenuBar.parts.buttons.Settings, "coins and the menu buttons, top right")
check(not home.home.Enabled, "the home screen goes")
check(Lighting.MenuBlur.Size == 0, "and the blur with it")
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
-- The results (between rounds): the gun holds its fire, so nothing reaches
-- the server to be refused; the next round it fires again.
do
	local ClientState = require(game.StarterPlayer.StarterPlayerScripts.Client.ClientState)
	local live = ClientState.snapshot
	local results = table.clone(live :: any)
	results.phase = "RESULTS"
	ReplicatedStorage.Remotes.RoundUpdate:FireClient(me, results)
	task.wait(0.4)
	UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
	task.wait(0.05)
	UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
	check(shots == 1 and not ClientState.canFight(), "in the results a click sends nothing")
	ReplicatedStorage.Remotes.RoundUpdate:FireClient(me, live)
	task.wait(0.05)
	check(ClientState.canFight(), "the round back: fighting again")
end
-- Taps and timing (the Gas Blaster, a 0.3 s interval). A click a little
-- before the gun is ready fires once, when it is; one far too early is
-- dropped. Held, the gun keeps to its schedule: a shot a frame late doesn't
-- push the next one later (timed from each late shot, an automatic gun
-- lost a frame every shot).
do
	local Combat = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.CombatController)
	local function click()
		UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
		task.wait(0.03)
		UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
	end
	task.wait(0.5)
	local before = shots
	click()
	check(shots == before + 1, "a click with the gun ready fires")
	task.wait(0.15)
	click()
	check(shots == before + 1, "a click a little before it's ready: nothing yet")
	task.wait(0.2)
	check(shots == before + 2, "then it fires, once it's ready")
	task.wait(0.3)
	check(shots == before + 2, "just the once")
	click()
	check(shots == before + 3, "ready again: fires")
	click()
	task.wait(0.5)
	check(shots == before + 3, "a click far too early (over 0.2 s) is dropped")
	check(Combat.fire(), "on schedule")
	task.wait(0.316)
	check(Combat.fire(), "a frame late")
	task.wait(0.285)
	check(Combat.fire(), "and the next is back on schedule, not a frame later")
	task.wait(0.1)
	check(not Combat.fire(), "but never faster than the gun")
end
local shotsBeforeMenu = shots
press(Enum.KeyCode.M)
check(home.menu.Enabled and home.resume.Modal, "M opens the menu with the mouse free")
RunService.RenderStepped:Fire(0.016)
check(not combat.crosshair.Visible and UserInputService.MouseIconEnabled, "with the cursor back")
task.wait(0.4)
UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
task.wait(0.05)
check(shots == shotsBeforeMenu, "no firing in the menu")
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

-- Down: the HUD gives way to a countdown to the next life (the server's
-- RespawnAt), and a trigger held through it doesn't fire the new life's
-- first moment away (firing ends spawn protection).
do
	local ClientState = require(client.ClientState)
	local hotbar = require(client.Controllers.HotbarController).parts
	local function render()
		RunService.RenderStepped:Fire(0.016)
	end
	task.wait(0.5)
	local fireDown = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }
	local before = shots
	UserInputService.InputBegan:Fire(fireDown, false)
	task.wait(0.1)
	check(shots > before, "holding the trigger fires")
	local body = me.Character
	body.Humanoid.Health = 0
	task.wait(0.2)
	render()
	check(not ClientState.alive() and type(me:GetAttribute("RespawnAt")) == "number", "down, and the server says when the next life starts")
	check(combat.respawn.Visible and string.find(combat.respawn.Text, "^BACK IN %d$"), "a countdown: " .. combat.respawn.Text)
	check(not combat.crosshair.Visible and not combat.gasMeter.Visible and not combat.dashMeter.Visible, "no crosshair, gas bar or dash bar meanwhile")
	check(not hotbar.bar.Visible, "and no hotbar")
	task.wait(3.5)
	render()
	check(me.Character ~= body and ClientState.alive() and me:GetAttribute("RespawnAt") == nil, "the next life")
	check(not combat.respawn.Visible and combat.crosshair.Visible and hotbar.bar.Visible, "the HUD is back")
	local after = shots
	task.wait(1)
	check(shots == after, "the trigger held through the death doesn't fire the new life away")
	UserInputService.InputEnded:Fire(fireDown, false)
	task.wait(0.4)
	UserInputService.InputBegan:Fire(fireDown, false)
	task.wait(0.05)
	UserInputService.InputEnded:Fire(fireDown, false)
	check(shots == after + 1, "a fresh press fires")
end

-- The AFK warning (Rival keeps moving; I stand still).
still[me] = true
-- One AFK check first, so a wander step just before isn't seen as moving
-- after the idle time is set.
frames(1.1)
TestControls.idle(me, 44)
frames(2)
check(hud.afk.Visible and hud.afk.Title.Text == "BRO FELL ASLEEP MID-FART!", "the AFK warning")
do
	local order = (hud.afk:FindFirstAncestorWhichIsA("ScreenGui") :: ScreenGui).DisplayOrder
	local over = {}
	for _, screen in gui:GetChildren() do
		if screen:IsA("ScreenGui") and screen.Name ~= "SoftShutdown" and screen ~= hud.afk:FindFirstAncestorWhichIsA("ScreenGui") and screen.DisplayOrder >= order then
			table.insert(over, screen.Name)
		end
	end
	check(#over == 0, "drawn above every menu and the results, so it's seen from the shop too: " .. table.concat(over, ", "))
end
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
check(home.teamButtons.Sharters:GetAttribute("Enabled") == false and home.teamButtons.Sharters.Lock.Visible, "the Sharters can't (0v2): locked")
click(home.teamButtons.Sharters)
check(Home.selectedTeam == "Stinkers", "clicking a greyed team does nothing")
check(string.find(home.status.Text, "Round in progress"), "the status line says what's on")

return { status = "PASS", checks = checks }
