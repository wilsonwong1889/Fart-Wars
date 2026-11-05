-- E in a match: a tap plays the emote equipped in the Loadout; held, a wheel
-- of every emote the player owns comes up, and letting go plays the one the
-- mouse points at (in the middle, nothing). The wheel only asks: the server
-- checks the player owns what it plays (LoadoutService.emote). The mouse is
-- free while it's open (MouseLock "EmoteWheel").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local MouseLock = require(Client.MouseLock)
local UI = require(Client.UI)
local InputController = require(script.Parent.InputController)
local LockerController = require(script.Parent.LockerController)
local LoadoutController = require(script.Parent.LoadoutController)

local C = UIConfig.colors
local SPOTS = UIConfig.emoteSpots
-- How long E is held before it's the wheel and not a tap.
local HOLD_SECONDS = 0.25
local RADIUS = 150
-- Pixels from the middle of the screen that pick nothing.
local DEADZONE = 50
local SPOT = Color3.fromRGB(46, 40, 64)
local LIT = Color3.fromRGB(102, 220, 60)

local EmoteWheelController = {}

EmoteWheelController.parts = {} :: { [string]: any }
EmoteWheelController.isOpen = false
EmoteWheelController.HOLD_SECONDS = HOLD_SECONDS
-- Where the mouse is from the middle of the screen (specs move it).
EmoteWheelController.mouse = function(): Vector2
	return UserInputService:GetMouseLocation() - workspace.CurrentCamera.ViewportSize / 2
end
-- The emotes on the wheel, in spot order, and the one pointed at.
EmoteWheelController.emotes = {} :: { string }
EmoteWheelController.picked = nil :: string?

local started = false
local held = false
local presses = 0
local following: RBXScriptConnection?

local function circle(frame: GuiObject)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
end

local function build()
	local p = EmoteWheelController.parts
	local screen = UI.screen("EmoteWheel", 14)
	screen.Enabled = false
	p.screen = screen
	p.ring = UI.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 2 * RADIUS + 110, 0, 2 * RADIUS + 110),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.2,
		Parent = screen,
	}, { UI.stroke(C.stroke, 5) })
	circle(p.ring)
	local center = UI.new("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 170, 0, 170),
		BackgroundColor3 = Color3.fromRGB(12, 10, 18),
		Parent = p.ring,
	}, { UI.stroke(C.stroke, 4) })
	circle(center)
	p.name = UI.label("", 22, {
		Name = "EmoteName",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 140, 0, 90),
		TextWrapped = true,
		Parent = center,
	})
	p.spots = {}
	for i = 1, SPOTS do
		local angle = math.rad(-90 + (i - 1) * 360 / SPOTS)
		local spot = UI.new("Frame", {
			Name = `Spot{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS),
			Size = UDim2.new(0, 92, 0, 92),
			BackgroundColor3 = SPOT,
			Parent = p.ring,
		}, { UI.stroke(C.stroke, 3) })
		circle(spot)
		UI.label("", 44, { Name = "Emoji", Size = UDim2.new(1, 0, 1, 0), Parent = spot })
		p.spots[i] = spot
	end
end

-- The wheel, from what the player owns now, in the Loadout ring's order.
local function fill()
	local p = EmoteWheelController.parts
	local view = LockerController.profile or {}
	local owned = if type(view.ownedCosmetics) == "table" then view.ownedCosmetics else {}
	local emotes = {}
	for _, id in ProgressionConfig.cosmeticOrder do
		if ProgressionConfig.cosmetics[id].kind == "emote" and ProgressionConfig.ownsCosmetic(owned, id) then
			table.insert(emotes, id)
		end
	end
	EmoteWheelController.emotes = emotes
	for i, spot in p.spots do
		local cosmetic = ProgressionConfig.cosmetics[emotes[i] or ""]
		spot.Emoji.Text = if cosmetic then cosmetic.emoji else ""
		spot.BackgroundTransparency = if cosmetic then 0 else 0.6
	end
end

-- Lights the spot pointed at, and names it in the middle.
local function point(id: string?)
	local p = EmoteWheelController.parts
	EmoteWheelController.picked = id
	for i, spot in p.spots do
		local lit = id ~= nil and EmoteWheelController.emotes[i] == id
		spot.BackgroundColor3 = if lit then LIT else SPOT
		spot.Border.Color = if lit then C.text else C.stroke
		spot.Border.Thickness = if lit then 5 else 3
	end
	p.name.Text = if id then ProgressionConfig.cosmetics[id].name else "Let go here to cancel"
end

-- The emote `offset` pixels from the middle of the screen points at.
function EmoteWheelController.pick(offset: Vector2): string?
	if offset.Magnitude < DEADZONE then
		return nil
	end
	local angle = math.deg(math.atan2(offset.Y, offset.X))
	local spot = math.floor(((angle + 90) % 360) / (360 / SPOTS) + 0.5) % SPOTS + 1
	return EmoteWheelController.emotes[spot]
end

function EmoteWheelController.update()
	local id = EmoteWheelController.pick(EmoteWheelController.mouse())
	if id ~= EmoteWheelController.picked then
		point(id)
	end
end

function EmoteWheelController.open()
	if EmoteWheelController.isOpen then
		return
	end
	EmoteWheelController.isOpen = true
	fill()
	point(nil)
	EmoteWheelController.parts.screen.Enabled = true
	MouseLock.setFree("EmoteWheel", true)
	following = RunService.RenderStepped:Connect(EmoteWheelController.update)
end

function EmoteWheelController.close()
	EmoteWheelController.isOpen = false
	EmoteWheelController.picked = nil
	EmoteWheelController.parts.screen.Enabled = false
	MouseLock.setFree("EmoteWheel", false)
	if following then
		following:Disconnect()
		following = nil
	end
end

local function allowed(): boolean
	return ClientState.isActive() and not InputController.menuOpen
end

local function pressed()
	held = true
	presses += 1
	local press = presses
	task.delay(HOLD_SECONDS, function()
		if held and press == presses and allowed() and not LockerController.isOpen and not LoadoutController.isOpen then
			EmoteWheelController.open()
		end
	end)
end

local function released()
	if not held then
		return
	end
	held = false
	if EmoteWheelController.isOpen then
		local id = EmoteWheelController.picked
		EmoteWheelController.close()
		if id then
			ClientState.send("Emote", id)
		end
	elseif allowed() then
		ClientState.send("Emote")
	end
end

function EmoteWheelController.start()
	if started then
		return
	end
	started = true
	build()
	InputController.EmotePressed:Connect(pressed)
	InputController.EmoteReleased:Connect(released)
	InputController.MenuToggled:Connect(EmoteWheelController.close)
	ClientState.StateChanged:Connect(EmoteWheelController.close)
end

return EmoteWheelController
