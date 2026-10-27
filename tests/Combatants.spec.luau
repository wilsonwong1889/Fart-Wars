-- Bots on the client, with one client. Bots aren't Player objects: each life
-- is an avatar in workspace.Bots, tagged "Bot", with BotId (negative),
-- TeamId and DisplayName, and CombatEvents name them by BotId. The screens
-- find them through Combatants. The bots here are stand-in avatars built by
-- the spec, so it checks the client alone (any bots the server adds just
-- come along):
--   * an id (a UserId, or a BotId) gives a name, a team and the avatar; a
--     bot's name outlives its avatar; an id nobody knows gives nil
--   * every avatar, players' and bots', is watched as it comes and goes,
--     each life of a bot a new one
--   * the kill feed and the EXPLODED cards name bots, in their team colour
--   * bots inflate with gas; bots on your team get the outline and symbol,
--     the other team's don't
--   * a bot's gun moves: its shots kick it, puff at its muzzle and draw the
--     bolt in its team's colour; a bot you hit flashes white
--   * the scoreboard and the Players screen list bots, with nothing to
--     block or report
--   * CombatEvents naming ids nobody knows (or no id) don't error
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
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
local WeaponModel = require(Shared.WeaponModel)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Team = require(server.Services.TeamService)
local Remotes = ReplicatedStorage.Remotes

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
local Combatants = require(Client.Combatants)
local CombatUI = require(Controllers.CombatController)
local Effects = require(Controllers.EffectsController)
local Fx = require(Controllers.WeaponFxController)
local HUD = require(Controllers.HUDController)
local PlayersUI = require(Controllers.PlayersController)
local ShotFx = require(Client.ShotFx)
task.wait(0.3)

-- I play for the Stinkers.
Lifecycle.requestPlay(me, "Stinkers")
task.wait(0.3)
if me:GetAttribute("TeamId") ~= "Stinkers" then
	Team.testSetTeam(me, "Stinkers")
	task.wait(0.2)
end
check(me:GetAttribute("TeamId") == "Stinkers" and me.Character, "I'm on the field for the Stinkers")

-- A stand-in bot's avatar, the way the server builds one: holding the Gas
-- Blaster, then tagged.
local folder = workspace:FindFirstChild("Bots")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = workspace
end
local function spawnBot(id: number, team: string, name: string, x: number): Model
	local avatar = Instance.new("Model")
	avatar.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(x, 3, 0)
	root.Parent = avatar
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = CFrame.new(x, 4.5, 0)
	head.Parent = avatar
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = name
	humanoid.Parent = avatar
	avatar.PrimaryPart = root
	for key, value in { BotId = id, TeamId = team, DisplayName = name, Gas = 0, GasStage = 0 } do
		avatar:SetAttribute(key, value)
	end
	local tool = WeaponModel.tool("GasBlaster", "Gas Blaster")
	tool.Handle.CFrame = CFrame.new(x + 1, 3.5, -1)
	tool.Parent = avatar
	avatar.Parent = folder
	CollectionService:AddTag(avatar, "Bot")
	return avatar
end

-- What the signals said about each avatar.
local arrived, left = {}, {}
Combatants.AvatarAdded:Connect(function(character, who)
	arrived[character] = who
end)
Combatants.AvatarRemoved:Connect(function(character, who)
	left[character] = who
end)
local watched = {}
Combatants.watch(function(character)
	watched[character] = (watched[character] or 0) + 1
end)
check(watched[me.Character] == 1, "watch() starts with the avatars already on the field")

-- Toots plays for the Sharters, Puff for my team.
local toots = spawnBot(-901, "Sharters", "[BOT] Toots", 20)
local puff = spawnBot(-902, "Stinkers", "[BOT] Puff", -20)
task.wait(0.1)
check(watched[toots] == 1 and watched[puff] == 1, "and hears each bot's avatar once, by its tag and its folder")
check(arrived[puff] and arrived[puff].id == -902 and arrived[puff].bot, "AvatarAdded says whose it is")

-- Ids to names, teams and avatars.
local who = Combatants.get(-901)
check(who and who.bot and who.name == "[BOT] Toots" and who.team == "Sharters" and who.character == toots and who.player == nil, "a BotId: the bot's name, team and avatar")
local mine = Combatants.get(me.UserId)
check(mine and not mine.bot and mine.player == me and mine.name == "Me" and mine.team == "Stinkers" and mine.character == me.Character, "a UserId: the player")
check(Combatants.get(-12345) == nil and Combatants.get(424242) == nil and Combatants.get(nil) == nil and Combatants.get("Toots") == nil, "nobody, for ids nobody knows")
check(Combatants.character(-902) == puff and Combatants.fromCharacter(puff).id == -902, "avatar from id, id from avatar")
check(Combatants.fromCharacter(me.Character).player == me and Combatants.fromCharacter(workspace) == nil, "a player's character is theirs; anything else is nobody's")
local onField = {}
for _, character in Combatants.avatars() do
	onField[character] = true
