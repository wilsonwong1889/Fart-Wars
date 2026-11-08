-- The soft shutdown's screen (SoftShutdownService): while this server is
-- closing (Workspace's SoftShutdown attribute), or while this player passes
-- through a reserved server on the way to a fresh one (their teleport data,
-- then their own SoftShutdown attribute), a full screen over everything
-- says "FART WARS JUST GOT AN UPDATE! Moving you to a fresh server...".
-- It's handed to the teleport too (TeleportService:SetTeleportGui), so the
-- screen between servers says the same. If the reserved server can't send
-- them on ("stay"), it says they're staying, then goes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoftShutdownConfig = require(Shared.Config.SoftShutdownConfig)
local UIConfig = require(Shared.Config.UIConfig)
local UI = require(script.Parent.Parent.UI)

local C = UIConfig.colors
local ATTRIBUTE = SoftShutdownConfig.ATTRIBUTE
local TEXT = SoftShutdownConfig.text

local ShutdownController = {}

-- How long teleport data alone keeps the screen up: the reserved server
-- marks a player it's sending on at once, so with no mark by then nothing
-- is coming, and the screen mustn't trap them.
ShutdownController.PASSING_TRUST_SECONDS = 10

-- Built the first time it shows: screen, title, detail.
ShutdownController.parts = nil :: { [string]: any }?
-- "update" or "closing" when this player arrived passing through (their
-- teleport data said so), otherwise nil.
ShutdownController.passing = nil :: string?

local player = Players.LocalPlayer
local started = false
local stayed = false

local function build(): { [string]: any }
	if ShutdownController.parts then
		return ShutdownController.parts
	end
	-- Above everything, the loading screen (100) included.
	local screen = UI.screen("SoftShutdown", 200)
	screen.Enabled = false
	local cover = UI.new("Frame", {
		Name = "Cover",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Active = true,
		Parent = screen,
	}, { UI.gradient(Color3.fromRGB(44, 30, 72), C.stroke) })
	UI.label("💨", 90, {
		Name = "Puff",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -60),
		Size = UDim2.new(0, 200, 0, 100),
		Parent = cover,
	})
	local title = UI.label(TEXT.update, 64, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -10),
		Size = UDim2.new(0.9, 0, 0, 80),
		TextScaled = true,
		TextColor3 = C.accent,
		Rotation = -3,
		Parent = cover,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = 64, Parent = title })
	local detail = UI.label(TEXT.moving, 30, {
		Name = "Detail",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 46),
		Size = UDim2.new(0.9, 0, 0, 40),
		Parent = cover,
	})
	ShutdownController.parts = { screen = screen, title = title, detail = detail }
	return ShutdownController.parts
end

local function show(title: string, detail: string, teleporting: boolean)
	local p = build()
	p.title.Text = title
	p.detail.Text = detail
	p.screen.Enabled = true
	if teleporting then
		-- Roblox wants it again before each teleport.
		pcall(TeleportService.SetTeleportGui, TeleportService, p.screen)
	end
end

local function hide()
	local p = ShutdownController.parts
	if p then
		p.screen.Enabled = false
	end
end

-- Shows or hides the screen from the attributes and the teleport data.
function ShutdownController.refresh()
	local closing = workspace:GetAttribute(ATTRIBUTE)
	local mine = player:GetAttribute(ATTRIBUTE)
	if closing == "update" or closing == "closing" then
		show(TEXT[closing], TEXT.moving, true)
	elseif mine == "stay" then
		-- The note shows once, then the screen goes.
		if stayed then
			hide()
		else
			stayed = true
			show(TEXT.stay, "", false)
			task.delay(SoftShutdownConfig.STAY_SECONDS, ShutdownController.refresh)
		end
	elseif mine == "moving" or ShutdownController.passing then
		show(TEXT[ShutdownController.passing or "update"] or TEXT.update, TEXT.moving, true)
	else
		hide()
	end
end

-- This player arrived passing through (`kind` from their teleport data):
-- the screen shows at once, and goes again if the server never marks them.
function ShutdownController.arrive(kind: string)
	ShutdownController.passing = kind
	task.delay(ShutdownController.PASSING_TRUST_SECONDS, function()
		if player:GetAttribute(ATTRIBUTE) == nil and ShutdownController.passing == kind then
			ShutdownController.passing = nil
			ShutdownController.refresh()
		end
	end)
	ShutdownController.refresh()
end

function ShutdownController.start()
	if started then
		return
	end
	started = true
	workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(ShutdownController.refresh)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(ShutdownController.refresh)
	local ok, data = pcall(TeleportService.GetLocalPlayerTeleportData, TeleportService)
	local kind = if ok and type(data) == "table" then data[SoftShutdownConfig.TELEPORT_KEY] else nil
	if kind == "update" or kind == "closing" then
		ShutdownController.arrive(kind)
	else
		ShutdownController.refresh()
	end
end

return ShutdownController
