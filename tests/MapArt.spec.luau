-- The map's Blender props (art/blender/build_props.py) in the game:
--   * PropArt (generated) has every prop MapArt uses, each modelled at the
--     size of its map part, within Roblox's triangle limit; every part
--     MapArt names is in the map
--   * until the meshes are imported the map is its plain parts, as before
--   * imported (at any scale, as a MeshPart or inside the importer's
--     Model), each named part gets its mesh drawn exactly over it,
--     coloured like it; the part turns invisible but stays the hitbox, so
--     everything players collide with or shots can hit is unchanged; the
--     mesh can't be hit, touched or collided with
--   * walls, trims and floors are modules repeated along their parts (a
--     wall's modules run along it), none stretched more than a quarter;
--     the spawn pads still work as spawns under theirs
--   * the throne's mirrored tank turns round to face its own bowl; the
--     Gas Gutter's sideways tank turns to face its bowl, sized to fit
--   * a gas barrel's mesh goes and comes back with it; the hitbox under
--     it stays invisible and solid, the mesh never solid
--   * a mesh imported on its side, or a Model with no MeshPart, is left
--     out and says why; dressing twice adds nothing
--   * Bean Rain's beans use the bean mesh; selftest reports on the props
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local MapArt = require(Shared.Config.MapArt)
local PropArt = require(Shared.Config.PropArt)
local MapConfig = require(Shared.Config.MapConfig)
local MapBase = require(Shared.Interfaces.MapBase)
local GameConfig = require(Shared.Config.GameConfig)
local EventConfig = require(Shared.Config.EventConfig)
local MapDressing = require(server.MapDressing)
local Map = require(server.Services.MapService)
local Barrels = require(server.Services.BarrelService)
local Events = require(server.Services.EventService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Round = require(server.Services.RoundService)
local TestControls = require(server.TestControls)

local function near(a: Vector3, b: Vector3, tolerance: number?): boolean
	return (a - b).Magnitude <= (tolerance or 1e-3)
end

local function partsNamed(map: Instance, name: string): { BasePart }
	local found = {}
	for _, item in map:GetDescendants() do
		if item:IsA("BasePart") and item.Name == name then
			table.insert(found, item)
		end
	end
	return found
end

-- What play sees: every part that collides or can be hit.
local function solid(map: Instance): { string }
	local list = {}
	for _, item in map:GetDescendants() do
		if item:IsA("BasePart") and (item.CanCollide or item.CanQuery) then
			local p, s = item.Position, item.Size
			table.insert(list, string.format("%s %.2f %.2f %.2f %.2f %.2f %.2f %s %s", item.Name, p.X, p.Y, p.Z, s.X, s.Y, s.Z, tostring(item.CanCollide), tostring(item.CanQuery)))
		end
	end
	table.sort(list)
	return list
end

-- The art.
local map = Map.current() :: Model
local used = { [MapArt.BEAN] = true }
for name, rule in MapArt.parts do
	used[rule.mesh] = true
	check(PropArt[rule.mesh], `{name}'s prop {rule.mesh} is in PropArt`)
	check(#partsNamed(map, name) > 0, `the map has a {name} for MapArt`)
end
for prop, art in PropArt do
	check(used[prop], `{prop} is used`)
	check(art.triangles > 0 and art.triangles <= 10000, `{prop}: {art.triangles} triangles, within Roblox's limit`)
	if prop == MapArt.BEAN then
		check(near(art.size, Vector3.new(2.4, 1.6, 1.6)), "the bean is the size of Bean Rain's beans")
	else
		local part = partsNamed(map, art.modelledOn)[1]
		local rule = MapArt.parts[art.modelledOn]
		check(part and rule and rule.mesh == prop, `{prop} dresses {art.modelledOn}`)
		local _, size = MapDressing.placement(part, rule)
		if art.tile then
			-- A module: its own length along the tiled axes, the part's across.
			for _, axis in { "X", "Y", "Z" } do
				local tile, want = (art.tile :: any)[axis], (art.size :: any)[axis]
				local fits = if tile > 0 then math.abs(tile - want) < 1e-3 else math.abs((size :: any)[axis] - want) < 1e-3
				check(fits, `{prop}, a module, fits {art.modelledOn} on {axis}`)
			end
		else
			check(near(size, art.size), `{prop} is modelled at {art.modelledOn}'s size`)
		end
	end
end

-- Not imported: the plain parts, as before.
local assets = ReplicatedStorage:FindFirstChild("Assets")
check(assets and assets:FindFirstChild("Props"), "ReplicatedStorage.Assets.Props is there for the imports")
for prop in PropArt do
	local mesh, why = MapDressing.imported(prop)
	check(mesh == nil and why == "not imported", `{prop}: not imported yet`)
end
check(map:FindFirstChild("Dressing") == nil, "no dressing without the meshes")
for name in MapArt.parts do
	for _, part in partsNamed(map, name) do
		check(part.Transparency < 1 and part:GetAttribute("Dressed") == nil, `{part:GetFullName()} shows as it is`)
	end
end
local plain = solid(map)

-- Imported.
local function import(prop: string, size: Vector3, wrap: boolean?): MeshPart
	local mesh = Instance.new("MeshPart")
	mesh.Name = prop
	mesh.MeshSize = size
	mesh.Size = size
	mesh.CFrame = CFrame.new(300, 50, 300)
	mesh.CanCollide = true
	if wrap then
		local model = Instance.new("Model")
		model.Name = prop
		mesh.Name = "Mesh"
		mesh.Parent = model
		model.Parent = assets.Props
	else
		mesh.Parent = assets.Props
	end
	return mesh
end
for prop, art in PropArt do
	-- At twice the size, somewhere else; the crate as the importer's Model.
	import(prop, art.size * 2, prop == "Crate")
end
for prop in PropArt do
	local mesh, why = MapDressing.imported(prop)
	check(mesh and why == "imported", `{prop} is found`)
end
map = Map.load("BrainrotBattlefield")
local ok, problems = MapBase.validate(map, MapConfig.BrainrotBattlefield, { "Stinkers", "Sharters" })
check(ok, "still keeps the MapBase contract: " .. table.concat(problems, "; "))
local dressed, expected, wanted = 0, {}, 0
local function key(name: string, position: Vector3): string
	return string.format("%s %.2f %.2f %.2f", name, position.X, position.Y, position.Z)
end
for name, rule in MapArt.parts do
	for _, part in partsNamed(map, name) do
		dressed += 1
		check(part.Transparency == 1 and part:GetAttribute("Dressed") == rule.mesh and not part.CastShadow, `{part:GetFullName()} is now the invisible hitbox`)
		for _, piece in MapDressing.pieces(part, rule) do
			expected[key(name, piece.cframe.Position)] = { part = part, piece = piece, rule = rule }
			wanted += 1
		end
	end
end
local arts = 0
for _, item in map:GetDescendants() do
	if item:IsA("MeshPart") and item:GetAttribute("Dresses") then
		arts += 1
		local entry = expected[key(item:GetAttribute("Dresses"), item.Position)]
		check(entry, `{item:GetFullName()} sits where MapDressing.pieces puts it`)
		local part, piece, rule = entry.part :: BasePart, entry.piece, entry.rule
		check(item.Name == `{part.Name}Art` and item:GetAttribute("Prop") == rule.mesh, `{item:GetFullName()} names its part and prop`)
		check(near(item.Size, piece.size), `{item:GetFullName()} sized to its part, whatever the import's scale`)
		check(near(item.CFrame.LookVector, piece.cframe.LookVector) and near(item.CFrame.UpVector, piece.cframe.UpVector), `{item:GetFullName()} turned as placed`)
		check(item.Color == part.Color and item.Material == part.Material, `{item:GetFullName()} coloured like its part`)
		if part.Name == "SpawnFloor" then
			check(math.abs(item.Transparency - 0.35) < 1e-3, "the spawn floor's tiles are see-through like it was")
		end
		check(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch, `{item:GetFullName()} is never in the way`)
		check(item.Parent == map.Dressing or item.Parent.Name == "GasBarrel", `{item:GetFullName()} is in Dressing or its barrel`)
		local art = PropArt[rule.mesh]
		if art.tile then
			for _, axis in { "X", "Y", "Z" } do
				if (art.tile :: any)[axis] > 0 then
					local stretch = (item.Size :: any)[axis] / (art.size :: any)[axis]
					check(stretch >= 0.75 and stretch <= 1.25, `{item:GetFullName()}: a module stretched {stretch} on {axis}, no more than a quarter`)
				end
			end
		end
		if rule.long then
			local right = item.CFrame.RightVector
			local runs = if part.Size.Z > part.Size.X then math.abs(right.Z) else math.abs(right.X)
			check(runs > 0.999, `{item:GetFullName()} runs along its wall`)
		end
	end
end
check(arts == wanted and dressed > 60 and arts > 300, `every named part dressed ({dressed} parts, {arts} meshes)`)
local sideWall = partsNamed(map, "SideWall")[1]
check(#MapDressing.pieces(sideWall, MapArt.parts.SideWall) == math.round(164 / PropArt.TallWall.tile.X), "a side wall is a row of wall modules, not one stretched mesh")
check(#MapDressing.pieces(map.Floor.Ground, MapArt.parts.Ground) == 64, "the ground is 8 x 8 modules")
for _, team in { "Stinkers", "Sharters" } do
	local pads = Map.spawns(team)
	check(#pads == 4, `{team} still have their four spawn pads`)
	for _, pad in pads do
		check(pad.Enabled and pad.CanCollide and pad.Transparency == 1 and pad:GetAttribute("Dressed") == "SpawnPad", `{pad:GetFullName()}: dressed and still a spawn`)
	end
end
local after = solid(map)
check(#after == #plain, `the same parts collide or can be hit ({#after} vs {#plain})`)
for i, line in plain do
	check(after[i] == line, `unchanged for play: {line}`)
end
check(MapDressing.dress(map) == 0, "dressing again adds nothing")

-- The thrones face their bowls; the Gutter's tank turns to its bowl.
for _, tank in partsNamed(map, "ThroneTank") do
	local art = map.Dressing:FindFirstChild("ThroneTankArt")
	for _, candidate in map.Dressing:GetChildren() do
		if candidate.Name == "ThroneTankArt" and near(candidate.Position, tank.Position) then
			art = candidate
		end
	end
	local bowlSide = if tank.Position.Z < 0 then -1 else 1
	check(near(art.CFrame.LookVector, Vector3.new(0, 0, bowlSide)), `the throne's tank at z = {tank.Position.Z} faces its bowl`)
end
for _, tank in partsNamed(map, "GutterTank") do
	for _, art in map.Dressing:GetChildren() do
		if art.Name == "GutterTankArt" and near(art.Position, tank.Position) then
			check(near(art.CFrame.LookVector, Vector3.new(-1, 0, 0)), "the Gutter's tank faces its bowl (-X)")
			check(near(art.Size, Vector3.new(tank.Size.Z, tank.Size.Y, tank.Size.X)), "and is sized for its turn")
		end
	end
end
for _, bowl in partsNamed(map, "ThroneBowl") do
	for _, art in map.Dressing:GetChildren() do
		if art.Name == "ThroneBowlArt" and near(art.Position, bowl.Position) then
			check(near(art.CFrame.RightVector, Vector3.new(0, 1, 0)), "the bowl stands up like its part")
		end
	end
end

-- Barrels.
local me = Instance.new("Player")
me.Name = "Me"
me.UserId = 1
me.Parent = Players
local foe = Instance.new("Player")
foe.Name = "Foe"
foe.UserId = 2
foe.Parent = Players
task.wait(0.1)
Lifecycle.requestPlay(me, nil)
Lifecycle.requestPlay(foe, nil)
task.wait(0.5)
local barrel = map.Barrels:FindFirstChildWhichIsA("Model") :: Model
local body, bodyArt = barrel:FindFirstChild("Barrel") :: BasePart, barrel:FindFirstChild("BarrelArt") :: BasePart
local band, bandArt = barrel:FindFirstChild("Band") :: BasePart, barrel:FindFirstChild("BandArt") :: BasePart
check(bodyArt and bandArt, "the barrel's meshes are in its model")
check(Barrels.shoot(me, body, GameConfig.BARREL.HEALTH), "a barrel shot to nothing")
task.wait(GameConfig.BARREL.FUSE_SECONDS + 0.2)
for _, item in { body, band, bodyArt, bandArt } do
	check(item.Transparency == 1 and not item.CanCollide and not item.CanQuery, `{item.Name} gone with the blast`)
end
task.wait(GameConfig.BARREL.RESPAWN_SECONDS + 0.5)
check(bodyArt.Transparency == 0 and bandArt.Transparency == 0, "back: the meshes show")
check(not bodyArt.CanCollide and not bodyArt.CanQuery and not bandArt.CanCollide and not bandArt.CanQuery, "and still never in the way")
check(body.Transparency == 1 and band.Transparency == 1, "the hitboxes stay invisible")
check(body.CanCollide and body.CanQuery and band.CanCollide and band.CanQuery, "and solid")

-- Beans.
check(Round.phase() == "ACTIVE", "a round on")
Events.testEnable(true)
Events.book(workspace:GetServerTimeNow())
local bean: BasePart? = nil
for _ = 1, 80 do
	task.wait(0.25)
	for _, item in Events.beans() do
		if item.landed then
			bean = item.part
		end
	end
	if bean then
		break
	end
end
check(bean and bean:IsA("MeshPart") and bean.Name == "Bean", "a landed bean is the bean mesh")
check(near((bean :: BasePart).Size, PropArt.Bean.size) and not (bean :: BasePart).CanCollide and not (bean :: BasePart).CanQuery, "bean-sized, never in the way")
Events.stop()
Events.testEnable(nil)
check(EventConfig.BEAN_RAIN ~= nil, "Bean Rain's settings are there")

-- On its side, or no MeshPart.
assets.Props.TankLid:Destroy()
local lid = PropArt.TankLid.size
import("TankLid", Vector3.new(lid.Z, lid.X, lid.Y))
local sideways, why = MapDressing.imported("TankLid")
check(sideways == nil and string.find(why, "wrong way round", 1, true), "a mesh on its side: " .. why)
assets.Props.Bean:Destroy()
local empty = Instance.new("Model")
empty.Name = "Bean"
empty.Parent = assets.Props
local none, noneWhy = MapDressing.imported("Bean")
check(none == nil and noneWhy == "no MeshPart in Bean", "a Model with no MeshPart: " .. noneWhy)
map = Map.load("BrainrotBattlefield")
for _, part in partsNamed(map, "ThroneLid") do
	check(part.Transparency < 1 and part:GetAttribute("Dressed") == nil, "the sideways lid is left out: the part shows")
end
for _, part in partsNamed(map, "ThroneTank") do
	check(part:GetAttribute("Dressed") == "ToiletTank", "the rest are still dressed")
end
-- Selftest prints a line each: catch them on the way out.
local globals = getmetatable(getfenv(1)).__index
local print0, lines = globals.print, {}
globals.print = function(...)
	table.insert(lines, table.concat({ ... }, " "))
	print0(...)
end
TestControls.selftest(nil)
globals.print = print0
local line = ""
for _, text in lines do
	if string.find(text, "Map props", 1, true) then
		line = text
	end
end
check(string.find(line, "WARN", 1, true) and string.find(line, "TankLid is the wrong way round", 1, true) and string.find(line, "no MeshPart in Bean", 1, true), "selftest reports on the props: " .. line)

return { status = "PASS", checks = checks }
