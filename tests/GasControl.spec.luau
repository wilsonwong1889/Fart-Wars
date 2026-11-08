-- Gas Control and mode rotation (masterplan 6.1) on the full-size map, with
-- one client:
--   * the zone fits Porcelain Plaza at 3x: a circle round the throne, 60
--     studs out and 18 up, exactly as wide as its floor ring, clear of the
--     dividers (so of the gaps between the lanes too), the same distance
--     from both spawns; standing and jumping count, up on the bowls or
--     past the ring doesn't; a box zone (a map made in Studio) still works
--   * bots head for open ground all over the zone, never into the throne
--   * a Gas Control round: the mode in the snapshot, on the HUD and in a
--     message as it starts; the ring and the marker over the plaza shown
--   * taking it: a team alone in it captures it in 6 seconds, 4 with two
--     of them, 3 with three or more (bots count, a full team of ten is no
--     quicker); an enemy in it freezes the capture; with nobody in it the
--     capture runs back down; the other team alone in it starts over
--   * holding it: a point a second while the holder has it to itself;
--     contested or empty nothing, but it stays theirs; the holder back in
--     it ends the other team's capture; eliminations don't score, they
--     clear the zone
--   * the HUD's zone line in words and its bar, the ring's and the
--     marker's colours, through each of those
--   * holders earn a little, capped per round
--   * most points wins, and the results say it was Gas Control
--   * rotation: off by default; on, servers under ROTATION_MIN_PLAYERS
--     players stay on the default even when bots fill them to 20; at the
--     minimum the modes take turns, starting with Gas Control after a run
--     of default rounds; under it again, the default
--   * a map without a zone fails validation; /fw mode
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local MapConfig = require(Shared.Config.MapConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local MapBase = require(Shared.Interfaces.MapBase)
local Round = require(server.Services.RoundService)
local Zone = require(server.Services.ZoneService)
local Scores = require(server.Services.MatchScoreService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Team = require(server.Services.TeamService)
local Data = require(server.Services.DataService)
local MapService = require(server.Services.MapService)
local Bots = require(server.Services.BotService)
local Director = require(server.Services.BotDirector)
local Telemetry = require(server.Telemetry)
local TestControls = require(server.TestControls)
local ZONE = GameConfig.ZONE
local STINKERS, SHARTERS = TeamConfig.teams.Stinkers, TeamConfig.teams.Sharters

check(FeatureFlags.MODE_ROTATION == false and GameConfig.DEFAULT_MODE == "TeamElimination", "as shipped: no rotation, Team Elimination")
check(table.find(MapConfig.BrainrotBattlefield.modes, "GasControl") and MapConfig.BrainrotBattlefield.zone, "the map supports Gas Control")
check(TestControls.mode("gascontrol") and not TestControls.mode("nope"), "/fw mode picks the next round's mode")

-- The zone on the full-size map. Spots are the map layout's, built
-- MapConfig's scale bigger.
local S = MapConfig.BrainrotBattlefield.scale
local map = MapService.current() :: Model
local zone, ring = Zone.parts()
check(zone and ring, "the map has the zone and its ring")
zone, ring = zone :: BasePart, ring :: BasePart
local radius = math.min(zone.Size.Y, zone.Size.Z) / 2
local height = zone.Size.X
check(zone:IsA("Part") and (zone :: Part).Shape == Enum.PartType.Cylinder and zone.Size.Y == zone.Size.Z, "a round zone")
check(radius == 20 * S and height == 6 * S, `60 studs out and 18 up at full size ({radius}, {height})`)
check(math.abs(zone.Position.Y - height / 2) < 1e-3 and zone.Position.X == 0 and zone.Position.Z == 0, "standing on the ground in the middle")
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-3
end
check(near(ring.Size.Y, zone.Size.Y) and near(ring.Size.Z, zone.Size.Z) and near(ring.Position.X, zone.Position.X) and near(ring.Position.Z, zone.Position.Z), `the ring is exactly as wide as the zone ({ring.Size})`)
check(ring.Size.X <= 1 and ring.Position.Y < 1, "and lies flat on the floor")
local dividers = 0
for _, wall in map.Walls:GetChildren() do
	if wall.Name == "Divider" then
		dividers += 1
		check(math.abs(wall.Position.X) - wall.Size.X / 2 - radius >= 10, "the zone stops well short of the dividers, and the gaps in them")
	end
end
check(dividers >= 6, "with the dividers there to check")
for _, name in { "ThroneTank", "ThroneBowl" } do
	for _, piece in map.Cover:GetChildren() do
		if piece.Name == name then
			check(Zone.inside(piece.Position * Vector3.new(1, 0, 1) + Vector3.new(0, 3, 0), zone), `the throne ({name}) is in the middle of it`)
		end
	end
end
local function centroid(pads: { BasePart }): Vector3
	local sum = Vector3.zero
	for _, pad in pads do
		sum += pad.Position
	end
	return sum / #pads
end
local home, away = centroid(MapService.spawns("Stinkers")), centroid(MapService.spawns("Sharters"))
check(math.abs((home - zone.Position).Magnitude - (away - zone.Position).Magnitude) < 1e-3, "as far from one spawn as the other")
check((home - zone.Position).Magnitude - radius > 100, "and a long way from both")
local function at(x: number, y: number, z: number): boolean
	return Zone.inside(Vector3.new(x, y, z), zone)
end
check(at(14 * S, 3, 0) and at(14 * S, 10, 0), "standing in it counts, and jumping")
check(not at(0, 21, -10 * S) and not at(14 * S, height + 1, 0), "up on a bowl or over the top doesn't")
check(at(radius - 1, 3, 0) and not at(radius + 1, 3, 0), "the edge is the ring's edge")
check(at(19 * S, 3, 0) and not at(18 * S, 3, 20 * S), "the old box's sides now count and its corners don't")
local box = Instance.new("Part")
box.Size = Vector3.new(10, 4, 10)
box.CFrame = CFrame.new(100, 2, 0)
check(Zone.inside(Vector3.new(104, 1, 4), box) and not Zone.inside(Vector3.new(106, 1, 0), box), "a box zone (made in Studio) still works")

-- Bots: open ground all over the zone, never inside the throne or other
-- cover.
local solid = {}
for _, folderName in { "Cover", "Walls", "Barrels" } do
	for _, item in map[folderName]:GetDescendants() do
		if item:IsA("BasePart") and item.CanCollide then
			table.insert(solid, item)
		end
	end
end
local function bounds(part: BasePart): (Vector3, Vector3)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
	local s = part.Size / 2
	local half = Vector3.new(
		math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z,
		math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z,
		math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z
	)
	return part.Position - half, part.Position + half
end
local rng = Random.new(7)
local sides = { left = 0, right = 0, front = 0, back = 0 }
for _ = 1, 200 do
	local spot = Zone.spot(rng) :: Vector3
	check(spot and Zone.inside(spot + Vector3.new(0, 1, 0), zone), "a bot's spot is in the zone")
	for _, part in solid do
		local lo, hi = bounds(part)
		local clear = spot.X + 2 <= lo.X or spot.X - 2 >= hi.X or spot.Z + 2 <= lo.Z or spot.Z - 2 >= hi.Z or spot.Y + 6 <= lo.Y or spot.Y + 1 >= hi.Y
		check(clear, `a bot's spot {spot} isn't inside {part.Name}`)
	end
	-- Beside the throne's tank, and past it on either team's half.
	sides.left += if spot.X < -8 * S then 1 else 0
	sides.right += if spot.X > 8 * S then 1 else 0
	sides.front += if spot.Z < -4 * S then 1 else 0
	sides.back += if spot.Z > 4 * S then 1 else 0
end
check(sides.left > 30 and sides.right > 30 and sides.front > 30 and sides.back > 30, `spread all round the throne ({sides.left} left, {sides.right} right, {sides.front} on the Stinkers' half, {sides.back} on the Sharters')`)

-- The round.
local messages = {}
ReplicatedStorage.Remotes.UIMessage.FiredToClient:Connect(function(player, payload)
	if player.Name == "Me" then
		table.insert(messages, payload)
	end
end)
local captured = {}
Zone.Captured:Connect(function(team)
	table.insert(captured, team)
end)
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local HUD = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.HUDController)
local hud = HUD.parts
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.05)
	return player
