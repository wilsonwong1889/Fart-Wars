-- The weapons' Blender art in the game, with one client:
--   * WeaponArt (generated from the Blender models) covers every weapon:
--     roles, meshes within Roblox's triangle limits, pieces, the muzzle in
--     front of the grip
--   * the held gun: built from the Blender pieces until the meshes are
--     imported (an invisible Handle at the grip, every part welded,
--     coloured by role, never in the way, a Muzzle attachment); with the
--     meshes in ReplicatedStorage.Assets.Weapons, made of them, sized and
--     placed from the art whatever the import's scale; a mesh imported on
--     its side, or a missing one, falls back to the pieces and says why
--   * animations on every client: the gun comes up when equipped, kicks
--     back and up on each shot and settles; the Thunderclapper's flash and
--     its shooter's camera kick; reduce motion keeps a little recoil and
--     none of the rest; the tank glows
--   * effects: muzzle particles in the gas colour, impacts where shots
--     hit, explosion smoke and rings; a per-frame particle budget
--   * shots: a bolt from the gun's muzzle (not the head) that flies on
--     and goes into its target, a hot core in a glow; the muzzle's burst,
--     facing down the barrel; a splat stuck flat to a wall it hits, never
--     on a player; reduced effects keep only the bolt; the Blender meshes
--     once imported (a sideways one is refused)
--   * screens: the hotbar's 3D icons (kept between renders) and the
--     locker's turning previews (still with reduce motion); selftest
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local Shared = ReplicatedStorage.Shared
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponArt = require(Shared.Config.WeaponArt)
local WeaponFx = require(Shared.Config.WeaponFx)
local ArtAssets = require(Shared.Config.ArtAssets)
local WeaponModel = require(Shared.WeaponModel)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TestControls = require(server.TestControls)
local Data = require(server.Services.DataService)
local Remotes = ReplicatedStorage.Remotes
local HttpService = game:GetService("HttpService")
local saved = {}
Data.setStore({
	UpdateAsync = function(_, key, transform)
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})

