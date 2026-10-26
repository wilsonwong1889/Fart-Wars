--!nocheck
-- Roblox stand-ins for running tests/*.spec.luau on the Luau CLI, without
-- Studio. scripts/run_specs.py puts a BUNDLE table in front of this file
-- (the spec's source, and every script under src/ at the path Rojo gives it)
-- and runs the result with `luau`.
--
-- The spec runs as Studio's command bar would run it in Edit mode, in a
-- fresh stand-in world: a DataModel with services; instances with
-- properties, attributes, tags, children and signals; Vector3, Vector2,
-- CFrame, Color3, UDim2 and the other datatypes; Enum; and a task scheduler
-- on a virtual clock, so task.wait(10) takes no real time. Unknown properties
-- read as nil instead of throwing, raycasts hit nothing, and box queries
-- compare bounding boxes, so Studio stays the final word.
--
-- Prints "PASS <spec>: <what the spec returned>" or "FAIL <spec>: <error>",
-- then anything the spec printed and any errors in background threads
-- (any of which fails the spec).
--
-- Fart Wars additions: BrickColor (named palette entries); PlayerAdded and
-- PlayerRemoving fire as Players gains and loses a Player; LoadCharacterAsync
-- builds a small rig at the RespawnLocation; Team:GetPlayers; and remotes
-- loop back within the one world (see RemoteEvent below).

local START_UNIX = 1_800_000_000 -- os.time() when the virtual clock starts
local MAX_VIRTUAL_SECONDS = 3600

local realTypeof = typeof
local realOs = os
local log = {}

----------------------------------------------------------------------------
-- Virtual clock and task scheduler

local clock = 0
local queue = {}
local sequence = 0
local backgroundErrors = {}
local cancelled = setmetatable({}, { __mode = "k" })

local function resume(thread, ...)
	if cancelled[thread] or coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(backgroundErrors, debug.traceback(thread, tostring(err)))
	end
end

local function enqueue(at, thread, ...)
	sequence += 1
	table.insert(queue, { at = at, sequence = sequence, thread = thread, args = table.pack(...) })
end

local function popNext()
	local best, index
	for i, item in queue do
		if not best or item.at < best.at or (item.at == best.at and item.sequence < best.sequence) then
			best, index = item, i
		end
	end
	if index then
		table.remove(queue, index)
	end
	return best
end

local function toThread(f)
	return if type(f) == "thread" then f else coroutine.create(f)
end

local task = {}
function task.spawn(f, ...)
	local thread = toThread(f)
	resume(thread, ...)
	return thread
end
function task.defer(f, ...)
	local thread = toThread(f)
	enqueue(clock, thread, ...)
	return thread
end
function task.delay(seconds, f, ...)
	local thread = toThread(f)
	enqueue(clock + math.max(tonumber(seconds) or 0, 0), thread, ...)
	return thread
end
function task.wait(seconds)
	local started = clock
	enqueue(clock + math.max(tonumber(seconds) or 0, 1 / 60), coroutine.running())
	coroutine.yield()
	return clock - started
end
function task.cancel(thread)
	cancelled[thread] = true
end
function task.synchronize() end
function task.desynchronize() end

local os = setmetatable({
	clock = function()
		return clock
	end,
	time = function(date)
		return if date then realOs.time(date) else START_UNIX + math.floor(clock)
	end,
}, { __index = realOs })

----------------------------------------------------------------------------
-- Signals

local Connection = {}
Connection.__index = Connection
function Connection:Disconnect()
	self.Connected = false
	-- As in Roblox, a disconnected handler is let go (so leak checks work).
	self.fn = nil
end
Connection.disconnect = Connection.Disconnect

local Signal = { __type = "RBXScriptSignal" }
Signal.__index = Signal
local function newSignal()
	return setmetatable({ connections = {} }, Signal)
end
function Signal:Connect(fn)
	local connection = setmetatable({ Connected = true, fn = fn }, Connection)
	table.insert(self.connections, connection)
	return connection
end
Signal.connect = Signal.Connect
Signal.ConnectParallel = Signal.Connect
function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end
function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		resume(thread, ...)
	end)
	return coroutine.yield()
end
Signal.wait = Signal.Wait
function Signal:Fire(...)
	local live = {}
	for _, connection in self.connections do
		if connection.Connected then
			table.insert(live, connection)
		end
	end
	self.connections = live
	for _, connection in table.clone(live) do
		if connection.Connected then
			task.spawn(connection.fn, ...)
		end
	end
end
function Signal:DisconnectAll()
	for _, connection in self.connections do
		connection.Connected = false
		connection.fn = nil
	end
	self.connections = {}
end

----------------------------------------------------------------------------
-- Enum

local enumTypes = {}
local function enumType(typeName)
	local existing = enumTypes[typeName]
	if existing then
		return existing
	end
	local items, order = {}, {}
	local methods = {
		GetEnumItems = function()
			return table.clone(order)
		end,
		FromName = function(_, name)
			return items[name]
		end,
		FromValue = function(_, value)
			for _, item in order do
				if item.Value == value then
					return item
				end
			end
			return nil
		end,
	}
	local itemMeta = {
		__type = "EnumItem",
		__tostring = function(item)
			return `Enum.{typeName}.{item.Name}`
		end,
		__index = {
			IsA = function(item, name)
				return name == typeName
			end,
		},
	}
	local proxy = setmetatable({}, {
		__type = "Enum",
		__tostring = function()
			return typeName
		end,
		__index = function(_, name)
			if methods[name] then
				return methods[name]
			end
			local item = items[name]
			if not item then
				item = table.freeze(setmetatable({ Name = name, Value = #order, EnumType = typeName }, itemMeta))
				items[name] = item
				table.insert(order, item)
			end
			return item
		end,
	})
	enumTypes[typeName] = proxy
	return proxy
end
local Enum = setmetatable({}, {
	__type = "Enums",
	__index = function(_, typeName)
		return enumType(typeName)
	end,
})
-- Values that code compares or iterates in order.
for _, name in { "Right", "Top", "Back", "Left", "Bottom", "Front" } do
	local _ = Enum.NormalId[name]
end

----------------------------------------------------------------------------
-- Datatypes

local function frozen(meta, fields)
	return table.freeze(setmetatable(fields, meta))
end

local Vector3, Vector2, CFrame, Color3, UDim, UDim2 = {}, {}, {}, {}, {}, {}
local V3 = { __type = "Vector3" }
local V2 = { __type = "Vector2" }
local CF = { __type = "CFrame" }
local C3 = { __type = "Color3" }
local UD = { __type = "UDim" }
local UD2 = { __type = "UDim2" }

-- Roblox vectors are values: two with the same components are the same table
-- key (the town keys its cells by Vector3). Equal vectors share one table.
local vectorCache = setmetatable({}, { __mode = "v" })
local function v3(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	if x == 0 then x = 0 end -- -0 and 0 are the same vector
	if y == 0 then y = 0 end
	if z == 0 then z = 0 end
	local key = string.pack("<ddd", x, y, z)
	local cached = vectorCache[key]
	if not cached then
		cached = frozen(V3, { X = x, Y = y, Z = z })
		vectorCache[key] = cached
	end
	return cached
end
local function isV3(value)
	return getmetatable(value) == V3
end

local v3Methods = {
	Dot = function(a, b)
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z
	end,
	Cross = function(a, b)
		return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
	end,
	Lerp = function(a, b, t)
		return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
	end,
	Min = function(a, b)
		return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	end,
	Max = function(a, b)
		return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	end,
	Abs = function(a)
		return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
	end,
	Floor = function(a)
		return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
	end,
	Ceil = function(a)
		return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
	end,
	Sign = function(a)
		return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
	end,
	FuzzyEq = function(a, b, epsilon)
		epsilon = epsilon or 1e-5
		return math.abs(a.X - b.X) <= epsilon and math.abs(a.Y - b.Y) <= epsilon and math.abs(a.Z - b.Z) <= epsilon
	end,
	Angle = function(a, b)
		local m = a.Magnitude * b.Magnitude
		return if m == 0 then 0 else math.acos(math.clamp(a:Dot(b) / m, -1, 1))
	end,
}
V3.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif key == "x" or key == "y" or key == "z" then
		return rawget(v, string.upper(key))
	end
	return v3Methods[key]
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(a) == "number" then
		return v3(a / b.X, a / b.Y, a / b.Z)
	elseif type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__idiv = function(a, b)
	local q = V3.__div(a, b)
	return v3(math.floor(q.X), math.floor(q.Y), math.floor(q.Z))
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return `{v.X}, {v.Y}, {v.Z}`
end
function Vector3.new(x, y, z)
	return v3(x, y, z)
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
local NORMALS = {
	Right = v3(1, 0, 0),
	Left = v3(-1, 0, 0),
	Top = v3(0, 1, 0),
	Bottom = v3(0, -1, 0),
	Back = v3(0, 0, 1),
	Front = v3(0, 0, -1),
}
function Vector3.FromNormalId(normal)
	return NORMALS[normal.Name]
end
function Vector3.FromAxis(axis)
	return ({ X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis })[axis.Name]
end

local vector2Cache = setmetatable({}, { __mode = "v" })
local function v2(x, y)
	x, y = x or 0, y or 0
	if x == 0 then x = 0 end
	if y == 0 then y = 0 end
	local key = string.pack("<dd", x, y)
	local cached = vector2Cache[key]
	if not cached then
		cached = frozen(V2, { X = x, Y = y })
		vector2Cache[key] = cached
	end
	return cached
end
local v2Methods = {
	Dot = function(a, b)
		return a.X * b.X + a.Y * b.Y
	end,
	Cross = function(a, b)
		return a.X * b.Y - a.Y * b.X
	end,
	Lerp = function(a, b, t)
		return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
	end,
	Min = function(a, b)
		return v2(math.min(a.X, b.X), math.min(a.Y, b.Y))
	end,
	Max = function(a, b)
		return v2(math.max(a.X, b.X), math.max(a.Y, b.Y))
	end,
	Abs = function(a)
		return v2(math.abs(a.X), math.abs(a.Y))
	end,
	Floor = function(a)
		return v2(math.floor(a.X), math.floor(a.Y))
	end,
	Ceil = function(a)
		return v2(math.ceil(a.X), math.ceil(a.Y))
	end,
	FuzzyEq = function(a, b, epsilon)
		epsilon = epsilon or 1e-5
		return math.abs(a.X - b.X) <= epsilon and math.abs(a.Y - b.Y) <= epsilon
	end,
}
V2.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return v2(v.X / m, v.Y / m)
	end
	return v2Methods[key]
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(v)
	return `{v.X}, {v.Y}`
end
function Vector2.new(x, y)
	return v2(x, y)
end
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)
Vector2.xAxis = v2(1, 0)
Vector2.yAxis = v2(0, 1)

-- CFrame: position plus a rotation matrix, stored as 12 numbers.
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return frozen(CF, { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 })
end
local function isCF(value)
	return getmetatable(value) == CF
end
local IDENTITY = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
local function cfMul(a, b)
	local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 = table.unpack(a)
	local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = table.unpack(b)
	return cf(
		a00 * bx + a01 * by + a02 * bz + ax,
		a10 * bx + a11 * by + a12 * bz + ay,
		a20 * bx + a21 * by + a22 * bz + az,
		a00 * b00 + a01 * b10 + a02 * b20,
		a00 * b01 + a01 * b11 + a02 * b21,
		a00 * b02 + a01 * b12 + a02 * b22,
		a10 * b00 + a11 * b10 + a12 * b20,
		a10 * b01 + a11 * b11 + a12 * b21,
		a10 * b02 + a11 * b12 + a12 * b22,
		a20 * b00 + a21 * b10 + a22 * b20,
		a20 * b01 + a21 * b11 + a22 * b21,
		a20 * b02 + a21 * b12 + a22 * b22
	)
end
local function cfInverse(c)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = table.unpack(c)
	return cf(
		-(r00 * x + r10 * y + r20 * z),
		-(r01 * x + r11 * y + r21 * z),
		-(r02 * x + r12 * y + r22 * z),
		r00, r10, r20, r01, r11, r21, r02, r12, r22
	)
end
local function cfPoint(c, v)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = table.unpack(c)
	return v3(r00 * v.X + r01 * v.Y + r02 * v.Z + x, r10 * v.X + r11 * v.Y + r12 * v.Z + y, r20 * v.X + r21 * v.Y + r22 * v.Z + z)
end
local function cfVector(c, v)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = table.unpack(c)
	return v3(r00 * v.X + r01 * v.Y + r02 * v.Z, r10 * v.X + r11 * v.Y + r12 * v.Z, r20 * v.X + r21 * v.Y + r22 * v.Z)
end
local function rotation(r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return cf(0, 0, 0, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return rotation(1, 0, 0, 0, c, -s, 0, s, c)
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return rotation(c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return rotation(c, -s, 0, s, c, 0, 0, 0, 1)
end
local function fromQuaternion(x, y, z, qx, qy, qz, qw)
	local m = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	qx, qy, qz, qw = qx / m, qy / m, qz / m, qw / m
	return cf(
		x, y, z,
		1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)
	)
end
local function toQuaternion(c)
	local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = table.unpack(c)
	local trace = m00 + m11 + m22
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		return (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		return 0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		return (m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s
	end
	local s = math.sqrt(1 + m22 - m00 - m11) * 2
	return (m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s
end
local function lookAt(eye, target, up)
	up = up or Vector3.yAxis
	local look = (target - eye)
	if look.Magnitude == 0 then
		return cf(eye.X, eye.Y, eye.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.zAxis)
	end
	right = right.Unit
	local upward = right:Cross(look)
	return cf(eye.X, eye.Y, eye.Z, right.X, upward.X, -look.X, right.Y, upward.Y, -look.Y, right.Z, upward.Z, -look.Z)
end
local cfMethods = {
	Inverse = cfInverse,
	ToWorldSpace = function(a, b)
		return cfMul(a, b)
	end,
	ToObjectSpace = function(a, b)
		return cfMul(cfInverse(a), b)
	end,
	PointToWorldSpace = cfPoint,
	PointToObjectSpace = function(c, v)
		return cfPoint(cfInverse(c), v)
	end,
	VectorToWorldSpace = cfVector,
	VectorToObjectSpace = function(c, v)
		return cfVector(cfInverse(c), v)
	end,
	GetComponents = function(c)
		return table.unpack(c)
	end,
	ToEulerAnglesXYZ = function(c)
		local _, _, _, r00, r01, r02, _, _, r12, _, _, r22 = table.unpack(c)
		return math.atan2(-r12, r22), math.asin(math.clamp(r02, -1, 1)), math.atan2(-r01, r00)
	end,
	ToEulerAnglesYXZ = function(c)
		local _, _, _, _, _, r02, r10, r11, r12, _, _, r22 = table.unpack(c)
		return math.asin(math.clamp(-r12, -1, 1)), math.atan2(r02, r22), math.atan2(r10, r11)
	end,
	ToAxisAngle = function(c)
		local qx, qy, qz, qw = toQuaternion(c)
		local angle = 2 * math.acos(math.clamp(qw, -1, 1))
		local s = math.sqrt(1 - qw * qw)
		if s < 1e-6 then
			return Vector3.xAxis, 0
		end
		return v3(qx / s, qy / s, qz / s), angle
	end,
	Lerp = function(a, b, t)
		local ax, ay, az, aw = toQuaternion(a)
		local bx, by, bz, bw = toQuaternion(b)
		local dot = ax * bx + ay * by + az * bz + aw * bw
		if dot < 0 then
			bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot
		end
		local wa, wb
		if dot > 0.9995 then
			wa, wb = 1 - t, t
		else
			local theta = math.acos(dot)
			wa, wb = math.sin((1 - t) * theta) / math.sin(theta), math.sin(t * theta) / math.sin(theta)
		end
		return fromQuaternion(
			a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
			ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb
		)
	end,
	Orthonormalize = function(c)
		return c
	end,
	FuzzyEq = function(a, b, epsilon)
		epsilon = epsilon or 1e-5
		for i = 1, 12 do
			if math.abs(a[i] - b[i]) > epsilon then
				return false
			end
		end
		return true
	end,
}
cfMethods.components = cfMethods.GetComponents
cfMethods.ToOrientation = cfMethods.ToEulerAnglesYXZ
CF.__index = function(c, key)
	if key == "Position" or key == "p" then
		return v3(c[1], c[2], c[3])
	elseif key == "X" or key == "x" then
		return c[1]
	elseif key == "Y" or key == "y" then
		return c[2]
	elseif key == "Z" or key == "z" then
		return c[3]
	elseif key == "LookVector" or key == "lookVector" then
		return v3(-c[6], -c[9], -c[12])
	elseif key == "RightVector" or key == "XVector" then
		return v3(c[4], c[7], c[10])
	elseif key == "UpVector" or key == "YVector" then
		return v3(c[5], c[8], c[11])
	elseif key == "ZVector" then
		return v3(c[6], c[9], c[12])
	elseif key == "Rotation" then
		return cf(0, 0, 0, table.unpack(c, 4, 12))
	end
	return cfMethods[key]
end
CF.__mul = function(a, b)
	if isV3(b) then
		return cfPoint(a, b)
	end
	return cfMul(a, b)
end
CF.__add = function(a, b)
	return cf(a[1] + b.X, a[2] + b.Y, a[3] + b.Z, table.unpack(a, 4, 12))
end
CF.__sub = function(a, b)
	return cf(a[1] - b.X, a[2] - b.Y, a[3] - b.Z, table.unpack(a, 4, 12))
end
CF.__eq = function(a, b)
	for i = 1, 12 do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end
CF.__tostring = function(c)
	return table.concat(c, ", ")
end
function CFrame.new(...)
	local n = select("#", ...)
	local a, b = ...
	if n == 0 then
		return IDENTITY
	elseif n == 1 then
		return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 2 then
		return lookAt(a, b)
	elseif n == 3 then
		local x, y, z = ...
		return cf(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 7 then
		return fromQuaternion(...)
	end
	return cf(...)
end
CFrame.identity = IDENTITY
CFrame.lookAt = lookAt
function CFrame.Angles(x, y, z)
	return cfMul(cfMul(rx(x), ry(y)), rz(z))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(x, y, z)
	return cfMul(cfMul(ry(y), rx(x)), rz(z))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(x, y, z, order)
	return CFrame.Angles(x, y, z)
end
function CFrame.fromAxisAngle(axis, angle)
	local unit = axis.Unit
	local s = math.sin(angle / 2)
	return fromQuaternion(0, 0, 0, unit.X * s, unit.Y * s, unit.Z * s, math.cos(angle / 2))
end
function CFrame.fromMatrix(position, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(position.X, position.Y, position.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end

local function c3(r, g, b)
	return frozen(C3, { R = r or 0, G = g or 0, B = b or 0 })
end
local function toHSV(c)
	local r, g, b = c.R, c.G, c.B
	local maxc, minc = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, maxc
	local d = maxc - minc
	if maxc > 0 then
		s = d / maxc
	end
	if d > 0 then
		if maxc == r then
			h = (g - b) / d % 6
		elseif maxc == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, s, v
end
local c3Methods = {
	Lerp = function(a, b, t)
		return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
	end,
	ToHSV = toHSV,
	ToHex = function(c)
		return string.format("%02X%02X%02X", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
	end,
}
C3.__index = function(c, key)
	if key == "r" or key == "g" or key == "b" then
		return rawget(c, string.upper(key))
	end
	return c3Methods[key]
end
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(c)
	return `{c.R}, {c.G}, {c.B}`
end
function Color3.new(r, g, b)
	return c3(r, g, b)
end
function Color3.fromRGB(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local k = i % 6
	if k == 0 then
		return c3(v, t, p)
	elseif k == 1 then
		return c3(q, v, p)
	elseif k == 2 then
		return c3(p, v, t)
	elseif k == 3 then
		return c3(p, q, v)
	elseif k == 4 then
		return c3(t, p, v)
	end
	return c3(v, p, q)
end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
end
Color3.toHSV = toHSV

-- BrickColor: the palette entries the game names, one shared value per name.
local BRICK_COLORS = {
	["Lime green"] = { 0, 255, 0 }, ["New Yeller"] = { 255, 255, 0 }, ["Medium stone grey"] = { 163, 162, 165 },
	["White"] = { 242, 243, 243 }, ["Really black"] = { 17, 17, 17 },
}
local BC = { __type = "BrickColor" }
BC.__index = BC
BC.__tostring = function(b)
	return b.Name
end
local brickColors = {}
local BrickColor = {}
function BrickColor.new(name)
	if type(name) ~= "string" then
		error("the stand-in BrickColor.new only takes a palette name")
	end
	local rgb = BRICK_COLORS[name] or error(`no stand-in for BrickColor "{name}"`)
	brickColors[name] = brickColors[name] or frozen(BC, { Name = name, Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]) })
	return brickColors[name]
end
function BrickColor.White()
	return BrickColor.new("White")
end

local function udim(scale, offset)
	return frozen(UD, { Scale = scale or 0, Offset = offset or 0 })
end
UD.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UD.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UD.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__tostring = function(u)
	return `{u.Scale}, {u.Offset}`
end
UD.__index = {}
function UDim.new(scale, offset)
	return udim(scale, offset)
end
local function udim2(x, y)
	return frozen(UD2, { X = x, Y = y })
end
UD2.__index = function(u, key)
	if key == "Width" then
		return u.X
	elseif key == "Height" then
		return u.Y
	elseif key == "Lerp" then
		return function(a, b, t)
			return udim2(udim(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t), udim(a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t))
		end
	end
	return nil
end
UD2.__add = function(a, b)
	return udim2(a.X + b.X, a.Y + b.Y)
end
UD2.__sub = function(a, b)
	return udim2(a.X - b.X, a.Y - b.Y)
end
UD2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UD2.__tostring = function(u)
	return `\{{u.X}}, \{{u.Y}}`
end
function UDim2.new(xs, xo, ys, yo)
	if getmetatable(xs) == UD then
		return udim2(xs, xo)
	end
	return udim2(udim(xs, xo), udim(ys, yo))
end
function UDim2.fromScale(x, y)
	return udim2(udim(x, 0), udim(y, 0))
end
function UDim2.fromOffset(x, y)
	return udim2(udim(0, x), udim(0, y))
end

local function record(typeName, fields)
	return table.freeze(setmetatable(fields, { __type = typeName }))
end
local NumberRange = {
	new = function(min, max)
		return record("NumberRange", { Min = min, Max = max or min })
	end,
}
local NumberSequenceKeypoint = {
	new = function(time, value, envelope)
		return record("NumberSequenceKeypoint", { Time = time, Value = value, Envelope = envelope or 0 })
	end,
}
local NumberSequence = {
	new = function(a, b)
		if type(a) == "table" then
			return record("NumberSequence", { Keypoints = a })
		end
		return record("NumberSequence", { Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } })
	end,
}
local ColorSequenceKeypoint = {
	new = function(time, value)
		return record("ColorSequenceKeypoint", { Time = time, Value = value })
	end,
}
local ColorSequence = {
	new = function(a, b)
		if type(a) == "table" and getmetatable(a) ~= C3 then
			return record("ColorSequence", { Keypoints = a })
		end
		return record("ColorSequence", { Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } })
	end,
}
local TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		return record("TweenInfo", {
			Time = time or 1,
			EasingStyle = style or Enum.EasingStyle.Quad,
			EasingDirection = direction or Enum.EasingDirection.Out,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delayTime or 0,
		})
	end,
}
local function params(typeName)
	return {
		new = function()
			return setmetatable({
				FilterType = Enum.RaycastFilterType.Exclude,
				FilterDescendantsInstances = {},
				CollisionGroup = "Default",
				IgnoreWater = false,
				RespectCanCollide = false,
				MaxParts = 0,
				BruteForceAllSlow = false,
				AddToFilter = function(self, item)
					table.insert(self.FilterDescendantsInstances, item)
				end,
			}, { __type = typeName })
		end,
	}
end
local RaycastParams = params("RaycastParams")
local OverlapParams = params("OverlapParams")
local Faces = {
	new = function(...)
		local faces = {}
		for _, normal in { ... } do
			faces[normal.Name] = true
		end
		return record("Faces", faces)
	end,
}
local PhysicalProperties = {
	new = function(density, friction, elasticity, frictionWeight, elasticityWeight)
		return record("PhysicalProperties", { Density = density, Friction = friction, Elasticity = elasticity, FrictionWeight = frictionWeight, ElasticityWeight = elasticityWeight })
	end,
}

-- Random, as a small linear congruential generator per object.
local RandomMeta = { __type = "Random" }
RandomMeta.__index = RandomMeta
local function newRandom(seed)
	return setmetatable({ state = math.floor(math.abs(tonumber(seed) or 12345)) % 2147483647 + 1 }, RandomMeta)
end
function RandomMeta:next()
	self.state = (self.state * 48271) % 2147483647
	return (self.state - 1) / 2147483646
end
function RandomMeta:NextNumber(min, max)
	min, max = min or 0, max or 1
	return min + (max - min) * self:next()
end
function RandomMeta:NextInteger(min, max)
	return math.min(max, min + math.floor((max - min + 1) * self:next()))
end
function RandomMeta:NextUnitVector()
	local theta, z = self:NextNumber(0, 2 * math.pi), self:NextNumber(-1, 1)
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(theta), r * math.sin(theta), z)
end
function RandomMeta:Shuffle(list)
	for i = #list, 2, -1 do
		local j = self:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end
function RandomMeta:Clone()
	return setmetatable({ state = self.state }, RandomMeta)
end
local Random = { new = newRandom }

----------------------------------------------------------------------------
-- JSON (HttpService)

local function jsonEncode(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		return if value == math.floor(value) and math.abs(value) < 2 ^ 53 then string.format("%d", value) else string.format("%.17g", value)
	elseif kind == "string" then
		local escaped = string.gsub(value, '[%c"\\]', function(char)
			local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return named[char] or string.format("\\u%04x", string.byte(char))
		end)
		return '"' .. escaped .. '"'
	elseif kind == "table" then
		if #value > 0 or next(value) == nil then
			local parts = {}
			for _, item in ipairs(value) do
				table.insert(parts, jsonEncode(item))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for key in value do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		local parts = {}
		for _, key in keys do
			local item = value[key]
			if item == nil then
				item = value[tonumber(key)]
			end
			table.insert(parts, jsonEncode(key) .. ":" .. jsonEncode(item))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error(`Can't convert {kind} to JSON`)
end

local function jsonDecode(text)
	local position = 1
	local function skip()
		position = string.find(text, "[^%s]", position) or #text + 1
	end
	local parseValue
	local function parseString()
		local out = {}
		position += 1
		while true do
			local char = string.sub(text, position, position)
			if char == "" then
				error("Unterminated JSON string")
			elseif char == '"' then
				position += 1
				return table.concat(out)
			elseif char == "\\" then
				local nextChar = string.sub(text, position + 1, position + 1)
				local named = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				if nextChar == "u" then
					table.insert(out, utf8.char(tonumber(string.sub(text, position + 2, position + 5), 16)))
					position += 6
				else
					table.insert(out, named[nextChar] or nextChar)
					position += 2
				end
			else
				table.insert(out, char)
				position += 1
			end
		end
	end
	function parseValue()
		skip()
		local char = string.sub(text, position, position)
		if char == "{" then
			local object = {}
			position += 1
			skip()
			if string.sub(text, position, position) == "}" then
				position += 1
				return object
			end
			while true do
				skip()
				local key = parseString()
				skip()
				position += 1 -- the colon
				object[key] = parseValue()
				skip()
				local separator = string.sub(text, position, position)
				position += 1
				if separator == "}" then
					return object
				end
			end
		elseif char == "[" then
			local list = {}
			position += 1
			skip()
			if string.sub(text, position, position) == "]" then
				position += 1
				return list
			end
			while true do
				table.insert(list, parseValue())
				skip()
				local separator = string.sub(text, position, position)
				position += 1
				if separator == "]" then
					return list
				end
			end
		elseif char == '"' then
			return parseString()
		elseif string.sub(text, position, position + 3) == "true" then
			position += 4
			return true
		elseif string.sub(text, position, position + 4) == "false" then
			position += 5
			return false
		elseif string.sub(text, position, position + 3) == "null" then
			position += 4
			return nil
		end
		local number = string.match(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", position)
		if not number then
			error(`Can't parse JSON at {position}`)
		end
		position += #number
		return tonumber(number)
	end
	return parseValue()
end

----------------------------------------------------------------------------
-- Instances

local SUPER = {
	Part = "FormFactorPart", WedgePart = "FormFactorPart", FormFactorPart = "BasePart", SpawnLocation = "Part", Seat = "Part",
	MeshPart = "TriangleMeshPart", UnionOperation = "PartOperation", PartOperation = "TriangleMeshPart", TriangleMeshPart = "BasePart",
	CornerWedgePart = "BasePart", TrussPart = "BasePart", VehicleSeat = "BasePart", Terrain = "BasePart",
	BasePart = "PVInstance", Model = "PVInstance", Workspace = "WorldRoot", WorldRoot = "Model", PVInstance = "Instance",
	Frame = "GuiObject", TextLabel = "GuiObject", ImageLabel = "GuiObject", TextBox = "GuiObject", ScrollingFrame = "GuiObject",
	ViewportFrame = "GuiObject", CanvasGroup = "GuiObject", VideoFrame = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton",
	GuiButton = "GuiObject", GuiObject = "GuiBase2d", GuiBase2d = "Instance",
	ScreenGui = "LayerCollector", BillboardGui = "LayerCollector", SurfaceGui = "LayerCollector", LayerCollector = "GuiBase2d",
	LocalScript = "Script", Script = "BaseScript", BaseScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer",
	IntValue = "ValueBase", NumberValue = "ValueBase", StringValue = "ValueBase", BoolValue = "ValueBase", ObjectValue = "ValueBase",
	Vector3Value = "ValueBase", CFrameValue = "ValueBase", Color3Value = "ValueBase",
	Weld = "JointInstance", Motor6D = "JointInstance", Snap = "JointInstance",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light",
	Texture = "Decal", Decal = "FaceInstance",
	UICorner = "UIComponent", UIStroke = "UIComponent", UIGradient = "UIComponent", UIPadding = "UIComponent", UIScale = "UIComponent",
	UIListLayout = "UIGridStyleLayout", UIGridLayout = "UIGridStyleLayout", UIGridStyleLayout = "UILayout", UILayout = "UIComponent",
	UIAspectRatioConstraint = "UIConstraint", UISizeConstraint = "UIConstraint", UITextSizeConstraint = "UIConstraint",
	UIConstraint = "UIComponent", UIComponent = "UIBase",
	Animator = "Instance", Humanoid = "Instance",
}
local DEFAULTS = {
	Instance = { Archivable = true },
	BasePart = {
		Size = v3(4, 1, 2), Anchored = false, CanCollide = true, CanTouch = true, CanQuery = true, Transparency = 0,
		Reflectance = 0, Color = c3(0.639, 0.635, 0.647), Material = Enum.Material.Plastic, Massless = false, Locked = false,
		CastShadow = true, AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, Shape = Enum.PartType.Block,
		CollisionGroup = "Default", PivotOffset = IDENTITY,
	},
	Model = { PrimaryPart = nil },
	Humanoid = {
		Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, UseJumpPower = false, HipHeight = 2,
		AutoRotate = true, PlatformStand = false, Sit = false, DisplayName = "", RigType = Enum.HumanoidRigType.R15,
		MoveDirection = Vector3.zero, FloorMaterial = Enum.Material.Air,
	},
	GuiObject = {
		Visible = true, Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0, 0, 0, 0), AnchorPoint = Vector2.zero,
		BackgroundTransparency = 0, BackgroundColor3 = c3(1, 1, 1), BorderSizePixel = 1, ZIndex = 1, LayoutOrder = 0,
		Rotation = 0, Active = false, ClipsDescendants = false, AutomaticSize = Enum.AutomaticSize.None, Text = "",
		TextColor3 = c3(0, 0, 0), TextSize = 14, TextScaled = false, TextWrapped = false, RichText = false,
		TextTransparency = 0, TextStrokeTransparency = 1, Image = "", ImageTransparency = 0, ImageColor3 = c3(1, 1, 1),
		AbsoluteSize = Vector2.zero, AbsolutePosition = Vector2.zero, AutoButtonColor = true, Selectable = false,
	},
	-- A real ScreenGui always knows its size; this is the stand-in camera's.
	LayerCollector = { Enabled = true, ResetOnSpawn = true, DisplayOrder = 0, IgnoreGuiInset = false, AlwaysOnTop = false, Size = UDim2.new(0, 0, 0, 0), AbsoluteSize = v2(1280, 720), AbsolutePosition = Vector2.zero },
	UIScale = { Scale = 1 },
	UICorner = { CornerRadius = UDim.new(0, 8) },
	UIStroke = { Thickness = 1, Transparency = 0, Color = c3(0, 0, 0), Enabled = true },
	UIPadding = { PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0), PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0) },
	UIListLayout = { Padding = UDim.new(0, 0), AbsoluteContentSize = Vector2.zero },
	UIGridLayout = { CellSize = UDim2.new(0, 100, 0, 100), CellPadding = UDim2.new(0, 5, 0, 5), AbsoluteContentSize = Vector2.zero },
	UIGradient = { Enabled = true, Rotation = 0 },
	ScrollingFrame = { CanvasSize = UDim2.new(0, 0, 2, 0), CanvasPosition = Vector2.zero, ScrollBarThickness = 12, ScrollingEnabled = true },
	IntValue = { Value = 0 }, NumberValue = { Value = 0 }, StringValue = { Value = "" }, BoolValue = { Value = false },
	Sound = { Volume = 0.5, PlaybackSpeed = 1, Looped = false, Playing = false, IsPlaying = false, SoundId = "", TimePosition = 0, TimeLength = 0, IsLoaded = true },
	Light = { Brightness = 1, Range = 8, Color = c3(1, 1, 1), Enabled = true, Shadows = false },
	Player = {
		UserId = 0, DisplayName = "Player", AccountAge = 0, Neutral = true,
		CameraMode = Enum.CameraMode.Classic, CameraMinZoomDistance = 0.5, CameraMaxZoomDistance = 400,
	},
	Workspace = { Gravity = 196.2, FallenPartsDestroyHeight = -500, DistributedGameTime = 0, StreamingEnabled = false },
	Lighting = { ClockTime = 14, Brightness = 2, FogEnd = 100000, FogStart = 0, GlobalShadows = true, ExposureCompensation = 0 },
	Players = { MaxPlayers = 30, RespawnTime = 5, CharacterAutoLoads = true },
	Attachment = { CFrame = IDENTITY, Position = Vector3.zero, Visible = false },
	Camera = { CFrame = IDENTITY, FieldOfView = 70, ViewportSize = v2(1280, 720), CameraType = Enum.CameraType.Custom },
	ProximityPrompt = { Enabled = true, MaxActivationDistance = 10, HoldDuration = 0, ActionText = "Interact", ObjectText = "", RequiresLineOfSight = true },
	Tool = { Enabled = true, RequiresHandle = true, CanBeDropped = true, ToolTip = "", TextureId = "" },
	ParticleEmitter = { Enabled = true, Rate = 5 },
	Beam = { Enabled = true }, Trail = { Enabled = true }, Highlight = { Enabled = true, FillTransparency = 0.5, OutlineTransparency = 0 },
	RunService = {},
}
local EVENTS = {}
for _, name in {
	"Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "AttributeChanged",
	"Destroying", "Touched", "TouchEnded", "Died", "HealthChanged", "Running", "StateChanged", "MoveToFinished", "Jumping",
	"Activated", "Deactivated", "Equipped", "Unequipped", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
	"MouseButton2Click", "MouseEnter", "MouseLeave", "InputBegan", "InputEnded", "InputChanged", "FocusLost", "Focused",
	"Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded",
	"MouseClick", "RightMouseClick", "Ended", "Played", "Paused", "Resumed", "Loaded", "Completed", "Event", "OnServerEvent",
	"OnClientEvent", "PlayerAdded", "PlayerRemoving", "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded",
	"Chatted", "Idled", "Heartbeat", "Stepped", "RenderStepped", "PreRender", "PreSimulation", "PostSimulation",
	"PreAnimation", "PromptProductPurchaseFinished", "PromptGamePassPurchaseFinished", "PromptPurchaseFinished",
	"PromptBundlePurchaseFinished", "MessageOut", "Error", "LastInputTypeChanged", "TouchStarted", "TouchMoved", "TouchTap",
	"JumpRequest", "WindowFocused", "WindowFocusReleased", "MenuOpened", "MenuClosed", "ReturnPressedFromOnScreenKeyboard",
	"DidLoop", "AnimationPlayed", "KeyframeReached", "Stopped", "MessageReceived", "SendingMessage", "OnIncomingMessage",
	"TouchTapInWorld", "TouchPan", "TouchPinch", "TouchRotate", "TouchSwipe", "TouchLongPress", "PointerAction",
	"GamepadConnected", "GamepadDisconnected", "FiredToClient", "TextBoxFocused", "TextBoxFocusReleased", "DeviceGravityChanged",
} do
	EVENTS[name] = true
end

local records = setmetatable({}, { __mode = "k" })
local everything = setmetatable({}, { __mode = "k" })
local InstanceMeta = { __type = "Instance" }
local game -- the DataModel, set when the world is built
local Instance = {}

local function classChain(className)
	local chain = { className }
	local current = className
	while SUPER[current] do
		current = SUPER[current]
		table.insert(chain, current)
	end
	if chain[#chain] ~= "Instance" then
		table.insert(chain, "Instance")
	end
	return chain
end

local function isA(instance, className)
	for _, name in records[instance].chain do
		if name == className then
			return true
		end
	end
	return false
end

local function signal(instance, key)
	local rec = records[instance]
	local existing = rec.signals[key]
	if not existing then
		existing = newSignal()
		rec.signals[key] = existing
	end
	return existing
end

local function fireIfExists(instance, key, ...)
	local s = records[instance] and records[instance].signals[key]
	if s then
		s:Fire(...)
	end
end

local function descendants(instance, out)
	out = out or {}
	for _, child in records[instance].children do
		table.insert(out, child)
		descendants(child, out)
	end
	return out
end

local function isDescendantOf(instance, ancestor)
	local current = records[instance].parent
	while current do
		if current == ancestor then
			return true
		end
		current = records[current].parent
	end
	return false
end

local function setParent(instance, newParent)
	local rec = records[instance]
	if rec.destroyed then
		error(`The Parent property of {rec.props.Name} is locked, current parent: NULL, new parent {newParent and records[newParent].props.Name or "NULL"}`)
	end
	local oldParent = rec.parent
	if oldParent == newParent then
		return
	end
	if newParent and (newParent == instance or isDescendantOf(newParent, instance)) then
		error("Attempt to set parent of " .. rec.props.Name .. " to a descendant of itself")
	end
	local leavingPlayers = oldParent and rec.className == "Player" and records[oldParent].className == "Players"
	if leavingPlayers then
		fireIfExists(oldParent, "PlayerRemoving", instance)
	end
	if oldParent then
		local siblings = records[oldParent].children
		local index = table.find(siblings, instance)
		if index then
			table.remove(siblings, index)
		end
		local current = oldParent
		while current do
			fireIfExists(current, "DescendantRemoving", instance)
			current = records[current].parent
		end
		fireIfExists(oldParent, "ChildRemoved", instance)
	end
	rec.parent = newParent
	if newParent then
		table.insert(records[newParent].children, instance)
		fireIfExists(newParent, "ChildAdded", instance)
		local current = newParent
		while current do
			fireIfExists(current, "DescendantAdded", instance)
			current = records[current].parent
		end
	end
	if newParent and rec.className == "Player" and records[newParent].className == "Players" then
		fireIfExists(newParent, "PlayerAdded", instance)
	end
	fireIfExists(instance, "AncestryChanged", instance, newParent)
	fireIfExists(instance, "Changed", "Parent")
	local propertySignal = rec.propertySignals.Parent
	if propertySignal then
		propertySignal:Fire()
	end
end

local function findChild(instance, name)
	for _, child in records[instance].children do
		if records[child].props.Name == name then
			return child
		end
	end
	return nil
end

-- The part's world-axis bounding box, rotation included.
local function boundsOf(part)
	local frame = part.CFrame
	local half = part.Size / 2
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:GetComponents()
	local extent = v3(
		math.abs(r00) * half.X + math.abs(r01) * half.Y + math.abs(r02) * half.Z,
		math.abs(r10) * half.X + math.abs(r11) * half.Y + math.abs(r12) * half.Z,
		math.abs(r20) * half.X + math.abs(r21) * half.Y + math.abs(r22) * half.Z
	)
	local position = frame.Position
	return position - extent, position + extent
end

-- Where a ray first enters a box, as a fraction of `direction`, and the
-- face's normal; nil if it misses.
local function rayBox(origin, direction, lo, hi)
	local enter, leave, normal = 0, 1, nil
	for _, axis in { "X", "Y", "Z" } do
		local o, d = origin[axis], direction[axis]
		if math.abs(d) < 1e-12 then
			if o < lo[axis] or o > hi[axis] then
				return nil
			end
		else
			local a, b = (lo[axis] - o) / d, (hi[axis] - o) / d
			local face = if d > 0 then -1 else 1
			if a > b then
				a, b = b, a
			end
			if a > enter then
				enter = a
				normal = v3(if axis == "X" then face else 0, if axis == "Y" then face else 0, if axis == "Z" then face else 0)
			end
			leave = math.min(leave, b)
			if enter > leave then
				return nil
			end
		end
	end
	return enter, normal or v3(0, 0, 0)
end

local function worldParts(params)
	local exclude = not params or params.FilterType ~= Enum.RaycastFilterType.Include
	local filter = params and params.FilterDescendantsInstances or {}
	local parts = {}
	local workspace = game and game:GetService("Workspace")
	if not workspace then
		return parts
	end
	for _, item in descendants(workspace) do
		if isA(item, "BasePart") and item.CanQuery ~= false then
			local listed = false
			for _, entry in filter do
				if item == entry or isDescendantOf(item, entry) then
					listed = true
					break
				end
			end
			if listed ~= exclude then
				table.insert(parts, item)
			end
		end
	end
	return parts
end

local function pivotOf(instance)
	if isA(instance, "BasePart") then
		return instance.CFrame
	end
	local primary = instance.PrimaryPart
	if primary then
		return primary.CFrame
	end
	local stored = records[instance].props.WorldPivot
	if stored then
		return stored
	end
	local lo, hi
	for _, item in descendants(instance) do
		if isA(item, "BasePart") then
			local a, b = boundsOf(item)
			lo = if lo then lo:Min(a) else a
			hi = if hi then hi:Max(b) else b
		end
	end
	return if lo then CFrame.new((lo + hi) / 2) else IDENTITY
end

local METHODS
local function newInstance(className, parent)
	local instance = setmetatable({}, InstanceMeta)
	records[instance] = {
		className = className,
		chain = classChain(className),
		props = { Name = className },
		attributes = {},
		tags = {},
		children = {},
		signals = {},
		propertySignals = {},
		attributeSignals = {},
	}
	everything[instance] = true
	if isA(instance, "BasePart") then
		records[instance].props.CFrame = IDENTITY
	end
	if parent then
		setParent(instance, parent)
	end
	return instance
end

local function lookupDefault(rec, key)
	for _, name in rec.chain do
		local defaults = DEFAULTS[name]
		if defaults and defaults[key] ~= nil then
			return defaults[key]
		end
	end
	return nil
end

local function method(rec, key)
	for _, name in rec.chain do
		local set = METHODS[name]
		if set and set[key] then
			return set[key]
		end
	end
	return nil
end

InstanceMeta.__index = function(instance, key)
	local rec = records[instance]
	if key == "Parent" then
		return rec.parent
	elseif key == "ClassName" then
		return rec.className
	end
	local found = method(rec, key)
	if found then
		return found
	end
	local value = rec.props[key]
	if value ~= nil then
		return value
	end
	if isA(instance, "BasePart") then
		local frame = rec.props.CFrame
		if key == "Position" then
			return frame.Position
		elseif key == "Orientation" then
			local x, y, z = frame:ToOrientation()
			return v3(math.deg(x), math.deg(y), math.deg(z))
		elseif key == "Rotation" then
			local x, y, z = frame:ToEulerAnglesXYZ()
			return v3(math.deg(x), math.deg(y), math.deg(z))
		end
	elseif isA(instance, "Attachment") and (key == "WorldPosition" or key == "WorldCFrame") then
		local frame = rec.props.CFrame or IDENTITY
		local part = rec.parent
		local world = if part and isA(part, "BasePart") then part.CFrame * frame else frame
		return if key == "WorldPosition" then world.Position else world
	end
	if EVENTS[key] then
		return signal(instance, key)
	end
	local child = findChild(instance, key)
	if child then
		return child
	end
	return lookupDefault(rec, key)
end

local function propertyChanged(instance, rec, key)
	fireIfExists(instance, "Changed", key)
	local s = rec.propertySignals[key]
	if s then
		s:Fire()
	end
end

InstanceMeta.__newindex = function(instance, key, value)
	local rec = records[instance]
	if key == "Parent" then
		setParent(instance, value)
		return
	end
	if isA(instance, "BasePart") then
		local frame = rec.props.CFrame
		if key == "Position" then
			rec.props.CFrame = frame.Rotation + value
			propertyChanged(instance, rec, "Position")
			propertyChanged(instance, rec, "CFrame")
			return
		elseif key == "Orientation" then
			rec.props.CFrame = CFrame.new(frame.Position) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
			propertyChanged(instance, rec, "Orientation")
			propertyChanged(instance, rec, "CFrame")
			return
		elseif key == "CFrame" then
			rec.props.CFrame = value
			propertyChanged(instance, rec, "CFrame")
			propertyChanged(instance, rec, "Position")
			return
		end
	end
	if isA(instance, "Attachment") and key == "WorldPosition" then
		local part = rec.parent
		local local_ = if part and isA(part, "BasePart") then part.CFrame:PointToObjectSpace(value) else value
		rec.props.CFrame = (rec.props.CFrame or IDENTITY).Rotation + local_
		return
	end
	if isA(instance, "Attachment") and key == "Position" then
		rec.props.CFrame = (rec.props.CFrame or IDENTITY).Rotation + value
	end
	local old = rec.props[key]
	rec.props[key] = value
	if old ~= value then
		propertyChanged(instance, rec, key)
		if key == "Health" and isA(instance, "Humanoid") then
			fireIfExists(instance, "HealthChanged", value)
			if value <= 0 and (old == nil or old > 0) then
				fireIfExists(instance, "Died")
			end
		end
	end
end

InstanceMeta.__tostring = function(instance)
	return records[instance].props.Name
end

local function cloneInstance(instance)
	local rec = records[instance]
	if rec.props.Archivable == false then
		return nil
	end
	local copy = newInstance(rec.className)
	local copyRec = records[copy]
	copyRec.props = table.clone(rec.props)
	copyRec.attributes = table.clone(rec.attributes)
	copyRec.tags = table.clone(rec.tags)
	for _, child in rec.children do
		local childCopy = cloneInstance(child)
		if childCopy then
			setParent(childCopy, copy)
		end
	end
	return copy
end

local function destroy(instance)
	local rec = records[instance]
	if rec.destroyed then
		return
	end
	for _, child in table.clone(rec.children) do
		destroy(child)
	end
	fireIfExists(instance, "Destroying")
	setParent(instance, nil)
	rec.destroyed = true
	for _, s in rec.signals do
		s:DisconnectAll()
	end
	for _, s in rec.propertySignals do
		s:DisconnectAll()
	end
	for _, s in rec.attributeSignals do
		s:DisconnectAll()
	end
end

local tagSignals = { added = {}, removed = {} }
local function tagSignal(kind, tag)
	local list = tagSignals[kind]
	list[tag] = list[tag] or newSignal()
	return list[tag]
end

METHODS = {
	Instance = {
		GetChildren = function(self)
			return table.clone(records[self].children)
		end,
		GetDescendants = function(self)
			return descendants(self)
		end,
		FindFirstChild = function(self, name, recursive)
			if recursive then
				for _, item in descendants(self) do
					if records[item].props.Name == name then
						return item
					end
				end
				return nil
			end
			return findChild(self, name)
		end,
		FindFirstDescendant = function(self, name)
			for _, item in descendants(self) do
				if records[item].props.Name == name then
					return item
				end
			end
			return nil
		end,
		FindFirstChildOfClass = function(self, className)
			for _, child in records[self].children do
				if records[child].className == className then
					return child
				end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(self, className, recursive)
			for _, child in (if recursive then descendants(self) else records[self].children) do
				if isA(child, className) then
					return child
				end
			end
			return nil
		end,
		FindFirstAncestor = function(self, name)
			local current = records[self].parent
			while current do
				if records[current].props.Name == name then
					return current
				end
				current = records[current].parent
			end
			return nil
		end,
		FindFirstAncestorOfClass = function(self, className)
			local current = records[self].parent
			while current do
				if records[current].className == className then
					return current
				end
				current = records[current].parent
			end
			return nil
		end,
		FindFirstAncestorWhichIsA = function(self, className)
			local current = records[self].parent
			while current do
				if isA(current, className) then
					return current
				end
				current = records[current].parent
			end
			return nil
		end,
		WaitForChild = function(self, name, timeout)
			local deadline = clock + (timeout or 5)
			while true do
				local child = findChild(self, name)
				if child or clock >= deadline then
					return child
				end
				task.wait(0.05)
			end
		end,
		IsA = isA,
		IsDescendantOf = isDescendantOf,
		IsAncestorOf = function(self, other)
			return isDescendantOf(other, self)
		end,
		GetFullName = function(self)
			local names = {}
			local current = self
			while current and current ~= game do
				table.insert(names, 1, records[current].props.Name)
				current = records[current].parent
			end
			return table.concat(names, ".")
		end,
		Destroy = destroy,
		Remove = function(self)
			setParent(self, nil)
		end,
		Clone = cloneInstance,
		ClearAllChildren = function(self)
			for _, child in table.clone(records[self].children) do
				destroy(child)
			end
		end,
		SetAttribute = function(self, name, value)
			local rec = records[self]
			if type(name) ~= "string" then
				error("Attribute name must be a string")
			end
			local kind = realTypeof(value)
			if value ~= nil and kind == "table" then
				local mt = getmetatable(value)
				if not (mt and rawget(mt, "__type")) then
					error(`{kind} is not a supported attribute type`)
				end
			elseif kind == "function" or kind == "thread" or kind == "userdata" then
				error(`{kind} is not a supported attribute type`)
			end
			local old = rec.attributes[name]
			rec.attributes[name] = value
			if old ~= value then
				fireIfExists(self, "AttributeChanged", name)
				local s = rec.attributeSignals[name]
				if s then
					s:Fire()
				end
			end
		end,
		GetAttribute = function(self, name)
			return records[self].attributes[name]
		end,
		GetAttributes = function(self)
			return table.clone(records[self].attributes)
		end,
		GetAttributeChangedSignal = function(self, name)
			local rec = records[self]
			rec.attributeSignals[name] = rec.attributeSignals[name] or newSignal()
			return rec.attributeSignals[name]
		end,
		GetPropertyChangedSignal = function(self, name)
			local rec = records[self]
			rec.propertySignals[name] = rec.propertySignals[name] or newSignal()
			return rec.propertySignals[name]
		end,
		AddTag = function(self, tag)
			if not records[self].tags[tag] then
				records[self].tags[tag] = true
				tagSignal("added", tag):Fire(self)
			end
		end,
		RemoveTag = function(self, tag)
			if records[self].tags[tag] then
				records[self].tags[tag] = nil
				tagSignal("removed", tag):Fire(self)
			end
		end,
		HasTag = function(self, tag)
			return records[self].tags[tag] == true
		end,
		GetTags = function(self)
			local tags = {}
			for tag in records[self].tags do
				table.insert(tags, tag)
			end
			return tags
		end,
		GetActor = function()
			return nil
		end,
	},
	PVInstance = {
		GetPivot = pivotOf,
		PivotTo = function(self, target)
			if isA(self, "BasePart") then
				self.CFrame = target
				return
			end
			local delta = target * pivotOf(self):Inverse()
			for _, item in descendants(self) do
				if isA(item, "BasePart") then
					item.CFrame = delta * item.CFrame
				end
			end
			records[self].props.WorldPivot = target
		end,
	},
	BasePart = {
		GetMass = function(self)
			local size = self.Size
			return size.X * size.Y * size.Z * 0.7
		end,
		GetTouchingParts = function()
			return {}
		end,
		GetConnectedParts = function(self)
			return { self }
		end,
		GetRootPart = function(self)
			return self
		end,
		ApplyImpulse = function() end,
		ApplyAngularImpulse = function() end,
		SetNetworkOwner = function() end,
		GetNetworkOwner = function()
			return nil
		end,
		CanSetNetworkOwnership = function()
			return true
		end,
		BreakJoints = function() end,
	},
	Model = {
		GetBoundingBox = function(self)
			local lo, hi
			for _, item in descendants(self) do
				if isA(item, "BasePart") then
					local a, b = boundsOf(item)
					lo = if lo then lo:Min(a) else a
					hi = if hi then hi:Max(b) else b
				end
			end
			if not lo then
				return pivotOf(self), Vector3.zero
			end
			return CFrame.new((lo + hi) / 2), hi - lo
		end,
		GetExtentsSize = function(self)
			local _, size = METHODS.Model.GetBoundingBox(self)
			return size
		end,
		MoveTo = function(self, position)
			METHODS.PVInstance.PivotTo(self, CFrame.new(position) * pivotOf(self).Rotation)
		end,
		ScaleTo = function() end,
		GetScale = function()
			return 1
		end,
		SetPrimaryPartCFrame = function(self, target)
			METHODS.PVInstance.PivotTo(self, target)
		end,
		GetPrimaryPartCFrame = function(self)
			return self.PrimaryPart and self.PrimaryPart.CFrame
		end,
		BreakJoints = function() end,
	},
	WorldRoot = {
		-- Rays hit parts' bounding boxes (rotation included, shapes not).
		Raycast = function(_, origin, direction, raycastParams)
			local best, bestT, bestNormal = nil, math.huge, nil
			for _, part in worldParts(raycastParams) do
				if not (raycastParams and raycastParams.RespectCanCollide and not part.CanCollide) then
					local lo, hi = boundsOf(part)
					local t, normal = rayBox(origin, direction, lo, hi)
					if t and t < bestT then
						best, bestT, bestNormal = part, t, normal
					end
				end
			end
			if not best then
				return nil
			end
			local position = origin + direction * bestT
			return {
				Instance = best,
				Position = position,
				Normal = bestNormal,
				Distance = (direction * bestT).Magnitude,
				Material = best.Material,
			}
		end,
		Blockcast = function()
			return nil
		end,
		Spherecast = function()
			return nil
		end,
		Shapecast = function()
			return nil
		end,
		GetPartBoundsInBox = function(_, frame, size, overlap)
			local lo, hi = frame.Position - size / 2, frame.Position + size / 2
			local hits = {}
			for _, part in worldParts(overlap) do
				local a, b = boundsOf(part)
				if a.X < hi.X and b.X > lo.X and a.Y < hi.Y and b.Y > lo.Y and a.Z < hi.Z and b.Z > lo.Z then
					table.insert(hits, part)
				end
			end
			return hits
		end,
		GetPartBoundsInRadius = function(_, position, radius, overlap)
			local hits = {}
			for _, part in worldParts(overlap) do
				local a, b = boundsOf(part)
				local nearest = position:Max(a):Min(b)
				if (nearest - position).Magnitude <= radius then
					table.insert(hits, part)
				end
			end
			return hits
		end,
		GetPartsInPart = function(self, part, overlap)
			return METHODS.WorldRoot.GetPartBoundsInBox(self, part.CFrame, part.Size, overlap)
		end,
		ArePartsTouchingOthers = function()
			return false
		end,
		BulkMoveTo = function(_, parts, frames)
			for i, part in parts do
				part.CFrame = frames[i]
			end
		end,
	},
	Workspace = {
		GetServerTimeNow = function()
			return START_UNIX + clock
		end,
		GetRealPhysicsFPS = function()
			return 60
		end,
	},
	Terrain = {
		FillBlock = function() end,
		FillBall = function() end,
		FillCylinder = function() end,
		FillWedge = function() end,
		FillRegion = function() end,
		Clear = function() end,
		ReplaceMaterial = function() end,
		SetMaterialColor = function() end,
		GetMaterialColor = function()
			return c3(1, 1, 1)
		end,
	},
	Humanoid = {
		TakeDamage = function(self, amount)
			if self.Health > 0 then
				self.Health = math.max(0, self.Health - amount)
			end
		end,
		MoveTo = function() end,
		ChangeState = function() end,
		GetState = function()
			return Enum.HumanoidStateType.Running
		end,
		SetStateEnabled = function() end,
		GetStateEnabled = function()
			return true
		end,
		EquipTool = function(self, tool)
			local character = records[self].parent
			if character then
				tool.Parent = character
			end
		end,
		UnequipTools = function() end,
		GetAccessories = function()
			return {}
		end,
		LoadAnimation = function()
			return { Play = function() end, Stop = function() end, AdjustSpeed = function() end, Stopped = newSignal() }
		end,
	},
	Animator = {
		LoadAnimation = function()
			return { Play = function() end, Stop = function() end, AdjustSpeed = function() end, Stopped = newSignal() }
		end,
	},
	Sound = {
		Play = function(self)
			self.Playing = true
		end,
		Stop = function(self)
			self.Playing = false
		end,
		Pause = function(self)
			self.Playing = false
		end,
		Resume = function(self)
			self.Playing = true
		end,
	},
	ParticleEmitter = { Emit = function() end, Clear = function() end },
	Tool = {
		Activate = function(self)
			fireIfExists(self, "Activated")
		end,
		Deactivate = function(self)
			fireIfExists(self, "Deactivated")
		end,
	},
	Player = {
		Kick = function(self)
			setParent(self, nil)
		end,
		LoadCharacterAsync = function(self)
			local old = self.Character
			if old then
				fireIfExists(self, "CharacterRemoving", old)
				destroy(old)
			end
			local character = newInstance("Model")
			character.Name = self.Name
			local root = newInstance("Part", character)
			root.Name = "HumanoidRootPart"
			root.Size = v3(2, 2, 1)
			local head = newInstance("Part", character)
			head.Name = "Head"
			head.Size = v3(2, 1, 1)
			local humanoid = newInstance("Humanoid", character)
			humanoid.Name = "Humanoid"
			character.PrimaryPart = root
			local spawn = self.RespawnLocation
			local at = if spawn then spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3, 0) else CFrame.new(0, 3, 0)
			root.CFrame = at
			head.CFrame = at * CFrame.new(0, 1.5, 0)
			setParent(character, game:GetService("Workspace"))
			self.Character = character
			fireIfExists(self, "CharacterAdded", character)
		end,
		IsFriendsWith = function()
			return false
		end,
		IsFriendsWithAsync = function()
			return false
		end,
		GetNetworkPing = function()
			return 0.06
		end,
		GetRankInGroup = function()
			return 0
		end,
		IsInGroup = function()
			return false
		end,
		GetJoinData = function()
			return {}
		end,
		GetFriendsOnline = function()
			return {}
		end,
		GetMouse = function()
			return { Hit = IDENTITY, Target = nil, X = 0, Y = 0, Move = newSignal(), Button1Down = newSignal(), Button1Up = newSignal() }
		end,
	},
	Camera = {
		WorldToViewportPoint = function()
			return Vector3.new(0, 0, 1), true
		end,
		WorldToScreenPoint = function()
			return Vector3.new(0, 0, 1), true
		end,
		ScreenPointToRay = function()
			return { Origin = Vector3.zero, Direction = Vector3.new(0, 0, -1) }
		end,
		ViewportPointToRay = function()
			return { Origin = Vector3.zero, Direction = Vector3.new(0, 0, -1) }
		end,
	},
	Team = {
		GetPlayers = function(self)
			local players = {}
			for _, player in game:GetService("Players"):GetPlayers() do
				if records[player].props.Team == self then
					table.insert(players, player)
				end
			end
			return players
		end,
	},
	-- One stand-in world plays both sides: what the server sends reaches
	-- OnClientEvent when it's for Players.LocalPlayer (if a spec set one), and
	-- every send also fires FiredToClient(player, ...), a spec-only signal
	-- that says who it was for. What a client sends arrives as LocalPlayer.
	RemoteEvent = {
		FireServer = function(self, ...)
			local localPlayer = game:GetService("Players").LocalPlayer
			if localPlayer then
				signal(self, "OnServerEvent"):Fire(localPlayer, ...)
			end
		end,
		FireClient = function(self, player, ...)
			signal(self, "FiredToClient"):Fire(player, ...)
			if player == game:GetService("Players").LocalPlayer then
				signal(self, "OnClientEvent"):Fire(...)
			end
		end,
		FireAllClients = function(self, ...)
			local players = game:GetService("Players")
			for _, player in players:GetPlayers() do
				signal(self, "FiredToClient"):Fire(player, ...)
			end
			if players.LocalPlayer then
				signal(self, "OnClientEvent"):Fire(...)
			end
		end,
	},
	UnreliableRemoteEvent = {
		FireServer = function() end,
		FireClient = function() end,
		FireAllClients = function() end,
	},
	RemoteFunction = {
		InvokeServer = function(self, ...)
			local localPlayer = game:GetService("Players").LocalPlayer
			local handler = records[self].props.OnServerInvoke
			if not (localPlayer and handler) then
				error("InvokeServer needs Players.LocalPlayer and an OnServerInvoke")
			end
			return handler(localPlayer, ...)
		end,
		InvokeClient = function()
			return nil
		end,
	},
	BindableEvent = {
		Fire = function(self, ...)
			signal(self, "Event"):Fire(...)
		end,
	},
	BindableFunction = {
		Invoke = function(self, ...)
			local handler = records[self].props.OnInvoke
			if not handler then
				error("OnInvoke is not set")
			end
			return handler(...)
		end,
	},
}

function Instance.new(className, parent)
	return newInstance(className, parent)
end
function Instance.fromExisting(instance)
	return cloneInstance(instance)
end

----------------------------------------------------------------------------
-- Services

local function noop() end
local SERVICE_METHODS = {
	RunService = {
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsRunning = function()
			return false
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return true
		end,
		BindToRenderStep = noop,
		UnbindFromRenderStep = noop,
	},
	Players = {
		GetPlayers = function(self)
			local players = {}
			for _, child in records[self].children do
				if records[child].className == "Player" then
					table.insert(players, child)
				end
			end
			return players
		end,
		GetPlayerFromCharacter = function(self, character)
			for _, child in records[self].children do
				if records[child].className == "Player" and records[child].props.Character == character then
					return child
				end
			end
			return nil
		end,
		GetPlayerByUserId = function(self, userId)
			for _, child in records[self].children do
				if records[child].className == "Player" and records[child].props.UserId == userId then
					return child
				end
			end
			return nil
		end,
		GetUserThumbnailAsync = function()
			return "rbxassetid://0", true
		end,
		GetNameFromUserIdAsync = function()
			return "Player"
		end,
		GetUserIdFromNameAsync = function()
			return 0
		end,
		GetFriendsAsync = function()
			return { GetCurrentPage = function()
				return {}
			end, IsFinished = true }
		end,
	},
	HttpService = {
		JSONEncode = function(_, value)
			return jsonEncode(value)
		end,
		JSONDecode = function(_, text)
			return jsonDecode(text)
		end,
		GenerateGUID = (function()
			local count = 0
			return function(_, braces)
				count += 1
				local id = string.format("00000000-0000-4000-8000-%012d", count)
				return if braces == false then id else "{" .. id .. "}"
			end
		end)(),
		UrlEncode = function(_, text)
			return (string.gsub(text, "[^%w%-_%.~]", function(char)
				return string.format("%%%02X", string.byte(char))
			end))
		end,
		GetAsync = function()
			error("Http requests are not enabled")
		end,
		PostAsync = function()
			error("Http requests are not enabled")
		end,
		RequestAsync = function()
			error("Http requests are not enabled")
		end,
	},
	TweenService = {
		Create = function(_, instance, info, goals)
			local tween = { PlaybackState = Enum.PlaybackState.Begin, Completed = newSignal(), Instance = instance, TweenInfo = info }
			function tween:Play()
				for key, value in goals do
					instance[key] = value
				end
				tween.PlaybackState = Enum.PlaybackState.Completed
				task.delay(info and info.Time or 0, function()
					tween.Completed:Fire(Enum.PlaybackState.Completed)
				end)
			end
			function tween:Cancel()
				tween.PlaybackState = Enum.PlaybackState.Cancelled
			end
			function tween:Pause()
				tween.PlaybackState = Enum.PlaybackState.Paused
			end
			function tween:Destroy() end
			return tween
		end,
		GetValue = function(_, alpha)
			return alpha
		end,
	},
	Debris = {
		AddItem = function(_, instance, lifetime)
			task.delay(lifetime or 10, function()
				if records[instance] and not records[instance].destroyed then
					destroy(instance)
				end
			end)
		end,
	},
	CollectionService = {
		GetTagged = function(_, tag)
			local tagged = {}
			for instance in everything do
				local rec = records[instance]
				if rec and rec.tags[tag] and not rec.destroyed and (instance == game or isDescendantOf(instance, game)) then
					table.insert(tagged, instance)
				end
			end
			return tagged
		end,
		AddTag = function(_, instance, tag)
			METHODS.Instance.AddTag(instance, tag)
		end,
		RemoveTag = function(_, instance, tag)
			METHODS.Instance.RemoveTag(instance, tag)
		end,
		HasTag = function(_, instance, tag)
			return METHODS.Instance.HasTag(instance, tag)
		end,
		GetTags = function(_, instance)
			return METHODS.Instance.GetTags(instance)
		end,
		GetInstanceAddedSignal = function(_, tag)
			return tagSignal("added", tag)
		end,
		GetInstanceRemovedSignal = function(_, tag)
			return tagSignal("removed", tag)
		end,
	},
	DataStoreService = (function()
		local function store()
			local blocked = function()
				error("502: API Services rejected request with error. Error code: 7 Reason: Studio access to APIs is not allowed.")
			end
			return { GetAsync = blocked, SetAsync = blocked, UpdateAsync = blocked, RemoveAsync = blocked, IncrementAsync = blocked, GetSortedAsync = blocked, ListKeysAsync = blocked }
		end
		return {
			GetDataStore = store,
			GetOrderedDataStore = store,
			GetGlobalDataStore = store,
			GetRequestBudgetForRequestType = function()
				return 0
			end,
		}
	end)(),
	MarketplaceService = {
		UserOwnsGamePassAsync = function()
			return false
		end,
		PlayerOwnsAsset = function()
			return false
		end,
		PlayerOwnsBundle = function()
			return false
		end,
		GetProductInfo = function(_, id)
			return { Name = "", Description = "", PriceInRobux = 0, IsForSale = false, AssetId = id, ProductId = id }
		end,
		PromptProductPurchase = noop,
		PromptGamePassPurchase = noop,
		PromptPurchase = noop,
		PromptPremiumPurchase = noop,
	},
	BadgeService = {
		AwardBadge = function()
			return true
		end,
		UserHasBadgeAsync = function()
			return false
		end,
		GetBadgeInfoAsync = function()
			return { IsEnabled = true, Name = "", Description = "" }
		end,
	},
	TextService = {
		GetTextSize = function(_, text, size)
			return v2(#text * size * 0.5, size)
		end,
		FilterStringAsync = function(_, text)
			return {
				GetNonChatStringForBroadcastAsync = function()
					return text
				end,
				GetNonChatStringForUserAsync = function()
					return text
				end,
				GetChatForUserAsync = function()
					return text
				end,
			}
		end,
	},
	PhysicsService = {
		RegisterCollisionGroup = noop,
		CollisionGroupSetCollidable = noop,
		CollisionGroupsAreCollidable = function()
			return true
		end,
		IsCollisionGroupRegistered = function()
			return true
		end,
		GetRegisteredCollisionGroups = function()
			return {}
		end,
	},
	PathfindingService = {
		CreatePath = function()
			return {
				Status = Enum.PathStatus.NoPath,
				ComputeAsync = noop,
				GetWaypoints = function()
					return {}
				end,
				Blocked = newSignal(),
				Destroy = noop,
			}
		end,
	},
	StarterGui = {
		SetCore = noop,
		GetCore = function()
			return nil
		end,
		SetCoreGuiEnabled = noop,
		GetCoreGuiEnabled = function()
			return true
		end,
	},
	SoundService = { PlayLocalSound = noop, SetListener = noop },
	ContentProvider = { PreloadAsync = noop },
	Stats = {
		GetTotalMemoryUsageMb = function()
			return 420
		end,
	},
	AnalyticsService = {
		LogCustomEvent = noop,
		LogEconomyEvent = noop,
		LogFunnelStepEvent = noop,
		LogOnboardingFunnelStepEvent = noop,
		LogProgressionEvent = noop,
		LogProgressionStartEvent = noop,
		LogProgressionCompleteEvent = noop,
		LogProgressionFailEvent = noop,
	},
	MessagingService = {
		PublishAsync = function()
			error("MessagingService isn't available in Studio Edit mode")
		end,
		SubscribeAsync = function()
			error("MessagingService isn't available in Studio Edit mode")
		end,
	},
	TeleportService = { TeleportAsync = noop, Teleport = noop, GetLocalPlayerTeleportData = function()
		return nil
	end },
	Teams = {
		GetTeams = function(self)
			return table.clone(records[self].children)
		end,
	},
	UserInputService = {
		IsKeyDown = function()
			return false
		end,
		IsMouseButtonPressed = function()
			return false
		end,
		GetMouseLocation = function()
			return Vector2.zero
		end,
		GetLastInputType = function()
			return Enum.UserInputType.MouseMovement
		end,
		GetConnectedGamepads = function()
			return {}
		end,
	},
	ContextActionService = { BindAction = noop, UnbindAction = noop, BindActionAtPriority = noop, SetTitle = noop, SetImage = noop, SetPosition = noop, GetButton = function()
		return nil
	end },
	GuiService = { GetGuiInset = function()
		return Vector2.new(0, 36), Vector2.zero
	end },
	PolicyService = { GetPolicyInfoForPlayerAsync = function()
		return { ArePaidRandomItemsRestricted = false, IsSubjectToChinaPolicies = false, AllowedExternalLinkReferences = {} }
	end },
	GroupService = { GetGroupInfoAsync = function()
		return {}
	end },
	LocalizationService = { GetCountryRegionForPlayerAsync = function()
		return "US"
	end },
	MemoryStoreService = (function()
		local blocked = function()
			error("MemoryStoreService isn't available in Studio Edit mode")
		end
		return { GetQueue = blocked, GetSortedMap = blocked, GetHashMap = blocked }
	end)(),
	Lighting = {
		GetMinutesAfterMidnight = function(self)
			return (self.ClockTime or 14) * 60
		end,
		SetMinutesAfterMidnight = function(self, minutes)
			self.ClockTime = minutes / 60
		end,
	},
	ServerStorage = {},
}

local SERVICE_CLASS = { Workspace = "Workspace" }

local function buildWorld(tree)
	local root = newInstance("DataModel")
	records[root].props.Name = "Game"
	game = root
	local services = {}
	local function getService(_, name)
		local existing = services[name]
		if existing then
			return existing
		end
		local service = newInstance(SERVICE_CLASS[name] or name)
		records[service].props.Name = name
		local extra = SERVICE_METHODS[name]
		if extra then
			METHODS[name] = METHODS[name] or {}
			for key, fn in extra do
				METHODS[name][key] = fn
			end
		end
		services[name] = service
		setParent(service, root)
		return service
	end
	METHODS.DataModel = {
		GetService = getService,
		FindService = function(_, name)
			return services[name]
		end,
		BindToClose = noop,
		IsLoaded = function()
			return true
		end,
		GetJobsInfo = function()
			return {}
		end,
	}
	records[root].props.PlaceId = 0
	records[root].props.GameId = 0
	records[root].props.JobId = ""
	records[root].props.PlaceVersion = 0
	records[root].props.CreatorId = 0
	for _, name in { "Workspace", "Players", "Lighting", "ReplicatedStorage", "ReplicatedFirst", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "SoundService", "Teams", "Chat", "RunService", "TweenService", "HttpService", "CollectionService", "Debris", "MarketplaceService", "DataStoreService", "BadgeService", "TextService", "PhysicsService" } do
		getService(root, name)
	end
	local workspace = services.Workspace
	local terrain = newInstance("Terrain", workspace)
	records[terrain].props.Name = "Terrain"
	records[workspace].props.Terrain = terrain
	local camera = newInstance("Camera", workspace)
	records[camera].props.Name = "Camera"
	records[workspace].props.CurrentCamera = camera
	records[services.Lighting].props.ClockTime = 14

	for _, entry in tree do
		local segments = string.split(entry.path, "/")
		local current = getService(root, segments[1])
		for i = 2, #segments do
			local name = segments[i]
			local child = findChild(current, name)
			if not child then
				local className = if i == #segments then entry.class elseif name == "StarterPlayerScripts" or name == "StarterCharacterScripts" then name else "Folder"
				child = newInstance(className)
				records[child].props.Name = name
				setParent(child, current)
			end
			if i == #segments and entry.source then
				records[child].props.Source = entry.source
			end
			current = child
		end
	end
	return root, workspace
end

----------------------------------------------------------------------------
-- Globals and require

local function typeofShim(value)
	local mt = getmetatable(value)
	if type(mt) == "table" then
		local name = rawget(mt, "__type")
		if name then
			return name
		end
	end
	return realTypeof(value)
end

local function show(...)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	return table.concat(parts, " ", 1, parts.n)
end

local function makeGlobals(workspace)
	local globals = {
		game = game,
		Game = game,
		workspace = workspace,
		Workspace = workspace,
		script = nil,
		plugin = nil,
		shared = {},
		task = task,
		wait = task.wait,
		delay = task.delay,
		spawn = task.defer,
		tick = function()
			return START_UNIX + clock
		end,
		time = function()
			return clock
		end,
		elapsedTime = function()
			return clock
		end,
		os = os,
		typeof = typeofShim,
		print = function(...)
			table.insert(log, show(...))
		end,
		warn = function(...)
			table.insert(log, "warning: " .. show(...))
		end,
		settings = function()
			return { Physics = {}, Rendering = {}, Network = {} }
		end,
		UserSettings = function()
			return { GameSettings = {}, GetService = function()
				return {}
			end }
		end,
		version = function()
			return "0.0.0.0"
		end,
		Enum = Enum,
		Instance = Instance,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrame,
		Color3 = Color3,
		BrickColor = BrickColor,
		UDim = UDim,
		UDim2 = UDim2,
		NumberRange = NumberRange,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		TweenInfo = TweenInfo,
		RaycastParams = RaycastParams,
		OverlapParams = OverlapParams,
		Random = Random,
		Faces = Faces,
		PhysicalProperties = PhysicalProperties,
	}
	local cache = {}
	local loading = {}
	globals.require = function(module)
		if typeofShim(module) ~= "Instance" then
			error("Attempted to call require with invalid argument(s).")
		end
		if cache[module] ~= nil then
			return cache[module]
		end
		-- As in Roblox: a module that (through others) requires itself fails.
		if loading[module] then
			error(`Requested module was required recursively: {module:GetFullName()}`)
		end
		loading[module] = true
		local source = module.Source
		if not source then
			error(`{module:GetFullName()} has no source`)
		end
		local fn, err = loadstring(source, module:GetFullName())
		if not fn then
			error(err)
		end
		setfenv(fn, setmetatable({ script = module }, { __index = globals }))
		local ok, result = pcall(fn)
		loading[module] = nil
		if not ok then
			error(result, 0)
		end
		cache[module] = if result == nil then false else result
		return result
	end
	return setmetatable(globals, { __index = getfenv(0) })
end

----------------------------------------------------------------------------
-- Run the spec

local _, workspace = buildWorld(BUNDLE.tree)
local globals = makeGlobals(workspace)
local name = BUNDLE.spec
local specFn, compileError = loadstring(BUNDLE.specSource, name)
if not specFn then
	print(`FAIL {name}: {compileError}`)
	return
end
setfenv(specFn, setmetatable({
	-- For a spec that sets off an error on purpose: the background errors so
	-- far (then forgotten, so they don't fail the spec).
	takeBackgroundErrors = function()
		local list = table.clone(backgroundErrors)
		table.clear(backgroundErrors)
		return list
	end,
}, { __index = globals }))

local finished, outcome = false, nil
local mainThread = coroutine.create(function()
	outcome = table.pack(xpcall(specFn, function(err)
		return debug.traceback(tostring(err), 2)
	end))
	finished = true
end)
resume(mainThread)
local steps = 0
while not finished do
	local item = popNext()
	if not item then
		break
	end
	if item.at > clock then
		clock = item.at
	end
	if clock > MAX_VIRTUAL_SECONDS then
		break
	end
	steps += 1
	if steps > 2_000_000 then
		break
	end
	resume(item.thread, table.unpack(item.args, 1, item.args.n))
end

-- Specs return a message or a summary table ({ status = "PASS", checks = 12, ... }).
local function summary(result)
	if type(result) ~= "table" then
		return tostring(result), true
	end
	local parts = {}
	for key, value in result do
		if key ~= "status" and key ~= "coverage" and type(value) ~= "table" then
			table.insert(parts, `{key} {value}`)
		end
	end
	table.sort(parts)
	return table.concat(parts, ", "), result.status == nil or result.status == "PASS"
end

if finished and outcome[1] then
	local text, passed = summary(outcome[2])
	-- An error in any background thread fails the spec, however it ended.
	if passed and #backgroundErrors > 0 then
		passed = false
		text = `{#backgroundErrors} background error(s); {text}`
	end
	print(`{if passed then "PASS" else "FAIL"} {name}: {text}`)
elseif finished then
	print(`FAIL {name}: {outcome[2]}`)
elseif clock > MAX_VIRTUAL_SECONDS or steps > 2_000_000 then
	print(`FAIL {name}: still running after {math.floor(clock)} virtual seconds`)
else
	print(`FAIL {name}: stuck waiting (nothing left to run) at {clock}s`)
end
for _, line in log do
	print("  | " .. line)
end
for _, err in backgroundErrors do
	print("  ! background error: " .. string.gsub(err, "\n", "\n  !   "))
end
