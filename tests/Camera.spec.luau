-- The mouse lock and the over-the-shoulder camera (CameraController), with
-- a stand-in for Roblox's own camera bound just before ours (it places the
-- camera behind the head and resets the mouse every frame, locking it in
-- first person as LockFirstPerson does):
--   * home screen: the mouse is free
--   * in a match: locked to the centre, every frame, with the crosshair at
--     the centre; freed by any MouseLock reason, locked again when the last
--     one clears
--   * Settings.lockMouse off: third person free, first person still locked
--   * third person sits over the right shoulder (eased in, snapped with
--     Reduce motion); first person and a free mouse have no offset
--   * a wall pulls the offset camera in; art meshes (CanQuery false) and
--     things you walk through don't
--   * locked, the avatar faces where the camera looks (yaw only), without
--     moving it or stopping a Fart Dash; free, AutoRotate is back
--   * spectating: the mouse is free and the camera left to the shots
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function near(a: Vector3, b: Vector3, tolerance: number?): boolean
	return (a - b).Magnitude < (tolerance or 1e-3)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
task.wait(0.5)
local Camera = require(client.Controllers.CameraController)
local Combat = require(client.Controllers.CombatController)
local MouseLock = require(client.MouseLock)
local Settings = require(client.Settings)
local cam = workspace.CurrentCamera
local LOCKED, FREE = Enum.MouseBehavior.LockCenter, Enum.MouseBehavior.Default

-- Roblox's camera: where it would put the camera this frame, and the mouse
-- behaviour it would leave.
local base: CFrame? = nil
RunService:BindToRenderStep("RobloxCamera", Enum.RenderPriority.Camera.Value, function()
	if base and cam.CameraType == Enum.CameraType.Custom then
		cam.CFrame = base
	end
	UserInputService.MouseBehavior = if me.CameraMode == Enum.CameraMode.LockFirstPerson then LOCKED else FREE
end)
local function frame(dt: number?)
	RunService:RenderFrame(dt or 1 / 60)
end

-- The home screen.
frame()
check(UserInputService.MouseBehavior == FREE, "home screen: the mouse is free")

-- Into a match, up in the open (nothing near), facing north.
Lifecycle.requestPlay(me, nil)
task.wait(0.5)
check(me:GetAttribute("State") == "ACTIVE" and me.Character, "on a team, with an avatar")
check(cam.CameraType == Enum.CameraType.Custom and not Camera.firstPerson, "the camera follows, third person")
local spawnLook = me.Character.HumanoidRootPart.CFrame.LookVector
check(math.abs(cam.CFrame.LookVector.Y) < 1e-3 and cam.CFrame.LookVector:Dot(spawnLook) > 0.99, "starting level, the way the avatar faces, not down at the map like the shot before")
me.Character:PivotTo(CFrame.new(0, 400, 0))
local character = me.Character
local root = character.HumanoidRootPart
local head = character.Head
local humanoid = character.Humanoid
head.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
-- Behind the head, looking a little down and to the north-east.
local function behind(look: Vector3): CFrame
	local at = head.Position - look.Unit * UIConfig.thirdPersonDistance
	return CFrame.lookAt(at, at + look)
end
local northEast = Vector3.new(1, -0.3, -1)
base = behind(northEast)

-- Locked, every frame, and the crosshair at the centre.
Settings.reduceMotion = true
frame()
check(Camera.locked() and UserInputService.MouseBehavior == LOCKED, "in a match: the mouse locked to the centre")
frame()
check(UserInputService.MouseBehavior == LOCKED, "and again the next frame, after Roblox's camera reset it")
Combat.render()
local centre = cam.ViewportSize / 2
local crosshair = Combat.parts.crosshair
check(crosshair.Visible and crosshair.Position == UDim2.new(0, centre.X, 0, centre.Y), "the crosshair at the centre of the screen")
check(not UserInputService.MouseIconEnabled, "no cursor")

-- The shoulder offset: right and up in the camera's axes.
local expected = (base :: CFrame) * CFrame.new(UIConfig.shoulderOffset)
check(near(cam.CFrame.Position, expected.Position), "third person: over the right shoulder")
check(cam.CFrame.LookVector:Dot((base :: CFrame).LookVector) > 0.9999, "looking the same way as Roblox's camera")
local rightOfHead = (cam.CFrame.Position - head.Position):Dot((base :: CFrame).RightVector)
check(rightOfHead > 2, "to the right of the head")

-- Facing where the camera looks (yaw only), without moving.
local flat = Vector3.new(northEast.X, 0, northEast.Z).Unit
check(not humanoid.AutoRotate, "locked: Roblox stops turning the avatar")
check(root.CFrame.LookVector:Dot(flat) > 0.999, "the avatar faces where the camera looks")
check(math.abs(root.CFrame.LookVector.Y) < 1e-6 and math.abs(root.CFrame.UpVector.Y - 1) < 1e-6, "upright: yaw only")
check(near(root.Position, Vector3.new(0, 400, 0)), "and stays where it is")
local west = Vector3.new(-1, 0, 0)
base = behind(west)
frame()
check(root.CFrame.LookVector:Dot(west) > 0.999, "turning the camera turns the avatar")

-- A Fart Dash: the push carries on while the avatar turns.
humanoid.FloorMaterial = Enum.Material.Grass
check(Combat.dash(), "a Fart Dash")
local push = root:FindFirstChild("FartDash")
check(push and push:IsA("LinearVelocity"), "pushing with a LinearVelocity")
base = behind(Vector3.new(0, 0, 1))
frame()
check(root:FindFirstChild("FartDash") == push and push.Enabled ~= false, "turning leaves the push alone")
check(root.CFrame.LookVector:Dot(Vector3.new(0, 0, 1)) > 0.999, "while the avatar turns")
humanoid.FloorMaterial = Enum.Material.Air
base = behind(northEast)
frame()

