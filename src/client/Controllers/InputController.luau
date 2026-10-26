-- PC controls: WASD and Space are Roblox's own; this adds Shift to sprint,
-- V for first/third person, M for the menu and Tab (held) for the
-- scoreboard. Q, R and F stay free for later mechanics. Keys pressed while
-- typing in chat or a text box are ignored.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Signal = require(Shared.Signal)
local ClientState = require(script.Parent.Parent.ClientState)

local keys = UIConfig.keys

local InputController = {}

InputController.CameraToggled = Signal.new()
InputController.MenuToggled = Signal.new()
InputController.ScoreboardHeld = Signal.new() -- (held)

-- Set by the menu: no sprinting while it's open.
InputController.menuOpen = false

local sprintHeld = false
local started = false

local function applySpeed()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local sprinting = sprintHeld and not InputController.menuOpen and ClientState.isActive()
		humanoid.WalkSpeed = if sprinting then GameConfig.SPRINT_SPEED else GameConfig.WALK_SPEED
	end
end
InputController.applySpeed = applySpeed

local function isSprintKey(key: Enum.KeyCode): boolean
	return key == keys.sprint or key == Enum.KeyCode.RightShift
end

-- Our Tab scoreboard replaces Roblox's player list (which also uses Tab).
local function hidePlayerList()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false) then
			return
		end
		task.wait(0.5)
	end
end

function InputController.start()
	if started then
		return
	end
	started = true
	task.spawn(hidePlayerList)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == keys.camera then
			InputController.CameraToggled:Fire()
		elseif key == keys.menu then
			InputController.MenuToggled:Fire()
		elseif key == keys.scoreboard then
			InputController.ScoreboardHeld:Fire(true)
		elseif isSprintKey(key) then
			sprintHeld = true
			applySpeed()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		if key == keys.scoreboard then
			InputController.ScoreboardHeld:Fire(false)
		elseif isSprintKey(key) then
			sprintHeld = false
			applySpeed()
		end
	end)
	-- Losing focus (alt-tab) lets go of every held key.
	UserInputService.WindowFocusReleased:Connect(function()
		sprintHeld = false
		applySpeed()
		InputController.ScoreboardHeld:Fire(false)
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		applySpeed()
	end)
	ClientState.StateChanged:Connect(applySpeed)
end

return InputController
