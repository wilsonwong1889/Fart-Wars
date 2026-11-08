-- Gas Control's zone (Phase 6). While a round of a zone mode is on, every
-- ZONE.TICK_SECONDS it counts each team's players and bots standing in the
-- map's control zone (ACTIVE, alive, not mid-explosion; a round zone is
-- an upright cylinder, as MapKit.controlZone makes it, anything else a box).
--   * Taking it: a team alone in a zone it doesn't hold captures it over
--     ZONE.CAPTURE_SECONDS (quicker with more of them in it). An enemy in
--     it too freezes the capture; with nobody in it the capture runs back
--     down; once the other team has it to itself the capture starts over
--     as theirs.
--   * Holding it: the team that took it scores ZONE.POINTS every
--     ZONE.POINT_SECONDS while it has the zone to itself (which ends any
--     capture of the other team's). Contested or empty, nobody scores, but
--     it stays theirs until the other team takes it. Eliminations score
--     nothing; they clear the zone.
--   * Each player in it while their team scores earns a little (ZONE.COINS
--     and XP every REWARD_SECONDS of scoring, a few times a round); bots
--     earn nothing.
-- What clients see: Workspace's ZoneActive, ZoneOwner (the team holding
-- it, or nil), ZoneCapturing (the team taking it, or nil), ZoneProgress
-- (how far that capture is, 0 to 1), ZoneContested and Zone_<team> (how
-- many of each team are in it) attributes; the floor ring in the holder's
-- colour (white when contested, grey while nobody holds it); and a marker
-- high over the zone, seen from anywhere, in the same colour, with the
-- capture's bar under it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local MapBase = require(Shared.Interfaces.MapBase)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local Messages = require(Server.Messages)
local MapService = require(script.Parent.MapService)
local TeamService = require(script.Parent.TeamService)
local MatchScoreService = require(script.Parent.MatchScoreService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local GasService = require(script.Parent.GasService)
local BotService = require(script.Parent.BotService)
local EconomyService = require(script.Parent.EconomyService)
local RoundService = require(script.Parent.RoundService)

local ZONE = GameConfig.ZONE
local CONTESTED_COLOR = Color3.fromRGB(245, 242, 250)
local EMPTY_COLOR = Color3.fromRGB(150, 146, 160)
-- The marker floats this high over the zone's floor (clear of Brainrot
-- Battlefield's 45-stud throne) and is this many pixels across, whatever
-- the distance.
local MARKER_HEIGHT = 54
local MARKER_SIZE = Vector2.new(170, 46)
-- Spots for bots: at most this far out from the centre (of the way to the
-- edge), in a box an avatar fills. The throne's bounding boxes cover about
-- half of Porcelain Plaza's zone, so it takes two tries on average; after
-- SPOT_TRIES it takes any.
local SPOT_REACH = 0.85
local SPOT_BOX = Vector3.new(4, 5, 4)
local SPOT_TRIES = 24

local ZoneService = {}

-- (owner?, contested): fires when who holds the zone, or whether it's
-- contested, changes.
ZoneService.Changed = Signal.new()
-- (team): a team took the zone.
ZoneService.Captured = Signal.new()
-- (player, seconds): a player was in the zone while their team scored.
ZoneService.Held = Signal.new()

type Holder = { seconds: number, rewards: number }
local holders: { [Player]: Holder } = {}
local active = false
local owner: string? = nil
local capturing: string? = nil
local progress = 0
local contested = false
local pointClock = 0
local started = false

-- The current map's control zone and its floor ring, if it has them.
function ZoneService.parts(): (BasePart?, BasePart?)
	local model, entry = MapService.current()
	if not (model and entry and entry.zone) then
		return nil, nil
	end
	local zone = MapBase.resolve(model, entry.zone)
	local ring = entry.zoneRing and MapBase.resolve(model, entry.zoneRing)
	return if zone and zone:IsA("BasePart") then zone else nil, if ring and ring:IsA("BasePart") then ring else nil
end

-- A round zone: an upright cylinder, standing on its own X axis.
local function round(zone: BasePart): boolean
	return zone:IsA("Part") and (zone :: Part).Shape == Enum.PartType.Cylinder
end

-- How tall the zone is.
local function height(zone: BasePart): number
	return if round(zone) then zone.Size.X else zone.Size.Y
end

function ZoneService.inside(position: Vector3, zone: BasePart): boolean
	local localPoint = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	if round(zone) then
		local radius = math.min(half.Y, half.Z)
		return math.abs(localPoint.X) <= half.X and localPoint.Y * localPoint.Y + localPoint.Z * localPoint.Z <= radius * radius
	end
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- A point on the zone's floor, `a` and `b` (-1..1) of the way out from its
-- centre across it.
local function floorPoint(zone: BasePart, a: number, b: number): Vector3
	local half = zone.Size / 2
	if round(zone) then
		local radius = math.min(half.Y, half.Z)
		return zone.CFrame:PointToWorldSpace(Vector3.new(-half.X, a * radius, b * radius))
	end
	return zone.CFrame:PointToWorldSpace(Vector3.new(a * half.X, -half.Y, b * half.Z))
end

-- Somewhere for a bot to go in the zone: a random spot on its floor, away
-- from the edge, with nothing solid of the map's where an avatar would
-- stand (so never inside the throne). After a few tries it takes the last
-- spot anyway. Nil if the map has no zone.
function ZoneService.spot(rng: Random): Vector3?
	local zone = ZoneService.parts()
	local model = MapService.current()
	if not (zone and model) then
		return nil
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true
	local lift = Vector3.new(0, 1 + SPOT_BOX.Y / 2, 0)
	local point = floorPoint(zone, 0, 0)
	for _ = 1, SPOT_TRIES do
		local a, b
		if round(zone) then
			local out, turn = SPOT_REACH * math.sqrt(rng:NextNumber()), rng:NextNumber() * 2 * math.pi
			a, b = out * math.cos(turn), out * math.sin(turn)
		else
			a, b = rng:NextNumber(-SPOT_REACH, SPOT_REACH), rng:NextNumber(-SPOT_REACH, SPOT_REACH)
		end
		point = floorPoint(zone, a, b)
		if #workspace:GetPartBoundsInBox(CFrame.new(point + lift), SPOT_BOX, params) == 0 then
			return point
		end
	end
	return point
end

-- Whether a zone round is on right now.
function ZoneService.isActive(): boolean
	return active
end

-- Who holds it (nil if nobody has taken it yet this round), and whether
-- it's contested.
function ZoneService.state(): (string?, boolean)
	return owner, contested
end

-- The team taking it (nil if none) and how far that is, 0 to 1.
function ZoneService.capture(): (string?, number)
	return capturing, if capturing then progress else 0
end

-- The marker over the zone: its name in the ring's colour, seen through
-- everything from anywhere on the map, and a bar under it while a team is
-- taking the zone. Made the first time it's needed, so a map built in
-- Studio gets one too.
local function marker(zone: BasePart): BillboardGui
	local existing = zone:FindFirstChild("ZoneMarker")
	if existing and existing:IsA("BillboardGui") then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ZoneMarker"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(MARKER_SIZE.X, MARKER_SIZE.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, MARKER_HEIGHT - height(zone) / 2, 0)
	gui.Enabled = false
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 1, -12)
	name.Font = UIConfig.font
	name.Text = UIConfig.zone.marker
	name.TextScaled = true
	name.TextColor3 = EMPTY_COLOR
	name.TextStrokeColor3 = UIConfig.colors.stroke
	name.TextStrokeTransparency = 0
	name.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, 0)
	bar.Size = UDim2.new(0.8, 0, 0, 8)
	bar.BackgroundColor3 = UIConfig.colors.panel
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = bar
	gui.Parent = zone
	return gui
