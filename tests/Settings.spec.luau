-- Saved settings (SettingsConfig, SettingsService, SettingsController),
-- against a stand-in DataStore that stores JSON like the real one, with one
-- client:
--   * the list: Settings.luau starts from SettingsConfig's defaults; a value
--     is only ever a listed step, a listed colour or a real boolean
--   * the server: a new profile has no saved choices; a save goes into the
--     profile, adds to what's saved, is written on leaving and is back on
--     rejoining; one save a second (a faster one refused and counted);
--     junk (wrong types, unknown names, values off the list, NaN, huge
--     tables, junk actions) refused, changing nothing; damaged saved
--     choices back to their defaults, a newer build's kept, an older save
--     without the field loading; still SaveVersion 1
--   * the client: saved choices back on joining, with their effects (low
--     detail, HUD size, field of view, sensitivity, the crosshair), shown on
--     the Settings page; changes there saved shortly after, in one save
--     however many clicks, and an honest client never refused
--   * field of view and sensitivity in third and first person (V), with
--     the M menu open and closed, the mouse freed with Alt and locked
--     again; off the avatar (the home screen's shots) the usual field of
--     view; the crosshair's colour and size; the weapon previews keep
--     their own view
--   * the next visit: a fresh client gets back what was picked, and a
--     choice made while the saved ones load wins
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
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
-- No bots: just the players here.
require(server.Services.BotDirector).testSetEnabled(false)
local Data = require(server.Services.DataService)
local SettingsService = require(server.Services.SettingsService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Telemetry = require(server.Telemetry)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig)
local Remotes = ReplicatedStorage.Remotes
local client = game.StarterPlayer.StarterPlayerScripts.Client
local Settings = require(client.Settings)

-- The stand-in store.
local saved: { [string]: any } = {}
local latency = 0
local function copy(value: any): any
	return if value == nil then nil else HttpService:JSONDecode(HttpService:JSONEncode(value))
end
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		if latency > 0 then
			task.wait(latency)
		end
		local result = transform(copy(saved[key]))
		if result ~= nil then
			saved[key] = copy(result)
		end
		return result
	end,
})
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function rejects(reason: string): number
	local byReason = Telemetry.snapshot().rejects.SettingsRequest
	return byReason and byReason[reason] or 0
