-- Keeps Roblox's chat and the menus out of each other's way. The chat
-- (TextChatService: its message window with the input bar under it, top
-- left by default) reports where it is on screen (the AbsolutePosition and
-- AbsoluteSize of ChatWindowConfiguration and ChatInputBarConfiguration);
-- its size isn't known before then and follows the screen's. Three ways
-- to share the screen:
--   * a layout keeps clear of bounds(), redoing itself on Changed (the
--     home screen's buttons go below the chat)
--   * a screen with no room where the chat is claims a corner for it
--     (claim): the chat moves there (its alignment) and, if it must, shrinks
--     to fit the room given (WidthScale and HeightScale, never under
--     MIN_SCALE), until the claim is let go. The newest claim wins; with
--     none the chat is back where the place had it.
--   * a screen whose window the chat would take the clicks of says so in
--     its claim (avoid): while the chat, where it would be, covers any of
--     the window, it's hidden (Enabled off, the window and the input bar),
--     and it shows again, as it was, once it wouldn't or the claim is let
--     go (the locker's window on a laptop's screen).
-- The chat is hidden for nothing else. Bounds are in the same pixels as
-- any GuiObject's AbsolutePosition, so they compare with a screen's own.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local ChatSpace = {}

-- Fires when the chat may have moved or changed size.
ChatSpace.Changed = Signal.new()
-- The least the chat is shrunk to (Roblox's own floor for WidthScale).
ChatSpace.MIN_SCALE = 0.5
-- Pixels kept between the chat and anything beside it (its frame has a
-- bevel the reported size leaves out).
ChatSpace.MARGIN = 12

export type Claim = {
	horizontal: Enum.HorizontalAlignment,
	vertical: Enum.VerticalAlignment,
	-- The room the chat must fit in (top left, bottom right), or nil for
	-- as much as it likes.
	room: (() -> (Vector2, Vector2))?,
	-- The window the chat mustn't cover (top left, bottom right, or nil
	-- while it isn't on screen): the chat is hidden while it would.
	avoid: (() -> (Vector2?, Vector2?))?,
}

local claims: { { name: string, claim: Claim } } = {}
local defaults: { horizontal: any, vertical: any, width: number, height: number }? = nil
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local announced = false
local last = ""
-- The parts of the chat an avoid has hidden, each with whether it was
-- showing before, and where the chat was when it went.
local hidden: { [any]: boolean } = {}
local hiddenLo: Vector2?, hiddenHi: Vector2? = nil, nil

local function hiding(): boolean
	return next(hidden) ~= nil
end

local function window(): any
	return TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
end

local function inputBar(): any
	return TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
end

-- Where a part of the chat is, or (`wouldBe`) would be if an avoid
-- hadn't hidden it.
local function rectOf(config: any, wouldBe: boolean?): (Vector2?, Vector2?)
	if not config then
		return nil, nil
	end
	local showing = if wouldBe and hidden[config] ~= nil then hidden[config] else config.Enabled ~= false
	if not showing then
		return nil, nil
	end
	local at, size = config.AbsolutePosition, config.AbsoluteSize
	if typeof(at) ~= "Vector2" or typeof(size) ~= "Vector2" or size.X <= 0 or size.Y <= 0 then
		return nil, nil
	end
	return at, at + size
end

-- The window and the input bar together.
local function span(wouldBe: boolean?): (Vector2?, Vector2?)
	local lo, hi = rectOf(window(), wouldBe)
	if not lo then
		return nil, nil
	end
	local barLo, barHi = rectOf(inputBar(), wouldBe)
	if barLo and barHi then
		lo, hi = (lo :: Vector2):Min(barLo), (hi :: Vector2):Max(barHi)
	end
	return lo, hi
end

-- Where the chat is: its top left and bottom right corners (the window and
-- the input bar together), or nil when no chat window is showing a size.
function ChatSpace.bounds(): (Vector2?, Vector2?)
	return span()
end

-- Whether the chat, where it would be with no avoid (where it says it is,
-- hidden or not, else where it was when it went), covers any of lo..hi.
local function covers(lo: Vector2?, hi: Vector2?): boolean
	local chatLo, chatHi = span(true)
	if not (chatLo and chatHi) then
		chatLo, chatHi = hiddenLo, hiddenHi
	end
	if not (lo and hi and chatLo and chatHi) then
		return false
	end
	return chatLo.X < hi.X and lo.X < chatHi.X and chatLo.Y < hi.Y and lo.Y < chatHi.Y
end

-- The claim in force, if any.
local function current(): Claim?
	local top = claims[#claims]
	return top and top.claim
end

local function remember(config: any)
	if not defaults then
		defaults = {
			horizontal = config.HorizontalAlignment or Enum.HorizontalAlignment.Left,
			vertical = config.VerticalAlignment or Enum.VerticalAlignment.Top,
			width = tonumber(config.WidthScale) or 1,
			height = tonumber(config.HeightScale) or 1,
		}
	end
end

-- (Protected: if Roblox ever stops a client setting one, the chat just
-- stays where it is.)
local function write(config: any, key: string, value: any)
	pcall(function()
		config[key] = value
	end)
end

local function set(config: any, key: string, value: any)
	if config[key] ~= value then
		write(config, key, value)
	end
end

-- Hides the chat, window and input bar (yes), or shows them as they were.
local function hide(yes: boolean)
	if not yes then
		for config, was in hidden do
			write(config, "Enabled", was)
		end
		table.clear(hidden)
		hiddenLo, hiddenHi = nil, nil
		return
	end
	if not hiding() then
		hiddenLo, hiddenHi = ChatSpace.bounds()
	end
	for _, config in { window(), inputBar() } do
		if hidden[config] == nil then
			hidden[config] = config.Enabled ~= false
			write(config, "Enabled", false)
		end
	end
end

local function setScale(config: any, key: string, value: number)
	local now = tonumber(config[key]) or 1
	if math.abs(now - value) > 0.01 then
		write(config, key, value)
	end
end

-- The scale that makes `size` (pixels, at `scale`) fit `room` pixels, of
-- which `fixed` don't scale; between MIN_SCALE and `most`.
local function fitScale(scale: number, size: number, fixed: number, room: number, most: number): number
	if size - fixed <= 0 then
		return scale
	end
	return math.clamp(scale * (room - fixed) / (size - fixed), ChatSpace.MIN_SCALE, most)
end

-- Puts the chat where the claim in force says (or back), and fits it.
local function apply()
	local config = window()
	if not config then
		return
	end
	remember(config)
	local base = defaults :: any
	local claim = current()
	if not claim then
		hide(false)
		set(config, "HorizontalAlignment", base.horizontal)
		set(config, "VerticalAlignment", base.vertical)
		setScale(config, "WidthScale", base.width)
		setScale(config, "HeightScale", base.height)
		return
	end
	set(config, "HorizontalAlignment", claim.horizontal)
	set(config, "VerticalAlignment", claim.vertical)
	hide(claim.avoid ~= nil and covers(claim.avoid()))
	local lo, hi = ChatSpace.bounds()
	if not (claim.room and lo and hi) then
		return
	end
	local roomLo, roomHi = claim.room()
	local margin = ChatSpace.MARGIN
	local right = claim.horizontal == Enum.HorizontalAlignment.Right
	local bottom = claim.vertical == Enum.VerticalAlignment.Bottom
	-- Not there yet (it moves a moment after its alignment changes): fit
	-- it once it is.
	if (if right then hi.X < roomLo.X else lo.X > roomHi.X) or (if bottom then hi.Y < roomLo.Y else lo.Y > roomHi.Y) then
		return
	end
	-- How much room there is from the chat's fixed corner (it grows away
	-- from the corner it's aligned to).
	local width = if right then hi.X - (roomLo.X + margin) else (roomHi.X - margin) - lo.X
	local height = if bottom then hi.Y - (roomLo.Y + margin) else (roomHi.Y - margin) - lo.Y
	-- Only the message list grows and shrinks; the input bar stays.
	local listLo, listHi = rectOf(config)
	local listHeight = if listLo and listHi then listHi.Y - listLo.Y else hi.Y - lo.Y
	local fixed = (hi.Y - lo.Y) - listHeight
	setScale(config, "WidthScale", fitScale(tonumber(config.WidthScale) or 1, hi.X - lo.X, 0, width, base.width))
	setScale(config, "HeightScale", fitScale(tonumber(config.HeightScale) or 1, hi.Y - lo.Y, fixed, height, base.height))
end

local applying, again = false, false
local function changed()
	-- (Hidden, it counts where it would be: an avoid looks again if that
	-- changes.)
	local lo, hi = span(true)
	local key = if lo and hi then `{hiding()}:{lo.X},{lo.Y},{hi.X},{hi.Y}` else ""
	if key == last then
		return
	end
	last = key
	-- A change the fitting itself causes mid-fit is fitted after it (a few
	-- rounds at most: a fit settles in one).
	if applying then
		again = true
	else
		applying = true
		for _ = 1, 4 do
			again = false
			apply()
			if not again then
				break
			end
		end
		applying = false
	end
	if not announced then
		announced = true
		task.defer(function()
			announced = false
			ChatSpace.Changed:Fire()
		end)
	end
end

-- The chat reports its position and size one property at a time: take
-- them together, once they're all in.
local pending = false
local function soon()
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		changed()
	end)
end

local function hook(config: Instance?)
	if not config or hooked[config] then
		return
	end
	hooked[config] = true
	for _, property in { "AbsolutePosition", "AbsoluteSize", "Enabled" } do
		local ok, signal = pcall(config.GetPropertyChangedSignal, config, property)
		if ok and signal then
			signal:Connect(soon)
		end
	end
end

-- Asks for the chat to sit as `claim` says while `name` needs it (nil:
-- stops asking). Asking again keeps a claim's place: only a new one goes
-- on top.
function ChatSpace.claim(name: string, claim: Claim?)
	for i, entry in claims do
		if entry.name == name then
			if claim then
				entry.claim = claim
			else
				table.remove(claims, i)
			end
			apply()
			return
		end
	end
	if claim then
		table.insert(claims, { name = name, claim = claim })
	end
	apply()
end

-- Whether `name` holds a claim.
function ChatSpace.holds(name: string): boolean
	for _, entry in claims do
		if entry.name == name then
			return true
		end
	end
	return false
end

-- Fits the chat again (a claim's room changed: the screen was resized).
function ChatSpace.refit()
	apply()
end

local started = false
function ChatSpace.start()
	if started then
		return
	end
	started = true
	hook(window())
	hook(inputBar())
	TextChatService.ChildAdded:Connect(function(child)
		if child:IsA("ChatWindowConfiguration") or child:IsA("ChatInputBarConfiguration") then
			hook(child)
			soon()
		end
	end)
	-- The chat reports its place a moment after it's built, and not every
	-- change may come as an event: look twice a second as well.
	task.spawn(function()
		while true do
			changed()
			task.wait(0.5)
		end
	end)
end

-- Specs only: no claims, nothing remembered (the chat showing).
function ChatSpace.reset()
	hide(false)
	table.clear(claims)
	defaults = nil
	last = ""
end

return ChatSpace
