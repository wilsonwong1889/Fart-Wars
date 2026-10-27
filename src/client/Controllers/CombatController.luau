-- Combat on the client: it shows and it asks, the server decides.
--   * a crosshair that follows the mouse (centred in first person)
--   * left click fires the Gas Blaster toward the crosshair at its fire
--     interval, numbering each shot, with an instant local tracer; the
--     server's verdict comes back as a hit marker that pops at the
--     crosshair (bigger, gold and higher-pitched for a headshot; bigger
--     still, orange and with a ring for the hit that sets them off)
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
local TweenService = game:GetService("TweenService")

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
local Settings = require(Client.Settings)
local InputController = require(script.Parent.InputController)
local WeaponFxController = require(script.Parent.WeaponFxController)

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
	return if other then `{UI.teamSymbol(team :: any)}{other.DisplayName}` else "Someone", color
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

-- The hit marker, on the server's verdict only (never this screen's guess):
-- it pops in at the crosshair and fades. A headshot's is bigger and gold,
-- and the hit sound plays higher and louder; the hit that fills a target's
-- gas (they're going off) is bigger still, orange, and throws a ring out;
-- one that did nothing (a teammate, spawn protection, or already going
-- off) is small, grey and silent. REDUCE MOTION just shows and hides it
-- (no pop or fade, a still ring); REDUCED EFFECTS (or low detail) keeps
-- the pop but drops the fade and the ring.
local HIT = UIConfig.hitMarker
local hitTweens: { [Instance]: Tween } = {}

local function stopHitTween(item: Instance)
	local tween = hitTweens[item]
	if tween then
		tween:Cancel()
		hitTweens[item] = nil
	end
end

local function tweenHit(item: Instance, seconds: number, goals: { [string]: any })
	stopHitTween(item)
	local tween = TweenService:Create(item, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	hitTweens[item] = tween
	tween:Play()
end

-- The marker's pop (a UIScale on it) and the ring behind it.
local function dressHitMarker()
	local p = CombatController.parts
	p.hitMarker.ZIndex = 2
	p.hitPop = UI.new("UIScale", { Name = "Pop", Parent = p.hitMarker })
	p.hitRing = UI.new("Frame", {
		Name = "HitRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, HIT.ringSize, 0, HIT.ringSize),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = p.crosshair,
	}, {
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.new("UIStroke", { Color = HIT.looks.kaboom.color, Thickness = 3 }),
	})
end

-- Which marker a verdict gets, first match wins: "blocked", "kaboom" (this
-- hit filled their gas), "headshot", "body".
function CombatController.hitKind(event: { [string]: any }): string
	if event.blocked then
		return "blocked"
	elseif (tonumber(event.gas) or 0) >= 100 then
		return "kaboom"
	end
	return if event.headshot then "headshot" else "body"
end

local function showHit(event: { [string]: any })
	local p = CombatController.parts
	local kind = CombatController.hitKind(event)
	local look = HIT.looks[kind]
	local calm = Settings.reduceMotion
	local plain = Settings.reducedEffects or Settings.lowDetail
	local marker: TextLabel = p.hitMarker
	local stroke = marker:FindFirstChildOfClass("UIStroke")
	stopHitTween(marker)
	stopHitTween(p.hitPop)
	marker.TextColor3 = look.color
	marker.TextSize = look.size
	marker.TextTransparency = 0
	if stroke then
		stopHitTween(stroke)
		stroke.Thickness = math.max(2, look.size // 14)
		stroke.Transparency = 0
	end
	p.hitPop.Scale = if calm then 1 else look.pop
	if not calm and look.pop ~= 1 then
		tweenHit(p.hitPop, HIT.popSeconds, { Scale = 1 })
	end
	flash(marker, look.seconds)
	-- It fades over the end of its time, unless another hit comes first.
	local token = marker:GetAttribute("Flash")
	if not (calm or plain) then
		task.delay(math.max(0, look.seconds - HIT.fadeSeconds), function()
			if marker:GetAttribute("Flash") == token then
				tweenHit(marker, HIT.fadeSeconds, { TextTransparency = 1 })
				if stroke then
					tweenHit(stroke, HIT.fadeSeconds, { Transparency = 1 })
				end
			end
		end)
	end
	if kind == "kaboom" and not plain then
		local ring: Frame = p.hitRing
		local ringStroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
		local full = UDim2.new(0, HIT.ringSize, 0, HIT.ringSize)
		stopHitTween(ring)
		stopHitTween(ringStroke)
		ringStroke.Transparency = 0
		ring.Size = if calm then full else UDim2.new(0, look.size, 0, look.size)
		if not calm then
			tweenHit(ring, look.seconds, { Size = full })
			tweenHit(ringStroke, look.seconds, { Transparency = 1 })
		end
		flash(ring, look.seconds)
	end
	if kind ~= "blocked" then
		Audio.play("hit", nil, if event.headshot then { pitch = HIT.headshotPitch, volume = HIT.headshotVolume } else nil)
	end
end

-- Shot tracers: the bolts WeaponFxController draws (ShotFx), from a pool
-- of GameConfig.BUDGET.MAX_TRACERS, so a server full of Spritzers costs a
-- fixed number of parts.
CombatController.tracers = WeaponFxController.tracers

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
	-- The gun kicks at once (the server decides whether it hit).
	WeaponFxController.fired(player.UserId)
	-- A lob is drawn when the server says where it flies. A shot's bolt
	-- stops at the first thing in its way, as far as this screen can tell
	-- (the server decides what it really hit).
	if gun.projectile == "hitscan" then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Model }
		local blocked = workspace:Raycast(from, direction * gun.range, params)
		local stop = if blocked then blocked.Position else from + direction * gun.range
		WeaponFxController.tracer(player.UserId, from, stop, tracerColorOf(player, gun.tracerColor))
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
	if event.kind == "dashRefill" then
		lastDash = -math.huge
		return
	end
	if event.kind == "shot" then
		if event.shooter ~= player.UserId and typeof(event.from) == "Vector3" and typeof(event.to) == "Vector3" then
			local _, color = nameOf(event.shooter)
			WeaponFxController.tracer(event.shooter, event.from, event.to, tracerColorOf(Players:GetPlayerByUserId(event.shooter), color))
			-- Their gun's sound, from where they fired.
			local shooter = Players:GetPlayerByUserId(event.shooter)
			local gun = WeaponConfig.weapons[(shooter and shooter:GetAttribute("Weapon")) :: any] or WeaponConfig.weapons[WeaponConfig.default]
			Audio.play(gun.fireSound, event.from)
		end
	elseif event.kind == "hit" then
		showHit(event)
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
			-- The team's symbol over teammates' heads too (not colour alone).
			local mark = character:FindFirstChild("TeamMark")
			local head = character:FindFirstChild("Head")
			if show and Settings.teamSymbols and head and not mark then
				local board = Instance.new("BillboardGui")
				board.Name = "TeamMark"
				board.Size = UDim2.new(0, 28, 0, 28)
				board.StudsOffset = Vector3.new(0, 2.6, 0)
				board.MaxDistance = 150
				board.Adornee = head
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.new(1, 0, 1, 0)
				label.Text = TeamConfig.teams[team].symbol
				label.TextScaled = true
				label.TextColor3 = TeamConfig.teams[team].color
				label.TextStrokeTransparency = 0.2
				label.Parent = board
				board.Parent = character
			elseif mark and not (show and Settings.teamSymbols) then
				mark:Destroy()
			end
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
	dressHitMarker()
	InputController.FireHeld:Connect(function(held)
		if held then
			startFiring()
		end
	end)
	InputController.DashPressed:Connect(CombatController.dash)
	InputController.AbilityPressed:Connect(CombatController.useAbility)
	InputController.EmotePressed:Connect(function()
		if ClientState.isActive() and not InputController.menuOpen then
			ClientState.send("Emote")
		end
	end)
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
