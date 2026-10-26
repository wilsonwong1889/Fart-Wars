-- The gas meter and its edge cases (masterplan 2.2 and 2.5), on the real
-- server:
--   * stages at 25 / 50 / 75 / 100, published on the character
--   * gas is clamped at 100; 99 + anything starts the countdown exactly once
--   * recovery waits 5 seconds after the last gas, then drains 5% a second;
--     more gas stops it; it never goes below zero
--   * no gas while protected, from teammates, or once the countdown runs
--   * simultaneous hits: the hit that reaches 100 is the killer, the other
--     shooter assists; one elimination, one event ID
--   * assists only count from the last 10 seconds
--   * leaving or spectating mid-countdown explodes at once, and the killer
--     still scores; a killer who leaves gets nothing
--   * exploding twice never scores twice; a respawn starts at 0
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
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Scores = require(server.Services.MatchScoreService)
local TeamService = require(server.Services.TeamService)
local Remotes = ReplicatedStorage.Remotes

local eliminations = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if event.kind == "elimination" and player.Name == "Watcher" then
		table.insert(eliminations, event)
	end
end)

local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = 700 + nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local function alive(player: Player): boolean
	return player.Character ~= nil and player.Character.Humanoid.Health > 0
end
local function hit(victim: Player, attacker: Player?, amount: number): boolean
	return Gas.add(victim, amount, { attacker = attacker, cause = "shot" })
end
-- Keeps everyone's avatar moving so the AFK check leaves them be.
local function fidget()
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:PivotTo(p.Character:GetPivot() * CFrame.new(7, 0, 0))
		end
	end
end

join("Watcher") -- an extra player who only listens
local ada, bo, cy, dee = join("Ada"), join("Bo"), join("Cy"), join("Dee")
-- Two a side: Ada and Cy against Bo and Dee (whichever way the rules put them).
local teamA = ada:GetAttribute("TeamId")
local friends, foes = {}, {}
for _, p in { bo, cy, dee } do
	table.insert(if p:GetAttribute("TeamId") == teamA then friends else foes, p)
end
local mate, victim, other = friends[1], foes[1], foes[2]
check(mate and victim and other, "two a side")
task.wait(3.2) -- spawn protection over

-- Stages and clamping.
check(hit(victim, ada, 24) and victim.Character:GetAttribute("GasStage") == 0, "24%: normal")
check(hit(victim, ada, 1) and victim.Character:GetAttribute("GasStage") == 1, "25%: slightly inflated")
hit(victim, ada, 25)
check(victim.Character:GetAttribute("GasStage") == 2, "50%: obvious")
hit(victim, ada, 25)
check(victim.Character:GetAttribute("GasStage") == 3 and victim.Character:GetAttribute("Gas") == 75, "75%: critical warning")
check(not hit(victim, mate and victim, 10), "nobody gasses themselves")

-- Recovery.
task.wait(4.8)
check(Gas.gasOf(victim) == 75, "no recovery for 5 seconds")
task.wait(2.2)
local drained = Gas.gasOf(victim)
check(drained < 75 and drained > 64, `then about 5% a second ({drained})`)
hit(victim, ada, 1)
local after = Gas.gasOf(victim)
task.wait(3)
check(Gas.gasOf(victim) == after, "fresh gas stops recovery again")
check(not hit(victim, other, 10) and Gas.gasOf(victim) == after, "no gas from a teammate")
check(not hit(ada, mate, 10) and Gas.gasOf(ada) == 0, "for either team")
fidget()

-- 99 -> 100, simultaneous hits.
Gas.reset(victim)
hit(victim, ada, 99)
check(Gas.gasOf(victim) == 99 and not Gas.isExploding(victim), "99%: not yet")
local scoreBefore = Scores.getScores()[teamA]
check(hit(victim, mate, 20), "Ada's teammate tips it over")
check(not hit(victim, ada, 20), "Ada's shot in the same moment is too late")
check(Gas.gasOf(victim) == 100 and Gas.isExploding(victim), "clamped at 100, counting down")
task.wait(1.05)
check(not alive(victim) and Scores.getScores()[teamA] == scoreBefore + 1, "one elimination")
local event = eliminations[#eliminations]
check(event.killer == mate.UserId and #event.assists == 1 and event.assists[1] == ada.UserId, "the one who tipped it scores; Ada assists")
Gas.explode(victim)
check(#eliminations == 1 and Scores.getScores()[teamA] == scoreBefore + 1, "exploding twice scores once")
task.wait(3.2)
check(alive(victim) and Gas.gasOf(victim) == 0 and victim.Character:GetAttribute("Gas") == 0, "the respawn starts at 0")
check(not hit(victim, ada, 20), "and is protected")
fidget()

-- Old contributions aren't assists.
task.wait(3.2)
hit(victim, mate, 10)
task.wait(4.9) -- under the recovery delay
fidget()
task.wait(6)
check(Gas.gasOf(victim) == 0, "Bo's teammate has fully recovered")
hit(victim, ada, 100)
task.wait(1.05)
event = eliminations[#eliminations]
check(event.killer == ada.UserId and #event.assists == 0, "help from over 10 seconds ago isn't an assist")
task.wait(3.2)
fidget()

-- Leaving mid-countdown: explode now, and the killer still scores.
task.wait(3.2)
scoreBefore = Scores.getScores()[teamA]
hit(other, ada, 100)
check(Gas.isExploding(other), "Bo's teammate is counting down")
other.Parent = nil
task.wait(0.05)
check(#eliminations == 3 and eliminations[3].victim == other.UserId and eliminations[3].killer == ada.UserId, "leaving explodes at once")
check(Scores.getScores()[teamA] == scoreBefore + 1, "and Ada scores")

-- Spectating mid-countdown: the same.
hit(victim, ada, 100)
Remotes.RequestSpectate.OnServerEvent:Fire(victim)
task.wait(0.6)
check(#eliminations == 4 and eliminations[4].victim == victim.UserId, "spectating explodes at once")
check(Scores.getScores()[teamA] == scoreBefore + 2, "and Ada scores again")
check(victim.Character == nil and victim:GetAttribute("State") == "MENU_SPECTATOR", "then they're spectating")

-- A killer who leaves before the bang gets nothing.
Lifecycle.requestPlay(victim, nil)
task.wait(3.2)
local leaver = join("Leaver")
task.wait(3.2)
local leaverFoe = if leaver:GetAttribute("TeamId") == victim:GetAttribute("TeamId") then ada else victim
scoreBefore = Scores.getScores()[leaver:GetAttribute("TeamId")]
local leaverTeam = leaver:GetAttribute("TeamId")
hit(leaverFoe, leaver, 100)
leaver.Parent = nil
task.wait(1.05)
check(not alive(leaverFoe) and eliminations[#eliminations].killer == nil, "the explosion has no killer")
check(Scores.getScores()[leaverTeam] == scoreBefore, "and nobody scores")
check(TeamService.activeCount() >= 3, "everyone else carries on")

return { status = "PASS", checks = checks }
