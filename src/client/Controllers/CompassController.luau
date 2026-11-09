-- Finding the fight and your team on a big map (FeatureFlags.COMPASS),
-- while you're in a match with an avatar:
--   * the compass strip at the top of the screen: the directions, and the
--     lanes and the plaza by the names on their gates' signs, each at the
--     middle of its two gates (a name leaves the strip while you're there;
--     when two would overlap, the nearer shows); your team's pings on it,
--     or at its end when they're off it
--   * a marker over each teammate (and bot on your team) too far away for
--     the symbol over their head (CompassConfig.markers.minDistance): the
--     team's symbol (▲ ●; a plain ◆ with team symbols off), so it never
--     relies on colour. A teammate in a fight (they fired or took gas in
--     the last few seconds) or blowing up (counting down to explode) says
--     so, and while they're off the screen an arrow near its edge points
--     at them, the ones blowing up first
--   * Z or the middle mouse button: a ping on the spot under the crosshair
--     (the ground if the crosshair is on nothing nearer), sent to the
--     server, which tells your team (CompassConfig.ping); a ping shows its
--     pin, who sent it and how far away it is for a few seconds, with a
--     sound, and each player's new ping moves their old one
-- Reduce motion keeps it still (no pulse, pop or fade); the HUD size
-- scales the strip, the markers and the arrows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CompassConfig = require(Shared.Config.CompassConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local Audio = require(Client.Audio)
local ClientState = require(Client.ClientState)
local Combatants = require(Client.Combatants)
local Compass = require(Client.Compass)
local Settings = require(Client.Settings)
local ShotFeed = require(Client.ShotFeed)
local UI = require(Client.UI)
local InputController = require(script.Parent.InputController)

local C = UIConfig.colors
local STRIP = CompassConfig.strip
local MARKERS = CompassConfig.markers
local PING = CompassConfig.ping
local WORDS = CompassConfig.words
-- The strip's rows: the letters, and under them the names and pings.
local LETTER_Y = 3
local ROW_Y = 20
local NAME_SIZE = 12
-- How far over a teammate's head their marker sits.
local OVER_HEAD = Vector3.new(0, 2.5, 0)

local CompassController = {}

-- The pieces, for tests: the screen, the strip, and the pools of markers
-- (`mates`), arrows, ping markers (`pins`), the strip's pings (`pips`) and
-- landmark names (`names`, in CompassController.landmarks' order).
CompassController.parts = {} :: { [string]: any }

export type Landmark = { name: string, position: Vector3, color: Color3 }
-- The names on the strip, read from the map in Workspace.
CompassController.landmarks = {} :: { Landmark }

export type Ping = { from: number, position: Vector3, endsAt: number, arrivedAt: number }
-- Your team's pings now, one per pinger (by user ID).
CompassController.pings = {} :: { [number]: Ping }

-- What the last frame showed, for tests: the teammates with a marker, the
-- ones with an arrow (in order, with why), and the pingers whose pins were
-- on the screen.
CompassController.shown = {
	mates = {} :: { Model },
	arrows = {} :: { { character: Model, trouble: string } },
	pins = {} :: { number },
}

local player = Players.LocalPlayer
local started = false
local lastPing = -math.huge
-- The directions' letters and ticks on the strip, at their bearings.
local fixed: { { gui: GuiObject, bearing: number, y: number } } = {}
-- When each avatar last fired or took gas (a new life starts afresh).
local fightAt: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- The map the landmarks were read from, how many gate parts it had, and
-- when it was last looked at.
local landmarksMap: Instance? = nil
local landmarkParts = -1
local landmarksCheckedAt = -math.huge

local function clock(): number
	return os.clock()
end

local function pooled(list: { GuiObject }, index: number, make: () -> GuiObject): any
	local item = list[index]
	if not item then
		item = make()
		list[index] = item
	end
	return item
end

local function hideFrom(list: { GuiObject }, first: number)
	for i = first, #list do
		list[i].Visible = false
	end
end

-- A team's symbol, or the plain pip with team symbols off.
local function symbolOf(team: string): string
	local config = TeamConfig.teams[team]
	return if config and Settings.teamSymbols then config.symbol else WORDS.pip
end

local function alertOf(trouble: string?): string
	return if trouble == "boom" then ` {WORDS.boom}` elseif trouble == "fight" then ` {WORDS.fight}` else ""
end

local function textWidth(text: string, size: number): number
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, UIConfig.font, Vector2.new(1000, 100))
	return (if ok then bounds.X else #text * size * 0.6) + 8
end

local function build()
	local p = CompassController.parts
	local screen = UI.screen("Compass", 3)
	screen.Enabled = false
	p.screen = screen
	local strip = UI.new("Frame", {
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, STRIP.top),
		Size = UDim2.new(0, STRIP.width, 0, STRIP.height),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.3,
		ClipsDescendants = true,
		Parent = screen,
	}, { UI.corner(8), UI.stroke(C.stroke, 2) })
	p.strip = strip
	-- Ticks between the letters.
	for bearing = 0, 359, STRIP.tickDegrees do
		if bearing % 45 ~= 0 then
			local tick = UI.new("Frame", {
				Name = "Tick",
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.new(0, 2, 0, 6),
				BackgroundColor3 = C.muted,
				BorderSizePixel = 0,
				Parent = strip,
			})
			table.insert(fixed, { gui = tick, bearing = bearing, y = 0 })
		end
	end
	for i, letter in Compass.LETTERS do
		local cardinal = i % 2 == 1
		local label = UI.label(letter, if cardinal then 16 else 12, {
			Name = letter,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(0, 30, 0, 16),
			TextColor3 = if letter == "N" then C.accent elseif cardinal then C.text else C.muted,
			ZIndex = 2,
			Parent = strip,
		})
		table.insert(fixed, { gui = label, bearing = (i - 1) * 45, y = LETTER_Y })
	end
	-- Where you're facing: a notch at the middle of the strip's top and bottom.
	for _, y in { 0, STRIP.height - 5 } do
		UI.new("Frame", {
			Name = "Notch",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.new(0, 3, 0, 5),
			BackgroundColor3 = C.accent,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = strip,
		})
	end
	p.names = {}
	p.pips = {}
	p.mates = {}
	p.arrows = {}
	p.pins = {}
end

local function newName(): TextLabel
	return UI.label("", NAME_SIZE, {
		Name = "Landmark",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 80, 0, 15),
		ZIndex = 2,
		Visible = false,
		Parent = CompassController.parts.strip,
	})
