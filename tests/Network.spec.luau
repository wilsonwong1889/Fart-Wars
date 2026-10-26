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
-- In the open (Porcelain Plaza, clear of the throne): the bolt stops at
-- the first thing in its way.
me.Character:PivotTo(CFrame.new(0, 3, -30))
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

-- Budgets: stink clouds on the server.
local lobber = WeaponConfig.weapons.StinkLobber
for _ = 1, GameConfig.BUDGET.MAX_CLOUDS + 6 do
	Projectiles.throw(ada, ada.Character.Head.Position, Vector3.new(0, -1, 0.3).Unit, lobber)
end
task.wait(1.5)
check(Projectiles.cloudCount() == GameConfig.BUDGET.MAX_CLOUDS, `at most {GameConfig.BUDGET.MAX_CLOUDS} clouds at once`)
check(counter("Projectile.cloudsCapped") == 6, "the oldest end early, counted")
-- Tracers and effects on the client.
for i = 1, 100 do
	Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = 2, from = Vector3.new(0, 5, i), to = Vector3.new(30, 5, i) })
end
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
