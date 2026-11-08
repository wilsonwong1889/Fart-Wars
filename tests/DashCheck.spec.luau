-- Fart Dash's wall check (DashService), on the real map: a fair dash is
-- never taken for going through a wall, and a real one still is. Each
-- case is a path the avatar's middle takes during the check (the server
-- sees it every frame), from a fresh dash:
--   * round a divider's end, seen all the way or in one jump (the
--     server's view lagging), where a straight line between the ends cuts
--     through the divider's corner
--   * along a wall, round a pillar sticking out of it
--   * off the top of a wall, and up onto something (as at the top of a
--     slope), where the straight line runs through what's below
--   * over a wall low enough to jump, and through a part nobody bumps into
--     (CanCollide off)
--   * the allowance grows with the player's ping, up to half a second, so
--     going round a corner that only fits with the lag is fine
--   * still put back and flagged (with the wall's name): through a
--     divider's middle in one jump, walked through it, and over a wall too
--     high to jump (however high the path goes)
local Players = game:GetService("Players")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
do
	local run = assert(loadstring(server.Bootstrap.Source, "Bootstrap"))
	setfenv(run, setmetatable({ script = server.Bootstrap }, { __index = getfenv() }))
	run()
end
require(server.Services.BotDirector).testSetEnabled(false)
local Dash = require(server.Services.DashService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local MapService = require(server.Services.MapService)
local Telemetry = require(server.Telemetry)
local Moderation = require(server.Moderation)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local DASH = require(game.ReplicatedStorage.Shared.Config.AbilityConfig).FartDash

local ada = Instance.new("Player")
ada.Name = "Ada"
ada.UserId = 701
ada.Parent = Players
task.wait(0.05)
Lifecycle.requestPlay(ada, nil)
task.wait(0.5)
check(Lifecycle.stateOf(ada) == "ACTIVE" and ada.Character, "Ada is in the match")

local walls = MapService.current():FindFirstChild("Walls")
-- The east divider's segment nearest the Stinkers (x 75..81, z -135..-72
-- at the map's scale): its sides and ends, read off the part.
local divider: BasePart
for _, part in walls:GetChildren() do
	if part.Name == "Divider" and part.Position.X > 0 and part.Position.Z < -50 then
		divider = part
	end
end
check(divider, "the divider segment is there")
local WEST = divider.Position.X - divider.Size.X / 2
local EAST = divider.Position.X + divider.Size.X / 2
local NORTH = divider.Position.Z + divider.Size.Z / 2 -- its end toward the middle
local MID = divider.Position.Z
local TOP = divider.Position.Y + divider.Size.Y / 2
local Y = 3 -- an avatar's middle, standing

local function wall(name: string, size: Vector3, at: Vector3, props: { [string]: any }?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = CFrame.new(at)
	for key, value in props or {} do
		(part :: any)[key] = value
	end
	part.Parent = walls
	return part
end

local function rejects(reason: string): number
	local snapshot = Telemetry.snapshot()
	return snapshot.rejects.FartDash and snapshot.rejects.FartDash[reason] or 0
end
local function flags(): number
	return Telemetry.snapshot().counters["flags.dashThroughWall"] or 0
end

-- A fresh dash at the path's first point; the avatar is then moved
-- through the rest over the first 0.4 seconds, and the check is let run.
-- Returns whether it was refused for a wall, flagged, and put back.
local function dashAlong(path: { Vector3 }): (boolean, boolean, boolean)
	Dash.refill(ada)
	ada.Character:PivotTo(CFrame.new(path[1]))
	local refused, flagged = rejects("throughWall"), flags()
	check(Dash.dash(ada, Vector3.new(1, 0, 0)), "the dash is accepted")
	for i = 2, #path do
		task.wait(0.4 / (#path - 1))
		ada.Character:PivotTo(CFrame.new(path[i]))
	end
	task.wait(DASH.checkSeconds - 0.4 + 0.1)
	local back = (ada.Character.HumanoidRootPart.Position - path[1]).Magnitude < 0.5
	return rejects("throughWall") > refused, flags() > flagged, back
end
local function fair(path: { Vector3 }, what: string)
	local refused, flagged, back = dashAlong(path)
	check(not refused and not flagged and not back, `{what}: not a wall, left where it is`)
end
local function caught(path: { Vector3 }, what: string)
	local refused, flagged, back = dashAlong(path)
	check(refused and flagged and back, `{what}: through a wall, put back and flagged`)
end
-- The straight line the old check drew, end to end.
local function straightLineHits(path: { Vector3 }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { walls }
	return workspace:Raycast(path[1], path[#path] - path[1], params) ~= nil
end

-- Round the divider's end: from the gap west of it, across, and back
-- behind its end on the east side.
local round = {
	Vector3.new(WEST - 3, Y, NORTH + 6),
	Vector3.new(WEST + 3, Y, NORTH + 6),
	Vector3.new(EAST + 3, Y, NORTH + 6),
	Vector3.new(EAST + 4, Y, NORTH + 2),
	Vector3.new(EAST + 4, Y, NORTH - 3),
}
check(Dash.throughWall(round[1], round[#round]) == divider, "a straight line between the ends cuts the divider's corner")
fair(round, "round the divider's end, seen all the way")
fair({ round[1], round[#round] }, "round the divider's end in one jump (lag)")

-- Along the divider's west side, round a pillar sticking out of it.
wall("Pillar", Vector3.new(3, TOP, 4), Vector3.new(WEST - 1.5, TOP / 2, MID))
local along = {
	Vector3.new(WEST - 1, Y, MID - 14),
	Vector3.new(WEST - 1, Y, MID - 6),
	Vector3.new(WEST - 4.5, Y, MID - 3),
	Vector3.new(WEST - 4.5, Y, MID + 3),
	Vector3.new(WEST - 1, Y, MID + 6),
	Vector3.new(WEST - 1, Y, MID + 12),
}
check(straightLineHits(along), "a straight line along the wall runs through the pillar")
fair(along, "along a wall, round a pillar")
fair({ along[1], along[#along] }, "along a wall, round a pillar, in one jump")

-- Off the top of the divider, down to the ground east of it.
local ledge = {
	Vector3.new(divider.Position.X, TOP + 3, MID + 20),
	Vector3.new(EAST + 1, TOP + 2, MID + 20),
	Vector3.new(EAST + 5, TOP - 12, MID + 20),
	Vector3.new(EAST + 7, Y, MID + 20),
}
check(straightLineHits(ledge), "a straight line off the ledge runs through the divider's top")
fair(ledge, "off the top of a wall")

-- Up onto a block a wall part high, as at the top of a slope.
wall("Platform", Vector3.new(10, 10, 10), Vector3.new(150, 5, -100))
local climb = {
	Vector3.new(138, Y, -100),
	Vector3.new(142, Y, -100),
	Vector3.new(146, 13, -100),
	Vector3.new(150, 13, -100),
}
check(straightLineHits(climb), "a straight line up onto it runs through the block")
fair(climb, "up onto something")

-- Over a wall low enough to jump; through one nobody bumps into.
wall("LowWall", Vector3.new(2, 5, 40), Vector3.new(200, 2.5, 60))
local hop = { Vector3.new(194, Y, 60), Vector3.new(198, 7, 60), Vector3.new(202, 9, 60), Vector3.new(206, Y, 60) }
check(straightLineHits(hop), "a straight line runs through the low wall")
fair(hop, "jumping a low wall")
fair({ hop[1], hop[#hop] }, "jumping a low wall, in one jump")
wall("Ghost", Vector3.new(2, 30, 40), Vector3.new(200, 15, -150), { CanCollide = false })
local ghost = { Vector3.new(194, Y, -150), Vector3.new(206, Y, -150) }
check(straightLineHits(ghost), "a straight line runs through the ghost part")
fair(ghost, "through a part with CanCollide off")

-- Lag: the allowance, and a corner that only fits with it.
local pingOf = Dash.pingOf
local base = DASH.maxTravelStuds + GameConfig.WALK_SPEED * DASH.checkSeconds
Dash.pingOf = function()
	return nil
end
check(math.abs(Dash.allowance(ada) - base) < 1e-6, "no ping known: the dash and walking")
Dash.pingOf = function()
	return 0.25
end
check(math.abs(Dash.allowance(ada) - (base + GameConfig.WALK_SPEED * 0.25)) < 1e-6, "a quarter-second ping: walking that much longer")
Dash.pingOf = function()
	return 2
end
check(math.abs(Dash.allowance(ada) - (base + GameConfig.WALK_SPEED * 0.5)) < 1e-6, "at most half a second of it")
-- Round the corner and well on: about 40 studs the way round, under 38 in
-- a straight line.
local far = { Vector3.new(WEST - 3, Y, NORTH + 6), Vector3.new(EAST + 4, Y, NORTH - 28) }
check(Dash.throughWall(far[1], far[2]) == divider, "the straight line cuts the corner")
Dash.pingOf = function()
	return 0
end
caught(far, "round a corner further than the dash and walking allow, no lag")
Dash.pingOf = function()
	return 0.25
end
fair(far, "the same with a quarter-second ping")
Dash.pingOf = pingOf

-- Still caught, where going round either end is far longer than a dash
-- (near an end, going round it is fair: 11 studs from the south end it's
-- about 34 studs the way round).
local across = MID + 8
check(math.min(across - (MID - divider.Size.Z / 2), NORTH - across) > 20, "the crossing is over 20 studs from both ends")
caught({ Vector3.new(WEST - 4, Y, across), Vector3.new(EAST + 4, Y, across) }, "through the divider's middle in one jump")
fair({ Vector3.new(WEST - 4, Y, MID - 20), Vector3.new(EAST + 4, Y, MID - 20) }, "the same 11 studs from its end (going round fits)")
caught({
	Vector3.new(WEST - 4, Y, across),
	Vector3.new(WEST + 1, Y, across),
	Vector3.new(EAST - 1, Y, across),
	Vector3.new(EAST + 4, Y, across),
}, "walked through the divider")
local latest = Moderation.flagsOf(ada)
latest = latest[#latest]
check(latest and latest.reason == "dashThroughWall" and string.find(latest.detail or "", "Divider", 1, true), "the flag names the wall")
wall("TallWall", Vector3.new(2, 20, 80), Vector3.new(220, 10, 100))
caught({ Vector3.new(214, Y, 100), Vector3.new(218, 9, 100), Vector3.new(222, 9, 100), Vector3.new(226, Y, 100) }, "jumping a wall too high to jump")
caught({ Vector3.new(214, Y, 100), Vector3.new(218, 25, 100), Vector3.new(222, 25, 100), Vector3.new(226, Y, 100) }, "flying over it")

return { status = "PASS", checks = checks }
