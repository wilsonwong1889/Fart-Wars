-- The compass strip, markers over far teammates, and pings (Compass,
-- CompassController, PingService), on the real server with one client:
--   * the arithmetic: bearings (north is -Z, east +X), a camera's heading
--     (even looking straight down), wrapping, the eight letters, where a
--     bearing sits on the strip, names that would overlap, the projection
--     onto the screen, the arrow's spot near the edge (behind you at the
--     bottom), and where a ping aimed at nothing lands on the ground
--   * pings on the server: the pinger's team hears it (the pinger too),
--     the other team and the home screen never do; one every
--     cooldown - slack seconds per player; junk, spots outside the map and
--     pings from off a team are refused, logged, and never use up the
--     limit or break anything
--   * the strip: the letters follow the camera; the lanes and the plaza
--     are named from the map's gate signs, at the middle of their gates,
--     on the side they're on; a name leaves while you're at it; of two that
--     overlap the nearer shows
--   * markers: only over teammates, only past where the symbol over their
--     heads stops; the team's symbol, or ◆ with team symbols off; in a
--     fight (fired or gassed lately) or blowing up they say so, and off the
--     screen they get an arrow toward them (behind you: at the bottom), at
--     most three, blowing up first, then the nearest
--   * the client's pings: Z and the middle mouse button send the spot
--     under the crosshair, not while typing, in a menu or faster than the
--     cooldown; a teammate's ping shows its pin, name and distance, plays
--     its sound, sits on the strip (at the strip's end when it's behind
--     you), moves when they ping again and goes after its seconds; the
--     client ignores junk and other teams' pings
--   * Reduce motion: no pulse, pop or fade; HUD size scales the strip and
--     the markers; nothing shows off the field
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

local client = game.StarterPlayer.StarterPlayerScripts.Client
local Compass = require(client.Compass)
local CompassConfig = require(ReplicatedStorage.Shared.Config.CompassConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local TeamConfig = require(ReplicatedStorage.Shared.Config.TeamConfig)
local STRIP, MARKERS, PING, WORDS = CompassConfig.strip, CompassConfig.markers, CompassConfig.ping, CompassConfig.words

-- Bearings and headings.
local NORTH, EAST, SOUTH, WEST = Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0)
check(near(Compass.bearingOf(NORTH) :: number, 0) and near(Compass.bearingOf(EAST) :: number, 90), "north is -Z, east is +X")
check(near(Compass.bearingOf(SOUTH) :: number, 180) and near(Compass.bearingOf(WEST) :: number, 270), "south +Z, west -X")
check(near(Compass.bearingOf(Vector3.new(3, 7, -3)) :: number, 45) and near(Compass.bearingOf(Vector3.new(-1, 0, -1)) :: number, 315), "height doesn't count")
check(Compass.bearingOf(Vector3.new(0, 5, 0)) == nil, "straight up has no bearing")
local origin = Vector3.new(0, 10, 0)
for _, case in { { NORTH, 0 }, { EAST, 90 }, { SOUTH, 180 }, { WEST, 270 }, { Vector3.new(1, -1.7, 0), 90 }, { Vector3.new(-1, 0.4, 1), 225 } } do
	local heading = Compass.heading(CFrame.lookAt(origin, origin + case[1]))
	check(near(heading, case[2], 1e-4), `a camera looking along {case[1]} faces {case[2]} (got {heading})`)
