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
-- A shot that hits a bot gasses it through BotService instead. Bots fire
-- the Gas Blaster through fireAsBot: the same cast, range, gas and
-- headshots, one shot per fire interval, only while a round is on. In the
-- practice yard (State PRACTICE) a shot passes the same checks and is cast
-- the same way, but only reaches the yard (PracticeHit): no gas to players
-- or bots, no stats, no funnel step, nothing lobbed.
--   CombatEvent { kind = "shot", shooter, from, to }                 all clients
--   CombatEvent { kind = "hit", victim, gas, headshot, blocked }     the shooter
--   CombatEvent { kind = "damaged", attacker, from }                 the victim
-- (player values are user IDs, a bot's its negative ID; positions Vector3s).
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
local Profiler = require(Server.Profiler)
local Cadence = require(Server.Cadence)
local MatchScoreService = require(script.Parent.MatchScoreService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)
local GasService = require(script.Parent.GasService)
local BotService = require(script.Parent.BotService)

local CombatService = {}

-- (shooter, part, weapon, from): every part a shot hits, so other services
-- (barrels) can react to it.
CombatService.PartHit = Signal.new()
-- (shooter, from, direction, weapon): a lobbed weapon fired.
CombatService.Lobbed = Signal.new()
-- (shooter, part, weapon, from, at): what a shot in the practice yard hit
-- (PracticeService: its dummies and barrel). Match shots never fire it.
CombatService.PracticeHit = Signal.new()

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
-- When each bot last fired.
local botShotAt: { [BotService.Bot]: number } = setmetatable({}, { __mode = "k" }) :: any
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

-- The gas a hit does `distance` studs from the shooter's head: full out to
-- the weapon's effective range, then less in a straight line down to its
-- minimum share at full range (WeaponConfig). A headshot loses the same
-- share, so it stays the better hit. Whole percents, never under 1.
function CombatService.gasAt(weapon: WeaponConfig.Weapon, distance: number, headshot: boolean): number
	local full = if headshot then weapon.headshotGas else weapon.gasPerHit
	local effective, minShare = weapon.effectiveRange, weapon.minGasShare
	if not (effective and minShare) or distance <= effective or weapon.range <= effective then
		return full
	end
	local past = math.min(1, (distance - effective) / (weapon.range - effective))
	return math.max(1, math.floor(full * (1 - (1 - minShare) * past) + 0.5))
end

-- A shot in the practice yard, after the usual checks: cast the same way,
-- the shooter shown where it went, and what it hit handed to the yard.
local function practiceShot(player: Player, character: Model, from: Vector3, unit: Vector3, weapon: WeaponConfig.Weapon)
	if weapon.projectile == "lob" then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(from, unit * weapon.range, params)
	local to = if result then result.Position else from + unit * weapon.range
	combatEvent():FireClient(player, { kind = "shot", shooter = player.UserId, from = from, to = to })
	if result then
		CombatService.PracticeHit:Fire(player, result.Instance, weapon, from, result.Position)
	end
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
	local state = PlayerLifecycleService.stateOf(player)
	if state ~= States.Player.ACTIVE and state ~= States.Player.PRACTICE then
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
	if state == States.Player.PRACTICE then
		practiceShot(player, character :: Model, head.Position, aim / length, weapon)
		return
	end
	checkMovement(player, entry, head.Position, at)
	entry.lastShotAt = at
	table.insert(entry.shots, at)

	PlayerLifecycleService.endProtection(player)
	AFKService.markActive(player)
	Telemetry.first(player, "shot")
	Telemetry.count("Combat.shots")
	-- Hit rates by the shooter's ping: is high ping still fair?
	local band = CombatService.pingBand(player)
	Telemetry.count(`Combat.shotsBy.{band}`)

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
	local bot = if victim then nil else BotService.fromInstance(result.Instance)
	if not (victim or bot) then
		return
	end
	local headshot = result.Instance.Name == "Head"
	local amount = CombatService.gasAt(weapon, (result.Position - from).Magnitude, headshot)
	local source: GasService.Source = { attacker = player, cause = "shot", weapon = weapon.id }
	local landed = if victim then GasService.add(victim, amount, source) else BotService.addGas(bot :: BotService.Bot, amount, source)
	if landed then
		table.insert(entry.hits, at)
		Telemetry.first(player, "hit")
		Telemetry.count("Combat.hits")
		Telemetry.count(`Combat.hitsBy.{band}`)
		if headshot then
			Telemetry.count("Combat.headshots")
		end
		if victim then
			combatEvent():FireClient(victim, { kind = "damaged", attacker = player.UserId, from = from })
		end
	end
	checkAccuracy(player, entry, at)
	combatEvent():FireClient(player, {
		kind = "hit",
		victim = if victim then victim.UserId else (bot :: BotService.Bot).id,
		gas = if victim then GasService.gasOf(victim) else BotService.gasOf(bot :: BotService.Bot),
		headshot = headshot,
		blocked = not landed,
	})
end

-- One Gas Blaster shot from `bot` toward `direction`, server-side: cast from
-- its head like a player's, the same range, gas (with its fall-off) and
-- headshots, gas through GasService (a player) or BotService (a bot), at
-- most one shot per fire interval. Only from a live bot that isn't
-- exploding, and only while a round is on (scores are open exactly then).
-- Firing ends its spawn protection. Returns whether a shot went out.
function CombatService.fireAsBot(bot: BotService.Bot, direction: Vector3): boolean
	if not FeatureFlags.GAS_COMBAT or typeof(direction) ~= "Vector3" or not (direction.Magnitude > 1e-3) then
		return false
	end
	if not MatchScoreService.isOpen() or not BotService.isAlive(bot) or BotService.isExploding(bot) then
		return false
	end
	local character = bot.character :: Model
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not (head and head:IsA("BasePart")) then
		return false
	end
	local weapon = WeaponConfig.weapons.GasBlaster
	local at = now()
	local last = botShotAt[bot]
	if last and at - last < weapon.fireInterval then
		return false
	end
	botShotAt[bot] = at
	BotService.endProtection(bot)
	Telemetry.count("Combat.botShots")

	local from = head.Position
	local unit = direction.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(from, unit * weapon.range, params)
	local to = if result then result.Position else from + unit * weapon.range
	combatEvent():FireAllClients({ kind = "shot", shooter = bot.id, from = from, to = to })
	if not result then
		return true
	end
	local headshot = result.Instance.Name == "Head"
	local amount = CombatService.gasAt(weapon, (result.Position - from).Magnitude, headshot)
	local source: GasService.Source = { team = bot.team, bot = bot.id, cause = "shot", weapon = weapon.id }
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local victim = model and Players:GetPlayerFromCharacter(model)
	if victim then
		if GasService.add(victim, amount, source) then
			combatEvent():FireClient(victim, { kind = "damaged", attacker = bot.id, from = from })
		end
		return true
	end
	local target = BotService.fromInstance(result.Instance)
	if target then
		BotService.addGas(target, amount, source)
	end
	return true
end

-- The player's network ping in seconds (nil if Roblox can't say).
-- Replaceable in tests.
CombatService.pingOf = function(player: Player): number?
	local ok, ping = pcall(player.GetNetworkPing, player)
	return if ok and type(ping) == "number" then ping else nil
end

-- "lowPing" (under 100 ms), "midPing" (under 200 ms), "highPing", or
-- "unknownPing".
function CombatService.pingBand(player: Player): string
	local ping = CombatService.pingOf(player)
	if not ping then
		return "unknownPing"
	end
	return if ping < 0.1 then "lowPing" elseif ping < 0.2 then "midPing" else "highPing"
end

function CombatService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireWeapon = remotes:WaitForChild("FireWeapon") :: RemoteEvent
	fireWeapon.OnServerEvent:Connect(Telemetry.guard("Combat", Profiler.wrap("Combat.fire", CombatService.fire)))
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