-- The art covers every weapon.
for _, id in WeaponConfig.order do
	local art = WeaponArt[id]
	check(art and WeaponFx.weapons[id], `{id} has art and effects`)
	check(art.muzzle.Z < -1 and math.abs(art.muzzle.X) < 0.01, `{id}'s muzzle is in front of the grip`)
	check(art.roles.Body and art.roles.Grip and art.roles.Gas and art.roles.Gas.material == Enum.Material.Neon, `{id}'s roles`)
	for role, mesh in art.meshes do
		check(art.roles[role], `{id}'s {role} mesh has a colour`)
		check(mesh.triangles > 0 and mesh.triangles < 10000, `{id}'s {role} mesh is within Roblox's limits ({mesh.triangles} triangles)`)
		check(mesh.size.X > 0 and mesh.size.Y > 0 and mesh.size.Z > 0, `{id}'s {role} mesh has a size`)
	end
	check(#art.pieces >= 10, `{id} is built from {#art.pieces} pieces`)
end

-- The held gun, from the pieces.
local tool = WeaponModel.tool("GasBlaster", "Gas Blaster")
local handle = tool:FindFirstChild("Handle") :: BasePart
check(handle and handle.Transparency == 1 and handle.CFrame == CFrame.new(), "an invisible Handle at the grip")
local standins = 0
for _, piece in WeaponArt.GasBlaster.pieces do
	standins += if piece.standin ~= false then 1 else 0
end
local parts, welds = 0, 0
for _, part in tool:GetChildren() do
	if part:IsA("BasePart") and part ~= handle then
		parts += 1
		check(not part.CanCollide and not part.CanQuery and not part.CanTouch and part.Massless, `{part.Name} is never in the way`)
		check(part.Color == WeaponArt.GasBlaster.roles[part.Name].color, `{part.Name} in its role's colour`)
	end
end
for _, weld in handle:GetChildren() do
	welds += if weld:IsA("WeldConstraint") then 1 else 0
end
check(parts == standins and welds == parts, `every piece there and welded ({parts})`)
local muzzle = handle:FindFirstChild("Muzzle") :: Attachment
check(muzzle and (muzzle.CFrame.Position - WeaponArt.GasBlaster.muzzle).Magnitude < 1e-3, "a Muzzle attachment at the barrel's end")
check(muzzle.CFrame.UpVector:Dot(Vector3.new(0, 0, -1)) > 0.99, "pointing down the barrel")
check(tool:GetAttribute("ArtSource") == "pieces", "the stand-in until the meshes are imported")

-- Imported meshes.
local assets = ReplicatedStorage:FindFirstChild("Assets")
check(assets and assets:FindFirstChild("Weapons"), "ReplicatedStorage.Assets.Weapons is there for the imports")
local function import(id: string, rotate: string?, skip: string?)
	local model = Instance.new("Model")
	model.Name = id
	for role, mesh in WeaponArt[id].meshes do
		if role ~= skip then
			local part = Instance.new("MeshPart")
			part.Name = role
			-- Imported at three times the size, somewhere else.
			local size = mesh.size * 3
			if role == rotate then
				size = Vector3.new(size.Z, size.Y, size.X)
			end
			part.MeshSize = size
			part.Size = size
			part.CFrame = CFrame.new(40, 10, 40)
			part.Parent = model
		end
	end
	model.Parent = assets.Weapons
	return model
end
import("Spritzer")
local found, why = WeaponModel.imported("Spritzer")
check(found and why == "imported", "imported meshes are found")
local spritzer = WeaponModel.tool("Spritzer")
check(spritzer:GetAttribute("ArtSource") == "mesh", "and the gun is made of them")
for role, mesh in WeaponArt.Spritzer.meshes do
	local part = spritzer:FindFirstChild(role) :: BasePart
	check(part and part:IsA("MeshPart"), `the {role} MeshPart`)
	check((part.Size - mesh.size).Magnitude < 1e-3 and (part.CFrame.Position - mesh.center).Magnitude < 1e-3, `{role} sized and placed from the art, whatever the import's scale`)
	check(part.Color == WeaponArt.Spritzer.roles[role].color and part.Material == WeaponArt.Spritzer.roles[role].material, `{role} coloured from the art`)
end
import("Thunderclapper", "Body")
local rotated, reason = WeaponModel.imported("Thunderclapper")
check(rotated == nil and string.find(reason, "wrong way round", 1, true), "a mesh imported on its side: " .. reason)
check(WeaponModel.tool("Thunderclapper"):GetAttribute("ArtSource") == "pieces", "falls back to the pieces")
import("StinkLobber", nil, "Gas")
local missing, missingWhy = WeaponModel.imported("StinkLobber")
check(missing == nil and missingWhy == "no Gas MeshPart", "a missing mesh: " .. missingWhy)
local _, report = TestControls.selftest(nil)
check(type(report) == "string", "selftest reports on the art")

-- Animations, on a client.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Client = game.StarterPlayer.StarterPlayerScripts.Client
local Fx = require(Client.Controllers.WeaponFxController)
local Effects = require(Client.Controllers.EffectsController)
local Hotbar = require(Client.Controllers.HotbarController)
local Locker = require(Client.Controllers.LockerController)
local Settings = require(Client.Settings)
local ada = Instance.new("Player")
ada.Name = "Ada"
ada.UserId = 2
ada.Parent = Players
task.wait(0.2)
Lifecycle.requestPlay(ada, nil)
Lifecycle.requestPlay(me, nil)
task.wait(0.5)

-- Roblox's grip weld (the specs' avatars don't make one).
local function grip(player: Player): Weld
	local character = player.Character :: Model
	local hand = character:FindFirstChild("RightHand") or Instance.new("Part")
	hand.Name = "RightHand"
	hand.Parent = character
	local old = hand:FindFirstChild("RightGrip")
	if old then
		old:Destroy()
	end
	local weld = Instance.new("Weld")
	weld.Name = "RightGrip"
	weld.Part0 = hand :: BasePart
	weld.Part1 = (character:FindFirstChild("HeldWeapon") :: Tool):FindFirstChild("Handle") :: BasePart
	weld.C1 = CFrame.new()
	weld.Parent = hand
	return weld
end
local function frames(seconds: number, dt: number?)
	local step = dt or 1 / 60
	for _ = 1, math.ceil(seconds / step) do
		RunService.RenderStepped:Fire(step)
	end
end
local adaTool = ada.Character:FindFirstChild("HeldWeapon") :: Tool
check(adaTool and Fx.states[adaTool], "every player's gun is animated here")
check(adaTool:GetAttribute("ArtSource") == "pieces", "Ada's Gas Blaster: the Blender stand-in")
local weld = grip(ada)
frames(1 / 60)
local lowered = weld.C1:Inverse()
check(lowered.LookVector.Y < -0.3, "a new gun starts lowered")
frames(0.5)
check((weld.C1.Position).Magnitude < 1e-3 and weld.C1.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.999, "and comes up into the hand")

-- Recoil.
local emitted = Fx.emitted
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -20) })
task.wait()
frames(1 / 60)
local kicked = weld.C1:Inverse()
check(kicked.Position.Z > 0.1 and kicked.LookVector.Y > 0.05, "a shot kicks the gun back and up")
check(Fx.emitted > emitted, "puffs from the muzzle")
local muzzleFx = adaTool.Handle.Muzzle:FindFirstChild("MuzzleFx") :: ParticleEmitter
check(muzzleFx and muzzleFx.Texture == ArtAssets.effect("puff"), "with the puff texture (Roblox's until the Blender one is uploaded)")
check(muzzleFx.Color.Keypoints[1].Value == WeaponArt.GasBlaster.roles.Gas.color, "in the gas colour")
frames(0.8)
check(weld.C1.Position.Magnitude < 0.01, "and it settles")
local impacts = workspace:FindFirstChild("WeaponFx")
check(impacts and impacts:FindFirstChild("Impact1") and (impacts.Impact1.WorldPosition - Vector3.new(0, 5, -20)).Magnitude < 1e-3, "a puff where the shot hit")
local impactAt = impacts.Impact1.WorldPosition
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -WeaponConfig.weapons.GasBlaster.range) })
task.wait()
check(impacts.Impact2.WorldPosition.Magnitude < 1e-3 and (impacts.Impact1.WorldPosition - impactAt).Magnitude < 1e-3, "a shot that hit nothing leaves no puff")

