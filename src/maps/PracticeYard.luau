-- The practice yard (FeatureFlags.PRACTICE): a small walled yard built from
-- code, one for each player in one, far from the battlefield
-- (PracticeService picks where and runs what happens in it). Not a map:
-- MapConfig never lists it and nothing in it sits in a map's folders, so
-- the battlefield's barrels, walls, blasts and bots never touch it.
--
-- In the yard's own frame (the CFrame it's built at), ground at y = 0, the
-- player starts on the START pad (z = 0) looking down -Z at:
--   the stink range   three dummies in a row (z = -24) to gas till they pop
--   the zoom lane     under its arch (z = -32), a strip with arrows down
--                     the middle to the finish line (z = -64): Fart Dash
--   kaboom corner     a gas barrel ringed by three more dummies (z = -84),
--                     under its sign on the far wall
-- Walls all round, higher than a jump. Everything is anchored, the signs
-- and arrows are decor (MapKit.decor: nothing hits them), and a dummy takes
-- shots (CanQuery) but never blocks anyone (CanCollide off). How a dummy
-- looks at a gas level (its belly swells and changes colour, its face
-- worries) is PracticeYard.inflate; popping is PracticeYard.setPopped; the
-- barrel's fuse and blast are PracticeYard.setBarrel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MapConfig = require(Shared.Config.MapConfig)
local UIConfig = require(Shared.Config.UIConfig)
local PracticeConfig = require(Shared.Config.PracticeConfig)
local MapKit = require(script.Parent.MapKit)

local THEME = MapConfig.BrainrotBattlefield.theme
local DUMMY = PracticeConfig.DUMMY
local UPRIGHT = MapKit.UPRIGHT

local HALF_WIDTH = 30
local FRONT_Z, BACK_Z = 10, -100
local WALL_HEIGHT = 14
local POST_HEIGHT = 3
local HEAD_SIZE = 2.4
-- A dummy's belly and face at each gas stage (0-3; at 4 it has popped):
-- the colours of a player's belly (EffectsController).
local STAGE_COLORS = {
	Color3.fromRGB(150, 220, 90),
	Color3.fromRGB(200, 220, 70),
	Color3.fromRGB(240, 150, 60),
	Color3.fromRGB(240, 70, 50),
}
local FACES = { "🙂", "😬", "😨", "🤢" }

local PracticeYard = {}

-- Where things are, in the yard's frame.
PracticeYard.START = Vector3.new(0, 0, 0)
PracticeYard.RANGE = table.freeze({ Vector3.new(-12, 0, -24), Vector3.new(0, 0, -24), Vector3.new(12, 0, -24) })
PracticeYard.LANE = table.freeze({ from = -32, to = -64, width = 10 })
PracticeYard.BARREL = Vector3.new(0, 0, -84)
PracticeYard.CORNER = table.freeze({ Vector3.new(-8, 0, -84), Vector3.new(8, 0, -84), Vector3.new(0, 0, -92) })
-- The floor's corners (x and z), for checks.
PracticeYard.BOUNDS = table.freeze({ halfWidth = HALF_WIDTH, front = FRONT_Z, back = BACK_Z })

-- The gas stage (0-4) for `gas`, by GameConfig.GAS.STAGES.
function PracticeYard.stage(gas: number): number
	local stage = 0
	for _, threshold in GameConfig.GAS.STAGES do
		if gas >= threshold then
			stage += 1
		end
	end
	return stage
end

-- A billboard over `part`, `size` studs, lit the same in any light.
local function billboard(name: string, part: BasePart, size: Vector2, offset: Vector3): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Adornee = part
	gui.Size = UDim2.new(size.X, 0, size.Y, 0)
	gui.StudsOffset = offset
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = part
	return gui
end

-- A dummy standing on the ground at `at`: a base and a post, a belly ball
-- on the post, a head with a face, and its gas bar above. The belly and the
-- head take shots (a hit on the head is a headshot); nothing of it blocks
-- anyone. Its "Gas" attribute says how full it is.
function PracticeYard.dummy(parent: Instance, name: string, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Ground", at.Position)
	local plain = { CanCollide = false, CanQuery = false, CanTouch = false }
	local function props(extra: MapKit.Props, base: MapKit.Props): MapKit.Props
		local merged = table.clone(base)
		for key, value in extra do
			merged[key] = value
		end
		return merged
	end
	MapKit.part(model, "Base", Vector3.new(0.4, 3.2, 3.2), at * CFrame.new(0, 0.2, 0) * UPRIGHT, props(MapKit.cylinder(Color3.fromRGB(60, 56, 74)), plain))
	MapKit.part(model, "Post", Vector3.new(POST_HEIGHT, 0.6, 0.6), at * CFrame.new(0, POST_HEIGHT / 2, 0) * UPRIGHT, props(MapKit.cylinder(Color3.fromRGB(120, 112, 140)), plain))
	local shootable = { CanCollide = false, CanQuery = true, CanTouch = false, Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic }
	local body = MapKit.part(model, "Body", Vector3.one * DUMMY.MIN_SIZE, at, props({ Color = STAGE_COLORS[1] }, shootable))
	local head = MapKit.part(model, "Head", Vector3.one * HEAD_SIZE, at, props({ Color = THEME.porcelain }, shootable))
	model.PrimaryPart = body

	local face = billboard("Face", head, Vector2.new(HEAD_SIZE * 0.9, HEAD_SIZE * 0.9), Vector3.zero)
	local emoji = Instance.new("TextLabel")
	emoji.Name = "Emoji"
	emoji.BackgroundTransparency = 1
	emoji.Size = UDim2.new(1, 0, 1, 0)
	emoji.TextScaled = true
	emoji.Text = FACES[1]
	emoji.Parent = face

	local bar = billboard("GasBar", head, Vector2.new(4, 0.55), Vector3.new(0, HEAD_SIZE / 2 + 0.9, 0))
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 1, 0)
	back.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
	back.BorderSizePixel = 0
	back.Parent = bar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = STAGE_COLORS[1]
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner:Clone().Parent = fill

	model.Parent = parent
	PracticeYard.inflate(model, 0)
	return model
