-- Gas Blaster combat, through the real Bootstrap and remotes (masterplan
-- 1.3-1.5, 2.1 and 2.5):
--   * two players on opposite teams can shoot each other; the server casts
--     every shot itself: 20% gas a body hit, 25% to the head
--   * nobody takes gas during the 3 seconds of spawn protection, and
--     firing gives up your own
--   * friendly fire is off; walls stop shots; hats don't; spectators
--     can't fire
--   * shots faster than the fire interval, repeated shot numbers and junk
--     payloads are refused and counted; a flood of them flags the player
--   * 100% gas: a one-second countdown (no firing or dashing in it), then
--     the explosion: one point for the shooter's team, once, however many
--     more shots land; respawn works after repeated deaths
--   * a death resets the streak and the dash cooldown
--   * Fart Dash: refused during the cooldown and while exploding, and an
--     avatar that travels too far, or through a wall, is put back
--   * the test commands for spawning, teams, gas and weapons work, and
--     Telemetry records first shots, hits and eliminations
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local Dash = require(server.Services.DashService)
local Gas = require(server.Services.GasService)
local Eliminations = require(server.Services.EliminationService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Scores = require(server.Services.MatchScoreService)
local RoundService = require(server.Services.RoundService)
local TeamService = require(server.Services.TeamService)
local Telemetry = require(server.Telemetry)
local TestControls = require(server.TestControls)
local Remotes = ReplicatedStorage.Remotes

local heard: { [Player]: { any } } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	heard[player] = heard[player] or {}
	table.insert(heard[player], event)
end)
local function last(player: Player, kind: string): any
	local list = heard[player] or {}
	for i = #list, 1, -1 do
		if list[i].kind == kind then
			return list[i]
		end
	end
	return nil
end
local function count(player: Player, kind: string): number
	local n = 0
	for _, event in heard[player] or {} do
		if event.kind == kind then
			n += 1
		end
	end
	return n
end
local function rejects(remote: string, reason: string): number
	local snapshot = Telemetry.snapshot()
	return snapshot.rejects[remote] and snapshot.rejects[remote][reason] or 0
end

local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = 500 + nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local function place(player: Player, x: number, z: number)
	player.Character:PivotTo(CFrame.new(x, 3, z))
end
local function gas(player: Player): number
	return Gas.gasOf(player)
end
local function alive(player: Player): boolean
	return player.Character ~= nil and player.Character.Humanoid.Health > 0
end
-- Across a clear stretch of the Gas Gutter lane (x = 53, z = -14 to 14):
-- level with the head, or down at the body.
local HEAD = Vector3.new(0, 0, 1)
local BODY = Vector3.new(0, -1.5, 28).Unit
local SOUTH_BODY = Vector3.new(0, -1.5, -28).Unit
local function lineUp(shooter: Player, target: Player)
	place(shooter, 53, -14)
	place(target, 53, 14)
end
local shots: { [Player]: number } = {}
local function shoot(player: Player, direction: any, id: any?)
	shots[player] = (shots[player] or 0) + 1
	Remotes.FireWeapon.OnServerEvent:Fire(player, direction, if id ~= nil then id else shots[player])
end
-- Body hits until `target` is counting down (each a fire interval apart).
local function inflate(shooter: Player, target: Player, aim: Vector3)
	for _ = 1, 6 do
		if target.Character:GetAttribute("ExplodesAt") then
			return
		end
		shoot(shooter, aim)
		task.wait(0.31)
	end
end

local ada = join("Ada")
local bo = join("Bo")
local adaTeam, boTeam = ada:GetAttribute("TeamId"), bo:GetAttribute("TeamId")
check(adaTeam and boTeam and adaTeam ~= boTeam, "two players on opposite teams")
task.wait(0.5)
check(RoundService.phase() == "ACTIVE", "a round is on")
check(ada:GetAttribute("Weapon") == "GasBlaster", "everyone spawns with the Gas Blaster")
check(bo.Character:GetAttribute("Gas") == 0 and bo.Character:GetAttribute("GasStage") == 0, "with an empty gas meter")

-- Spawn protection.
lineUp(ada, bo)
check(Lifecycle.isProtected(bo) and bo.Character:FindFirstChild("SpawnProtection"), "a fresh spawn is protected (with a ForceField)")
shoot(ada, BODY)
check(gas(bo) == 0 and last(ada, "hit") and last(ada, "hit").blocked, "a protected player takes no gas")
check(not Lifecycle.isProtected(ada), "firing ended Ada's own protection")
task.wait(3.1)
check(not Lifecycle.isProtected(bo), "protection ends after 3 seconds")