end
local foe = join("Foe", 2)
Lifecycle.requestPlay(me, "Stinkers")
Lifecycle.requestPlay(foe, "Sharters")
task.wait(0.5)
Team.testSetTeam(me, "Stinkers")
Team.testSetTeam(foe, "Sharters")
local snapshot = Round.snapshot()
check(Round.phase() == "ACTIVE" and snapshot.mode == "GasControl" and snapshot.objective == "zone" and snapshot.modeName == "Gas Control", "a Gas Control round")
task.wait(1.2)
local said = false
for _, payload in messages do
	said = said or (payload.kind == "mode" and payload.text == UIConfig.zone.start)
end
check(said, "it says what to do as it starts")
local marker = zone:FindFirstChild("ZoneMarker") :: BillboardGui
check(ring.Transparency < 1 and marker and marker.Enabled and marker.AlwaysOnTop, "the ring shows, and the marker over the plaza, seen from anywhere")
check(marker.StudsOffsetWorldSpace.Y + zone.Position.Y > 45 + 5, "floating clear over the throne")
check(Zone.isActive() and workspace:GetAttribute("ZoneActive") == true and workspace:GetAttribute("ZoneOwner") == nil, "an empty zone, nobody's")
check(Scores.getScores().Stinkers == 0 and Scores.getScores().Sharters == 0, "scores nothing")
HUD.renderZone()
check(hud.zone.Visible and hud.zone.Text == UIConfig.zone.empty and not hud.zoneBar.Visible, "the HUD says what to do")
game:GetService("RunService").Heartbeat:Fire(0.2)
check(hud.phase.Text == "GAS CONTROL", "and which mode it is")

