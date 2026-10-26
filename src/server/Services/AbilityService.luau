-- The Q ability, by its AbilityConfig entry. A player has at most one,
-- equipped through their loadout (LoadoutService sets it on spawn). The
-- client only asks (UseAbility, no payload); the server checks the state,
-- the equipped ability, exploding, protection and the cooldown, then does
-- it:
--   Recovery Burst  vents gas at once (refused with nothing to vent)
--   Gas Pulse       after a visible wind-up, a blast of gas onto enemies
--                   around the player (walls stop it; barrels in range go
--                   off); cancelled if the player dies or blows up first
-- The cooldown resets with each life. Clients see it as player attributes
-- "Ability" (the equipped id) and "AbilityReadyAt" (server time), and
-- everyone sees it used:
--   CombatEvent { kind = "ability", player, ability, position }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityConfig = require(Shared.Config.AbilityConfig)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Cadence = require(Server.Cadence)
local TeamService = require(script.Parent.TeamService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)
local GasService = require(script.Parent.GasService)
local ExplosionService = require(script.Parent.ExplosionService)

local AbilityService = {}

-- Network slack on the cooldown (see Cadence).
AbilityService.COOLDOWN_TOLERANCE_SECONDS = 0.5

local equipped: { [Player]: string } = {}
local cadences: { [Player]: Cadence.State } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function reject(player: Player, reason: string)
	Telemetry.reject("UseAbility", player, reason)
end

local function combatEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
end

-- Sets (or clears) the player's Q ability. LoadoutService checks they've
-- unlocked it.
function AbilityService.setAbility(player: Player, id: string?)
	local ability = id and AbilityConfig[id]
	if ability and ability.input == Enum.KeyCode.Q then
		equipped[player] = ability.id
		player:SetAttribute("Ability", ability.id)
	else
		equipped[player] = nil
		player:SetAttribute("Ability", nil)
	end
end

function AbilityService.abilityOf(player: Player): string?
	return equipped[player]
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function pulse(player: Player, ability: AbilityConfig.Ability, character: Model)
	task.wait(ability.durationSeconds)
	local root = rootOf(player)
	local team = TeamService.teamOf(player)
	if player.Character ~= character or not root or not team or GasService.isExploding(player) then
		Telemetry.count("Ability.pulseCancelled")
		return
	end
	ExplosionService.blast({
		position = root.Position,
		radius = ability.radius :: number,
		gas = ability.gas :: number,
		owner = player,
		ownerTeam = team,
		cause = "pulse",
		depth = 0,
		source = player,
	})
end

-- Q from `player`. Returns whether it went off.
function AbilityService.use(player: Player): boolean
	local id = equipped[player]
	local ability = id and AbilityConfig[id]
	if not ability then
		reject(player, "notEquipped")
		return false
	end
	if not table.find(ability.allowedStates, PlayerLifecycleService.stateOf(player) or "") then
		reject(player, "notActive")
		return false
	end
	local root = rootOf(player)
	if not root then
		reject(player, "dead")
		return false
	end
	if (ability.blockedWhileExploding and GasService.isExploding(player))
		or (not ability.allowedWhileProtected and PlayerLifecycleService.isProtected(player))
	then
		reject(player, "prohibited")
		return false
	end
	-- Before the cooldown, so a refusal here doesn't spend it.
	if ability.vent and GasService.gasOf(player) <= 0 then
		reject(player, "noGas")
		return false
	end
	local at = now()
	local cadence = cadences[player] or Cadence.new()
	cadences[player] = cadence
	if not Cadence.take(cadence, ability.cooldownSeconds, AbilityService.COOLDOWN_TOLERANCE_SECONDS, at) then
		reject(player, "cooldown")
		return false
	end
	player:SetAttribute("AbilityReadyAt", at + ability.cooldownSeconds)
	if ability.endsProtection then
		PlayerLifecycleService.endProtection(player)
	end
	AFKService.markActive(player)
	Telemetry.count(`Ability.{ability.id}`)
	combatEvent():FireAllClients({ kind = "ability", player = player.UserId, ability = ability.id, position = root.Position })
	if ability.vent then
		Telemetry.count("Ability.vented", GasService.vent(player, ability.vent))
	elseif ability.radius and ability.gas then
		task.spawn(pulse, player, ability, player.Character :: Model)
	end
	return true
end

function AbilityService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local useAbility = remotes:WaitForChild("UseAbility") :: RemoteEvent
	useAbility.OnServerEvent:Connect(Telemetry.guard("Ability", function(player)
		AbilityService.use(player)
	end))
	PlayerLifecycleService.Died:Connect(function(player)
		cadences[player] = nil
		player:SetAttribute("AbilityReadyAt", nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		equipped[player] = nil
		cadences[player] = nil
	end)
end

return AbilityService
