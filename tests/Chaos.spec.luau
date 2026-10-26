-- Chain reactions and gas barrels (masterplan 2.3 and 2.5), on the real
-- server:
--   * an explosion blasts the killer's enemies nearby: a chain of players
--     goes off one after another, all credited to the first killer, until
--     the depth limit stops it
--   * blasts never touch the killer's team, and walls stop them
--   * at most PER_TICK blasts resolve per tick
--   * barrels: two shots light the fuse (a lit barrel is marked), then it
--     blasts the shooter's enemies, disappears, and is back 20 s later
--   * barrel -> barrel -> player chains credit the shooter, and barrels
--     next to each other still set each other off on the full-size map
--     (a blast reaches RADIUS past the barrel's side)
--   * the last shot owns a barrel, whichever team fired it
-- Spots are the map layout's numbers times the map's scale (S) where they
-- depend on the map; distances between players are real studs.
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
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local S = require(ReplicatedStorage.Shared.Config.MapConfig).BrainrotBattlefield.scale
local Gas = require(server.Services.GasService)
local Explosions = require(server.Services.ExplosionService)
local Barrels = require(server.Services.BarrelService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TeamService = require(server.Services.TeamService)
local Scores = require(server.Services.MatchScoreService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes

local eliminations, barrelEvents = {}, 0
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if player.Name == "Ace" then
		if event.kind == "elimination" then
			table.insert(eliminations, event)
		elseif event.kind == "barrel" then
			barrelEvents += 1
		end
	end
end)

local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = 900 + nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local function place(player: Player, x: number, y: number, z: number)
	player.Character:PivotTo(CFrame.new(x, y, z))
end
local function alive(player: Player): boolean
	return player.Character ~= nil and player.Character.Humanoid.Health > 0
end
local function fidget()
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:PivotTo(p.Character:GetPivot() * CFrame.new(0, 0, 0.001) + Vector3.new(7, 0, 0))
		end
	end
end

-- Ace and an ally against nine.
local ace, ally = join("Ace"), join("Ally")
local teamA = ace:GetAttribute("TeamId")
local teamB = if teamA == "Stinkers" then "Sharters" else "Stinkers"
TeamService.testSetTeam(ally, teamA)
local foes = {}
for i = 1, 9 do
	local foe = join(`Foe{i}`)
	TeamService.testSetTeam(foe, teamB)
	table.insert(foes, foe)
end
task.wait(3.2)
check(TeamService.counts()[teamA] == 2 and TeamService.counts()[teamB] == 9, "2 against 9")

-- A chain of six, ten studs apart, up in clear air (above the throne):
-- five go off, the depth limit spares the sixth.
for i = 1, 6 do
	place(foes[i], 0, 40 * S, -25 + 10 * (i - 1))
	if i > 1 then
		Gas.add(foes[i], 70, { attacker = ace, cause = "shot" })
	end
end
place(ally, 5, 40 * S, -25) -- right next to the first blast
local before = Scores.getScores()[teamA]
Gas.add(foes[1], 100, { attacker = ace, cause = "shot" })
task.wait(7)
local exploded = {}
for _, event in eliminations do
	exploded[event.victim] = true
end
for i = 1, 5 do
	check(exploded[foes[i].UserId], `chain link {i} exploded`)
end
check(alive(foes[6]) and not exploded[foes[6].UserId] and Gas.gasOf(foes[6]) <= 70, "the depth limit spares the sixth (no blast reached it)")
check((Telemetry.snapshot().counters["Explosion.depthCapped"] or 0) >= 1, "and counts the cut")
check(#eliminations == 5 and Scores.getScores()[teamA] == before + 5, "five eliminations, five points")
for i, event in eliminations do
	check(event.killer == ace.UserId and event.cause == (if i == 1 then "shot" else "chain"), `link {i} credited to Ace ({event.cause})`)
end
check(alive(ally) and Gas.gasOf(ally) == 0, "the blasts never touch Ace's team")
task.wait(3.2)
fidget()

-- Walls stop blasts: the spawn room's front wall (z = -57 in the layout)
-- stands between two players 13 studs apart, inside the blast's reach.
task.wait(3.2)
local inside, outside = foes[7], foes[8]
local frontWall = -57 * S
place(foes[1], 0, 3, frontWall + 7) -- the Stinkers' spawn plaza
place(inside, 0, 3, frontWall - 6) -- inside the spawn room, behind its front wall
place(outside, 6, 3, frontWall + 7)
Gas.add(foes[1], 100, { attacker = ace, cause = "shot" })
task.wait(1.4)
check(Gas.gasOf(outside) == 40, "the blast reaches someone in the open")
check(Gas.gasOf(inside) == 0, "but not through the wall")
Gas.reset(outside)

-- The per-tick budget.
for i = 1, 20 do
	Explosions.blast({ position = Vector3.new(i * 50, 500, 0), radius = 1, gas = 1, owner = ace, ownerTeam = teamA, cause = "chain", depth = 1 })
end
Explosions.step()
check(Explosions.pending() == 20 - GameConfig.EXPLOSION.PER_TICK, `{GameConfig.EXPLOSION.PER_TICK} blasts a tick, the rest wait`)
task.wait(0.3)
check(Explosions.pending() == 0, "and resolve over the next few ticks")
task.wait(3)
fidget()

-- Barrels.
local function barrelAt(x: number, z: number): Model
	for _, model in Barrels.all() do
		local p = model.PrimaryPart.Position
		if math.abs(p.X - x) < 0.1 and math.abs(p.Z - z) < 0.1 then
			return model
		end
	end
	error(`no barrel at {x}, {z}`)
end
-- The Gas Gutter's pair (the layout's 66, -12 and 70, -16), and one by
-- Porcelain Plaza.
local barrel1, barrel2, barrel3 = barrelAt(66 * S, -12 * S), barrelAt(70 * S, -16 * S), barrelAt(12 * S, -16 * S)
local b1, b2 = barrel1.PrimaryPart.Position, barrel2.PrimaryPart.Position
local reach = GameConfig.BARREL.RADIUS + math.max(barrel1.PrimaryPart.Size.X, barrel1.PrimaryPart.Size.Y, barrel1.PrimaryPart.Size.Z) / 2
check((b1 - b2).Magnitude <= reach, "the pair is within a blast of each other")
check(#Barrels.all() == 12 and barrel1:GetAttribute("Ready") and barrel1:GetAttribute("Health") == 40, "12 barrels, ready, 40 health")

task.wait(3.2)
local shotsFired = 0
local function shoot(direction: Vector3)
	shotsFired += 1
	Remotes.FireWeapon.OnServerEvent:Fire(ace, direction, 10000 + shotsFired)
	task.wait(0.31)
end
local near, chained, far = foes[1], foes[2], foes[3]
local along = Vector3.new(b2.X - b1.X, 0, b2.Z - b1.Z).Unit -- from barrel 1 to 2
local function spot(from: Vector3, offset: Vector3): (number, number)
	return from.X + offset.X, from.Z + offset.Z
end
local function out(player: Player, x: number, z: number)
	place(player, x, 3, z)
end
out(ace, b1.X, b1.Z - 15) -- shooting barrel 1 along +Z, clear of barrel 2
out(ally, spot(b1, Vector3.new(4, 0, 6))) -- by the barrel: Ace's team is never hurt
out(near, spot(b1, -along * 10)) -- 10 from barrel 1, out of barrel 2's reach
out(chained, spot(b1, Vector3.new(-12, 0, 0))) -- barrel 1 only, far from the rest
out(far, spot(b2, along * 10)) -- 10 from barrel 2 only
for _, p in { near, chained, far } do
	Gas.reset(p)
end
Gas.add(chained, 70, { attacker = ace, cause = "shot" })
eliminations = {}
shoot(Vector3.new(0, 0, 1))
check(barrel1:GetAttribute("Health") == 20 and barrel1:GetAttribute("Ready"), "one shot: half health")
shoot(Vector3.new(0, 0, 1))
check(barrel1:GetAttribute("FuseAt") ~= nil and not barrel1:GetAttribute("Ready"), "two: the fuse is lit")
task.wait(0.7)
check(barrelEvents == 1 and barrel1.PrimaryPart.Transparency == 1 and not barrel1.PrimaryPart.CanQuery, "it blows and disappears")
check(Gas.gasOf(near) == 40, "the blast gasses an enemy nearby")
check(Gas.gasOf(ally) == 0, "not Ace's ally")
task.wait(4)
check(eliminations[1] and eliminations[1].victim == chained.UserId and eliminations[1].killer == ace.UserId and eliminations[1].cause == "barrel", "a barrel elimination, credited to Ace")
check(not barrel2:GetAttribute("Ready"), "the barrel next to it went off too")
check(Gas.gasOf(far) == 40, "and gassed the enemy by it: barrel, barrel, player")
check((Telemetry.snapshot().counters["Elimination.cause.barrel"] or 0) >= 1, "barrel kills are counted")

-- The last shot owns a barrel.
local b3 = barrel3.PrimaryPart.Position
out(ally, b3.X, b3.Z + 10)
out(near, b3.X, b3.Z - 10)
Gas.reset(ally)
Gas.reset(near)
check(Barrels.shoot(ace, barrel3.PrimaryPart, 20), "Ace hits barrel 3")
check(Barrels.shoot(near, barrel3.PrimaryPart, 20), "then an enemy finishes it")
task.wait(1)
check(Gas.gasOf(ally) == 40 and Gas.gasOf(near) == 0, "so it blasts Ace's side")

-- Respawn.
fidget()
task.wait(GameConfig.BARREL.RESPAWN_SECONDS)
check(barrel1:GetAttribute("Ready") and barrel1:GetAttribute("Health") == 40 and barrel1.PrimaryPart.Transparency == 0, "20 s later the barrel is back, full")
check(barrel1.PrimaryPart.CanQuery and barrel1.PrimaryPart.CanCollide, "and solid")

return { status = "PASS", checks = checks }
