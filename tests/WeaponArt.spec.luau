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
	for name, mesh in art.meshes do
		check(art.roles[mesh.role], `{id}'s {name} mesh has a colour`)
		check(mesh.triangles > 0 and mesh.triangles < 10000, `{id}'s {name} mesh is within Roblox's limits ({mesh.triangles} triangles)`)
		check(mesh.size.X > 0 and mesh.size.Y > 0 and mesh.size.Z > 0, `{id}'s {name} mesh has a size`)
		if mesh.moving then
			local pieces = 0
			for _, piece in art.pieces do
				if piece.part == name then
					pieces += 1
					check(piece.role == mesh.role, `{id}'s {name} is all {mesh.role}`)
				end
			end
			check(pieces > 0, `{id}'s moving {name} has its pieces`)
		end
	end
	for name, motion in WeaponFx.weapons[id].parts or {} do
		local mesh = art.meshes[name]
		check(mesh and mesh.moving and (motion.pivot == nil or art.meshes[motion.pivot]), `{id}'s {name} moves ({motion.kind})`)
	end
	check(#art.pieces >= 10, `{id} is built from {#art.pieces} pieces`)
end
check(WeaponArt.GasBlaster.meshes.Pump and WeaponArt.GasBlaster.meshes.Needle, "the Gas Blaster's pump and needle are parts of their own")

-- The meshes packed for the game to build (Shared.MeshData): every mesh,
-- the right size once unpacked, its triangles facing the way its normals do.
local MeshBuilder = require(Shared.MeshBuilder)
local ShotArt = require(Shared.Config.ShotArt)
local function unpacked(set: string, name: string, entry, size: Vector3)
	check(entry and (entry.size - size).Magnitude < 1e-3, `{set}'s {name} is packed at its size`)
	local positions, normals, corners = MeshBuilder.decode(entry)
	check(#positions == entry.vertices and #corners == entry.triangles * 3, `{set}'s {name}: {entry.vertices} vertices, {entry.triangles} triangles`)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in positions do
		lo = lo:Min(p)
		hi = hi:Max(p)
	end
	check((hi - lo - size).Magnitude < 2e-3 and ((hi + lo) / 2).Magnitude < 2e-3, `{set}'s {name} unpacks to its box, round its centre`)
	local facing, total = 0, 0
	for i = 1, #corners, 3 do
		local a, b, c = corners[i], corners[i + 1], corners[i + 2]
		check(a >= 1 and a <= #positions and b <= #positions and c <= #positions, `{set}'s {name}'s corners are vertices`)
		local face = (positions[b] - positions[a]):Cross(positions[c] - positions[a])
		if face.Magnitude > 1e-6 then
			total += 1
			facing += if face:Dot(normals[a] + normals[b] + normals[c]) > 0 then 1 else 0
		end
	end
	check(facing >= total * 0.97, `{set}'s {name} faces out, counterclockwise as Roblox draws ({facing} of {total})`)
end
local MeshData = Shared:FindFirstChild("MeshData")
check(MeshData, "Shared.MeshData is there")
for _, id in WeaponConfig.order do
	local packed = require(MeshData:FindFirstChild(id))
	for name, mesh in WeaponArt[id].meshes do
		unpacked(id, name, packed[name], mesh.size)
	end
end
local packedShots = require(MeshData:FindFirstChild("Shots"))
for name, art in ShotArt do
	unpacked("Shots", name, packedShots[name], art.size)
end

-- The held gun, from the pieces.
local tool = WeaponModel.tool("GasBlaster", "Gas Blaster")
local handle = tool:FindFirstChild("Handle") :: BasePart
check(handle and handle.Transparency == 1 and handle.CFrame == CFrame.new(), "an invisible Handle at the grip")
local standins = 0
for _, piece in WeaponArt.GasBlaster.pieces do
	standins += if piece.standin ~= false then 1 else 0
end
local parts, welds, moving = 0, 0, 0
for _, part in tool:GetChildren() do
	if part:IsA("BasePart") and part ~= handle then
		parts += 1
		check(not part.CanCollide and not part.CanQuery and not part.CanTouch and part.Massless, `{part.Name} is never in the way`)
		check(part.Color == WeaponArt.GasBlaster.roles[part:GetAttribute("Role")].color, `{part.Name} in its role's colour`)
		local move = part:FindFirstChild("Move")
		if part:GetAttribute("Part") then
			moving += 1
			check(move and move:IsA("Weld") and move.Part0 == handle and move:GetAttribute("Part") == part.Name, `{part.Name} hangs on a Move weld`)
			check(move.C0 == move:GetAttribute("Rest") and (handle.CFrame * move.C0).Position:FuzzyEq(part.Position, 1e-3), `{part.Name} rests where it belongs`)
			welds += 1
		end
	end
end
for _, weld in handle:GetChildren() do
	welds += if weld:IsA("WeldConstraint") then 1 else 0
end
check(parts == standins and welds == parts, `every piece there and welded ({parts})`)
check(moving == 6, `the pump's four pieces and the needle's two move ({moving})`)
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
	for name, mesh in WeaponArt[id].meshes do
		if name ~= skip then
			local part = Instance.new("MeshPart")
			part.Name = name
			-- Imported at three times the size, somewhere else.
			local size = mesh.size * 3
			if name == rotate then
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
for name, mesh in WeaponArt.Spritzer.meshes do
	local part = spritzer:FindFirstChild(name) :: BasePart
	check(part and part:IsA("MeshPart"), `the {name} MeshPart`)
	check((part.Size - mesh.size).Magnitude < 1e-3 and (part.CFrame.Position - mesh.center).Magnitude < 1e-3, `{name} sized and placed from the art, whatever the import's scale`)
	check(part.Color == WeaponArt.Spritzer.roles[mesh.role].color and part.Material == WeaponArt.Spritzer.roles[mesh.role].material, `{name} coloured from the art`)
	check(if mesh.moving then part:FindFirstChild("Move") ~= nil else part:FindFirstChild("Move") == nil, `{name} welded to move or not`)
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
local buildable, buildWhy = MeshBuilder.probe()
check(not buildable and string.find(buildWhy, "CreateEditableMesh", 1, true) ~= nil, "meshes can't be built in the stand-in world (no EditableMesh), and the selftest's probe says why")

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

-- A splat where it hits a wall, facing out of it; none on a player. Up
-- above the map, so nothing of the map is in the way.
local UP = Vector3.new(0, 300, 0)
local wall = Instance.new("Part")
wall.Name = "TestWall"
wall.Anchored = true
wall.Size = Vector3.new(30, 30, 2)
wall.CFrame = CFrame.new(Vector3.new(0, 5, -41) + UP)
wall.Parent = workspace
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0) + UP, to = Vector3.new(0, 5, -40) + UP })
task.wait()
local splat: BasePart? = nil
for _, part in ShotFx.splats do
	if part.Transparency < 1 then
		splat = part
	end
