-- Launch pads (FeatureFlags.LAUNCH_PADS; the pads and their arcs are
-- LaunchPads', the numbers LaunchPadConfig's). A player's client launches
-- its own avatar when it steps onto a pad, as Roblox avatars are
-- client-driven, and tells the server (LaunchPad, with the pad's name).
-- The server checks the player's state, that they aren't exploding, that
-- they're at that pad, and the cooldown (one launch every
-- COOLDOWN_SECONDS from any pad, ready again with each life); refused
-- launches are logged. A launch is movement, not an attack: it keeps
-- spawn protection, like Fart Dash.
-- Every launch it accepts is remembered for a minute, so the movement
-- checks (CombatService's between shots, DashService's after a dash) allow
-- for the flight and never flag it (LaunchPadService.allowance).
-- Bots are launched here, on the server that drives them: a live bot that
-- walks onto a pad heading its way (not one backing off against it) gets
-- the same kick and push a player's client gives itself, and a LandsAt
-- attribute so its brain plans again from where it comes down. Everyone
-- sees every launch:
--   CombatEvent { kind = "launch", player, pad, from, to, seconds }
-- (player a user ID, or a bot's negative ID; from and to where the root
-- left and comes down; seconds the flight).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local LaunchPadConfig = require(Shared.Config.LaunchPadConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local LaunchPads = require(Shared.LaunchPads)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Cadence = require(Server.Cadence)
local Health = require(Server.Health)
local MapService = require(script.Parent.MapService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local AFKService = require(script.Parent.AFKService)
local GasService = require(script.Parent.GasService)
local BotService = require(script.Parent.BotService)

local CONFIG = LaunchPadConfig
-- How long a flight is remembered after it lands.
local MEMORY_SECONDS = 60

local LaunchPadService = {}

-- (player?, bot?, pad, arc): a launch the server took (a player's) or made
-- (a bot's).
LaunchPadService.Launched = Signal.new()

type Flight = { at: number, seconds: number, length: number }
local flights: { [Player]: { Flight } } = {}
local cadences: { [Player]: Cadence.State } = {}
local botReadyAt: { [BotService.Bot]: number } = setmetatable({}, { __mode = "k" }) :: any
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function reject(player: Player, reason: string)
	Telemetry.reject("LaunchPad", player, reason)
end

local function announce(id: number, pad: Model, from: Vector3, arc: LaunchPads.Arc)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatEvent = remotes:WaitForChild("CombatEvent") :: RemoteEvent
	combatEvent:FireAllClients({ kind = "launch", player = id, pad = pad.Name, from = from, to = arc.to, seconds = arc.seconds })
end

local function remember(player: Player, arc: LaunchPads.Arc, at: number)
	local list = flights[player] or {}
	flights[player] = list
	while list[1] and at - (list[1].at + list[1].seconds) > MEMORY_SECONDS do
		table.remove(list, 1)
	end
	table.insert(list, { at = at, seconds = arc.seconds, length = LaunchPads.length(arc) + CONFIG.SLACK_STUDS })
end

-- How much further than running and dashing allow (studs) `player` may
-- have travelled between two server times, for the launches in between:
-- each flight's length, from GRACE_SECONDS before it set off to
-- GRACE_SECONDS after it came down. 0 with no launch.
function LaunchPadService.allowance(player: Player, from: number, to: number): number
	local extra = 0
	for _, flight in flights[player] or {} do
		if flight.at - CONFIG.GRACE_SECONDS <= to and flight.at + flight.seconds + CONFIG.GRACE_SECONDS >= from then
			extra += flight.length
		end
	end
	return extra
end

-- A player's client says it launched them from the pad named `padName`.
function LaunchPadService.launch(player: Player, padName: unknown): boolean
	if not FeatureFlags.LAUNCH_PADS then
		reject(player, "disabled")
		return false
	end
	local pad = LaunchPads.find(MapService.current(), padName)
	if not pad then
		reject(player, "badPayload")
		return false
	end
	if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE then
		reject(player, "notActive")
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		reject(player, "dead")
		return false
	end
	if GasService.isExploding(player) then
		reject(player, "prohibited")
		return false
	end
	if not LaunchPads.reaches(pad, root.Position, CONFIG.TRIGGER_HEIGHT, CONFIG.SLACK_STUDS, CONFIG.LAG_SECONDS) then
		reject(player, "tooFar")
		return false
	end
	local at = now()
	local cadence = cadences[player] or Cadence.new()
	cadences[player] = cadence
	local slack = math.max(CONFIG.COOLDOWN_SECONDS * (1 - GameConfig.FIRE_INTERVAL_TOLERANCE), GameConfig.FIRE_SLACK_SECONDS)
	if not Cadence.take(cadence, CONFIG.COOLDOWN_SECONDS, slack, at) then
		reject(player, "cooldown")
		return false
	end
	-- The flight as the client flies it, from the cushion it set off from.
	local top = LaunchPads.cushion(pad)
	local lift = LaunchPads.lift(humanoid, root)
	local arc = LaunchPads.arc(pad, top + Vector3.new(0, lift, 0), lift)
	remember(player, arc, at)
	AFKService.markActive(player)
	Telemetry.count("LaunchPads.launches")
	Telemetry.log("LaunchPads", "launch", { player = player, pad = pad.Name })
	announce(player.UserId, pad, root.Position, arc)
	LaunchPadService.Launched:Fire(player, nil, pad, arc)
	return true
end

-- Which way across the ground a bot is walking (zero standing still).
local function heading(humanoid: Humanoid, root: BasePart): Vector3
	local v = (root.AssemblyLinearVelocity :: Vector3?) or Vector3.zero
	local across = Vector3.new(v.X, 0, v.Z)
	if across.Magnitude < 2 then
		local move = (humanoid.MoveDirection :: Vector3?) or Vector3.zero
		across = Vector3.new(move.X, 0, move.Z)
	end
	return if across.Magnitude > 1e-3 then across.Unit else Vector3.zero
end

-- Throws `bot` from `pad`, as a player's client throws its own avatar
-- (the push is gone when the arc comes down), cooldown and all.
function LaunchPadService.launchBot(bot: BotService.Bot, pad: Model): boolean
	local root = BotService.rootOf(bot)
	local character = bot.character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (FeatureFlags.LAUNCH_PADS and root and character and humanoid) or BotService.isExploding(bot) then
		return false
	end
	local at = now()
	if (botReadyAt[bot] or -math.huge) > at then
		return false
	end
	botReadyAt[bot] = at + CONFIG.COOLDOWN_SECONDS
	local from = root.Position
	local arc = LaunchPads.arc(pad, from, LaunchPads.lift(humanoid, root))
	local push = LaunchPads.throw(humanoid, root, arc)
	task.delay(arc.seconds, function()
		if root.Parent then
			LaunchPads.land(root, push, GameConfig.WALK_SPEED)
		end
	end)
	character:SetAttribute("LandsAt", at + arc.seconds)
	Telemetry.count("LaunchPads.botLaunches")
	announce(bot.id, pad, from, arc)
	LaunchPadService.Launched:Fire(nil, bot, pad, arc)
	return true
end

-- Bots walking onto a pad their way take it.
function LaunchPadService.tick(_dt: number)
	local map = MapService.current()
	local pads = LaunchPads.list(map)
	if #pads == 0 then
		return
	end
	local at = now()
	for _, bot in BotService.all() do
		local root = BotService.rootOf(bot)
		local humanoid = root and bot.character and bot.character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and (botReadyAt[bot] or -math.huge) <= at then
			local pad = LaunchPads.under(map, root.Position, CONFIG.TRIGGER_HEIGHT, pads)
			if pad and heading(humanoid, root):Dot(LaunchPads.direction(pad)) >= CONFIG.BOT_ALIGNMENT then
				LaunchPadService.launchBot(bot, pad)
			end
		end
	end
end

function LaunchPadService.start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("LaunchPad") :: RemoteEvent
	remote.OnServerEvent:Connect(Telemetry.guard("LaunchPads", LaunchPadService.launch))
	PlayerLifecycleService.Died:Connect(function(player)
		cadences[player] = nil
	end)
	BotService.Spawned:Connect(function(bot)
		botReadyAt[bot] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		cadences[player] = nil
		flights[player] = nil
	end)
	if FeatureFlags.LAUNCH_PADS then
		Health.loop("LaunchPads", 0.1, LaunchPadService.tick)
	end
end

return LaunchPadService
