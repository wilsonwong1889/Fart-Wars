-- The weapons in motion, for every player's gun on this screen (WeaponFx):
--   * equip: a new gun comes up from below
--   * recoil: each shot kicks the gun back and up, then it settles; the
--     Stink Lobber's kick is its throw
--   * the muzzle: puffs (or the Spritzer's droplets) in the gun's gas
--     colour, the Thunderclapper's flash and, for its own shooter, a small
--     camera kick
--   * idle: the gas tank glows slowly
--   * impacts: a puff and sparks where a shot hits something
--   * the shots themselves (ShotFx): the bolt from the muzzle to where the
--     shot stopped, the muzzle's burst, and a splat where it hit
-- It all happens on each client from the shots the server announces (and
-- your own as you fire), by moving the gun's grip weld locally; nothing
-- here changes what the server sees. Reduce motion keeps a little recoil
-- and none of the other movement; reduced effects halve the particles; and
-- no more than MAX_PARTICLES_PER_FRAME are emitted a frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponFx = require(Shared.Config.WeaponFx)
local WeaponArt = require(Shared.Config.WeaponArt)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ArtAssets = require(Shared.Config.ArtAssets)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Settings = require(Client.Settings)
local ShotFx = require(Client.ShotFx)

local WeaponFxController = {}

type State = {
	weapon: string,
	weld: Weld?,
	base: CFrame?,
	kick: number,
	equip: number,
	emitters: { [string]: ParticleEmitter },
	light: PointLight?,
	gas: { [BasePart]: number },
}

-- Every held gun being animated, by tool.
WeaponFxController.states = setmetatable({}, { __mode = "k" }) :: any
-- Particles emitted (for budgets and tests).
WeaponFxController.emitted = 0
-- The shots' bolt pool (ShotFx).
WeaponFxController.tracers = ShotFx.tracers

local player = Players.LocalPlayer
local frameParticles = 0
local cameraKick = 0
local clockTime = 0
local impactAnchor: BasePart? = nil
local impacts: { Attachment } = {}
local impactNext = 0
local started = false

local function reducedEffects(): boolean
	return Settings.reducedEffects or Settings.lowDetail
end

-- Emits up to `count` particles from `emitter`, within this frame's budget.
local function emit(emitter: ParticleEmitter, count: number): number
	if reducedEffects() then
		count = math.ceil(count / 2)
	end
	count = math.min(count, WeaponFx.MAX_PARTICLES_PER_FRAME - frameParticles)
	if count <= 0 then
		return 0
	end
	frameParticles += count
	WeaponFxController.emitted += count
	emitter:Emit(count)
	return count
end

local function emitter(parent: Instance, name: string, texture: string, color: Color3, size: number, speed: number, lifetime: number, spread: number?, gravity: number?): ParticleEmitter
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ParticleEmitter") then
		return existing
	end
	local particles = Instance.new("ParticleEmitter")
	particles.Name = name
	particles.Texture = ArtAssets.effect(texture)
	particles.Rate = 0
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 0.25
	particles.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	particles.Speed = NumberRange.new(speed * 0.6, speed)
	particles.SpreadAngle = Vector2.new(spread or 18, spread or 18)
	particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.6) })
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) })
	particles.Rotation = NumberRange.new(0, 360)
	particles.RotSpeed = NumberRange.new(-120, 120)
	particles.Drag = 5
	particles.Acceleration = Vector3.new(0, if gravity then -gravity else 3, 0)
	particles.Parent = parent
	return particles
end

local function gripWeld(tool: Tool): Weld?
	local character = tool.Parent
	local handle = tool:FindFirstChild("Handle")
	if not (character and handle) then
		return nil
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local weld = hand and hand:FindFirstChild("RightGrip")
	if weld and weld:IsA("Weld") and weld.Part1 == handle then
		return weld
	end
	return nil
end

-- Starts animating a gun that has just appeared in someone's hands.
function WeaponFxController.track(tool: Tool): State?
	local weapon = tool:GetAttribute("Weapon")
	if type(weapon) ~= "string" or not WeaponFx.weapons[weapon] then
		return nil
	end
	local existing = WeaponFxController.states[tool]
	if existing then
		return existing
	end
	local gas = {}
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Gas") then
			gas[part] = part.Transparency
		end
	end
	local state: State = {
		weapon = weapon,
		weld = nil,
		base = nil,
		kick = 0,
		equip = if Settings.reduceMotion then 0 else 1,
		emitters = {},
		light = nil,
		gas = gas,
	}
	WeaponFxController.states[tool] = state
	return state
end

