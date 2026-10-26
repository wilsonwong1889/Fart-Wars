-- Combat on the client: it shows and it asks, the server decides.
--   * a crosshair that follows the mouse (centred in first person)
--   * left click fires the equipped weapon toward the crosshair at its fire
--     interval, with an instant local tracer; the server's verdict comes
--     back as a hit marker
--   * other players' shots as tracers, a red marker pointing at whoever
--     hit you, a kill feed, and "ELIMINATED" / "ELIMINATED BY" cards
--   * Shift: Fart Dash (on the ground, off cooldown); the client moves the
--     avatar and the server checks it
--   * teammates outlined in the team colour
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local InputController = require(script.Parent.InputController)

local C = UIConfig.colors
local DASH = GameConfig.FART_DASH

local CombatController = {}

CombatController.parts = {} :: { [string]: any }

local player = Players.LocalPlayer
local lastShot = -math.huge
local lastDash = -math.huge
local firing = false
local started = false

local function clock(): number
	return os.clock()
end

local function weapon(): WeaponConfig.Weapon
	local id = player:GetAttribute("Weapon")
	return WeaponConfig.weapons[id :: any] or WeaponConfig.weapons[WeaponConfig.default]
end

local function humanoid(): Humanoid?
	local character = player.Character
	local found = character and character:FindFirstChildOfClass("Humanoid")
	return if found and found.Health > 0 then found else nil
end

-- Whether the player may fire or dash right now.
local function canAct(): boolean
	return ClientState.isActive() and not InputController.menuOpen and humanoid() ~= nil
end

local function nameOf(userId: number): (string, Color3)
	local other = Players:GetPlayerByUserId(userId)
	local team = other and other:GetAttribute("TeamId")
	local color = if team and TeamConfig.teams[team] then TeamConfig.teams[team].color else C.text
	return if other then other.DisplayName else "Someone", color
end

local function build()
	local p = CombatController.parts
	local screen = UI.screen("Combat", 4)
	p.screen = screen

	local crosshair = UI.new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 28, 0, 28),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	p.crosshair = crosshair
	for i, size in { UDim2.new(0, 2, 0, 10), UDim2.new(0, 10, 0, 2) } do
		for _, offset in { -9, 9 } do
			UI.new("Frame", {
				Name = "Tick",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = if i == 1 then UDim2.new(0.5, 0, 0.5, offset) else UDim2.new(0.5, offset, 0.5, 0),
				Size = size,
				BackgroundColor3 = C.text,
				BorderSizePixel = 0,
				Parent = crosshair,
			}, { UI.stroke(C.stroke, 1) })
		end
	end
	p.hitMarker = UI.label("✕", 26, {
		Name = "HitMarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = crosshair,
	})

	p.damageArrow = UI.label("▲", 40, {
		Name = "DamageArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 260, 0, 260),
		TextColor3 = C.warning,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = screen,
	})

	p.card = UI.label("", 34, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.new(0, 600, 0, 44),
		Visible = false,
		Parent = screen,
	})

	p.feed = UI.new("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 70),
		Size = UDim2.new(0, 320, 0, 140),
		BackgroundTransparency = 1,
		Parent = screen,
	}, { UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right) })

	p.dash = UI.label("", 16, {
		Name = "Dash",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -70),
		Size = UDim2.new(0, 220, 0, 22),
		Visible = false,
		Parent = screen,
	})
end

local function flash(item: GuiObject, seconds: number)
	local token = ((item:GetAttribute("Flash") :: number?) or 0) + 1
	item:SetAttribute("Flash", token)
	item.Visible = true
	task.delay(seconds, function()
		if item:GetAttribute("Flash") == token then
			item.Visible = false
		end
	end)
end

local function showCard(text: string, color: Color3)
	local card = CombatController.parts.card
	card.Text = text
	card.TextColor3 = color
	flash(card, 2.5)
end

local function tracer(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(0.15, 0.15, length)
	beam.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
	beam.Parent = workspace
	Debris:AddItem(beam, 0.08)
end

-- Where the crosshair points, and the direction to it from the head.
local function aim(): (Vector3?, Vector3?, Vector3?)
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not (head and head:IsA("BasePart")) then
		return nil, nil, nil
	end
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Model }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	local target = if result then result.Position else ray.Origin + ray.Direction * 1000
	local offset = target - head.Position
	if offset.Magnitude < 0.01 then
		return nil, nil, nil
	end
	return offset.Unit, head.Position, target
end

function CombatController.fire(): boolean
	if not (FeatureFlags.PLACEHOLDER_BLASTER and canAct()) then
		return false
	end
	local gun = weapon()
	local at = clock()
	if at - lastShot < gun.fireInterval then
		return false
	end
	local direction, from = aim()
	if not (direction and from) then
		return false
	end
	lastShot = at
	ClientState.send("FireWeapon", direction)
	tracer(from, from + direction * gun.range, gun.tracerColor)
	return true
end

local function startFiring()
	if firing then
		return
	end
	firing = true
	task.spawn(function()
		while InputController.fireHeld do
			CombatController.fire()
			task.wait(math.max(0.05, weapon().fireInterval - (clock() - lastShot)))
		end
		firing = false
	end)
end

