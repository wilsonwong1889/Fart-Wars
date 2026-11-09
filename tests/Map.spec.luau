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
--   * launch pads (behind their flag): four a half, each the other half's
--     mirror; cushions flat on the ground in a lane on their own half, out
--     of the spawn zones, nothing on them; every arc, flown from the
--     cushion's middle and all round its edge with an avatar's box, clears
--     every wall and piece of cover, peaks under the dividers' tops and
--     the gates, stays on its own half and comes down in about a second on
--     open ground well inside the walls, nearer the middle, far from the
--     other team's spawn and on no other pad, with room to run on
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
end
for _, pad in pads.Sharters do
	check(pad.Position.Z > 40 * S and pad.TeamColor == BrickColor.new("New Yeller"), "Sharter pads are theirs, at +Z")
end
for _, pad in pads.Stinkers do
	local mirror = nil
	for _, candidate in pads.Sharters do
		if candidate.Name == pad.Name then
			mirror = candidate
		end
	end
	check(mirror, `{pad.Name} has a Sharters pad of the same name`)
	local look, other = pad.CFrame.LookVector, mirror.CFrame.LookVector
	check(math.abs(look.Y) < 1e-3 and math.abs(other.Y) < 1e-3, `{pad.Name}: both teams' pads face level`)
	check((other - Vector3.new(look.X, 0, -look.Z)).Magnitude < 1e-3, `{pad.Name}: the Sharters' pad faces the mirror image of the Stinkers' way`)
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
-- Every life starts facing the way out. The spawn room is solid at the
-- front and sides with its doors in the back wall, so a pad facing the
-- middle put a wall in your face each spawn: straight ahead from each pad
-- leaves the room through a door and reaches the corridor along the end
-- wall (z -80..-76 in the layout) with nothing in the way.
for team, sign in { Stinkers = 1, Sharters = -1 } do
	for _, pad in pads[team] do
		local look = pad.CFrame.LookVector
		local from = pad.Position + Vector3.new(0, 3, 0)
		check(look.Z * sign < -0.3, `{team} {pad.Name} faces toward its back wall's doors, not the solid front`)
		local out = from + look * ((-78 * S * sign - from.Z) / look.Z)
		check(not blocked(from, out), `{team} {pad.Name}: straight ahead leads out a door, to {out}`)
		check(blocked(from, from + Vector3.new(0, 0, 40 * S * sign)), `{team} {pad.Name}: the front is still solid (so facing it would be a wall)`)
	end
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

