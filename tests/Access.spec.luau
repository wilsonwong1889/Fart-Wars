-- Accessibility and friends (masterplan 6.4), with one client:
--   * team symbols (▲ ●): on the score boxes and team cards, in the kill
--     feed and the Players screen, and over teammates' heads; off in
--     Settings takes them away
--   * HUD size: every panel scales around its own anchor, full-screen
--     backdrops don't; from Settings, in steps, within limits
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
