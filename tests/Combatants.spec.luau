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
--   * a bot's gun is the one its life carries: Combatants says which, its
--     shots kick that gun and sound like it, a Lobber's throws draw the arc;
--     its dashes and its Q are heard like anyone's
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
local Audio = require(Client.Audio)
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

-- A stand-in bot's avatar, the way the server builds one: holding its gun,
-- then tagged. Given a `weapon`, it holds that and says so (the life's
-- "Weapon"); else the Gas Blaster, saying nothing.
local folder = workspace:FindFirstChild("Bots")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = workspace
end
local function spawnBot(id: number, team: string, name: string, x: number, weapon: string?): Model
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
	for key, value in { BotId = id, TeamId = team, DisplayName = name, Gas = 0, GasStage = 0, Weapon = weapon } do
		avatar:SetAttribute(key, value)
	end
	local tool = WeaponModel.tool(weapon or "GasBlaster")
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

-- A bot's gun is the one its life carries.
check(Combatants.get(-901).weapon == "GasBlaster", "Combatants knows the gun in a bot's hands")
local clapper = spawnBot(-903, "Sharters", "[BOT] Clapper", 40, "Thunderclapper")
local lobber = spawnBot(-904, "Sharters", "[BOT] Lobber", 60, "StinkLobber")
task.wait(0.1)
check(Combatants.get(-903).weapon == "Thunderclapper" and Combatants.get(-904).weapon == "StinkLobber", "and the one its life carries")
local played = {}
local play = Audio.play
Audio.play = function(name, ...)
	table.insert(played, name)
	return play(name, ...)
end
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = -903, from = Vector3.new(40, 4.5, 0), to = Vector3.new(40, 4.5, -60) })
task.wait()
local clapperGun = clapper:FindFirstChild("HeldWeapon") :: Tool
check(Fx.states[clapperGun] and Fx.states[clapperGun].weapon == "Thunderclapper" and Fx.states[clapperGun].kick > 0, "its shot kicks the Thunderclapper in its hands")
check(table.find(played, "thunderclapper") and not table.find(played, "blaster"), "and sounds like one")
table.clear(played)
Remotes.CombatEvent:FireClient(me, {
	kind = "lob",
	shooter = -904,
	from = Vector3.new(60, 4.5, 0),
	to = Vector3.new(60, 0, -60),
	path = { Vector3.new(60, 4.5, 0), Vector3.new(60, 20, -30), Vector3.new(60, 0, -60) },
	flight = 1.2,
})
task.wait()
local lobberGun = lobber:FindFirstChild("HeldWeapon") :: Tool
check(Fx.states[lobberGun] and Fx.states[lobberGun].weapon == "StinkLobber" and Fx.states[lobberGun].kick > 0, "a bot's throw kicks its Stink Lobber")
local arc = false
for _, child in workspace:GetChildren() do
	if child.Name == "LobArc" then
		arc = true
	end
end
check(arc and table.find(played, "lobber"), "draws the arc and sounds the throw")
table.clear(played)
Remotes.CombatEvent:FireClient(me, { kind = "dash", player = -903, from = Vector3.new(40, 3, 0), direction = Vector3.new(1, 0, 0) })
Remotes.CombatEvent:FireClient(me, { kind = "ability", player = -904, ability = "GasPulse", position = Vector3.new(60, 3, 0) })
task.wait()
check(table.find(played, "dash") and table.find(played, "pulse"), "its dashes and its Q are heard like anyone's")
Audio.play = play
clapper:Destroy()
lobber:Destroy()

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
-- The scoreboard keeps it while its team still counts it (it's only
-- waiting to respawn, like a player who's down), held open it keeps up,
-- and it drops the bot once the server takes it off the team.
do
	local ClientState = require(Client.ClientState)
	local counts, bots = table.clone(ClientState.counts), table.clone(ClientState.bots)
	-- The server's own bots on the Sharters are on the field too.
	local onField = 0
	for _, bot in Combatants.bots() do
		if bot.team == "Sharters" then
			onField += 1
		end
	end
	local function teams(sharterBots: number)
		local withCounts, withBots = table.clone(counts), table.clone(bots)
		withCounts.Sharters = (counts.Sharters or 0) - (bots.Sharters or 0) + sharterBots
		withBots.Sharters = sharterBots
		Remotes.TeamUpdate:FireClient(me, { counts = withCounts, bots = withBots, maxTeamSize = ClientState.maxTeamSize })
		task.wait(0.05)
	end
	local function rows(): number
		local n = 0
		for _, child in HUD.parts.columns.Sharters:GetChildren() do
			if child:IsA("TextLabel") then
				n += 1
			end
		end
		return n
	end
	teams(onField + 1)
	HUD.renderScoreboard()
	check(HUD.parts.columns.Sharters:FindFirstChild("-901") and rows() == onField + 1, "the scoreboard keeps a bot between lives while its team counts it, and no more")
	HUD.parts.scoreboard.Enabled = true
	teams(onField)
	check(not HUD.parts.columns.Sharters:FindFirstChild("-901") and rows() == onField, "held open, it drops the bot as soon as the server takes it off the team")
	HUD.parts.scoreboard.Enabled = false
	Remotes.TeamUpdate:FireClient(me, { counts = counts, bots = bots, maxTeamSize = ClientState.maxTeamSize })
	task.wait(0.05)
end
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

-- A body that leaves the field only as Parent = nil (how a bot destroyed on
-- the server reaches a client, and how Roblox takes a player's old body
-- away) is let go here a moment later: the handlers screens hang on every
-- avatar would otherwise keep every life in memory.
do
	local ghost = spawnBot(-905, "Sharters", "[BOT] Ghost", 30)
	task.wait(0.1)
	local released = false
	ghost.Destroying:Connect(function()
		released = true
	end)
	ghost.Parent = nil
	task.wait(0.5)
	check(not released, "not at once (effects may still be finishing with it)")
	task.wait(2)
	check(released, "but a moment later, it's let go")
end

return { status = "PASS", checks = checks }
