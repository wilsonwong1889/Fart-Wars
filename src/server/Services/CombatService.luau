-- Shooting, server-authoritative from end to end. A client only says
-- which way it's aiming and numbers its shots (FireWeapon). The server
-- checks the shooter (active, alive, not exploding, holding the weapon,
-- not firing faster than its interval, no repeated shot numbers), casts
-- the shot itself from the shooter's head, and only a hit it finds counts:
-- gas to an enemy (more for a headshot) through GasService, which handles
-- friendly fire, protection, explosions and credit. Firing ends your own
-- spawn protection. Too-accurate shooting and impossible movement between
-- shots are logged for review, not punished. Lobbed weapons (the Stink
-- Lobber) pass the same checks, then hand the throw to ProjectileService.
--   CombatEvent { kind = "shot", shooter, from, to }                 all clients
--   CombatEvent { kind = "hit", victim, gas, headshot, blocked }     the shooter
--   CombatEvent { kind = "damaged", attacker, from }                 the victim
-- (player values are user IDs, positions Vector3s).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Cadence = require(Server.Cadence)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)
local GasService = require(script.Parent.GasService)

local CombatService = {}

-- (shooter, part, weapon, from): every part a shot hits, so other services
-- (barrels) can react to it.
CombatService.PartHit = Signal.new()
-- (shooter, from, direction, weapon): a lobbed weapon fired.
CombatService.Lobbed = Signal.new()

type Shooter = {
	weapon: string,
	lastShotAt: number?,
	cadence: Cadence.State,
	lastShotId: number,
	lastHead: Vector3?,
	-- Shot and hit times in the last minute, for the accuracy check.
	shots: { number },
	hits: { number },
	flagged: boolean,
	movementFlagged: boolean,
}
local shooters: { [Player]: Shooter } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function combatEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
end

local function shooter(player: Player): Shooter
	local entry = shooters[player]
	if not entry then
		entry = {
			weapon = WeaponConfig.default,
			lastShotAt = nil,
			cadence = Cadence.new(),
			lastShotId = 0,
			lastHead = nil,
			shots = {},
			hits = {},
			flagged = false,
			movementFlagged = false,
		}
		shooters[player] = entry
	end
	return entry
end

function CombatService.weaponOf(player: Player): WeaponConfig.Weapon
	return WeaponConfig.weapons[shooter(player).weapon]
end