-- Hits.
shoot(ada, BODY)
check(gas(bo) == 20 and bo.Character:GetAttribute("Gas") == 20, "a body hit: 20% gas")
check(last(ada, "hit").gas == 20 and not last(ada, "hit").headshot, "the shooter gets a hit marker")
check(last(bo, "damaged") and last(bo, "damaged").attacker == ada.UserId, "the victim learns who hit them, and from where")
check(last(bo, "shot") and last(bo, "shot").shooter == ada.UserId, "everyone sees the shot")
task.wait(0.31)
shoot(ada, HEAD)
check(gas(bo) == 45 and last(ada, "hit").headshot, "a headshot: 25%")
check(bo.Character:GetAttribute("GasStage") == 1, "45%: slightly inflated")
local tooFast = rejects("FireWeapon", "tooFast")
shoot(ada, BODY)
check(gas(bo) == 45 and rejects("FireWeapon", "tooFast") == tooFast + 1, "a shot inside the fire interval is refused")
task.wait(0.31)
shoot(ada, BODY, shots[ada] - 1)
check(gas(bo) == 45 and rejects("FireWeapon", "duplicate") == 1, "a repeated shot number is refused")
task.wait(0.31)
shoot(ada, nil)
for _, junk in { "north", 7, { 0, 0, 1 }, Vector3.new(0 / 0, 0, 1), Vector3.new(0, 0, 9), Vector3.zero } do
	task.wait(0.31)
	shoot(ada, junk)
end
task.wait(0.31)
shoot(ada, BODY, "1")
task.wait(0.31)
shoot(ada, BODY, 1.5)
check(gas(bo) == 45 and rejects("FireWeapon", "badPayload") >= 9, "junk aim or shot numbers are refused, never trusted")
check(next(Telemetry.snapshot().errors) == nil, "and never break the server")

-- The explosion, once.
local before = Scores.getScores()[adaTeam]
task.wait(0.31)
inflate(ada, bo, BODY)
check(gas(bo) == 100 and type(bo.Character:GetAttribute("ExplodesAt")) == "number", "100%: the countdown starts")
check(alive(bo) and Gas.isExploding(bo), "Bo is still standing for a moment")
local exploding = rejects("FireWeapon", "exploding")
shoot(bo, SOUTH_BODY)
check(rejects("FireWeapon", "exploding") == exploding + 1, "no firing in the countdown")
check(not Dash.dash(bo, HEAD) and rejects("FartDash", "prohibited") == 1, "no dashing either")
task.wait(1.05)
check(not alive(bo), "then Bo explodes")
check(Scores.getScores()[adaTeam] == before + 1, "one point for Ada's team")
local elimination = last(ada, "elimination")
check(elimination and elimination.killer == ada.UserId and elimination.victim == bo.UserId and elimination.cause == "shot", "everyone hears about it")
check(last(ada, "explosion") and typeof(last(ada, "explosion").position) == "Vector3", "and sees where")
check(Eliminations.streakOf(ada) == 1, "Ada's streak is 1")
for _ = 1, 3 do
	task.wait(0.31)
	shoot(ada, BODY)
end
check(Scores.getScores()[adaTeam] == before + 1 and count(ada, "elimination") == 1, "shooting the body scores nothing more")

-- Respawn after repeated deaths, protected every time, with a fresh meter.
for life = 1, 3 do
	task.wait(3.2)
	check(alive(bo) and gas(bo) == 0 and bo.Character:GetAttribute("Gas") == 0 and Lifecycle.isProtected(bo), `respawn {life}: fresh and protected`)
	lineUp(ada, bo)
	task.wait(0.31)
	shoot(ada, BODY)
	check(gas(bo) == 0, `respawn {life}: no spawn kill`)
	task.wait(3.1)
	inflate(ada, bo, BODY)
	task.wait(1.05)
	check(not alive(bo), `life {life} ends`)
end
check(Eliminations.streakOf(ada) == 4 and Scores.getScores()[adaTeam] == before + 4, "four eliminations, four points")

-- A death resets the streak.
task.wait(3.2)
place(bo, 53, -14)
place(ada, 53, 14)
task.wait(3.1)
inflate(bo, ada, BODY)
task.wait(1.05)
check(not alive(ada) and Eliminations.streakOf(ada) == 0 and Eliminations.streakOf(bo) == 1, "Ada's death resets her streak")
check(Eliminations.bestStreakOf(ada) == 4, "her best stays 4")
task.wait(3.2)

