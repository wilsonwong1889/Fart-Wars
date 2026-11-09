-- Bots as combatants, on the real server (BotService and every service
-- that takes them in):
--   * IDs count down from -1001 and are never reused; names get "[BOT] "
--     once; team counts include bots, humanCounts doesn't; one player and
--     three bots start a round, but mode rotation counts players only
--   * a new avatar: workspace.Bots, the Bot tag, its attributes, an empty
--     meter, spawn protection; players don't spawn on top of enemy bots
--   * the meter: stages, clamping, recovery, friendly fire, protection, no
--     gas once the countdown runs
--   * a bot gasses a player out: the bot's team scores, the kill feed and
--     the explosion name the bot, Eliminated fires with no killer; the
--     chain blast gasses a bot nearby
--   * a bot gasses a bot out: a point, Died once, Ada's assist, a chain
--     credited to the killer bot, and no Eliminated
--   * a player shoots a bot out: hits, a point, no streak, no Eliminated
--   * fireAsBot: everyone sees the shot, the victim hears who hit them,
--     protection ends, one shot per interval, none mid-countdown, dead or
--     between rounds; its shots set off a barrel, the explosion the bot's
--   * removed mid-countdown (credited), moved (not), fell while gassed
--     (credited), died or destroyed with no gas (not); a bot that left
--     can't be credited
--   * the modes: kills of and by bots score in Team Elimination, never in
--     Gas Control, where bots hold and contest the zone
local CollectionService = game:GetService("CollectionService")
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
-- No bots: these checks count the players themselves.
require(server.Services.BotDirector).testSetEnabled(false)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Bots = require(server.Services.BotService)
local Gas = require(server.Services.GasService)
local Combat = require(server.Services.CombatService)
local Eliminations = require(server.Services.EliminationService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local AFK = require(server.Services.AFKService)
local Scores = require(server.Services.MatchScoreService)
local Round = require(server.Services.RoundService)
local Zone = require(server.Services.ZoneService)
local TeamService = require(server.Services.TeamService)
local TeamElimination = require(server.Modes.TeamElimination)
local GasControl = require(server.Modes.GasControl)
local Remotes = ReplicatedStorage.Remotes
Bots.start() -- a no-op once Bootstrap starts it

-- What Ada's client hears, and what the server signals.
local heard: { any } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if player.Name == "Ada" then
		table.insert(heard, event)
	end
end)
-- Shots come a frame's worth at a time, unreliably (ShotFeed).
local ShotFeed = require(game.ServerScriptService.Server.ShotFeed)
Remotes.Shots.FiredToClient:Connect(function(player, shooters, froms, tos)
	if player.Name == "Ada" then
		for i, shooter in shooters do
			table.insert(heard, { kind = "shot", shooter = shooter, from = froms[i], to = tos[i] })
		end
	end
end)
local function last(kind: string): any
	ShotFeed.flush() -- the frame's shots, sent
	for i = #heard, 1, -1 do
		if heard[i].kind == kind then
			return heard[i]
		end
	end
	return nil
end
local function count(kind: string): number
	ShotFeed.flush()
	local n = 0
	for _, event in heard do
		if event.kind == kind then
			n += 1
		end
	end
	return n
end
local teamUpdates = {}
Remotes.TeamUpdate.FiredToClient:Connect(function(player, snapshot)
	if player.Name == "Ada" then
		table.insert(teamUpdates, snapshot)
	end
end)
local eliminated = {}
Eliminations.Eliminated:Connect(function(elimination)
	table.insert(eliminated, elimination)
end)
local spawned, died, exploded, gasExploded = {}, {}, {}, {}
Bots.Spawned:Connect(function(bot, character)
	table.insert(spawned, { bot = bot, character = character })
end)
Bots.Died:Connect(function(bot, character)
	table.insert(died, { bot = bot, character = character })
end)
Bots.Exploded:Connect(function(bot, position, killer, depth, killerTeam, killerBot)
	table.insert(exploded, { bot = bot, position = position, killer = killer, depth = depth, killerTeam = killerTeam, killerBot = killerBot })
end)
Gas.Exploded:Connect(function(victim, position, killer, depth, killerTeam, killerBot)
	table.insert(gasExploded, { victim = victim, killer = killer, depth = depth, killerTeam = killerTeam, killerBot = killerBot })
end)

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
-- A bot avatar as BotDirector builds one, standing at (x, 3, z).
local function avatar(name: string, x: number, z: number): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(x, 3, z)
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = CFrame.new(x, 4.5, z)
	head.Parent = model
	Instance.new("Humanoid").Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	return model