function CombatController.dash(): boolean
	local h = humanoid()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (FeatureFlags.FART_DASH and canAct() and h and root and root:IsA("BasePart")) then
		return false
	end
	if h.FloorMaterial == Enum.Material.Air or clock() - lastDash < DASH.COOLDOWN_SECONDS then
		return false
	end
	local direction = h.MoveDirection
	if direction.Magnitude < 0.1 then
		local look = workspace.CurrentCamera.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	if direction.Magnitude < 0.01 then
		return false
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	lastDash = clock()
	local attachment = Instance.new("Attachment")
	attachment.Name = "FartDashAttachment"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Name = "FartDash"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	push.LineDirection = direction
	push.LineVelocity = DASH.SPEED
	push.MaxForce = math.huge
	push.Parent = root
	Debris:AddItem(push, DASH.SECONDS)
	Debris:AddItem(attachment, DASH.SECONDS)
	ClientState.send("FartDash", direction)
	return true
end

local function feedLine(killer: number, victim: number)
	local feed = CombatController.parts.feed
	local killerName, killerColor = nameOf(killer)
	local victimName = nameOf(victim)
	local line = UI.label(`{killerName}  ✕  {victimName}`, 16, {
		Name = "Line",
		LayoutOrder = -math.floor(clock() * 100),
		Size = UDim2.new(1, 0, 0, 22),
		Font = UIConfig.bodyFont,
		TextColor3 = killerColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = feed,
	})
	local lines = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 5, #lines do
		lines[i]:Destroy()
	end
	task.delay(6, function()
		if line.Parent then
			line:Destroy()
		end
	end)
end

local function onCombatEvent(event: { [string]: any })
	local p = CombatController.parts
	if event.kind == "shot" then
		if event.shooter ~= player.UserId and typeof(event.from) == "Vector3" and typeof(event.to) == "Vector3" then
			local _, color = nameOf(event.shooter)
			tracer(event.from, event.to, color)
		end
	elseif event.kind == "hit" then
		p.hitMarker.TextColor3 = if event.blocked then C.muted elseif (event.health or 0) <= 0 then C.warning else C.text
		flash(p.hitMarker, 0.15)
	elseif event.kind == "damaged" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and typeof(event.from) == "Vector3" then
			local camera = workspace.CurrentCamera.CFrame
			local toward = event.from - (root :: BasePart).Position
			local forward = camera.LookVector
			local right = camera.RightVector
			p.damageArrow.Rotation = math.deg(math.atan2(toward:Dot(right), toward:Dot(Vector3.new(forward.X, 0, forward.Z))))
			flash(p.damageArrow, 0.6)
		end
	elseif event.kind == "elimination" then
		feedLine(event.killer, event.victim)
		if event.killer == player.UserId then
			local name, color = nameOf(event.victim)
			showCard(`ELIMINATED {string.upper(name)}`, color)
		elseif event.victim == player.UserId then
			local name, color = nameOf(event.killer)
			showCard(`ELIMINATED BY {string.upper(name)}`, color)
		end
	end
end

-- Teammates get an outline in the team colour, through walls.
local function refreshTeammates()
	local mine = player:GetAttribute("TeamId")
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and other ~= player then
			local existing = character:FindFirstChild("TeammateOutline")
			local team = other:GetAttribute("TeamId")
			local show = FeatureFlags.TEAMMATE_HIGHLIGHTS and mine ~= nil and team == mine and TeamConfig.teams[team]
			if show and not existing then
				local outline = Instance.new("Highlight")
				outline.Name = "TeammateOutline"
				outline.FillTransparency = 1
				outline.OutlineColor = TeamConfig.teams[team].color
				outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				outline.Adornee = character
				outline.Parent = character
			elseif existing and not show then
				existing:Destroy()
			end
		end
	end
end
CombatController.refreshTeammates = refreshTeammates

-- Every frame: the crosshair follows the mouse, the dash meter counts down.
local function render()
	local p = CombatController.parts
	local aiming = ClientState.isActive() and not InputController.menuOpen
	p.crosshair.Visible = aiming
	UserInputService.MouseIconEnabled = not aiming
	if aiming then
		local mouse = UserInputService:GetMouseLocation()
		p.crosshair.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
	end
	p.dash.Visible = aiming and FeatureFlags.FART_DASH
	local cooldownLeft = DASH.COOLDOWN_SECONDS - (clock() - lastDash)
	p.dash.Text = if cooldownLeft > 0 then `FART DASH {math.ceil(cooldownLeft)}s` else "FART DASH READY (SHIFT)"
	p.dash.TextColor3 = if cooldownLeft > 0 then C.muted else C.accent
end
CombatController.render = render

function CombatController.start()
	if started then
		return
	end
	started = true
	build()
	InputController.FireHeld:Connect(function(held)
		if held then
			startFiring()
		end
	end)
	InputController.DashPressed:Connect(CombatController.dash)
	local combatEvent = ClientState.remote("CombatEvent") :: RemoteEvent
	combatEvent.OnClientEvent:Connect(function(event)
		if type(event) == "table" then
			onCombatEvent(event)
		end
	end)
	player.CharacterAdded:Connect(function()
		lastDash = -math.huge
	end)
	-- Teammate outlines follow team changes and new avatars; a slow sweep
	-- catches anything missed.
	local function watch(other: Player)
		other:GetAttributeChangedSignal("TeamId"):Connect(refreshTeammates)
		other.CharacterAdded:Connect(function()
			task.defer(refreshTeammates)
		end)
	end
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerAdded:Connect(watch)
	task.spawn(function()
		while true do
			refreshTeammates()
			task.wait(2)
		end
	end)
	RunService.RenderStepped:Connect(render)
	render()
end

return CombatController
