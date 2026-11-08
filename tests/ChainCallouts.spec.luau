-- Chain reactions on screen (ChainController), with one client (Ace)
-- against the real server:
--   * the server counts each chain reaction: every explosion's event
--     carries its place in its chain (players, bots and barrels alike), a
--     chain that branches keeps one count, and anything else (a shot, a
--     stink bomb, Gas Pulse) starts a new chain
--   * Ace's own chain: nothing for the first explosion, then "CHAIN x2!",
--     "CHAIN x3!"... bigger and hotter each link, with a tagline, the chain
--     sting a step higher each time, a ring and a camera kick that rolls
--     the view without turning it, then settles; barrel to barrel to player
--     counts the same way
--   * nothing is guessed: two of Ace's explosions side by side that the
--     server says are separate chains get no pop-up
--   * someone else's chain near Ace: a smaller line naming them, in their
--     colour; far away, or while Ace's own pop-up is up: nothing
--   * REDUCE MOTION: no pop, tilt, fade or kick, a still ring; REDUCED
--     EFFECTS: the pop and kick stay, no fade, no ring
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)
local TeamConfig = require(ReplicatedStorage.Shared.Config.TeamConfig)
local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local S = require(ReplicatedStorage.Shared.Config.MapConfig).BrainrotBattlefield.scale
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
-- No bots but the one made here.
require(server.Services.BotDirector).testSetEnabled(false)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TeamService = require(server.Services.TeamService)
local Gas = require(server.Services.GasService)
local Bots = require(server.Services.BotService)
local Barrels = require(server.Services.BarrelService)
local Explosions = require(server.Services.ExplosionService)
local AFK = require(server.Services.AFKService)
local Remotes = ReplicatedStorage.Remotes

local ace = Instance.new("Player")
ace.Name = "Ace"
ace.DisplayName = "Ace"
ace.UserId = 1
Instance.new("PlayerGui").Parent = ace
Players.LocalPlayer = ace
ace.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
local Chain = require(client.Controllers.ChainController)
local Settings = require(client.Settings)
local UI = require(client.UI)
Lifecycle.requestPlay(ace, nil)

local CHAIN = UIConfig.chain
local p = Chain.parts
check(FeatureFlags.CHAIN_CALLOUTS, "chain callouts are on")
check(p.popup and p.line and p.popup.Parent == p.line.Parent, "the pop-up and the line share a spot on the Chain screen")

