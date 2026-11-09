-- Bots and the whole arsenal, on the real server, with stand-in avatars on
-- an empty range well away from the map (BotConfig.WEAPONS, BotService's
-- loadouts, BotBrain, CombatService.fireAsBot, ProjectileService,
-- DashService.dashAsBot, AbilityService.useAsBot):
--   * the pick: every gun comes up about as often as weighted, a team's bots
--     lean away from what their teammates carry (more guns per team than
--     picking blind), each with a Q ability that suits its gun
--   * a life's gun: in its hand (the Gas Blaster BotDirector builds it with
--     swapped), at that gun's walk speed, Weapon and Ability on the avatar
--   * each gun's shots: the Spritzer's full gas close up, less at 80 and
--     nothing past 90; the Thunderclapper heavy at 300 and slow; the Stink
--     Lobber thrown, its splash and cloud credited to the bot
--   * each gun's fight: where it closes in, holds and backs off; a Spritzer
--     holds its fire at 120 and sprays at 40, a Thunderclapper fires at 200
--     and backs off at 50, a Lobber lobs at 100 but not at 160; never faster
--     than its gun
--   * lobs: both arcs land where aimed; with a wall in the way the high one;
--     a target gone behind the wall is still lobbed at, over it, for a moment
--   * Fart Dash: a player's cooldown and checks (not mid-countdown, not dead,
--     too far put back), the trail for everyone, fresh each life; in a fight
--     a bot dashes in at a far target and away from a near one, never twice
--     in a cooldown, never where its gun likes to be, never from mid-air
--   * Q: Recovery Burst and Gas Pulse on a player's rules; a bot vents at
--     high gas after its reaction time, and pulses a target in reach
--   * fair: every gun aims the same
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
do
	local run = assert(loadstring(server.Bootstrap.Source, "Bootstrap"))
	setfenv(run, setmetatable({ script = server.Bootstrap }, { __index = getfenv() }))
	run()
