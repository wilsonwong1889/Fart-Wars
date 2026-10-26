-- Phase 1 combat, through the real Bootstrap and remotes (masterplan 1.3,
-- 1.4 and 1.5):
--   * two players on opposite teams can shoot each other with the
--     placeholder blaster; the server casts every shot itself
--   * nobody can be hurt during the 3 seconds of spawn protection, and
--     firing gives up your own
--   * friendly fire is off; walls stop shots; spectators can't fire
--   * shots faster than the fire interval, and junk payloads, are refused
--     and counted; a flood of them flags the player as abnormal
--   * four hits eliminate: one point for the shooter's team, once, however
--     many more shots land on the body; respawn works after repeated deaths
--   * a death resets the streak and the dash cooldown
--   * Fart Dash: refused during the cooldown, and an avatar that travels
--     too far is put back
--   * the test commands for spawning, teams, resetting and weapons work,
--     and Telemetry records first shots, hits and eliminations
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
local Combat = require(server.Services.CombatService)
local Dash = require(server.Services.DashService)
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
local function health(player: Player): number
	return player.Character.Humanoid.Health
end
local NORTH, SOUTH = Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)
-- A clear stretch of the Gas Gutter lane: x = 53 from z = -14 to 14.
local function lineUp(shooter: Player, target: Player)
	place(shooter, 53, -14)
	place(target, 53, 14)
end
local function shoot(player: Player, direction: any)
	Remotes.FireWeapon.OnServerEvent:Fire(player, direction)
end

local ada = join("Ada")
local bo = join("Bo")
local adaTeam, boTeam = ada:GetAttribute("TeamId"), bo:GetAttribute("TeamId")
check(adaTeam and boTeam and adaTeam ~= boTeam, "two players on opposite teams")
task.wait(0.5)
check(RoundService.phase() == "ACTIVE", "a round is on")
check(ada:GetAttribute("Weapon") == "StarterBlaster", "everyone spawns with the starter weapon")

-- Spawn protection.
lineUp(ada, bo)
check(Lifecycle.isProtected(bo) and bo.Character:FindFirstChild("SpawnProtection"), "a fresh spawn is protected (with a ForceField)")
shoot(ada, NORTH)
check(health(bo) == 100 and last(ada, "hit") and last(ada, "hit").blocked, "a protected player takes nothing")
check(not Lifecycle.isProtected(ada) and not ada.Character:FindFirstChild("SpawnProtection"), "firing ended Ada's own protection")
task.wait(3.1)
check(not Lifecycle.isProtected(bo) and not bo.Character:FindFirstChild("SpawnProtection"), "protection ends after 3 seconds")

-- Hits.
shoot(ada, NORTH)
check(health(bo) == 75, "a hit takes 25")
check(last(ada, "hit").health == 75 and not last(ada, "hit").blocked, "the shooter gets a hit marker")
check(last(bo, "damaged") and last(bo, "damaged").attacker == ada.UserId, "the victim learns who hit them, and from where")
check(last(bo, "shot") and last(bo, "shot").shooter == ada.UserId, "everyone sees the shot")
local tooFast = rejects("FireWeapon", "tooFast")
shoot(ada, NORTH)
check(health(bo) == 75 and rejects("FireWeapon", "tooFast") == tooFast + 1, "a shot inside the fire interval is refused")
task.wait(0.31)
shoot(ada, nil)
for _, junk in { "north", 7, { 0, 0, 1 }, Vector3.new(0 / 0, 0, 1), Vector3.new(0, 0, 9), Vector3.zero } do
	task.wait(0.31)
	shoot(ada, junk)
end
check(health(bo) == 75 and rejects("FireWeapon", "badPayload") >= 7, "junk aim is refused, never trusted")
check(next(Telemetry.snapshot().errors) == nil, "and never breaks the server")

-- Elimination, once.
local before = Scores.getScores()[adaTeam]
for _ = 1, 3 do
	task.wait(0.31)
	shoot(ada, NORTH)
end
check(health(bo) == 0, "four hits eliminate")
check(Scores.getScores()[adaTeam] == before + 1, "one point for Ada's team")
local elimination = last(ada, "elimination")
check(elimination and elimination.killer == ada.UserId and elimination.victim == bo.UserId, "everyone hears about it")
check(Combat.streakOf(ada) == 1, "Ada's streak is 1")
for _ = 1, 3 do
	task.wait(0.31)
	shoot(ada, NORTH)
end
check(Scores.getScores()[adaTeam] == before + 1 and count(ada, "elimination") == 1, "shooting the body scores nothing more")

