-- Live events (EventConfig; masterplan 6.3), behind FeatureFlags.EVENTS.
-- Bean Rain: when a round starts, it may be booked (CHANCE_PER_ROUND) for
-- a random moment in the round. WARNING_SECONDS before, Workspace's
-- EventPhase turns "warning" (the HUD's banner); then for
-- DURATION_SECONDS beans come down over the lanes, each first shown as a
-- ring where it will land. Standing on a bean picks it up: a few coins
-- (MAX_PER_PLAYER per event) and the Fart Dash ready again. A round's end
-- clears it all. Workspace attributes: Event (the event's ID), EventPhase
-- ("warning" / "active"), EventStartsAt, EventEndsAt (server time).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local EventConfig = require(Shared.Config.EventConfig)
local MapArt = require(Shared.Config.MapArt)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local MapDressing = require(Shared.MapDressing)
local MapService = require(script.Parent.MapService)
local RoundService = require(script.Parent.RoundService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local EconomyService = require(script.Parent.EconomyService)
local DashService = require(script.Parent.DashService)

local RAIN = EventConfig.BEAN_RAIN
local TICK_SECONDS = 0.25

local EventService = {}

type Bean = { part: BasePart, landsAt: number, goneAt: number, landed: boolean }
type Running = { id: number, warnAt: number, startsAt: number, endsAt: number, beans: { Bean }, owed: number, picked: { [Player]: number } }

local running: Running? = nil
local count = 0
local folder: Folder? = nil
local rng = Random.new()
local override: boolean? = nil
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function enabled(): boolean
	if override ~= nil then
		return override
	end
	return FeatureFlags.EVENTS
end

-- Test seams: on or off whatever the flag says, and the dice.
function EventService.testEnable(on: boolean?)
	override = on
end
function EventService.setRandom(random: Random)
	rng = random
end

local function events(): Folder
	if not (folder and folder.Parent) then
		local f = Instance.new("Folder")
		f.Name = "Events"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function publish()
	local event = running
	workspace:SetAttribute("Event", if event then RAIN.id else nil)
	workspace:SetAttribute("EventPhase", if not event then nil elseif now() < event.startsAt then "warning" else "active")
	workspace:SetAttribute("EventStartsAt", if event then event.startsAt else nil)
	workspace:SetAttribute("EventEndsAt", if event then event.endsAt else nil)
end

-- Clears the current event and its parts.
function EventService.stop()
	if running then
		for _, bean in running.beans do
			bean.part:Destroy()
		end
	end
	running = nil
	publish()
end

-- Books Bean Rain to start at `at` (server time; now if nil).
function EventService.book(at: number?)
	EventService.stop()
	count += 1
	local startsAt = at or now()
	running = {
		id = count,
		warnAt = startsAt - RAIN.WARNING_SECONDS,
		startsAt = startsAt,
		endsAt = startsAt + RAIN.DURATION_SECONDS,
		beans = {},
		owed = 0,
		picked = {},
	}
	Telemetry.count("Event.booked")
	publish()
end

-- The event on now, if any: its phase ("booked", "warning", "active").
function EventService.phase(): string?
	local event = running
	if not event then
		return nil
	end
	local at = now()
	return if at < event.warnAt then "booked" elseif at < event.startsAt then "warning" else "active"
end

function EventService.beans(): { Bean }
	return if running then running.beans else {}
end

-- A random spot on the lanes, not in a spawn room (nil if the map has no
-- lanes marked).
function EventService.spot(): Vector3?
	local model = MapService.current()
	local zones = model and model:FindFirstChild("Zones")
	if not zones then
		return nil
	end
	local lanes, spawns = {}, {}
	for _, zone in zones:GetChildren() do
		if zone:IsA("BasePart") then
			if string.sub(zone.Name, 1, 4) == "Lane" then
				table.insert(lanes, zone)
			elseif zone.Name == "SpawnZone" then
				table.insert(spawns, zone)
			end
		end
	end
	if #lanes == 0 then
		return nil
	end
	for _ = 1, 10 do
		local lane = lanes[rng:NextInteger(1, #lanes)]
		local half = lane.Size / 2 - Vector3.new(3, 0, 3)
		local point = lane.CFrame:PointToWorldSpace(Vector3.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z)))
		local blocked = false
		for _, room in spawns do
			local localPoint = room.CFrame:PointToObjectSpace(point)
			if math.abs(localPoint.X) <= room.Size.X / 2 + 4 and math.abs(localPoint.Z) <= room.Size.Z / 2 + 4 then
				blocked = true
			end
		end
		if not blocked then
			return Vector3.new(point.X, 0, point.Z)
		end
	end
	return nil
end

-- `prop`: the Blender prop to use instead of a plain part, when imported.
local function makePart(name: string, size: Vector3, frame: CFrame, color: Color3, transparency: number, shape: Enum.PartType, prop: string?): BasePart
	local mesh = if prop then MapDressing.copy(prop) else nil
	local part: BasePart = mesh or Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if not mesh then
		(part :: Part).Shape = shape
	end
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = frame
	part.Parent = events()
	return part
end

local function drop(event: Running)
	if #event.beans >= RAIN.MAX_BEANS then
		Telemetry.count("Event.beansCapped")
		return
	end
	local spot = EventService.spot()
	if not spot then
		return
	end
	-- The ring first: where it will land.
	local ring = makePart("BeanMarker", Vector3.new(0.2, 7, 7), CFrame.new(spot + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 200, 80), 0.4, Enum.PartType.Cylinder)
	local at = now()
	table.insert(event.beans, { part = ring, landsAt = at + RAIN.TELEGRAPH_SECONDS, goneAt = at + RAIN.TELEGRAPH_SECONDS + RAIN.BEAN_SECONDS, landed = false })
end

local function land(bean: Bean)
	local position = bean.part.Position
	bean.part:Destroy()
	bean.part = makePart("Bean", Vector3.new(2.4, 1.6, 1.6), CFrame.new(position.X, 1.2, position.Z), Color3.fromRGB(196, 92, 40), 0, Enum.PartType.Ball, MapArt.BEAN)
	bean.landed = true
end

local function pickUp(event: Running, bean: Bean, player: Player)
	local picked = (event.picked[player] or 0) + 1
	event.picked[player] = picked
	bean.goneAt = 0
	Telemetry.count("Event.beansPicked")
	if picked <= RAIN.MAX_PER_PLAYER then
		EconomyService.grant(player, `bean:{event.id}:{picked}`, "event", RAIN.COINS, 0)
	end
	DashService.refill(player)
end

function EventService.tick(dt: number)
	local event = running
	if not event then
		return
	end
	if not enabled() or RoundService.phase() ~= States.Phase.ACTIVE then
		EventService.stop()
		return
	end
	local at = now()
	if at >= event.endsAt and #event.beans == 0 then
		Telemetry.count("Event.finished")
		EventService.stop()
		return
	end
	publish()
	if at >= event.startsAt and at < event.endsAt then
		event.owed += dt * RAIN.BEANS_PER_SECOND
		while event.owed >= 1 do
			event.owed -= 1
			drop(event)
		end
	end
	for i = #event.beans, 1, -1 do
		local bean = event.beans[i]
		if not bean.landed and at >= bean.landsAt then
			land(bean)
		end
		if bean.landed and bean.goneAt > 0 then
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE
					and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(bean.part.Position.X, 0, bean.part.Position.Z)).Magnitude <= RAIN.PICKUP_RADIUS
				then
					pickUp(event, bean, player)
					break
				end
			end
		end
		if at >= bean.goneAt then
			bean.part:Destroy()
			table.remove(event.beans, i)
		end
	end
end

function EventService.start()
	if started then
		return
	end
	started = true
	RoundService.PhaseChanged:Connect(function(phase, snapshot)
		if phase ~= States.Phase.ACTIVE then
			EventService.stop()
			return
		end
		if enabled() and snapshot.phaseEndTime and rng:NextNumber() < EventConfig.CHANCE_PER_ROUND then
			local latest = math.min(EventConfig.LATEST_SECONDS, snapshot.phaseEndTime - snapshot.phaseStartTime - RAIN.DURATION_SECONDS)
			if latest > EventConfig.EARLIEST_SECONDS then
				EventService.book(snapshot.phaseStartTime + rng:NextNumber(EventConfig.EARLIEST_SECONDS, latest))
			end
		end
	end)
	Health.loop("Events", TICK_SECONDS, EventService.tick)
end

return EventService