-- The shots (ShotFx): a bolt from the muzzle, a burst, a splat.
local ShotFx = require(Client.ShotFx)
local ShotArt = require(Shared.Config.ShotArt)
local SHOT = WeaponFx.SHOT
local blaster = WeaponFx.weapons.GasBlaster.shot
frames(1)
local handle = adaTool:FindFirstChild("Handle") :: BasePart
local muzzleAt = handle.CFrame * (handle:FindFirstChild("Muzzle") :: Attachment).CFrame
local from = muzzleAt.Position + Vector3.new(0, 1.5, 0)
local direction = Vector3.new(0, 0, -1)
local bursts = 0
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = from, to = from + direction * WeaponConfig.weapons.GasBlaster.range })
task.wait()
local bolt: BasePart? = nil
for _, part in ShotFx.tracers do
	if part.Transparency == 0 then
		bolt = part
	end
end
check(bolt and bolt.Name == "Tracer" and bolt.Parent == workspace and bolt:GetAttribute("ArtSource") == "part", "a shot's bolt shows at once (a glowing part until the mesh is imported)")
local boltPart = bolt :: BasePart
local back = boltPart.Position - boltPart.CFrame.LookVector * boltPart.Size.Z / 2
check((back - muzzleAt.Position).Magnitude < 0.05, "from the gun's muzzle, not the shooter's head")
check(math.abs(boltPart.Size.Z - blaster.length) < 1e-3 and math.abs(boltPart.Size.X - blaster.width) < 1e-3, "the Gas Blaster's bolt: its width, and its length")
local shotDirection = (from + direction * WeaponConfig.weapons.GasBlaster.range - muzzleAt.Position).Unit
check(boltPart.CFrame.LookVector:Dot(shotDirection) > 0.999, "pointing where the shot went")
local glow = boltPart:FindFirstChild("Glow") :: BasePart
check(glow and math.abs(glow.Transparency - SHOT.GLOW_TRANSPARENCY) < 1e-3 and glow.Size.X > boltPart.Size.X * 2, "in a softer glow")
local gas = WeaponArt.GasBlaster.roles.Gas.color
-- (Someone else's shots are in their team's colour, or their tracer's.)
check(boltPart.Color.R + boltPart.Color.G + boltPart.Color.B > glow.Color.R + glow.Color.G + glow.Color.B, "a hot core in the shot's colour")
for _, part in ShotFx.bursts do
	if part.Transparency < 1 then
		bursts += 1
		check((part.Position - muzzleAt.Position).Magnitude < 0.05, "the burst at the muzzle")
		check(part.CFrame.LookVector:Dot(muzzleAt.UpVector) > 0.999, "facing down the barrel")
		check(part.Color.G >= gas.G - 1e-3, "in the gas colour, lightened")
	end
end
check(bursts == 1, "the muzzle bursts")
local startedAt = boltPart.Position
frames(0.05)
check((boltPart.Position - startedAt):Dot(shotDirection) > blaster.speed * 0.04, "the bolt flies on")
local _, shown = ShotFx.showing()
frames(SHOT.BURST_SECONDS)
local _, after = ShotFx.showing()
check(after < shown, "the burst is gone in a moment")
frames(WeaponConfig.weapons.GasBlaster.range / blaster.speed + 0.1)
check(boltPart.Transparency == 1 and glow.Transparency == 1 and (ShotFx.showing()) == 0, "and the bolt, once it's gone into its target")

-- A splat where it hits a wall, facing out of it; none on a player.
local wall = Instance.new("Part")
wall.Name = "TestWall"
wall.Anchored = true
wall.Size = Vector3.new(30, 30, 2)
wall.CFrame = CFrame.new(0, 5, -41)
wall.Parent = workspace
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -40) })
task.wait()
local splat: BasePart? = nil
for _, part in ShotFx.splats do
	if part.Transparency < 1 then
		splat = part
	end