end
check(splat and splat:GetAttribute("ArtSource") == "part", "a splat where it hit the wall")
local splatPart = splat :: BasePart
check((splatPart.Position - (Vector3.new(0, 5, -39.96) + UP)).Magnitude < 0.01, "on its face")
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
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0) + UP, to = Vector3.new(0, 5, -40) + UP })
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
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0) + UP, to = Vector3.new(0, 5, -40) + UP })
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
local preview = card and card:FindFirstChild("Preview", true)
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

-- The springs: a kick swings back past rest a little; standing still, the
-- gun sways round the grip; walking, it bobs.
adaTool = ada.Character:FindFirstChild("HeldWeapon") :: Tool
weld = grip(ada)
frames(1)
Fx.fired(ada.UserId)
local lowest = math.huge
for _ = 1, 40 do
	frames(1 / 60)
	lowest = math.min(lowest, Fx.states[adaTool].kick)
end
check(lowest < -0.05, `the recoil springs back past rest a little ({lowest})`)
frames(1)
local swayFrom = weld.C1
frames(0.8)
check((weld.C1.LookVector - swayFrom.LookVector).Magnitude > 1e-4 and weld.C1.Position.Magnitude < 1e-3, "standing still, the gun sways a little, round the grip")
local adaRoot = (ada.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
adaRoot.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
local low, high = math.huge, -math.huge
for _ = 1, 45 do
	frames(1 / 30)
	local y = weld.C1:Inverse().Position.Y
	low, high = math.min(low, y), math.max(high, y)
end
check(high - low > 0.03, `walking, it bobs with the steps ({high - low})`)
adaRoot.AssemblyLinearVelocity = Vector3.zero
frames(1)
check(weld.C1.Position.Magnitude < 1e-3, "and stops when they do")

-- A light gun twirls as it comes up; a heavy one doesn't.
TestControls.weapon(ada, "Spritzer")
task.wait(0.2)
weld = grip(ada)
frames(0.1)
check(math.abs(weld.C1:Inverse().RightVector.Y) > 0.3, "the Spritzer twirls round its barrel as it comes up")
frames(0.5)
check(math.abs(weld.C1:Inverse().RightVector.Y) < 0.05, "and ends upright")
TestControls.weapon(ada, "Thunderclapper")
task.wait(0.2)
weld = grip(ada)
frames(0.1)
check(math.abs(weld.C1:Inverse().RightVector.Y) < 0.05, "the Thunderclapper just swings up")
TestControls.weapon(ada, "GasBlaster")
task.wait(0.2)
adaTool = ada.Character:FindFirstChild("HeldWeapon") :: Tool
weld = grip(ada)
frames(1)

-- The new effects: every gun's muzzle lights up and throws a shock ring;
-- the bolt lights its way and trails smoke; where it hits, a flash of
-- light and a ring; a player you hit flashes white; a hot barrel smokes.
local target = Instance.new("Part")
target.Name = "TestWall"
target.Anchored = true
target.Size = Vector3.new(30, 30, 2)
target.CFrame = CFrame.new(Vector3.new(0, 5, -41) + UP) -- above the map, clear of it
target.Parent = workspace
Fx.fired(ada.UserId)
local blasterFlash = (adaTool:FindFirstChild("Handle") :: BasePart):FindFirstChild("Muzzle"):FindFirstChild("Flash") :: PointLight
check(blasterFlash and blasterFlash.Enabled, "the Gas Blaster's muzzle flashes light too")
local ring: BasePart? = nil
for _, part in ShotFx.rings do
	if part.Transparency < 1 then
		ring = part
	end
end
check(ring, "a shock ring at the muzzle")
local ringSize = (ring :: BasePart).Size.X
frames(SHOT.RING_SECONDS * 0.5)
check((ring :: BasePart).Size.X > ringSize and (ring :: BasePart).Transparency > SHOT.RING_TRANSPARENCY, "spreading and fading")
frames(SHOT.RING_SECONDS)
check((ring :: BasePart).Transparency == 1, "then gone")
local trailed = ShotFx.trailed
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0) + UP, to = Vector3.new(0, 5, -40) + UP })
task.wait()
local lit = false
for _, part in ShotFx.tracers do
	local lamp = part:FindFirstChild("Light") :: PointLight?
	lit = lit or (part.Transparency == 0 and lamp ~= nil and lamp.Enabled and lamp.Range == blaster.light)
