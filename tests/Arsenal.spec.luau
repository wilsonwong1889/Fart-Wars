-- The new weapons and the Q abilities (masterplan 3.3), through the real
-- remotes:
--   * Spritzer: small hits at a fast rate (never faster over time, however
--     the shots are timed; honest jitter passes), nothing past 60 studs
--   * Thunderclapper: heavy hits, a slow rate, and a slower walk
--   * Stink Lobber: the throw arcs and lands; the splash and the cloud gas
--     enemies (never teammates), the cloud stops when you step out and
--     fades on time, and its kills count toward its mastery
--   * Recovery Burst vents gas; refused with nothing to vent, on cooldown,
--     mid-countdown or unequipped; the cooldown resets with a new life
--   * Gas Pulse: after its wind-up, gas to enemies around (not teammates,
--     not out of reach); cancelled if the user blows up first; it ends spawn
--     protection
--   * the client: Q, the ability and weapon lines on the HUD, the arc and
--     the cloud on screen
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
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Combat = require(server.Services.CombatService)
local Abilities = require(server.Services.AbilityService)
local Projectiles = require(server.Services.ProjectileService)
local Loadout = require(server.Services.LoadoutService)
local Data = require(server.Services.DataService)
local Telemetry = require(server.Telemetry)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local Remotes = ReplicatedStorage.Remotes
local HttpService = game:GetService("HttpService")

-- Profiles in a stand-in store, so they load at once.
local saved = {}
Data.setStore({
	UpdateAsync = function(_, key, transform)
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})

local heard = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if player.Name == "Me" then
		table.insert(heard, event)
	end
end)
local function lastHeard(kind: string): any
	for i = #heard, 1, -1 do
		if heard[i].kind == kind then
			return heard[i]
		end
	end
	return nil
end
local function rejects(remote: string, reason: string): number
	local snapshot = Telemetry.snapshot()
	return snapshot.rejects[remote] and snapshot.rejects[remote][reason] or 0
end

-- The client is the shooter.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local CombatUI = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.CombatController)
local InputController = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController)
Lifecycle.requestPlay(me, nil)

local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = 700 + nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local mine = me:GetAttribute("TeamId")
local foe, mate
for _, name in { "A", "B", "C" } do
	local p = join(name)
	if p:GetAttribute("TeamId") ~= mine then
		foe = foe or p
	else
		mate = mate or p
	end
end
assert(foe and mate, "an enemy and a teammate")
local function place(player: Player, x: number, z: number)
	player.Character:PivotTo(CFrame.new(x, 3, z))
end
local function settle()
	task.wait(3.2)
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:PivotTo(p.Character:GetPivot() * CFrame.new(5, 0, 0))
		end
	end
	task.wait(3.1)
end
local shotId = 0
local function shoot(direction: Vector3)
	shotId += 1
	Remotes.FireWeapon.OnServerEvent:Fire(me, direction, shotId)
end
-- Down the Gas Gutter lane (x = 53), aimed at the body.
local function lineUp(distance: number): Vector3
	place(me, 53, -14)
	place(foe, 53, -14 + distance)
	place(mate, 30, -40)
	local head = me.Character.Head.Position
	return (foe.Character.HumanoidRootPart.Position - head).Unit
end
local function give(weapon: string)
	assert(Loadout.testGive(me, "weapon", weapon), "test give " .. weapon)
end
local function reset()
	for _, p in Players:GetPlayers() do
		Gas.reset(p)
	end
end
settle()

-- Spritzer.
give("Spritzer")
check(Combat.weaponOf(me).id == "Spritzer" and me:GetAttribute("Weapon") == "Spritzer", "the Spritzer in hand")
local aim = lineUp(30)
shoot(aim)
check(Gas.gasOf(foe) == WeaponConfig.weapons.Spritzer.gasPerHit, "a Spritzer hit: 7% gas")
task.wait(0.02)
shoot(aim)
check(rejects("FireWeapon", "tooFast") == 1 and Gas.gasOf(foe) == 7, "far faster than its 0.1 s interval: refused")
task.wait(0.1)
shoot(aim)
check(Gas.gasOf(foe) == 14, "a tenth of a second later: another hit")
-- Over time, no faster than its rate however the shots are timed (the
-- old per-gap tolerance let 0.085 s spacing through every time).
task.wait(1)
local refusedBefore = rejects("FireWeapon", "tooFast")
local up = Vector3.new(0, 1, 0) -- into the sky: only the rate matters here
for _ = 1, 30 do
	shoot(up)
	task.wait(0.085)