-- The looks, link by link.
local text, tagline, color, size = Chain.look(2)
check(text == "CHAIN x2!" and tagline == CHAIN.taglines[1] and color == CHAIN.colors[1] and size == CHAIN.size, "x2: CHAIN x2!, the first tagline, colour and size")
text, tagline, color, size = Chain.look(3)
check(text == "CHAIN x3!" and tagline == CHAIN.taglines[2] and color == CHAIN.colors[2] and size == CHAIN.size + CHAIN.growth, "x3: the next of each, bigger")
text, tagline, color, size = Chain.look(40)
check(text == "CHAIN x40!" and tagline == CHAIN.taglines[#CHAIN.taglines] and color == CHAIN.colors[#CHAIN.colors] and size == CHAIN.maxSize, "a huge chain: the last tagline and colour, the biggest size")
check(Chain.pitchOf(2) == 1 and Chain.pitchOf(3) > Chain.pitchOf(2) and Chain.pitchOf(99) == CHAIN.maxPitch, "the sting climbs a step a link, up to a limit")
check(Chain.kickOf(2) == CHAIN.kick and Chain.kickOf(3) > Chain.kickOf(2) and Chain.kickOf(99) == CHAIN.maxKick, "and so does the kick")
check(Chain.ownerOf({ kind = "barrel", owner = 5, killer = 6 }) == 5 and Chain.ownerOf({ kind = "explosion", killer = 6 }) == 6, "a barrel's owner, an explosion's killer")
check(Chain.countOf({}) == 0 and Chain.countOf({ chain = "x" }) == 0 and Chain.countOf({ chain = 3 }) == 3, "no count, no chain")

-- Every chain event the server sends Ace, and what Ace's screen shows
-- just after each one (this listener runs after the controller's).
local events: { any } = {}
local seen: { any } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if player == ace and (event.kind == "explosion" or event.kind == "barrel") then
		table.insert(events, event)
	end
end)
Remotes.CombatEvent.OnClientEvent:Connect(function(event)
	if type(event) == "table" and (event.kind == "explosion" or event.kind == "barrel") then
		local sound = SoundService:FindFirstChild("chain") :: Sound?
		table.insert(seen, {
			event = event,
			popup = p.popup.Visible,
			title = p.title.Text,
			tagline = p.tagline.Text,
			color = p.title.TextColor3,
			size = p.title.TextSize,
			pop = p.pop.Scale,
			tilt = p.burst.Rotation,
			ring = p.ring.Visible,
			kick = Chain.kick(),
			pitch = sound and sound.Playing and sound.PlaybackSpeed,
			line = if p.line.Visible then p.line.Text else nil,
			lineColor = p.line.TextColor3,
		})
	end
end)
local function fresh()
	table.clear(events)
	table.clear(seen)
end

local nextId = 1
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local function place(player: Player, x: number, y: number, z: number)
	player.Character:PivotTo(CFrame.new(x, y, z))
end
local function awake()
	for _, player in Players:GetPlayers() do
		AFK.markActive(player)
	end
end
-- Up in clear air, above the throne.
local SKY = 40 * S

local ally = join("Ally")
local teamA = ace:GetAttribute("TeamId")
local teamB = if teamA == "Stinkers" then "Sharters" else "Stinkers"
TeamService.testSetTeam(ally, teamA)
local foes = {}
for i = 1, 9 do
	local foe = join(`Foe{i}`)
	TeamService.testSetTeam(foe, teamB)
	table.insert(foes, foe)
end
-- A bot on the foes' side, made as BotDirector would.
local body = Instance.new("Model")
body.Name = "Puff"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(5, SKY, -5)
root.Parent = body
local head = Instance.new("Part")
head.Name = "Head"
head.Size = Vector3.new(2, 1, 1)
head.CFrame = CFrame.new(5, SKY + 1.5, -5)
head.Parent = body
Instance.new("Humanoid").Parent = body
body.PrimaryPart = root
body.Parent = workspace
local puff = Bots.add(teamB, "Puff")
Bots.attach(puff, body)
task.wait(3.2)
awake()
check(TeamService.teamOf(ally) == teamA and TeamService.teamOf(foes[9]) == teamB, "Ace and an ally against nine and a bot")

-- 1. Ace's chain, branching: Foe1 sets off Foe2, whose blast sets off
-- Foe3 and the bot together, and their blasts set off Foe4.
fresh()
place(ace, 0, SKY, -60)
place(ally, 0, SKY, -50)
place(foes[1], 0, SKY, -25)
place(foes[2], 0, SKY, -15)
place(foes[3], -5, SKY, -5) -- the bot is at 5, -5
place(foes[4], 0, SKY, 5)
for _, foe in { foes[2], foes[3], foes[4] } do
	check(Gas.add(foe, 70, { attacker = ace, cause = "shot" }), `{foe.Name} at 70%`)
end
check(Bots.addGas(puff, 70, { attacker = ace, cause = "shot" }), "the bot at 70%")
Gas.add(foes[1], 100, { attacker = ace, cause = "shot" })
task.wait(1.02)
check(#seen == 1 and seen[1].event.victim == foes[1].UserId and seen[1].event.chain == 1, "Foe1 goes off: the first link")
check(not seen[1].popup and seen[1].title == "", "one explosion is no chain: no pop-up")
task.wait(1.05)
check(#seen == 2 and seen[2].event.victim == foes[2].UserId and seen[2].event.chain == 2, "Foe2, set off by Foe1's blast: the second")
local x2 = seen[2]
check(x2.popup and x2.title == "CHAIN x2!" and x2.tagline == CHAIN.taglines[1], "Ace's screen: CHAIN x2!, and its tagline")
check(x2.color == CHAIN.colors[1] and x2.size == CHAIN.size, "in the first colour, at the first size")
check(x2.pop == 1 and x2.tilt == 0, "popped in and settled (the stand-in's tweens finish at once)")
check(x2.ring, "a ring thrown out")
check(x2.pitch == 1, "the chain sting at its own pitch")
check(x2.kick == CHAIN.kick, "and a camera kick")
check(x2.line == nil, "not the line: it's Ace's own")

-- The kick rolls the view and shoves it, but never turns where it looks,
-- and settles.
local camera = workspace.CurrentCamera
camera.CFrame = CFrame.new(10, SKY, -70) * CFrame.Angles(-0.3, 0.8, 0)
local before = camera.CFrame
Chain.step(1 / 60)
local after = camera.CFrame
check((after.LookVector - before.LookVector).Magnitude < 1e-6, "the kick leaves where Ace looks alone")
check((after.UpVector - before.UpVector).Magnitude > 1e-3 and (after.Position - before.Position).Magnitude > 1e-3, "but rolls and shoves the view")
check(Chain.kick() < CHAIN.kick, "and starts to settle")
for _ = 1, 60 do
	Chain.step(1 / 60)
end
check(Chain.kick() == 0, "a second later it's gone")
camera.CFrame = before
Chain.step(1 / 60)
check(camera.CFrame == before, "and moves the camera no more")

task.wait(1.05)
check(#seen == 4, "Foe3 and the bot go off together")
local third, fourth = seen[3], seen[4]
check(third.event.chain == 3 and fourth.event.chain == 4, "as the third and fourth links: a branch keeps counting the one chain")
local victims = { [third.event.victim] = true, [fourth.event.victim] = true }
check(victims[foes[3].UserId] and victims[puff.id], "a player and a bot alike")
check(fourth.title == "CHAIN x4!" and fourth.color == CHAIN.colors[3] and fourth.size == CHAIN.size + 2 * CHAIN.growth, "CHAIN x4!: hotter and bigger")
check(third.pitch and fourth.pitch and fourth.pitch > third.pitch and third.pitch > x2.pitch, "the sting a step higher each link")
check(fourth.kick == Chain.kickOf(4) and fourth.kick > x2.kick, "and the kick harder")
task.wait(1.05)
check(#seen == 5 and seen[5].event.victim == foes[4].UserId and seen[5].event.chain == 5, "Foe4, set off by the branch: the fifth")
check(seen[5].title == "CHAIN x5!" and seen[5].tagline == CHAIN.taglines[4], "CHAIN x5!")
for i, event in events do
	check(event.chain == i and event.killer == ace.UserId, `link {i} came from the server, credited to Ace`)
end
task.wait(CHAIN.seconds + 0.1)
check(not p.popup.Visible, "the pop-up goes")
awake()

-- 2. Barrel, barrel, player (the Gas Gutter's pair).
local function barrelAt(x: number, z: number): Model
	for _, model in Barrels.all() do
		local at = model.PrimaryPart.Position
		if math.abs(at.X - x) < 0.1 and math.abs(at.Z - z) < 0.1 then
			return model
		end
	end
	error(`no barrel at {x}, {z}`)
end
local barrel1, barrel2 = barrelAt(66 * S, -12 * S), barrelAt(70 * S, -16 * S)
local b1 = barrel1.PrimaryPart.Position
local chained = foes[5]
fresh()
place(chained, b1.X - 12, 3, b1.Z) -- by barrel 1 only
place(ace, b1.X, 3, b1.Z - 40)
place(ally, b1.X - 60, 3, b1.Z - 60)
check(Gas.add(chained, 70, { attacker = ace, cause = "shot" }), "Foe5 at 70%, by a barrel")
check(Barrels.shoot(ace, barrel1.PrimaryPart, 40), "Ace finishes barrel 1")
task.wait(4)
check(#events == 3, "two barrels and Foe5 go off")
check(events[1].kind == "barrel" and events[1].chain == 1 and events[1].owner == ace.UserId, "barrel 1: a new chain, Ace's")
check(events[2].kind == "barrel" and events[2].chain == 2 and events[2].owner == ace.UserId, "barrel 2, set off by barrel 1: the second link")
check(events[3].kind == "explosion" and events[3].victim == chained.UserId and events[3].chain == 3 and events[3].killer == ace.UserId, "Foe5, by barrel 1's blast: the third")
check(not seen[1].popup, "barrel 1 alone: no pop-up")
check(seen[2].popup and seen[2].title == "CHAIN x2!" and seen[3].title == "CHAIN x3!", "then CHAIN x2! and CHAIN x3! on Ace's screen")
task.wait(CHAIN.seconds)
awake()

-- 3. Nothing guessed: one stink bomb sets off two of Ace's foes side by
-- side. Two explosions at once, both Ace's, but the server says each is
-- the first of its own chain.
fresh()
place(ace, 0, SKY, -60)
place(foes[6], -3, SKY, 30)
place(foes[7], 3, SKY, 30)
Explosions.blast({ position = Vector3.new(0, SKY, 30), radius = 8, gas = 100, owner = ace, ownerTeam = teamA, cause = "lob", depth = 0 })
task.wait(1.2)
check(#events == 2 and events[1].chain == 1 and events[2].chain == 1, "a stink bomb's two: each the first of its own chain")
check(events[1].killer == ace.UserId and events[2].killer == ace.UserId, "both Ace's")
check(not seen[1].popup and not seen[2].popup and not p.popup.Visible, "so no pop-up: the count is the server's, never the screen's guess")
task.wait(1)
awake()

-- 4. The ally's chain, near Ace: the line, naming them.
fresh()
place(ace, 80, SKY, -20)
place(foes[8], 80, SKY, 0)
place(foes[9], 80, SKY, 10)
check(Gas.add(foes[9], 70, { attacker = ally, cause = "shot" }), "Foe9 at 70%, the ally's")
Gas.add(foes[8], 100, { attacker = ally, cause = "shot" })
task.wait(2.1)
check(#events == 2 and events[2].chain == 2 and events[2].killer == ally.UserId, "the ally's chain of two")
check(seen[1].line == nil, "its first link: nothing")
local allyName = string.upper(`{UI.teamSymbol(teamA)}{ally.DisplayName}`)
check(seen[2].line == string.format(CHAIN.line, allyName, 2), `the second: "{seen[2].line}" near Ace`)
check(seen[2].lineColor == TeamConfig.teams[teamA].color, "in the ally's team colour")
check(not seen[2].popup, "not the big pop-up: it isn't Ace's")
task.wait(CHAIN.lineSeconds + 0.1)
check(not p.line.Visible, "the line goes")
awake()

-- 5. The same far away: nothing. (Foes 1 and 2 are back by now.)
fresh()
check(not Lifecycle.isProtected(foes[1]) and Gas.gasOf(foes[1]) == 0, "Foe1 is back")
place(ace, -150, SKY, -150)
place(foes[1], 80, SKY, 40)
place(foes[2], 80, SKY, 50)
Gas.add(foes[2], 70, { attacker = ally, cause = "shot" })
Gas.add(foes[1], 100, { attacker = ally, cause = "shot" })
task.wait(2.1)
check(#events == 2 and events[2].chain == 2, "another chain of the ally's")
check(seen[2].line == nil and not p.line.Visible, "too far from Ace: no line")
awake()

-- 6. Ace's own pop-up comes first: no line over it. (A count the server
-- sends, straight to Ace's screen, from here on.)
local function send(event: { [string]: any })
	Remotes.CombatEvent:FireClient(ace, event)
	task.wait()
end
local here = ace.Character.HumanoidRootPart.Position
send({ kind = "explosion", victim = 99, killer = ace.UserId, position = here + Vector3.new(0, 0, 200), chain = 2 })
check(p.popup.Visible, "Ace's pop-up")
check(Chain.onEvent({ kind = "explosion", victim = 98, killer = ally.UserId, position = here, chain = 3 }) == nil and not p.line.Visible, "an ally's chain right by Ace: no line while it's up")
task.wait(CHAIN.seconds + 0.1)
check(Chain.onEvent({ kind = "barrel", owner = ally.UserId, position = here, chain = 4 }) == "line", "after it, the line")
check(p.line.Text == string.format(CHAIN.line, allyName, 4), "naming the ally for a barrel too")
check(Chain.onEvent({ kind = "barrel", position = here, chain = 2 }) == "line" and p.line.Text == string.format(CHAIN.lineNoOwner, 2), "and nobody for a barrel whose owner left")
check(Chain.onEvent({ kind = "explosion", killer = ace.UserId, position = here, chain = 1 }) == nil, "a first link: nothing, even Ace's")
task.wait(CHAIN.lineSeconds + 0.1)

-- Fades and settles over its time.
local fades = {}
p.title:GetPropertyChangedSignal("TextTransparency"):Connect(function()
	table.insert(fades, p.title.TextTransparency)
end)
local pops, tilts = {}, {}
p.pop:GetPropertyChangedSignal("Scale"):Connect(function()
	table.insert(pops, p.pop.Scale)
end)
p.burst:GetPropertyChangedSignal("Rotation"):Connect(function()
	table.insert(tilts, p.burst.Rotation)
end)
local function showOwn(count: number)
	table.clear(fades)
	table.clear(pops)
	table.clear(tilts)
	send({ kind = "explosion", victim = 99, killer = ace.UserId, position = here, chain = count })
end
showOwn(2)
check(pops[1] == CHAIN.pop and math.abs(tilts[1]) == CHAIN.tilt and p.pop.Scale == 1 and p.burst.Rotation == 0, "it pops in tilted, then settles")
task.wait(CHAIN.seconds - CHAIN.fadeSeconds / 2)
showOwn(3)
check(p.popup.Visible and p.title.Text == "CHAIN x3!" and p.title.TextTransparency == 0, "a new link mid-fade: back to solid, the new count")
task.wait(CHAIN.seconds - CHAIN.fadeSeconds + 0.05)
check(p.popup.Visible and fades[#fades] == 1, "it fades at the end")
task.wait(CHAIN.fadeSeconds)
check(not p.popup.Visible, "and goes")
for _ = 1, 120 do
	Chain.step(1 / 60)
end

-- REDUCE MOTION: shown and hidden, no pop, tilt, fade or kick.
Settings.reduceMotion = true
showOwn(3)
check(p.popup.Visible and p.title.Text == "CHAIN x3!", "REDUCE MOTION: the pop-up still shows")
check(#pops == 0 and #tilts == 0 and p.pop.Scale == 1 and p.burst.Rotation == 0, "without a pop or tilt")
check(Chain.kick() == 0, "or a kick")
check(p.ring.Visible and p.ring.Size.X.Offset == CHAIN.ringSize, "the ring stands still")
camera.CFrame = before
Chain.step(1 / 60)
check(camera.CFrame == before, "the camera never moves")
task.wait(CHAIN.seconds - 0.05)
check(p.popup.Visible and p.title.TextTransparency == 0 and not table.find(fades, 1), "solid to the end")
task.wait(0.1)
check(not p.popup.Visible and not p.ring.Visible, "then hidden")
Settings.reduceMotion = false

-- REDUCED EFFECTS: the pop and the kick stay; no fade, no ring.
Settings.reducedEffects = true
showOwn(2)
check(p.popup.Visible and pops[1] == CHAIN.pop, "REDUCED EFFECTS: it still pops")
check(Chain.kick() == CHAIN.kick, "and kicks")
check(not p.ring.Visible, "no ring")
task.wait(CHAIN.seconds + 0.05)
check(not p.popup.Visible and not table.find(fades, 1), "gone without a fade")
Settings.reducedEffects = false

return { status = "PASS", checks = checks }
