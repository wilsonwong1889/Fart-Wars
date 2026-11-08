-- The practice yard on the client (FeatureFlags.PRACTICE; PracticeService
-- runs it on the server and says how it's going in the Player's
-- PracticeStep, PracticeCount and PracticeEnded attributes):
--   * a profile's first PLAY asks for the yard instead of opening the team
--     screen (offer; once a session, and only while the server says it's
--     due), and PRACTICE on the home screen and in Settings ask for it any
--     time (replay). If the yard doesn't open (the server says no, or
--     nothing comes), a first PLAY goes on to the team screen without it
--   * in the yard, a banner across the top (over the match clock, which
--     the yard isn't part of) says what to do: the step's big prompt, its
--     progress, a hint when it's taking a while, a cheer when it's done.
--     SKIP works all the way through: the button (with a free mouse, Alt)
--     or Enter
--   * when the yard finishes or is skipped, Finished fires and the home
--     screen opens the team screen; spectating from the menu just goes home
-- The rest of the yard plays like a match (ClientState.isActive): the
-- crosshair, the gun, the dash and the camera.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local PracticeConfig = require(Shared.Config.PracticeConfig)
local UIConfig = require(Shared.Config.UIConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local Audio = require(Client.Audio)

local C = UIConfig.colors
local STEPS = PracticeConfig.STEPS
-- How a yard ended that goes on to the team screen (set before the player
-- leaves PRACTICE; spectating doesn't).
local ON_TO_TEAMS = { finished = true, skipped = true, failed = true }

local PracticeController = {}

PracticeController.parts = {} :: { [string]: any }
-- The yard is over (finished or skipped): time to choose a team.
PracticeController.Finished = Signal.new()

local player = Players.LocalPlayer
local started = false
-- The first PLAY's offer is made once a session.
local offered = false
-- When the yard was asked for and hasn't opened yet (os.clock()), and
-- whether the team screen follows if it doesn't.
local pendingSince: number? = nil
local pendingFallback = false
-- A yard is under way (PRACTICE was seen), and whether its end has been
-- passed on.
local inRun = false
local finishedFired = false
-- When the current step began, for its hint.
local stepSince = 0

function PracticeController.available(): boolean
	return FeatureFlags.PRACTICE
end

-- Whether the server says the next PLAY goes to the yard.
function PracticeController.due(): boolean
	return FeatureFlags.PRACTICE and player:GetAttribute("PracticeDue") == true
end

-- Asks the server for the yard. With `fallback`, the team screen follows
-- if it doesn't open in time.
local function open(fallback: boolean): boolean
	local asked = os.clock()
	pendingSince = asked
	pendingFallback = fallback
	ClientState.send("Practice", "start")
	task.delay(PracticeConfig.OPEN_TIMEOUT_SECONDS, function()
		if pendingSince == asked then
			pendingSince = nil
			if fallback and not ClientState.isActive() then
				PracticeController.Finished:Fire()
			end
		end
	end)
	return true
end

-- PLAY on the home screen: the yard first, if it's due (once a session).
-- Returns whether the yard is on its way (so the team screen waits).
function PracticeController.offer(): boolean
	if pendingSince then
		return true
	end
	if offered or ClientState.isActive() or not PracticeController.due() then
		return false
	end
	offered = true
	return open(true)
end

-- PRACTICE (the home screen's tile, Settings): the yard again, from the
-- home screen.
function PracticeController.replay(): boolean
	if not FeatureFlags.PRACTICE or ClientState.isActive() or pendingSince then
		return false
	end
	return open(false)
end

-- SKIP: out of the yard and on to the team screen.
function PracticeController.skip()
	if ClientState.inPractice() then
		ClientState.send("Practice", "skip")
	end
end

local function build()
	local p = PracticeController.parts
	local screen = UI.screen("Practice", 7)
	screen.Enabled = false
	p.screen = screen
	local banner = UI.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.new(0, 700, 0, 176),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.06,
		Active = true,
		Parent = screen,
	}, { UI.corner(18), UI.stroke(C.stroke, 4) })
	p.banner = banner
	p.step = UI.label("PRACTICE YARD", 16, {
		Name = "Step",
		Position = UDim2.new(0, 18, 0, 12),
		Size = UDim2.new(0, 300, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.muted,
		Parent = banner,
	})
	p.title = UI.label("", 40, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48),
		Size = UDim2.new(1, -28, 0, 46),
		TextScaled = true,
		TextColor3 = C.accent,
		Parent = banner,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = 40, Parent = p.title })
	p.text = UI.label("", 20, {
		Name = "Text",
		Position = UDim2.new(0, 14, 0, 96),
		Size = UDim2.new(1, -28, 0, 26),
		TextWrapped = true,
		Parent = banner,
	})
	p.progress = UI.label("", 24, {
		Name = "Progress",
		Position = UDim2.new(0, 14, 0, 122),
		Size = UDim2.new(1, -28, 0, 28),
		TextColor3 = UIConfig.gold,
		Parent = banner,
	})
	p.hint = UI.label("", 15, {
		Name = "Hint",
		Position = UDim2.new(0, 14, 0, 150),
		Size = UDim2.new(1, -28, 0, 20),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		Visible = false,
		Parent = banner,
	})
	local skip = UI.chunky(`SKIP ({PracticeConfig.SKIP_KEY_NAME})`, C.panelLight, "⏭️", {
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.new(0, 180, 0, 38),
		TextSize = 17,
		Parent = banner,
	})
	p.skip = skip
	UI.onClick(skip, PracticeController.skip)
end

-- The banner, from the server's attributes.
function PracticeController.render()
	local p = PracticeController.parts
	local practicing = ClientState.inPractice()
	p.screen.Enabled = practicing
	if not practicing then
		return
	end
	local id = player:GetAttribute("PracticeStep")
	local count = tonumber(player:GetAttribute("PracticeCount")) or 0
	local step, index = PracticeConfig.step(id)
	if step then
		local cleared = count >= step.goal
		p.step.Text = `STEP {index} OF {#STEPS}`
		p.title.Text = if cleared then step.cheer else step.title
		p.text.Text = step.text
		p.progress.Visible = step.progress ~= nil
		p.progress.Text = if step.progress then string.format(step.progress, count, step.goal) else ""
		p.hint.Text = step.hint
		p.hint.Visible = not cleared and os.clock() - stepSince >= PracticeConfig.HINT_SECONDS
		return
	end
	local words = if id == "done" then PracticeConfig.DONE else PracticeConfig.INTRO
	p.step.Text = "PRACTICE YARD"
	p.title.Text = words.title
	p.text.Text = words.text
	p.progress.Visible = false
	p.hint.Visible = false
end

-- The yard is over: on to the team screen if it finished or was skipped.
-- (The server sets how it ended before the state changes; this works with
-- the two arriving either way round.)
local function checkFinished()
	if not inRun or finishedFired then
		return
	end
	local state = ClientState.state()
	if state == States.Player.PRACTICE then
		return
	end
	local ended = player:GetAttribute("PracticeEnded")
	if state == States.Player.ACTIVE or ended == "left" or ended == "played" then
		-- Straight into a match, or home by choice: nothing to follow.
		inRun = false
	elseif ON_TO_TEAMS[ended :: any] then
		inRun = false
		finishedFired = true
		PracticeController.Finished:Fire()
	end
end

local function onState(state: string)
	if state == States.Player.PRACTICE then
		pendingSince = nil
		inRun = true
		finishedFired = false
	else
		checkFinished()
	end
	PracticeController.render()
end

function PracticeController.start()
	if started then
		return
	end
	started = true
	build()
	ClientState.StateChanged:Connect(onState)
	player:GetAttributeChangedSignal("PracticeStep"):Connect(function()
		local p = PracticeController.parts
		stepSince = os.clock()
		PracticeController.render()
		UI.pop(p.title, 1.15)
		if player:GetAttribute("PracticeStep") == "done" and ClientState.inPractice() then
			Audio.play("levelUp")
		end
	end)
	player:GetAttributeChangedSignal("PracticeCount"):Connect(function()
		local p = PracticeController.parts
		PracticeController.render()
		local step = PracticeConfig.step(player:GetAttribute("PracticeStep"))
		local count = tonumber(player:GetAttribute("PracticeCount")) or 0
		if step and count >= step.goal and ClientState.inPractice() then
			UI.pop(p.title, 1.25)
			Audio.play("coins")
		elseif count > 0 then
			UI.pop(p.progress, 1.2)
		end
	end)
	player:GetAttributeChangedSignal("PracticeEnded"):Connect(checkFinished)
	-- A start the server refused: no waiting for it.
	local remote = ClientState.remote("Practice") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind)
		if kind == "refused" and pendingSince then
			pendingSince = nil
			if pendingFallback and not ClientState.isActive() then
				PracticeController.Finished:Fire()
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == PracticeConfig.SKIP_KEY and ClientState.inPractice() then
			PracticeController.skip()
		end
	end)
	-- The hint's clock.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if ClientState.inPractice() then
				PracticeController.render()
			end
		end
	end)
	onState(ClientState.state())
end

return PracticeController
