-- The weapons in motion, for every player's gun on this screen (WeaponFx):
--   * the look: each gun is dressed in the Blender meshes as soon as this
--     client has built them (WeaponSkin)
--   * equip: a new gun swings up from below, and a light one twirls
--   * recoil: each shot kicks the gun back and up, a little to a side, and
--     springs settle it; the Stink Lobber's kick is its throw
--   * idle and walking: the gun sways, and bobs with its holder's steps
--   * moving parts: the pump pumps, the gauge's needle drops with the
--     pressure and climbs back, the Stink Lobber's bomb is gone when thrown
--     and grows back as it reloads
--   * the gas: the tank and vents glow slowly and flash on each shot;
--     after a burst of shots the barrel smokes
--   * the muzzle: puffs (or the Spritzer's droplets) in the gun's gas
--     colour, sparks, a flash of light, a shock ring, and for your own
--     shots a camera kick
--   * impacts: a puff, sparks, a flash of light, a splat and a ring where
--     a shot hits something; a player your shot hits flashes white
--   * the shots themselves (ShotFx): the bolt from the muzzle to where the
--     shot stopped, the muzzle's burst, and a splat where it hit
-- It all happens on each client from the shots the server announces (and
-- your own as you fire), by moving the gun's grip weld and its parts'
-- welds locally; nothing here changes what the server sees. Reduce motion
-- keeps a little recoil and none of the other movement; reduced effects
-- halve the particles and drop the lights and smoke; and no more than
-- MAX_PARTICLES_PER_FRAME are emitted a frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponFx = require(Shared.Config.WeaponFx)
local WeaponArt = require(Shared.Config.WeaponArt)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ArtAssets = require(Shared.Config.ArtAssets)
local MeshBuilder = require(Shared.MeshBuilder)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Settings = require(Client.Settings)
local ShotFx = require(Client.ShotFx)
local WeaponSkin = require(Client.WeaponSkin)

local WeaponFxController = {}

-- A moving part's weld, where it rests, and its part's own size and
-- see-through.
type Move = { weld: Weld, rest: CFrame, part: BasePart, size: Vector3, transparency: number }
type State = {
	weapon: string,
	weld: Weld?,
	base: CFrame?,
	-- Recoil springs: the kick (back and up together) and the twist to a
	-- side (yaw) and round the barrel (roll), each with its speed.
	kick: number,
	kickSpeed: number,
	yaw: number,
	yawSpeed: number,
	roll: number,
	rollSpeed: number,
	equip: number,
	-- Seconds since the last shot, the pressure (1 full) and barrel heat.
	sinceShot: number,
	pressure: number,
	heat: number,
	-- How bright the gas is flashing (1 just fired), the needle's jolt,
	-- the walk's phase and how much of a walk it is, and a phase of its
	-- own so guns don't sway together.
	flash: number,
	jolt: number,
	stride: number,
	walking: number,
	phase: number,
	moves: { [string]: { Move } },
	gas: { [BasePart]: { transparency: number, color: Color3 } },
	dressed: boolean,
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
local hitFlash: Highlight? = nil
local hitUntil = 0
local started = false
local WHITE = Color3.new(1, 1, 1)

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

-- A light that flashes for `seconds` each time flashLight is called.
local function light(parent: Instance, name: string, color: Color3, brightness: number, range: number): PointLight
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("PointLight") then
		return existing
	end
	local made = Instance.new("PointLight")
	made.Name = name
	made.Color = color
	made.Brightness = brightness
	made.Range = range
	made.Shadows = false
	made.Enabled = false
	made.Parent = parent
	return made
end

local function flashLight(lamp: PointLight, seconds: number)
	lamp.Enabled = true
	local token = ((lamp:GetAttribute("Token") or 0) :: number) + 1
	lamp:SetAttribute("Token", token)
	task.delay(seconds, function()
		if lamp:GetAttribute("Token") == token then
			lamp.Enabled = false
		end
	end)
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

-- Finds what to animate on a gun: its moving parts' welds and its gas.
local function scan(tool: Tool, state: State)
	local moves: { [string]: { Move } } = {}
	for _, weld in tool:GetDescendants() do
		if weld:IsA("Weld") and weld.Name == "Move" then
			local part = weld.Part1
			local name = weld:GetAttribute("Part")
			if part and type(name) == "string" and not part:GetAttribute("Hidden") then
				local rest = weld:GetAttribute("Rest")
				local list = moves[name] or {}
				moves[name] = list
				table.insert(list, {
					weld = weld,
					rest = if typeof(rest) == "CFrame" then rest else weld.C0,
					part = part,
					size = part.Size,
					transparency = part.Transparency,
				})
			end
		end
	end
	local gas = {}
	for _, part in WeaponSkin.parts(tool) do
		if part:GetAttribute("Gas") then
			gas[part] = { transparency = part.Transparency, color = part.Color }
		end
	end
	state.moves = moves
	state.gas = gas
end

-- Dresses `tool` in the meshes if they're built here; rescans it if so. A
-- gun of imported meshes needs none.
local function dress(tool: Tool, state: State)
	if state.dressed then
		return
	end
	local source = tool:GetAttribute("ArtSource")
	if source ~= nil and source ~= "pieces" then
		state.dressed = true
	elseif WeaponSkin.dress(tool) then
		state.dressed = true
		scan(tool, state)
	end
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
	local state: State = {
		weapon = weapon,
		weld = nil,
		base = nil,
		kick = 0,
		kickSpeed = 0,
		yaw = 0,
		yawSpeed = 0,
		roll = 0,
		rollSpeed = 0,
		equip = if Settings.reduceMotion then 0 else 1,
		sinceShot = math.huge,
		pressure = 1,
		heat = 0,
		flash = 0,
		jolt = 0,
		stride = 0,
		walking = 0,
		phase = math.random() * 2 * math.pi,
		moves = {},
		gas = {},
		dressed = false,
	}
	WeaponFxController.states[tool] = state
	scan(tool, state)
	dress(tool, state)
	return state
end

local function heldBy(userId: number): Tool?
	local shooter = Players:GetPlayerByUserId(userId)
	local character = shooter and shooter.Character
	local tool = character and character:FindFirstChild("HeldWeapon")
	return if tool and tool:IsA("Tool") then tool else nil
end

local function gasColor(weapon: string): Color3
	local art = WeaponArt[weapon]
	return if art and art.roles.Gas then art.roles.Gas.color else WeaponConfig.weapons[weapon].tracerColor
end

-- A shot from `userId`'s gun: recoil, the moving parts, the muzzle's
-- particles, burst, ring and flash, and your own camera kick.
function WeaponFxController.fired(userId: number)
	local tool = heldBy(userId)
	local state = tool and WeaponFxController.track(tool)
	if not (tool and state) then
		return
	end
	local fx = WeaponFx.weapons[state.weapon]
	state.kick = math.min(WeaponFx.MAX_RECOIL, state.kick + 1)
	state.yawSpeed += (math.random() * 2 - 1) * fx.twist * fx.frequency * 6
	state.rollSpeed += (math.random() * 2 - 1) * fx.twist * fx.frequency * 4
	state.sinceShot = 0
	state.pressure = math.max(0, state.pressure - WeaponFx.PRESSURE.DROP)
	state.heat = math.min(WeaponFx.HEAT.MAX, state.heat + WeaponFx.HEAT.SHOT)
	state.flash = 1
	state.jolt = (math.random() * 2 - 1) * 8
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		local color = gasColor(state.weapon)
		local spec = fx.muzzle
		local particles = emitter(muzzle, "MuzzleFx", spec.texture, color, spec.size, spec.speed, spec.lifetime, spec.spread, spec.gravity)
		emit(particles, spec.count)
		if fx.sparks then
			local sparks = emitter(muzzle, "MuzzleSparks", "spark", Color3.fromRGB(255, 240, 180), 0.35, 14, 0.2, 25, nil)
			emit(sparks, fx.sparks)
		end
		local handle = muzzle.Parent
		if handle and handle:IsA("BasePart") then
			-- The burst and the ring, facing down the barrel (the muzzle's +Y).
			local world = handle.CFrame * muzzle.CFrame
			local facing = CFrame.lookAt(world.Position, world.Position + world.UpVector)
			ShotFx.burst(facing, color, fx.shot.burst)
			ShotFx.ring(facing * CFrame.new(0, 0, -0.15), color, fx.shot.ring)
		end
		if fx.flash and not (Settings.reduceMotion or reducedEffects()) then
			flashLight(light(muzzle, "Flash", color, fx.flash.brightness, fx.flash.range), fx.flash.seconds)
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

-- Where a shot hit something: a puff, sparks and a flash of light, and
-- (given the way the shot came and the weapon's sizes) a splat and a ring
-- on the surface.
function WeaponFxController.impact(position: Vector3, color: Color3, direction: Vector3?, splat: number?, ring: number?)
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
	local sparks = emitter(attachment, "Sparks", "spark", Color3.fromRGB(255, 245, 200), 0.3, 14, 0.3, 180, 30)
	emit(sparks, spec.sparks)
	if not (Settings.reduceMotion or reducedEffects()) then
		local lamp = light(attachment, "Flash", color, 2, spec.light)
		lamp.Color = color
		flashLight(lamp, spec.LIGHT_SECONDS)
	end
	if direction and splat then
		ShotFx.splat(position, direction, color, splat, ring)
	end
end

-- A player your shot hit flashes white for a moment.
function WeaponFxController.hit(userId: number)
	local victim = Players:GetPlayerByUserId(userId)
	local character = victim and victim.Character
	if not character or reducedEffects() then
		return
	end
	local highlight = hitFlash
	if not (highlight and highlight.Parent) then
		local made = Instance.new("Highlight")
		made.Name = "HitFlash"
		made.FillColor = WHITE
		made.OutlineTransparency = 1
		made.DepthMode = Enum.HighlightDepthMode.Occluded
		made.Enabled = false
		made.Parent = workspace
		hitFlash = made
		highlight = made
	end
	local flash = highlight :: Highlight
	flash.Adornee = character
	flash.FillTransparency = WeaponFx.HIT.TRANSPARENCY
	flash.Enabled = true
	hitUntil = clockTime + WeaponFx.HIT.SECONDS
end

-- Damped springs, a few small steps at a time so a slow frame can't blow
-- up: returns where `x` (moving at `v`) is after `dt`.
local function spring(x: number, v: number, dt: number, frequency: number, damping: number): (number, number)
	local w = 2 * math.pi * frequency
	local steps = math.max(1, math.ceil(dt * 240))
	local h = dt / steps
	for _ = 1, steps do
		v += (-w * w * x - 2 * damping * w * v) * h
		x += v * h
	end
	return x, v
end

-- Out past 1 a little, then back: an easing for the swing up.
local function overshoot(t: number): number
	local c = 1.70158
	local u = t - 1
	return 1 + (c + 1) * u * u * u + c * u * u
end

-- Where a moving part is now: the turn or slide round its pivot, its
-- scale, and whether it shows.
local function motion(state: State, spec: WeaponFx.Motion): (CFrame, number, boolean)
	local calm = Settings.reduceMotion
	if spec.kind == "slide" then
		local u = state.sinceShot / spec.seconds
		if calm or u >= 1 then
			return CFrame.identity, 1, true
		end
		-- Back fast, home slower.
		local out = if u < 0.35 then math.sin(u / 0.35 * math.pi / 2) else math.cos((u - 0.35) / 0.65 * math.pi / 2)
		return CFrame.new(0, 0, spec.amount * out), 1, true
	elseif spec.kind == "swing" then
		local angle = spec.amount * (1 - state.pressure) + (if calm then 0 else state.jolt)
		return CFrame.Angles(math.rad(angle), 0, 0), 1, true
	elseif spec.kind == "reload" then
		local since = state.sinceShot
		local growFrom = spec.seconds - spec.amount
		if since < growFrom then
			return CFrame.identity, 1, false
		elseif since < spec.seconds and not calm then
			return CFrame.identity, math.max(0.05, overshoot((since - growFrom) / spec.amount)), true
		end
	end
	return CFrame.identity, 1, true
end

local function animateParts(state: State, fx: WeaponFx.Weapon)
	local art = WeaponArt[state.weapon]
	for name, list in state.moves do
		local spec = fx.parts and fx.parts[name]
		if not spec then
			continue
		end
		local mesh = art.meshes[spec.pivot or name]
		local pivot = if mesh then mesh.center else Vector3.zero
		local offset, scale, shows = motion(state, spec)
		local around = CFrame.new(pivot) * offset * CFrame.new(-pivot)
		for _, move in list do
			if not move.weld.Parent then
				continue
			end
			local rest = move.rest
			if scale ~= 1 then
				local at = pivot + (rest.Position - pivot) * scale
				move.weld.C0 = around * (CFrame.new(at) * (rest - rest.Position))
			else
				move.weld.C0 = around * rest
			end
			move.part.Size = move.size * scale
			move.part.Transparency = if shows then move.transparency else 1
		end
	end
end

-- One frame: every gun's springs, sway, bob, parts and gas; the smoke;
-- the hit flash; the camera kick settling.
function WeaponFxController.step(dt: number)
	frameParticles = 0
	clockTime += dt
	ShotFx.step(dt)
	local calm = Settings.reduceMotion
	local equipSeconds = WeaponFx.EQUIP.SECONDS
	for tool, state in WeaponFxController.states do
		if not tool.Parent then
			WeaponFxController.states[tool] = nil
			continue
		end
		local fx = WeaponFx.weapons[state.weapon]
		state.kick, state.kickSpeed = spring(state.kick, state.kickSpeed, dt, fx.frequency, fx.damping)
		state.yaw, state.yawSpeed = spring(state.yaw, state.yawSpeed, dt, fx.frequency, fx.damping)
		state.roll, state.rollSpeed = spring(state.roll, state.rollSpeed, dt, fx.frequency, fx.damping)
		if math.abs(state.kick) < 0.002 and math.abs(state.kickSpeed) < 0.02 then
			state.kick, state.kickSpeed = 0, 0
		end
		state.equip = math.max(0, state.equip - dt / equipSeconds)
		state.sinceShot += dt
		state.pressure = math.min(1, state.pressure + WeaponFx.PRESSURE.RECOVER * dt)
		state.heat = math.max(0, state.heat - WeaponFx.HEAT.COOL * dt)
		state.flash = if state.flash > 0.01 then state.flash * math.exp(-dt / 0.08) else 0
		state.jolt *= math.exp(-dt / 0.15)
		-- Walking: how fast its holder is going.
		local character = tool.Parent
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local velocity = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity else nil
		local speed = if typeof(velocity) == "Vector3" then Vector3.new(velocity.X, 0, velocity.Z).Magnitude else 0
		local pace = math.clamp(speed / 16, 0, 1.3)
		state.walking += (pace - state.walking) * math.min(1, dt * 8)
		state.stride += dt * WeaponFx.WALK.RATE * math.max(pace, 0.3) * math.pi
		if not state.dressed and MeshBuilder.ready(state.weapon) then
			dress(tool, state)
		end
		local weld = gripWeld(tool)
		if weld ~= state.weld then
			state.weld = weld
			state.base = if weld then weld.C1 else nil
		end
		if weld and state.base then
			local share = if calm then WeaponFx.REDUCED_RECOIL else 1
			local kick = state.kick * share
			local lowered, twirl, swayPitch, swayYaw, bob, bobRoll = 0, 0, 0, 0, 0, 0
			if not calm then
				local up = 1 - state.equip
				lowered = WeaponFx.EQUIP.DROP * (1 - overshoot(up))
				twirl = fx.twirl * (1 - up) ^ 3
				local sway = (clockTime + state.phase) * 2 * math.pi / WeaponFx.IDLE.SWAY_PERIOD
				swayPitch = WeaponFx.IDLE.SWAY * math.sin(sway)
				swayYaw = WeaponFx.IDLE.SWAY * 0.7 * math.sin(sway * 0.5 + 1.3)
				bob = -WeaponFx.WALK.BOB * state.walking * math.abs(math.sin(state.stride))
				bobRoll = WeaponFx.WALK.ROLL * state.walking * math.sin(state.stride)
			end
			local offset = CFrame.new(0, bob, fx.kick * kick)
				* CFrame.Angles(
					math.rad(fx.rise * kick - lowered + swayPitch),
					math.rad(state.yaw * share + swayYaw),
					math.rad(state.roll * share + bobRoll + twirl)
				)
			weld.C1 = (state.base :: CFrame) * offset:Inverse()
		end
		animateParts(state, fx)
		-- The gas: a slow glow, bright on every shot.
		for part, rest in state.gas do
			if calm then
				part.Transparency = rest.transparency
				part.Color = rest.color
			else
				local wave = 0.5 + 0.5 * math.sin(clockTime * 2 * math.pi / WeaponFx.IDLE.PERIOD)
				part.Transparency = math.min(1, rest.transparency + WeaponFx.IDLE.GLOW * wave * (1 - state.flash))
				part.Color = rest.color:Lerp(WHITE, 0.45 * state.flash)
			end
		end
		-- A hot barrel smokes.
		local muzzle = tool:FindFirstChild("Muzzle", true)
		if muzzle and muzzle:IsA("Attachment") then
			local over = state.heat - 1
			local smoke = muzzle:FindFirstChild("Smoke") :: ParticleEmitter?
			if over > 0 and not (calm or reducedEffects()) then
				if not smoke then
					local made = emitter(muzzle, "Smoke", "puff", Color3.fromRGB(205, 210, 196), 0.35, 1.2, 1.1, 20, -2)
					made.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
					made.Drag = 1
					smoke = made
				end
				(smoke :: ParticleEmitter).Rate = over * WeaponFx.HEAT.SMOKE
			elseif smoke then
				smoke.Rate = 0
			end
		end
	end
	if hitFlash and hitFlash.Enabled then
		local left = hitUntil - clockTime
		if left <= 0 then
			hitFlash.Enabled = false
		else
			local t = 1 - left / WeaponFx.HIT.SECONDS
			hitFlash.FillTransparency = WeaponFx.HIT.TRANSPARENCY + (1 - WeaponFx.HIT.TRANSPARENCY) * t
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
				local fx = weapon and WeaponFx.weapons[weapon.id]
				local color = if weapon then gasColor(weapon.id) else Color3.fromRGB(180, 255, 90)
				WeaponFxController.impact(event.to, color, event.to - event.from, if fx then fx.shot.splat else nil, if fx then fx.shot.ring else nil)
			end
		end
	elseif event.kind == "lob" and type(event.shooter) == "number" and event.shooter ~= player.UserId then
		WeaponFxController.fired(event.shooter)
	elseif event.kind == "hit" and type(event.victim) == "number" and not event.blocked then
		WeaponFxController.hit(event.victim)
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
	-- Build the shot meshes now, so the first shots already have them.
	MeshBuilder.request("Shots")
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerAdded:Connect(watch)
	-- Guns already held when a weapon's meshes are built get dressed.
	MeshBuilder.built:Connect(function(set: string)
		for tool, state in WeaponFxController.states do
			if state.weapon == set and tool.Parent then
				dress(tool, state)
			end
		end
	end)
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