end

local function newPip(): TextLabel
	return UI.label(WORDS.pin, 13, {
		Name = "Pip",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 18, 0, 15),
		TextColor3 = PING.color,
		ZIndex = 3,
		Visible = false,
		Parent = CompassController.parts.strip,
	})
end

local function newMate(): Frame
	local mate = UI.new("Frame", {
		Name = "Mate",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(0, 60, 0, 24),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = CompassController.parts.screen,
	})
	local text = UI.label("", 20, { Name = "Text", Size = UDim2.new(1, 0, 1, 0), Parent = mate })
	UI.new("UIScale", { Name = "Pulse", Parent = text })
	return mate
end

local function newArrow(): Frame
	local arrow = UI.new("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 60, 0, 60),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = CompassController.parts.screen,
	})
	UI.label(WORDS.arrow, 22, {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 24, 0, 24),
		Parent = arrow,
	})
	local text = UI.label("", 18, {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = arrow,
	})
	UI.new("UIScale", { Name = "Pulse", Parent = text })
	return arrow
end

local function newPin(): Frame
	local pin = UI.new("Frame", {
		Name = "Pin",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(0, 170, 0, 50),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = CompassController.parts.screen,
	})
	UI.label("", 14, {
		Name = "Caption",
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = PING.color,
		Parent = pin,
	})
	local icon = UI.label(WORDS.pin, 26, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 32, 0, 32),
		Parent = pin,
	})
	UI.new("UIScale", { Name = "Pop", Parent = icon })
	return pin
end

