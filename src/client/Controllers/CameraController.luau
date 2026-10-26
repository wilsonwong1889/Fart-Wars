-- The camera. In a match it follows the avatar in third person, and V
-- switches to first person and back. Off a team (home screen, AFK) it
-- shows the live battlefield from the map's fixed CameraPoints, never from
-- a player's eyes, so a spectator learns nothing an active player couldn't.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local MapBase = require(Shared.Interfaces.MapBase)
local ClientState = require(script.Parent.Parent.ClientState)
local InputController = require(script.Parent.InputController)

local CameraController = {}

CameraController.firstPerson = false

local player = Players.LocalPlayer
local defaultMinZoom = 0.5
local spectating = false
local shotToken = 0
local shotTween: Tween? = nil
local started = false

local function camera(): Camera
	return workspace.CurrentCamera
end

-- Applies first or third person to the player's camera settings.
local function applyView()
	if CameraController.firstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		return
	end
	player.CameraMode = Enum.CameraMode.Classic
	-- Raising the minimum pushes the camera back out to the third-person
	-- distance; dropping it again a frame later leaves it there but lets
	-- the player zoom in.
	player.CameraMinZoomDistance = math.max(defaultMinZoom, UIConfig.thirdPersonDistance)
	task.defer(function()
		if not CameraController.firstPerson then
			player.CameraMinZoomDistance = defaultMinZoom
		end
	end)
end

local function followAvatar()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local cam = camera()
	cam.CameraType = Enum.CameraType.Custom
	if humanoid then
		cam.CameraSubject = humanoid
	end
	applyView()
end

-- Cycles through the map's fixed views with a slow push-in on each.
local function runShots(token: number)
	local index = 0
	while spectating and shotToken == token do
		local map = workspace:FindFirstChild("Map")
		local points = if map then MapBase.cameraPoints(map) else {}
		if #points == 0 then
			task.wait(0.5)
			continue
		end
		index = index % #points + 1
		local from = points[index].CFrame
		local cam = camera()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = from
		local tween = TweenService:Create(
			cam,
			TweenInfo.new(UIConfig.spectatorShotSeconds, Enum.EasingStyle.Linear),
			{ CFrame = from * CFrame.new(0, 0, -10) }
		)
		shotTween = tween
		tween:Play()
		task.wait(UIConfig.spectatorShotSeconds)
	end
end

local function spectate()
	if spectating then
		return
	end
	spectating = true
	shotToken += 1
	player.CameraMode = Enum.CameraMode.Classic
	task.spawn(runShots, shotToken)
end

local function refresh()
	if ClientState.isActive() then
		spectating = false
		shotToken += 1
		if shotTween then
			shotTween:Cancel()
			shotTween = nil
		end
		followAvatar()
	else
		spectate()
	end
end
CameraController.refresh = refresh

function CameraController.toggle()
	if not ClientState.isActive() then
		return
	end
	CameraController.firstPerson = not CameraController.firstPerson
	applyView()
end

function CameraController.start()
	if started then
		return
	end
	started = true
	defaultMinZoom = player.CameraMinZoomDistance
	InputController.CameraToggled:Connect(CameraController.toggle)
	ClientState.StateChanged:Connect(refresh)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		if ClientState.isActive() then
			followAvatar()
		end
	end)
	refresh()
end

return CameraController