local function heldBy(userId: number): Tool?
	local shooter = Players:GetPlayerByUserId(userId)
	local character = shooter and shooter.Character
	local tool = character and character:FindFirstChild("HeldWeapon")
	return if tool and tool:IsA("Tool") then tool else nil
end

-- A shot from `userId`'s gun: recoil, the muzzle's particles and flash.
function WeaponFxController.fired(userId: number)
	local tool = heldBy(userId)
	local state = tool and WeaponFxController.track(tool)
	if not (tool and state) then
		return
	end
	local fx = WeaponFx.weapons[state.weapon]
	state.kick = math.min(WeaponFx.MAX_RECOIL, state.kick + 1)
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		local art = WeaponArt[state.weapon]
		local color = if art and art.roles.Gas then art.roles.Gas.color else WeaponConfig.weapons[state.weapon].tracerColor
		local spec = fx.muzzle
		local particles = emitter(muzzle, "MuzzleFx", spec.texture, color, spec.size, spec.speed, spec.lifetime, spec.spread, spec.gravity)
		emit(particles, spec.count)
		if fx.sparks then
			local sparks = emitter(muzzle, "MuzzleSparks", "spark", Color3.fromRGB(255, 240, 180), 0.35, 14, 0.2, 25, nil)
			emit(sparks, fx.sparks)
		end
		local handle = muzzle.Parent
		if handle and handle:IsA("BasePart") then
			-- The burst, facing down the barrel (the muzzle's +Y).
			local world = handle.CFrame * muzzle.CFrame
			ShotFx.burst(CFrame.lookAt(world.Position, world.Position + world.UpVector), color, fx.shot.burst)
		end
		if fx.flash and not (Settings.reduceMotion or reducedEffects()) then
			local light = muzzle:FindFirstChild("Flash") :: PointLight?
			if not light then
				local made = Instance.new("PointLight")
				made.Name = "Flash"
				made.Color = color
				made.Brightness = fx.flash.brightness
				made.Range = fx.flash.range
				made.Enabled = false
				made.Parent = muzzle
				light = made
			end
			local flash = light :: PointLight
			flash.Enabled = true
			local token = (flash:GetAttribute("Token") or 0) + 1
			flash:SetAttribute("Token", token)
			task.delay(fx.flash.seconds, function()
				if flash:GetAttribute("Token") == token then
					flash.Enabled = false
				end
			end)
		end
	end
	if userId == player.UserId and fx.cameraKick and not Settings.reduceMotion then
		cameraKick = math.min(cameraKick + fx.cameraKick, fx.cameraKick * 2)
	end
end

-- A shot's bolt: from `userId`'s muzzle when their gun is in their hands
-- near `from` (where the server measured the shot from, the head), to
-- `to`, drawn the way their weapon's shots look.
function WeaponFxController.tracer(userId: number, from: Vector3, to: Vector3, color: Color3): BasePart?
	local tool = heldBy(userId)
	local weapon = if tool then tool:GetAttribute("Weapon") else nil
	local fx = WeaponFx.weapons[weapon :: any] or WeaponFx.weapons.GasBlaster
	local origin = from
	local muzzle = tool and tool:FindFirstChild("Muzzle", true)
	local handle = muzzle and muzzle.Parent
	if muzzle and muzzle:IsA("Attachment") and handle and handle:IsA("BasePart") then
		local at = (handle.CFrame * muzzle.CFrame).Position
		if (at - from).Magnitude < 8 then
			origin = at
		end
	end
	return ShotFx.bolt(origin, to, color, fx.shot)
end

-- Where a shot hit something: a puff and a few sparks, and (given the
-- way the shot came and the weapon's splat size) a splat on the surface.
function WeaponFxController.impact(position: Vector3, color: Color3, direction: Vector3?, splat: number?)
	local anchor = impactAnchor
	if not anchor then
		return
	end
	impactNext = impactNext % #impacts + 1
	local attachment = impacts[impactNext]
	attachment.WorldPosition = position
	local spec = WeaponFx.IMPACT
	local puff = emitter(attachment, "Puff", spec.texture, color, spec.size, 4, 0.4, 180, nil)
	puff.Color = ColorSequence.new(color)
	emit(puff, spec.count)
	local sparks = emitter(attachment, "Sparks", "spark", Color3.fromRGB(255, 245, 200), 0.3, 12, 0.25, 180, 20)
	emit(sparks, spec.sparks)
	if direction and splat then
		ShotFx.splat(position, direction, color, splat)
	end
end

-- One frame: settle every gun, and the camera kick.
function WeaponFxController.step(dt: number)
	frameParticles = 0
	clockTime += dt
	ShotFx.step(dt)
	local equipSeconds = WeaponFx.EQUIP.SECONDS
	for tool, state in WeaponFxController.states do
		if not tool.Parent then
			WeaponFxController.states[tool] = nil
			continue
		end
		local fx = WeaponFx.weapons[state.weapon]
		state.kick *= math.exp(-dt / fx.recover)
		if state.kick < 0.002 then
			state.kick = 0
		end
		state.equip = math.max(0, state.equip - dt / equipSeconds)
		local weld = gripWeld(tool)
		if weld ~= state.weld then
			state.weld = weld
			state.base = if weld then weld.C1 else nil
		end
		if weld and state.base then
			local share = if Settings.reduceMotion then WeaponFx.REDUCED_RECOIL else 1
			local lowered = if Settings.reduceMotion then 0 else state.equip * state.equip * WeaponFx.EQUIP.DROP
			local offset = CFrame.new(0, 0, fx.kick * state.kick * share)
				* CFrame.Angles(math.rad(fx.rise * state.kick * share - lowered), 0, 0)
			weld.C1 = (state.base :: CFrame) * offset:Inverse()
		end
		-- The tank's slow glow.
		for part, base in state.gas do
			if Settings.reduceMotion then
				part.Transparency = base
			else
				local wave = 0.5 + 0.5 * math.sin(clockTime * 2 * math.pi / WeaponFx.IDLE.PERIOD)
				part.Transparency = math.min(1, base + WeaponFx.IDLE.GLOW * wave)
			end
		end
	end
	cameraKick *= math.exp(-dt / 0.12)
	if cameraKick < 0.01 then
		cameraKick = 0
	end
end

-- The camera kick, after the camera has moved this frame.
local function kickCamera()
	if cameraKick > 0 and not Settings.reduceMotion then
		local camera = workspace.CurrentCamera
		if camera then
			camera.CFrame *= CFrame.Angles(math.rad(cameraKick), 0, 0)
		end
	end
end

function WeaponFxController.cameraKick(): number
	return cameraKick
end

local function watch(other: Player)
	local function onCharacter(character: Model)
		local function onChild(child: Instance)
			if child:IsA("Tool") and child.Name == "HeldWeapon" then
				WeaponFxController.track(child)
			end
		end
		character.ChildAdded:Connect(onChild)
		for _, child in character:GetChildren() do
			onChild(child)
		end
	end
	other.CharacterAdded:Connect(onCharacter)
	if other.Character then
		onCharacter(other.Character)
	end
end

local function onCombatEvent(event: { [string]: any })
	if event.kind == "shot" and type(event.shooter) == "number" then
		if event.shooter ~= player.UserId then
			WeaponFxController.fired(event.shooter)
		end
		-- A shot that stopped short of its range hit something.
		if typeof(event.from) == "Vector3" and typeof(event.to) == "Vector3" then
			local tool = heldBy(event.shooter)
			local weapon = tool and WeaponConfig.weapons[tool:GetAttribute("Weapon") :: any]
			local range = if weapon then weapon.range else math.huge
			if (event.to - event.from).Magnitude < range - 0.5 then
				local art = weapon and WeaponArt[weapon.id]
				local fx = weapon and WeaponFx.weapons[weapon.id]
				local color = if art and art.roles.Gas then art.roles.Gas.color else Color3.fromRGB(180, 255, 90)
				WeaponFxController.impact(event.to, color, event.to - event.from, if fx then fx.shot.splat else nil)
			end
		end
	elseif event.kind == "lob" and type(event.shooter) == "number" and event.shooter ~= player.UserId then
		WeaponFxController.fired(event.shooter)
	end
end

function WeaponFxController.start()
	if started then
		return
	end
	started = true
	-- The impact pool: one invisible anchor, a few attachments.
	local anchor = Instance.new("Part")
	anchor.Name = "WeaponFx"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new()
	anchor.Parent = workspace
	impactAnchor = anchor
	for i = 1, WeaponFx.IMPACT.pool do
		local attachment = Instance.new("Attachment")
		attachment.Name = `Impact{i}`
		attachment.Parent = anchor
		table.insert(impacts, attachment)
	end
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerAdded:Connect(watch)
	local combatEvent = ClientState.remote("CombatEvent") :: RemoteEvent
	combatEvent.OnClientEvent:Connect(function(event)
		if type(event) == "table" then
			onCombatEvent(event)
		end
	end)
	RunService.RenderStepped:Connect(WeaponFxController.step)
	pcall(function()
		RunService:BindToRenderStep("FartWarsCameraKick", Enum.RenderPriority.Camera.Value + 1, kickCamera)
	end)
end

return WeaponFxController
