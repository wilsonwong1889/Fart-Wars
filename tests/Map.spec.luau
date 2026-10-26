-- Brainrot Battlefield v0, as MapService loads it:
--   * it keeps the MapBase contract (spawns for both teams, camera points,
--     bounds, everything anchored) and is about 160 x 160 studs
--   * it is symmetric: every part has a mirror image across z = 0
--   * three lanes: each divider wall has at least two gaps joining them
--   * each team's spawn pads are on its own half, and no straight line from
--     anywhere in the lanes or the enemy half (standing, or up on cover)
--     reaches a pad through the walls
--   * barrels are decoration: nothing on them to interact with
--   * reloading swaps the map cleanly and spawn lookups follow the new one
local ServerStorage = game:GetService("ServerStorage")
local shared = game.ReplicatedStorage.Shared
local MapConfig = require(shared.Config.MapConfig)
local MapBase = require(shared.Interfaces.MapBase)
local MapService = require(game.ServerScriptService.Server.Services.MapService)
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

local entry = MapConfig.BrainrotBattlefield
local map = MapService.load("BrainrotBattlefield")
check(map.Parent == workspace and map.Name == "Map", "the map is in Workspace")
check(map:GetAttribute("MapId") == "BrainrotBattlefield", "it says which map it is")
local ok, problems = MapBase.validate(map, entry, { "Stinkers", "Sharters" })
check(ok, "keeps the MapBase contract: " .. table.concat(problems, "; "))
check(ServerStorage.Maps:FindFirstChild("BrainrotBattlefield"), "the template lives in ServerStorage.Maps")

local ground = map.Floor.Ground
check(ground.Size.X == 160 and ground.Size.Z == 160, "a 160 x 160 arena")

local parts = {}
for _, item in map:GetDescendants() do
	if item:IsA("BasePart") then
		check(item.Anchored, `{item:GetFullName()} is anchored`)
		if not item:IsDescendantOf(map.CameraPoints) and item ~= map.Bounds then
			table.insert(parts, item)
		end
	end
