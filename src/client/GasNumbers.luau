-- Floating gas numbers: "+20%" where your shot landed, popping in, rising
-- and fading (UIConfig.gasNumbers). Only from the server's verdict on your
-- own shots: CombatEvent "hit" goes to the shooter alone, and
-- CombatController hands each one here. The number is the gas the server
-- says the hit put in; a headshot's is bigger and gold. A hit that did
-- nothing (a teammate, spawn protection, someone already going off) shows
-- none. Each number is a billboard on its own attachment, from a pool of
-- at most `pool` (`reducedPool` with Reduced effects or low detail): a new
-- one takes the oldest's place. REDUCE MOTION: no pop and no rise, it's
-- shown and hidden; REDUCED EFFECTS (or low detail): the pop and rise stay,
-- no fade, and fewer at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Settings = require(script.Parent.Settings)
local UI = require(script.Parent.UI)

local NUMBERS = UIConfig.gasNumbers

local GasNumbers = {}

-- One number: its billboard (on its own attachment), the label in it, the
-- label's outline and pop, and which showing it's on.
export type Number = {
	attachment: Attachment,
	board: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	pop: UIScale,
	shownAt: number,
	token: number,
}

-- The pool, made as it's needed.
GasNumbers.numbers = {} :: { Number }

local anchor: BasePart? = nil
local tweens: { [Instance]: Tween } = {}
local shown = 0

local function stopTween(item: Instance)
	local tween = tweens[item]
	if tween then
		tween:Cancel()
		tweens[item] = nil
	end
end

local function tween(item: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	stopTween(item)
	local made = TweenService:Create(item, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	tweens[item] = made
	made:Play()
end

-- The invisible anchor the numbers' attachments hang on (made again, with
-- a fresh pool, if something removed it).
local function anchored(): BasePart
	if anchor and anchor.Parent then
		return anchor
	end
	table.clear(GasNumbers.numbers)
	local part = Instance.new("Part")
	part.Name = "GasNumbers"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new()
	part.Parent = workspace
	anchor = part
	return part
end

local function newNumber(parent: BasePart): Number
	local attachment = Instance.new("Attachment")
	attachment.Name = `GasNumber{#GasNumbers.numbers + 1}`
	attachment.Parent = parent
	local board = UI.new("BillboardGui", {
		Name = "Number",
		Adornee = attachment,
		Size = UDim2.new(0, 140, 0, 48),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = NUMBERS.maxDistance,
		Enabled = false,
		Parent = attachment,
	})
	local label = UI.label("", NUMBERS.looks.body.size, {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		Parent = board,
	})
	local entry: Number = {
		attachment = attachment,
		board = board,
		label = label,
		stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke,
		pop = UI.new("UIScale", { Name = "Pop", Parent = label }),
		shownAt = -math.huge,
		token = 0,
	}
	table.insert(GasNumbers.numbers, entry)
	return entry
end

-- The number to use: a free one, a new one while there's room, else the
-- one shown longest ago.
local function take(limit: number): Number
	local parent = anchored()
	local free, oldest = nil :: Number?, nil :: Number?
	for i = 1, math.min(limit, #GasNumbers.numbers) do
		local entry = GasNumbers.numbers[i]
		if not entry.board.Enabled and not free then
			free = entry
		end
		if not oldest or entry.shownAt < oldest.shownAt then
			oldest = entry
		end
	end
	if free then
		return free
	elseif #GasNumbers.numbers < limit then
		return newNumber(parent)
	end
	return oldest :: Number
end

-- How many numbers are on show.
function GasNumbers.showing(): number
	local count = 0
	for _, entry in GasNumbers.numbers do
		if entry.board.Enabled then
			count += 1
		end
	end
	return count
end

-- Shows the number for one of your hits (CombatEvent "hit"), unless it did
-- nothing. Returns the number shown, or nil.
function GasNumbers.show(event: { [string]: any }): Number?
	local amount = tonumber(event.amount)
	if not FeatureFlags.GAS_NUMBERS or event.blocked or not amount or amount < 0.5 or typeof(event.position) ~= "Vector3" then
		return nil
	end
	local calm = Settings.reduceMotion
	local plain = Settings.reducedEffects or Settings.lowDetail
	local look = if event.headshot then NUMBERS.looks.headshot else NUMBERS.looks.body
	local entry = take(if plain then NUMBERS.reducedPool else NUMBERS.pool)
	shown += 1
	entry.token = shown
	entry.shownAt = os.clock()
	local token = entry.token
	for _, item in { entry.board, entry.label, entry.stroke, entry.pop } do
		stopTween(item)
	end
	entry.attachment.WorldPosition = event.position
	entry.label.Text = `+{math.round(amount)}%`
	entry.label.TextColor3 = look.color
	entry.label.TextSize = look.size
	entry.label.TextTransparency = 0
	entry.stroke.Thickness = math.max(2, look.size // 12)
	entry.stroke.Transparency = 0
	-- A little to the left, the middle, then the right, so a burst of hits
	-- on one spot doesn't stack.
	local from = Vector3.new(((shown % 3) - 1) * NUMBERS.spread, NUMBERS.lift, 0)
	entry.board.StudsOffset = from
	entry.pop.Scale = if calm then 1 else NUMBERS.pop
	entry.board.Enabled = true
	if not calm then
		tween(entry.pop, NUMBERS.popSeconds, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(entry.board, NUMBERS.seconds, { StudsOffset = from + Vector3.new(0, NUMBERS.rise, 0) })
	end
	if not (calm or plain) then
		task.delay(math.max(0, NUMBERS.seconds - NUMBERS.fadeSeconds), function()
			if entry.token == token then
				tween(entry.label, NUMBERS.fadeSeconds, { TextTransparency = 1 })
				tween(entry.stroke, NUMBERS.fadeSeconds, { Transparency = 1 })
			end
		end)
	end
	task.delay(NUMBERS.seconds, function()
		if entry.token == token then
			entry.board.Enabled = false
		end
	end)
	return entry
end

return GasNumbers
