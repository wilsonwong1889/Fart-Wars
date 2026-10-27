-- The free spin's prize wheel, built in code: a coloured segment for each
-- prize (RewardsConfig.spin) with its icon, amount and exact chance, a
-- pointer at the top, lights round the rim and a hub. The segments are
-- the same size; the chances printed on them are the real ones.
--   reset()           no banner, the cards back to size
--   windUp()          a short pull back while the server draws
--   spinTo(id)        spins and slows to land on that prize, ticking past
--                     each segment (yields until it lands)
--   settle()          back to rest, for a refused spin
--   celebrate(id, text)  the win: the segment pops, the lights flash, a
--                     banner says what came, and confetti
-- Reduce Motion: a short spin, steady lights, no confetti.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local UI = require(script.Parent.UI)
local Audio = require(script.Parent.Audio)
local Settings = require(script.Parent.Settings)

local C = UIConfig.colors

local SpinWheel = {}
SpinWheel.__index = SpinWheel

-- A spin's length and whole turns before it lands (Reduce Motion: CALM_).
SpinWheel.SECONDS = 4.5
SpinWheel.TURNS = 5
SpinWheel.CALM_SECONDS = 1.5
SpinWheel.CALM_TURNS = 1
SpinWheel.WIND_UP_SECONDS = 0.25

-- Degrees between the strips that fill each segment (Roblox has no
-- wedges, so each is a fan of thin strips from the centre).
local STRIP = 2
local RIM = 12
local LIGHTS = 16
local GOLD = Color3.fromRGB(255, 205, 50)
local RIM_COLOR = Color3.fromRGB(46, 34, 66)
local LIGHT_OFF = Color3.fromRGB(110, 80, 50)
-- A cosmetic prize (the jackpot): dark, with gold writing.
local JACKPOT = Color3.fromRGB(52, 30, 86)
-- The other segments' colours, in turn.
local COLORS = {
	Color3.fromRGB(92, 205, 50),
	Color3.fromRGB(45, 155, 245),
	Color3.fromRGB(165, 90, 235),
	Color3.fromRGB(240, 120, 40),
	Color3.fromRGB(30, 185, 160),
	Color3.fromRGB(235, 70, 120),
}

export type Prize = { id: string, label: string, coins: number?, xp: number?, cosmetic: string?, weight: number }

-- A prize's icon and short name for its segment.
function SpinWheel.describe(prize: Prize): (string, string)
	if prize.cosmetic then
		local cosmetic = ProgressionConfig.cosmetics[prize.cosmetic]
		return "✨", if cosmetic then cosmetic.name else prize.label
	elseif prize.xp then
		return "⭐", `{UI.commas(prize.xp)} XP`
	end
	return "💰", UI.commas(prize.coins or 0)
end

-- A frame the size of the disc, turned `degrees` about its centre, so
-- what's put at its top sits at that angle on the wheel.
local function spoke(parent: Instance, name: string, degrees: number): Frame
	return UI.new("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Rotation = degrees,
		Parent = parent,
	})
end

local function circle(): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