end
local refused = rejects("FireWeapon", "tooFast") - refusedBefore
check(refused >= 3, `30 shots at 0.085 s: the rate holds ({refused} refused)`)
-- Honest jitter: two shots bunched together after a steady rhythm pass.
task.wait(1)
refusedBefore = rejects("FireWeapon", "tooFast")
for _, gap in { 0.1, 0.1, 0.14, 0.06, 0.1 } do
	shoot(up)
	task.wait(gap)
end
check(rejects("FireWeapon", "tooFast") == refusedBefore, "a late shot followed by an early one (network jitter) isn't refused")
reset()
aim = lineUp(80)
task.wait(0.11)
shoot(aim)
check(Gas.gasOf(foe) == 0, "past 60 studs, nothing")
check(lastHeard("shot") and (lastHeard("shot").to - lastHeard("shot").from).Magnitude <= 60.5, "the spray stops at its range")

-- Thunderclapper.
give("Thunderclapper")
check(me.Character.Humanoid.WalkSpeed == 14, "heavy: a slower walk")
aim = lineUp(25)
task.wait(1.05)
shoot(aim)
check(Gas.gasOf(foe) == 40, "a Thunderclapper hit: 40% gas")
task.wait(0.5)
shoot(aim)
check(Gas.gasOf(foe) == 40, "half a second later: too soon")
task.wait(0.55)
shoot(aim)
check(Gas.gasOf(foe) == 80, "a second later: 80%")
reset()

-- Stink Lobber: find a throw that lands at the target.
give("StinkLobber")
check(me.Character.Humanoid.WalkSpeed == 15, "the Lobber's walk")
local lobber = WeaponConfig.weapons.StinkLobber
local function lobAt(target: Vector3): (Vector3, Vector3)
	local head = me.Character.Head.Position
	local flat = Vector3.new(target.X - head.X, 0, target.Z - head.Z).Unit
	local best, bestDirection, bestMiss = nil, nil, math.huge
	for degrees = -10, 60, 2 do
		local r = math.rad(degrees)
		local direction = (flat * math.cos(r) + Vector3.new(0, math.sin(r), 0)).Unit
		local landing = Projectiles.arc(head, direction, lobber, { me.Character })
		local miss = Vector3.new(landing.X - target.X, 0, landing.Z - target.Z).Magnitude
		if miss < bestMiss then
			best, bestDirection, bestMiss = landing, direction, miss
		end
	end
	return bestDirection, best
end
place(me, 53, -14)
place(foe, 53, 16)
place(mate, 55, 18) -- right beside the enemy
task.wait(1.5)
local direction, landing = lobAt(Vector3.new(53, 0, 16))
check((landing - Vector3.new(53, 0, 16)).Magnitude < 6, "a throw that lands by the target exists")
shoot(direction)
local lob = lastHeard("lob")
check(lob and lob.shooter == me.UserId and type(lob.path) == "table" and #lob.path >= 3 and lob.flight > 0.2, "the throw is sent with its arc")
check(Gas.gasOf(foe) == 0, "nothing until it lands")
task.wait(lob.flight + 0.15)
check(Gas.gasOf(foe) == lobber.gasPerHit, "the splash: 15%")
check(Gas.gasOf(mate) == 0, "a teammate in the splash takes none")
check(Projectiles.cloudCount() == 1 and lastHeard("cloud"), "a cloud is left behind")
task.wait(1.05)
local inCloud = Gas.gasOf(foe)
check(inCloud >= lobber.gasPerHit + 2 * (lobber.cloudGas :: number), "the cloud keeps gassing: " .. inCloud)
check(Gas.gasOf(mate) == 0, "but never a teammate")
place(foe, 53, 40)
task.wait(1)
check(Gas.gasOf(foe) == inCloud, "out of the cloud: no more")
task.wait(lobber.cloudSeconds :: number)
check(Projectiles.cloudCount() == 0, "the cloud fades on time")
-- A Lobber kill counts toward its mastery.
reset()
settle()
place(me, 53, -14)
place(foe, 53, 16)
Gas.add(foe, 95, { attacker = me, cause = "shot", weapon = "GasBlaster" })
task.wait(1.6)
direction = lobAt(foe.Character.HumanoidRootPart.Position - Vector3.new(0, 3, 0))
shoot(direction)
task.wait(lastHeard("lob").flight + 1.3)
local mastery = assert(Data.get(me)).data.WeaponMastery.StinkLobber
check(mastery and mastery.Eliminations == 1, "a stink bomb kill counts for the Lobber")
settle()

-- Recovery Burst.
give("GasBlaster")
check(not Abilities.use(me) and rejects("UseAbility", "notEquipped") == 1, "no ability equipped: refused")
assert(Loadout.testGive(me, "ability", "RecoveryBurst"))
check(me:GetAttribute("Ability") == "RecoveryBurst", "Recovery Burst on Q")
check(not Abilities.use(me) and rejects("UseAbility", "noGas") == 1, "nothing to vent: refused, no cooldown spent")
Gas.testSetGas(me, 60)
check(Abilities.use(me) and Gas.gasOf(me) == 25, "60% vented down to 25%")
check(lastHeard("ability") and lastHeard("ability").ability == "RecoveryBurst", "everyone sees the puff")
check(not Abilities.use(me) and rejects("UseAbility", "cooldown") == 1, "again at once: on cooldown")
check(math.abs((me:GetAttribute("AbilityReadyAt") :: number) - workspace:GetServerTimeNow() - 20) < 0.5, "ready again in 20 seconds")
task.wait(0.1)
local Hotbar = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.HotbarController)
Hotbar.renderAbility()
check(Hotbar.parts.abilityName.Text == "RECOVERY BURST" and string.find(Hotbar.parts.ability.Text, "^%d+s$") ~= nil, "the Q slot counts it down: " .. Hotbar.parts.ability.Text)
-- The cooldown resets with a new life; the countdown is too late.
Gas.testSetGas(me, 100)
task.wait(0.2)
check(not Abilities.use(me) and rejects("UseAbility", "prohibited") == 1, "mid-countdown: too late")
task.wait(1.2)
settle()
check(me:GetAttribute("AbilityReadyAt") == nil, "a new life, a fresh cooldown")
Hotbar.renderAbility()
check(Hotbar.parts.ability.Text == "READY", "and the Q slot says so")
Gas.testSetGas(me, 40)
InputController.AbilityPressed:Fire()
task.wait(0.1)
check(Gas.gasOf(me) == 5, "Q on the client vents it")