end
check(lit, "the bolt lights its way")
local impactLit, impactRings = false, 0
for _, attachment in impacts:GetChildren() do
	local lamp = attachment:FindFirstChild("Flash") :: PointLight?
	impactLit = impactLit or (lamp ~= nil and lamp.Enabled)
end
for _, part in ShotFx.rings do
	impactRings += if part.Transparency < 1 and math.abs(part.Position.Z + 40) < 0.2 then 1 else 0
end
check(impactLit and impactRings == 1, "where it hits: a flash of light and a ring on the wall")
frames(0.2)
check(ShotFx.trailed > trailed, `the bolt leaves a trail of smoke ({ShotFx.trailed - trailed} puffs)`)
target:Destroy()
Remotes.CombatEvent:FireClient(me, { kind = "hit", victim = ada.UserId, gas = 20, headshot = false, blocked = false })
task.wait()
local hitFlash = workspace:FindFirstChild("HitFlash") :: Highlight
check(hitFlash and hitFlash.Enabled and hitFlash.Adornee == ada.Character, "a player you hit flashes white")
frames(WeaponFx.HIT.SECONDS + 0.05)
check(not hitFlash.Enabled, "for a moment")
for _ = 1, 6 do
	Fx.fired(ada.UserId)
	frames(0.05)
