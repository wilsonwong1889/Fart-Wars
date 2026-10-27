-- Whether the mouse should be free. In a match the mouse is locked to the
-- crosshair in both views (CameraController applies it); anything that
-- needs a free mouse says so here under its own reason, and it stays free
-- while any reason holds:
--   "key"         the unlock key (UIConfig.keys.unlockMouse) toggled it
--   "menu", ...   a screen with buttons is open (each screen its own name)
-- Only state lives here: no camera or input code, so every screen and the
-- camera can use it without depending on each other.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local MouseLock = {}

-- Fires with isFree() whenever that changes.
MouseLock.Changed = Signal.new()

local reasons: { [string]: true } = {}
local wasFree = false

local function announce()
	local free = next(reasons) ~= nil
	if free ~= wasFree then
		wasFree = free
		MouseLock.Changed:Fire(free)
	end
end

-- Asks for a free mouse under `reason` (or stops asking).
function MouseLock.setFree(reason: string, free: boolean)
	reasons[reason] = if free then true else nil
	announce()
end

-- The unlock key: frees the mouse, or locks it again.
function MouseLock.toggleKey()
	MouseLock.setFree("key", not reasons.key)
end

-- Whether anything wants the mouse free right now.
function MouseLock.isFree(): boolean
	return next(reasons) ~= nil
end

-- Whether `reason` is asking for it.
function MouseLock.holds(reason: string): boolean
	return reasons[reason] == true
end

-- Specs only: back to locked, nothing asking.
function MouseLock.reset()
	table.clear(reasons)
	wasFree = false
end

return MouseLock