end
check(onField[me.Character] and onField[toots] and onField[puff], "every avatar on the field, players' and bots'")
local listed = {}
for _, bot in Combatants.bots() do
	listed[bot.id] = bot
end
check(listed[-901] and listed[-902] and listed[-901].name == "[BOT] Toots", "the bots on the field")

-- The kill feed and the cards.
local function lastLine(): TextLabel?
	local newest = nil
	for _, child in CombatUI.parts.feed:GetChildren() do
		if child:IsA("TextLabel") and (not newest or child.LayoutOrder < newest.LayoutOrder) then
			newest = child
		end
	end
	return newest
end
local SHARTERS, STINKERS = TeamConfig.teams.Sharters, TeamConfig.teams.Stinkers
Remotes.CombatEvent:FireClient(me, { kind = "elimination", killer = -901, victim = me.UserId, assists = {} })
task.wait(0.05)
local line = lastLine()
check(line and string.find(line.Text, `{SHARTERS.symbol} [BOT] Toots`, 1, true) and string.find(line.Text, `{STINKERS.symbol} Me`, 1, true), "the kill feed names the bot: " .. (line and line.Text or "?"))
check(line.TextColor3 == SHARTERS.color, "in its team's colour")
check(CombatUI.parts.card.Visible and CombatUI.parts.card.Text == `EXPLODED BY {SHARTERS.symbol} [BOT] TOOTS` and CombatUI.parts.card.TextColor3 == SHARTERS.color, "and the card says who got me: " .. CombatUI.parts.card.Text)
Remotes.CombatEvent:FireClient(me, { kind = "elimination", killer = me.UserId, victim = -901, assists = { -902 } })
task.wait(0.05)
check(CombatUI.parts.card.Text == `EXPLODED {SHARTERS.symbol} [BOT] TOOTS`, "my kill on a bot: " .. CombatUI.parts.card.Text)
check(string.find(lastLine().Text, "Me +1", 1, true), "a bot's assist counts on the line")
Remotes.CombatEvent:FireClient(me, { kind = "elimination", killer = -902, victim = -901, assists = { me.UserId } })
task.wait(0.05)
check(CombatUI.parts.card.Text == `ASSIST ON {SHARTERS.symbol} [BOT] TOOTS`, "an assist on a bot's kill of a bot")

-- Gas on a bot.
toots:SetAttribute("GasStage", 3)
task.wait(0.4)
local belly = toots:FindFirstChild("GasBelly")
check(belly and belly.Size.X > 4 and belly.CanQuery == false and belly.CanCollide == false, "a bot inflates with its gas stage")
check(toots:FindFirstChild("GasWarning"), "and gets the critical outline")
toots:SetAttribute("GasStage", 0)
task.wait(0.4)
check(not toots:FindFirstChild("GasWarning") and belly.Transparency == 1, "and deflates")

-- Teammates.
CombatUI.refreshTeammates()
check(puff:FindFirstChild("TeammateOutline") and puff.TeammateOutline.OutlineColor == STINKERS.color, "a bot on my team: the team outline")
check(puff:FindFirstChild("TeamMark") and puff.TeamMark:FindFirstChildOfClass("TextLabel").Text == STINKERS.symbol, "and the team symbol over its head")
check(not toots:FindFirstChild("TeammateOutline") and not toots:FindFirstChild("TeamMark"), "the other team's bot: neither")

-- A bot's gun and shots.
local tool = toots:FindFirstChild("HeldWeapon") :: Tool
check(tool and Fx.states[tool], "the bot's gun is animated from the moment it's held")
ShotFx.clear()
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = -901, from = Vector3.new(20, 4.5, 0), to = Vector3.new(20, 4.5, -40) })
task.wait()
check(Fx.states[tool].kick > 0 and tool.Handle.Muzzle:FindFirstChild("MuzzleFx"), "its shot kicks the gun and puffs at its muzzle")
local bolt = nil
for _, part in ShotFx.tracers do
	if part.Transparency == 0 and part.Glow.Color == SHARTERS.color then
		bolt = part
	end