end
local down = Compass.heading(CFrame.lookAt(origin, origin - Vector3.yAxis))
check(down == down and down >= 0 and down < 360, "looking straight down still has a heading")
check(near(Compass.relative(10, 350), 20) and near(Compass.relative(350, 10), -20), "bearings wrap across north")
check(near(Compass.relative(180, 0), 180) and near(Compass.relative(0, 180), 180) and near(Compass.relative(271, 90), -179), "right behind is 180; just past it, the left")
for bearing, letter in { [0] = "N", [22] = "N", [23] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW", [338] = "N", [359.9] = "N" } do
	check(Compass.letter(bearing) == letter, `{bearing} is {letter}`)
end

-- The strip: 420 pixels for 150 degrees, the heading in the middle.
local W, SPAN = 420, 150
local x, on = Compass.stripX(0, 0, W, SPAN)
check(near(x, 210) and on, "facing it: the middle")
x, on = Compass.stripX(75, 0, W, SPAN)
check(near(x, 420) and on, "75 degrees right: the right end")
x, on = Compass.stripX(285, 0, W, SPAN)
check(near(x, 0) and on, "75 degrees left: the left end")
check(not select(2, Compass.stripX(76, 0, W, SPAN)) and not select(2, Compass.stripX(180, 0, W, SPAN)), "further round: off the strip")
x = Compass.stripX(350, 0, W, SPAN)
check(near(x, 182), "10 degrees left, 28 pixels")
x, on = Compass.stripX(5, 355, W, SPAN)
check(near(x, 238) and on, "across north")
local shown = Compass.layout({ { x = 100, width = 80 }, { x = 150, width = 80 } }, W, 8)
check(shown[1] and not shown[2], "of two names that overlap, the first (nearer) shows")
shown = Compass.layout({ { x = 150, width = 80 }, { x = 100, width = 80 } }, W, 8)
check(shown[1] and not shown[2], "whichever side it's on")
shown = Compass.layout({ { x = 100, width = 80 }, { x = 200, width = 80 } }, W, 8)
check(shown[1] and shown[2], "names with room between them both show")
shown = Compass.layout({ { x = 100, width = 80 }, { x = 187, width = 80 } }, W, 8)
check(shown[1] and not shown[2], "but not closer than the gap")
check(not Compass.layout({ { x = -5, width = 40 } }, W, 8)[1], "off the strip: hidden")

-- The screen: 1280 x 720 at 70 degrees, a camera 10 up looking north.
local VIEWPORT = Vector2.new(1280, 720)
local view = CFrame.lookAt(origin, origin + NORTH)
local tanY = math.tan(math.rad(35))
local tanX = tanY * 1280 / 720
local spot, depth = Compass.project(view, 70, VIEWPORT, Vector3.new(0, 10, -100))
check(near(spot.X, 640, 1e-3) and near(spot.Y, 360, 1e-3) and near(depth, 100, 1e-6), "straight ahead: the middle of the screen")
spot = Compass.project(view, 70, VIEWPORT, Vector3.new(100 * tanX, 10, -100))
check(near(spot.X, 1280, 1e-3) and near(spot.Y, 360, 1e-3), "at the edge of the view: the screen's edge")
spot = Compass.project(view, 70, VIEWPORT, Vector3.new(0, 10 + 100 * tanY, -100))
check(near(spot.Y, 0, 1e-3), "at the top of the view: the screen's top")
spot = Compass.project(view, 70, VIEWPORT, Vector3.new(-50 * tanX, 10 - 50 * tanY, -100))
check(near(spot.X, 320, 1e-3) and near(spot.Y, 540, 1e-3), "half way to the bottom left corner")
spot, depth = Compass.project(view, 70, VIEWPORT, Vector3.new(0, 10, 100))
check(depth < 0, "behind the camera: behind")
check(Compass.onScreen(Vector2.new(640, 360), 100, VIEWPORT, 24), "the middle is on the screen")
check(not Compass.onScreen(Vector2.new(640, 360), -1, VIEWPORT, 24), "but not from behind")
check(not Compass.onScreen(Vector2.new(10, 360), 100, VIEWPORT, 24) and not Compass.onScreen(Vector2.new(1270, 360), 100, VIEWPORT, 24), "nor at the very edge")

-- Arrows: on the ellipse 70 in from the sides and 150 from top and bottom.
local function onEllipse(at: Vector2): boolean
	return near(((at.X - 640) / 570) ^ 2 + ((at.Y - 360) / 210) ^ 2, 1, 1e-6)
end
local edge, rotation = Compass.edge(view, 70, VIEWPORT, Vector3.new(0, 10, 100), 70, 150)
check(near(edge.X, 640, 1e-3) and near(edge.Y, 570, 1e-3) and near(math.abs(rotation), 180, 1e-3), "right behind: the bottom, pointing down")
edge, rotation = Compass.edge(view, 70, VIEWPORT, Vector3.new(-100, 10, 0), 70, 150)
check(near(edge.X, 70, 1e-3) and near(edge.Y, 360, 1e-3) and near(rotation, -90, 1e-3), "right beside you on the left: the left, pointing left")
edge, rotation = Compass.edge(view, 70, VIEWPORT, Vector3.new(-500, 10, -100), 70, 150)
check(near(edge.X, 70, 1e-3) and near(edge.Y, 360, 1e-3) and near(rotation, -90, 1e-3), "ahead but off to the left: the left")
edge, rotation = Compass.edge(view, 70, VIEWPORT, Vector3.new(0, -500, -100), 70, 150)
check(near(edge.Y, 570, 1e-3) and near(math.abs(rotation), 180, 1e-3), "ahead but far below the view: the bottom")
edge, rotation = Compass.edge(view, 70, VIEWPORT, Vector3.new(400, 300, -100), 70, 150)
check(onEllipse(edge) and rotation > 0 and rotation < 90 and edge.X > 640 and edge.Y < 360, "up and to the right: on the ellipse, up and right")
edge = Compass.edge(view, 70, VIEWPORT, Vector3.new(-80, 10, 60), 70, 150)
check(onEllipse(edge) and edge.X < 640 and edge.Y > 360, "behind on the left: down on the left")

-- A ping aimed at nothing nearer lands on the ground, if it reaches it.
local ground = Compass.groundSpot(origin, Vector3.new(0, -1, -1), 700)
check(ground and (ground - Vector3.new(0, 0, -10)).Magnitude < 1e-6, "aimed down: where the ray meets the ground")
check(Compass.groundSpot(origin, Vector3.new(0, 0.5, -1), 700) == nil and Compass.groundSpot(origin, NORTH, 700) == nil, "aimed up or level: nowhere")
check(Compass.groundSpot(origin, Vector3.new(0, -0.01, -1), 700) == nil, "too far: nowhere")

-- The server and one client.
Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
require(server.Services.BotDirector).testSetEnabled(false)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Team = require(server.Services.TeamService)
local AFK = require(server.Services.AFKService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes
local S = MapConfig.BrainrotBattlefield.scale

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(client.ClientBootstrap)
local CompassUI = require(client.Controllers.CompassController)
local InputController = require(client.Controllers.InputController)
local Settings = require(client.Settings)
local UI = require(client.UI)
local Audio = require(client.Audio)
local p = CompassUI.parts
local camera = workspace.CurrentCamera

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.05)
	return player
end
local ada, bo, cy = join("Ada", 2), join("Bo", 3), join("Cy", 4)
local dee, eve, fay = join("Dee", 5), join("Eve", 6), join("Fay", 7)

CompassUI.render()
check(p.screen and not p.screen.Enabled, "on the home screen: no compass")

for _, player in { me, ada, bo, dee, eve, fay } do
	Lifecycle.requestPlay(player, nil)
	task.wait(0.2)
end
local mine = Team.teamOf(me) :: string
local theirs = if mine == "Stinkers" then "Sharters" else "Stinkers"
for _, player in { ada, dee, eve, fay } do
	Team.testSetTeam(player, mine)
end
Team.testSetTeam(bo, theirs)
task.wait(0.5)
check(Team.teamOf(ada) == mine and Team.teamOf(dee) == mine and Team.teamOf(bo) == theirs, "Ada, Dee, Eve and Fay with me; Bo against us")
check(cy:GetAttribute("State") ~= "ACTIVE" and Team.teamOf(cy) == nil, "Cy watches from the home screen")
check(me.Character and ada.Character and bo.Character, "everyone in the match has an avatar")
-- Nobody here falls asleep while the clock runs on.
task.spawn(function()
	while true do
		for _, player in Players:GetPlayers() do
			AFK.markActive(player)
		end
		task.wait(5)
	end
end)

-- Pings on the server.
local heard: { [Player]: { any } } = {}
Remotes.Ping.FiredToClient:Connect(function(player, payload)
	heard[player] = heard[player] or {}
	table.insert(heard[player], payload)
end)
local function count(player: Player): number
	return if heard[player] then #heard[player] else 0
end
local function rejects(reason: string): number
	local byReason = Telemetry.snapshot().rejects.Ping
	return byReason and byReason[reason] or 0
end
local function ping(player: Player, at: any)
	Remotes.Ping.OnServerEvent:Fire(player, at)
end
local plaza = Vector3.new(0, 0, -30 * S)
local sentAt = workspace:GetServerTimeNow()
ping(me, plaza)
check(count(me) == 1 and count(ada) == 1 and count(dee) == 1, "my ping reaches my team, and me")
check(count(bo) == 0 and count(cy) == 0, "never the other team or the home screen")
local payload = heard[ada][1]
check(payload.from == me.UserId and payload.position == plaza, "who and where")
check(near(payload.endsAt, sentAt + PING.seconds, 0.05), `for {PING.seconds} seconds`)
ping(me, plaza)
check(count(ada) == 1 and rejects("rateLimited") == 1, "again at once: refused")
task.wait(PING.cooldownSeconds - PING.slackSeconds - 0.15)
ping(me, plaza)
check(count(ada) == 1 and rejects("rateLimited") == 2, "still too soon")
task.wait(0.2)
ping(me, plaza + Vector3.new(10, 0, 0))
check(count(ada) == 2 and heard[ada][2].position == plaza + Vector3.new(10, 0, 0), "after cooldown - slack seconds: through")

local junk = {
	{ nil, "badPayload" },
	{ "north", "badPayload" },
	{ 7, "badPayload" },
	{ true, "badPayload" },
	{ { 1, 2, 3 }, "badPayload" },
	{ { X = 1, Y = 2, Z = 3 }, "badPayload" },
	{ Vector2.new(1, 2), "badPayload" },
	{ CFrame.new(0, 2, 0), "badPayload" },
	{ Vector3.new(0 / 0, 0, 0), "badPayload" },
	{ Vector3.new(math.huge, 0, 0), "badPayload" },
	{ Vector3.new(0, -math.huge, 0), "badPayload" },
	{ Vector3.new(0, 0, 9999), "outOfBounds" },
	{ Vector3.new(0, 500, 0), "outOfBounds" },
	{ Vector3.new(300, 0, 0), "outOfBounds" },
	{ Vector3.new(0, -20, 0), "outOfBounds" },
}
local before = { badPayload = rejects("badPayload"), outOfBounds = rejects("outOfBounds") }
for _, case in junk do
	ping(dee, case[1])
end
check(rejects("badPayload") - before.badPayload == 11 and rejects("outOfBounds") - before.outOfBounds == 4, "junk and spots off the map are refused")
check(count(me) == 2 and count(ada) == 2 and count(bo) == 0, "and nobody hears a thing")
ping(dee, Vector3.new(240, 0, 240))
check(count(ada) == 3 and heard[ada][3].from == dee.UserId, "none of it used up Dee's limit: the map's corner goes through")
ping(dee, plaza)
check(count(ada) == 3, "(and then his limit holds)")
ping(cy, plaza)
check(rejects("notActive") == 1 and count(cy) == 0 and count(me) == 3, "from the home screen: refused")
ping(bo, plaza)
check(count(bo) == 1 and count(me) == 3 and count(ada) == 3, "Bo's ping stays on his own team")
check(next(Telemetry.snapshot().errors) == nil, "nothing broke")

-- The strip.
local root = me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
local function stand(at: Vector3, toward: Vector3)
	me.Character:PivotTo(CFrame.new(at))
	local eye = at + Vector3.new(0, 4, 0)
	camera.CFrame = CFrame.lookAt(eye, eye + toward)
	CompassUI.render()
end
local function letterAt(name: string): number?
	local label = p.strip:FindFirstChild(name) :: TextLabel
	return if label.Visible then label.Position.X.Offset else nil
end
stand(Vector3.new(0, 3, -200), NORTH)
check(p.screen.Enabled, "in the match: the compass")
check(near(letterAt("N") :: number, STRIP.width / 2), "facing north: N in the middle")
local k = STRIP.width / STRIP.spanDegrees
check(near(letterAt("NE") :: number, STRIP.width / 2 + 45 * k) and near(letterAt("NW") :: number, STRIP.width / 2 - 45 * k), "NE to the right, NW to the left")
check(letterAt("S") == nil and letterAt("E") == nil and letterAt("W") == nil, "and nothing from behind or the sides")
stand(Vector3.new(0, 3, -200), EAST)
check(near(letterAt("E") :: number, STRIP.width / 2) and letterAt("N") == nil, "facing east: E in the middle")
stand(Vector3.new(0, 3, -200), Vector3.new(-1, 0, 1))
check(near(letterAt("SW") :: number, STRIP.width / 2) and letterAt("S") and letterAt("W"), "facing south-west: SW, between S and W")

-- The lanes and the plaza, from the gates' signs.
local names = {}
for _, landmark in CompassUI.landmarks do
	names[landmark.name] = landmark
end
check(#CompassUI.landmarks == 3 and names["BEAN ALLEY"] and names["PORCELAIN PLAZA"] and names["GAS GUTTER"], "three names, from the gates")
check(math.abs(names["BEAN ALLEY"].position.Z) < 1 and math.abs(names["PORCELAIN PLAZA"].position.Z) < 1, "each at the middle of its two gates")
check(names["BEAN ALLEY"].position.X < -100 and math.abs(names["PORCELAIN PLAZA"].position.X) < 1 and names["GAS GUTTER"].position.X > 100, "the alley west, the plaza in the middle, the gutter east")
local theme = MapConfig.BrainrotBattlefield.theme
check(names["BEAN ALLEY"].color == theme.beanLabel and names["GAS GUTTER"].color == theme.barrelBand, "in their signs' colours")
local function nameAt(name: string): number?
	for i, landmark in CompassUI.landmarks do
		if landmark.name == name then
			local label = p.names[i]
			return if label.Visible then label.Position.X.Offset else nil
		end
	end
	return nil
end
-- From the north, facing south toward the middle: west is on your right.
stand(Vector3.new(0, 3, -200), SOUTH)
local alley, plazaX, gutter = nameAt("BEAN ALLEY"), nameAt("PORCELAIN PLAZA"), nameAt("GAS GUTTER")
check(plazaX and near(plazaX, STRIP.width / 2, 1), "the plaza straight ahead")
check(alley and gutter and gutter < (plazaX :: number) and (plazaX :: number) < alley, "the gutter on the left, the alley on the right")
-- At the plaza, facing west.
stand(Vector3.new(10, 3, 10), WEST)
check(nameAt("PORCELAIN PLAZA") == nil and nameAt("BEAN ALLEY"), "at the plaza its name leaves the strip; the alley's ahead")
-- In the alley, facing east: the plaza and the gutter are the same way.
stand(Vector3.new(-200, 3, 0), EAST)
check(nameAt("PORCELAIN PLAZA") and nameAt("GAS GUTTER") == nil and nameAt("BEAN ALLEY") == nil, "of the two that overlap, the nearer; and I'm in the alley")

-- Markers over far teammates.
local function place(player: Player, at: Vector3)
	player.Character:PivotTo(CFrame.new(at))
end
local function hasMarker(player: Player): boolean
	return table.find(CompassUI.shown.mates, player.Character) ~= nil
end
local function markerText(player: Player): string?
	local index = table.find(CompassUI.shown.mates, player.Character)
	return if index then p.mates[index].Text.Text else nil
end
local symbol = TeamConfig.teams[mine].symbol
local function away()
	-- Everyone else well off to the side, out of the way.
	for i, player in { dee, eve, fay } do
		place(player, Vector3.new(200, 3, -230 + i * 4))
	end
end
away()
place(ada, Vector3.new(0, 3, 20))
place(bo, Vector3.new(20, 3, 20))
stand(Vector3.new(0, 3, -200), SOUTH)
check(hasMarker(ada) and markerText(ada) == symbol, `Ada, 220 ahead: a marker with our symbol ({markerText(ada)})`)
check(not hasMarker(bo), "Bo's on the other team: no marker")
place(ada, Vector3.new(0, 3, -100))
CompassUI.render()
check(not hasMarker(ada), "100 away: the symbol over her head does it")
place(ada, Vector3.new(0, 3, -200 + MARKERS.minDistance + 10))
CompassUI.render()
check(hasMarker(ada), `just past {MARKERS.minDistance}: the marker`)
Settings.teamSymbols = false
CompassUI.render()
check(markerText(ada) == WORDS.pip, "team symbols off: a plain pip")
Settings.teamSymbols = true
CompassUI.render()
local marker = p.mates[table.find(CompassUI.shown.mates, ada.Character) :: number]
check(marker.Text.TextColor3 == TeamConfig.teams[mine].color, "in our colour too")

-- In a fight, or blowing up.
place(ada, Vector3.new(0, 3, 20))
Remotes.Shots:FireAllClients({ ada.UserId }, { Vector3.new(0, 5, 20) }, { Vector3.new(0, 5, 40) })
CompassUI.render()
check(CompassUI.troubleOf(ada.Character) == "fight" and markerText(ada) == `{symbol} {WORDS.fight}`, "she fired: in a fight")
task.wait(MARKERS.fightSeconds + 0.1)
CompassUI.render()
check(CompassUI.troubleOf(ada.Character) == nil and markerText(ada) == symbol, "a few seconds later: not any more")
ada.Character:SetAttribute("Gas", 40)
CompassUI.render()
check(markerText(ada) == `{symbol} {WORDS.fight}`, "gassed: in a fight")
task.wait(MARKERS.fightSeconds + 0.1)
ada.Character:SetAttribute("Gas", 20)
CompassUI.render()
check(markerText(ada) == symbol, "her gas going down isn't a fight")
ada.Character:SetAttribute("ExplodesAt", workspace:GetServerTimeNow() + 1)
CompassUI.render()
check(markerText(ada) == `{symbol} {WORDS.boom}`, "counting down: blowing up")
check(#CompassUI.shown.arrows == 0, "she's on the screen: no arrow")
Remotes.Shots:FireAllClients({ bo.UserId }, { Vector3.new(20, 5, 20) }, { Vector3.new(0, 5, 0) })
CompassUI.render()
check(not hasMarker(bo) and #CompassUI.shown.arrows == 0, "Bo fighting means no arrow for him")

-- Off the screen.
local function arrowOf(player: Player): number?
	for i, entry in CompassUI.shown.arrows do
		if entry.character == player.Character then
			return i
		end
	end
	return nil
end
ada.Character:SetAttribute("ExplodesAt", nil)
place(ada, Vector3.new(0, 3, -230))
CompassUI.render()
check(#CompassUI.shown.arrows == 0, "behind me and fine: no arrow")
Remotes.Shots:FireAllClients({ ada.UserId }, { Vector3.new(0, 5, -230) }, { Vector3.new(0, 5, -260) })
CompassUI.render()
local index = arrowOf(ada)
local arrow = index and p.arrows[index]
check(arrow and arrow.Visible and CompassUI.shown.arrows[index].trouble == "fight", "behind me in a fight: an arrow")
check(arrow.Position.Y.Offset > VIEWPORT.Y / 2 + 100 and near(arrow.Position.X.Offset, VIEWPORT.X / 2, 1), "at the bottom of the screen")
check(near(math.abs(arrow.Pointer.Rotation), 180, 1) and arrow.Text.Text == `{symbol} {WORDS.fight}`, "pointing down, with our symbol")
-- Facing south, east is on your left.
place(ada, Vector3.new(200, 3, -190))
Remotes.Shots:FireAllClients({ ada.UserId }, { Vector3.new(200, 5, -190) }, { Vector3.new(200, 5, -160) })
CompassUI.render()
index = arrowOf(ada)
arrow = index and p.arrows[index]
check(arrow and arrow.Position.X.Offset < 200 and near(arrow.Pointer.Rotation, -90, 5), "off to the left: at the left, pointing left")
-- Four in trouble behind me: three arrows, blowing up first, then the nearest.
local fight = function(player: Player)
	Remotes.Shots:FireAllClients({ player.UserId }, { Vector3.new(0, 5, -230) }, { Vector3.new(0, 5, -240) })
end
place(ada, Vector3.new(-10, 3, -215))
place(dee, Vector3.new(10, 3, -220))
place(fay, Vector3.new(0, 3, -225))
place(eve, Vector3.new(0, 3, -235))
for _, player in { ada, dee, fay } do
	fight(player)
end
eve.Character:SetAttribute("ExplodesAt", workspace:GetServerTimeNow() + 1)
CompassUI.render()
local arrows = CompassUI.shown.arrows
check(#arrows == MARKERS.maxArrows and #p.arrows >= 3, `at most {MARKERS.maxArrows} arrows`)
check(arrows[1].character == eve.Character and arrows[1].trouble == "boom", "Eve's blowing up: hers first, though she's furthest")
check(arrows[2].character == ada.Character and arrows[3].character == dee.Character, "then the nearest")
check(p.arrows[1].Text.Text == `{symbol} {WORDS.boom}`, "with the boom on it")
eve.Character:SetAttribute("ExplodesAt", nil)
away()

-- Pings on the client.
local sounds = {}
local play = Audio.play
Audio.play = function(name, ...)
	table.insert(sounds, name)
	return play(name, ...)
end
local function pinOf(from: number): Frame?
	local i = table.find(CompassUI.shown.pins, from)
	return if i then p.pins[i] else nil
end
table.clear(CompassUI.pings)
stand(Vector3.new(0, 3, -200), SOUTH)
place(ada, Vector3.new(30, 3, -150))
task.wait(PING.cooldownSeconds)
local ahead = Vector3.new(0, 0, -100)
ping(ada, ahead)
CompassUI.render()
check(CompassUI.pings[ada.UserId] and table.find(sounds, "ping"), "Ada's ping arrives, with its sound")
local pin = pinOf(ada.UserId)
check(pin and pin.Visible, "its pin on the screen")
local distance = math.floor((ahead - root.Position).Magnitude + 0.5)
check(pin.Caption.Text == string.format(WORDS.caption, "ADA", distance), `who and how far: {pin and pin.Caption.Text}`)
local pip = p.pips[1]
check(pip.Visible and pip.Text == WORDS.pin and near(pip.Position.X.Offset, STRIP.width / 2, 1), "and on the strip, straight ahead")
task.wait(PING.cooldownSeconds)
local behind = Vector3.new(-40, 0, -235)
ping(ada, behind)
CompassUI.render()
local count2 = 0
for _ in CompassUI.pings do
	count2 += 1
end
check(count2 == 1 and CompassUI.pings[ada.UserId].position == behind, "her new ping moves her old one")
check(pinOf(ada.UserId) == nil, "behind me: no pin on the screen")
check(p.pips[1].Visible and (p.pips[1].Text == WORDS.pingLeft or p.pips[1].Text == WORDS.pingRight), "but the strip's end says which way to turn")
-- Facing south, the west behind you is on your right.
check(p.pips[1].Text == WORDS.pingRight and p.pips[1].Position.X.Offset > STRIP.width - 20, "here: turn right")
task.wait(PING.seconds + 0.1)
CompassUI.render()
check(CompassUI.pings[ada.UserId] == nil and not p.pips[1].Visible and not p.pins[1].Visible, `after {PING.seconds} seconds it's gone`)

-- What the client takes.
local now = workspace:GetServerTimeNow()
check(not CompassUI.receive({ from = bo.UserId, position = ahead, endsAt = now + 5 }), "never another team's ping")
check(not CompassUI.receive("ping") and not CompassUI.receive({ from = "Ada", position = ahead }) and not CompassUI.receive({ from = ada.UserId, position = "here" }), "nor junk")
check(not CompassUI.receive({ from = ada.UserId, position = ahead, endsAt = now - 1 }), "nor one that's over")
check(CompassUI.receive({ from = ada.UserId, position = ahead, endsAt = now + 999 }) and CompassUI.pings[ada.UserId].endsAt <= now + PING.seconds + 1e-6, "and never for longer than a ping lasts")
check(CompassUI.receive({ from = ada.UserId, position = ahead, endsAt = 0 / 0 }) and CompassUI.pings[ada.UserId].endsAt <= now + PING.seconds + 1e-6, "even one that says NaN")
table.clear(CompassUI.pings)

-- Z and the middle mouse button.
local function key(code: Enum.KeyCode, typing: boolean?)
	UserInputService.InputBegan:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, typing == true)
	UserInputService.InputEnded:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, typing == true)
end
local aimed: Vector3? = Vector3.new(5, 0, -120)
CompassUI.aimSpot = function()
	return aimed
end
local heardBefore = count(ada)
key(Enum.KeyCode.Z)
check(count(ada) == heardBefore + 1 and heard[ada][count(ada)].position == aimed and heard[ada][count(ada)].from == me.UserId, "Z: my ping, where the crosshair is")
CompassUI.render()
local mine2 = pinOf(me.UserId)
check(mine2 and string.sub(mine2.Caption.Text, 1, #WORDS.you) == WORDS.you, "my own says YOU")
local limited = rejects("rateLimited")
key(Enum.KeyCode.Z)
check(count(ada) == heardBefore + 1 and rejects("rateLimited") == limited, "again at once: not even sent")
task.wait(PING.cooldownSeconds)
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton3 }, false)
check(count(ada) == heardBefore + 2, "the middle mouse button pings too")
task.wait(PING.cooldownSeconds)
key(Enum.KeyCode.Z, true)
check(count(ada) == heardBefore + 2, "not while typing")
InputController.menuOpen = true
key(Enum.KeyCode.Z)
InputController.menuOpen = false
check(count(ada) == heardBefore + 2, "not in a menu")
aimed = nil
key(Enum.KeyCode.Z)
check(count(ada) == heardBefore + 2, "nor at the sky")
aimed = Vector3.new(0, 0, -150)
key(Enum.KeyCode.Z)
check(count(ada) == heardBefore + 3, "and then, yes")

-- Reduce motion, and the HUD size.
local ownPin = function()
	CompassUI.render()
	return pinOf(me.UserId) :: any
end
CompassUI.pings[me.UserId].arrivedAt = os.clock()
check(ownPin().Icon.Pop.Scale > 1.1, "a new ping pops in")
Settings.reduceMotion = true
check(ownPin().Icon.Pop.Scale == 1, "with Reduce motion it just appears")
Settings.reduceMotion = false
CompassUI.pings[me.UserId].endsAt = workspace:GetServerTimeNow() + PING.fadeSeconds / 2
check(ownPin().Caption.TextTransparency > 0.3, "and fades at the end")
Settings.reduceMotion = true
check(ownPin().Caption.TextTransparency == 0, "with Reduce motion, no fade")
place(ada, Vector3.new(0, 3, 20))
Remotes.Shots:FireAllClients({ ada.UserId }, { Vector3.new(0, 5, 20) }, { Vector3.new(0, 5, 40) })
local still = true
for _ = 1, 6 do
	task.wait(0.05)
	CompassUI.render()
	local i = table.find(CompassUI.shown.mates, ada.Character)
	still = still and i ~= nil and p.mates[i].Text.Pulse.Scale == 1
end
check(still, "with Reduce motion a fighting teammate's marker doesn't pulse")
Settings.reduceMotion = false
local pulsed = false
for _ = 1, 6 do
	task.wait(0.05)
	CompassUI.render()
	local i = table.find(CompassUI.shown.mates, ada.Character)
	pulsed = pulsed or (i ~= nil and p.mates[i].Text.Pulse.Scale ~= 1)
end
check(pulsed, "without it, it does")
task.wait(0.1)
local scale = p.strip:FindFirstChild("HudScale") :: UIScale
check(scale and scale.Scale == Settings.hudScale, "the strip follows the HUD size")
Settings.hudScale = 1.25
UI.applyScale()
local mateScale = p.mates[1]:FindFirstChild("HudScale") :: UIScale
check(scale.Scale == 1.25 and mateScale and mateScale.Scale == 1.25, "and the markers do too")
Settings.hudScale = 1
UI.applyScale()

-- Off the field.
Remotes.RequestSpectate.OnServerEvent:Fire(me)
task.wait(0.3)
CompassUI.render()
check(me:GetAttribute("State") ~= "ACTIVE" and not p.screen.Enabled, "back on the home screen: no compass")
check(#CompassUI.shown.mates == 0 and #CompassUI.shown.pins == 0, "and no markers")
check(not CompassUI.ping(), "and no pings")
check(next(Telemetry.snapshot().errors) == nil, "and nothing broke")

return { status = "PASS", checks = checks }