end
-- No bots but the spec's own.
require(server.Services.BotDirector).testSetEnabled(false)
local Shared = ReplicatedStorage.Shared
local BotConfig = require(Shared.Config.BotConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local WeaponModel = require(Shared.WeaponModel)
local Bots = require(server.Services.BotService)
local Combat = require(server.Services.CombatService)
local Dash = require(server.Services.DashService)
local Abilities = require(server.Services.AbilityService)
local Projectiles = require(server.Services.ProjectileService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local AFK = require(server.Services.AFKService)
local Round = require(server.Services.RoundService)
local Brain = require(server.Bots.BotBrain)
local Remotes = ReplicatedStorage.Remotes
local WEAPONS = WeaponConfig.weapons
local DASH = AbilityConfig.FartDash
local TICK = BotConfig.THINK_SECONDS

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Everything Ada's client hears, and when.
type Heard = { event: any, at: number }
local heard: { Heard } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if player.Name == "Ada" then
		table.insert(heard, { event = event, at = now() })
	end
end)
-- Shots come a frame's worth at a time, unreliably (ShotFeed): each heard
-- when its frame's are sent, at the end of every frame here as the
-- Heartbeat sends them in Roblox.
local ShotFeed = require(server.ShotFeed)
task.spawn(function()
	while true do
		ShotFeed.flush()
		task.wait()
	end
end)
Remotes.Shots.FiredToClient:Connect(function(player, shooters, froms, tos)
	if player.Name == "Ada" then
		for i, shooter in shooters do
			table.insert(heard, { event = { kind = "shot", shooter = shooter, from = froms[i], to = tos[i] }, at = now() })
		end
	end
end)
-- Events of `kinds` from combatant `id` (a shot's or a throw's shooter, a
-- dash's or an ability's player) since `since`.
local function from(id: number, kinds: { string }, since: number): { Heard }
	ShotFeed.flush()
	local list = {}
	for _, entry in heard do
		local event = entry.event
		if entry.at >= since and table.find(kinds, event.kind) and (event.shooter == id or event.player == id) then
			table.insert(list, entry)
		end
	end
	return list
end
-- The closest two of `entries` came together.
local function closest(entries: { Heard }): number
	local least = math.huge
	for i = 2, #entries do
		least = math.min(least, entries[i].at - entries[i - 1].at)
	end
	return least
end

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end

-- The range: flat, empty ground well away from the map, along +X.
local ORIGIN = Vector3.new(3000, 0, 3000)
local ground = Instance.new("Part")
ground.Name = "TestRange"
ground.Anchored = true
ground.Size = Vector3.new(1600, 1, 1600)
ground.CFrame = CFrame.new(ORIGIN - Vector3.new(0, 0.5, 0))
ground.Parent = workspace
-- Standing `x` studs down the range and `z` across it.
local function spot(x: number, z: number?): Vector3
	return ORIGIN + Vector3.new(x, 3, z or 0)
end

-- A new life for `bot`: an avatar as BotDirector builds one (holding the
-- Gas Blaster, on the ground), standing `x` down the range facing `toward`
-- (both `z` across), adopted with `loadout` (nil: the pick) and, unless
-- `protected`, past its spawn protection.
type Options = { z: number?, protected: boolean? }
local function spawnBot(bot: any, x: number, toward: number, loadout: any?, options: Options?): Model
	local z = options and options.z or 0
	local model = Instance.new("Model")
	model.Name = bot.name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.lookAt(spot(x, z), spot(toward, z))
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.Parent = model
	model.PrimaryPart = root
	WeaponModel.tool("GasBlaster", "Gas Blaster").Parent = model
	model.Parent = workspace
	Bots.attach(bot, model, loadout)
	if not (options and options.protected) then
		Bots.endProtection(bot)
	end
	return model
end
local function aimAt(shooterBody: Model, targetBody: Model): Vector3
	return ((targetBody :: any).HumanoidRootPart.Position - (shooterBody :: any).Head.Position).Unit
end
local function last(kind: string, victim: number): any
	for i = #heard, 1, -1 do
		local event = heard[i].event
		if event.kind == kind and event.victim == victim then
			return event
		end
	end
	return nil
end

-- A player and three bots start a round.
local ada = join("Ada", 901)
local teamA = ada:GetAttribute("TeamId")
local teamB = if teamA == "Stinkers" then "Sharters" else "Stinkers"
local shooter = Bots.add(teamB, "Shooter")
local mate = Bots.add(teamB, "Mate")
local dummy = Bots.add(teamA, "Dummy")
task.wait(0.5)
check(Round.phase() == "ACTIVE", "a round is on")
local function awake()
	AFK.markActive(ada)
end

-- The shooter `distance` down the range from a still dummy, facing it.
local function duelists(weapon: string, distance: number, ability: string?): (Model, Model)
	local a = spawnBot(shooter, 0, distance, { weapon = weapon, ability = ability })
	local b = spawnBot(dummy, distance, 0, { weapon = "GasBlaster" })
	return a, b
end
-- A fight: `weapon`'s bot against the dummy `distance` away, its brain
-- thinking for `seconds` (the dummy never blows up).
type Duel = { shots: { Heard }, dashes: { Heard }, abilities: { Heard }, brain: any, body: Model, target: Model }
type DuelOptions = { ability: string?, airborne: boolean? }
local function duel(weapon: string, distance: number, seconds: number, options: DuelOptions?): Duel
	local a, b = duelists(weapon, distance, options and options.ability)
	if options and options.airborne then
		(a :: any).Humanoid.FloorMaterial = Enum.Material.Air
	end
	local brain = Brain.new(shooter, a, BotConfig.tuning())
	local since = now()
	for _ = 1, math.ceil(seconds / TICK) do
		brain:tick(TICK)
		ShotFeed.flush() -- the frame ends: its shots go out
		task.wait(TICK)
		Bots.vent(dummy, 100)
	end
	brain:stop()
	awake()
	return {
		shots = from(shooter.id, { "shot", "lob" }, since),
		dashes = from(shooter.id, { "dash" }, since),
		abilities = from(shooter.id, { "ability" }, since),
		brain = brain,
		body = a,
		target = b,
	}
end

-- The pick.
local total = 0
for _, id in WeaponConfig.order do
	local style = BotConfig.WEAPONS[id]
	check(style and style.weight > 0, `bots carry the {id}`)
	check(style.backUp < style.closeIn and style.closeIn <= style.fireRange and style.fireRange <= WEAPONS[id].range, `{id}: backs off, closes in and fires inside its reach`)
	for ability, weight in style.abilities do
		check(AbilityConfig[ability] and AbilityConfig[ability].input == Enum.KeyCode.Q and weight > 0, `{id} goes with {ability}, a Q ability`)
	end
	total += style.weight
end
local rng = Random.new(2024)
local N = 6000
local counts, paired = {}, {}
for _ = 1, N do
	local weapon, ability = BotConfig.pickLoadout(rng, {})
	counts[weapon] = (counts[weapon] or 0) + 1
	local key = `{weapon}/{ability}`
	paired[key] = (paired[key] or 0) + 1
	check(ability == nil or BotConfig.WEAPONS[weapon].abilities[ability], "an ability its gun goes with")
end
for _, id in WeaponConfig.order do
	local share, expected = (counts[id] or 0) / N, BotConfig.WEAPONS[id].weight / total
	check(math.abs(share - expected) < 0.025, `the {id}: {share} of lives, about its {expected}`)
end
check((paired["Spritzer/GasPulse"] or 0) > (paired["Spritzer/RecoveryBurst"] or 0), "a Spritzer bot mostly brings Gas Pulse")
check((paired["Thunderclapper/RecoveryBurst"] or 0) > (paired["Thunderclapper/GasPulse"] or 0), "a Thunderclapper bot mostly Recovery Burst")
-- Each teammate carrying a gun makes it rarer.
local blasters = 0
for _ = 1, N do
	if BotConfig.pickLoadout(rng, { "GasBlaster", "GasBlaster" }) == "GasBlaster" then
		blasters += 1
	end
end
local blaster = BotConfig.WEAPONS.GasBlaster.weight * BotConfig.SAME_WEAPON_FACTOR ^ 2
local expected = blaster / (total - BotConfig.WEAPONS.GasBlaster.weight + blaster)
check(math.abs(blasters / N - expected) < 0.02, `two teammates with the Blaster: a third has it {blasters / N} of the time, about {expected}`)
-- Teams of five, each bot picking after the one before.
local function team(lean: boolean): number
	local carried: { string } = {}
	for _ = 1, 5 do
		table.insert(carried, (BotConfig.pickLoadout(rng, if lean then carried else {})))
	end
	local seen, distinct = {}, 0
	for _, id in carried do
		if not seen[id] then
			seen[id] = true
			distinct += 1
		end
	end
	return distinct
end
local leaning, blind = 0, 0
for _ = 1, 1000 do
	leaning += team(true)
	blind += team(false)
end
check(leaning / 1000 >= 3.4 and leaning > blind + 300, `a team of five bots carries {leaning / 1000} of the four guns ({blind / 1000} picked blind)`)

-- A life's gun.
local body = spawnBot(shooter, 0, 10, { weapon = "Thunderclapper", ability = "RecoveryBurst" })
local function guns(model: Model): { Tool }
	local list = {}
	for _, child in model:GetChildren() do
		if child.Name == "HeldWeapon" and child:IsA("Tool") then
			table.insert(list, child)
		end
	end
	return list
end
check(shooter.weapon == "Thunderclapper" and Bots.weaponOf(shooter) == WEAPONS.Thunderclapper and shooter.ability == "RecoveryBurst", "this life's loadout")
local held = guns(body)
check(#held == 1 and held[1]:GetAttribute("Weapon") == "Thunderclapper", "the Thunderclapper in its hands, in place of the Blaster it was built holding")
check((body :: any).Humanoid.WalkSpeed == WEAPONS.Thunderclapper.walkSpeed, "walking at the Thunderclapper's speed")
check(body:GetAttribute("Weapon") == "Thunderclapper" and body:GetAttribute("Ability") == "RecoveryBurst", "and every client can see which (attributes on the avatar)")
body = spawnBot(shooter, 0, 10, { weapon = "GasBlaster" })
held = guns(body)
check(#held == 1 and held[1]:GetAttribute("Weapon") == "GasBlaster" and (body :: any).Humanoid.WalkSpeed == 16, "the next life, the Blaster it was built with")
check(shooter.ability == nil and body:GetAttribute("Ability") == nil, "and no ability unless it has one")
spawnBot(shooter, 0, 10, { weapon = "Bazooka", ability = "FartDash" })
check(shooter.weapon == "GasBlaster" and shooter.ability == nil, "a gun nobody knows is the Blaster; Fart Dash isn't on Q")
local squad, carriedBy = {}, {}
for i = 1, 4 do
	local bot = Bots.add(teamA, `Squad{i}`)
	local model = spawnBot(bot, 300 + i * 8, 0, nil, { z = 300 })
	table.insert(squad, bot)
	carriedBy[bot.weapon] = true
	local gun = guns(model)
	check(#gun == 1 and gun[1]:GetAttribute("Weapon") == bot.weapon and model:GetAttribute("Weapon") == bot.weapon, `{bot.name}: its own pick in its hands ({bot.weapon})`)
	check((model :: any).Humanoid.WalkSpeed == WEAPONS[bot.weapon].walkSpeed, "at its walk speed")
	check(bot.ability == nil or BotConfig.WEAPONS[bot.weapon].abilities[bot.ability], "with an ability that goes with it")
end
local mix = 0
for _ in carriedBy do
	mix += 1
end
check(mix >= 2, `four new lives on one team, nobody saying what they carry: {mix} different guns`)
for _, bot in squad do
	Bots.remove(bot)
end

-- Each gun's shots.
task.wait(0.35)
local a, b = duelists("Spritzer", 30)
check(Combat.fireAsBot(shooter, aimAt(a, b)) and Bots.gasOf(dummy) == WEAPONS.Spritzer.gasPerHit, "a Spritzer bot at 30 studs: full gas")
check(not Combat.fireAsBot(shooter, aimAt(a, b)), "not again inside its tenth of a second")
task.wait(0.11)
check(Combat.fireAsBot(shooter, aimAt(a, b)) and Bots.gasOf(dummy) == 2 * WEAPONS.Spritzer.gasPerHit, "then again")
task.wait(0.11)
a, b = duelists("Spritzer", 80)
check(Combat.fireAsBot(shooter, aimAt(a, b)) and Bots.gasOf(dummy) == Combat.gasAt(WEAPONS.Spritzer, 79.5, false), `at 80 studs, less: {Bots.gasOf(dummy)}`)
check(Bots.gasOf(dummy) < WEAPONS.Spritzer.gasPerHit, "less than close up")
task.wait(0.11)
a, b = duelists("Spritzer", 100)
local since = now()
check(Combat.fireAsBot(shooter, aimAt(a, b)) and Bots.gasOf(dummy) == 0, "past 90 studs, nothing")
local spray = from(shooter.id, { "shot" }, since)
check(#spray == 1 and math.abs((spray[1].event.to - spray[1].event.from).Magnitude - WEAPONS.Spritzer.range) < 0.01, "everyone sees its spray stop at 90")
task.wait(0.35)
a, b = duelists("Thunderclapper", 300)
check(Combat.fireAsBot(shooter, aimAt(a, b)) and Bots.gasOf(dummy) == Combat.gasAt(WEAPONS.Thunderclapper, 299.5, false), `a Thunderclapper bot at 300 studs: {Bots.gasOf(dummy)}`)
check(Bots.gasOf(dummy) > 30, "still a heavy hit")
task.wait(0.5)
check(not Combat.fireAsBot(shooter, aimAt(a, b)), "not again inside its second")
task.wait(0.55)
check(Combat.fireAsBot(shooter, aimAt(a, b)), "then again")
-- The Stink Lobber: a throw, not a shot, credited to the bot.
task.wait(1.05)
a, b = duelists("StinkLobber", 90)
check(Bots.addGas(dummy, 90, { team = teamB, bot = mate.id, cause = "shot" }), "the dummy nearly gone")
since = now()
local point = (b :: any).HumanoidRootPart.Position - Vector3.new(0, 2, 0)
local low = Brain.arcs((a :: any).Head.Position, point, WEAPONS.StinkLobber)
check(low ~= nil and Combat.fireAsBot(shooter, low), "a Lobber bot throws")
local throws = from(shooter.id, { "lob" }, since)
check(#throws == 1 and #from(shooter.id, { "shot" }, since) == 0, "a stink bomb, not a shot: everyone sees the arc")
local throw = throws[1].event
check(type(throw.flight) == "number" and throw.flight > 0.5 and type(throw.path) == "table" and #throw.path >= 3, "with its path and flight")
check((throw.to - (b :: any).HumanoidRootPart.Position).Magnitude < 4, "landing on the target")
check(not Combat.fireAsBot(shooter, low), "and not again inside its 1.4 seconds")
task.wait(throw.flight + 0.2)
check(Bots.isExploding(dummy), "the splash sets the dummy off")
task.wait(1.1)
local kill = last("elimination", dummy.id)
check(kill and kill.killer == shooter.id and kill.team == teamB, "credited to the bot that threw it")
check(Projectiles.cloudCount() >= 1, "and its cloud lingers")
b = spawnBot(dummy, 90, 0, { weapon = "GasBlaster" })
spawnBot(mate, 90, 0, { weapon = "GasBlaster" }, { z = 2 })
task.wait(1.05)
check(Bots.gasOf(dummy) >= WEAPONS.StinkLobber.cloudGas, `the bot's cloud gasses an enemy standing in it ({Bots.gasOf(dummy)})`)
check(Bots.gasOf(mate) == 0, "never its teammate")
task.wait(WEAPONS.StinkLobber.cloudSeconds)
check(Projectiles.cloudCount() == 0, "the cloud fades")

-- Each gun's fight.
local fight = duel("Spritzer", 120, 2)
check(#fight.shots == 0 and fight.brain.intent == 1, "a Spritzer bot 120 studs off holds its fire and closes in")
fight = duel("Spritzer", 40, 2)
check(#fight.shots >= 6 and fight.shots[1].event.kind == "shot" and fight.brain.intent == 1, `at 40 it sprays ({#fight.shots} in 2 s), still closing in`)
check(closest(fight.shots) >= WEAPONS.Spritzer.fireInterval - 1e-6, "never faster than the Spritzer")
fight = duel("Spritzer", 15, 1)
check(fight.brain.intent == 0, "at 15 it holds its ground")
fight = duel("Thunderclapper", 200, 3)
check(#fight.shots >= 1 and fight.brain.intent == 0, `a Thunderclapper bot fires at 200 studs ({#fight.shots} in 3 s) and holds`)
check(closest(fight.shots) >= WEAPONS.Thunderclapper.fireInterval - 1e-6, "never faster than the Thunderclapper")
fight = duel("Thunderclapper", 50, 1)
check(fight.brain.intent == -1, "at 50 it backs off")
fight = duel("GasBlaster", 100, 2)
check(#fight.shots >= 2 and fight.brain.intent == 1, "a Gas Blaster bot fires at 100 and closes in, as it always did")
check(closest(fight.shots) >= WEAPONS.GasBlaster.fireInterval - 1e-6, "never faster than the Blaster")
check(duel("GasBlaster", 40, 1).brain.intent == 0, "at 40 it holds")
check(duel("GasBlaster", 10, 1).brain.intent == -1, "at 10 it backs up")
fight = duel("StinkLobber", 100, 3)
check(#fight.shots >= 1 and fight.shots[1].event.kind == "lob" and fight.brain.intent == 0, `a Stink Lobber bot lobs at 100 studs ({#fight.shots} in 3 s) and holds`)
check(closest(fight.shots) >= WEAPONS.StinkLobber.fireInterval - 1e-6, "never faster than the Lobber")
fight = duel("StinkLobber", 160, 1.5)
check(#fight.shots == 0 and fight.brain.intent == 1, "at 160, past its throw, it closes in first")
check(duel("StinkLobber", 20, 1).brain.intent == -1, "at 20 it backs off")
task.wait(WEAPONS.StinkLobber.cloudSeconds)

-- Lobs.
a, b = duelists("StinkLobber", 100)
local head = (a :: any).Head.Position
point = (b :: any).HumanoidRootPart.Position - Vector3.new(0, 2, 0)
local flatLow, steep = Brain.arcs(head, point, WEAPONS.StinkLobber)
check(flatLow and steep and steep.Y > flatLow.Y + 0.4, "two arcs reach 100 studs, a low one and a high one")
for _, direction in { flatLow, steep } do
	local landing = Projectiles.arc(head, direction, WEAPONS.StinkLobber, { a })
	check(Vector3.new(landing.X - point.X, 0, landing.Z - point.Z).Magnitude < 3, "each comes down on the target")
end
check(Brain.arcs(head, spot(170) - Vector3.new(0, 2, 0), WEAPONS.StinkLobber) == nil, "none reaches 170")
local wall = Instance.new("Part")
wall.Name = "TestWall"
wall.Anchored = true
wall.Size = Vector3.new(2, 25, 40)
wall.CFrame = CFrame.new(ORIGIN + Vector3.new(50, 12.5, 0))
wall.Parent = workspace
local brain = Brain.new(shooter, a, BotConfig.tuning())
check(not brain:arcClear(head, flatLow, point, b), "a wall in the way stops the low arc")
local over = brain:lobAim(head, point, false, b)
check(over ~= nil and over:Dot(steep) > 0.999, "so it throws the high one")
local landing = Projectiles.arc(head, over, WEAPONS.StinkLobber, { a })
check(Vector3.new(landing.X - point.X, 0, landing.Z - point.Z).Magnitude < 3, "which clears the wall and lands on them")
brain:stop()
-- A target that ducks behind the wall.
wall.Parent = nil
a, b = duelists("StinkLobber", 100)
brain = Brain.new(shooter, a, BotConfig.tuning())
for _ = 1, 3 do
	brain:tick(TICK)
	task.wait(TICK)
end
check(brain.target and brain.visible, "a Lobber bot has its target in sight")
wall.Parent = workspace
since = now()
for _ = 1, math.ceil((BotConfig.LOB_BLIND_SECONDS + 0.5) / TICK) do
	brain:tick(TICK)
	task.wait(TICK)
	Bots.vent(dummy, 100)
end
check(not brain.visible, "the wall hides them")
local overCover = from(shooter.id, { "lob" }, since)
check(#overCover >= 1, "but it lobs at where they went")
local peak = -math.huge
for _, p in overCover[1].event.path do
	peak = math.max(peak, p.Y)
end
check(peak > wall.Position.Y + wall.Size.Y / 2 + 10 and overCover[1].event.to.X > wall.Position.X + 2, `high, over the wall (up to {peak}), coming down beyond it`)
since = now()
for _ = 1, 16 do
	brain:tick(TICK)
	task.wait(TICK)
end
check(#from(shooter.id, { "lob" }, since) == 0, "and after a moment, stops")
brain:stop()
wall:Destroy()
awake()

-- Fart Dash.
task.wait(WEAPONS.StinkLobber.cloudSeconds)
a, b = duelists("Spritzer", 60)
since = now()
check(Dash.dashAsBot(shooter, Vector3.new(1, 0, 0)), "a bot's Fart Dash")
local trail = from(shooter.id, { "dash" }, since)
check(#trail == 1 and trail[1].event.direction:Dot(Vector3.xAxis) > 0.999 and (trail[1].event.from - (a :: any).HumanoidRootPart.Position).Magnitude < 0.01, "everyone sees its trail")
local push = (a :: any).HumanoidRootPart:FindFirstChild("FartDash")
check(push and push.LineVelocity == DASH.speed and push.LineDirection:Dot(Vector3.xAxis) > 0.999, "the server pushes it at a dash's speed")
task.wait(DASH.durationSeconds + 0.05)
check((a :: any).HumanoidRootPart:FindFirstChild("FartDash") == nil, "for a dash's length")
check(not Dash.dashAsBot(shooter, Vector3.xAxis), "not again inside the cooldown")
task.wait(DASH.cooldownSeconds)
local start = (a :: any).HumanoidRootPart.Position
check(Dash.dashAsBot(shooter, Vector3.xAxis), "after it, another")
a:PivotTo(CFrame.new(start + Vector3.new(60, 0, 0)))
task.wait((DASH.checkSeconds :: number) + 0.1)
check(((a :: any).HumanoidRootPart.Position - start).Magnitude < 0.01, "one that went too far is put back, as a player is")
check(not Dash.dashAsBot(shooter, Vector3.zero) and not Dash.dashAsBot(shooter, Vector3.yAxis), "only along the ground")
task.wait(DASH.cooldownSeconds)
check(Bots.addGas(shooter, 100, { team = teamA, cause = "shot" }) and not Dash.dashAsBot(shooter, Vector3.xAxis), "no dash mid-countdown")
task.wait(1.2)
check(not Bots.isAlive(shooter) and not Dash.dashAsBot(shooter, Vector3.xAxis), "nor dead")
a, b = duelists("Spritzer", 60)
check(Dash.dashAsBot(shooter, Vector3.xAxis), "a new life, a fresh dash")
task.wait(DASH.cooldownSeconds)
-- In a fight.
fight = duel("Spritzer", 60, 12)
check(#fight.dashes >= 1, `a Spritzer bot dashes in at a target 60 studs off ({#fight.dashes} in 12 s)`)
for _, dash in fight.dashes do
	check(dash.event.direction:Dot(Vector3.xAxis) > 0.99, "toward it")
end
check(closest(fight.dashes) >= DASH.cooldownSeconds - 1e-6, "never twice in a cooldown")
fight = duel("Thunderclapper", 20, 12)
check(#fight.dashes >= 1 and fight.dashes[1].event.direction:Dot(Vector3.xAxis) < -0.99, `a Thunderclapper bot dashes away from a target 20 studs off ({#fight.dashes} in 12 s)`)
check(#duel("GasBlaster", 40, 8).dashes == 0, "a Gas Blaster bot at 40 studs, where it likes to be, doesn't")
check(#duel("Spritzer", 60, 8, { airborne = true }).dashes == 0, "nor does anyone from mid-air")

-- Q.
a, b = duelists("Thunderclapper", 60, "RecoveryBurst")
check(not Abilities.useAsBot(shooter), "Recovery Burst with nothing to vent: refused")
check(Bots.addGas(shooter, 70, { team = teamA, cause = "shot" }), "70% gas")
since = now()
check(Abilities.useAsBot(shooter) and Bots.gasOf(shooter) == 35, "vents 35")
local used = from(shooter.id, { "ability" }, since)
check(#used == 1 and used[1].event.ability == "RecoveryBurst" and typeof(used[1].event.position) == "Vector3", "everyone sees the puff")
check(Bots.addGas(shooter, 20, { team = teamA, cause = "shot" }) and not Abilities.useAsBot(shooter), "not again inside its cooldown")
local far = Bots.add(teamA, "Far")
a = spawnBot(shooter, 0, 8, { weapon = "Spritzer", ability = "GasPulse" }, { protected = true })
b = spawnBot(dummy, 8, 0, { weapon = "GasBlaster" })
spawnBot(mate, 0, 8, { weapon = "GasBlaster" }, { z = 6 })
spawnBot(far, 20, 0, { weapon = "GasBlaster" }, { z = 4 })
check(Bots.isProtected(shooter) and Abilities.useAsBot(shooter), "Gas Pulse")
check(not Bots.isProtected(shooter), "which ends its spawn protection")
check(Bots.gasOf(dummy) == 0, "nothing in the wind-up")
task.wait(AbilityConfig.GasPulse.durationSeconds + 0.2)
check(Bots.gasOf(dummy) == AbilityConfig.GasPulse.gas, "then the ring: 15% to the enemy in it")
check(Bots.gasOf(mate) == 0 and Bots.gasOf(far) == 0, "none to a teammate, or out of reach")
check(not Abilities.useAsBot(shooter), "not again inside its cooldown")
-- In a fight: venting at high gas, after its reaction time...
a, b = duelists("Thunderclapper", 300, "RecoveryBurst")
check(Bots.addGas(shooter, 70, { team = teamA, cause = "shot" }), "a bot with Recovery Burst at 70% gas")
brain = Brain.new(shooter, a, BotConfig.tuning())
since = now()
for _ = 1, 16 do
	brain:tick(TICK)
	task.wait(TICK)
end
brain:stop()
used = from(shooter.id, { "ability" }, since)
check(#used == 1 and Bots.gasOf(shooter) == 35, "vents it")
check(used[1].at - since >= BotConfig.tuning().reactionSeconds * 0.85 - TICK, "after its reaction time")
-- ...and pulsing a target in reach.
fight = duel("Spritzer", 6, 1.5, { ability = "GasPulse" })
check(#fight.abilities == 1 and fight.abilities[1].event.ability == "GasPulse", "a Spritzer bot with Gas Pulse uses it on a target 6 studs off")
fight = duel("Spritzer", 20, 1.5, { ability = "GasPulse" })
check(#fight.abilities == 0, "but not on one out of its reach")

-- Fair: the gun changes where a bot fights, never how well it aims.
local cones = {}
for _, id in WeaponConfig.order do
	a = duelists(id, 100)
	brain = Brain.new(shooter, a, BotConfig.tuning())
	brain.seenAt = -math.huge
	table.insert(cones, brain:errorCone(now(), Vector3.xAxis, 100, Vector3.new(0, 0, 8)))
	brain:stop()
end
local tuning = BotConfig.tuning()
local cone = tuning.aimErrorDegrees + tuning.speedErrorDegrees * 8 / 16 + tuning.distanceErrorDegrees
for i, value in cones do
	check(math.abs(value - cone) < 1e-9, `{WeaponConfig.order[i]}: the same aim as any gun ({value} degrees)`)
end

return { status = "PASS", checks = checks }
