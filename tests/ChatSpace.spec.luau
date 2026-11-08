-- Roblox's chat and the menus keep out of each other's way (ChatSpace),
-- at 1366x768 and 1920x1080, with a stand-in for the chat (TextChatService
-- reports where its window and input bar are; it lays itself out from its
-- alignment, its scales and the screen, a moment after they change).
-- Roblox doesn't publish the chat's size, so two are tried: a share of the
-- screen (as the old chat was) and a fixed 400 x 250.
--   * the home screen: the chat stays top left, and the page buttons
--     (LOADOUT first) move down below it, still clear of the level panel;
--     on a screen too short for both, the chat shrinks (never under half)
--   * the loadout: the chat moves to the bottom right, which the stage
--     keeps empty, and shrinks to fit there if it must; it never covers
--     the weapons, the home screen redrawing under it doesn't take it
--     back, and closing the loadout puts it back top left
--   * in a match the chat is where the place had it, full size
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

-- The stand-in chat, before anything starts.
local window = Instance.new("ChatWindowConfiguration")
window.HorizontalAlignment = Enum.HorizontalAlignment.Left
window.VerticalAlignment = Enum.VerticalAlignment.Top
window.WidthScale = 1
window.HeightScale = 1
window.Enabled = true
window.Parent = TextChatService
local bar = Instance.new("ChatInputBarConfiguration")
bar.Enabled = true
bar.Parent = TextChatService

local SCREEN = Vector2.new(1366, 768)
local TOP_BAR = 58 -- Roblox's top bar; the chat sits under it
local BAR_HEIGHT, GAP, EDGE = 44, 4, 8
local model = "share"
-- The chat's message list at scale 1 for the screen.
local function baseSize(): Vector2
	if model == "share" then
		return Vector2.new(math.floor(SCREEN.X * 0.3), math.floor(SCREEN.Y * 0.25 + 46))
	end
	return Vector2.new(400, 250)
end
local function layOut()
	local base = baseSize()
	local width = base.X * window.WidthScale
	local list = base.Y * window.HeightScale
	local tall = list + GAP + BAR_HEIGHT
	local x = if window.HorizontalAlignment == Enum.HorizontalAlignment.Right then SCREEN.X - EDGE - width else EDGE
	local y = if window.VerticalAlignment == Enum.VerticalAlignment.Bottom then SCREEN.Y - EDGE - tall else TOP_BAR + GAP
	window.AbsolutePosition = Vector2.new(x, y)
	window.AbsoluteSize = Vector2.new(width, list)
	bar.AbsolutePosition = Vector2.new(x, y + list + GAP)
	bar.AbsoluteSize = Vector2.new(width, BAR_HEIGHT)
end
for _, property in { "HorizontalAlignment", "VerticalAlignment", "WidthScale", "HeightScale" } do
	window:GetPropertyChangedSignal(property):Connect(function()
		task.defer(layOut)
	end)
end
layOut()

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
require(server.Services.BotDirector).testSetEnabled(false)
local Data = require(server.Services.DataService)
local saved: { [string]: any } = {}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		local result = transform(saved[key])
		if result ~= nil then
			saved[key] = result
		end
		return result
	end,
})
local me = Instance.new("Player")
me.Name = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
task.wait(0.5)
local ChatSpace = require(client.ChatSpace)
local Home = require(client.Controllers.HomeController)
local Loadout = require(client.Controllers.LoadoutController)
local home = Home.parts
local loadout = Loadout.parts

local function chat(): (Vector2, Vector2)
	local lo, hi = ChatSpace.bounds()
	return assert(lo), assert(hi)
end
local function overlaps(aLo: Vector2, aHi: Vector2, bLo: Vector2, bHi: Vector2): boolean
	return aLo.X < bHi.X and bLo.X < aHi.X and aLo.Y < bHi.Y and bLo.Y < aHi.Y
