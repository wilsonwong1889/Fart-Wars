-- Bots filling the server, through the real Bootstrap: one human gets
-- three bots, 2v2; only humans playing count (one still in the lobby takes
-- no bot's place); joins, leaves and team changes add, remove and move
-- them; a dead bot is back after RESPAWN_SECONDS with no body left
-- behind; two bots face to face fight at a human rate of fire and the kill
-- is credited; the /fw bots commands; a new round brings every bot back in a
-- fresh avatar with no gas; Gas Control sends them to the zone.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
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
local Bots = require(server.Services.BotService)
local Director = require(server.Services.BotDirector)
local TeamService = require(server.Services.TeamService)
local Round = require(server.Services.RoundService)
local TestControls = require(server.TestControls)
local Remotes = ReplicatedStorage.Remotes
Director.start()

local function join(name, id)
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = id
	player.Parent = Players
	task.wait(0.1)
	return player
end
local function play(player, team)
	Remotes.RequestPlay.OnServerEvent:Fire(player, team)
	task.wait(0.6)
end
local function line()
	local parts = {}
	for _, bot in Bots.all() do
		table.insert(parts, `{bot.name}:{bot.team}:{if Bots.isAlive(bot) then "alive" else "dead"}`)
	end
	local c = TeamService.counts()
	return `{#Bots.all()} bots [{table.concat(parts, ", ")}] counts S{c.Stinkers} Y{c.Sharters}`
end

check(#Bots.all() == 0, "no bots in an empty server")
local ada = join("Ada", 1)
task.wait(1)
print("after join:", line())
check(#Bots.all() == 3, "3 bots for one human")
check(#workspace.Bots:GetChildren() == 3, "3 avatars in workspace.Bots: " .. #workspace.Bots:GetChildren())
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
for _, model in workspace.Bots:GetChildren() do
	local gun = model:FindFirstChild("HeldWeapon")
	check(gun and gun:GetAttribute("Weapon") == model:GetAttribute("Weapon"), "holding its life's gun")
	check(CollectionService:HasTag(model, "Bot"), "tagged")
	check(model:FindFirstChildOfClass("Humanoid").WalkSpeed == WeaponConfig.weapons[gun:GetAttribute("Weapon")].walkSpeed, "at that gun's walk speed")
	print(model.Name, model:GetAttribute("Weapon"), model:GetPivot().Position)
end
play(ada)
task.wait(1)
print("after play:", line(), Round.phase())
local c = TeamService.counts()
check(c.Stinkers == 2 and c.Sharters == 2, "2v2")
task.wait(10)
print("10 s in:", line(), Round.phase())
local bob = join("Bob", 2)
task.wait(1)
print("bob joined:", line())
check(#Bots.all() == 3, "Bob in the lobby takes no bot's place: still 3 bots for Ada")
play(bob)
task.wait(1)
print("bob plays:", line())
check(#Bots.all() == 2, "Bob playing: 2 bots for 2 humans")
c = TeamService.counts()
check(c.Stinkers == 2 and c.Sharters == 2, "still 2v2")
-- Bob forced onto Ada's team: a bot crosses to even it.
local adaTeam = TeamService.teamOf(ada)
print(TestControls.run(bob, "/fw team " .. string.lower(adaTeam)))
task.wait(1)
print("bob moved:", line())
c = TeamService.counts()
check(c.Stinkers == 2 and c.Sharters == 2, "a bot moved: 2v2 " .. line())
for _, bot in Bots.all() do
	check(bot.team ~= adaTeam, "both bots against the two humans")
	check(Bots.isAlive(bot) and bot.character and bot.character:GetAttribute("TeamId") == bot.team, "respawned on its new team")
end
check(#workspace.Bots:GetChildren() == 2, "no stray bodies: " .. #workspace.Bots:GetChildren())
print(TestControls.run(bob, "/fw team " .. (if adaTeam == "Stinkers" then "sharters" else "stinkers")))
task.wait(1)
print("bob back:", line())
print(TestControls.run(ada, "/fw bots"))
print(TestControls.run(ada, "/fw bots fill 6"))
task.wait(1)
check(#Bots.all() == 4, "fill 6 -> 4 bots")
print(TestControls.run(ada, "/fw bots skill 0.9"))
print(TestControls.run(ada, "/fw bots off"))
task.wait(1)
check(#Bots.all() == 0 and #workspace.Bots:GetChildren() == 0, "off: none " .. #workspace.Bots:GetChildren())
print(TestControls.run(ada, "/fw bots on"))
print(TestControls.run(ada, "/fw bots fill"))
task.wait(1)
check(#Bots.all() == 2, "on again: 2")
bob.Parent = nil
task.wait(1)
print("bob left:", line())
check(#Bots.all() == 3, "bob left: 3")
c = TeamService.counts()
check(c.Stinkers == 2 and c.Sharters == 2, "2v2 again")
-- kill a bot, watch it respawn
local victim = Bots.all()[1]
local old = victim.character
old:FindFirstChildOfClass("Humanoid").Health = 0
task.wait(0.5)
check(not Bots.isAlive(victim), "dead")
task.wait(3.5)
check(Bots.isAlive(victim) and victim.character ~= old and old.Parent == nil, "respawned, old body gone")
for _, model in workspace.Bots:GetChildren() do
	print(model.Name, model:GetPivot().Position)
end
-- Two enemy bots face to face in the open: they fight (shots, or stink
-- bombs), each with its own gun.
local shots = {}
local function heard(id: number)
	local shooter = Bots.get(id)
	table.insert(shots, { shooter = id, at = workspace:GetServerTimeNow(), weapon = shooter and shooter.weapon })
end
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if player.Name == "Ada" and event.kind == "lob" and event.shooter < 0 then
		heard(event.shooter)
	end
end)
-- Shots go out a frame's worth at a time (ShotFeed); timed here as the
-- server casts them, for the rate of fire.
local ShotFeed = require(server.ShotFeed)
local cast = ShotFeed.add
ShotFeed.add = function(shooter: number, from: Vector3, to: Vector3, onlyTo: Player?)
	if shooter < 0 then
		heard(shooter)
	end
	return cast(shooter, from, to, onlyTo)
end
local a, b
for _, bot in Bots.all() do
	if bot.team == "Stinkers" and not a then a = bot end
	if bot.team == "Sharters" and not b then b = bot end
end
task.wait(4) -- past spawn protection
a.character:PivotTo(CFrame.lookAt(Vector3.new(220, 3, -15), Vector3.new(220, 3, 15)))
b.character:PivotTo(CFrame.lookAt(Vector3.new(220, 3, 15), Vector3.new(220, 3, -15)))
print("protected?", Bots.isProtected(a), Bots.isProtected(b), Round.phase())
do
	local Brain = require(server.Bots.BotBrain)
	local probe = Brain.new(a, a.character, require(ReplicatedStorage.Shared.Config.BotConfig).tuning())
	local foeB = { key = b, character = b.character, root = Bots.rootOf(b) }
	print("root", probe.root.Position, probe.root.CFrame.LookVector, "head", probe.head.Position)
	print("inView", probe:inView(foeB, workspace:GetServerTimeNow()))
	local from = probe.head.Position
	local result = workspace:Raycast(from, b.character.UpperTorso.Position - from, probe.rays)
	print("ray hit", result and result.Instance:GetFullName(), result and result.Instance.CanQuery)
	probe:stop()
end
task.wait(3)
print("shots in 3 s:", #shots, "gas", Bots.gasOf(a), Bots.gasOf(b))
check(#shots > 3, "they shoot each other")
local last = {}
for _, shot in shots do
	if last[shot.shooter] then
		local interval = WeaponConfig.weapons[shot.weapon].fireInterval
		check(shot.at - last[shot.shooter] >= interval - 1e-6, `never faster than the gun ({shot.weapon}): {shot.at - last[shot.shooter]}`)
	end
	last[shot.shooter] = shot.at
end
task.wait(10)
print("13 s:", #shots, "gas", Bots.gasOf(a), Bots.gasOf(b), Bots.isAlive(a), Bots.isAlive(b))
task.wait(60)
print("a minute on:", line(), Round.phase())
print(TestControls.run(ada, "/fw mode gascontrol"))
-- A new round: everyone back at a spawn. Gas on them first, or "no gas"
-- below would prove nothing.
local before, gassed = {}, 0
for _, bot in Bots.all() do
	before[bot] = bot.character
	Bots.endProtection(bot)
	local enemy = if bot.team == "Stinkers" then "Sharters" else "Stinkers"
	if Bots.addGas(bot, 40, { team = enemy, cause = "cloud" }) then
		gassed += 1
	end
end
check(gassed > 0, "gas on them before the round ends")
-- The new round's spawns, as they come: spread over half a second like the
-- players', not all in one frame; the bots still to come wait in their old
-- bodies, sitting out.
local SPREAD = require(ReplicatedStorage.Shared.Config.GameConfig).ROUND_SPAWN_SPREAD_SECONDS
local respawns: { { bot: any, at: number } } = {}
local roundAt: number? = nil
local sittingOut = { count = 0, safe = true }
local spawnWatch = Bots.Spawned:Connect(function(bot)
	table.insert(respawns, { bot = bot, at = os.clock() })
end)
local roundWatch = Round.PhaseChanged:Connect(function(phase)
	if phase ~= "ACTIVE" or roundAt then
		return
	end
	roundAt = os.clock()
	local fresh = {}
	for _, entry in respawns do
		if entry.at >= roundAt then
			fresh[entry.bot] = true
		end
	end
	for _, bot in Bots.all() do
		if not fresh[bot] then
			sittingOut.count += 1
			local enemy = if bot.team == "Stinkers" then "Sharters" else "Stinkers"
			sittingOut.safe = sittingOut.safe and Bots.isProtected(bot) and not Bots.addGas(bot, 40, { team = enemy, cause = "cloud" })
		end
	end
end)
print(TestControls.run(ada, "/fw end 1"))
task.wait(20)
spawnWatch:Disconnect()
roundWatch:Disconnect()
print("mode now", Round.getMode().id, Round.phase())
check(Round.phase() == "ACTIVE", "the next round is on: " .. Round.phase())
check(#Bots.all() == 3 and #workspace.Bots:GetChildren() == 3, "three bots, no old bodies: " .. #workspace.Bots:GetChildren())
local started = roundAt :: number
local fresh, at = {}, {}
for _, entry in respawns do
	if entry.at >= started and entry.at <= started + SPREAD + 1e-6 then
		table.insert(fresh, entry.bot)
		table.insert(at, entry.at - started)
	end
end
check(#fresh == 3 and at[1] == 0 and math.abs(at[2] - SPREAD / 2) < 1e-6 and math.abs(at[3] - SPREAD) < 1e-6, `each bot respawns once, half a second for the three ({table.concat(at, ", ")})`)
check(sittingOut.count == 2 and sittingOut.safe, "the two still to come wait in their old bodies, where no gas lands")
for _, bot in Bots.all() do
	check(Bots.isAlive(bot) and bot.character ~= before[bot], "a fresh avatar: " .. bot.name)
	check(Bots.gasOf(bot) == 0, "no gas: " .. bot.name .. " " .. Bots.gasOf(bot))
end
do
	local Brain = require(server.Bots.BotBrain)
	local Zone = require(server.Services.ZoneService)
	local bot = Bots.all()[1]
	local probe = Brain.new(bot, bot.character, require(ReplicatedStorage.Shared.Config.BotConfig).tuning())
	local now = workspace:GetServerTimeNow()
	check(probe:wantedGoal(now) == "zone", "gas control: to the zone")
	local zone = Zone.parts()
	for _ = 1, 20 do
		local goal = probe:pickGoal("zone")
		check(Zone.inside(goal + Vector3.new(0, 1, 0), zone), "a spot in the zone " .. tostring(goal))
	end
	probe.retreating = true
	check(probe:wantedGoal(now) == "retreat", "backing off beats the zone")
	probe:stop()
	local other = Brain.new(bot, bot.character, require(ReplicatedStorage.Shared.Config.BotConfig).tuning())
	for _ = 1, 10 do
		local p = other:patrolPoint()
		print("patrol", bot.team, p)
	end
	other:stop()
end
ada.Parent = nil
task.wait(1)
check(#Bots.all() == 0 and #workspace.Bots:GetChildren() == 0, "the last human left: no bots")
return { status = "PASS", checks = checks }