-- The map's gates by the names on their signs (a SurfaceGui's TextLabel on
-- a part in the map's Landmarks): each name once, at the middle of its
-- gates, in its sign's colour, in name order.
function CompassController.readLandmarks(map: Instance?): { Landmark }
	local folder = map and map:FindFirstChild("Landmarks")
	local found: { [string]: { sum: Vector3, count: number, color: Color3 } } = {}
	for _, item in if folder then folder:GetChildren() else {} do
		if item:IsA("BasePart") then
			for _, gui in item:GetChildren() do
				local label = if gui:IsA("SurfaceGui") then gui:FindFirstChildWhichIsA("TextLabel") else nil
				if label and label.Text ~= "" then
					local entry = found[label.Text] or { sum = Vector3.zero, count = 0, color = label.TextColor3 }
					entry.sum += item.Position
					entry.count += 1
					found[label.Text] = entry
					break
				end
			end
		end
	end
	local list: { Landmark } = {}
	for name, entry in found do
		table.insert(list, { name = name, position = entry.sum / entry.count, color = entry.color })
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Reads the landmarks again when the map changes (or its gates arrive).
local function refreshLandmarks(now: number)
	local map = workspace:FindFirstChild("Map")
	if map == landmarksMap and now - landmarksCheckedAt < 1 then
		return
	end
	landmarksCheckedAt = now
	local folder = map and map:FindFirstChild("Landmarks")
	local parts = if folder then #folder:GetChildren() else 0
	if map == landmarksMap and parts == landmarkParts then
		return
	end
	landmarksMap, landmarkParts = map, parts
	local list = CompassController.readLandmarks(map)
	CompassController.landmarks = list
	local names = CompassController.parts.names
	for i, landmark in list do
		local label = pooled(names, i, newName)
		label.Text = landmark.name
		label.TextColor3 = landmark.color
		label.Size = UDim2.new(0, textWidth(landmark.name, NAME_SIZE), 0, 15)
	end
	hideFrom(names, #list + 1)
end

-- "boom" while an avatar is counting down to explode, "fight" if it fired
-- or took gas in the last CompassConfig.markers.fightSeconds, else nil.
function CompassController.troubleOf(character: Model, now: number?): string?
	if type(character:GetAttribute("ExplodesAt")) == "number" then
		return "boom"
	end
	local at = fightAt[character]
	return if at and (now or clock()) - at <= MARKERS.fightSeconds then "fight" else nil
end

-- An avatar took gas whenever its Gas goes up.
local function watchGas(character: Model)
	if watched[character] then
		return
	end
	watched[character] = true
	local last = tonumber(character:GetAttribute("Gas")) or 0
	character:GetAttributeChangedSignal("Gas"):Connect(function()
		local gas = tonumber(character:GetAttribute("Gas")) or 0
		if gas > last then
			fightAt[character] = clock()
		end
		last = gas
	end)
end

local function onCombatEvent(event: any)
	if type(event) == "table" and (event.kind == "shot" or event.kind == "lob") then
		local character = Combatants.character(event.shooter)
		if character then
			fightAt[character] = clock()
		end
	end
end

-- Takes a ping the server sent: true if it's shown.
function CompassController.receive(event: unknown): boolean
	if type(event) ~= "table" then
		return false
	end
	local ping = event :: { [string]: any }
	local from, position = ping.from, ping.position
	if type(from) ~= "number" or typeof(position) ~= "Vector3" then
		return false
	end
	-- Only ever your own team's (the server sends nothing else).
	local who = Combatants.get(from)
	local mine = ClientState.teamId()
	if not (who and mine and who.team == mine) then
		return false
	end
	-- Never longer than a ping lasts, whatever it says (NaN included).
	local now = workspace:GetServerTimeNow()
	local endsAt = now + PING.seconds
	if type(ping.endsAt) == "number" and ping.endsAt == ping.endsAt then
		endsAt = math.min(ping.endsAt, endsAt)
	end
	if endsAt <= now then
		return false
	end
	CompassController.pings[from] = { from = from, position = position, endsAt = endsAt, arrivedAt = clock() }
	Audio.play("ping")
	return true
end

-- The spot under the crosshair: the first thing the crosshair's ray hits
-- within CompassConfig.ping.range, else the ground it reaches, else nil.
function CompassController.aimSpot(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	if ray.Direction.Magnitude < 1e-6 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = workspace:Raycast(ray.Origin, ray.Direction.Unit * PING.range, params)
	if hit then
		return hit.Position
	end
	return Compass.groundSpot(ray.Origin, ray.Direction, PING.range)
end

-- Z (or the middle mouse button): pings the spot under the crosshair, if
-- you're in the match with no screen open and the last ping was long
-- enough ago. True if it was sent (the server has the last word).
function CompassController.ping(): boolean
	if not (FeatureFlags.COMPASS and started and ClientState.isActive() and player.Character)
		or ClientState.inPractice()
		or InputController.menuOpen
	then
		return false
	end
	local now = clock()
	if now - lastPing < PING.cooldownSeconds then
		return false
	end
	local spot = CompassController.aimSpot()
	if not spot then
		return false
	end
	lastPing = now
	ClientState.send("Ping", spot)
	return true
end

local function renderStrip(view: CFrame, heading: number, me: Vector3)
	local p = CompassController.parts
	local width, span = STRIP.width, STRIP.spanDegrees
	for _, item in fixed do
		local x, on = Compass.stripX(item.bearing, heading, width, span)
		item.gui.Visible = on
		if on then
			item.gui.Position = UDim2.new(0, x, 0, item.y)
		end
	end
	-- The names, nearest first; one you're at leaves the strip.
	local order = {}
	for i, landmark in CompassController.landmarks do
		local distance = Vector3.new(landmark.position.X - me.X, 0, landmark.position.Z - me.Z).Magnitude
		local bearing = Compass.bearingOf(landmark.position - view.Position)
		if bearing and distance > STRIP.landmarkHideWithin then
			local x, onStrip = Compass.stripX(bearing, heading, width, span)
			if onStrip then
				table.insert(order, { label = p.names[i], x = x, distance = distance })
			end
		end
	end
	table.sort(order, function(a, b)
		return a.distance < b.distance
	end)
	local items = {}
	for i, entry in order do
		items[i] = { x = entry.x, width = entry.label.Size.X.Offset }
	end
	local shown = Compass.layout(items, width, STRIP.labelGap)
	for _, label in p.names do
		label.Visible = false
	end
	for i, entry in order do
		if shown[i] then
			entry.label.Position = UDim2.new(0, entry.x, 0, ROW_Y)
			entry.label.Visible = true
		end
	end
end

type Mate = { character: Model, head: BasePart, team: string, distance: number, trouble: string? }

-- Your teammates on the field (players and bots), alive, but not you.
local function teammates(view: CFrame, now: number): { Mate }
	local mine = ClientState.teamId()
	local list: { Mate } = {}
	if not (mine and TeamConfig.teams[mine]) then
		return list
	end
	for _, character in Combatants.avatars() do
		if character ~= player.Character then
			local who = Combatants.fromCharacter(character)
			local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if who and who.team == mine and head and head:IsA("BasePart") and not (humanoid and humanoid.Health <= 0) then
				table.insert(list, {
					character = character,
					head = head,
					team = mine,
					distance = (head.Position - view.Position).Magnitude,
					trouble = CompassController.troubleOf(character, now),
				})
			end
		end
	end
	return list
end

local function renderMates(view: CFrame, fieldOfView: number, viewport: Vector2, now: number)
	local p = CompassController.parts
	local record = CompassController.shown
	table.clear(record.mates)
	table.clear(record.arrows)
	local pulse = if Settings.reduceMotion then 1 else 1 + 0.12 * math.sin(now * 9)
	local shown = 0
	local offScreen: { Mate } = {}
	for _, mate in teammates(view, now) do
		local spot, depth = Compass.project(view, fieldOfView, viewport, mate.head.Position + OVER_HEAD)
		local color = TeamConfig.teams[mate.team].color
		if Compass.onScreen(spot, depth, viewport, MARKERS.onScreenMargin) then
			if mate.distance >= MARKERS.minDistance then
				shown += 1
				local marker = pooled(p.mates, shown, newMate)
				marker.Position = UDim2.fromOffset(spot.X, spot.Y)
				marker.Text.Text = symbolOf(mate.team) .. alertOf(mate.trouble)
				marker.Text.TextColor3 = color
				marker.Text.Pulse.Scale = if mate.trouble then pulse else 1
				marker.Visible = true
				table.insert(record.mates, mate.character)
			end
		elseif mate.trouble then
			table.insert(offScreen, mate)
		end
	end
	hideFrom(p.mates, shown + 1)
	-- Arrows for the ones in trouble off the screen: blowing up first, then
	-- the nearest.
	table.sort(offScreen, function(a, b)
		if (a.trouble == "boom") ~= (b.trouble == "boom") then
			return a.trouble == "boom"
		end
		return a.distance < b.distance
	end)
	local arrows = math.min(#offScreen, MARKERS.maxArrows)
	for i = 1, arrows do
		local mate = offScreen[i]
		local arrow = pooled(p.arrows, i, newArrow)
		local spot, rotation = Compass.edge(view, fieldOfView, viewport, mate.head.Position, MARKERS.edgeInsetX, MARKERS.edgeInsetY)
		local angle = math.rad(rotation)
		local color = TeamConfig.teams[mate.team].color
		arrow.Position = UDim2.fromOffset(spot.X, spot.Y)
		arrow.Pointer.Rotation = rotation
		arrow.Pointer.Position = UDim2.new(0.5, math.sin(angle) * 20, 0.5, -math.cos(angle) * 20)
		arrow.Pointer.TextColor3 = color
		arrow.Text.Text = symbolOf(mate.team) .. alertOf(mate.trouble)
		arrow.Text.TextColor3 = color
		arrow.Text.Pulse.Scale = pulse
		arrow.Visible = true
		table.insert(record.arrows, { character = mate.character, trouble = mate.trouble :: string })
	end
	hideFrom(p.arrows, arrows + 1)
end

local function nameOf(from: number): string
	if from == player.UserId then
		return WORDS.you
	end
	local who = Combatants.get(from)
	return if who then string.upper(who.name) else "?"
end

local function setFade(label: TextLabel, fade: number)
	label.TextTransparency = fade
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = fade
	end
end

local function renderPings(view: CFrame, fieldOfView: number, viewport: Vector2, heading: number, me: Vector3, now: number)
	local p = CompassController.parts
	local record = CompassController.shown.pins
	table.clear(record)
	local serverNow = workspace:GetServerTimeNow()
	local live: { Ping } = {}
	for from, ping in CompassController.pings do
		if ping.endsAt <= serverNow then
			CompassController.pings[from] = nil
		else
			table.insert(live, ping)
		end
	end
	-- The newest on top.
	table.sort(live, function(a, b)
		return a.arrivedAt < b.arrivedAt
	end)
	local width, span = STRIP.width, STRIP.spanDegrees
	local calm = Settings.reduceMotion
	for i, ping in live do
		-- On the strip, or at its end on the side to turn to.
		local pip = pooled(p.pips, i, newPip)
		local bearing = Compass.bearingOf(ping.position - view.Position) or heading
		local x, onStrip = Compass.stripX(bearing, heading, width, span)
		if onStrip then
			pip.Text = WORDS.pin
		else
			local left = Compass.relative(bearing, heading) < 0
			pip.Text = if left then WORDS.pingLeft else WORDS.pingRight
			x = if left then 10 else width - 10
		end
		pip.Position = UDim2.new(0, x, 0, ROW_Y)
		pip.ZIndex = 3 + i
		pip.Visible = true
		-- In the world, while it's on the screen.
		local pin = pooled(p.pins, i, newPin)
		local spot, depth = Compass.project(view, fieldOfView, viewport, ping.position)
		if Compass.onScreen(spot, depth, viewport, 0) then
			local age = now - ping.arrivedAt
			local fade = if calm then 0 else math.clamp(1 - (ping.endsAt - serverNow) / PING.fadeSeconds, 0, 1)
			pin.Position = UDim2.fromOffset(spot.X, spot.Y)
			pin.Caption.Text = string.format(WORDS.caption, nameOf(ping.from), math.floor((ping.position - me).Magnitude + 0.5))
			pin.Icon.Pop.Scale = if calm or age >= PING.popSeconds then 1 else 1 + 0.6 * (1 - age / PING.popSeconds)
			setFade(pin.Caption, fade)
			setFade(pin.Icon, fade)
			pin.ZIndex = 1 + i
			pin.Visible = true
			table.insert(record, ping.from)
		else
			pin.Visible = false
		end
	end
	hideFrom(p.pips, #live + 1)
	hideFrom(p.pins, #live + 1)
end

-- Every frame, once the camera has moved: nothing unless you're in the
-- match with an avatar.
function CompassController.render()
	local p = CompassController.parts
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	-- Not in the practice yard: it's far from the battlefield, with no team.
	local on = ClientState.isActive() and not ClientState.inPractice() and root ~= nil and root:IsA("BasePart") and camera ~= nil
	if p.screen.Enabled ~= on then
		p.screen.Enabled = on
	end
	if not on then
		table.clear(CompassController.shown.mates)
		table.clear(CompassController.shown.arrows)
		table.clear(CompassController.shown.pins)
		return
	end
	local now = clock()
	local view = camera.CFrame
	local heading = Compass.heading(view)
	local me = (root :: BasePart).Position
	refreshLandmarks(now)
	renderStrip(view, heading, me)
	renderMates(view, camera.FieldOfView, camera.ViewportSize, now)
	renderPings(view, camera.FieldOfView, camera.ViewportSize, heading, me, now)
end

function CompassController.start()
	if started or not FeatureFlags.COMPASS then
		return
	end
	started = true
	build()
	local pingRemote = ClientState.remote("Ping") :: RemoteEvent
	pingRemote.OnClientEvent:Connect(CompassController.receive)
	-- Throws (CombatEvent) and shots (ShotFeed) mark a fight.
	local combatEvent = ClientState.remote("CombatEvent") :: RemoteEvent
	combatEvent.OnClientEvent:Connect(onCombatEvent)
	ShotFeed.listen(onCombatEvent)
	Combatants.watch(watchGas)
	InputController.PingPressed:Connect(CompassController.ping)
	-- A new team: the old one's pings mean nothing now.
	ClientState.TeamChanged:Connect(function()
		table.clear(CompassController.pings)
	end)
	-- After the camera (and its kick) has moved this frame, so the markers
	-- sit exactly on what they mark.
	RunService:BindToRenderStep("FartWarsCompass", Enum.RenderPriority.Camera.Value + 2, CompassController.render)
end

return CompassController
