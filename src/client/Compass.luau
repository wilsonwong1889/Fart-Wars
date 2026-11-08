-- The compass's arithmetic, apart from the screen so it can be checked on
-- its own: bearings, where things sit on the strip, where a point in the
-- world lands on the screen, and where an arrow near the screen's edge
-- goes for something off it.
-- Bearings are degrees clockwise from north, in [0, 360). North is -Z and
-- east is +X: the way a Roblox camera looks before it turns, and its right.
local Compass = {}

Compass.LETTERS = table.freeze({ "N", "NE", "E", "SE", "S", "SW", "W", "NW" })

-- The bearing of a direction along the ground (its height is ignored), or
-- nil for one straight up or down.
function Compass.bearingOf(direction: Vector3): number?
	if direction.X * direction.X + direction.Z * direction.Z < 1e-12 then
		return nil
	end
	return math.deg(math.atan2(direction.X, -direction.Z)) % 360
end

-- The bearing a camera faces, from its right side, so it's still right
-- when the camera looks straight down (cameras never roll).
function Compass.heading(view: CFrame): number
	local right = view.RightVector
	return math.deg(math.atan2(right.Z, right.X)) % 360
end

-- `bearing` seen from `heading`: in (-180, 180], negative to the left.
function Compass.relative(bearing: number, heading: number): number
	local offset = (bearing - heading) % 360
	return if offset > 180 then offset - 360 else offset
end

-- The nearest of the eight directions' letters.
function Compass.letter(bearing: number): string
	return Compass.LETTERS[math.floor((bearing % 360 + 22.5) / 45) % 8 + 1]
end

-- Where on a strip `width` pixels wide showing `span` degrees a bearing
-- sits (pixels from its left edge, the heading in the middle), and whether
-- that's on the strip at all.
function Compass.stripX(bearing: number, heading: number, width: number, span: number): (number, boolean)
	local offset = Compass.relative(bearing, heading)
	return width / 2 + offset * width / span, math.abs(offset) <= span / 2
end

-- Names on one row of the strip, in priority order (nearest first): each
-- { x = its middle, width = its width }. Which are shown: those on the
-- strip that keep `gap` pixels clear of every one shown before them.
function Compass.layout(items: { { x: number, width: number } }, stripWidth: number, gap: number): { boolean }
	local shown, placed = {}, {}
	for i, item in items do
		local left, right = item.x - item.width / 2, item.x + item.width / 2
		local fits = item.x >= 0 and item.x <= stripWidth
		for _, other in placed do
			if left < other.right + gap and right > other.left - gap then
				fits = false
				break
			end
		end
		shown[i] = fits
		if fits then
			table.insert(placed, { left = left, right = right })
		end
	end
	return shown
end

-- Where a point in the world lands on the screen, as
-- Camera:WorldToViewportPoint works it out (pixels from the top left, with
-- FieldOfView the vertical angle), and how far in front of the camera it
-- is (negative: behind it, where the spot means nothing).
function Compass.project(view: CFrame, fieldOfView: number, viewport: Vector2, point: Vector3): (Vector2, number)
	local relative = view:PointToObjectSpace(point)
	local depth = -relative.Z
	local tanY = math.tan(math.rad(fieldOfView) / 2)
	local tanX = tanY * viewport.X / viewport.Y
	local d = if math.abs(depth) < 1e-6 then 1e-6 else depth
	local x = (1 + relative.X / (d * tanX)) / 2 * viewport.X
	local y = (1 - relative.Y / (d * tanY)) / 2 * viewport.Y
	return Vector2.new(x, y), depth
end

-- Whether a projected point is on the screen, at least `margin` pixels in
-- from its edges.
function Compass.onScreen(screen: Vector2, depth: number, viewport: Vector2, margin: number): boolean
	return depth > 0
		and screen.X >= margin
		and screen.X <= viewport.X - margin
		and screen.Y >= margin
		and screen.Y <= viewport.Y - margin
end

-- Where the arrow for something off the screen goes: on the ellipse
-- `insetX` in from the screen's sides and `insetY` in from its top and
-- bottom, in the direction of the thing from the middle of the screen. In
-- front of the camera that's the way it lies on the screen; behind it,
-- its bearing (straight ahead at the top, behind you at the bottom, as the
-- red marker for whoever hit you does). Returns the spot and the arrow's
-- rotation (degrees clockwise, 0 pointing up).
function Compass.edge(view: CFrame, fieldOfView: number, viewport: Vector2, point: Vector3, insetX: number, insetY: number): (Vector2, number)
	local screen, depth = Compass.project(view, fieldOfView, viewport, point)
	local center = viewport / 2
	local angle: number
	local toward = screen - center
	if depth > 0 and toward.Magnitude > 1e-6 then
		angle = math.atan2(toward.X, -toward.Y)
	else
		local heading = Compass.heading(view)
		local bearing = Compass.bearingOf(point - view.Position) or heading
		angle = math.rad(Compass.relative(bearing, heading))
	end
	local rx, ry = math.max(center.X - insetX, 1), math.max(center.Y - insetY, 1)
	local sin, cos = math.sin(angle), math.cos(angle)
	-- The ray from the middle at `angle`, to where it meets the ellipse.
	local reach = 1 / math.sqrt((sin / rx) ^ 2 + (cos / ry) ^ 2)
	return center + Vector2.new(sin * reach, -cos * reach), math.deg(angle)
end

-- Where a ray from `origin` along `direction` meets the ground (y = 0)
-- within `range`, for a ping aimed at nothing nearer; nil when it never
-- does (aimed level or up, or too far).
function Compass.groundSpot(origin: Vector3, direction: Vector3, range: number): Vector3?
	if direction.Magnitude < 1e-6 then
		return nil
	end
	local unit = direction.Unit
	if unit.Y > -1e-3 or origin.Y < 0 then
		return nil
	end
	local distance = -origin.Y / unit.Y
	return if distance <= range then origin + unit * distance else nil
end

return Compass