-- Friendly fire, walls, spectators.
local cy = join("Cy")
local cyTeam = cy:GetAttribute("TeamId")
local mate = if cyTeam == adaTeam then ada else bo
task.wait(3.1)
lineUp(mate, cy)
task.wait(0.31)
shoot(mate, BODY)
check(gas(cy) == 0, "no friendly fire")
local enemy = if cyTeam == adaTeam then bo else ada
place(enemy, 0, -40)
place(cy, 0, -66) -- inside the Stinkers' spawn room, behind its front wall
task.wait(0.31)
shoot(enemy, Vector3.new(0, 0, -1))
check(gas(cy) == 0, "walls stop shots")
Remotes.RequestSpectate.OnServerEvent:Fire(cy)
task.wait(0.6)
local notActive = rejects("FireWeapon", "notActive")
shoot(cy, BODY)
check(rejects("FireWeapon", "notActive") == notActive + 1, "spectators can't fire")

-- Fart Dash.
task.wait(0.6)
check(Dash.dash(ada, HEAD), "a dash is accepted")
check(last(bo, "dash") and last(bo, "dash").player == ada.UserId, "everyone sees the trail")
check(not Dash.dash(ada, HEAD) and rejects("FartDash", "cooldown") >= 1, "a second inside the cooldown isn't")
task.wait(3.1)
local start = ada.Character.HumanoidRootPart.Position
check(Dash.dash(ada, HEAD), "after the cooldown, another")
place(ada, start.X, start.Z + 60) -- far more than a dash allows
task.wait(0.6)
check((ada.Character.HumanoidRootPart.Position - start).Magnitude < 1 and rejects("FartDash", "tooFar") == 1, "too far: put back")
-- Through the spawn room's front wall (z = -57): a short hop, but a wall.
task.wait(2.6)
place(ada, 0, -53)
local outside = ada.Character.HumanoidRootPart.Position
check(Dash.dash(ada, HEAD), "a dash by the spawn room's front wall")
place(ada, 0, -61)
task.wait(0.6)
check((ada.Character.HumanoidRootPart.Position - outside).Magnitude < 1 and rejects("FartDash", "throughWall") == 1, "through the wall: put back")
check((Telemetry.snapshot().counters["flags.dashThroughWall"] or 0) == 1, "and flagged for review")
check(Dash.dash(bo, HEAD), "Bo dashes")
place(bo, 53, -14)
place(ada, 53, 14)
task.wait(0.31)
inflate(ada, bo, SOUTH_BODY)
task.wait(1.05)
check(not alive(bo), "Bo is eliminated mid-cooldown")
task.wait(3.2)
check(Dash.dash(bo, HEAD), "a new life, a fresh dash")

-- Hats and hair don't take shots meant for the head.
local hat = Instance.new("Accessory")
local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Parent = hat
hat.Parent = bo.Character
task.wait(0.05)
check(handle.CanQuery == false and handle.CanCollide == false, "an accessory on an avatar can't be hit")

-- Test commands.
check(TestControls.team(ada, if adaTeam == "Stinkers" then "sharters" else "stinkers"), "/fw team moves a player")
check(ada:GetAttribute("TeamId") ~= adaTeam and TeamService.teamOf(ada) ~= adaTeam, "and the team follows")
check(TestControls.spawn(ada), "/fw spawn respawns")
check(TestControls.gas(ada, 60) and gas(ada) == 60 and ada.Character:GetAttribute("GasStage") == 2, "/fw gas sets the meter")
check(TestControls.resetGas(ada) and gas(ada) == 0, "/fw resetgas empties it")
check(TestControls.weapon(ada, "gasblaster") and not TestControls.weapon(ada, "bazooka"), "/fw weapon gives known weapons only")
local ok, summary = TestControls.stats()
check(ok and string.find(summary, "eliminations 6"), "/fw stats sums it up: " .. summary)

-- Telemetry.
local snapshot = Telemetry.snapshot()
check(snapshot.firsts.shot and snapshot.firsts.hit and snapshot.firsts.elimination, "first shot, hit and elimination are timed")
check(snapshot.firsts.shot.players >= 2 and snapshot.firsts.elimination.players == 2, "per player, once each")
check(snapshot.firsts.timeToExplosion and snapshot.firsts.timeToExplosion.players == 6, "and time to explosion")
local spammer = join("Spammer")
for _ = 1, 40 do
	shoot(spammer, "junk")
end
check(Telemetry.isFlagged(spammer) and not Telemetry.isFlagged(ada), "a flood of rejected requests is flagged")

return { status = "PASS", checks = checks }
