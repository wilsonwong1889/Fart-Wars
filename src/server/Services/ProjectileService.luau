-- Lobbed weapons (the Stink Lobber). CombatService has already checked the
-- throw like any shot; here the server flies it: an arc from the head
-- along the aim, under the weapon's gravity, until it hits something or
-- has travelled its range. Where it lands, it splashes the thrower's
-- enemies (a blast through ExplosionService, so walls stop it and barrels
-- in range go off) and leaves a cloud that gasses enemies standing in it
-- every tick until it fades. Friendly fire stays off throughout, and the
-- gas is credited to the thrower and the weapon.
--   CombatEvent { kind = "lob", shooter, from, to, path, flight }    all clients
--   CombatEvent { kind = "cloud", position, radius, endsAt, team }  all clients
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local GasService = require(script.Parent.GasService)
local CombatService = require(script.Parent.CombatService)
local ExplosionService = require(script.Parent.ExplosionService)

local ProjectileService = {}

ProjectileService.STEP_SECONDS = 1 / 30
ProjectileService.MAX_FLIGHT_SECONDS = 3

type Cloud = {
	position: Vector3,
	radius: number,
	gas: number,
	owner: Player?,
	team: string,
	weapon: string,
	endsAt: number,
	nextTickAt: number,
	tick: number,
}
local clouds: { Cloud } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function combatEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
end

-- The arc from `from` along `direction`: where it lands, how long it
-- flies, and a few points along the way for the clients to draw.
function ProjectileService.arc(from: Vector3, direction: Vector3, weapon: WeaponConfig.Weapon, ignore: { Instance }): (Vector3, number, { Vector3 })
	local velocity = direction * (weapon.lobSpeed :: number)
	local gravity = Vector3.new(0, -(weapon.lobGravity :: number), 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local position, t = from, 0
	local path = { from }
	local dt = ProjectileService.STEP_SECONDS
	while t < ProjectileService.MAX_FLIGHT_SECONDS do
		local nextVelocity = velocity + gravity * dt
		local step = (velocity + nextVelocity) / 2 * dt
		local result = workspace:Raycast(position, step, params)
		if result then
			table.insert(path, result.Position)
			return result.Position, t + dt * (result.Position - position).Magnitude / math.max(step.Magnitude, 1e-3), path
		end
		position += step
		velocity = nextVelocity
		t += dt
		local flat = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
		if flat.Magnitude >= weapon.range then
			break
		end
		if #path < 12 and math.floor(t / dt) % 3 == 0 then
			table.insert(path, position)
		end
	end
	table.insert(path, position)
	return position, t, path
end

local function land(thrower: Player, team: string, at: Vector3, weapon: WeaponConfig.Weapon)
	Telemetry.count("Projectile.landed")
	ExplosionService.blast({
		position = at + Vector3.new(0, 1, 0),
		radius = weapon.splashRadius :: number,
		gas = weapon.gasPerHit,
		owner = if thrower.Parent == Players then thrower else nil,
		ownerTeam = team,
		cause = "lob",
		depth = 0,
		weapon = weapon.id,
	})
	local cloud: Cloud = {
		position = at + Vector3.new(0, 1, 0),
		radius = weapon.cloudRadius :: number,
		gas = weapon.cloudGas :: number,
		owner = thrower,
		team = team,
		weapon = weapon.id,
		endsAt = now() + (weapon.cloudSeconds :: number),
		nextTickAt = now() + (weapon.cloudTickSeconds :: number),
		tick = weapon.cloudTickSeconds :: number,
	}
	table.insert(clouds, cloud)
	combatEvent():FireAllClients({ kind = "cloud", position = cloud.position, radius = cloud.radius, endsAt = cloud.endsAt, team = team })
end

-- Throws `weapon` from `from` toward `direction` for `thrower`.
function ProjectileService.throw(thrower: Player, from: Vector3, direction: Vector3, weapon: WeaponConfig.Weapon)
	local team = TeamService.teamOf(thrower)
	if not team or weapon.projectile ~= "lob" then
		return
	end
	local ignore: { Instance } = {}
	if thrower.Character then
		table.insert(ignore, thrower.Character)
	end
	local to, flight, path = ProjectileService.arc(from, direction, weapon, ignore)
	Telemetry.count("Projectile.thrown")
	combatEvent():FireAllClients({ kind = "lob", shooter = thrower.UserId, from = from, to = to, path = path, flight = flight })
	task.delay(flight, land, thrower, team, to, weapon)
end

-- Clouds gas the enemies inside them, a tick at a time.
function ProjectileService.step()
	local at = now()
	for i = #clouds, 1, -1 do
		local cloud = clouds[i]
		if at >= cloud.endsAt then
			table.remove(clouds, i)
		elseif at >= cloud.nextTickAt then
			cloud.nextTickAt += cloud.tick
			local owner = if cloud.owner and cloud.owner.Parent == Players then cloud.owner else nil
			for _, player in Players:GetPlayers() do
				local team = TeamService.teamOf(player)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if team and team ~= cloud.team
					and PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE
					and root and root:IsA("BasePart")
					and (root.Position - cloud.position).Magnitude <= cloud.radius
					and not ExplosionService.blocked(cloud.position, root.Position)
				then
					GasService.add(player, cloud.gas, { attacker = owner, team = cloud.team, cause = "cloud", weapon = cloud.weapon })
				end
			end
		end
	end
end

function ProjectileService.cloudCount(): number
	return #clouds
end

function ProjectileService.start()
	if started then
		return
	end
	started = true
	CombatService.Lobbed:Connect(ProjectileService.throw)
	task.spawn(function()
		while true do
			task.wait(0.1)
			ProjectileService.step()
		end
	end)
end

return ProjectileService