end
local smoke = adaTool.Handle.Muzzle:FindFirstChild("Smoke") :: ParticleEmitter
check(smoke and smoke.Rate > 0, "a burst of shots leaves the barrel smoking")
frames(5)
check(smoke.Rate == 0, "until it cools")
task.wait(0.2)
Settings.reducedEffects = true
Fx.fired(ada.UserId)
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -100) })
task.wait()
local quiet = true
for _, part in ShotFx.tracers do
	local lamp = part:FindFirstChild("Light") :: PointLight?
	quiet = quiet and not (lamp and lamp.Enabled)
end
trailed = ShotFx.trailed
frames(0.1)
check(quiet and not blasterFlash.Enabled, "reduced effects: no lights")
check(ShotFx.trailed == trailed, "and no trail")
Settings.reducedEffects = false
frames(1)

-- Built in the game, so nothing has to be imported: each client builds
-- the meshes (EditableMesh; here a stand-in that keeps what it's given)
-- and dresses every held gun in them.
local fakeAssets = {}
function fakeAssets.CreateEditableMesh(_self)
	local mesh = { vertices = {}, normals = {}, faces = {}, faceNormals = {} }
	function mesh.AddVertex(self, p: Vector3)
		table.insert(self.vertices, p)
		return #self.vertices
	end
	function mesh.AddNormal(self, n: Vector3)
		table.insert(self.normals, n)
		return #self.normals
	end
	function mesh.AddTriangle(self, a, b, c)
		assert(self.vertices[a] and self.vertices[b] and self.vertices[c], "triangles of real vertices")
		table.insert(self.faces, { a, b, c })
		return #self.faces
	end
	function mesh.SetFaceNormals(self, face, ids)
		assert(self.faces[face] and #ids == 3 and self.normals[ids[1]], "normals for real faces")
		self.faceNormals[face] = ids
	end
	function mesh.Destroy() end
	return mesh
end
function fakeAssets.CreateMeshPartAsync(_self, mesh, options)
	assert(options and options.CollisionFidelity == Enum.CollisionFidelity.Box, "no collision geometry worked out")
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in mesh.vertices do
		lo = lo:Min(p)
		hi = hi:Max(p)
	end
	local part = Instance.new("MeshPart")
	part.MeshSize = hi - lo
	part.MeshContent = mesh
	return part
end
MeshBuilder.reset()
MeshBuilder.service = fakeAssets
MeshBuilder.content = function(object)
	return object
end
check(MeshBuilder.probe(), "with EditableMesh, meshes can be built")
check(MeshBuilder.prepare("GasBlaster"), "the Gas Blaster's meshes build")
task.wait(0.1)
frames(1 / 60)
local skin = adaTool:FindFirstChild("Skin")
check(skin and adaTool:GetAttribute("ArtSource") == "pieces", "Ada's gun, the server's stand-in, is dressed in them here")
local adaHandle = adaTool:FindFirstChild("Handle") :: BasePart
for name, mesh in WeaponArt.GasBlaster.meshes do
	local part = skin:FindFirstChild(name) :: MeshPart
	check(part and part:IsA("MeshPart") and part.MeshSize:FuzzyEq(mesh.size, 2e-3), `the {name} mesh, built to its size`)
	check(part.Size == mesh.size and part.Color == WeaponArt.GasBlaster.roles[mesh.role].color and part.Material == WeaponArt.GasBlaster.roles[mesh.role].material, `{name} sized and coloured from the art`)
	check((part.Position - (adaHandle.CFrame * mesh.center)).Magnitude < 1e-3 and not part.CanCollide and not part.CanQuery and part.Massless, `{name} in its place, never in the way`)
	local joint = if mesh.moving then part:FindFirstChild("Move") else nil
	check(if mesh.moving then joint and (joint :: Weld).Part0 == adaHandle else true, `{name} welded to the grip`)
end
local hidden = 0
for _, part in adaTool:GetChildren() do
	if part:IsA("BasePart") and part:GetAttribute("Role") then
		hidden += if part.Transparency == 1 then 1 else 0
	end
end
check(hidden == standins, `the stand-in's {standins} pieces hidden here`)
local pump = skin.Pump.Move :: Weld
local pumpRest = pump:GetAttribute("Rest") :: CFrame
frames(0.5)
Fx.fired(ada.UserId)
frames(0.05)
check(pump.C0.Position.Z > pumpRest.Position.Z + 0.05, "the pump pumps back on a shot")
frames(0.4)
check((pump.C0.Position - pumpRest.Position).Magnitude < 1e-3, "and home")
local needle = skin.Needle.Move :: Weld
local needleRest = needle:GetAttribute("Rest") :: CFrame
Fx.fired(ada.UserId)
Fx.fired(ada.UserId)
frames(0.3)
check((needle.C0.LookVector - needleRest.LookVector).Magnitude > 0.15 and (needle.C0.Position - needleRest.Position).Magnitude < 1e-3, "the gauge's needle drops round its middle as the pressure does")
frames(3)
check((needle.C0.LookVector - needleRest.LookVector).Magnitude < 1e-3, "and climbs back")
local gasPieces = 0
for part in Fx.states[adaTool].gas do
	gasPieces += if part.Parent == skin then 1 else 0
end
check(gasPieces == 1, "the glow is the meshes' now")
-- The hotbar's icon swaps to the meshes.
local blasterSlot
for _, s in Hotbar.parts.slots do
	blasterSlot = if s:GetAttribute("Weapon") == "GasBlaster" then s else blasterSlot
end
local iconModel = blasterSlot and blasterSlot:FindFirstChild("Icon"):FindFirstChildOfClass("Model")
check(iconModel and iconModel:GetAttribute("ArtSource") == "runtime", "the hotbar shows the meshes too")
-- The Stink Lobber's bomb goes with the throw and grows back.
TestControls.weapon(ada, "StinkLobber")
task.wait(0.2)
local lobber = ada.Character:FindFirstChild("HeldWeapon") :: Tool
grip(ada)
check(MeshBuilder.prepare("StinkLobber"), "the Stink Lobber's meshes build")
task.wait(0.1)
frames(0.5)
local bomb = lobber:FindFirstChild("Skin") and lobber.Skin:FindFirstChild("Bomb") :: MeshPart
check(bomb and bomb.Transparency == 0, "a bomb loaded")
Remotes.CombatEvent:FireClient(me, { kind = "lob", shooter = ada.UserId })
task.wait()
frames(1 / 60)
check(bomb.Transparency == 1 and lobber.Skin.Fuse.Transparency == 1, "gone when it's thrown, fuse and all")
local lob = WeaponFx.weapons.StinkLobber.parts.Bomb
frames(lob.seconds - lob.amount + 0.05)
check(bomb.Transparency == 0 and bomb.Size.X < WeaponArt.StinkLobber.meshes.Bomb.size.X * 0.99, "back as it reloads, growing")
frames(0.5)
check(bomb.Size:FuzzyEq(WeaponArt.StinkLobber.meshes.Bomb.size, 1e-3), "to full size")
-- The shot meshes: built too (and imports win, so take those away).
effectsFolder:ClearAllChildren()
check(MeshBuilder.prepare("Shots"), "the shot meshes build")
task.wait(0.1)
TestControls.weapon(ada, "GasBlaster")
task.wait(0.2)
grip(ada)
frames(0.5)
Fx.fired(ada.UserId)
Remotes.CombatEvent:FireClient(me, { kind = "shot", shooter = ada.UserId, from = Vector3.new(0, 5, 0), to = Vector3.new(0, 5, -60) })
task.wait()
local runtimeBolt, runtimeRing
for _, part in ShotFx.tracers do
	runtimeBolt = if part.Transparency == 0 then part else runtimeBolt
end
for _, part in ShotFx.rings do
	runtimeRing = if part.Transparency < 1 then part else runtimeRing
end
check(runtimeBolt and runtimeBolt:IsA("MeshPart") and runtimeBolt:GetAttribute("ArtSource") == "runtime", "the bolt is the Blender gas bolt, built here")
check(runtimeRing and runtimeRing:IsA("MeshPart") and runtimeRing:GetAttribute("ArtSource") == "runtime", "and the ring")
check(string.find(MeshBuilder.status(), "GasBlaster", 1, true) ~= nil, "status says what's built: " .. MeshBuilder.status())
frames(1)
MeshBuilder.service = nil

return { status = "PASS", checks = checks }