end

local function publish(counts: { [string]: number })
	workspace:SetAttribute("ZoneActive", active)
	workspace:SetAttribute("ZoneOwner", owner)
	workspace:SetAttribute("ZoneCapturing", capturing)
	workspace:SetAttribute("ZoneProgress", if capturing then math.floor(progress * 100 + 0.5) / 100 else 0)
	workspace:SetAttribute("ZoneContested", contested)
	for _, team in TeamConfig.order do
		workspace:SetAttribute(`Zone_{team}`, if active then counts[team] or 0 else nil)
	end
	local color = if contested then CONTESTED_COLOR elseif owner then TeamConfig.teams[owner].color else EMPTY_COLOR
	local zone, ring = ZoneService.parts()
	if ring then
		ring.Transparency = if active then 0.55 else 1
		ring.Color = color
	end
	if zone then
		local gui = marker(zone)
		gui.Enabled = active
		local name = gui:FindFirstChild("Name") :: TextLabel
		name.TextColor3 = color
		local bar = gui:FindFirstChild("Bar") :: Frame
		bar.Visible = active and capturing ~= nil and progress > 0
		if capturing then
			local fill = bar:FindFirstChild("Fill") :: Frame
			fill.BackgroundColor3 = TeamConfig.teams[capturing].color
			fill.Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
		end
	end
end