-- Equips a weapon (LoadoutService checks ownership; test controls don't).
function CombatService.setWeapon(player: Player, id: string): boolean
	if not WeaponConfig.weapons[id] then
		return false
	end
	shooter(player).weapon = id
	player:SetAttribute("Weapon", id)
	return true
end

local function reject(player: Player, reason: string)
	Telemetry.reject("FireWeapon", player, reason)
end

local function trim(times: { number }, at: number)
	while times[1] and at - times[1] > 60 do
		table.remove(times, 1)
	end
end

-- Logs (once) a player who hits nearly everything over many shots.
local function checkAccuracy(player: Player, entry: Shooter, at: number)
	trim(entry.shots, at)
	trim(entry.hits, at)
	local rule = GameConfig.SUSPICIOUS_ACCURACY
	if not entry.flagged and #entry.shots >= rule.SHOTS and #entry.hits / #entry.shots > rule.RATIO then
		entry.flagged = true
		Telemetry.count("Combat.suspiciousAccuracy")
		Telemetry.flag(player, "suspiciousAccuracy", `{#entry.hits}/{#entry.shots} hits in a minute`)
	end
end

-- Logs a shooter whose head moved further since the last shot than
-- running and dashing allow (a teleport, or a lagging client); the first
-- time in a session it's flagged for review.
local function checkMovement(player: Player, entry: Shooter, head: Vector3, at: number)
	if entry.lastHead and entry.lastShotAt then
		local dash = AbilityConfig.FartDash
		local allowed = (GameConfig.WALK_SPEED + (dash.speed :: number)) * (at - entry.lastShotAt) + 8
		if (head - entry.lastHead).Magnitude > allowed then
			local studs = math.floor((head - entry.lastHead).Magnitude)
			Telemetry.count("Combat.impossibleMovement")
			Telemetry.log("Combat", "impossibleMovement", { player = player, studs = studs })
			if not entry.movementFlagged then
				entry.movementFlagged = true
				Telemetry.flag(player, "impossibleMovement", `{studs} studs between shots`)
			end
		end
	end
	entry.lastHead = head
end

-- One shot from `player` toward `direction`; `shotId` counts up per shot.
function CombatService.fire(player: Player, direction: unknown, shotId: unknown)
	if not FeatureFlags.GAS_COMBAT then
		reject(player, "disabled")
		return
	end
	if typeof(direction) ~= "Vector3" or type(shotId) ~= "number" then
		reject(player, "badPayload")
		return
	end
	local aim = direction :: Vector3
	local length = aim.Magnitude
	local id = shotId :: number
	if length ~= length or length < 0.5 or length > 1.5 or id ~= id or id ~= math.floor(id) then
		reject(player, "badPayload")
		return
	end
	if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE then
		reject(player, "notActive")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not (humanoid and humanoid.Health > 0 and head and head:IsA("BasePart")) then
		reject(player, "dead")
		return
	end
	if GasService.isExploding(player) then
		reject(player, "exploding")
		return
	end
	local entry = shooter(player)
	if id <= entry.lastShotId then
		reject(player, "duplicate")
		return
	end
	local weapon = WeaponConfig.weapons[entry.weapon]
	local at = now()
	local slack = math.max(weapon.fireInterval * (1 - GameConfig.FIRE_INTERVAL_TOLERANCE), GameConfig.FIRE_SLACK_SECONDS)
	if not Cadence.take(entry.cadence, weapon.fireInterval, slack, at) then
		reject(player, "tooFast")
		return
	end
	entry.lastShotId = id
	checkMovement(player, entry, head.Position, at)
	entry.lastShotAt = at
	table.insert(entry.shots, at)

	PlayerLifecycleService.endProtection(player)
	AFKService.markActive(player)
	Telemetry.first(player, "shot")
	Telemetry.count("Combat.shots")

	local from = head.Position
	local unit = aim / length
	if weapon.projectile == "lob" then
		CombatService.Lobbed:Fire(player, from, unit, weapon)
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Model }
	local result = workspace:Raycast(from, unit * weapon.range, params)
	local to = if result then result.Position else from + unit * weapon.range
	combatEvent():FireAllClients({ kind = "shot", shooter = player.UserId, from = from, to = to })
	if not result then
		return
	end
	CombatService.PartHit:Fire(player, result.Instance, weapon, from)
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local victim = model and Players:GetPlayerFromCharacter(model)
	if not victim then
		return
	end
	local headshot = result.Instance.Name == "Head"
	local landed = GasService.add(victim, if headshot then weapon.headshotGas else weapon.gasPerHit, {
		attacker = player,
		cause = "shot",
		weapon = weapon.id,
	})
	if landed then
		table.insert(entry.hits, at)
		Telemetry.first(player, "hit")
		Telemetry.count("Combat.hits")
		if headshot then
			Telemetry.count("Combat.headshots")
		end
		combatEvent():FireClient(victim, { kind = "damaged", attacker = player.UserId, from = from })
	end
	checkAccuracy(player, entry, at)
	combatEvent():FireClient(player, {
		kind = "hit",
		victim = victim.UserId,
		gas = GasService.gasOf(victim),
		headshot = headshot,
		blocked = not landed,
	})
end

function CombatService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireWeapon = remotes:WaitForChild("FireWeapon") :: RemoteEvent
	fireWeapon.OnServerEvent:Connect(Telemetry.guard("Combat", CombatService.fire))
	PlayerLifecycleService.Spawned:Connect(function(player)
		local entry = shooter(player)
		entry.lastShotAt = nil
		entry.cadence = Cadence.new()
		entry.lastHead = nil
		player:SetAttribute("Weapon", entry.weapon)
	end)
	Players.PlayerRemoving:Connect(function(player)
		shooters[player] = nil
	end)
end

return CombatService