-- Respawn after repeated deaths, protected every time.
for life = 1, 3 do
	task.wait(3.2)
	check(bo.Character and health(bo) == 100 and Lifecycle.isProtected(bo), `respawn {life}: fresh and protected`)
	lineUp(ada, bo)
	task.wait(0.31)
	shoot(ada, NORTH)
	check(health(bo) == 100, `respawn {life}: no spawn kill`)
	task.wait(3.1)
	for _ = 1, 4 do
		shoot(ada, NORTH)
		task.wait(0.31)
	end
	check(health(bo) == 0, `life {life} ends`)
end
check(Combat.streakOf(ada) == 4 and Scores.getScores()[adaTeam] == before + 4, "four eliminations, four points")

-- A death resets the streak.
task.wait(3.2)
place(bo, 53, -14)
place(ada, 53, 14)
task.wait(3.1)
for _ = 1, 4 do
	shoot(bo, NORTH)
	task.wait(0.31)
end
check(health(ada) == 0 and Combat.streakOf(ada) == 0 and Combat.streakOf(bo) == 1, "Ada's death resets her streak")
task.wait(3.2)

-- Friendly fire, walls, spectators.
local cy = join("Cy")
local cyTeam = cy:GetAttribute("TeamId")
local mate = if cyTeam == adaTeam then ada else bo
task.wait(3.1)
lineUp(mate, cy)
task.wait(0.31)
shoot(mate, NORTH)
check(health(cy) == 100, "no friendly fire")
local enemy = if cyTeam == adaTeam then bo else ada
place(enemy, 0, -40)
place(cy, 0, -66) -- inside the Stinkers' spawn room, behind its front wall
task.wait(0.31)
shoot(enemy, SOUTH)
check(health(cy) == 100, "walls stop shots")
Remotes.RequestSpectate.OnServerEvent:Fire(cy)
task.wait(0.6)
local notActive = rejects("FireWeapon", "notActive")
shoot(cy, NORTH)
check(rejects("FireWeapon", "notActive") == notActive + 1, "spectators can't fire")

-- Fart Dash.
task.wait(0.6)
check(Dash.dash(ada, NORTH), "a dash is accepted")
check(not Dash.dash(ada, NORTH) and rejects("FartDash", "cooldown") >= 1, "a second inside the cooldown isn't")
task.wait(3.1)
local start = ada.Character.HumanoidRootPart.Position
check(Dash.dash(ada, NORTH), "after the cooldown, another")
place(ada, start.X, start.Z + 60) -- far more than a dash allows
task.wait(0.6)
check((ada.Character.HumanoidRootPart.Position - start).Magnitude < 1 and rejects("FartDash", "tooFar") == 1, "too far: put back")
check(Dash.dash(bo, NORTH), "Bo dashes")
place(bo, 53, -14)
place(ada, 53, 14)
task.wait(0.31)
for _ = 1, 4 do
	shoot(ada, SOUTH)
	task.wait(0.31)
end
check(health(bo) == 0, "Bo is eliminated mid-cooldown")
task.wait(3.2)
check(Dash.dash(bo, NORTH), "a new life, a fresh dash")

-- Test commands.
check(TestControls.team(ada, if adaTeam == "Stinkers" then "sharters" else "stinkers"), "/fw team moves a player")
check(ada:GetAttribute("TeamId") ~= adaTeam and TeamService.teamOf(ada) ~= adaTeam, "and the team follows")
check(TestControls.spawn(ada), "/fw spawn respawns")
ada.Character.Humanoid.Health = 40
check(TestControls.resetGas(ada) and health(ada) == 100, "/fw resetgas clears the meter")
check(TestControls.weapon(ada, "starterblaster") and not TestControls.weapon(ada, "bazooka"), "/fw weapon gives known weapons only")
local ok, summary = TestControls.stats()
check(ok and string.find(summary, "shots %d+, hits %d+, eliminations 6"), "/fw stats sums it up: " .. summary)

-- Telemetry.
local firsts = Telemetry.snapshot().firsts
check(firsts.shot and firsts.hit and firsts.elimination, "first shot, hit and elimination are timed")
check(firsts.shot.players >= 2 and firsts.elimination.players == 2, "per player, once each")
local spammer = join("Spammer")
for _ = 1, 40 do
	shoot(spammer, "junk")
end
check(Telemetry.isFlagged(spammer) and not Telemetry.isFlagged(ada), "a flood of rejected requests is flagged")

return { status = "PASS", checks = checks }