-- Builds the wheel in `parent`, `radius` pixels to the segments' edge.
-- `prizes` with each one's chance (0-1).
function SpinWheel.new(parent: Instance, prizes: { Prize }, chance: (Prize) -> number, radius: number)
	local self = setmetatable({}, SpinWheel)
	self.prizes = prizes
	self.seg = 360 / #prizes
	self.radius = radius
	self.rotation = 0
	self.lastIndex = 1
	self.lastTick = -1
	self.flick = 0
	self.spinning = false
	self.rng = Random.new()
	self.index = {} :: { [string]: number }
	self.cards = {} :: { [string]: Frame }

	local size = (radius + RIM) * 2
	local holder = UI.new("Frame", {
		Name = "Wheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, size, 0, size),
		BackgroundColor3 = RIM_COLOR,
		Parent = parent,
	}, { circle(), UI.stroke(C.stroke, 4) })
	self.holder = holder

	local disc = UI.new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, radius * 2, 0, radius * 2),
		BackgroundColor3 = C.stroke,
		Parent = holder,
	}, { circle() })
	self.disc = disc

	-- Strips wide enough to meet at the rim.
	local width = math.ceil(2 * radius * math.sin(math.rad(STRIP / 2))) + 1
	for i, prize in prizes do
		self.index[prize.id] = i
		local color = if prize.cosmetic then JACKPOT else COLORS[(i - 1) % #COLORS + 1]
		local from = (i - 1) * self.seg
		local angle = from + STRIP / 2
		while angle < from + self.seg do
			UI.new("Frame", {
				Name = "Strip",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0, width, 0.5, 0),
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				Parent = spoke(disc, `Segment{i}`, angle),
			})
			angle += STRIP
		end
	end
	-- Dividers, then each prize's card along its segment's middle.
	for i in prizes do
		UI.new("Frame", {
			Name = "Divider",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 5, 0.5, 0),
			BorderSizePixel = 0,
			BackgroundColor3 = C.stroke,
			Parent = spoke(disc, `Divider{i}`, (i - 1) * self.seg),
		})
	end
	for i, prize in prizes do
		local icon, name = SpinWheel.describe(prize)
		local card = UI.new("Frame", {
			Name = prize.id,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, radius * 0.07),
			Size = UDim2.new(0, radius * 0.62, 0, radius * 0.6),
			BackgroundTransparency = 1,
			Parent = spoke(disc, `Card{i}`, (i - 0.5) * self.seg),
		}, { UI.new("UIScale", { Name = "Pop" }) })
		UI.label(icon, math.floor(radius * 0.17), {
			Name = "Icon",
			Size = UDim2.new(1, 0, 0.36, 0),
			Parent = card,
		})
		UI.label(name, math.floor(radius * 0.1), {
			Name = "Amount",
			Position = UDim2.new(0, 0, 0.36, 0),
			Size = UDim2.new(1, 0, 0.34, 0),
			TextWrapped = true,
			TextColor3 = if prize.cosmetic then GOLD else C.text,
			Parent = card,
		})
		UI.label(string.format("%g%%", math.floor(chance(prize) * 1000 + 0.5) / 10), math.floor(radius * 0.085), {
			Name = "Chance",
			Position = UDim2.new(0, 0, 0.7, 0),
			Size = UDim2.new(1, 0, 0.22, 0),
			Font = UIConfig.bodyFont,
			Parent = card,
		})
		self.cards[prize.id] = card
	end
	local hub = UI.new("Frame", {
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, radius * 0.42, 0, radius * 0.42),
		BackgroundColor3 = RIM_COLOR,
		ZIndex = 2,
		Parent = disc,
	}, { circle(), UI.stroke(GOLD, 4) })
	UI.label("💨", math.floor(radius * 0.22), { Name = "Icon", Size = UDim2.new(1, 0, 1, 0), ZIndex = 2, Parent = hub })

	-- Lights round the rim (they stay put while the disc turns).
	self.lights = {}
	for i = 1, LIGHTS do
		local angle = math.rad((i - 1) * 360 / LIGHTS + 180 / LIGHTS)
		local at = radius + RIM / 2
		table.insert(self.lights, UI.new("Frame", {
			Name = `Light{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, at * math.sin(angle), 0.5, -at * math.cos(angle)),
			Size = UDim2.new(0, 9, 0, 9),
			BackgroundColor3 = LIGHT_OFF,
			Parent = holder,
		}, { circle() }))
	end
	self:setLights(0)

	-- The pointer, over the rim at the top.
	self.pointer = UI.label("▼", math.floor(radius * 0.3), {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, RIM / 2),
		Size = UDim2.new(0, radius * 0.3, 0, radius * 0.3),
		TextColor3 = GOLD,
		ZIndex = 3,
		Parent = holder,
	})

	-- The win: a banner over the wheel's lower half.
	self.banner = UI.box("Banner", GOLD, UDim2.new(0, size * 0.86, 0, radius * 0.5), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.74, 0),
		Visible = false,
		ZIndex = 4,
		Parent = holder,
	})
	UI.new("UIScale", { Name = "Pop", Parent = self.banner })
	UI.label("YOU WON!", math.floor(radius * 0.13), {
		Name = "Title",
		Position = UDim2.new(0, 0, 0.06, 0),
		Size = UDim2.new(1, 0, 0.36, 0),
		ZIndex = 4,
		Parent = self.banner,
	})
	self.bannerText = UI.label("", math.floor(radius * 0.15), {
		Name = "Prize",
		Position = UDim2.new(0, 0, 0.42, 0),
		Size = UDim2.new(1, 0, 0.5, 0),
		TextWrapped = true,
		ZIndex = 4,
		Parent = self.banner,
	})
	return self
end

-- Every other light on, shifting with `phase` (all of them on with nil).
function SpinWheel:setLights(phase: number?)
	for i, light in self.lights do
		local on = phase == nil or (i + phase) % 2 == 0
		light.BackgroundColor3 = if on then GOLD else LIGHT_OFF
	end
end

-- The prize under the pointer at `rotation`.
function SpinWheel:under(rotation: number): number
	return math.floor(((-rotation) % 360) / self.seg) + 1
end

-- Turns the disc; a new segment under the pointer ticks.
function SpinWheel:setRotation(rotation: number)
	self.rotation = rotation
	self.disc.Rotation = rotation % 360
	local index = self:under(rotation)
	if index ~= self.lastIndex then
		self.lastIndex = index
		self.flick = 1
		-- Fast spins tick no more than this often.
		local now = os.clock()
		if now - self.lastTick >= 0.05 then
			self.lastTick = now
			Audio.play("tick")
		end
	end
end

-- The pointer kicks against each segment and settles back.
function SpinWheel:step(dt: number)
	self.flick = math.max(0, self.flick - dt * 7)
	self.pointer.Rotation = -24 * self.flick
end

-- Runs `frame(t)` for `seconds`, t from 0 to 1.
local function animate(seconds: number, frame: (number, number) -> ())
	local elapsed = 0
	while elapsed < seconds do
		local dt = task.wait()
		elapsed += dt
		frame(math.min(elapsed / seconds, 1), dt)
	end
end

function SpinWheel:reset()
	self.banner.Visible = false
	for _, card in self.cards do
		card.Pop.Scale = 1
	end
end

function SpinWheel:windUp()
	self:reset()
	local from = self.rotation
	self.rest = from
	animate(SpinWheel.WIND_UP_SECONDS, function(t, dt)
		self:setRotation(from - 14 * math.sin(t * math.pi / 2))
		self:step(dt)
	end)
end

function SpinWheel:spinTo(id: string)
	local index = self.index[id] or 1
	local calm = Settings.reduceMotion
	local seconds = if calm then SpinWheel.CALM_SECONDS else SpinWheel.SECONDS
	local turns = if calm then SpinWheel.CALM_TURNS else SpinWheel.TURNS
	-- Somewhere in the segment, not always its middle.
	local offset = (self.rng:NextNumber() - 0.5) * 0.6 * self.seg
	local target = -((index - 0.5) * self.seg + offset)
	local from = self.rotation
	local distance = turns * 360 + (target - from) % 360
	self.spinning = true
	animate(seconds, function(t, dt)
		self:setRotation(from + distance * (1 - (1 - t) ^ 3))
		self:step(dt)
		if not calm then
			self:setLights(math.floor(t * 40))
		end
	end)
	self:setRotation(from + distance)
	self.pointer.Rotation = 0
	self.spinning = false
end

-- Back to where it was before the wind-up (a refused spin).
function SpinWheel:settle()
	local from = self.rotation
	local to = self.rest or from
	animate(0.3, function(t, dt)
		self:setRotation(from + (to - from) * math.sin(t * math.pi / 2))
		self:step(dt)
	end)
end

-- A handful of confetti from the pointer.
function SpinWheel:confetti()
	local pieces = {}
	for i = 1, 28 do
		local piece = UI.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, RIM),
			Size = UDim2.new(0, self.rng:NextInteger(6, 11), 0, self.rng:NextInteger(4, 8)),
			BorderSizePixel = 0,
			BackgroundColor3 = if i % 3 == 0 then GOLD else COLORS[self.rng:NextInteger(1, #COLORS)],
			ZIndex = 5,
			Parent = self.holder,
		})
		local angle = self.rng:NextNumber(-math.pi * 0.9, -math.pi * 0.1)
		local speed = self.rng:NextNumber(180, 420)
		table.insert(pieces, {
			item = piece,
			x = 0,
			y = 0,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed,
			spin = self.rng:NextNumber(-540, 540),
		})
	end
	task.spawn(function()
		animate(1.4, function(t, dt)
			for _, piece in pieces do
				piece.vy += 700 * dt
				piece.x += piece.vx * dt
				piece.y += piece.vy * dt
				piece.item.Position = UDim2.new(0.5, piece.x, 0, RIM + piece.y)
				piece.item.Rotation += piece.spin * dt
				piece.item.BackgroundTransparency = math.max(0, t - 0.6) / 0.4
			end
		end)
		for _, piece in pieces do
			piece.item:Destroy()
		end
	end)
end

function SpinWheel:celebrate(id: string, text: string)
	local calm = Settings.reduceMotion
	self.bannerText.Text = text
	self.banner.Visible = true
	local card = self.cards[id]
	if not calm and not Settings.reducedEffects then
		self:confetti()
	end
	-- The card grows and the banner pops in (past full size, then back);
	-- the lights flash.
	animate(if calm then 0.2 else 0.9, function(t)
		self.banner.Pop.Scale = if calm then 1
			elseif t < 0.6 then 1.12 * math.sin(t / 0.6 * math.pi / 2)
			else 1.12 - 0.12 * (t - 0.6) / 0.4
		if card then
			card.Pop.Scale = 1 + 0.18 * math.min(t / 0.3, 1)
		end
		if not calm then
			self:setLights(if math.floor(t * 8) % 2 == 0 then nil else 1)
		end
	end)
	self.banner.Pop.Scale = 1
	self:setLights(nil)
end

return SpinWheel