end
-- A frame's place in its parent, from its Position, Size and AnchorPoint
-- (the stand-ins don't lay anything out).
local function placeIn(frame: GuiObject, parent: Vector2): (Vector2, Vector2)
	local size = Vector2.new(frame.Size.X.Scale * parent.X + frame.Size.X.Offset, frame.Size.Y.Scale * parent.Y + frame.Size.Y.Offset)
	local at = Vector2.new(frame.Position.X.Scale * parent.X + frame.Position.X.Offset, frame.Position.Y.Scale * parent.Y + frame.Position.Y.Offset)
	at -= frame.AnchorPoint * size
	return at, at + size
end
-- The page column and the level panel on the home screen (in pixels).
local function pagesRect(): (Vector2, Vector2)
	local lo, hi = placeIn(home.pages, SCREEN)
	local scale = home.pages:FindFirstChild("HudScale")
	local s = if scale then scale.Scale else 1
	local middle = (lo + hi) / 2
	local half = (hi - lo) * s / 2
	return middle - half, middle + half
end
local function levelTop(): number
	local lo = placeIn(home.levelBox, SCREEN)
	return lo.Y
end

local function resize(size: Vector2)
	SCREEN = size
	home.home.AbsoluteSize = size
	loadout.screen.AbsoluteSize = size
	layOut()
	task.wait(0.1)
end

for _, which in { "share", "fixed" } do
	model = which
	for _, size in { Vector2.new(1366, 768), Vector2.new(1920, 1080) } do
		local label = `{size.X}x{size.Y}, {which} chat`
		resize(size)
		task.wait(1)
		-- The home screen.
		check(home.home.Enabled and ChatSpace.holds("HomeScreen"), `{label}: the home screen holds the top left`)
		check(window.HorizontalAlignment == Enum.HorizontalAlignment.Left and window.VerticalAlignment == Enum.VerticalAlignment.Top, `{label}: the chat stays top left`)
		local lo, hi = chat()
		local pagesLo, pagesHi = pagesRect()
		check(not overlaps(lo, hi, pagesLo, pagesHi), `{label}: the chat doesn't cover LOADOUT or the other page buttons`)
		check(pagesLo.Y >= hi.Y + ChatSpace.MARGIN - 0.5, `{label}: the buttons start below the chat`)
		check(pagesHi.Y <= levelTop() - ChatSpace.MARGIN + 0.5, `{label}: and end above the level panel`)
		check(window.HeightScale >= ChatSpace.MIN_SCALE and window.WidthScale == 1, `{label}: the chat is its full width`)

		-- The loadout.
		Loadout.open()
		task.wait(1)
		check(window.HorizontalAlignment == Enum.HorizontalAlignment.Right and window.VerticalAlignment == Enum.VerticalAlignment.Bottom, `{label}: with the loadout open, the chat goes bottom right`)
		lo, hi = chat()
		local scale = math.min(size.X / 1280, size.Y / 720)
		local stageOrigin = (size - Vector2.new(1280, 720) * scale) / 2
		local spotLo = stageOrigin + Vector2.new(900, 500) * scale
		check(lo.X >= spotLo.X + ChatSpace.MARGIN - 0.5 and lo.Y >= spotLo.Y + ChatSpace.MARGIN - 0.5 and hi.X <= size.X and hi.Y <= size.Y, `{label}: inside the corner the stage keeps for it`)
		check(window.WidthScale >= ChatSpace.MIN_SCALE and window.HeightScale >= ChatSpace.MIN_SCALE, `{label}: never under half size`)
		local weaponsLo, weaponsHi = placeIn(loadout.stage.Weapons, Vector2.new(1280, 720))
		weaponsLo, weaponsHi = stageOrigin + weaponsLo * scale, stageOrigin + weaponsHi * scale
		check(not overlaps(lo, hi, weaponsLo, weaponsHi), `{label}: the chat doesn't cover the weapons`)
		-- The home screen under it redraws often (the round's updates): the
		-- chat stays where the loadout put it.
		Home.render()
		task.wait(0.6)
		check(window.HorizontalAlignment == Enum.HorizontalAlignment.Right, `{label}: the home screen redrawing doesn't take the chat back`)
		Loadout.close()
		task.wait(1)
		check(window.HorizontalAlignment == Enum.HorizontalAlignment.Left and window.VerticalAlignment == Enum.VerticalAlignment.Top, `{label}: closing the loadout puts the chat back top left`)
		lo, hi = chat()
		pagesLo, pagesHi = pagesRect()
		check(not overlaps(lo, hi, pagesLo, pagesHi), `{label}: still clear of the buttons`)
	end
end

-- Nothing on the loadout's stage is in the chat's corner.
local spotLo, spotHi = placeIn(loadout.chatSpot, Vector2.new(1280, 720))
for _, child in loadout.stage:GetChildren() do
	if child:IsA("GuiObject") and child ~= loadout.chatSpot and child.Name ~= "Picker" then
		local lo, hi = placeIn(child, Vector2.new(1280, 720))
		check(not overlaps(lo, hi, spotLo, spotHi), `the loadout's {child.Name} stays out of the chat's corner`)
	end
end

-- A screen too short for both: the chat shrinks so the buttons fit.
model = "share"
resize(Vector2.new(1280, 560))
task.wait(1)
local lo, hi = chat()
local pagesLo, pagesHi = pagesRect()
check(window.HeightScale < 1 and window.HeightScale >= ChatSpace.MIN_SCALE, "a short screen: the chat is shorter")
check(not overlaps(lo, hi, pagesLo, pagesHi) and pagesHi.Y <= levelTop() - ChatSpace.MARGIN + 0.5, "and the buttons fit under it")

-- In a match: where the place had it, full size.
resize(Vector2.new(1366, 768))
ChatSpace.claim("HomeScreen", nil)
task.wait(1)
check(window.HorizontalAlignment == Enum.HorizontalAlignment.Left and window.HeightScale == 1 and window.WidthScale == 1, "with no screen asking, the chat is back as it was")

return { status = "PASS", checks = checks }
