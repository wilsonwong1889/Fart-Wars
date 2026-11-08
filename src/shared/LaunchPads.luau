-- Launch pads on the map, and the arcs they throw along (FeatureFlags
-- .LAUNCH_PADS, LaunchPadConfig). Each pad is a Model in the map's
-- LaunchPads folder (MapKit.launchPad builds them) with:
--   Pad      the cushion, a flat cylinder on the ground: an avatar over it
--            is launched
--   Target   an invisible column standing on the landing spot, as tall as
--            the arc's highest point
-- Wherever on the cushion a launch starts, it lands on the Target's spot
-- and peaks at its top: a fixed arc, which the Map spec checks against the
-- walls and cover. Everything here works on an avatar's root: the arc is
-- raised by `lift`, how high the root rides above the feet.
local LaunchPads = {}

LaunchPads.FOLDER = "LaunchPads"
-- Roblox's default, for when workspace.Gravity can't be read.
LaunchPads.GRAVITY = 196.2

export type Arc = {
	from: Vector3, -- where the root starts
	velocity: Vector3, -- its velocity as it leaves
	seconds: number, -- until it's back down at the landing spot
	gravity: number,
	to: Vector3, -- where the root comes down (the landing spot, plus lift)
	apex: number, -- the root's highest point
}

function LaunchPads.gravity(): number
	local ok, gravity = pcall(function()
		return workspace.Gravity
	end)
	return if ok and type(gravity) == "number" and gravity > 0 then gravity else LaunchPads.GRAVITY
end

-- The map's pads, in name order.
function LaunchPads.list(map: Instance?): { Model }
	local folder = map and map:FindFirstChild(LaunchPads.FOLDER)
	local pads = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and child:FindFirstChild("Pad") and child:FindFirstChild("Target") then
				table.insert(pads, child)
			end
		end
	end
	table.sort(pads, function(a, b)
		return a.Name < b.Name
	end)
	return pads
end

function LaunchPads.find(map: Instance?, name: unknown): Model?
	if type(name) ~= "string" then
		return nil
	end
	local folder = map and map:FindFirstChild(LaunchPads.FOLDER)
	local pad = folder and folder:FindFirstChild(name)
	if pad and pad:IsA("Model") and pad:FindFirstChild("Pad") and pad:FindFirstChild("Target") then
		return pad
	end
	return nil
end

-- A part's half size in world space (any rotation).
local function halfExtents(part: BasePart): Vector3
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
	local s = part.Size / 2
	return Vector3.new(
		math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z,
		math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z,
		math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z
	)
end

-- The cushion's centre on its top, and its radius.
function LaunchPads.cushion(pad: Model): (Vector3, number)
	local part = pad:FindFirstChild("Pad") :: BasePart
	local half = halfExtents(part)
	return part.Position + Vector3.new(0, half.Y, 0), math.min(half.X, half.Z)
end

-- Where a launch from the pad lands (on the ground) and how high it peaks.
function LaunchPads.landing(pad: Model): (Vector3, number)
	local target = pad:FindFirstChild("Target") :: BasePart
	local half = halfExtents(target)
	return target.Position - Vector3.new(0, half.Y, 0), target.Position.Y + half.Y
end

-- The way the pad throws you, across the ground.
function LaunchPads.direction(pad: Model): Vector3
	local top = LaunchPads.cushion(pad)
	local landing = LaunchPads.landing(pad)
	local across = Vector3.new(landing.X - top.X, 0, landing.Z - top.Z)
	return if across.Magnitude > 1e-3 then across.Unit else Vector3.new(0, 0, 1)
end

-- The pad `position` (a root) is over: inside the cushion's circle, at
-- most TRIGGER_HEIGHT above its top. `pads` defaults to the map's.
function LaunchPads.under(map: Instance?, position: Vector3, triggerHeight: number, pads: { Model }?): Model?
	for _, pad in pads or LaunchPads.list(map) do
		local top, radius = LaunchPads.cushion(pad)
		local up = position.Y - top.Y
		if up >= -1 and up <= triggerHeight and Vector3.new(position.X - top.X, 0, position.Z - top.Z).Magnitude <= radius then
			return pad
		end
	end
	return nil
end

