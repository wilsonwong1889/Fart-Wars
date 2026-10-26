-- The Phase 1 placeholder attack, server-authoritative from end to end. A
-- client only says which way it's aiming (FireWeapon); the server checks
-- the shooter (active, alive, holding the weapon, not firing faster than
-- its interval), casts the shot itself from the shooter's head, and only a
-- hit it finds counts. Enemies only: friendly fire is off on every path,
-- and a protected (just spawned) player takes nothing. A killing blow is
-- an elimination for the shooter's team, once per life.
-- Damage comes off Roblox health for now; Phase 2's gas meter replaces it.
-- Everyone hears about shots, hits and eliminations through CombatEvent:
--   { kind = "shot", shooter, from, to }            all clients (tracers)
--   { kind = "hit", victim, health, blocked? }      the shooter
--   { kind = "damaged", attacker, from }            the victim
--   { kind = "elimination", killer, victim, team }  all clients
-- (player values are user IDs, positions Vector3s).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local MatchScoreService = require(script.Parent.MatchScoreService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)

local CombatService = {}

-- (victim, killer): an elimination that counted.
CombatService.Eliminated = Signal.new()

type Combatant = { weapon: string, lastShotAt: number?, streak: number, bestStreak: number }
local combatants: { [Player]: Combatant } = {}
-- Characters already eliminated, so one death is never two kills.
local eliminated: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function combatEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
end

local function combatant(player: Player): Combatant
	local entry = combatants[player]
	if not entry then
		entry = { weapon = WeaponConfig.default, lastShotAt = nil, streak = 0, bestStreak = 0 }
		combatants[player] = entry
	end
	return entry
end

function CombatService.weaponOf(player: Player): WeaponConfig.Weapon
	return WeaponConfig.weapons[combatant(player).weapon]
end

function CombatService.streakOf(player: Player): number
	return combatant(player).streak
end

-- Equips a weapon the player may use (test controls; Phase 3 inventory).
function CombatService.setWeapon(player: Player, id: string): boolean
	if not WeaponConfig.weapons[id] then
		return false
	end
	combatant(player).weapon = id
	player:SetAttribute("Weapon", id)
	return true
end

local function aliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function eliminate(victim: Player, killer: Player, character: Model)
	if eliminated[character] then
		return
	end
	eliminated[character] = true
	local team = TeamService.teamOf(killer)
	local counted = team ~= nil
		and MatchScoreService.recordElimination({ team = team, source = "elimination", killer = killer, victim = victim })
	local entry = combatant(killer)
	entry.streak += 1
	entry.bestStreak = math.max(entry.bestStreak, entry.streak)
	Telemetry.first(killer, "elimination")
	Telemetry.log("Combat", "elimination", { killer = killer, victim = victim, counted = counted, streak = entry.streak })
	combatEvent():FireAllClients({ kind = "elimination", killer = killer.UserId, victim = victim.UserId, team = team })
	CombatService.Eliminated:Fire(victim, killer)
end

-- Damage from `attacker` to `victim`, on the server's say-so only. Returns
-- whether any landed.
function CombatService.damage(victim: Player, attacker: Player, amount: number): boolean
	local victimTeam, attackerTeam = TeamService.teamOf(victim), TeamService.teamOf(attacker)
	if victim == attacker or not victimTeam or victimTeam == attackerTeam then
		return false -- friendly fire is off
	end
	if PlayerLifecycleService.isProtected(victim) then
		return false
	end
	local humanoid = aliveHumanoid(victim)
	local character = victim.Character
	if not (humanoid and character) or eliminated[character] then
		return false
	end
	humanoid.Health = math.max(0, humanoid.Health - amount)
	if humanoid.Health <= 0 then
		eliminate(victim, attacker, character)
	end
	return true
end

local function reject(player: Player, reason: string)
	Telemetry.reject("FireWeapon", player, reason)
end

-- One shot from `player` toward `direction`.
function CombatService.fire(player: Player, direction: unknown)
	if not FeatureFlags.PLACEHOLDER_BLASTER then
		reject(player, "disabled")
		return
	end
	if typeof(direction) ~= "Vector3" then
		reject(player, "badPayload")
		return
	end
	local aim = direction :: Vector3
	local length = aim.Magnitude
	if length ~= length or length < 0.5 or length > 1.5 then -- NaN, or not a unit vector
		reject(player, "badPayload")
		return
	end
	if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE then
		reject(player, "notActive")
		return
	end
	local humanoid = aliveHumanoid(player)
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not (humanoid and character and head and head:IsA("BasePart")) then
		reject(player, "dead")
		return
	end
	local entry = combatant(player)
	local weapon = WeaponConfig.weapons[entry.weapon]
	local at = now()
	if entry.lastShotAt and at - entry.lastShotAt < weapon.fireInterval * GameConfig.FIRE_INTERVAL_TOLERANCE then
		reject(player, "tooFast")
		return
	end
	entry.lastShotAt = at

	PlayerLifecycleService.endProtection(player)
	AFKService.markActive(player)
	Telemetry.first(player, "shot")
	Telemetry.count("Combat.shots")

	local from = head.Position
	local unit = aim / length
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(from, unit * weapon.range, params)
	local to = if result then result.Position else from + unit * weapon.range
	combatEvent():FireAllClients({ kind = "shot", shooter = player.UserId, from = from, to = to })
	if not result then
		return
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local victim = model and Players:GetPlayerFromCharacter(model)
	if not victim then
		return
	end
	local landed = CombatService.damage(victim, player, weapon.damage)
	local victimHumanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if landed then
		Telemetry.first(player, "hit")
		Telemetry.count("Combat.hits")
		combatEvent():FireClient(victim, { kind = "damaged", attacker = player.UserId, from = from })
	end
	combatEvent():FireClient(player, {
		kind = "hit",
		victim = victim.UserId,
		health = if victimHumanoid then victimHumanoid.Health else 0,
		blocked = not landed,
	})
end

-- Test-only: full health again (Phase 2: an empty gas meter).
function CombatService.reset(player: Player)
	local humanoid = aliveHumanoid(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
end

function CombatService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireWeapon = remotes:WaitForChild("FireWeapon") :: RemoteEvent
	fireWeapon.OnServerEvent:Connect(Telemetry.guard("Combat", CombatService.fire))
	-- A death ends the streak; the respawn starts the next life clean.
	PlayerLifecycleService.Died:Connect(function(player)
		local entry = combatants[player]
		if entry then
			entry.streak = 0
			entry.lastShotAt = nil
		end
	end)
	PlayerLifecycleService.Spawned:Connect(function(player)
		player:SetAttribute("Weapon", combatant(player).weapon)
	end)
	Players.PlayerRemoving:Connect(function(player)
		combatants[player] = nil
	end)
end

return CombatService
