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
