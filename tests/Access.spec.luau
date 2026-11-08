-- Accessibility and friends (masterplan 6.4), with one client:
--   * team symbols (▲ ●): on the score boxes and team cards, in the kill
--     feed and the Players screen, and over teammates' heads; off in
--     Settings takes them away
--   * HUD size: every panel scales around its own anchor, full-screen
--     backdrops don't; from Settings, in steps, within limits; at every
--     size, on a 768 or 820 tall screen, nothing runs into anything (the
--     home screen's tiles stay under the coin pill and on the screen; the
--     gas and Fart Dash bars over the hotbar, the weapon and streak over
--     them; the kill feed under the menu bar's SPIN / DAILY row)
--   * reduce motion: softer explosion bursts, a steady gas outline
--   * friends: the team cards say where your friends are
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local Shared = ReplicatedStorage.Shared
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local SettingsConfig = require(Shared.Config.SettingsConfig)
local Team = require(server.Services.TeamService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Gas = require(server.Services.GasService)
local Remotes = ReplicatedStorage.Remotes

-- Me and Pal are friends.
Team.checkFriends = function(a, b)
	return (a.UserId == 1 and b.UserId == 2) or (a.UserId == 2 and b.UserId == 1)
end
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Client = game.StarterPlayer.StarterPlayerScripts.Client
local Controllers = Client.Controllers
local Settings = require(Client.Settings)
local UI = require(Client.UI)
local HUD = require(Controllers.HUDController)
local Home = require(Controllers.HomeController)
local Locker = require(Controllers.LockerController)
local CombatUI = require(Controllers.CombatController)
local Hotbar = require(Controllers.HotbarController)
local MenuBar = require(Controllers.MenuBarController)
local Effects = require(Controllers.EffectsController)
local PlayersUI = require(Controllers.PlayersController)
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local pal = join("Pal", 2)
local foe = join("Foe", 3)
task.wait(0.5)

-- Symbols.
check(TeamConfig.teams.Stinkers.symbol ~= TeamConfig.teams.Sharters.symbol, "each team has its own symbol")
check(HUD.parts.left.TeamName.Text == "▲ STINKERS" or HUD.parts.left.TeamName.Text == "● SHARTERS", "on the score boxes: " .. HUD.parts.left.TeamName.Text)
check(string.find(Home.parts.teamButtons.Stinkers.TeamName.Text, "▲", 1, true), "and the team cards")

-- Friends on the cards.
Lifecycle.requestPlay(pal, "Stinkers")
task.wait(0.3)
Team.testSetTeam(pal, "Stinkers")
task.wait(0.2)
check(me:GetAttribute("Friends_Stinkers") == 1 and me:GetAttribute("Friends_Sharters") == nil, "the server counts my friends on each team")
Home.play()
task.wait(0.1)
check(Home.parts.teamButtons.Stinkers.Friends.Text == "👥 1 friend here" and Home.parts.teamButtons.Sharters.Friends.Text == "", "the cards say where my friends are")
-- (Stinkers is locked for me while it's 1 v 0: Foe goes first.)
Lifecycle.requestPlay(foe, "Sharters")
task.wait(0.3)
Team.testSetTeam(foe, "Sharters")
Home.pick("Stinkers")
task.wait(0.3)
Team.testSetTeam(me, "Stinkers")
task.wait(0.3)
check(me:GetAttribute("TeamId") == "Stinkers", "I join my friend's team")

-- Over teammates' heads.
CombatUI.refreshTeammates()
local mark = pal.Character and pal.Character:FindFirstChild("TeamMark")
check(mark and mark:FindFirstChildOfClass("TextLabel").Text == "▲", "my teammate has ▲ over their head")
check(not (foe.Character and foe.Character:FindFirstChild("TeamMark")), "the other team doesn't")
-- The kill feed.
Remotes.CombatEvent:FireClient(me, { kind = "elimination", killer = 2, victim = 3, assists = {} })
task.wait(0.05)
local line = nil
for _, child in CombatUI.parts.feed:GetChildren() do
	if child:IsA("TextLabel") then
		line = child
	end
end
check(line and string.find(line.Text, "▲ Pal", 1, true) and string.find(line.Text, "● Foe", 1, true), "the kill feed: " .. (line and line.Text or "?"))
-- The Players screen.
PlayersUI.open()
task.wait(0.1)
check(string.find(PlayersUI.parts.list["2"].PlayerName.Text, "▲ Pal", 1, true), "the Players screen")
PlayersUI.close()
-- Off.
Settings.teamSymbols = false
CombatUI.refreshTeammates()
check(not pal.Character:FindFirstChild("TeamMark") and UI.teamSymbol("Stinkers") == "", "team symbols off: gone")
Settings.teamSymbols = true

-- HUD size.
local hudScreen = me.PlayerGui:FindFirstChild("HUD")
local function scales(screen: Instance): { UIScale }
	local list = {}
	for _, child in screen:GetChildren() do
		local s = child:FindFirstChild("HudScale")
		if s then
			table.insert(list, s)
		end
	end
	return list
end
check(hudScreen and #scales(hudScreen) > 0, "HUD panels can scale")
local dim = me.PlayerGui.TeamSelect:FindFirstChild("Dim")
check(dim and not dim:FindFirstChild("HudScale"), "full-screen backdrops don't")
Locker.open("Settings")
task.wait(0.1)
local list = Locker.parts.content.Settings
list.HudSizeRow.HudSizeUp.Activated:Fire()
task.wait(0.1)
check(Settings.hudScale == 1.1 and Locker.parts.content.Settings.HudSizeRow.HudSize.Text == "HUD SIZE 110%", "HUD SIZE +")
for _, s in scales(hudScreen) do
	check(s.Scale == 1.1, "every panel at 110%")
end
for _ = 1, 5 do
	Locker.parts.content.Settings.HudSizeRow.HudSizeUp.Activated:Fire()
	task.wait(0.05)
end
check(Settings.hudScale == 1.25, "up to 125%")
for _ = 1, 8 do
	Locker.parts.content.Settings.HudSizeRow.HudSizeDown.Activated:Fire()
	task.wait(0.05)
end
check(Settings.hudScale == 0.8, "down to 80%")
Settings.hudScale = 1
UI.applyScale()
-- UI holds the panels' UIScales strongly (Roblox can collect a weak
-- table's instances while they're on screen, and HUD SIZE then changed
-- nothing mid-session), and lets each go once it leaves the game.
check(not string.find((Client.UI :: any).Source, "__mode", 1, true), "UI keeps the UIScales in a strong table")
local probe = UI.new("Frame", { Name = "Probe", Size = UDim2.new(0, 100, 0, 40), Parent = hudScreen })
task.wait()
local probeScale = probe:FindFirstChild("HudScale") :: UIScale
check(probeScale and probeScale.Scale == 1, "a new panel takes the HUD size")
probeScale.Parent = nil
Settings.hudScale = 1.1
UI.applyScale()
check(probeScale.Scale == 1, "out of the game, it's let go")
probeScale.Parent = probe
check(probeScale.Scale == 1.1, "back in, it follows again, at the size of the moment")
probe:Destroy()
Settings.hudScale = 1
UI.applyScale()
check(probeScale.Scale == 1.1, "destroyed, it's let go")

-- At every HUD size, on a 768 or 820 tall screen, nothing runs into
-- anything. The stand-ins lay nothing out, so `rect` works out where a
-- frame is: from its Position, Size and AnchorPoint inside its parents,
-- each UIScale growing its frame and all in it round the frame's anchor
-- (UI.springy's Press aside: it's 1 at rest).
local function rect(item: Instance, screen: Vector2): (Vector2, Vector2, number)
	local lo, hi, k = Vector2.zero, screen, 1
	local parent = item.Parent
	if parent and parent:IsA("GuiObject") then
		lo, hi, k = rect(parent, screen)
	end
	local frame = item :: GuiObject
	local own = 1
	for _, child in frame:GetChildren() do
		if child:IsA("UIScale") and child.Name ~= "Press" then
			own *= child.Scale
		end
	end
	local area = hi - lo
	local size = (Vector2.new(frame.Size.X.Scale * area.X, frame.Size.Y.Scale * area.Y) + Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset) * k) * own
	local anchor = lo + Vector2.new(frame.Position.X.Scale * area.X, frame.Position.Y.Scale * area.Y) + Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset) * k
	local at = anchor - frame.AnchorPoint * size
	return at, at + size, k * own
end
local home = Home.parts
-- Calls `test` on each screen at each HUD size.
local function eachLayout(test: (screen: Vector2, label: string) -> ())
	for _, height in { 768, 820 } do
		local screen = Vector2.new(1366, height)
		home.home.AbsoluteSize = screen
		for _, size in SettingsConfig.settings.hudScale.steps do
			Settings.hudScale = size
			UI.applyScale()
			test(screen, `{height} tall at {math.floor(size * 100 + 0.5)}%`)
		end
	end
	Settings.hudScale = 1
	UI.applyScale()
	home.home.AbsoluteSize = Vector2.new(1280, 720)
end
-- The home screen's tiles (six, and seven while a season is on): from
-- below the coin pill to the screen's bottom, full size wherever they fit.
for _, season in { false, true } do
	workspace:SetAttribute("SeasonActive", season)
	eachLayout(function(screen, label)
		local shown = {}
		for _, entry in UIConfig.lobbyTiles do
			if home.tiles[entry.id].Visible then
				table.insert(shown, home.tiles[entry.id])
			end
		end
		label ..= `, {#shown} tiles`
		local _, pill = rect(home.home.Wallet.Pill, screen)
		local first = rect(shown[1], screen)
		local _, last = rect(shown[#shown], screen)
		check(first.Y >= pill.Y, `{label}: the tiles start below the coin pill ({first.Y} vs {pill.Y})`)
		check(last.Y <= screen.Y, `{label}: and end on the screen ({last.Y})`)
		local unshrunk = first.Y + (last.Y - first.Y) / home.tileFit.Scale
		check(home.tileFit.Scale == 1 or unshrunk > screen.Y - 12, `{label}: full size where they fit`)
	end)
end
workspace:SetAttribute("SeasonActive", nil)
check(home.tileFit.Scale == 1, "the tiles full size again")
-- In a match: the gas and Fart Dash bars over the hotbar, the weapon in
-- hand and the streak over them.
eachLayout(function(screen, label)
	local hotbarTop = rect(Hotbar.parts.bar, screen)
	local barsTop, barsBottom = rect(CombatUI.parts.bars, screen)
	check(barsBottom.Y <= hotbarTop.Y, `{label}: the gas and Fart Dash bars clear the hotbar ({barsBottom.Y} vs {hotbarTop.Y})`)
	for _, name in { "weapon", "streak" } do
		local _, bottom = rect(CombatUI.parts[name], screen)
		check(bottom.Y <= barsTop.Y, `{label}: the {name} line clears the bars ({bottom.Y} vs {barsTop.Y})`)
	end
	-- The kill feed under the menu bar's corner and its last row, the free
	-- spin and the daily reward (always there for a new player).
	local _, corner = rect(MenuBar.parts.corner, screen)
	local _, claims = rect(MenuBar.parts.spin.Parent, screen)
	local feed = rect(CombatUI.parts.feed, screen)
	check(feed.Y >= corner.Y and feed.Y >= claims.Y, `{label}: the kill feed starts under the SPIN / DAILY row ({feed.Y} vs {claims.Y})`)
end)
-- Choose a Team: the cards, AUTO under them and the hint under that never
-- run into each other, and the hint ends on the screen.
eachLayout(function(screen, label)
	local autoLo, autoHi = rect(home.teamButtons.Auto, screen)
	local hintLo, hintHi, k = rect(home.teamHint, screen)
	-- (It grows down to fit its two lines; the stand-ins don't.)
	hintHi = Vector2.new(hintHi.X, math.max(hintHi.Y, hintLo.Y + 2 * home.teamHint.TextSize * k))
	local function apart(aLo: Vector2, aHi: Vector2, bLo: Vector2, bHi: Vector2): boolean
		return aHi.X <= bLo.X or bHi.X <= aLo.X or aHi.Y <= bLo.Y or bHi.Y <= aLo.Y
	end
	for name, card in home.teamButtons do
		if name ~= "Auto" then
			local cardLo, cardHi = rect(card, screen)
			check(apart(cardLo, cardHi, autoLo, autoHi), `{label}: the {name} card clears AUTO ({cardHi.Y} vs {autoLo.Y})`)
			check(apart(cardLo, cardHi, hintLo, hintHi), `{label}: and the hint`)
		end
	end
	check(apart(autoLo, autoHi, hintLo, hintHi), `{label}: AUTO clears the hint ({autoHi.Y} vs {hintLo.Y})`)
	check(hintHi.Y <= screen.Y, `{label}: the hint ends on the screen ({hintHi.Y})`)
end)

-- Reduce motion.
Locker.parts.content.Settings.ReduceMotionRow.ReduceMotion.Activated:Fire()
task.wait(0.1)
check(Settings.reduceMotion, "REDUCE MOTION on")
Locker.close()
Effects.explosion(Vector3.new(0, 5, 0))
local soft = false
for _, burst in Effects.pool do
	if burst.Material == Enum.Material.SmoothPlastic and burst.Transparency >= 0.5 then
		soft = true
	end
end
check(soft, "a softer explosion burst")
task.wait(3.2)
Gas.testSetGas(foe, 85)
task.wait(0.5)
local warning = foe.Character and foe.Character:FindFirstChild("GasWarning")
check(warning and warning.FillTransparency == 0.55, "a steady gas outline, no pulse")
Settings.reduceMotion = false

return { status = "PASS", checks = checks }