end
-- Carrying the Gas Blaster: the checks below count its gas and its rate
-- (BotArsenal tries the rest of the arsenal).
local function spawnBot(bot: any, x: number, z: number): Model
	local model = avatar(bot.name, x, z)
	Bots.attach(bot, model, { weapon = "GasBlaster" })
	return model
end
local function place(model: Model, x: number, z: number)
	model:PivotTo(CFrame.new(x, 3, z))
end
local function awake()
	for _, player in Players:GetPlayers() do
		AFK.markActive(player)
	end
end
local function near(list: { Vector3 }, position: Vector3): boolean
	for _, p in list do
		if (p - position).Magnitude < 0.01 then
			return true
		end
	end
	return false
end
-- The Gas Gutter lane (x = 53, z = -14 to 14) is clear; level with the
-- head, a shot along it is a headshot.
local NORTH, SOUTH = Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)

-- Slots and the round.
local ada = join("Ada", 901)
local teamA = ada:GetAttribute("TeamId")
local teamB = if teamA == "Stinkers" then "Sharters" else "Stinkers"
task.wait(0.5)
check(Round.phase() == "WAITING", "one player alone: waiting")
local toots = Bots.add(teamB, "Toots")
local puff = Bots.add(teamB, "Puff")
local whiff = Bots.add(teamA, "[BOT] Whiff")
check(toots.id == -1001 and puff.id == -1002 and whiff.id == -1003, "bot IDs count down from -1001")
check(toots.name == "[BOT] Toots" and whiff.name == "[BOT] Whiff", "names carry [BOT] once")
check(Bots.get(-1002) == puff and #Bots.all() == 3 and Bots.all()[1] == toots and toots.character == nil, "found by ID, listed oldest first, no avatar yet")
local counts, humans = TeamService.counts(), TeamService.humanCounts()
check(counts[teamA] == 2 and counts[teamB] == 2 and TeamService.activeCount() == 4, "bots hold slots: two a side")
check(humans[teamA] == 1 and humans[teamB] == 0, "humanCounts is the players alone")
local update = teamUpdates[#teamUpdates]
check(update and update.counts[teamA] == 2 and update.counts[teamB] == 2, "clients see the bots in the team counts")
task.wait(0.5)
check(Round.phase() == "ACTIVE", "one player and three bots start a round")
check(Round.snapshot().activePlayersByTeam[teamB] == 2, "the round snapshot counts them too")
Round.testRotation(true)
local extras = {}
for i = 1, 3 do
	table.insert(extras, Bots.add(teamA, `Extra{i}`))
end
check(TeamService.activeCount() == 7 and Round.nextMode().id == GameConfig.DEFAULT_MODE, "mode rotation counts players, not bots")
Round.testRotation(nil)
for _, bot in extras do
	Bots.remove(bot)
end
check(TeamService.activeCount() == 4 and Bots.get(extras[1].id) == nil, "a removed bot frees its slot")

-- New avatars.
local tootsBody = spawnBot(toots, 53, 14)
local puffBody = spawnBot(puff, 30, 14)
local whiffBody = spawnBot(whiff, 53, -14)
check(#spawned == 3 and spawned[1].bot == toots and spawned[1].character == tootsBody, "Spawned for each new avatar")
check(tootsBody.Parent == workspace.Bots and CollectionService:HasTag(tootsBody, "Bot"), "avatars live in workspace.Bots, tagged Bot")
check(tootsBody:GetAttribute("BotId") == -1001 and tootsBody:GetAttribute("TeamId") == teamB, "with the bot's ID and team")
check(tootsBody:GetAttribute("DisplayName") == "[BOT] Toots" and tootsBody.Humanoid.DisplayName == "[BOT] Toots", "and its name")
check(tootsBody:GetAttribute("Gas") == 0 and tootsBody:GetAttribute("GasStage") == 0, "an empty meter")
check(Bots.isProtected(toots) and tootsBody:FindFirstChild("SpawnProtection") and type(tootsBody:GetAttribute("ProtectedUntil")) == "number", "spawn protection")
check(toots.character == tootsBody and Bots.isAlive(toots) and Bots.rootOf(toots) == tootsBody.HumanoidRootPart, "alive, with a root")
check(Bots.fromInstance(tootsBody.Head) == toots and Bots.fromInstance(tootsBody) == toots and Bots.fromInstance(ada.Character.Head) == nil, "its parts lead back to it")
local enemies = Lifecycle.enemyPositions(teamA)
check(near(enemies, tootsBody.HumanoidRootPart.Position) and near(enemies, puffBody.HumanoidRootPart.Position), "players don't spawn on top of enemy bots")
check(not near(enemies, whiffBody.HumanoidRootPart.Position), "teammate bots aren't in the way")
check(not Bots.addGas(toots, 20, { attacker = ada, cause = "shot" }), "no gas while protected")
task.wait(3.2)
check(not Bots.isProtected(toots) and tootsBody:FindFirstChild("SpawnProtection") == nil, "protection wears off")

-- The meter.
local function hitToots(amount: number): boolean
	return Bots.addGas(toots, amount, { attacker = ada, cause = "shot" })
end
check(hitToots(24) and tootsBody:GetAttribute("GasStage") == 0, "24%: normal")
check(hitToots(1) and tootsBody:GetAttribute("GasStage") == 1 and Bots.gasOf(toots) == 25, "25%: slightly inflated")
check(not Bots.addGas(toots, 10, { team = teamB, bot = puff.id, cause = "shot" }), "no gas from a teammate bot")
check(not Bots.addGas(toots, 10, { team = teamA, bot = toots.id, cause = "shot" }), "nobody gasses themselves")
check(not Bots.addGas(toots, 10, { bot = whiff.id, cause = "shot" }), "a bot's gas has to say whose side it's on")
check(Bots.gasOf(toots) == 25, "none of that went in")
task.wait(4.8)
check(Bots.gasOf(toots) == 25, "no recovery for 5 seconds")
task.wait(2.2)
local drained = Bots.gasOf(toots)
check(drained < 25 and drained > 14, `then about 5% a second ({drained})`)
hitToots(1)
local after = Bots.gasOf(toots)
task.wait(3)
check(Bots.gasOf(toots) == after, "fresh gas stops recovery again")
awake()

-- A bot gasses a player out.
place(ada.Character, 53, -10)
check(not Gas.add(ada, 10, { team = teamA, bot = whiff.id, cause = "shot" }), "a teammate bot can't gas a player")
check(not Gas.add(ada, 10, { bot = puff.id, cause = "shot" }), "nor can a bot's gas with no team")
local scoreA, scoreB = Scores.getScores()[teamA], Scores.getScores()[teamB]
local before = #eliminated
check(Gas.add(ada, 100, { team = teamB, bot = puff.id, cause = "shot", weapon = "GasBlaster" }) and Gas.isExploding(ada), "Puff gasses Ada to 100")
task.wait(1.2)
check(ada.Character.Humanoid.Health == 0 and Scores.getScores()[teamB] == scoreB + 1, "Ada explodes, and Puff's team scores")
local event = last("elimination")
check(event.victim == ada.UserId and event.killer == puff.id and event.team == teamB, "the kill feed names Puff")
check(last("explosion").victim == ada.UserId and last("explosion").killer == puff.id, "and so does the explosion")
local elimination = eliminated[#eliminated]
check(#eliminated == before + 1 and elimination.victim == ada and elimination.killer == nil and elimination.killerBot == puff.id, "Eliminated: no killer to reward; killerBot says who")
check(elimination.counted and elimination.weapon == nil and Eliminations.streakOf(ada) == 0, "it counted; no mastery for anyone")
local bang = gasExploded[#gasExploded]
check(bang.victim == ada and bang.killer == nil and bang.killerBot == puff.id and bang.killerTeam == teamB, "GasService.Exploded carries the bot")
check(Bots.gasOf(whiff) == GameConfig.EXPLOSION.CHAIN_GAS, "the chain blast gasses the bot next to Ada")

-- A bot gasses a bot out.
task.wait(3.2) -- Ada respawns
awake()
place(puffBody, 53, 10)
check(hitToots(5), "Ada adds a little")
scoreA = Scores.getScores()[teamA]
before = #eliminated
local diedBefore = #died
check(Bots.addGas(toots, 100, { team = teamA, bot = whiff.id, cause = "shot", weapon = "GasBlaster" }), "Whiff tips Toots over")
check(Bots.isExploding(toots) and Bots.gasOf(toots) == 100 and type(tootsBody:GetAttribute("ExplodesAt")) == "number", "clamped at 100, counting down")
check(not hitToots(10), "no more gas once the countdown runs")
task.wait(1.2)
check(not Bots.isAlive(toots) and toots.character == nil and tootsBody.Humanoid.Health == 0, "Toots explodes")
check(#died == diedBefore + 1 and died[#died].bot == toots and died[#died].character == tootsBody, "Died, once")
check(Scores.getScores()[teamA] == scoreA + 1, "Whiff's team scores")
event = last("elimination")
check(event.victim == toots.id and event.killer == whiff.id and event.team == teamA and table.find(event.assists, ada.UserId), "the kill feed: Whiff, with Ada's assist")
local blast = exploded[#exploded]
check(blast.bot == toots and blast.killer == nil and blast.killerBot == whiff.id and blast.killerTeam == teamA and blast.depth == 0, "Exploded names the killer bot")
check(last("explosion").victim == toots.id and last("explosion").killer == whiff.id, "the explosion event too")
check(#eliminated == before, "no Eliminated for a bot: nobody earns anything off one")
check(Bots.gasOf(puff) == GameConfig.EXPLOSION.CHAIN_GAS, "the chain blast gasses Puff")
scoreA = Scores.getScores()[teamA]
check(Bots.addGas(puff, 60, { team = teamA, cause = "chain" }), "gas with nobody behind it")
task.wait(1.2)
event = last("elimination")
check(event.victim == puff.id and event.killer == whiff.id and Scores.getScores()[teamA] == scoreA + 1, "leaves the chain's credit with Whiff")

-- A player shoots a bot out.
awake()
puffBody = spawnBot(puff, 30, 30) -- off the lane; the old body goes
local oldToots = tootsBody
local diedNow = #died
tootsBody = spawnBot(toots, 53, 14)
check(oldToots.Parent == nil and #died == diedNow, "a new avatar takes the old body away (that life already ended)")
place(ada.Character, 53, -14)
place(whiffBody, 45, 0)
task.wait(3.2)
local shotId = 0
local function shoot(direction: Vector3)
	shotId += 1
	Remotes.FireWeapon.OnServerEvent:Fire(ada, direction, shotId)
end
local weapon = Combat.weaponOf(ada)
shoot(NORTH)
local hit = last("hit")
check(hit and hit.victim == toots.id and hit.headshot and not hit.blocked and hit.gas == weapon.headshotGas, "Ada's headshot on Toots: a hit, with its gas")
scoreA = Scores.getScores()[teamA]
before = #eliminated
local streak = Eliminations.streakOf(ada)
for _ = 1, 6 do
	if tootsBody:GetAttribute("ExplodesAt") then
		break
	end
	task.wait(0.31)
	shoot(NORTH)
end
task.wait(1.2)
event = last("elimination")
check(not Bots.isAlive(toots) and event.victim == toots.id and event.killer == ada.UserId and event.team == teamA, "Ada shoots Toots out")
check(Scores.getScores()[teamA] == scoreA + 1, "and her team scores")
check(#eliminated == before and Eliminations.streakOf(ada) == streak, "but no Eliminated and no streak")

-- Bots firing.
awake()
tootsBody = spawnBot(toots, 53, 14)
check(Bots.isProtected(toots), "Toots is back, protected")
local adaGas = Gas.gasOf(ada)
local shots = count("shot")
check(Combat.fireAsBot(toots, SOUTH), "Toots fires")
check(not Bots.isProtected(toots) and tootsBody:FindFirstChild("SpawnProtection") == nil, "firing ends its protection")
check(count("shot") == shots + 1 and last("shot").shooter == toots.id, "every client sees the bot's shot")
check(Gas.gasOf(ada) == adaGas + 25, "Ada takes a headshot")
check(last("damaged").attacker == toots.id, "and her client hears who hit her")
check(not Combat.fireAsBot(toots, SOUTH) and count("shot") == shots + 1, "no faster than the fire interval")
check(not Combat.fireAsBot(toots, Vector3.zero), "and only somewhere")
place(ada.Character, 45, -14)
place(whiffBody, 53, -14)
task.wait(0.4)
local whiffGas = Bots.gasOf(whiff)
check(Combat.fireAsBot(toots, SOUTH) and Bots.gasOf(whiff) == whiffGas + 25, "a bot's shot gasses an enemy bot")
-- A bot's shots set off a barrel like anyone's: lit by its second shot, the
-- explosion is the bot's, and it gasses the bot's enemy standing beside it.
do
	local Barrels = require(server.Services.BarrelService)
	local model = Barrels.all()[1]
	local barrel = Barrels.get(model) :: any
	local pivot = model:GetPivot()
	model:PivotTo(pivot.Rotation + Vector3.new(53, pivot.Position.Y, 2))
	local body = (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) :: BasePart
	place(ada.Character, 60, 2)
	-- Whiff (Toots's enemy too) well out of the blast: the checks below
	-- count on its gas.
	place(whiffBody, -53, -14)
	task.wait(0.4)
	local adaBefore, whiffBefore = Gas.gasOf(ada), Bots.gasOf(whiff)
	local before = count("barrel")
	local head = tootsBody:FindFirstChild("Head") :: BasePart
	for _ = 1, 4 do
		if barrel.state ~= "ready" then
			break
		end
		check(Combat.fireAsBot(toots, body.Position - head.Position), "Toots shoots the barrel")
		task.wait(0.31)
	end
	check(barrel.state == "fused" and barrel.ownerBot == toots.id and barrel.owner == nil, "two bot shots light a barrel, the bot its owner")
	task.wait(GameConfig.BARREL.FUSE_SECONDS + 0.2)
	check(count("barrel") == before + 1 and last("barrel").owner == toots.id, "it goes off, every client told it's the bot's")
	check(Gas.gasOf(ada) > adaBefore, "and the blast gasses the bot's enemy beside it")
	check(Bots.gasOf(whiff) <= whiffBefore, "but no one out of its reach")
	Barrels.resetAll()
	model:PivotTo(pivot)
	place(ada.Character, 45, -14)
	place(whiffBody, 53, -14)
	task.wait(0.31)
end
check(Bots.addGas(toots, 100, { attacker = ada, cause = "shot" }) and not Combat.fireAsBot(toots, SOUTH), "no shots mid-countdown")
task.wait(1.2)
check(not Combat.fireAsBot(toots, SOUTH), "nor from the dead")

-- Every other way a life ends.
awake()
scoreA = Scores.getScores()[teamA]
local teamBCount = TeamService.counts()[teamB]
check(Bots.addGas(puff, 100, { attacker = ada, cause = "shot" }) and Bots.isExploding(puff), "Puff is counting down")
Bots.remove(puff)
event = last("elimination")
check(event.victim == puff.id and event.killer == ada.UserId and Scores.getScores()[teamA] == scoreA + 1, "removed mid-countdown: it explodes, and Ada still scores")
check(died[#died].bot == puff and puffBody.Parent == nil and Bots.get(puff.id) == nil, "Died, the avatar gone, the slot freed")
check(TeamService.counts()[teamB] == teamBCount - 1, "and counted off its team")

local eliminations = count("elimination")
check(Bots.addGas(whiff, 30, { team = teamB, bot = toots.id, cause = "shot" }), "Toots's gas in Whiff")
local teamACount = TeamService.counts()[teamA]
teamBCount = TeamService.counts()[teamB]
Bots.setTeam(whiff, teamB)
check(count("elimination") == eliminations and died[#died].bot == whiff and whiffBody.Parent == nil, "moved: that life ends with no credit")
check(whiff.team == teamB and not Bots.isAlive(whiff), "on its new team, waiting for an avatar")
check(TeamService.counts()[teamA] == teamACount - 1 and TeamService.counts()[teamB] == teamBCount + 1, "the slot moves with it")

whiffBody = spawnBot(whiff, 60, 30)
check(whiffBody:GetAttribute("TeamId") == teamB, "Whiff's new avatar is on the new team")
task.wait(3.2)
scoreA = Scores.getScores()[teamA]
check(Bots.addGas(whiff, 30, { attacker = ada, cause = "shot" }), "Ada can gas Whiff now")
whiffBody.Humanoid.Health = 0
event = last("elimination")
check(event.victim == whiff.id and event.killer == ada.UserId and event.cause == "died", "dying while gassed (a fall) is credited")
check(Scores.getScores()[teamA] == scoreA + 1 and died[#died].bot == whiff, "a point, and Died")

eliminations = count("elimination")
diedNow = #died
tootsBody = spawnBot(toots, 60, -30)
tootsBody.Humanoid.Health = 0
check(count("elimination") == eliminations and #died == diedNow + 1, "dying with no gas: nobody's credited")
tootsBody = spawnBot(toots, 60, -30)
tootsBody:Destroy()
check(count("elimination") == eliminations and #died == diedNow + 2 and not Bots.isAlive(toots), "an avatar destroyed: Died, no credit")

local gone = Bots.add(teamB, "Gone")
check(gone.id == -1007, "IDs are never reused")
Gas.reset(ada)
scoreB = Scores.getScores()[teamB]
check(Gas.add(ada, 50, { team = teamB, bot = gone.id, cause = "shot" }), "Gone gasses Ada")
Bots.remove(gone)
check(Gas.add(ada, 60, { team = teamB, cause = "chain" }) and Gas.isExploding(ada), "then leaves before the bang")
task.wait(1.2)
event = last("elimination")
check(event.victim == ada.UserId and event.killer == nil and Scores.getScores()[teamB] == scoreB, "a bot that left gets nothing")
check(eliminated[#eliminated].killer == nil and eliminated[#eliminated].killerBot == nil, "and isn't named")

-- The modes.
local context = { roundId = 1, teamIds = { "Stinkers", "Sharters" }, teamOf = TeamService.teamOf }
local function kill(fields: { [string]: any }): any
	local event = { team = "Stinkers", source = "elimination", killerTeam = "Stinkers", victimTeam = "Sharters" }
	for key, value in fields do
		event[key] = value
	end
	return event
end
check(TeamElimination:validateScoreEvent(kill({ killerBot = -1001, victimBot = -1002 }), context), "Team Elimination: a bot's kill on a bot scores")
check(TeamElimination:validateScoreEvent(kill({ killer = ada, victimBot = -1002 }), context), "a player's on a bot")
check(TeamElimination:validateScoreEvent(kill({ killerBot = -1001, victim = ada }), context), "a bot's on a player")
check(not TeamElimination:validateScoreEvent(kill({ killerBot = -1001, victimBot = -1001 }), context), "not off itself")
check(not TeamElimination:validateScoreEvent(kill({ killerBot = -1001, victimBot = -1002, victimTeam = "Stinkers" }), context), "nor off a teammate")
check(not TeamElimination:validateScoreEvent(kill({ killerBot = -1001, victimBot = -1002, killerTeam = false }), context), "a bot's kill names its team")
check(not TeamElimination:validateScoreEvent(kill({ victimBot = -1002 }), context), "and needs a killer")
check(not GasControl:validateScoreEvent(kill({ killerBot = -1001, victimBot = -1002 }), context), "Gas Control: eliminations never score")

check(Round.testSetMode("GasControl") and Round.testEndPhaseIn(0), "the next round is Gas Control")
task.wait(0.5)
awake()
tootsBody = spawnBot(toots, 53, 14)
check(Round.phase() == "RESULTS" and not Combat.fireAsBot(toots, SOUTH), "bots hold their fire between rounds")
task.wait(GameConfig.INTERMISSION_SECONDS / 2)
awake()
task.wait(GameConfig.INTERMISSION_SECONDS / 2 + 0.5)
check(Round.phase() == "ACTIVE" and Round.getMode().id == "GasControl", "a Gas Control round")
local zone = Zone.parts()
check(zone ~= nil, "the map has a zone")
tootsBody:PivotTo(CFrame.new((zone :: BasePart).Position))
-- A capture takes a few seconds (GameConfig.ZONE.CAPTURE_SECONDS).
for _ = 1, 3 * GameConfig.ZONE.CAPTURE_SECONDS[1] do
	if Zone.state() == teamB then
		break
	end
	Zone.tick(1)
end
local owner, contested = Zone.state()
check(owner == teamB and not contested and workspace:GetAttribute(`Zone_{teamB}`) == 1, "a bot alone in the zone takes it for its team")
ada.Character:PivotTo(CFrame.new((zone :: BasePart).Position + Vector3.new(1, 0, 0)))
Zone.tick(1)
owner, contested = Zone.state()
check(owner == teamB and contested, "a player against a bot contests it")

return { status = "PASS", checks = checks }