-- Gas Pulse.
-- One cooldown, whichever ability: swapping can't skip it.
assert(Loadout.testGive(me, "ability", "GasPulse"))
check(not Abilities.use(me) and rejects("UseAbility", "cooldown") == 2, "a fresh ability is still on the last one's cooldown")
task.wait(20)
settle()
place(me, 53, 0)
place(foe, 53, 8)
place(mate, 53, -8)
local far = join("Far")
if far:GetAttribute("TeamId") == mine then
	far = nil
end
task.wait(1.5)
if far then
	settle()
	place(me, 53, 0)
	place(foe, 53, 8)
	place(mate, 53, -8)
	place(far, 53, 30)
end
check(Lifecycle.isProtected(me) == false, "out of protection")
reset()
check(Abilities.use(me), "Gas Pulse")
check(Gas.gasOf(foe) == 0, "nothing during the wind-up")
task.wait(0.55)
check(Gas.gasOf(foe) == 15, "then 15% to the enemy within 12 studs")
check(Gas.gasOf(mate) == 0 and Gas.gasOf(me) == 0, "none to the teammate or the user")
if far then
	check(Gas.gasOf(far) == 0, "none to an enemy out of reach")
end
-- Cancelled if the user blows up first.
task.wait(Abilities.COOLDOWN_TOLERANCE_SECONDS + 25)
settle()
place(me, 53, 0)
place(foe, 53, 8)
reset()
check(Abilities.use(me), "another pulse")
Gas.add(me, 100, { attacker = foe, cause = "shot" })
task.wait(0.6)
check(Gas.gasOf(foe) == 0 and (Telemetry.snapshot().counters["Ability.pulseCancelled"] or 0) == 1, "the user blew up first: no pulse")
settle()
-- It ends spawn protection.
Lifecycle.respawn(me)
task.wait(0.2)
check(Lifecycle.isProtected(me), "freshly spawned: protected")
check(Abilities.use(me) and not Lifecycle.isProtected(me), "a pulse gives up the protection, like firing")

-- On the client.
check(CombatUI.parts.weapon.Text == "GAS BLASTER", "the weapon in hand on the HUD")
local arcs, clouds = 0, 0
give("StinkLobber")
settle()
place(me, 53, -14)
direction = lobAt(Vector3.new(53, 0, 10))
shoot(direction)
task.wait(0.05)
for _, child in workspace:GetChildren() do
	if child.Name == "LobArc" then
		arcs += 1
	end
end
check(arcs >= 2, "the arc is drawn")
task.wait(lastHeard("lob").flight + 0.2)
for _, child in workspace:GetChildren() do
	if child.Name == "StinkCloud" then
		clouds += 1
	end
end
check(clouds == 1, "and the cloud")

return { status = "PASS", checks = checks }