-- A MouseLock reason frees it; locked again once the last one clears.
MouseLock.setFree("key", true)
frame()
check(not Camera.locked() and UserInputService.MouseBehavior == FREE, "the unlock key frees the mouse")
check(humanoid.AutoRotate, "free: Roblox turns the avatar again")
check(near(cam.CFrame.Position, (base :: CFrame).Position), "free in third person: Roblox's own camera, no offset")
base = behind(west)
local facing = root.CFrame.LookVector
frame()
check(root.CFrame.LookVector:Dot(facing) > 0.9999, "the avatar no longer follows the camera")
MouseLock.setFree("menu", true)
MouseLock.setFree("key", false)
frame()
check(UserInputService.MouseBehavior == FREE, "an open screen keeps it free after the key")
MouseLock.setFree("menu", false)
frame()
check(UserInputService.MouseBehavior == LOCKED and not humanoid.AutoRotate, "the last reason gone: locked again")
check(root.CFrame.LookVector:Dot(west) > 0.999, "facing the camera again")

-- The offset eases in and out (Reduce motion off).
Settings.reduceMotion = false
MouseLock.setFree("key", true)
frame()
local partway = (cam.CFrame.Position - (base :: CFrame).Position).Magnitude
check(partway > 0.1 and partway < UIConfig.shoulderOffset.Magnitude - 0.1, "freeing eases the offset out")
for _ = 1, 60 do
	frame()
end
check(near(cam.CFrame.Position, (base :: CFrame).Position), "and it's gone")
MouseLock.setFree("key", false)
frame()
partway = (cam.CFrame.Position - (base :: CFrame).Position).Magnitude
check(partway > 0.1 and partway < UIConfig.shoulderOffset.Magnitude - 0.1, "locking eases it back in")
for _ = 1, 60 do
	frame()
end
check(near(cam.CFrame.Position, ((base :: CFrame) * CFrame.new(UIConfig.shoulderOffset)).Position), "all the way")
Settings.reduceMotion = true

-- First person: locked, no offset, and a MouseLock reason still frees it
-- although Roblox's first person locks it every frame.
Camera.toggle()
check(Camera.firstPerson and me.CameraMode == Enum.CameraMode.LockFirstPerson, "V: first person")
base = CFrame.lookAt(head.Position, head.Position + northEast)
frame()
check(UserInputService.MouseBehavior == LOCKED, "first person: locked")
check(near(cam.CFrame.Position, head.Position), "no shoulder offset")
check(root.CFrame.LookVector:Dot(flat) > 0.999 and not humanoid.AutoRotate, "facing where it looks")
MouseLock.setFree("key", true)
frame()
check(UserInputService.MouseBehavior == FREE, "the unlock key frees it in first person too")
check(humanoid.AutoRotate, "with AutoRotate back")
MouseLock.setFree("key", false)

-- Settings.lockMouse off: a free cursor in third person, first person still locked.
Settings.lockMouse = false
frame()
check(UserInputService.MouseBehavior == LOCKED and Camera.locked(), "lockMouse off: first person still locks")
Camera.toggle()
base = behind(northEast)
frame()
check(not Camera.firstPerson and UserInputService.MouseBehavior == FREE, "lockMouse off: third person is free")
check(humanoid.AutoRotate and near(cam.CFrame.Position, (base :: CFrame).Position), "with Roblox's own camera and turning")
Settings.lockMouse = true
frame()
check(UserInputService.MouseBehavior == LOCKED, "lockMouse on: third person locks again")

-- A wall behind the right shoulder pulls the camera in.
local shifted = ((base :: CFrame) * CFrame.new(UIConfig.shoulderOffset)).Position
local midway = head.Position:Lerp(shifted, 0.5)
local wall = Instance.new("Part")
wall.Name = "Wall"
wall.Anchored = true
wall.Size = Vector3.new(30, 30, 30)
-- Its near face halfway between the head and the camera.
local toward = (shifted - head.Position).Unit
wall.CFrame = CFrame.new(midway + toward * 15)
wall.Parent = workspace
frame()
local reach = (cam.CFrame.Position - head.Position).Magnitude
local full = (shifted - head.Position).Magnitude
check(reach < full / 2 and reach > 0, "a wall in the way: the camera stops short of it")
check((cam.CFrame.Position - head.Position).Unit:Dot(toward) > 0.999, "on the line from the head")
check(cam.CFrame.LookVector:Dot((base :: CFrame).LookVector) > 0.9999, "still looking the same way")
wall.CanQuery = false
frame()
check(near(cam.CFrame.Position, shifted), "an art mesh (CanQuery false) doesn't count")
wall.CanQuery = true
wall.CanCollide = false
frame()
check(near(cam.CFrame.Position, shifted), "nor does something you walk through")
wall:Destroy()
frame()
check(near(cam.CFrame.Position, shifted), "wall gone: the full offset")

-- Spectating: free, and the camera is the shots'.
Lifecycle.requestSpectate(me)
task.wait(0.3)
check(me:GetAttribute("State") ~= "ACTIVE", "spectating")
frame()
check(not Camera.locked() and UserInputService.MouseBehavior == FREE, "spectating: the mouse is free")
check(cam.CameraType == Enum.CameraType.Scriptable, "the spectator shots have the camera")
local shot = cam.CFrame
frame()
check(cam.CFrame == shot, "and it isn't moved over a shoulder")
check(me.Character == nil, "no avatar to turn")

-- Back in: locked again.
Lifecycle.requestPlay(me, nil)
task.wait(0.5)
base = nil
frame()
check(UserInputService.MouseBehavior == LOCKED, "back in a match: locked again")

return { status = "PASS", checks = checks }