-- Exact seconds: the zone's own ticks, with nothing else running between.
local function hold(seconds: number)
	for _ = 1, math.round(seconds / ZONE.TICK_SECONDS) do
		Zone.tick(ZONE.TICK_SECONDS)
	end
end
local function put(player: Player, x: number, z: number)
	player.Character:PivotTo(CFrame.new(x * S, 3, z * S))
end
local function points(): (number, number)
	local scores = Scores.getScores()
	return scores.Stinkers or 0, scores.Sharters or 0
end
local function line(): string
	HUD.renderZone()
	return hud.zone.Text
end
local function bar(): number?
	HUD.renderZone()
	return if hud.zoneBar.Visible then hud.zoneFill.Size.X.Scale else nil
end
local IN_ME, IN_FOE, OUT_ME, OUT_FOE = { 14, 0 }, { -14, 0 }, { 14, -60 }, { 0, 60 }
local function place(player: Player, spot: { number })
	put(player, spot[1], spot[2])
end

task.wait(3.2) -- past spawn protection
-- Nobody's yet: whoever has it to themselves takes over the capture.
place(me, IN_ME)
place(foe, OUT_FOE)
hold(1)
check(Zone.capture() == "Stinkers", "a Stinker starts taking it")
place(me, OUT_ME)
place(foe, IN_FOE)
hold(0.25)
local taker, progress = Zone.capture()
check(taker == "Sharters" and math.abs(progress - 1 / 24) < 1e-6, "a Sharter alone in it starts over as theirs")
-- Taking it: one player, six seconds.
place(me, IN_ME)
place(foe, OUT_FOE)
hold(3)
taker, progress = Zone.capture()
check(taker == "Stinkers" and math.abs(progress - 0.5) < 1e-6 and Zone.state() == nil, `alone: half taken in 3 seconds ({progress})`)
check(line() == string.format(UIConfig.zone.capturing, STINKERS.shortName, 50) and bar() == 0.5, "the HUD shows it being taken, and the bar half full")
local markerBar = marker:FindFirstChild("Bar") :: Frame
check(markerBar.Visible and (markerBar:FindFirstChild("Fill") :: Frame).BackgroundColor3 == STINKERS.color, "so does the marker, in their colour")
hold(2.75)
check(Zone.state() == nil, "not quite theirs at 5.75 seconds")
hold(0.25)
check(Zone.state() == "Stinkers" and captured[#captured] == "Stinkers" and Zone.capture() == nil, "theirs at 6")
check(workspace:GetAttribute("ZoneOwner") == "Stinkers" and workspace:GetAttribute("Zone_Stinkers") == 1, "published")
check(points() == 0, "taking it scores nothing yet")
-- Holding it.
hold(5)
local stinkers, sharters = points()
check(stinkers == 5 and sharters == 0, `then a point a second ({stinkers})`)
check(line() == string.format(UIConfig.zone.held, STINKERS.shortName) and bar() == nil, "the HUD says who holds it, in words")
check(hud.zone.TextColor3 == STINKERS.color and ring.Color == STINKERS.color and (marker:FindFirstChild("Name") :: TextLabel).TextColor3 == STINKERS.color, "and the ring and the marker in their colour")
check(not markerBar.Visible, "no bar while it's held")
-- Contested: nobody scores, it stays theirs.
place(foe, IN_FOE)
hold(4)
check(points() == 5 and Zone.state() == "Stinkers" and select(2, Zone.state()) == true, "both teams in it: nobody scores, still theirs")
check(line() == string.format(UIConfig.zone.contested, 1, 1) and ring.Color == Color3.fromRGB(245, 242, 250), "the HUD shows the standoff, the ring goes white")
-- The holder out: the other team takes it, a standoff freezes that, and
-- the holder back alone ends it.
place(me, OUT_ME)
hold(3)
taker, progress = Zone.capture()
check(taker == "Sharters" and math.abs(progress - 0.5) < 1e-6 and Zone.state() == "Stinkers", "the Sharters alone: halfway to taking it")
check(line() == string.format(UIConfig.zone.capturing, SHARTERS.shortName, 50) and hud.zone.TextColor3 == SHARTERS.color, "the HUD names who's taking it")
check(points() == 5, "and nobody scores")
place(me, IN_ME)
hold(2)
taker, progress = Zone.capture()
check(taker == "Sharters" and math.abs(progress - 0.5) < 1e-6, "a standoff freezes the capture")
check(line() == string.format(UIConfig.zone.contested, 1, 1) and bar() == 0.5, "the bar stays where it got to")
place(foe, OUT_FOE)
hold(1)
check(Zone.capture() == nil and points() == 6, "the holder alone again: the capture's over and the points come back")
-- Nobody in it: a capture runs back down; the zone stays theirs.
place(me, OUT_ME)
place(foe, IN_FOE)
hold(3)
place(foe, OUT_FOE)
hold(1.5)
taker, progress = Zone.capture()
check(taker == "Sharters" and math.abs(progress - 0.25) < 1e-6 and Zone.state() == "Stinkers", `left empty, the capture runs down ({progress})`)
check(line() == string.format(UIConfig.zone.idle, STINKERS.shortName) and bar() == 0.25, "the HUD says it's theirs but empty, with the bar going down")
hold(1.5)
check(Zone.capture() == nil and Zone.state() == "Stinkers" and points() == 6, "until it's gone; nobody scored")

-- More of a team takes it quicker, bots too: four seconds with two, three
-- with three or more, and a full team of ten no quicker than that. Bots
-- fill the server to 20 for this; they wait at their spawns until put in.
check(Director.testSetFill(GameConfig.MAX_PLAYERS), "bots fill the server")
task.wait(1)
check(Team.activeCount() == 20 and #Bots.all() == 18, `ten a side ({Team.activeCount()})`)
local squads: { [string]: { any } } = { Stinkers = {}, Sharters = {} }
for _, bot in Bots.all() do
	if Bots.isAlive(bot) then
		table.insert(squads[bot.team], { bot = bot, from = (bot.character :: Model):GetPivot() })
	end
end
check(#squads.Stinkers == 9 and #squads.Sharters == 9, "all of them out on the field")
local function send(squad: { any }, n: number, x: number)
	for i = 1, n do
		(squad[i].bot.character :: Model):PivotTo(CFrame.new(x * S, 3, (i - 5) * 3 * S))
	end
end
local function sendHome()
	for _, squad in squads do
		for _, member in squad do
			(member.bot.character :: Model):PivotTo(member.from)
		end
	end
end
check(Zone.state() == "Stinkers" and Zone.capture() == nil, "the Stinkers still hold it, nobody taking it")
place(foe, IN_FOE)
send(squads.Sharters, 1, -14)
hold(3.75)
check(Zone.state() == "Stinkers", "two Sharters: not yet at 3.75 seconds")
hold(0.25)
check(Zone.state() == "Sharters", "theirs at 4")
place(foe, OUT_FOE)
sendHome()
place(me, IN_ME)
send(squads.Stinkers, 9, 14)
hold(2.75)
check(Zone.state() == "Sharters", "ten Stinkers: not yet at 2.75 seconds")
hold(0.25)
check(Zone.state() == "Stinkers", "theirs at 3, no quicker than three")
send(squads.Sharters, 1, -14)
hold(0.25)
check(line() == string.format(UIConfig.zone.contested, 10, 1), "one bot contests it against ten (10 v 1)")
sendHome()
check(Director.testSetFill(nil), "the fill goes back to normal")
task.wait(1)
check(#Bots.all() == 2, "two bots again")

-- Eliminations clear the zone but don't score.
place(me, IN_ME)
place(foe, IN_FOE)
hold(1)
local before = points()
local zonePoints = Telemetry.snapshot().counters["Zone.points"] or 0
Gas.add(foe, 100, { attacker = me, cause = "shot", weapon = "GasBlaster" })
task.wait(1.1)
local afterBang = points()
check(afterBang - before == (Telemetry.snapshot().counters["Zone.points"] or 0) - zonePoints, "an elimination isn't a point in Gas Control: every point was the zone's")
task.wait(3)
check(points() > afterBang and Zone.state() == "Stinkers", "and the zone is ours to score again")

-- Holding rewards: a few a round.
hold(ZONE.REWARD_SECONDS * (ZONE.REWARDS_PER_ROUND + 3))
local zoneGrants = 0
for _, entry in assert(Data.get(me)).data.Ledger do
	if entry.reason == "zone" then
		zoneGrants += 1
	end
end
check(zoneGrants >= 1, "holding the zone pays, through the ledger")
check((Telemetry.snapshot().counters["Economy.coins.zone"] or 0) == ZONE.COINS * ZONE.REWARDS_PER_ROUND, "up to the round's cap")

-- The result.
Round.testEndPhaseIn(0)
task.wait(0.5)
local result = Round.snapshot().result
check(Round.phase() == "RESULTS" and result and result.winner == "Stinkers", "most zone points wins")
check(result.mode == "GasControl" and (Telemetry.snapshot().counters["round.GasControl.ended"] or 0) == 1, "the result says it was Gas Control, and it's counted as one")
check(hud.results.Enabled and hud.resultYou.Text == UIConfig.zone.results.won, "the results card says so: " .. hud.resultYou.Text)
task.wait(1.2)
check(not Zone.isActive() and ring.Transparency == 1 and not marker.Enabled and not hud.zone.Visible, "between rounds the zone is off")
check(Zone.state() == nil and Zone.capture() == nil, "and nobody holds it")

-- Rotation. (Foe stood still a while: back in, in case.)
Lifecycle.requestPlay(foe, "Sharters")
task.wait(0.2)
Round.testEndPhaseIn(0)
task.wait(0.5)
check(Round.snapshot().mode == "TeamElimination", "without rotation, the default mode")
task.wait(1.2)
check(not Zone.isActive() and workspace:GetAttribute("ZoneActive") == false, "no zone in Team Elimination")
Round.testRotation(true)
local function nextRound(): string
	Round.testEndPhaseIn(0)
	task.wait(0.5)
	Round.testEndPhaseIn(0)
	task.wait(0.5)
	return Round.snapshot().mode
end
check(nextRound() == "TeamElimination", `rotation on, but under {GameConfig.ROTATION_MIN_PLAYERS} players: the default`)
Director.testSetFill(GameConfig.MAX_PLAYERS)
task.wait(1)
check(Team.activeCount() == 20 and nextRound() == "TeamElimination", "bots filling the server to 20 don't count: still the default")
Director.testSetFill(nil)
task.wait(0.5)
local extras = {}
for i = 3, GameConfig.ROTATION_MIN_PLAYERS do
	local extra = join(`P{i}`, i)
	Lifecycle.requestPlay(extra, nil)
	table.insert(extras, extra)
end
task.wait(0.5)
local seen = {}
for _ = 1, 4 do
	table.insert(seen, nextRound())
end
check(seen[1] == "GasControl" and seen[2] == "TeamElimination" and seen[3] == "GasControl" and seen[4] == "TeamElimination", `{GameConfig.ROTATION_MIN_PLAYERS} players: straight to Gas Control after the default rounds, then turns ({table.concat(seen, ", ")})`)
extras[#extras].Parent = nil
task.wait(0.5)
check(nextRound() == "TeamElimination" and nextRound() == "TeamElimination", "one leaves: back to the default")
local returning = join("P9", 9)
Lifecycle.requestPlay(returning, nil)
task.wait(0.5)
check(nextRound() == "GasControl", "back at the minimum: Gas Control next")
Round.testRotation(nil)

-- A map that lists a zone must have one.
local bare = Instance.new("Model")
local ok, problems = MapBase.validate(bare, MapConfig.BrainrotBattlefield, { "Stinkers", "Sharters" })
check(not ok and string.find(table.concat(problems, ";"), "no control zone part", 1, true), "a missing zone fails validation")

return { status = "PASS", checks = checks }