end

-- Shows `model` (a dummy) at `gas` (0-100): the belly from MIN_SIZE to
-- MAX_SIZE across, sitting on its post with the head on top, in its
-- stage's colour; the face and the gas bar to match.
function PracticeYard.inflate(model: Model, gas: number)
	local body = model:FindFirstChild("Body") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local ground = model:GetAttribute("Ground") :: Vector3
	local share = math.clamp(gas / 100, 0, 1)
	local size = DUMMY.MIN_SIZE + (DUMMY.MAX_SIZE - DUMMY.MIN_SIZE) * share
	local stage = math.min(PracticeYard.stage(gas), #STAGE_COLORS - 1)
	local color = STAGE_COLORS[stage + 1]
	body.Size = Vector3.one * size
	body.CFrame = CFrame.new(ground + Vector3.new(0, POST_HEIGHT + size / 2 - 0.3, 0))
	body.Color = color
	head.CFrame = CFrame.new(ground + Vector3.new(0, POST_HEIGHT + size + HEAD_SIZE / 2 - 0.6, 0))
	local face = head:FindFirstChild("Face")
	local emoji = (face and face:FindFirstChild("Emoji")) :: TextLabel?
	if emoji then
		emoji.Text = FACES[stage + 1]
	end
	local bar = head:FindFirstChild("GasBar")
	local fill = (bar and bar:FindFirstChild("Fill", true)) :: Frame?
	if fill then
		fill.Size = UDim2.new(share, 0, 1, 0)
		fill.BackgroundColor3 = color
	end
	model:SetAttribute("Gas", gas)
end

-- A dummy popped (gone: the post stays) or back (`popped` false).
function PracticeYard.setPopped(model: Model, popped: boolean)
	for _, name in { "Body", "Head" } do
		local part = model:FindFirstChild(name) :: BasePart
		part.Transparency = if popped then 1 else 0
		part.CanQuery = not popped
		for _, gui in part:GetChildren() do
			if gui:IsA("BillboardGui") then
				gui.Enabled = not popped
			end
		end
	end
	model:SetAttribute("Popped", popped)
end

-- The barrel ready to shoot, its fuse burning (a steady red outline, as on
-- the battlefield), or gone (blown up, until it's back).
function PracticeYard.setBarrel(model: Model, state: "ready" | "fused" | "gone")
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = if state == "gone" then 1 else 0
			part.CanCollide = state ~= "gone"
			part.CanQuery = state ~= "gone"
		end
	end
	local outline = model:FindFirstChild("Danger")
	if state == "fused" and not outline then
		local highlight = Instance.new("Highlight")
		highlight.Name = "Danger"
		highlight.FillColor = Color3.fromRGB(255, 60, 40)
		highlight.OutlineColor = Color3.fromRGB(255, 80, 60)
		highlight.FillTransparency = 0.5
		highlight.Adornee = model
		highlight.Parent = model
	elseif outline and state ~= "fused" then
		outline:Destroy()
	end
	model:SetAttribute("Ready", state == "ready")
end

-- Builds a yard at `origin` (its START pad; it faces down the yard).
-- Returns the model: Floor, Walls and Decor folders, the Start marker,
-- Dummies (Range1-3 and Corner1-3) and the PracticeBarrel.
function PracticeYard.build(origin: CFrame): Model
	local yard = Instance.new("Model")
	yard.Name = "PracticeYard"
	local floor = MapKit.folder("Floor", yard)
	local walls = MapKit.folder("Walls", yard)
	local decor = MapKit.folder("Decor", yard)
	local dummies = MapKit.folder("Dummies", yard)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	local length = FRONT_Z - BACK_Z
	local middle = (FRONT_Z + BACK_Z) / 2
	MapKit.part(floor, "Ground", Vector3.new(HALF_WIDTH * 2, 4, length), at(0, -2, middle), {
		Color = THEME.ground,
		Material = Enum.Material.Plastic,
	})
	local wall = { Color = THEME.wall, Material = Enum.Material.Plastic }
	local trim = MapKit.decor(THEME.wallTop, Enum.Material.Plastic)
	for _, x in { -HALF_WIDTH - 1, HALF_WIDTH + 1 } do
		MapKit.part(walls, "SideWall", Vector3.new(2, WALL_HEIGHT, length + 4), at(x, WALL_HEIGHT / 2, middle), wall)
		MapKit.part(decor, "SideTrim", Vector3.new(2.4, 1, length + 4.4), at(x, WALL_HEIGHT + 0.5, middle), trim)
	end
	for _, z in { FRONT_Z + 1, BACK_Z - 1 } do
		MapKit.part(walls, "EndWall", Vector3.new(HALF_WIDTH * 2, WALL_HEIGHT, 2), at(0, WALL_HEIGHT / 2, z), wall)
		MapKit.part(decor, "EndTrim", Vector3.new(HALF_WIDTH * 2 - 0.4, 1, 2.4), at(0, WALL_HEIGHT + 0.5, z), trim)
	end

	-- START: where the avatar appears, looking down the yard.
	MapKit.part(decor, "StartPad", Vector3.new(8, 0.2, 8), at(0, 0.1, 0), MapKit.decor(UIConfig.colors.play, Enum.Material.Neon, { CastShadow = false }))
	MapKit.marker(yard, "Start", Vector3.new(4, 1, 4), at(0, 0.5, 0))

	-- The stink range: three dummies, a sign hung over them.
	for i, spot in PracticeYard.RANGE do
		PracticeYard.dummy(dummies, `Range{i}`, at(spot.X, 0, spot.Z))
	end
	local rangeSign = MapKit.part(decor, "RangeSign", Vector3.new(26, 5, 1), at(0, 12, -30), MapKit.decor(THEME.crate))
	MapKit.sign(rangeSign, "🎯 STINK RANGE", UIConfig.colors.text)

	-- The zoom lane: an arch at its start, arrows down it, the finish line.
	local lane = PracticeYard.LANE
	local laneLength = lane.from - lane.to
	MapKit.part(decor, "Lane", Vector3.new(lane.width, 0.2, laneLength), at(0, 0.1, (lane.from + lane.to) / 2), MapKit.decor(THEME.lanes.Center, Enum.Material.Plastic))
	for _, x in { -lane.width / 2 - 2, lane.width / 2 + 2 } do
		MapKit.part(walls, "ArchPost", Vector3.new(1.5, 10, 1.5), at(x, 5, lane.from), { Color = THEME.wall, Material = Enum.Material.Plastic })
	end
	local arch = MapKit.part(decor, "LaneSign", Vector3.new(lane.width + 5.5, 3, 1), at(0, 11.5, lane.from), MapKit.decor(THEME.trim))
	MapKit.sign(arch, "💨 ZOOM LANE", UIConfig.colors.text)
	local arrow = MapKit.decor(THEME.barrelBand, Enum.Material.Neon, { CastShadow = false })
	for _, z in { lane.from - 6, lane.from - 14, lane.from - 22 } do
		-- A chevron pointing down the lane: its tip toward -Z.
		MapKit.part(decor, "Arrow", Vector3.new(0.6, 0.22, 2.9), at(-1, 0.12, z + 0.3) * CFrame.Angles(0, math.rad(-45), 0), arrow)
		MapKit.part(decor, "Arrow", Vector3.new(0.6, 0.22, 2.9), at(1, 0.12, z + 0.3) * CFrame.Angles(0, math.rad(45), 0), arrow)
	end
	MapKit.part(decor, "FinishLine", Vector3.new(lane.width, 0.22, 1), at(0, 0.12, lane.to), arrow)

	-- Kaboom corner: the barrel, three dummies round it, the sign behind.
	local barrel = Instance.new("Model")
	barrel.Name = "PracticeBarrel"
	local spot = PracticeYard.BARREL
	local body = MapKit.part(barrel, "Barrel", Vector3.new(5, 4, 4), at(spot.X, 2.5, spot.Z) * UPRIGHT, MapKit.cylinder(THEME.barrel))
	MapKit.part(barrel, "Band", Vector3.new(0.6, 4.2, 4.2), at(spot.X, 2.5, spot.Z) * UPRIGHT, MapKit.cylinder(THEME.barrelBand, Enum.Material.Neon))
	barrel.PrimaryPart = body
	barrel.Parent = yard
	PracticeYard.setBarrel(barrel, "ready")
	for i, corner in PracticeYard.CORNER do
		PracticeYard.dummy(dummies, `Corner{i}`, at(corner.X, 0, corner.Z))
	end
	local cornerSign = MapKit.part(decor, "CornerSign", Vector3.new(24, 5, 1), at(0, 10, BACK_Z + 0.6), MapKit.decor(THEME.bean))
	MapKit.sign(cornerSign, "💥 KABOOM CORNER", UIConfig.colors.text)

	-- Nobody streams it in and out: the player in it is the only one near.
	pcall(function()
		(yard :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	return yard
end

return PracticeYard
