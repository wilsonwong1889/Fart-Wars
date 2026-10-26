-- PC controls: WASD and Space are Roblox's own; this adds mouse aim and
-- left click to fire, Shift for Fart Dash, Q for the equipped ability, 1-4
-- for the hotbar's weapons, V
-- for first/third person, M for the menu and Tab (held) for the
-- scoreboard. R and F stay free for later mechanics. Keys pressed while
-- typing in chat or a text box are ignored. Bindings live in
-- UIConfig.keys, ready for rebinding later.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local Signal = require(Shared.Signal)

local keys = UIConfig.keys

local InputController = {}

InputController.CameraToggled = Signal.new()
InputController.MenuToggled = Signal.new()
InputController.ScoreboardHeld = Signal.new() -- (held)
InputController.FireHeld = Signal.new() -- (held)
InputController.DashPressed = Signal.new()
InputController.AbilityPressed = Signal.new()
InputController.SlotPressed = Signal.new() -- (slot number)
InputController.EmotePressed = Signal.new()

-- Set by the menu: no firing or dashing while it's open.
InputController.menuOpen = false
InputController.fireHeld = false

local started = false

local function isDashKey(key: Enum.KeyCode): boolean
	return key == keys.dash or key == Enum.KeyCode.RightShift
end

local function setFire(held: boolean)
	if InputController.fireHeld ~= held then
		InputController.fireHeld = held
		InputController.FireHeld:Fire(held)
	end
end

-- Our Tab scoreboard replaces Roblox's player list (which also uses Tab),
-- and our hotbar replaces its backpack (which also uses 1-9).
local function hidePlayerList()
	for _ = 1, 10 do
		local listOk = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
		local backpackOk = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		if listOk and backpackOk then
			return
		end
		task.wait(0.5)
	end
end

-- Roblox's Reset Character would let a gassed player skip their own
-- explosion; the server credits such deaths anyway, and the button goes.
local function disableReset()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then
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
	task.spawn(disableReset)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == keys.fire then
			setFire(true)
			return
		end
		local key = input.KeyCode
		if key == keys.camera then
			InputController.CameraToggled:Fire()
		elseif key == keys.menu then
			InputController.MenuToggled:Fire()
		elseif key == keys.scoreboard then
			InputController.ScoreboardHeld:Fire(true)
		elseif isDashKey(key) then
			InputController.DashPressed:Fire()
		elseif key == keys.ability then
			InputController.AbilityPressed:Fire()
		elseif key == keys.emote then
			InputController.EmotePressed:Fire()
		else
			local slot = table.find(keys.slots, key)
			if slot then
				InputController.SlotPressed:Fire(slot)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == keys.fire then
			setFire(false)
		elseif input.KeyCode == keys.scoreboard then
			InputController.ScoreboardHeld:Fire(false)
		end
	end)
	-- Losing focus (alt-tab) lets go of every held input.
	UserInputService.WindowFocusReleased:Connect(function()
		setFire(false)
		InputController.ScoreboardHeld:Fire(false)
	end)
end

return InputController
