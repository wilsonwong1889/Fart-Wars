-- Launch pads (FeatureFlags.LAUNCH_PADS), on the real server with one
-- client (the stand-ins have no physics, so flights are flown by hand
-- along each launch's own arc):
--   * stepping onto a pad launches your avatar: the kick and the push
--     along the pad's arc (Fart Dash's push gone first), the server told
--     and agreeing, the fart heard flat with its puff and green cloud;
--     coming down ends the push and slows you to walking speed
--   * one launch every COOLDOWN_SECONDS, on your client and on the server,
--     ready again with each life; never while exploding
--   * no cheat flag: shooting all through a flight, and a dash onto a pad,
--     are neither flagged nor put back, where the same moves without a
--     launch are (so the checks still bite); a launch that arrives while
--     the server still sees the dash's start, 23 studs out, is taken, where
--     the same spot with no dash, or a dash from 40 out, is too far
--   * spawn protection works as before: a launch keeps it
--   * refused: junk and unknown pads, far from the pad, not playing
--   * everyone else's launches (a bot's) fart from where they happen
--   * bots take a pad they walk onto its way, not one they back off
--     against, with the push, a cooldown and LandsAt, and their brain
--     plans again from where they land
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
-- No bots but the spec's own.
require(server.Services.BotDirector).testSetEnabled(false)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local LaunchPadConfig = require(Shared.Config.LaunchPadConfig)
local AudioConfig = require(Shared.Config.AudioConfig)
local BotConfig = require(Shared.Config.BotConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local LaunchPads = require(Shared.LaunchPads)
local MapService = require(server.Services.MapService)
local Pads = require(server.Services.LaunchPadService)
local Combat = require(server.Services.CombatService)
local Dash = require(server.Services.DashService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Bots = require(server.Services.BotService)
local BotBrain = require(server.Bots.BotBrain)
local Telemetry = require(server.Telemetry)
local Moderation = require(server.Moderation)
local Remotes = ReplicatedStorage.Remotes

check(FeatureFlags.LAUNCH_PADS, "launch pads are on")
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function rejects(reason: string): number
	local byReason = Telemetry.snapshot().rejects.LaunchPad
	return byReason and byReason[reason] or 0
end
local function flagged(player: Player, reason: string): boolean
	for _, flag in Moderation.flagsOf(player) do
		if flag.reason == reason then
			return true
		end
	end
	return false
end

local me = Instance.new("Player")
me.Name = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
task.wait(0.5)
local Controller = require(client.Controllers.LaunchPadController)
local Audio = require(client.Audio)

-- What the server sends and hears.
local sent: { any } = {}
Remotes.LaunchPad.OnServerEvent:Connect(function(_, name)
	table.insert(sent, name)
end)
local launches: { any } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if player == me and type(event) == "table" and event.kind == "launch" then
		table.insert(launches, event)
	end
end)
local accepted = {}
Pads.Launched:Connect(function(player, bot, pad, arc)
	table.insert(accepted, { player = player, bot = bot, pad = pad, arc = arc })
end)

Lifecycle.requestPlay(me, nil)
task.wait(0.5)
local team = me:GetAttribute("TeamId")
check(me.Character and (team == "Stinkers" or team == "Sharters"), "playing")
local map = MapService.current()
local pad = LaunchPads.find(map, `{team}Alley`) :: Model
check(pad, `{team} have a pad up Bean Alley`)

local function parts(): (Humanoid, BasePart)
	local character = me.Character :: Model
	return character:FindFirstChildOfClass("Humanoid") :: Humanoid, character:FindFirstChild("HumanoidRootPart") :: BasePart
end
-- Puts `player` standing on (or `back` studs behind) a pad.
local function stand(player: Player, on: Model, back: number?)
	local top = LaunchPads.cushion(on)
	local spot = top - LaunchPads.direction(on) * (back or 0) + Vector3.new(0, 3, 0)
	local character = player.Character :: Model
	character:PivotTo(CFrame.new(spot))
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.FloorMaterial = Enum.Material.Grass
end
-- Flies `player` along `arc` by hand (no physics here), calling
-- `during()` every `every` seconds of it, for the whole flight or the
-- first `upTo` seconds.
local function fly(player: Player, arc: LaunchPads.Arc, every: number?, during: (() -> ())?, upTo: number?)
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.FloorMaterial = Enum.Material.Air
	local t, nextCall = 0, every or math.huge
	local stop = math.min(upTo or math.huge, arc.seconds)
	while t < stop do
		local dt = math.min(1 / 30, stop - t)
		task.wait(dt)
		t += dt
		character:PivotTo(CFrame.new(LaunchPads.at(arc, math.min(t, arc.seconds))))
		if during and t >= nextCall then
			nextCall += every :: number
			during()
		end
	end
end
-- A shot straight up (so it gasses nobody), numbered like a client's.
local shotIds: { [Player]: number } = {}
local function shoot(player: Player)
	shotIds[player] = (shotIds[player] or 0) + 1
	Combat.fire(player, Vector3.new(0, 1, 0), shotIds[player])
end
local INTERVAL = WeaponConfig.weapons[WeaponConfig.default].fireInterval
-- The arc from the middle of a pad's cushion, as stand() puts you.
local function arcOf(on: Model): LaunchPads.Arc
	return LaunchPads.arc(on, LaunchPads.cushion(on) + Vector3.new(0, 3, 0), 3)
end

-- Stepping onto a pad.
local humanoid, root = parts()
stand(me, pad)
local fakeDash = Instance.new("LinearVelocity")
fakeDash.Name = "FartDash"
fakeDash.Parent = root
check(Controller.flight == nil, "on the ground")
shoot(me)
Controller.step()
local flight = Controller.flight
local push = root:FindFirstChild("LaunchPad")
check(flight and push and push:IsA("LinearVelocity") and flight.push == push, "stepping onto the pad launches you, with a push")
check(fakeDash.Parent == nil, "a Fart Dash push still on you goes first")
local arc = LaunchPads.arc(pad, root.Position, LaunchPads.lift(humanoid, root))
check((root.AssemblyLinearVelocity - arc.velocity).Magnitude < 1e-3 and root.AssemblyLinearVelocity.Y > 50, "the kick: up and away along the pad's arc")
check(push.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane and (Vector3.new(push.PlaneVelocity.X, 0, push.PlaneVelocity.Y) - Vector3.new(arc.velocity.X, 0, arc.velocity.Z)).Magnitude < 1e-3, "and the push holds that speed across the ground")
check(math.abs(flight.seconds - arc.seconds) < 1e-6 and arc.seconds > 0.6 and arc.seconds < 1.4, `a flight of about a second ({arc.seconds})`)
check(#sent == 1 and sent[1] == pad.Name, "the server is told which pad")
check(#accepted == 1 and accepted[1].player == me and accepted[1].pad == pad and counter("LaunchPads.launches") == 1, "and takes the launch")
check(#launches == 1 and launches[1].player == me.UserId and launches[1].pad == pad.Name and typeof(launches[1].from) == "Vector3", "everyone hears of it")
local landing = LaunchPads.landing(pad)
check(math.abs(launches[1].seconds - accepted[1].arc.seconds) < 1e-6 and (launches[1].to - (landing + Vector3.new(0, 3, 0))).Magnitude < 1e-3, "with where and when it comes down")
local fart = Audio.flat.launch
check(fart and fart.SoundId == AudioConfig.launch and fart.Playing, "your launch farts, flat")
local puffs, clouds = 0, 0
for _, item in workspace:GetChildren() do
	puffs += if item.Name == "LaunchPuff" then 1 else 0
	clouds += if item.Name == "LaunchCloud" then 1 else 0
end
check(puffs >= 1 and clouds >= 1, `a puff under you and a green cloud on the pad ({puffs}, {clouds})`)
for _, item in Controller.effects do
	check(not item.CanCollide and not item.CanQuery and not item.CanTouch and item.Anchored, `{item.Name} is never in the way`)
end

-- The flight, shooting all the way: never flagged.
fly(me, arc, INTERVAL, function()
	shoot(me)
end)
check((root.Position - arc.to).Magnitude < 1e-3, "down on the landing spot")
task.wait(INTERVAL)
shoot(me)
check(counter("Combat.shots") >= 4, `shots all through the flight ({counter("Combat.shots")})`)
check(counter("Combat.impossibleMovement") == 0 and not flagged(me, "impossibleMovement") and #Moderation.flagsOf(me) == 0, "a launch is never cheating")
humanoid.FloorMaterial = Enum.Material.Grass
task.wait(0.05)
Controller.step()
check(Controller.flight == nil and root:FindFirstChild("LaunchPad") == nil and root:FindFirstChild("LaunchPadAttachment") == nil, "coming down ends the push")
local across = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
check(across.Magnitude <= GameConfig.WALK_SPEED + 1e-3, `and you run on at walking speed ({across.Magnitude})`)

-- The cooldown.
stand(me, pad)
Controller.step()
check(Controller.flight == nil and #sent == 1, "not again until the cooldown is up")
check(not Pads.launch(me, pad.Name) and rejects("cooldown") == 1, "and the server says the same")
task.wait(LaunchPadConfig.COOLDOWN_SECONDS)
stand(me, pad)
Controller.step()
check(Controller.flight ~= nil and #sent == 2 and #accepted == 2, "ready again after it")
fly(me, arcOf(pad))
humanoid.FloorMaterial = Enum.Material.Grass
Controller.step()

-- The same flight without a launch is caught: the checks still bite.
local cheat = Instance.new("Player")
cheat.Name = "Cheat"
cheat.UserId = 2
cheat.Parent = Players
task.wait(0.05)
Lifecycle.requestPlay(cheat, nil)
task.wait(0.5)
check(cheat.Character, "someone else playing")
-- Two players start a round, which gives everyone a fresh avatar.
humanoid, root = parts()
stand(cheat, pad)
shoot(cheat)
fly(cheat, arcOf(pad), INTERVAL, function()
	shoot(cheat)
end)
check(counter("Combat.impossibleMovement") >= 1 and flagged(cheat, "impossibleMovement"), "the same flight with no launch is flagged")

-- A Fart Dash onto a pad: neither put back nor flagged.
task.wait(LaunchPadConfig.COOLDOWN_SECONDS + AbilityConfig.FartDash.cooldownSeconds)
humanoid, root = parts()
stand(me, pad, 14)
check(Dash.dash(me, LaunchPads.direction(pad)), "a Fart Dash at the pad")
task.wait(0.1)
stand(me, pad)
Controller.step()
check(Controller.flight ~= nil and #accepted == 3, "and onto it: launched")
local dashArc = arcOf(pad)
fly(me, dashArc)
task.wait(0.1)
check((root.Position - dashArc.to).Magnitude < 1e-3, "not put back")
local dashRejects = Telemetry.snapshot().rejects.FartDash or {}
check((dashRejects.tooFar or 0) == 0 and (dashRejects.throughWall or 0) == 0 and #Moderation.flagsOf(me) == 0, "nor refused or flagged")
humanoid.FloorMaterial = Enum.Material.Grass
Controller.step()
-- The same without the pad: put back.
task.wait(AbilityConfig.FartDash.cooldownSeconds)
stand(cheat, pad, 14)
local cheatRoot = (cheat.Character :: Model).HumanoidRootPart :: BasePart
local dashFrom = cheatRoot.Position
check(Dash.dash(cheat, LaunchPads.direction(pad)), "a Fart Dash with no pad")
fly(cheat, arcOf(pad), nil, nil, AbilityConfig.FartDash.checkSeconds - 0.1)
task.wait(0.2)
check((Telemetry.snapshot().rejects.FartDash or {}).tooFar == 1 and (cheatRoot.Position - dashFrom).Magnitude < 1, "carried off with no launch: put back")

-- A Fart Dash onto a pad from further out: the client reaches the pad and
-- launches, and its request arrives while the server's view of it, a
-- moment behind a dash, is still back where it dashed from.
local DASH = AbilityConfig.FartDash
local FAR_OUT = 23
local _, padRadius = LaunchPads.cushion(pad)
local reach = padRadius + LaunchPadConfig.SLACK_STUDS
check(FAR_OUT > reach and FAR_OUT < reach + DASH.speed * DASH.durationSeconds, `(beyond a launch's {reach} studs, within a dash's length more)`)
task.wait(DASH.cooldownSeconds)
humanoid, root = parts()
stand(me, pad, FAR_OUT)
local acceptedBefore = #accepted
check(Dash.dash(me, LaunchPads.direction(pad)), `a Fart Dash at the pad from {FAR_OUT} studs out`)
check(Pads.launch(me, pad.Name) and #accepted == acceptedBefore + 1, `the launch, with the server still seeing you {FAR_OUT} studs out: taken`)
local farArc = arcOf(pad)
fly(me, farArc)
task.wait(0.1)
check((root.Position - farArc.to).Magnitude < 1e-3, "the dash isn't put back")
dashRejects = Telemetry.snapshot().rejects.FartDash or {}
check((dashRejects.tooFar or 0) == 1 and (dashRejects.throughWall or 0) == 0 and #Moderation.flagsOf(me) == 0, "nor refused or flagged")
-- The same spot with no dash: too far, as before; nor does a dash stretch
-- a launch beyond what it covers.
task.wait(LaunchPadConfig.COOLDOWN_SECONDS)
stand(me, pad, FAR_OUT)
local tooFar = rejects("tooFar")
check(not Pads.launch(me, pad.Name) and rejects("tooFar") == tooFar + 1, `{FAR_OUT} studs out with no dash: too far`)
task.wait(DASH.cooldownSeconds)
stand(me, pad, 40)
check(Dash.dash(me, LaunchPads.direction(pad)) and not Pads.launch(me, pad.Name) and rejects("tooFar") == tooFar + 2, "a Fart Dash from 40 studs out: still too far")

-- Spawn protection works as before: a launch keeps it.
task.wait(LaunchPadConfig.COOLDOWN_SECONDS)
Lifecycle.respawn(me)
task.wait(0.1)
humanoid, root = parts()
check(Lifecycle.isProtected(me), "a fresh spawn is protected")
stand(me, pad)
Controller.step()
check(Controller.flight ~= nil and #accepted == 5, "launched while protected")
check(Lifecycle.isProtected(me) and (me.Character :: Model):FindFirstChild("SpawnProtection"), "still protected")
fly(me, arcOf(pad))
humanoid.FloorMaterial = Enum.Material.Grass
Controller.step()

-- Refused.
task.wait(LaunchPadConfig.COOLDOWN_SECONDS)
check(not Pads.launch(me, 42) and not Pads.launch(me, "Nowhere") and rejects("badPayload") == 2, "junk or an unknown pad")
local far = LaunchPads.find(map, `{if team == "Stinkers" then "Sharters" else "Stinkers"}Gutter`) :: Model
tooFar = rejects("tooFar")
check(not Pads.launch(me, far.Name) and rejects("tooFar") == tooFar + 1, "a pad you're nowhere near")
check(Gas.add(me, 100, { team = if team == "Stinkers" then "Sharters" else "Stinkers", cause = "cloud" }) and Gas.isExploding(me), "about to blow")
stand(me, pad)
Controller.step()
check(Controller.flight == nil and #accepted == 5, "no launch while exploding")
check(not Pads.launch(me, pad.Name) and rejects("prohibited") == 1, "and the server agrees")
task.wait(2)
Lifecycle.requestSpectate(cheat)
task.wait(0.1)
check(not Pads.launch(cheat, pad.Name) and rejects("notActive") == 1, "not playing")
check(#Moderation.flagsOf(me) == 0, "and still nothing flagged against you")

-- Bots.
local launchesBefore = #launches
local bot = Bots.add(team, "Toots")
local function avatar(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local botRoot = Instance.new("Part")
	botRoot.Name = "HumanoidRootPart"
	botRoot.Size = Vector3.new(2, 2, 1)
	botRoot.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Parent = model
	Instance.new("Humanoid").Parent = model
	model.PrimaryPart = botRoot
	model.Parent = workspace
	return model
end
local body = avatar("Toots")
Bots.attach(bot, body)
local botRoot = body.HumanoidRootPart :: BasePart
-- Onto the pad, walking `direction`; off it again, standing still (the
-- server's own loop ticks while the spec waits).
local function walk(direction: Vector3)
	local top = LaunchPads.cushion(pad)
	body:PivotTo(CFrame.new(top + Vector3.new(0, 3, 0)))
	botRoot.AssemblyLinearVelocity = direction * 16
end
local function away()
	body:PivotTo(CFrame.new(LaunchPads.landing(pad) + Vector3.new(0, 3, 0)))
	botRoot.AssemblyLinearVelocity = Vector3.zero
end
walk(-LaunchPads.direction(pad))
Pads.tick(0.1)
check(botRoot:FindFirstChild("LaunchPad") == nil and #launches == launchesBefore, "a bot backing off across a pad isn't thrown")
walk(LaunchPads.direction(pad))
Pads.tick(0.1)
local botPush = botRoot:FindFirstChild("LaunchPad")
check(botPush and botPush:IsA("LinearVelocity") and botRoot.AssemblyLinearVelocity.Y > 50, "one walking onto it its way is")
check(#launches == launchesBefore + 1 and launches[#launches].player == bot.id and counter("LaunchPads.botLaunches") == 1, "and everyone hears of it")
local landsAt = body:GetAttribute("LandsAt")
check(type(landsAt) == "number" and landsAt > workspace:GetServerTimeNow(), "it's told when it comes down")
-- Its brain, on its way somewhere with a path in hand, drops the path
-- and plans again once it's down.
local brain = BotBrain.new(bot, body, BotConfig.tuning())
local now = workspace:GetServerTimeNow()
brain.goal = LaunchPads.landing(pad) + LaunchPads.direction(pad) * 60
brain.goalKind = brain:wantedGoal(now)
brain.goalUntil = now + 30
brain.repathAt = now + 30
brain.waypoints = { { Position = LaunchPads.cushion(pad), Action = Enum.PathWaypointAction.Walk } } :: any
brain.waypointIndex = 1
brain:travel(now)
check(#brain.waypoints == 0, "its old path is dropped")
check(brain.repathAt == landsAt and body:GetAttribute("LandsAt") == nil, "and it plans again once it's down")
brain:stop()
away()
-- The bot's own heard from where it happened, on your client.
local camera = workspace.CurrentCamera
camera.CFrame = CFrame.new(launches[#launches].from + Vector3.new(0, 10, 20))
Remotes.CombatEvent:FireAllClients(launches[#launches])
local heard = false
for _, voice in Audio.voices do
	heard = heard or (voice.name == "launch" and (voice.attachment.WorldPosition - launches[#launches].from).Magnitude < 1e-3)
end
check(heard, "someone else's launch farts from where it happened")
task.wait(LaunchPadConfig.COOLDOWN_SECONDS / 2)
walk(LaunchPads.direction(pad))
Pads.tick(0.1)
check(counter("LaunchPads.botLaunches") == 1, "bots wait out the cooldown too")
away()
task.wait(LaunchPadConfig.COOLDOWN_SECONDS)
check(botRoot:FindFirstChild("LaunchPad") == nil, "the bot's push went when it came down")
walk(LaunchPads.direction(pad))
Pads.tick(0.1)
check(counter("LaunchPads.botLaunches") == 2, "then it can go again")

return { status = "PASS", checks = checks }