end
check(splat and splat:GetAttribute("ArtSource") == "part", "a splat where it hit the wall")
local splatPart = splat :: BasePart
check((splatPart.Position - Vector3.new(0, 5, -39.96)).Magnitude < 0.01, "on its face")
check(math.abs(splatPart.CFrame.RightVector.Z) > 0.999, "flat to it (a disc, facing out)")
check(splatPart.Color == gas, "in the gas colour")
frames(SHOT.SPLAT_SECONDS * 0.5)
check(splatPart.Transparency < 0.5, "it stays a moment")
frames(SHOT.SPLAT_SECONDS * 0.6)
check(splatPart.Transparency == 1, "then fades")
local root = (me.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = root.Position + Vector3.new(0, 0, 20), to = root.Position + Vector3.new(0, 0, 0.9) })
task.wait()
local onPlayer = 0
for _, part in ShotFx.splats do
	onPlayer += if part.Transparency < 1 then 1 else 0
end
check(onPlayer == 0, "no splat on a player")
frames(1)

-- Reduced effects: no bursts or splats, but the bolt still shows.
Settings.reducedEffects = true
Fx.fired(ada.UserId)
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -40) })
task.wait()
local flying, flashing = ShotFx.showing()
check(flying == 1 and flashing == 0, "reduced effects: the bolt, nothing else")
Settings.reducedEffects = false
frames(1)

-- The Blender meshes, once imported.
local effectsFolder = assets:FindFirstChild("Effects")
check(effectsFolder, "ReplicatedStorage.Assets.Effects is there for the imports")
for name in ShotArt do
	local found, why = WeaponModel.effect(name)
	check(found == nil and why == "not imported", `{name}: not imported yet`)
end
for name, art in ShotArt do
	local mesh = Instance.new("MeshPart")
	mesh.Name = name
	mesh.MeshSize = art.size * 2
	mesh.Size = art.size * 2
	mesh.Parent = effectsFolder
end
ShotFx.clear()
Fx.fired(ada.UserId)
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -40) })
task.wait()
local meshBolt, meshBurst, meshSplat
for _, part in ShotFx.tracers do
	meshBolt = if part.Transparency == 0 then part else meshBolt
end
for _, part in ShotFx.bursts do
	meshBurst = if part.Transparency < 1 then part else meshBurst
end
for _, part in ShotFx.splats do
	meshSplat = if part.Transparency < 1 then part else meshSplat
end
check(meshBolt and meshBolt:IsA("MeshPart") and meshBolt:GetAttribute("ArtSource") == "mesh", "the bolt is the Blender gas bolt")
check(meshBolt.Size.X == blaster.width and meshBolt:FindFirstChild("Glow"):IsA("MeshPart"), "sized to the weapon, glow and all")
check(meshBurst and meshBurst:IsA("MeshPart"), "the burst is the Blender burst")
local burstFull = ShotArt.MuzzleBurst.size * (blaster.burst / ShotArt.MuzzleBurst.size.X)
frames(SHOT.BURST_SECONDS * 0.6)
check((meshBurst.Size - burstFull).Magnitude < 1e-3, "out to the weapon's burst size")
check(meshSplat and meshSplat:IsA("MeshPart") and meshSplat.CFrame.LookVector.Z > 0.999, "the splat is the Blender splat, facing out of the wall")
wall:Destroy()
local sideways = effectsFolder:FindFirstChild("Splat") :: MeshPart
sideways.MeshSize = Vector3.new(ShotArt.Splat.size.Z, ShotArt.Splat.size.Y, ShotArt.Splat.size.X)
local none, sidewaysWhy = WeaponModel.effect("Splat")
check(none == nil and string.find(sidewaysWhy, "wrong way round", 1, true), "an effect imported on its side: " .. sidewaysWhy)
sideways.MeshSize = ShotArt.Splat.size
frames(1)
-- Rapid fire stacks, up to a cap.
for _ = 1, 10 do
	Fx.fired(ada.UserId)
end
check(Fx.states[adaTool].kick <= WeaponFx.MAX_RECOIL, "kicks stack, up to a cap")
-- The budget.
local before = Fx.emitted
for _ = 1, 40 do
	Fx.fired(ada.UserId)
