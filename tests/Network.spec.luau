-- Network resilience and performance budgets (masterplan 5.2):
--   * latency: a late shot at a target standing still still hits; a shot
--     aimed at where a moving target used to be misses, because the server
--     casts every shot against where players are now; only the server's
--     verdict shows a hit marker (the client's own tracer is just a picture)
--   * packet loss and jitter: lost shots leave gaps the server accepts;
--     bunched shots within the slack pass; a late, out-of-order shot is
--     dropped, never counted twice
--   * high-ping fairness: shots and hits counted by the shooter's ping
--   * budgets: stink clouds capped on the server; tracers and effect parts
--     capped on the client however much is going on
--   * the profiler: hot paths timed, remote volume counted, /fw perf
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
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local Combat = require(server.Services.CombatService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Projectiles = require(server.Services.ProjectileService)
local Team = require(server.Services.TeamService)
local Telemetry = require(server.Telemetry)
local Profiler = require(server.Profiler)
local TestControls = require(server.TestControls)
local Remotes = ReplicatedStorage.Remotes

local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function rejects(reason: string): number
	local snapshot = Telemetry.snapshot()
	return snapshot.rejects.FireWeapon and snapshot.rejects.FireWeapon[reason] or 0
end
local hits: { [Player]: number } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if event.kind == "hit" and not event.blocked then
		hits[player] = (hits[player] or 0) + 1
	end
end)

-- The client: me, on a team, with nobody to hit.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Controllers = game.StarterPlayer.StarterPlayerScripts.Client.Controllers
local CombatUI = require(Controllers.CombatController)
local Effects = require(Controllers.EffectsController)
Lifecycle.requestPlay(me, nil)
task.wait(0.5)
-- In the open (Porcelain Plaza, clear of the throne; the layout's z = -30
-- on the map built its scale bigger): the bolt stops at the first thing
-- in its way.
me.Character:PivotTo(CFrame.new(0, 3, -30 * require(game.ReplicatedStorage.Shared.Config.MapConfig).BrainrotBattlefield.scale))
check(CombatUI.fire(), "I fire")
local shown = 0
for _, beam in CombatUI.tracers do
	if beam.Transparency == 0 then
		shown += 1
	end
end
check(shown == 1, "my own tracer shows at once")
check(not CombatUI.parts.hitMarker.Visible and (hits[me] or 0) == 0, "but no hit marker: only the server's verdict shows one")
Remotes.RequestSpectate.OnServerEvent:Fire(me)
task.wait(0.2)

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local ada = join("Ada", 2)
local bo = join("Bo", 3)
task.wait(0.3)
if Team.teamOf(ada) == Team.teamOf(bo) then
	Team.testSetTeam(bo, if Team.teamOf(ada) == "Stinkers" then "Sharters" else "Stinkers")
end
check(Team.teamOf(ada) ~= Team.teamOf(bo), "Ada and Bo on opposite teams")
local function place(player: Player, x: number, z: number)
	player.Character:PivotTo(CFrame.new(x, 3, z))
end
-- Down the Gas Gutter lane.
local AIM = Vector3.new(0, 0, 1)
place(ada, 53, -14)
place(bo, 53, 14)
task.wait(3.2) -- past spawn protection
local id = 0
local function shoot(direction: Vector3, delay: number?, shotId: number?)
	id = shotId or (id + 1)
	local sent = id
	if delay then
		task.delay(delay, function()
			Remotes.FireWeapon.OnServerEvent:Fire(ada, direction, sent)
		end)
	else
		Remotes.FireWeapon.OnServerEvent:Fire(ada, direction, sent)
	end
end
local function resetBo()
	-- Back on its feet (after an explosion), unprotected, empty, in place.
	while not (bo.Character and bo.Character:FindFirstChildOfClass("Humanoid") and bo.Character.Humanoid.Health > 0) or Gas.isExploding(bo) do
		task.wait(0.2)
	end
	Lifecycle.endProtection(bo)
	Gas.reset(bo)
	place(bo, 53, 14)
end
local fireInterval = WeaponConfig.weapons.GasBlaster.fireInterval

-- Latency: a target standing still.
resetBo()
shoot(AIM, 0.3)
task.wait(0.4)
check(Gas.gasOf(bo) > 0 and (hits[ada] or 0) == 1, "300 ms late at a target standing still: a hit")
-- A target that moves while the shot is on its way.
task.wait(fireInterval)
resetBo()
local gasBefore = Gas.gasOf(bo)
shoot(AIM, 0.25)
task.wait(0.05)
place(bo, 59, 14) -- strafed 6 studs before the shot arrived
task.wait(0.3)
check(Gas.gasOf(bo) == gasBefore and (hits[ada] or 0) == 1, "aimed where a moving target used to be: a miss, no gas")
check(counter("Combat.shots") >= 3, "the late shots were accepted, just checked against now")

-- Packet loss: shots 1-10 with every third lost.
task.wait(fireInterval)
resetBo()
local duplicates = rejects("duplicate")
local accepted = counter("Combat.shots")
for n = 1, 10 do
	if n % 3 ~= 0 then
		shoot(AIM, nil, id + 1)
	else
		id += 1 -- lost on the way
	end
	task.wait(fireInterval + 0.01)
	if Gas.gasOf(bo) >= 50 then
		resetBo()
	end
end
check(counter("Combat.shots") - accepted == 7 and rejects("duplicate") == duplicates, "7 of 10 arrive: all 7 accepted, gaps and all")
-- Jitter: two shots bunched together after a pause.
task.wait(1)
resetBo()
local before = counter("Combat.shots")
shoot(AIM)
task.wait(fireInterval - 0.04)
shoot(AIM)
check(counter("Combat.shots") - before == 2, "two shots bunched by jitter: both accepted")
-- Out of order: shot n + 2 arrives before n + 1.
task.wait(1)
local nextId = id
shoot(AIM, nil, nextId + 2)
task.wait(fireInterval + 0.01)
shoot(AIM, nil, nextId + 1)
check(rejects("duplicate") == duplicates + 1, "the late one is dropped, not counted twice")
id = nextId + 2

-- High ping, measured.
Combat.pingOf = function(player: Player)
	return if player == ada then 0.3 else 0.05
end
task.wait(1)
resetBo()
shoot(AIM)
task.wait(0.05)
check(counter("Combat.shotsBy.highPing") == 1 and counter("Combat.hitsBy.highPing") == 1, "shots and hits at high ping counted")
check(counter("Combat.shotsBy.lowPing") > 5 and counter("Combat.hitsBy.lowPing") > 5, "and at low ping")
Combat.pingOf = function()
	return 0.05
end

-- Shots on the wire (ShotFeed): unreliable, so a lost one is only a
-- picture and never holds up a hit marker behind it, and a frame's worth
-- at a time as flat arrays (twenty Spritzers fire about 200 a second: that
-- was 200 reliable events a second to every client). Hits, damage and
-- eliminations stay reliable.
local ShotFeed = require(server.ShotFeed)
local RunService = game:GetService("RunService")
type Batch = { shooters: { number }, froms: { Vector3 }, tos: { Vector3 } }
local batches: { [Player]: { Batch } } = {}
Remotes.Shots.FiredToClient:Connect(function(player, shooters, froms, tos)
	batches[player] = batches[player] or {}
	table.insert(batches[player], { shooters = shooters, froms = froms, tos = tos })
end)
local reliableShots = 0
Remotes.CombatEvent.FiredToClient:Connect(function(_, event)
	if event.kind == "shot" then
		reliableShots += 1
	end
end)
check(Remotes.Shots.ClassName == "UnreliableRemoteEvent" and Remotes.CombatEvent.ClassName == "RemoteEvent", "shots go unreliably, everything else on CombatEvent")
task.wait(1)
resetBo()
RunService.Heartbeat:Fire(1 / 60)
table.clear(batches)
local hitsBefore = hits[ada] or 0
shoot(AIM)
check(ShotFeed.pending() == 1 and batches[bo] == nil, "a shot waits for the end of the frame")
check((hits[ada] or 0) == hitsBefore + 1, "while its hit has already gone to the shooter, reliably")
RunService.Heartbeat:Fire(1 / 60)
local one = batches[bo] and batches[bo][1]
check(ShotFeed.pending() == 0 and #batches[bo] == 1 and #batches[ada] == 1 and #batches[me] == 1, "then goes to every client, in one event each")
check(#one.shooters == 1 and one.shooters[1] == ada.UserId and #one.froms == 1 and #one.tos == 1, "as flat arrays: who fired")
check((one.froms[1] - ada.Character.Head.Position).Magnitude < 1e-3 and (one.tos[1] - one.froms[1]).Unit:Dot(AIM) > 0.99, "from where, and where it stopped")
-- A busy frame: everyone's shots in it, split so no event is over the
-- 900 bytes an unreliable event may carry (the stand-in drops one that is).
table.clear(batches)
for i = 1, 45 do
	ShotFeed.add(-1000 - i, Vector3.new(i, 5, 0), Vector3.new(i, 5, -40))
end
RunService.Heartbeat:Fire(1 / 60)
local sizes, order = {}, true
local nextId = -1001
for _, batch in batches[bo] or {} do
	table.insert(sizes, #batch.shooters)
	for i, shooter in batch.shooters do
		order = order and shooter == nextId and batch.froms[i].X == -1000 - shooter
		nextId -= 1
	end
end
check(table.concat(sizes, ",") == "20,20,5" and order, `45 shots in a frame: three events, every shot in order ({table.concat(sizes, ",")})`)
check(reliableShots == 0, "and not one shot as a reliable CombatEvent")

-- Budgets: stink clouds on the server.
local lobber = WeaponConfig.weapons.StinkLobber
for _ = 1, GameConfig.BUDGET.MAX_CLOUDS + 6 do
	Projectiles.throw(ada, ada.Character.Head.Position, Vector3.new(0, -1, 0.3).Unit, lobber)
end
task.wait(1.5)
check(Projectiles.cloudCount() == GameConfig.BUDGET.MAX_CLOUDS, `at most {GameConfig.BUDGET.MAX_CLOUDS} clouds at once`)
check(counter("Projectile.cloudsCapped") == 6, "the oldest end early, counted")
-- Tracers and effects on the client: 100 shots in a frame, five events,
-- and every one of them reaches each thing on the client that shows shots
-- (the bolt from CombatController, the gun's kick from WeaponFxController).
local Fx = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.WeaponFxController)
local bolts, kicks = 0, 0
local tracer, fired = Fx.tracer, Fx.fired
Fx.tracer = function(...)
	bolts += 1
	return tracer(...)
end
Fx.fired = function(...)
	kicks += 1
	return fired(...)
end
table.clear(batches)
for i = 1, 100 do
	ShotFeed.add(2, Vector3.new(0, 5, i), Vector3.new(30, 5, i))
end
RunService.Heartbeat:Fire(1 / 60)
Fx.tracer, Fx.fired = tracer, fired
check(#batches[me] == 5 and bolts == 100 and kicks == 100, `100 shots in a frame: five events, and all 100 drawn ({#batches[me]} events, {bolts} bolts, {kicks} kicks)`)
local parts = 0
for _, child in workspace:GetChildren() do
	if child.Name == "Tracer" then
		parts += 1
	end
end
check(#CombatUI.tracers == GameConfig.BUDGET.MAX_TRACERS and parts == GameConfig.BUDGET.MAX_TRACERS, "100 shots at once: a fixed pool of tracers")
for _ = 1, 300 do
	Effects.dashPuff(Vector3.new(0, 3, 0), Vector3.new(1, 0, 0))
end
check(Effects.liveEffects() <= GameConfig.BUDGET.MAX_EFFECT_PARTS, `300 puffs: at most {GameConfig.BUDGET.MAX_EFFECT_PARTS} effect parts`)
task.wait(1)

-- The profiler.
local names = {}
for _, cost in Profiler.costs() do
	names[cost.name] = cost
end
check(names["Combat.fire"] and names["Combat.fire"].count >= 15, "shot checks timed")
check(names["loop.Gas"] and names["loop.Explosions"] and names["loop.Projectiles"], "gas ticks, blasts and clouds timed")
check(counter("remote.in.FireWeapon") >= 15, "remote volume counted")
local ok, summary = TestControls.perf()
check(ok and string.find(summary, "ms avg", 1, true) and string.find(summary, "busiest remote", 1, true), "/fw perf: " .. summary)

return { status = "PASS", checks = checks }
