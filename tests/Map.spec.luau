-- Brainrot Battlefield v0, as MapService loads it:
--   * it keeps the MapBase contract (spawns for both teams, camera points,
--     bounds, everything anchored) and is its 160 x 160 stud layout built
--     MapConfig's `scale` times bigger (the numbers below are the layout's,
--     times S), with the floors and pads still flat
--   * it is symmetric: every part has a mirror image across z = 0
--   * three lanes: each divider wall has at least two gaps joining them
--   * cover in two heights: low cover (the plaza and alley walls, the
--     crates) grows across with the map but stays about an avatar's height,
--     standing on the ground, low enough to jump onto; the rest (the
--     throne, the bean cans, the Gutter's toilet) is the layout's times S
--     and still towers over everyone (MapKit.scale's KeepHeight, checked
--     on its own too)
--   * each team's spawn pads are on its own half, and no straight line from
--     anywhere in the lanes or the enemy half (standing, up on low cover,
--     or on the enemy half up on anything) reaches a pad through the walls
--   * each lane's name is on a gate across its entrance on both halves,
--     reading both ways and lit, in sight of where that team comes out of
--     its spawn corridor; the gates are decor up above the dividers (no
--     collisions, no hits, nothing to get stuck in) and the spawn check
--     doesn't count on them; a few dozen parts
--   * gas barrels (plain models; the server makes them explosive) sit in
--     the contested middle, well away from both spawns
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
local S = entry.scale
local map = MapService.load("BrainrotBattlefield")
check(map.Parent == workspace and map.Name == "Map", "the map is in Workspace")
check(map:GetAttribute("MapId") == "BrainrotBattlefield", "it says which map it is")
local ok, problems = MapBase.validate(map, entry, { "Stinkers", "Sharters" })
check(ok, "keeps the MapBase contract: " .. table.concat(problems, "; "))
check(ServerStorage.Maps:FindFirstChild("BrainrotBattlefield"), "the template lives in ServerStorage.Maps")

local ground = map.Floor.Ground
check(ground.Size.X == 160 * S and ground.Size.Z == 160 * S, `a {160 * S} x {160 * S} arena`)
check(math.abs(ground.Position.Y + ground.Size.Y / 2) < 1e-3, "its top still at y = 0")
for _, pad in MapService.spawns("Stinkers") do
	check(pad.Size.Y == 1 and pad.Size.X == 6 * S and math.abs(pad.Position.Y - 0.5) < 1e-3, "a spawn pad grows across, not up")
end
check(map.Floor.LaneCenterFloor.Size.Y == 0.2, "a lane floor stays a floor")

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

-- A part's box in world space (the kit only turns parts by quarter turns).
local function bounds(part: BasePart): (Vector3, Vector3)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
	local s = part.Size / 2
	local half = Vector3.new(
		math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z,
		math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z,
		math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z
	)
	return part.Position - half, part.Position + half
end

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
		-- Pads are square and each faces the middle: mirrored in place, not turn.
		local matches = if part:IsA("SpawnLocation")
			then (other.Position - Vector3.new(want[1], want[2], want[3])).Magnitude < 1e-3
			else same({ other.CFrame:GetComponents() }, want)
		if other.ClassName == part.ClassName and other.Shape == part.Shape and (other.Size - part.Size).Magnitude < 1e-3 and matches then
			found = true
			break
		end
	end
	check(found, `{part:GetFullName()} at {part.Position} has a mirror image`)
end

-- Lanes: each divider wall (x = ±26) has at least two gaps along Z.
for _, x in { -26 * S, 26 * S } do
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
		if segments[i][1] - segments[i - 1][2] >= 8 * S then
			gaps += 1
		end
	end
	check(gaps >= 2, `the divider at x = {x} has {gaps} gaps`)
end
for _, lane in { "LaneLeft", "LaneCenter", "LaneRight" } do
	check(map.Zones:FindFirstChild(lane), `{lane} is marked`)
end

-- Cover heights. MapKit.scale on its own first: a KeepHeight part grows
-- across and stays where it stands, a plain one grows every way, and a
-- light reaches further, up to Roblox's limit.
do
	local MapKit = require(ServerStorage.Maps.MapKit) :: any
	local model = Instance.new("Model")
	local low = MapKit.part(model, "Low", Vector3.new(4, 5, 2), CFrame.new(10, 2.5, -6), { KeepHeight = true })
	local tall = MapKit.part(model, "Tall", Vector3.new(4, 5, 2), CFrame.new(10, 2.5, 6))
	local near, far = MapKit.light(tall, Color3.new(1, 1, 1), 15), MapKit.light(low, Color3.new(1, 1, 1), 30)
	MapKit.scale(model, 3)
	check((low.Size - Vector3.new(12, 5, 6)).Magnitude < 1e-3 and (low.Position - Vector3.new(30, 2.5, -18)).Magnitude < 1e-3, "KeepHeight: grows across, keeps its height, stays on the ground")
	check((tall.Size - Vector3.new(12, 15, 6)).Magnitude < 1e-3 and (tall.Position - Vector3.new(30, 7.5, 18)).Magnitude < 1e-3, "anything else grows every way")
	check(near.Range == 45 and far.Range == MapKit.MAX_LIGHT_RANGE, "lights reach further, up to the limit")
	model:Destroy()
end
-- On the map: low cover (laid out at avatar height to duck behind, shoot
-- past and lob over) grows across but not up; every other piece of cover
-- is the layout's size times S.
local AVATAR_HEIGHT = 5 -- a standard avatar, near enough
local JUMP_HEIGHT = 7.2 -- Humanoid.JumpHeight's default
local LOW_COVER = { PlazaWall = true, AlleyWall = true, Crate = true }
local layoutEntry = table.clone(entry)
layoutEntry.scale = 1
local layout = (require(ServerStorage.Maps.BrainrotBattlefield) :: any).build(layoutEntry)
local function laidOut(part: BasePart): BasePart?
	for _, candidate in layout.Cover:GetChildren() do
		local at = candidate.Position * S
		if candidate.Name == part.Name and math.abs(at.X - part.Position.X) < 1e-3 and math.abs(at.Z - part.Position.Z) < 1e-3 then
			return candidate
		end
	end
	return nil
end
local lowTop, lowFound = 0, {}
for _, part in map.Cover:GetChildren() do
	local original = laidOut(part)
	check(original, `{part:GetFullName()} at {part.Position} is in the layout`)
	local low = LOW_COVER[part.Name] == true
	check((part:GetAttribute("KeepHeight") == true) == low, `{part.Name} is {if low then "" else "not "}marked as low cover`)
	if low and original then
		lowFound[part.Name] = true
		local height = part.Size.Y
		check(height == original.Size.Y and math.abs(part.Size.X - original.Size.X * S) < 1e-3 and math.abs(part.Size.Z - original.Size.Z * S) < 1e-3, `{part.Name} grows across with the map, not up ({part.Size})`)
		check(math.abs(part.Position.Y - height / 2) < 1e-3, `{part.Name} stands on the ground`)
		check(height >= 4 and height <= AVATAR_HEIGHT + 1 and height < JUMP_HEIGHT, `{part.Name} is about an avatar's height, low enough to jump onto ({height})`)
		lowTop = math.max(lowTop, height)
	elseif original then
		check((part.Size - original.Size * S).Magnitude < 1e-3 and (part.Position - original.Position * S).Magnitude < 1e-3, `{part.Name} at {part.Position} is the layout's times {S}`)
	end
end
for name in LOW_COVER do
	check(lowFound[name], `there's low cover: {name}`)
end
for _, name in { "ThroneTank", "BeanCan", "GutterTank" } do
	local part = map.Cover:FindFirstChild(name) :: BasePart
	local _, top = bounds(part)
	check(top.Y > AVATAR_HEIGHT + JUMP_HEIGHT, `{name} still towers over everyone ({top.Y} studs)`)
end
layout:Destroy()

-- Spawns.
local pads = { Stinkers = MapService.spawns("Stinkers"), Sharters = MapService.spawns("Sharters") }
check(#pads.Stinkers >= 2 and #pads.Stinkers == #pads.Sharters, "the same number of pads each")
for _, pad in pads.Stinkers do
	check(pad.Position.Z < -40 * S and pad.TeamColor == BrickColor.new("Lime green") and not pad.Neutral, "Stinker pads are theirs, at -Z")
	check(pad.Duration == 0 and not pad.AllowTeamChangeOnTouch, "no forcefield yet, and touching doesn't switch teams")
	check(pad.CFrame.LookVector.Z > 0.99, "and faces the middle of the map (+Z), not its own back wall")
end
for _, pad in pads.Sharters do
	check(pad.Position.Z > 40 * S and pad.TeamColor == BrickColor.new("New Yeller"), "Sharter pads are theirs, at +Z")
	check(pad.CFrame.LookVector.Z < -0.99, "and faces the middle of the map (-Z)")
end
check(MapService.safeSpawn("Stinkers", {}) ~= nil, "a spawn with nobody around")
local nearEnemy = pads.Stinkers[1].Position
local safest = MapService.safeSpawn("Stinkers", { nearEnemy }) :: SpawnLocation
check(safest ~= pads.Stinkers[1] and (safest.Position - nearEnemy).Magnitude > 20 * S, "spawns away from an enemy")

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
-- Eyes: standing; up on low cover (anyone can jump onto it, so check it
-- everywhere); and on the enemy half, up on anything.
local onLowCover = lowTop + 4.5
for team, sign in { Stinkers = 1, Sharters = -1 } do
	for _, pad in pads[team] do
		local target = pad.Position + Vector3.new(0, 3, 0)
		-- Everywhere from the lanes (past the spawn plaza) to the far wall.
		for x = -78 * S, 78 * S, 4 * S do
			for depth = -44 * S, 78 * S, 4 * S do
				local z = depth * sign
				local spot = Vector3.new(x, 0, z)
				if not inside(spot) then
					for _, eye in { 4.5, onLowCover, if depth >= 0 then 20 else nil } do
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

-- Landmarks: the lane gates. All decor up above the dividers: never in a
-- player's way or line of fire, nothing to get stuck in, and not one of
-- the spawn check's blockers (Walls and Cover only), so the spawns would
-- be just as hidden without them.
local landmarks = map:FindFirstChild("Landmarks")
check(landmarks, "the lanes have their landmarks")
local dividerTop = 0
for _, part in map.Walls:GetChildren() do
	if part.Name == "Divider" then
		dividerTop = math.max(dividerTop, part.Position.Y + part.Size.Y / 2)
	end
end
check(dividerTop > 0, "dividers to measure against")
local decorParts, lights = 0, 0
for _, item in landmarks:GetDescendants() do
	if item:IsA("BasePart") then
		decorParts += 1
		local lo = bounds(item)
		check(not item.CanCollide and not item.CanQuery and not item.CanTouch, `{item:GetFullName()} is decor: walked and shot through, never hit`)
		check(lo.Y >= dividerTop - 1e-3, `{item:GetFullName()} is up above the dividers, out of reach (from {lo.Y})`)
	elseif item:IsA("Light") then
		lights += 1
		local light = item :: any
		check(not light.Shadows and light.Range <= 60, `{item:GetFullName()}: an accent light, no shadows`)
	end
end
check(decorParts >= 20 and decorParts <= 48, `a few dozen parts, not hundreds ({decorParts})`)
check(lights >= 6 and lights <= 12, `the signs are lit ({lights} lights)`)
-- Each lane's sign, on both halves, reads both ways, sits over its lane,
-- and is in plain sight (no wall or cover in the way, cylinders counted by
-- their boxes) from where that team comes out of its spawn corridor:
-- the side lanes' from the corridor's ends, the plaza's from the side
-- lanes beside the gaps into it. Spots are the layout's (times S).
local LANE_SIGNS = {
	["BEAN ALLEY"] = { zone = "LaneLeft", from = { Vector3.new(-30, 0, -78) } },
	["PORCELAIN PLAZA"] = { zone = "LaneCenter", from = { Vector3.new(-30, 0, -50), Vector3.new(30, 0, -50) } },
	["GAS GUTTER"] = { zone = "LaneRight", from = { Vector3.new(30, 0, -78) } },
}
local opaque = {}
for _, folderName in { "Walls", "Cover" } do
	for _, part in map[folderName]:GetChildren() do
		local lo, hi = bounds(part)
		table.insert(opaque, { lo = lo, hi = hi })
	end
end
local signsFound = {}
for _, item in landmarks:GetChildren() do
	local faces, text = {}, nil
	for _, gui in item:GetChildren() do
		local label = gui:IsA("SurfaceGui") and gui:FindFirstChildWhichIsA("TextLabel")
		if label then
			faces[gui.Face] = true
			check(text == nil or text == label.Text, `{item:GetFullName()} says one thing`)
			text = label.Text
		end
	end
	local lane = text and LANE_SIGNS[text]
	if text then
		check(lane, `{item:GetFullName()} names a lane: {text}`)
		check(faces[Enum.NormalId.Front] and faces[Enum.NormalId.Back], `{text} reads both ways`)
		local side = if item.Position.Z < 0 then 1 else -1
		signsFound[`{text} {side}`] = true
		local zone = map.Zones:FindFirstChild(lane.zone) :: BasePart
		check(math.abs(item.Position.X - zone.Position.X) < zone.Size.X / 2, `{text} hangs over its lane`)
		for _, spot in lane.from do
			local from = Vector3.new(spot.X * S, 4.5, spot.Z * S * side)
			local seen = true
			for _, box in opaque do
				if hits(from, item.Position, box) then
					seen = false
				end
			end
			check(seen, `{text} on the {if side == 1 then "Stinkers'" else "Sharters'"} half is in sight from {from}`)
		end
	end
end
for text in LANE_SIGNS do
	check(signsFound[`{text} 1`] and signsFound[`{text} -1`], `{text} has a sign on each half`)
end

local barrels = 0
for _, gasBarrel in map.Barrels:GetChildren() do
	check(gasBarrel:IsA("Model") and gasBarrel.Name == "GasBarrel" and gasBarrel.PrimaryPart == gasBarrel:FindFirstChild("Barrel"), "each barrel is a GasBarrel model")
	for _, item in gasBarrel:GetDescendants() do
		check(item:IsA("BasePart"), "barrels are only parts (the server makes them explosive)")
	end
	local barrel = gasBarrel.PrimaryPart
	barrels += 1
	check(math.abs(barrel.Position.Z) <= 30 * S, `the barrel at {barrel.Position} is in the contested middle`)
	for _, team in { "Stinkers", "Sharters" } do
		for _, pad in pads[team] do
			check((barrel.Position - pad.Position).Magnitude >= 30 * S, `the barrel at {barrel.Position} is well away from {team} spawns`)
		end
	end
end
check(barrels == 12, "six barrels a half")

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