-- The arc from `from` to `to` that peaks at height `apex`, under
-- `gravity`: (the velocity to leave with, the seconds until it's down).
function LaunchPads.solve(from: Vector3, to: Vector3, apex: number, gravity: number): (Vector3, number)
	local top = math.max(apex, from.Y + 0.5, to.Y + 0.5)
	local up = math.sqrt(2 * gravity * (top - from.Y))
	local seconds = up / gravity + math.sqrt(2 * (top - to.Y) / gravity)
	return Vector3.new((to.X - from.X) / seconds, up, (to.Z - from.Z) / seconds), seconds
end

-- The launch of a root at `from` (riding `lift` above its feet) from the
-- pad: it comes down on the landing spot, peaking at the pad's height.
function LaunchPads.arc(pad: Model, from: Vector3, lift: number, gravity: number?): Arc
	local g = gravity or LaunchPads.gravity()
	local landing, apex = LaunchPads.landing(pad)
	local to = landing + Vector3.new(0, lift, 0)
	local velocity, seconds = LaunchPads.solve(from, to, apex + lift, g)
	return { from = from, velocity = velocity, seconds = seconds, gravity = g, to = to, apex = apex + lift }
end

-- Where the root is `t` seconds into the arc.
function LaunchPads.at(arc: Arc, t: number): Vector3
	local v = arc.velocity
	return arc.from + Vector3.new(v.X * t, v.Y * t - arc.gravity * t * t / 2, v.Z * t)
end

-- At most how far the root travels along the arc: across, then up and
-- back down (for the movement checks).
function LaunchPads.length(arc: Arc): number
	local across = Vector3.new(arc.to.X - arc.from.X, 0, arc.to.Z - arc.from.Z).Magnitude
	return across + (arc.apex - arc.from.Y) + (arc.apex - arc.to.Y)
end

-- Throws an avatar along `arc`: the kick (its velocity as it leaves) and
-- a push holding its speed across the ground, so nothing steers it off
-- the arc; gravity does the rest. On whichever machine simulates the
-- avatar (its player's client; the server for a bot). A Fart Dash push
-- still on it goes first. Returns the push, for LaunchPads.land.
function LaunchPads.throw(humanoid: Humanoid, root: BasePart, arc: Arc): LinearVelocity
	for _, name in { "FartDash", "LaunchPad" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local attachment = root:FindFirstChild("LaunchPadAttachment")
	if not (attachment and attachment:IsA("Attachment")) then
		attachment = Instance.new("Attachment")
		attachment.Name = "LaunchPadAttachment"
		attachment.Parent = root
	end
	local push = Instance.new("LinearVelocity")
	push.Name = "LaunchPad"
	push.Attachment0 = attachment :: Attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.PlaneVelocity = Vector2.new(arc.velocity.X, arc.velocity.Z)
	push.MaxForce = math.huge
	push.Parent = root
	pcall(humanoid.ChangeState, humanoid, Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = arc.velocity
	return push
end

-- Ends a flight: the push goes, and the avatar runs on across the ground
-- at no more than `speed`.
function LaunchPads.land(root: BasePart, push: LinearVelocity?, speed: number)
	if push then
		push:Destroy()
	end
	local attachment = root:FindFirstChild("LaunchPadAttachment")
	if attachment then
		attachment:Destroy()
	end
	local v = root.AssemblyLinearVelocity
	local across = Vector3.new(v.X, 0, v.Z)
	if across.Magnitude > speed then
		root.AssemblyLinearVelocity = across.Unit * speed + Vector3.new(0, v.Y, 0)
	end
end

-- How high a standing avatar's root rides above its feet.
function LaunchPads.lift(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return root.Size.Y / 2 + 2
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

-- Whether a root at `position` could have been launched from the pad up
-- to `lag` seconds ago: still over or beside the cushion (within
-- `slack`), or that close to where the arc has taken it since.
function LaunchPads.reaches(pad: Model, position: Vector3, triggerHeight: number, slack: number, lag: number): boolean
	local top, radius = LaunchPads.cushion(pad)
	local up = position.Y - top.Y
	if up >= -1 - slack and up <= triggerHeight + slack and Vector3.new(position.X - top.X, 0, position.Z - top.Z).Magnitude <= radius + slack then
		return true
	end
	local arc = LaunchPads.arc(pad, top + Vector3.new(0, 3, 0), 3)
	for i = 0, 20 do
		local t = math.min(lag, arc.seconds) * i / 20
		if (LaunchPads.at(arc, t) - position).Magnitude <= radius + slack then
			return true
		end
	end
	return false
end

return LaunchPads