-- Launch pads.
local FeatureFlags = require(shared.Config.FeatureFlags)
local LaunchPadConfig = require(shared.Config.LaunchPadConfig)
local LaunchPads = require(shared.LaunchPads)
local launchPads = LaunchPads.list(map)
local flown = 0
if not FeatureFlags.LAUNCH_PADS then
	check(#launchPads == 0 and map:FindFirstChild("LaunchPads") == nil, "launch pads off: the map has none")
else
	check(#launchPads == 8, `four launch pads a half ({#launchPads})`)
	-- What an arc can run into: everything solid but the floors, the spawn
	-- pads and the launch pads' cushions (flat on the ground, and where
	-- every arc starts).
	local obstacles = {}
	for _, part in parts do
		local cushion = part.Name == "Pad" and part.Parent and part.Parent.Parent == map.LaunchPads
		if part.CanCollide and part.Name ~= "Ground" and not string.find(part.Name, "Floor") and not part:IsA("SpawnLocation") and not cushion then
			local lo, hi = bounds(part)
			table.insert(obstacles, { lo = lo, hi = hi, name = part:GetFullName() })
		end
	end
	-- An avatar's box, feet at `feet`: 3 studs across, 5.5 tall.
	local RADIUS, HEIGHT = 1.5, 5.5
	-- The gap between the avatar's box and the nearest obstacle's
	-- (negative: they overlap), and which obstacle.
	local function clearance(feet: Vector3): (number, string)
		local alo = feet - Vector3.new(RADIUS, 0, RADIUS)
		local ahi = feet + Vector3.new(RADIUS, HEIGHT, RADIUS)
		local best, who = math.huge, "nothing"
		for _, box in obstacles do
			local gap = math.max(box.lo.X - ahi.X, alo.X - box.hi.X, box.lo.Y - ahi.Y, alo.Y - box.hi.Y, box.lo.Z - ahi.Z, alo.Z - box.hi.Z)
			if gap < best then
				best, who = gap, box.name
			end
		end
		return best, who
	end
	local zones = {}
	for _, zone in map.Zones:GetChildren() do
		zones[zone] = { bounds(zone) }
	end
	local function within(point: Vector3, zone: BasePart, margin: number): boolean
		local lo, hi = zones[zone][1], zones[zone][2]
		return point.X >= lo.X - margin and point.X <= hi.X + margin and point.Z >= lo.Z - margin and point.Z <= hi.Z + margin
	end
	local spawnZones = {}
	for _, zone in map.Zones:GetChildren() do
		if zone.Name == "SpawnZone" then
			table.insert(spawnZones, zone)
		end
	end
	check(#spawnZones == 2, "a spawn zone each")
	local lanes = { map.Zones.LaneLeft, map.Zones.LaneCenter, map.Zones.LaneRight }
	local bound = map.Bounds
	local edgeLo, edgeHi = bound.Position - bound.Size / 2, bound.Position + bound.Size / 2
	local gateBottom = math.huge
	for _, item in landmarks:GetDescendants() do
		if item:IsA("BasePart") then
			gateBottom = math.min(gateBottom, (bounds(item)).Y)
		end
	end
	local LIFT = 3 -- a standing avatar's root over its feet
	local CLEAR = 1 -- the least room an arc leaves round the avatar
	local RUNOUT = 12 -- open ground past the landing, to run on after it
	local byName = {}
	for _, pad in launchPads do
		byName[pad.Name] = pad
		local half = pad:GetAttribute("Half")
		local side = if half == "Stinkers" then -1 else 1
		check((half == "Stinkers" or half == "Sharters") and string.sub(pad.Name, 1, #half) == half, `{pad.Name} says which half it's on`)
		-- Placement: a walkable cushion flat on the ground, in a lane on
		-- its own half, clear of both spawn zones and of every solid thing.
		local cushion = pad.Pad :: BasePart
		local top, radius = LaunchPads.cushion(pad)
		local lo, hi = bounds(cushion)
		check(cushion.CanCollide and cushion.Transparency == 0 and math.abs(lo.Y) < 1e-3 and hi.Y <= 1, `{pad.Name}'s cushion lies on the ground, to walk on`)
		check(radius >= 6 and top.Z * side > 40 * S, `{pad.Name} is a big cushion on its own half (radius {radius}, at {top})`)
		for _, item in pad:GetDescendants() do
			if item:IsA("BasePart") and item ~= cushion then
				local itemLo, itemHi = bounds(item)
				check(not item.CanCollide and not item.CanQuery and not item.CanTouch, `{item:GetFullName()} is never in the way`)
				check(item.Name == "Target" or (math.abs(itemLo.Y) < 1e-3 and itemHi.Y <= 1), `{item:GetFullName()} lies flat with the cushion`)
			end
		end
		check((pad.Target :: BasePart).Transparency == 1, `{pad.Name}'s landing marker is invisible`)
		local inLane = false
		for _, lane in lanes do
			inLane = inLane or within(top, lane, -radius)
		end
		check(inLane, `{pad.Name} stands in a lane`)
		for _, zone in spawnZones do
			check(not within(top, zone, radius + 3), `{pad.Name} is out of the spawn zones`)
		end
		local footprint = clearance(top - Vector3.new(0, 0.8, 0))
		check(footprint > radius - RADIUS + 2, `nothing stands on {pad.Name} or crowds it ({footprint})`)
		for _, other in launchPads do
			if other ~= pad then
				local otherTop, otherRadius = LaunchPads.cushion(other)
				check((otherTop - top).Magnitude > radius + otherRadius + 30, `{pad.Name} is well apart from {other.Name}`)
			end
		end
		-- The landing: on open ground on the pad's own half, nearer the
		-- middle than the pad, well inside the walls, out of both spawn
		-- zones, far from the other team's spawn pads, on no other pad.
		local landing, apex = LaunchPads.landing(pad)
		local direction = LaunchPads.direction(pad)
		check(math.abs(landing.Y) < 0.25, `{pad.Name} lands on the ground ({landing.Y})`)
		check(landing.Z * side > 0 and math.abs(landing.Z) < math.abs(top.Z) - 60, `{pad.Name} throws toward the middle and stays on its own half ({landing})`)
		check(landing.X > edgeLo.X + 30 and landing.X < edgeHi.X - 30 and landing.Z > edgeLo.Z + 30 and landing.Z < edgeHi.Z - 30, `{pad.Name} lands well inside the walls`)
		for _, zone in spawnZones do
			check(not within(landing, zone, 40), `{pad.Name} lands nowhere near a spawn zone`)
		end
		for team, list in pads do
			for _, spawn in list do
				local far = (spawn.Position - landing).Magnitude
				check(far > (if team == half then 60 else 150), `{pad.Name} lands {math.floor(far)} studs from {team}' {spawn.Name}`)
			end
		end
		for _, other in launchPads do
			local otherTop, otherRadius = LaunchPads.cushion(other)
			check(Vector3.new(landing.X - otherTop.X, 0, landing.Z - otherTop.Z).Magnitude > otherRadius + RUNOUT, `{pad.Name} doesn't land on {other.Name}`)
		end
		for step = 0, RUNOUT, 2 do
			local spot = landing + direction * step + Vector3.new(0, 0.2, 0)
			local room, who = clearance(spot)
			check(room > 2, `{pad.Name}: open ground {step} studs past the landing ({room} from {who})`)
		end
		-- The arc, from the cushion's middle and all round its edge: clear of
		-- every wall and piece of cover, under the gates, never as high as a
		-- divider's top (so nobody comes down on one), back down in about a
		-- second, and on its own half all the way.
		check(apex + HEIGHT < dividerTop - 1 and apex + HEIGHT < gateBottom - 4, `{pad.Name} peaks at {apex}: below the dividers' tops and the gates`)
		local starts = { top }
		for k = 0, 7 do
			local angle = k * math.pi / 4
			table.insert(starts, top + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius - 0.5))
		end
		for _, start in starts do
			local arc = LaunchPads.arc(pad, start + Vector3.new(0, LIFT, 0), LIFT, LaunchPads.GRAVITY)
			check(arc.seconds > 0.6 and arc.seconds < 1.4 and Vector3.new(arc.velocity.X, 0, arc.velocity.Z).Magnitude < 150, `{pad.Name}: a flight of {arc.seconds} s`)
			local least, nearest, at = math.huge, "nothing", start
			local samples = math.ceil(arc.seconds / 0.01)
			local onHalf = true
			for i = 1, samples do
				local feet = LaunchPads.at(arc, arc.seconds * i / samples) - Vector3.new(0, LIFT, 0)
				local room, who = clearance(feet)
				if room < least then
					least, nearest, at = room, who, feet
				end
				onHalf = onHalf and feet.Z * side > 0
			end
			check(least >= CLEAR, `{pad.Name}'s arc from {start} comes within {least} of {nearest} at {at}`)
			check(onHalf, `{pad.Name}'s arc from {start} stays on its own half`)
			local down = LaunchPads.at(arc, arc.seconds) - Vector3.new(0, LIFT, 0)
			check((down - landing).Magnitude < 0.05, `{pad.Name}'s arc from {start} comes down on its landing spot`)
			flown += 1
		end
	end
	-- Each half's pads are the other's mirror image: cushion, landing, peak.
	for _, pad in launchPads do
		if pad:GetAttribute("Half") == "Stinkers" then
			local twin = byName["Sharters" .. string.sub(pad.Name, #"Stinkers" + 1)]
			check(twin, `{pad.Name} has a twin on the Sharters' half`)
			local top, landing, apex = LaunchPads.cushion(pad), LaunchPads.landing(pad)
			local twinTop, twinLanding, twinApex = LaunchPads.cushion(twin), LaunchPads.landing(twin)
			local function mirrored(a: Vector3, b: Vector3): boolean
				return (Vector3.new(a.X, a.Y, -a.Z) - b).Magnitude < 1e-3
			end
			check(mirrored(top, twinTop) and mirrored(landing, twinLanding) and math.abs(apex - twinApex) < 1e-3, `{twin.Name} mirrors {pad.Name}`)
		end
	end
	check(flown == 72, `every arc flown ({flown})`)
	check(LaunchPadConfig.COOLDOWN_SECONDS > 0, "a cooldown between launches")
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
