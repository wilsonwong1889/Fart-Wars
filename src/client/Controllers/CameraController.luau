-- The camera. In a match it follows the avatar in third person, and V
-- switches to first person and back. Off a team (home screen, AFK) it
-- shows the live battlefield from the map's fixed CameraPoints, never from
-- a player's eyes, so a spectator learns nothing an active player couldn't.
--
-- In a match the mouse is locked to the centre crosshair in both views
-- (like Arsenal or Rivals), unless something wants it free (MouseLock: the
-- unlock key, an open screen) or the player turned Settings.lockMouse off
-- for third person. While it's locked the avatar faces where the camera
-- looks, and third person sits over the right shoulder. All of this is
-- applied every frame just after Roblox's own camera update, which resets
-- the mouse behaviour each frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local MapBase = require(Shared.Interfaces.MapBase)
local ClientState = require(script.Parent.Parent.ClientState)
local Settings = require(script.Parent.Parent.Settings)
local MouseLock = require(script.Parent.Parent.MouseLock)
local InputController = require(script.Parent.InputController)

-- How quickly the shoulder offset eases in and out (per second), and how
-- far short of a wall the camera stops when one is in the way (studs).
local SHOULDER_EASE = 12
local WALL_GAP = 0.5

local CameraController = {}

CameraController.firstPerson = false

local player = Players.LocalPlayer
local defaultMinZoom = 0.5
local spectating = false
local shotToken = 0
local shotTween: Tween? = nil
local started = false
-- How much of the shoulder offset is on (0 to 1), and the humanoid whose
-- turning we took over (to hand back when the mouse is freed).
local shoulderAmount = 0
local turned: Humanoid? = nil

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
		-- Reduce motion: a still shot.
		if Settings.reduceMotion then
			task.wait(UIConfig.spectatorShotSeconds)
			continue
		end
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

-- Whether the mouse is locked to the crosshair right now: in a match,
-- nothing wants it free, and first person (always) or Settings.lockMouse.
function CameraController.locked(): boolean
	return ClientState.isActive()
		and not spectating
		and not MouseLock.isFree()
		and (CameraController.firstPerson or Settings.lockMouse)
end

-- While locked the avatar turns with the camera (yaw only), the way shift
-- lock does; otherwise Roblox turns it toward where it walks. Only the
-- rotation changes, so the Fart Dash's push carries on.
local function face(locked: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local want = locked
		and humanoid ~= nil
		and humanoid.Health > 0
		and not humanoid.Sit
		and not humanoid.PlatformStand
		and root ~= nil
		and root:IsA("BasePart")
	if turned and (turned ~= humanoid or not want) then
		if turned.Parent then
			turned.AutoRotate = true
		end
		turned = nil
	end
	if not want then
		return
	end
	local h = humanoid :: Humanoid
	local part = root :: BasePart
	if h.AutoRotate then
		h.AutoRotate = false
	end
	turned = h
	local look = camera().CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	-- Already facing that way: leave the physics be.
	if part.CFrame.LookVector:Dot(flat) > 0.99999 then
		return
	end
	local position = part.Position
	part.CFrame = CFrame.lookAt(position, position + flat)
end

-- Over the shoulder: moves the camera Roblox just placed right and up (in
-- the camera's own axes), then pulls it back toward the head if anything
-- solid is in the way. Our own avatar and anything CanQuery false (the
-- map's art meshes; the plain parts under them are the real walls) don't
-- count, and neither do things you can walk through.
local function shoulder(cam: Camera, amount: number)
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not (head and head:IsA("BasePart")) then
		return
	end
	local shifted = cam.CFrame * CFrame.new(UIConfig.shoulderOffset * amount)
	local from = head.Position
	local offset = shifted.Position - from
	if offset.Magnitude > 0.01 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character :: Model }
		params.RespectCanCollide = true
		local hit = workspace:Raycast(from, offset, params)
		if hit then
			local keep = math.max(0, (hit.Position - from).Magnitude - WALL_GAP)
			shifted = shifted.Rotation + (from + offset.Unit * keep)
		end
	end
	cam.CFrame = shifted
end

-- Every frame, after Roblox's camera: the mouse, which way the avatar
-- faces, and the shoulder offset.
function CameraController.step(dt: number)
	local locked = CameraController.locked()
	local behavior = if locked then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	if UserInputService.MouseBehavior ~= behavior then
		UserInputService.MouseBehavior = behavior
	end
	face(locked)

	-- The offset eases in and out between a locked and a free mouse in
	-- third person (snaps with Reduce motion); first person and spectating
	-- never have it.
	local thirdPerson = ClientState.isActive() and not spectating and not CameraController.firstPerson
	local target = if locked and thirdPerson then 1 else 0
	if not thirdPerson or Settings.reduceMotion then
		shoulderAmount = target
	else
		shoulderAmount += (target - shoulderAmount) * (1 - math.exp(-SHOULDER_EASE * dt))
		if math.abs(target - shoulderAmount) < 0.001 then
			shoulderAmount = target
		end
	end
	local cam = camera()
	if shoulderAmount > 0 and cam.CameraType == Enum.CameraType.Custom then
		shoulder(cam, shoulderAmount)
	end
end

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
	RunService:BindToRenderStep("FartWarsCamera", Enum.RenderPriority.Camera.Value + 1, CameraController.step)
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
