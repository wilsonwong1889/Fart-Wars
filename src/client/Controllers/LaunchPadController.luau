-- Launch pads on the client (FeatureFlags.LAUNCH_PADS, LaunchPads,
-- LaunchPadConfig):
--   * stepping onto a pad launches your own avatar along the pad's arc to
--     its landing spot (Roblox avatars are client-driven, as with Fart
--     Dash): a kick up and a push holding your speed across the ground, so
--     you come down where the arc says; then you run on at walking speed.
--     One launch every COOLDOWN_SECONDS, ready again with each life; never
--     while exploding or off a team. The server hears of it (LaunchPad)
--     and checks it.
--   * every launch, yours and everyone else's (players' and bots'),
--     farts: the sound (yours flat, theirs from where it happened), a puff
--     of gas under the launcher and a green cloud left on the pad (only the
--     sound and one small puff with reduced effects), at most
--     MAX_EFFECT_PARTS parts at once.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local LaunchPadConfig = require(Shared.Config.LaunchPadConfig)
local LaunchPads = require(Shared.LaunchPads)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Audio = require(Client.Audio)
local EffectsController = require(script.Parent.EffectsController)

local CONFIG = LaunchPadConfig

local LaunchPadController = {}

export type Flight = { push: LinearVelocity, root: BasePart, startedAt: number, seconds: number }
-- Your flight under way (nil on the ground).
LaunchPadController.flight = nil :: Flight?
-- The puffs and clouds showing now, oldest first.
LaunchPadController.effects = {} :: { BasePart }

local player = Players.LocalPlayer
local lastLaunch = -math.huge
local knownMap: Instance? = nil
local knownPads: { Model } = {}
local started = false

local function clock(): number
	return os.clock()
end

-- The map's pads (looked up again when the map changes).
local function pads(): (Instance?, { Model })
	local map = workspace:FindFirstChild("Map")
	if map ~= knownMap or #knownPads == 0 then
		knownMap = map
		knownPads = LaunchPads.list(map)
	end
	return map, knownPads
end

-- A part for a puff or a cloud; past the budget the oldest goes.
local function effectPart(name: string): BasePart
	local list = LaunchPadController.effects
	for i = #list, 1, -1 do
		if not list[i].Parent then
			table.remove(list, i)
		end
	end
	while #list >= CONFIG.MAX_EFFECT_PARTS do
		table.remove(list, 1):Destroy()
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	table.insert(list, p)
	return p
end

-- A puff of gas bursting out under a launch at `feet`, blown back from
-- the way it throws.
function LaunchPadController.puff(feet: Vector3, direction: Vector3)
	local reduced = EffectsController.reduced()
	for i = 1, if reduced then 1 else 4 do
		local puff = effectPart("LaunchPuff")
		puff.Color = CONFIG.PUFF_COLOR
		puff.Transparency = 0.35
		puff.Size = Vector3.one * (2.5 + i * 0.7)
		puff.CFrame = CFrame.new(feet - direction * (i - 1) * 2 + Vector3.new(0, 0.6 + i * 0.4, 0))
		puff.Parent = workspace
		TweenService:Create(puff, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = puff.Size * 2.2,
		}):Play()
		Debris:AddItem(puff, 0.6)
	end
end

-- The green cloud a launch leaves hanging over the pad at `at`, rising
-- and fading (none with reduced effects).
function LaunchPadController.cloud(at: Vector3)
	if EffectsController.reduced() then
		return
	end
	for i = 1, 3 do
		local cloud = effectPart("LaunchCloud")
		local angle = i * math.pi * 2 / 3
		cloud.Color = CONFIG.CLOUD_COLOR
		cloud.Transparency = 0.5
		cloud.Size = Vector3.one * (6 + i * 1.5)
		cloud.CFrame = CFrame.new(at + Vector3.new(math.cos(angle) * 3, 2 + i, math.sin(angle) * 3))
		cloud.Parent = workspace
		TweenService:Create(cloud, TweenInfo.new(CONFIG.CLOUD_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = cloud.Size * 1.6,
			CFrame = cloud.CFrame + Vector3.new(0, 6, 0),
		}):Play()
		Debris:AddItem(cloud, CONFIG.CLOUD_SECONDS + 0.1)
	end
end

-- A launch's fart from `pad` (if this client knows it) by a root at
-- `from`: the sound, the puff and the cloud.
function LaunchPadController.fart(pad: Model?, from: Vector3, own: boolean)
	Audio.play("launch", if own then nil else from)
	local top = if pad then LaunchPads.cushion(pad) else from - Vector3.new(0, 3, 0)
	local direction = if pad then LaunchPads.direction(pad) else Vector3.zero
	LaunchPadController.puff(Vector3.new(from.X, top.Y, from.Z), direction)
	LaunchPadController.cloud(top)
end

-- Launches your avatar from `pad` and tells the server.
function LaunchPadController.launch(pad: Model, humanoid: Humanoid, root: BasePart)
	local arc = LaunchPads.arc(pad, root.Position, LaunchPads.lift(humanoid, root))
	local push = LaunchPads.throw(humanoid, root, arc)
	lastLaunch = clock()
	LaunchPadController.flight = { push = push, root = root, startedAt = lastLaunch, seconds = arc.seconds }
	ClientState.send("LaunchPad", pad.Name)
	LaunchPadController.fart(pad, root.Position, true)
end

-- Each frame: a flight ends once you're down (or should be); otherwise a
-- pad under you launches you.
function LaunchPadController.step()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local flight = LaunchPadController.flight
	if flight then
		local elapsed = clock() - flight.startedAt
		if flight.root ~= root or not flight.root.Parent or not humanoid or humanoid.Health <= 0 then
			LaunchPadController.flight = nil
			flight.push:Destroy()
		elseif (elapsed >= CONFIG.MIN_FLIGHT_SECONDS and humanoid.FloorMaterial ~= Enum.Material.Air)
			or elapsed >= flight.seconds + CONFIG.OVERRUN_SECONDS
		then
			LaunchPadController.flight = nil
			LaunchPads.land(flight.root, flight.push, GameConfig.WALK_SPEED)
		end
		return
	end
	if not (FeatureFlags.LAUNCH_PADS and character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return
	end
	if not ClientState.isActive() or character:GetAttribute("ExplodesAt") ~= nil or clock() - lastLaunch < CONFIG.COOLDOWN_SECONDS then
		return
	end
	local map, list = pads()
	local pad = LaunchPads.under(map, root.Position, CONFIG.TRIGGER_HEIGHT, list)
	if pad then
		LaunchPadController.launch(pad, humanoid, root)
	end
end

function LaunchPadController.start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function()
		LaunchPadController.step()
	end)
	-- A new life starts ready (the server's cooldown resets too).
	player.CharacterAdded:Connect(function()
		lastLaunch = -math.huge
	end)
	local combatEvent = ClientState.remote("CombatEvent") :: RemoteEvent
	combatEvent.OnClientEvent:Connect(function(event)
		if type(event) ~= "table" or event.kind ~= "launch" or event.player == player.UserId or typeof(event.from) ~= "Vector3" then
			return
		end
		local map = pads()
		LaunchPadController.fart(LaunchPads.find(map, event.pad), event.from, false)
	end)
end

return LaunchPadController
