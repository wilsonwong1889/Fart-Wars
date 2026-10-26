-- Nobody dodges giving the killer the point, and nobody gets credit they
-- didn't earn (masterplan 2.2, 2.3, 1.3):
--   * mid-countdown, a team switch, a new round's respawn or another death
--     (Reset, a fall) still explodes the player for the killer
--   * a death while gassed (not counting down) goes to the recent attacker
--   * an attacker whose gas has all drained away gets no credit for a
--     later finish by gas nobody owns (a bomb whose thrower left)
--   * gas nobody fired counts toward nobody's weapon mastery
--   * someone who switched teams can't gas their new teammates, and
--     doesn't assist against them
local Players = game:GetService("Players")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
do
	local fn = assert(loadstring(server.Bootstrap.Source, "Bootstrap"))
	setfenv(fn, setmetatable({ script = server.Bootstrap }, { __index = getfenv() }))
	fn()
end
local Gas = require(server.Services.GasService)
local Eliminations = require(server.Services.EliminationService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Teams = require(server.Services.TeamService)
local TestControls = require(server.TestControls)

local credited = {}
Eliminations.Eliminated:Connect(function(e)
	table.insert(credited, e)
end)
local function lastFor(victim: Player): any
	for i = #credited, 1, -1 do
		if credited[i].victim == victim then
			return credited[i]
		end
	end
	return nil
end

local nextId = 0
local function join(name: string): Player
	nextId += 1
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = 600 + nextId
	p.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(p, nil)
	return p
end
local function fidget()
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:PivotTo(p.Character:GetPivot() * CFrame.new(6, 0, 0))
		end
	end
end
local function settle()
	task.wait(3.2)
	fidget()
	task.wait(3.1)
	fidget()
end
local everyone = {}
for _, name in { "A", "B", "C", "D", "E", "F" } do
	table.insert(everyone, join(name))
end
settle()
local function onTeam(team: string): { Player }
	local list = {}
	for _, p in everyone do
		if Teams.teamOf(p) == team then
			table.insert(list, p)
		end
	end
	return list
end
local stinkers, sharters = onTeam("Stinkers"), onTeam("Sharters")
check(#stinkers == 3 and #sharters == 3, "3v3")
local attacker, victim = sharters[1], stinkers[1]

-- A team switch mid-countdown. (Two Sharters spectate first, so the switch
-- evens the teams and is allowed.)
Lifecycle.requestSpectate(sharters[2])
Lifecycle.requestSpectate(sharters[3])
task.wait(0.2)
check(Gas.add(victim, 100, { attacker = attacker, cause = "shot" }) and Gas.isExploding(victim), "the victim is counting down")
local before = #credited
Lifecycle.requestTeam(victim, "Sharters")
task.wait(0.2)
local e = lastFor(victim)
check(#credited == before + 1 and e and e.killer == attacker, "switching team mid-countdown: exploded anyway, for the attacker")
Lifecycle.requestPlay(sharters[2], nil)
Lifecycle.requestPlay(sharters[3], nil)
settle()
stinkers, sharters = onTeam("Stinkers"), onTeam("Sharters")
attacker, victim = sharters[1], stinkers[1]

-- A new round's respawn mid-countdown.
check(Gas.add(victim, 100, { attacker = attacker, cause = "shot" }), "counting down again")
before = #credited
Lifecycle.respawnAll()
task.wait(0.2)
check(#credited == before + 1 and lastFor(victim).killer == attacker, "a respawn for everyone (a new round) doesn't save them")
settle()

-- Reset (any other death) mid-countdown, and while just gassed.
check(Gas.add(victim, 100, { attacker = attacker, cause = "shot" }), "counting down")
before = #credited
victim.Character.Humanoid.Health = 0
task.wait(0.2)
check(#credited == before + 1 and lastFor(victim).killer == attacker, "Reset mid-countdown: still the attacker's")
settle()
Gas.add(victim, 60, { attacker = attacker, cause = "shot" })
before = #credited
victim.Character.Humanoid.Health = 0
task.wait(0.2)
e = lastFor(victim)
check(#credited == before + 1 and e.killer == attacker and e.cause == "died", "Reset at 60% gas: credited to the attacker")
settle()

-- Drained gas owes nothing.
Gas.add(victim, 20, { attacker = attacker, cause = "shot", weapon = "GasBlaster" })
task.wait(5.2)
fidget()
task.wait(4.5)
fidget()
check(Gas.gasOf(victim) == 0, "fully recovered")
before = #credited
for _ = 1, 10 do
	Gas.add(victim, 10, { team = "Sharters", cause = "cloud", weapon = "StinkLobber" })
end
task.wait(1.2)
e = lastFor(victim)
check(#credited == before + 1 and e.killer == nil, "finished by gas nobody owns, long after the last hit: nobody's kill")
settle()
-- Not all drained, but the attacker's last hit was over 10 s ago.
Gas.add(victim, 90, { attacker = attacker, cause = "shot" })
task.wait(5)
fidget()
task.wait(6)
fidget()
check(Gas.gasOf(victim) > 30, "still gassed, 11 s later")
before = #credited
for _ = 1, 10 do
	Gas.add(victim, 10, { team = "Sharters", cause = "cloud" })
end
task.wait(1.2)
check(#credited == before + 1 and lastFor(victim).killer == nil, "an old attacker (outside the 10 s window) gets no credit")
settle()
-- Within the window, the attacker keeps it, but not the weapon's mastery.
Gas.add(victim, 50, { attacker = attacker, cause = "shot", weapon = "GasBlaster" })
task.wait(1)
for _ = 1, 5 do
	Gas.add(victim, 10, { team = "Sharters", cause = "cloud", weapon = "StinkLobber" })
end
task.wait(1.2)
e = lastFor(victim)
check(e.killer == attacker and e.weapon == nil, "the attacker's kill, but the bomb nobody threw counts for no weapon")
settle()

-- A turncoat can't gas their new teammates, or assist against them.
local helper = stinkers[2]
Gas.add(attacker, 30, { attacker = helper, cause = "shot" })
check(TestControls.team(helper, "sharters") and Teams.teamOf(helper) == "Sharters", "the helper switches to the attacker's team")
task.wait(0.2)
check(not Gas.add(attacker, 30, { attacker = helper, team = "Stinkers", cause = "cloud" }), "their old bomb's gas can't hurt a new teammate")
Gas.add(attacker, 100, { attacker = stinkers[3], cause = "shot" })
task.wait(1.2)
e = lastFor(attacker)
check(e and e.killer == stinkers[3] and not table.find(e.assists, helper), "and no assist against their new team")

return { status = "PASS", checks = checks }