end
check(#parts > 60, "there's a real layout to check")

-- Symmetry: an independent reflection across z = 0.
local function reflected(frame: CFrame): { number }
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:GetComponents()
	return { x, y, -z, r00, r01, -r02, r10, r11, -r12, -r20, -r21, r22 }
end
local function same(a: { number }, b: { number }): boolean
	for i = 1, 12 do
		if math.abs(a[i] - b[i]) > 1e-3 then
			return false
		end
	end
	return true
end
for _, part in parts do
	local want = reflected(part.CFrame)
	local found = false
	for _, other in parts do
		if other.ClassName == part.ClassName and other.Shape == part.Shape and (other.Size - part.Size).Magnitude < 1e-3
			and same({ other.CFrame:GetComponents() }, want) then
			found = true
			break
		end
	end
	check(found, `{part:GetFullName()} at {part.Position} has a mirror image`)
end

-- Lanes: each divider wall (x = ±26) has at least two gaps along Z.
for _, x in { -26, 26 } do
	local segments = {}
	for _, part in map.Walls:GetChildren() do
		if part.Name == "Divider" and math.abs(part.Position.X - x) < 0.01 then
			table.insert(segments, { part.Position.Z - part.Size.Z / 2, part.Position.Z + part.Size.Z / 2 })
		end
	end
	table.sort(segments, function(a, b)
		return a[1] < b[1]
	end)
	local gaps = 0
	for i = 2, #segments do
		if segments[i][1] - segments[i - 1][2] >= 8 then
			gaps += 1
		end
	end
	check(gaps >= 2, `the divider at x = {x} has {gaps} gaps`)
end
for _, lane in { "LaneLeft", "LaneCenter", "LaneRight" } do
	check(map.Zones:FindFirstChild(lane), `{lane} is marked`)
end

-- Spawns.
local pads = { Stinkers = MapService.spawns("Stinkers"), Sharters = MapService.spawns("Sharters") }
check(#pads.Stinkers >= 2 and #pads.Stinkers == #pads.Sharters, "the same number of pads each")
for _, pad in pads.Stinkers do
	check(pad.Position.Z < -40 and pad.TeamColor == BrickColor.new("Lime green") and not pad.Neutral, "Stinker pads are theirs, at -Z")
	check(pad.Duration == 0 and not pad.AllowTeamChangeOnTouch, "no forcefield yet, and touching doesn't switch teams")
end
for _, pad in pads.Sharters do
	check(pad.Position.Z > 40 and pad.TeamColor == BrickColor.new("New Yeller"), "Sharter pads are theirs, at +Z")
end
check(MapService.safeSpawn("Stinkers", {}) ~= nil, "a spawn with nobody around")
local nearEnemy = pads.Stinkers[1].Position
local safest = MapService.safeSpawn("Stinkers", { nearEnemy }) :: SpawnLocation
check(safest ~= pads.Stinkers[1] and (safest.Position - nearEnemy).Magnitude > 20, "spawns away from an enemy")

-- Sightlines. Blockers: the axis-aligned walls and block cover.
local blockers = {}
for _, folderName in { "Walls", "Cover" } do
	for _, part in map[folderName]:GetChildren() do
		if part.Shape == Enum.PartType.Block and part.Transparency < 0.5 then
			local half = part.Size / 2
			table.insert(blockers, { lo = part.Position - half, hi = part.Position + half })
		end
	end
end
local solid = {}
for _, part in parts do
	if part.CanCollide and part.Name ~= "Ground" and not string.find(part.Name, "Floor") and not part:IsA("SpawnLocation") then
		local half = part.Size / 2
		table.insert(solid, { lo = part.Position - half, hi = part.Position + half })
	end
end
local function hits(from: Vector3, to: Vector3, box): boolean
	local t0, t1 = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local origin, delta = from[axis], to[axis] - from[axis]
		local lo, hi = box.lo[axis], box.hi[axis]
		if math.abs(delta) < 1e-9 then
			if origin < lo or origin > hi then
				return false
			end
		else
			local a, b = (lo - origin) / delta, (hi - origin) / delta
			if a > b then
				a, b = b, a
			end
			t0, t1 = math.max(t0, a), math.min(t1, b)
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end
local function blocked(from: Vector3, to: Vector3): boolean
	for _, box in blockers do
		if hits(from, to, box) then
			return true
		end
	end
	return false
end
local function inside(point: Vector3): boolean
	for _, box in solid do
		if point.X > box.lo.X - 1 and point.X < box.hi.X + 1 and point.Z > box.lo.Z - 1 and point.Z < box.hi.Z + 1 and box.lo.Y < 3 then
			return true
		end
	end
	return false
end
local looked = 0
for team, sign in { Stinkers = 1, Sharters = -1 } do
	for _, pad in pads[team] do
		local target = pad.Position + Vector3.new(0, 3, 0)
		-- Everywhere from the lanes (past the spawn plaza) to the far wall.
		for x = -78, 78, 4 do
			for depth = -44, 78, 4 do
				local z = depth * sign
				local spot = Vector3.new(x, 0, z)
				if not inside(spot) then
					for _, eye in { 4.5, if depth >= 0 then 20 else nil } do
						local from = Vector3.new(x, eye, z)
						looked += 1
						check(blocked(from, target), `{team} pad {pad.Name} is visible from {from}`)
					end
				end
			end
		end
	end
end
check(looked > 5000, "plenty of lines checked")

for _, item in map.Decor:GetDescendants() do
	check(not (item:IsA("ClickDetector") or item:IsA("ProximityPrompt") or item:IsA("LuaSourceContainer")), "barrels do nothing")
end

-- Reload.
local oldPad = pads.Stinkers[1]
local reloaded = MapService.load("BrainrotBattlefield")
check(reloaded ~= map and map.Parent == nil and oldPad.Parent == nil, "the old map is gone")
local maps = 0
for _, child in workspace:GetChildren() do
	if child.Name == "Map" then
		maps += 1
	end
end
check(maps == 1, "only one map in Workspace")
for _, team in { "Stinkers", "Sharters" } do
	for _, pad in MapService.spawns(team) do
		check(pad:IsDescendantOf(reloaded), "spawn lookups use the new map")
	end
end
check((MapService.safeSpawn("Sharters", {}) :: SpawnLocation):IsDescendantOf(reloaded), "safe spawns too")
check(not pcall(MapService.load, "Nowhere"), "an unknown map is refused")
check(workspace:FindFirstChild("Map") == reloaded, "and leaves the current one in place")

return { status = "PASS", checks = checks, lines = looked }