end
check(Fx.emitted - before <= WeaponFx.MAX_PARTICLES_PER_FRAME, `at most {WeaponFx.MAX_PARTICLES_PER_FRAME} particles a frame ({Fx.emitted - before})`)
frames(1)

-- The tank glows.
local gasPart
for _, part in adaTool:GetChildren() do
	if part:IsA("BasePart") and part:GetAttribute("Gas") then
		gasPart = part
	end
end
local glowA = gasPart.Transparency
frames(0.45)
check(gasPart.Transparency ~= glowA, "the gas tank glows")

-- The Thunderclapper.
TestControls.weapon(ada, "Thunderclapper")
task.wait(0.2)
local thunder = ada.Character:FindFirstChild("HeldWeapon") :: Tool
check(thunder:GetAttribute("Weapon") == "Thunderclapper" and Fx.states[thunder], "a new gun is tracked")
weld = grip(ada)
frames(0.5)
Fx.fired(ada.UserId)
local flash = thunder.Handle.Muzzle:FindFirstChild("Flash") :: PointLight
check(flash and flash.Enabled, "the Thunderclapper flashes")
task.wait(0.15)
check(not flash.Enabled, "for a moment")
frames(1 / 60)
local heavy = weld.C1:Inverse()
check(heavy.Position.Z > 0.3 and heavy.LookVector.Y > 0.15, "and kicks hard")
check(Fx.cameraKick() == 0, "no camera kick for someone else's shot")
TestControls.weapon(me, "Thunderclapper")
task.wait(0.2)
grip(me)
frames(0.5)
Fx.fired(me.UserId)
check(Fx.cameraKick() > 0, "my own Thunderclapper kicks my camera")
frames(1)

-- Reduce motion.
Settings.reduceMotion = true
frames(0.5)
Fx.fired(ada.UserId)
frames(1 / 60)
local calm = weld.C1:Inverse()
check(calm.Position.Z > 0 and calm.Position.Z < heavy.Position.Z * 0.5, "reduce motion: a little recoil")
check(not flash.Enabled, "no flash")
Fx.fired(me.UserId)
check(Fx.cameraKick() == 0, "no camera kick")
frames(1)
local tankNow
for _, part in thunder:GetChildren() do
	if part:IsA("BasePart") and part:GetAttribute("Gas") then
		tankNow = part
	end
end
local still = tankNow.Transparency
frames(0.5)
check(tankNow.Transparency == still, "no glowing tank")
TestControls.weapon(ada, "GasBlaster")
task.wait(0.2)
weld = grip(ada)
frames(1 / 60)
check(weld.C1.Position.Magnitude < 1e-3 and weld.C1.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.999, "a new gun is simply there")
Settings.reduceMotion = false

-- Explosions.
local blasts = Effects.blastParticles
Effects.explosion(Vector3.new(0, 5, 0))
local blastFx = workspace:FindFirstChild("BlastFx")
check(Effects.blastParticles == blasts + 1 and blastFx, "explosions throw smoke")
local cloud = blastFx.Blast1:FindFirstChild("Cloud") :: ParticleEmitter
check(cloud and cloud.Texture == ArtAssets.effect("cloud") and blastFx.Blast1:FindFirstChild("Ring"), "the cloud and the shockwave ring")

-- The hotbar's icons.
local slot = Hotbar.parts.slots[1]
local icon = slot:FindFirstChild("Icon")
check(icon and icon:IsA("ViewportFrame") and icon.CurrentCamera and icon:GetAttribute("Weapon") == slot:GetAttribute("Weapon"), "the hotbar shows the weapon's 3D model")
local model = icon:FindFirstChildOfClass("Model")
check(model and #model:GetChildren() > 5, "the whole model")
Hotbar.renderSlots()
check(slot:FindFirstChild("Icon") == icon, "kept between renders")

-- The locker's previews.
Locker.open("Weapons")
task.wait(0.1)
local card = Locker.parts.content:FindFirstChild("GasBlaster")
local preview = card and card:FindFirstChild("Preview")
check(preview and preview:IsA("ViewportFrame") and preview:FindFirstChildOfClass("Model"), "each weapon card shows the weapon")
local angle = preview:GetAttribute("Angle")
frames(0.5)
check(preview:GetAttribute("Angle") ~= angle, "turning slowly")
Settings.reduceMotion = true
angle = preview:GetAttribute("Angle")
frames(0.5)
check(preview:GetAttribute("Angle") == angle, "and still with reduce motion")
Settings.reduceMotion = false
Locker.close()

return { status = "PASS", checks = checks }