end
local function waitFor(condition: () -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while not condition() do
		if os.clock() > deadline then
			return false
		end
		task.wait(0.1)
	end
	return true
end
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local function ready(player: Player): boolean
	return waitFor(function()
		return Data.isLoaded(player)
	end, 3)
end
local function leave(player: Player)
	player.Parent = nil
	task.wait(0.1)
end
-- What a client's SettingsRequest:InvokeServer(...) reaches.
local function ask(player: Player, ...: any): { [string]: any }
	return Remotes.SettingsRequest.OnServerInvoke(player, ...)
end
local function same(a: { [string]: any }, b: { [string]: any }): boolean
	for key, value in a do
		if b[key] ~= value then
			return false
		end
	end
	for key, value in b do
		if a[key] ~= value then
			return false
		end
	end
	return true
end

-- The list.
for key, setting in SettingsConfig.settings do
	check((Settings :: any)[key] == setting.default, `Settings.{key} starts at SettingsConfig's default`)
	check(SettingsConfig.check(key, setting.default) == setting.default, `{key}'s default is one of its values`)
end
check(SettingsConfig.settings.fieldOfView.default == 70 and SettingsConfig.settings.sensitivity.default == 1, "Roblox's own field of view and sensitivity to start with")
check(SettingsConfig.check("fieldOfView", 90) == 90 and SettingsConfig.check("fieldOfView", 90 + 1e-9) == 90, "a step, or as near as a save carries it")
check(SettingsConfig.check("fieldOfView", 91) == nil and SettingsConfig.check("fieldOfView", 9000) == nil, "nothing between steps or past the ends")
check(SettingsConfig.check("sensitivity", 0 / 0) == nil and SettingsConfig.check("sensitivity", math.huge) == nil, "never NaN or infinity")
check(SettingsConfig.check("sound", "yes") == nil and SettingsConfig.check("sound", false) == false, "toggles are true or false")
check(SettingsConfig.check("crosshairColor", "Cyan") == "Cyan" and SettingsConfig.check("crosshairColor", "Plaid") == nil, "colours from the list")
check(SettingsConfig.check("hacks", true) == nil and SettingsConfig.check(7, true) == nil, "only real settings")
for _, name in SettingsConfig.settings.crosshairColor.choices :: { string } do
	check(typeof(SettingsConfig.crosshairColors[name]) == "Color3", `{name} has a colour`)
end
check(SettingsConfig.crosshairColors.White == Color3.fromRGB(245, 242, 250), "white is the crosshair's colour from before")
check(SettingsConfig.step("fieldOfView", 70, 1) == 75 and SettingsConfig.step("fieldOfView", 110, 1) == 110 and SettingsConfig.step("fieldOfView", 60, -1) == 60, "- and + walk the steps and stop at the ends")
check(SettingsConfig.step("crosshairColor", "Red", 1) == "White" and SettingsConfig.step("crosshairColor", "White", -1) == "Red", "colours go round")
check(SettingsConfig.step("volume", 1, -1) == 0.75 and SettingsConfig.step("hudScale", 1, 1) == 1.1, "volume in quarters and the HUD sizes, as before")

-- The server: save, leave, rejoin.
local ada = join("Ada", 201)
check(ready(ada), "Ada's profile loads")
local data = assert(Data.get(ada)).data
local answer = ask(ada, "get")
check(answer.ok and type(answer.settings) == "table" and next(answer.settings) == nil, "a new player has no saved choices: every setting at its default")
check(type(data.Settings) == "table" and next(data.Settings) == nil, "an empty Settings field in a new profile")
task.wait(SettingsService.SAVE_GAP)
answer = ask(ada, "save", { fieldOfView = 90, sensitivity = 0.5, crosshairColor = "Pink", lockMouse = false })
check(answer.ok and answer.reason == "saved", "a save")
check(data.Settings.fieldOfView == 90 and data.Settings.sensitivity == 0.5 and data.Settings.crosshairColor == "Pink" and data.Settings.lockMouse == false, "goes into the profile")
answer = ask(ada, "save", { fieldOfView = 100 })
check(not answer.ok and answer.reason == "rateLimited" and data.Settings.fieldOfView == 90, "another within a second is refused")
check(rejects("rateLimited") == 1, "and counted")
task.wait(SettingsService.SAVE_GAP)
answer = ask(ada, "save", { volume = 0.25 })
check(answer.ok and data.Settings.volume == 0.25 and data.Settings.fieldOfView == 90 and data.Settings.crosshairColor == "Pink", "a later save adds to what's saved")

-- Junk.
local before = table.clone(data.Settings)
local huge = {}
for i = 1, 1000 do
	huge[`setting{i}`] = true
end
local junk = {
	"loud",
	7,
	true,
	{ fieldOfView = 9000 },
	{ fieldOfView = 91 },
	{ fieldOfView = 0 / 0 },
	{ fieldOfView = math.huge },
	{ fieldOfView = "90" },
	{ sensitivity = -1 },
	{ sound = "yes" },
	{ sound = 1 },
	{ crosshairColor = "Plaid" },
	{ crosshairColor = string.rep("x", 10000) },
	{ hacks = true },
	{ [1] = true },
	{ volume = { 1 } },
	{ fieldOfView = 90, coins = 999999 },
	huge,
}
for i, payload in junk do
	answer = ask(ada, "save", payload)
	check(not answer.ok and answer.reason == "badPayload", `junk save {i} refused`)
end
local actions = 0
for _, action in { 7, "delete", "set", { "save" }, "SAVE" } do
	answer = ask(ada, action, { volume = 1 })
	check(not answer.ok and answer.reason == "badPayload", `a junk action refused: {tostring(action)}`)
	actions += 1
end
answer = ask(ada)
check(not answer.ok and answer.reason == "badPayload", "no action at all, refused")
check(same(data.Settings, before), "junk changes nothing")
check(rejects("badPayload") == #junk + actions + 1, "every one counted")

-- Written on leaving, back on rejoining.
leave(ada)
local stored = saved.player_201
check(stored and stored.Settings.fieldOfView == 90 and stored.Settings.volume == 0.25 and stored.Settings.lockMouse == false, "leaving writes them to the store")
check(stored.SaveVersion == 1 and Data.VERSION == 1, "a field with a default: still SaveVersion 1")
local ada2 = join("Ada", 201)
check(ready(ada2), "Ada's back")
answer = ask(ada2, "get")
check(answer.ok and same(answer.settings, { fieldOfView = 90, sensitivity = 0.5, crosshairColor = "Pink", lockMouse = false, volume = 0.25 }), "with every choice saved last time")
leave(ada2)

-- Damaged saves, a newer build's choice, and saves from before the field.
saved.player_202 = {
	SaveVersion = 1,
	Coins = 5,
	Settings = {
		fieldOfView = 9000,
		volume = "max",
		crosshairColor = "Plaid",
		lockMouse = "yes",
		sensitivity = 2,
		teamSymbols = false,
		colorblindMode = "deutan",
		[string.rep("k", 100)] = true,
	},
}
local bo = join("Bo", 202)
check(ready(bo), "Bo's damaged save loads")
local boSettings = assert(Data.get(bo)).data.Settings
check(boSettings.fieldOfView == nil and boSettings.volume == nil and boSettings.crosshairColor == nil and boSettings.lockMouse == nil, "damaged choices go back to their defaults")
check(boSettings.sensitivity == 2 and boSettings.teamSymbols == false and assert(Data.get(bo)).data.Coins == 5, "the good ones (and the coins) are kept")
check(boSettings.colorblindMode == "deutan", "a newer build's choice is kept as it was")
check(boSettings[string.rep("k", 100)] == nil, "a junk name isn't")
answer = ask(bo, "get")
check(same(answer.settings, { sensitivity = 2, teamSymbols = false }), "the client only gets this build's choices")
leave(bo)
check(saved.player_202.Settings.colorblindMode == "deutan" and saved.player_202.Settings.sensitivity == 2, "and the newer one survives the save")
saved.player_203 = { SaveVersion = 1, Coins = 7, Settings = "loud" }
saved.player_204 = { SaveVersion = 1, Coins = 3, Level = 4 }
local cy = join("Cy", 203)
local di = join("Di", 204)
check(ready(cy) and ready(di), "a Settings field of the wrong type, and none at all, both load")
check(next(assert(Data.get(cy)).data.Settings) == nil and next(assert(Data.get(di)).data.Settings) == nil, "with no saved choices")
check(assert(Data.get(di)).data.Level == 4 and assert(Data.get(di)).data.SaveVersion == 1, "and everything else as it was")
leave(cy)
leave(di)

-- The client, joining with settings saved on an earlier visit.
saved.player_1 = {
	SaveVersion = 1,
	Coins = 40,
	Settings = { fieldOfView = 90, sensitivity = 0.5, crosshairColor = "Cyan", crosshairSize = 1.5, lowDetail = true, hudScale = 1.1, tips = false },
}
local refusedBefore = rejects("badPayload") + rejects("rateLimited")
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(client.ClientBootstrap)
task.wait(0.5)
local Controllers = client.Controllers
local SettingsController = require(Controllers.SettingsController)
local Camera = require(Controllers.CameraController)
local Combat = require(Controllers.CombatController)
local Home = require(Controllers.HomeController)
local Locker = require(Controllers.LockerController)
local Rewards = require(Controllers.RewardsController)
local MouseLock = require(client.MouseLock)
check(waitFor(function()
	return SettingsController.state ~= "loading"
end, 5), "the saved settings load")
check(SettingsController.state == "saving", "into a profile that saves")
check(Settings.fieldOfView == 90 and Settings.sensitivity == 0.5 and Settings.crosshairColor == "Cyan" and Settings.crosshairSize == 1.5, "the view, sensitivity and crosshair are back")
check(Settings.lowDetail and Settings.hudScale == 1.1 and Settings.tips == false, "and the rest")
check(Settings.chosen.fieldOfView and Settings.chosen.tips and not Settings.chosen.volume, "as picks of the player's own; unpicked ones stay at their defaults")
check(Lighting.GlobalShadows == false, "low detail: the shadows go at once")
local hud = me.PlayerGui:FindFirstChild("HUD")
local scaledPanels = 0
for _, panel in hud and hud:GetChildren() or {} do
	local hudScale = panel:FindFirstChild("HudScale")
	if hudScale then
		check(hudScale.Scale == 1.1, `{panel.Name} at 110%`)
		scaledPanels += 1
	end
end
check(scaledPanels > 0, "the HUD at the saved size")

-- Roblox's camera, bound just before ours: it resets the mouse every
-- frame, locking it in first person as LockFirstPerson does.
local cam = workspace.CurrentCamera
local LOCKED, FREE = Enum.MouseBehavior.LockCenter, Enum.MouseBehavior.Default
RunService:BindToRenderStep("RobloxCamera", Enum.RenderPriority.Camera.Value, function()
	UserInputService.MouseBehavior = if me.CameraMode == Enum.CameraMode.LockFirstPerson then LOCKED else FREE
end)
local function frame()
	RunService:RenderFrame(1 / 60)
end
local function click(button: Instance)
	(button :: GuiButton).Activated:Fire()
	task.wait(0.05)
end
local function press(code: Enum.KeyCode)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	UserInputService.InputBegan:Fire(input, false)
	UserInputService.InputEnded:Fire(input, false)
	task.wait(0.05)
end
local function viewIs(fov: number, sensitivity: number): boolean
	return cam.FieldOfView == fov and UserInputService.MouseDeltaSensitivity == sensitivity
end
frame()
check(viewIs(70, 0.5), "on the home screen: the saved sensitivity; the live shots keep the usual field of view")

-- In a match, third person and first.
local home = Home.parts
if Rewards.parts.daily.Enabled then
	click(Rewards.parts.daily:FindFirstChild("Close", true))
end
click(home.play)
click(home.teamButtons.Stinkers)
task.wait(0.6)
check(me:GetAttribute("State") == "ACTIVE", "in a match")
frame()
check(not Camera.firstPerson and Camera.locked() and UserInputService.MouseBehavior == LOCKED, "third person, the mouse locked")
check(viewIs(90, 0.5), "third person: field of view 90, sensitivity 0.5")
press(Enum.KeyCode.V)
frame()
check(Camera.firstPerson and me.CameraMode == Enum.CameraMode.LockFirstPerson and UserInputService.MouseBehavior == LOCKED, "V: first person")
check(viewIs(90, 0.5), "first person: the same")

-- The crosshair: cyan, half as big again.
Combat.render()
local function tickShaped(color: Color3, length: number, gap: number): boolean
	for _, tick in Combat.parts.ticks do
		local frameSize = tick.frame.Size
		local along = if tick.vertical then frameSize.Y.Offset else frameSize.X.Offset
		local across = if tick.vertical then frameSize.X.Offset else frameSize.Y.Offset
		local at = if tick.vertical then tick.frame.Position.Y.Offset else tick.frame.Position.X.Offset
		if tick.frame.BackgroundColor3 ~= color or along ~= length or across ~= 2 or at ~= tick.sign * gap then
			return false
		end
	end
	return #Combat.parts.ticks == 4
end
check(tickShaped(SettingsConfig.crosshairColors.Cyan, 15, 14), "the crosshair in the saved colour and size")

-- The M menu: the mouse is free, the view holds; Settings from it.
press(Enum.KeyCode.M)
frame()
check(MouseLock.holds("GameMenu") and UserInputService.MouseBehavior == FREE, "M: the menu frees the mouse")
check(viewIs(90, 0.5), "the view and sensitivity hold with the menu open")
click(home.menu:FindFirstChild("Settings", true))
check(Locker.isOpen and Locker.tab == "Settings", "SETTINGS from the menu")
local function list(): Instance
	return Locker.parts.content.Settings
end
check(list().FieldOfViewRow.FieldOfView.Text == "FIELD OF VIEW 90", "the page shows the saved field of view")
check(list().SensitivityRow.Sensitivity.Text == "SENSITIVITY 0.5x", "and sensitivity")
check(list().CrosshairSizeRow.CrosshairSize.Text == "CROSSHAIR 150%", "the crosshair's size")
check(list().CrosshairColorRow.CrosshairColor.Text == "CROSSHAIR CYAN" and list().CrosshairColorRow.CrosshairColor.TextColor3 == SettingsConfig.crosshairColors.Cyan, "and colour, in that colour")
check(list().LowDetailRow.LowDetail.Text == "LOW DETAIL: ON" and list().HudSizeRow.HudSize.Text == "HUD SIZE 110%", "and the rest")
check(string.find(list().SaveNote.Text, "Saved to your profile", 1, true) ~= nil, "it says the settings are saved")
local savesBefore = counter("Settings.saves")
click(list().FieldOfViewRow.FieldOfViewUp)
frame()
check(Settings.fieldOfView == 95 and cam.FieldOfView == 95 and list().FieldOfViewRow.FieldOfView.Text == "FIELD OF VIEW 95", "FIELD OF VIEW +: 95, at once, with the menu open")
click(list().SensitivityRow.SensitivityDown)
frame()
check(Settings.sensitivity == 0.4 and UserInputService.MouseDeltaSensitivity == 0.4 and list().SensitivityRow.Sensitivity.Text == "SENSITIVITY 0.4x", "SENSITIVITY -: 0.4x, at once")
click(list().CrosshairColorRow.CrosshairColorUp)
click(list().CrosshairSizeRow.CrosshairSizeDown)
Combat.render()
check(Settings.crosshairColor == "Pink" and Settings.crosshairSize == 1.25, "the crosshair: pink, 125%")
check(tickShaped(SettingsConfig.crosshairColors.Pink, 13, 11), "the crosshair changes with it")
for _ = 1, 12 do
	click(list().FieldOfViewRow.FieldOfViewUp)
end
check(Settings.fieldOfView == 110 and list().FieldOfViewRow.FieldOfView.Text == "FIELD OF VIEW 110", "up to 110, no further")
for _ = 1, 3 do
	click(list().FieldOfViewRow.FieldOfViewDown)
end
check(Settings.fieldOfView == 95, "and back down to 95")

-- Everything closed: locked, with the new view; Alt frees it and locks it again.
press(Enum.KeyCode.M)
frame()
check(not Locker.isOpen and not MouseLock.isFree() and UserInputService.MouseBehavior == LOCKED, "M closes the menu and the page: locked again")
check(viewIs(95, 0.4), "with the new field of view and sensitivity")
press(Enum.KeyCode.LeftAlt)
frame()
check(MouseLock.holds("key") and UserInputService.MouseBehavior == FREE, "Alt frees the mouse")
check(viewIs(95, 0.4), "the view and sensitivity hold")
press(Enum.KeyCode.LeftAlt)
frame()
check(not MouseLock.isFree() and UserInputService.MouseBehavior == LOCKED and viewIs(95, 0.4), "Alt again: locked, the same")
press(Enum.KeyCode.V)
frame()
check(not Camera.firstPerson and UserInputService.MouseBehavior == LOCKED and viewIs(95, 0.4), "V: third person, the same")
press(Enum.KeyCode.LeftAlt)
frame()
check(UserInputService.MouseBehavior == FREE and viewIs(95, 0.4), "Alt in third person: free, the same")
press(Enum.KeyCode.LeftAlt)
frame()
check(UserInputService.MouseBehavior == LOCKED and viewIs(95, 0.4), "and locked again")

-- Out of the match: the home screen's shots, the usual field of view.
Lifecycle.requestSpectate(me)
task.wait(0.3)
frame()
check(me:GetAttribute("State") ~= "ACTIVE" and cam.CameraType == Enum.CameraType.Scriptable, "spectating: the home screen's shots")
check(viewIs(70, 0.4), "the usual field of view there; the sensitivity stays")

-- The weapon previews keep their own camera.
local previews = 0
for _, item in me.PlayerGui:GetDescendants() do
	if item:IsA("ViewportFrame") and item:GetAttribute("Weapon") and item.CurrentCamera then
		check(item.CurrentCamera.FieldOfView == 30, "a weapon preview keeps its own field of view")
		previews += 1
	end
end
check(previews > 0, "the hotbar's previews were looked at")

-- Saved shortly after the last click, in one save.
local profile = assert(Data.get(me)).data
check(profile.Settings.fieldOfView == 90, "not saved on every click")
check(waitFor(function()
	return profile.Settings.fieldOfView == 95
end, SettingsController.SAVE_DELAY + 1), "saved shortly after the last change")
check(profile.Settings.sensitivity == 0.4 and profile.Settings.crosshairColor == "Pink" and profile.Settings.crosshairSize == 1.25, "every change")
check(profile.Settings.lowDetail == true and profile.Settings.tips == false and profile.Settings.hudScale == 1.1, "with what was saved before")
check(counter("Settings.saves") == savesBefore + 1, "in one save, however many clicks")
check(rejects("badPayload") + rejects("rateLimited") == refusedBefore, "an honest client is never refused")

-- The next visit, on a fresh client: the defaults until the saved
-- settings arrive (slowly this time); a choice made meanwhile wins.
leave(me)
task.wait(0.5)
check(saved.player_1.Settings.fieldOfView == 95 and saved.player_1.Settings.crosshairColor == "Pink" and saved.player_1.Coins >= 40, "leaving writes them to the store")
SettingsController.reset()
check(Settings.fieldOfView == 70 and Settings.sensitivity == 1 and Settings.crosshairColor == "White" and next(Settings.chosen) == nil, "a fresh client starts from the defaults")
latency = 2
local me2 = Instance.new("Player")
me2.Name = "Me"
me2.DisplayName = "Me"
me2.UserId = 1
Instance.new("PlayerGui").Parent = me2
Players.LocalPlayer = me2
me2.Parent = Players
local loaded: boolean? = nil
task.spawn(function()
	loaded = SettingsController.load()
end)
task.wait(0.5)
check(SettingsController.state == "loading" and loaded == nil, "loading (a slow store)")
SettingsController.choose("fieldOfView", 80)
SettingsController.choose("reduceMotion", true)
check(waitFor(function()
	return loaded ~= nil
end, 10) and loaded == true, "the saved settings arrive")
latency = 0
check(Settings.fieldOfView == 80 and Settings.reduceMotion, "a choice made while they loaded wins")
check(Settings.sensitivity == 0.4 and Settings.crosshairColor == "Pink" and Settings.crosshairSize == 1.25 and Settings.lowDetail, "the rest are back from last time")
local profile2 = assert(Data.get(me2)).data
check(waitFor(function()
	return profile2.Settings.fieldOfView == 80
end, SettingsController.SAVE_DELAY + 1), "the next save has the new choices")
check(profile2.Settings.reduceMotion == true and profile2.Settings.sensitivity == 0.4 and profile2.Settings.crosshairColor == "Pink", "and the old ones")
check(rejects("badPayload") + rejects("rateLimited") == refusedBefore, "still never refused")

return { status = "PASS", checks = checks }