end
check(bolt, "and draws the bolt in its team's colour")
Remotes.CombatEvent:FireClient(me, { kind = "hit", victim = -901, gas = 20, headshot = false, blocked = false })
task.wait()
local hitFlash = workspace:FindFirstChild("HitFlash") :: Highlight
check(hitFlash and hitFlash.Enabled and hitFlash.Adornee == toots, "a bot I hit flashes white")
check(CombatUI.parts.hitMarker.Visible, "with the hit marker")
Remotes.CombatEvent:FireClient(me, { kind = "damaged", attacker = -901, from = Vector3.new(20, 4.5, 0) })
task.wait()
check(CombatUI.parts.damageArrow.Visible, "a bot's hit on me: the arrow points at it")
local blasts = Effects.blastParticles
Remotes.CombatEvent:FireClient(me, { kind = "explosion", victim = -902, killer = -901, position = Vector3.new(-20, 3, 0) })
task.wait()
check(Effects.blastParticles == blasts + 1, "a bot's explosion bursts like anyone's")

-- The scoreboard and the Players screen.
HUD.renderScoreboard()
local row = HUD.parts.columns.Sharters:FindFirstChild("-901")
check(row and row.Text == "[BOT] Toots" and HUD.parts.columns.Stinkers:FindFirstChild("-902") and HUD.parts.columns.Stinkers:FindFirstChild("Me"), "the scoreboard lists the bots under their teams")
PlayersUI.open()
task.wait(0.1)
local botRow = PlayersUI.parts.list:FindFirstChild("-901")
check(botRow and string.find(botRow.PlayerName.Text, "[BOT] Toots", 1, true) and botRow:FindFirstChild("Bot"), "the Players screen lists a bot, marked BOT")
check(not botRow:FindFirstChild("Report") and not botRow:FindFirstChild("Block") and not botRow:FindFirstChild("Emotes"), "with nothing to block, hide or report")
check(not PlayersUI.parts.list:FindFirstChild("1") and not PlayersUI.parts.empty.Visible, "and still not me")

-- A bot's life ends: its avatar goes, its name stays; the next life is a new avatar.
toots:Destroy()
task.wait(0.1)
check(left[toots] and left[toots].id == -901 and left[toots].character == nil, "AvatarRemoved when its avatar goes")
check(not PlayersUI.parts.list:FindFirstChild("-901"), "off the Players screen while it's between lives")
local between = Combatants.get(-901)
check(between and between.bot and between.name == "[BOT] Toots" and between.team == "Sharters" and between.character == nil, "between lives: still named, no avatar")
Remotes.CombatEvent:FireClient(me, { kind = "elimination", killer = me.UserId, victim = -901, assists = {} })
task.wait(0.05)
check(string.find(lastLine().Text, "[BOT] Toots", 1, true), "so a late kill feed line still names it")
Remotes.CombatEvent:FireClient(me, { kind = "hit", victim = -901, gas = 20, headshot = false, blocked = false })
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = -901, from = Vector3.new(20, 4.5, 0), to = Vector3.new(20, 4.5, -40) })
task.wait()
local reborn = spawnBot(-901, "Sharters", "[BOT] Toots", 24)
task.wait(0.1)
check(watched[reborn] == 1 and Combatants.character(-901) == reborn, "the next life: a new avatar, watched like the first")
check(PlayersUI.parts.list:FindFirstChild("-901"), "back on the Players screen")
reborn:SetAttribute("GasStage", 2)
task.wait(0.4)
check(reborn:FindFirstChild("GasBelly") and reborn.GasBelly.Size.X > 3, "and it inflates too")
PlayersUI.close()

-- Ids nobody knows, or none: nothing breaks (an error here fails the spec).
for _, event in {
	{ kind = "elimination", killer = -777, victim = -778, assists = { -779 } },
	{ kind = "elimination", victim = -778 },
	{ kind = "shot", shooter = -777, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -30) },
	{ kind = "hit", victim = -777, gas = 20 },
	{ kind = "damaged", attacker = -777, from = Vector3.new(0, 5, 0) },
	{ kind = "explosion", victim = -778, killer = -777, position = Vector3.new(0, 3, 0) },
	{ kind = "explosion", position = Vector3.new(0, 3, 0) },
	{ kind = "alpha", player = -777 },
} do
	Remotes.CombatEvent:FireClient(me, event)
end
task.wait(0.1)
check(string.find(lastLine().Text, "Someone", 1, true), "an id nobody knows is Someone")

return { status = "PASS", checks = checks }