local function standing(player: Player, zone: BasePart): boolean
	if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE or GasService.isExploding(player) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart") and ZoneService.inside(root.Position, zone)
end

-- How much of a capture `n` players in the zone get through in a second.
local function rate(n: number): number
	local times = ZONE.CAPTURE_SECONDS
	return 1 / times[math.clamp(n, 1, #times)]
end

local function reset()
	owner, capturing, progress, contested, pointClock = nil, nil, 0, false, 0
end

-- A point for the holder: and a little for each player in the zone.
local function score(inZone: { Player })
	if not (owner and MatchScoreService.record({ team = owner, source = "zone" }, ZONE.POINTS)) then
		return
	end
	Telemetry.count("Zone.points", ZONE.POINTS)
	local roundId = RoundService.snapshot().roundId
	for _, player in inZone do
		local holder = holders[player] or { seconds = 0, rewards = 0 }
		holders[player] = holder
		holder.seconds += ZONE.POINT_SECONDS
		ZoneService.Held:Fire(player, ZONE.POINT_SECONDS)
		if holder.seconds >= ZONE.REWARD_SECONDS and holder.rewards < ZONE.REWARDS_PER_ROUND then
			holder.seconds -= ZONE.REWARD_SECONDS
			holder.rewards += 1
			EconomyService.grant(player, `zone:{roundId}:{holder.rewards}`, "zone", ZONE.COINS, ZONE.XP)
		end
	end
end

function ZoneService.tick(dt: number)
	local zone = ZoneService.parts()
	local nowActive = zone ~= nil and RoundService.phase() == States.Phase.ACTIVE
		and RoundService.getMode().objective == "zone" and MatchScoreService.isOpen()
	if not nowActive then
		if active then
			active = false
			reset()
			publish({})
			ZoneService.Changed:Fire(nil, false)
		end
		return
	end
	active = true
	local counts: { [string]: number } = {}
	local inZone: { Player } = {}
	for _, player in Players:GetPlayers() do
		local team = TeamService.teamOf(player)
		if team and standing(player, zone :: BasePart) then
			counts[team] = (counts[team] or 0) + 1
			table.insert(inZone, player)
		end
	end
	for _, bot in BotService.all() do
		local root = BotService.rootOf(bot)
		if root and not BotService.isExploding(bot) and ZoneService.inside(root.Position, zone :: BasePart) then
			counts[bot.team] = (counts[bot.team] or 0) + 1
		end
	end
	local present = {}
	for _, team in TeamConfig.order do
		if (counts[team] or 0) > 0 then
			table.insert(present, team)
		end
	end
	local wasOwner, wasContested = owner, contested
	contested = #present > 1
	local alone = if #present == 1 then present[1] else nil
	local scoring = false
	if alone and alone == owner then
		-- Holding it: it scores, and the other team's capture is over.
		scoring = true
		capturing, progress = nil, 0
	elseif alone then
		-- Taking it: the capture is theirs now (one of the other team's
		-- starts over), quicker the more of them are in it.
		if capturing ~= alone then
			capturing, progress = alone, 0
		end
		progress += dt * rate(counts[alone])
		if progress >= 1 - 1e-6 then
			owner, capturing, progress = alone, nil, 0
			Telemetry.count("Zone.captures")
			ZoneService.Captured:Fire(alone)
		end
	elseif #present == 0 and capturing then
		-- Nobody in it: the capture runs back down.
		progress -= dt * rate(1)
		if progress <= 0 then
			capturing, progress = nil, 0
		end
	end
	if owner ~= wasOwner or contested ~= wasContested then
		ZoneService.Changed:Fire(owner, contested)
	end
	if scoring then
		pointClock += dt
		while pointClock >= ZONE.POINT_SECONDS - 1e-6 do
			pointClock -= ZONE.POINT_SECONDS
			score(inZone)
		end
	else
		pointClock = 0
		if contested then
			Telemetry.count("Zone.contestedSeconds", dt)
		end
	end
	publish(counts)
end

function ZoneService.start()
	if started then
		return
	end
	started = true
	-- Each round starts with nobody holding the zone, and holding rewards
	-- count per round. A zone round says what to do as it starts.
	RoundService.PhaseChanged:Connect(function(phase)
		if phase ~= States.Phase.ACTIVE then
			return
		end
		table.clear(holders)
		reset()
		if RoundService.getMode().objective == "zone" and ZoneService.parts() then
			for _, player in Players:GetPlayers() do
				Messages.send(player, "mode", UIConfig.zone.start)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		holders[player] = nil
	end)
	publish({})
	Health.loop("Zone", ZONE.TICK_SECONDS, ZoneService.tick)
end

return ZoneService
