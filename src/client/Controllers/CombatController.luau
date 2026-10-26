-- Combat on the client: it shows and it asks, the server decides.
--   * a crosshair that follows the mouse (centred in first person)
--   * left click fires the Gas Blaster toward the crosshair at its fire
--     interval, numbering each shot, with an instant local tracer; the
--     server's verdict comes back as a hit marker (bigger for a headshot)
--   * your gas meter and its stage, the countdown when you're about to
--     blow, and your current streak
--   * other players' shots as tracers, a red marker pointing at whoever
--     hit you, a kill feed (with assists), and "EXPLODED" cards
--   * Shift: Fart Dash (on the ground, off cooldown); the client moves the
--     avatar and the server checks it
--   * Q: the equipped ability (Recovery Burst, Gas Pulse) with its cooldown
--   * the weapon in hand (and a note when a new loadout waits for the
--     respawn); tracers in the shooter's cosmetic colour if they have one
--   * teammates outlined in the team colour
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityConfig = require(Shared.Config.AbilityConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local Audio = require(Client.Audio)
local InputController = require(script.Parent.InputController)

local C = UIConfig.colors
local DASH = AbilityConfig.FartDash
-- Gas stage names, 0-4.
local STAGES = { "FRESH", "BLOATED", "SWOLLEN", "CRITICAL", "KABOOM" }
local STAGE_COLORS = {
	Color3.fromRGB(150, 220, 90),
	Color3.fromRGB(200, 220, 70),
	Color3.fromRGB(240, 190, 60),
	Color3.fromRGB(240, 110, 50),
	Color3.fromRGB(240, 60, 50),
}

local CombatController = {}

CombatController.parts = {} :: { [string]: any }

local player = Players.LocalPlayer
local lastShot = -math.huge
local lastDash = -math.huge
local shotId = 0
local streak = 0
local lastStage = 0
local firing = false
local started = false

local function clock(): number
	return os.clock()
end

local function weapon(): WeaponConfig.Weapon
	local id = player:GetAttribute("Weapon")
	return WeaponConfig.weapons[id :: any] or WeaponConfig.weapons[WeaponConfig.default]
end

-- A shooter's tracer colour: their cosmetic's, if they've equipped one.
local function tracerColorOf(shooter: Player?, default: Color3): Color3
	local id = shooter and shooter:GetAttribute("Tracer")
	local cosmetic = type(id) == "string" and ProgressionConfig.cosmetics[id]
	return if cosmetic then cosmetic.tracerColor else default
end

local function humanoid(): Humanoid?
	local character = player.Character
	local found = character and character:FindFirstChildOfClass("Humanoid")
	return if found and found.Health > 0 then found else nil
end

local function exploding(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("ExplodesAt") ~= nil
end

-- Whether the player may fire or dash right now.
local function canAct(): boolean
	return ClientState.isActive() and not InputController.menuOpen and humanoid() ~= nil and not exploding()
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
		Position = UDim2.new(1, -20, 0, 190),
		Size = UDim2.new(0, 320, 0, 140),
		BackgroundTransparency = 1,
		Parent = screen,
	}, { UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right) })

	-- The bars over the hotbar: gas (left) and Fart Dash charge (right).
	local bars = UI.new("Frame", {
		Name = "Bars",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0, 470, 0, 26),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	p.bars = bars
	local meter = UI.new("Frame", {
		Name = "GasMeter",
		Size = UDim2.new(0, 290, 1, 0),
		BackgroundColor3 = Color3.fromRGB(30, 26, 40),
		Visible = false,
		Parent = bars,
	}, { UI.corner(8), UI.stroke(C.stroke, 3) })
	p.gasMeter = meter
	p.gasFill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = meter,
	}, { UI.corner(8), UI.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)) })
	p.gasText = UI.label("GAS 0%  FRESH", 15, {
		Name = "Text",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
		Parent = meter,
	})
	UI.label("💨", 16, {
		Name = "Icon",
		Size = UDim2.new(0, 24, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
		ZIndex = 2,
		Parent = meter,
	})
	local energy = UI.new("Frame", {
		Name = "DashMeter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 170, 1, 0),
		BackgroundColor3 = Color3.fromRGB(30, 26, 40),
		Visible = false,
		Parent = bars,
	}, { UI.corner(8), UI.stroke(C.stroke, 3) })
	p.dashMeter = energy
	p.dashFill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = energy,
	}, { UI.corner(8), UI.gradient(Color3.fromRGB(255, 190, 60), Color3.fromRGB(240, 120, 20)) })
	p.dash = UI.label("", 11, {
		Name = "Dash",
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
		Font = UIConfig.bodyFont,
		ZIndex = 2,
		Parent = energy,
	})

	-- Above the bars: the weapon in hand (left) and the streak (right).
	p.weapon = UI.label("", 16, {
		Name = "Weapon",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -90, 1, -140),
		Size = UDim2.new(0, 290, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = screen,
	})
	p.streak = UI.label("", 16, {
		Name = "Streak",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 150, 1, -140),
		Size = UDim2.new(0, 170, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 221, 26),
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
	if not (FeatureFlags.GAS_COMBAT and canAct()) then
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
	shotId += 1
	ClientState.send("FireWeapon", direction, shotId)
	Audio.play(gun.fireSound)
	-- A lob is drawn when the server says where it flies.
	if gun.projectile == "hitscan" then
		tracer(from, from + direction * gun.range, tracerColorOf(player, gun.tracerColor))
	end
	return true
end

-- Q: the equipped ability, when it's ready. The server decides.
function CombatController.useAbility(): boolean
	local id = player:GetAttribute("Ability")
	local readyAt = player:GetAttribute("AbilityReadyAt")
	if type(id) ~= "string" or not canAct() then
		return false
	end
	if type(readyAt) == "number" and workspace:GetServerTimeNow() < readyAt then
		return false
	end
	ClientState.send("UseAbility")
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
	if h.FloorMaterial == Enum.Material.Air or clock() - lastDash < DASH.cooldownSeconds then
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
	push.LineVelocity = DASH.speed :: number
	push.MaxForce = math.huge
	push.Parent = root
	Debris:AddItem(push, DASH.durationSeconds)
	Debris:AddItem(attachment, DASH.durationSeconds)
	Audio.play("dash")
	ClientState.send("FartDash", direction)
	return true
end

local function feedLine(killer: number?, victim: number, assists: number)
	local feed = CombatController.parts.feed
	local victimName, victimColor = nameOf(victim)
	local text = `💥 {victimName}`
	local color = victimColor
	if killer then
		local killerName, killerColor = nameOf(killer)
		text = `{killerName}{if assists > 0 then ` +{assists}` else ""}  💥  {victimName}`
		color = killerColor
	end
	local line = UI.label(text, 16, {
		Name = "Line",
		LayoutOrder = -math.floor(clock() * 100),
		Size = UDim2.new(1, 0, 0, 22),
		Font = UIConfig.bodyFont,
		TextColor3 = color,
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
			tracer(event.from, event.to, tracerColorOf(Players:GetPlayerByUserId(event.shooter), color))
		end
	elseif event.kind == "hit" then
		p.hitMarker.TextColor3 = if event.blocked then C.muted elseif (event.gas or 0) >= 100 then C.warning else C.text
		p.hitMarker.TextSize = if event.headshot then 36 else 26
		flash(p.hitMarker, 0.15)
		if not event.blocked then
			Audio.play("hit")
		end
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
	elseif event.kind == "elimination" and type(event.victim) == "number" then
		local assists = if type(event.assists) == "table" then event.assists else {}
		feedLine(event.killer, event.victim, #assists)
		if event.killer == player.UserId then
			streak += 1
			local name, color = nameOf(event.victim)
			showCard(`EXPLODED {string.upper(name)}`, color)
		elseif event.victim == player.UserId then
			streak = 0
			if event.killer then
				local name, color = nameOf(event.killer)
				showCard(`EXPLODED BY {string.upper(name)}`, color)
			else
				showCard("KABOOM", C.warning)
			end
		elseif table.find(assists, player.UserId) then
			local name, color = nameOf(event.victim)
			showCard(`ASSIST ON {string.upper(name)}`, color)
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
	p.dashMeter.Visible = aiming and FeatureFlags.FART_DASH
	local cooldownLeft = DASH.cooldownSeconds - (clock() - lastDash)
	p.dash.Text = if cooldownLeft > 0 then `FART DASH {math.ceil(cooldownLeft)}s` else "FART DASH READY (SHIFT)"
	p.dashFill.Size = UDim2.new(math.clamp(1 - cooldownLeft / DASH.cooldownSeconds, 0, 1), 0, 1, 0)
	p.weapon.Visible = aiming
	p.weapon.Text = string.upper(weapon().displayName) .. (if player:GetAttribute("LoadoutPending") then " · NEW LOADOUT ON RESPAWN" else "")

	-- Gas meter.
	local character = player.Character
	local active = ClientState.isActive() and character ~= nil
	p.gasMeter.Visible = active and FeatureFlags.GAS_COMBAT
	p.streak.Visible = active and streak > 0
	p.streak.Text = `STREAK {streak}`
	if active then
		local gas = math.clamp(tonumber((character :: Model):GetAttribute("Gas")) or 0, 0, 100)
		local stage = tonumber((character :: Model):GetAttribute("GasStage")) or 0
		local explodesAt = (character :: Model):GetAttribute("ExplodesAt")
		if type(explodesAt) == "number" then
			stage = 4
			gas = 100
		end
		p.gasFill.Size = UDim2.new(gas / 100, 0, 1, 0)
		p.gasFill.BackgroundColor3 = STAGE_COLORS[stage + 1]
		p.gasText.Text = if type(explodesAt) == "number"
			then `KABOOM IN {string.format("%.1f", math.max(0, explodesAt - workspace:GetServerTimeNow()))}`
			else `GAS {math.floor(gas)}%  {STAGES[stage + 1]}`
		if stage > lastStage then
			Audio.play(if stage >= 3 then "critical" else "inflate")
		end
		lastStage = stage
	end
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
	InputController.AbilityPressed:Connect(CombatController.useAbility)
	local combatEvent = ClientState.remote("CombatEvent") :: RemoteEvent
	combatEvent.OnClientEvent:Connect(function(event)
		if type(event) == "table" then
			onCombatEvent(event)
		end
	end)
	player.CharacterAdded:Connect(function()
		lastDash = -math.huge
		lastStage = 0
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
