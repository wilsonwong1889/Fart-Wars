-- The award cards at the end of a round (FeatureFlags.ROUND_AWARDS):
--   * the maths (RoundAwards): Top Fragger counts eliminations, Chain
--     Master the biggest chain reaction (chain and barrel eliminations no
--     more than CHAIN_GAP_SECONDS apart; the shot that starts one, stink
--     bombs, clouds and pulses aren't part of it), Barrel Buster barrels
--     set off, Team Player assists; nobody wins with 0, an empty round has
--     none, and one combatant can win several
--   * ties: the award's own tie-breaker (fewer deaths; more chain or
--     barrel eliminations), then whoever got there first, then a player
--     over a bot, then the lower id
--   * bots win like players (as bots, by their names); someone who has
--     left can't win, so the next best does
--   * through the real server: eliminations of and by players and bots,
--     assists, a chain and barrels count only while the round is live; the
--     results snapshot carries the cards to the clients; the next round
--     starts from nothing; an empty round sends none; awards off, nothing
--     is counted or sent
--   * the results screen: a card per award with the winner's name, their
--     headshot (asked for once, then cached) or a bot's robot, the award's
--     badge, the number in words and a line; your own name stands out;
--     Reduce Motion puts them all up at once with no pop, otherwise they
--     pop in one at a time; the HUD size scales the whole block; with no
--     awards the winner's card is alone, where it always was
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local Shared = ReplicatedStorage.Shared
local UIConfig = require(Shared.Config.UIConfig)
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local RoundAwards = require(server.RoundAwards)

----------------------------------------------------------------------------
-- The maths.

check(FeatureFlags.ROUND_AWARDS == true, "awards are on as shipped")
local roster = {
	[1] = { id = 1, name = "Ada", team = "Stinkers", bot = false },
	[2] = { id = 2, name = "Bo", team = "Sharters", bot = false },
	[3] = { id = 3, name = "Cy", team = "Stinkers", bot = false },
	[-1001] = { id = -1001, name = "[BOT] Toots", team = "Sharters", bot = true },
	[-1002] = { id = -1002, name = "[BOT] Puff", team = "Stinkers", bot = true },
}
local function everyone(id: number)
	return roster[id]
end
local function awardsOf(tally, lookup: any?): ({ [string]: any }, { any })
	local list = RoundAwards.compute(tally, lookup or everyone)
	local byAward = {}
	for _, award in list do
		byAward[award.award] = award
	end
	return byAward, list
end
local function kill(tally, at: number, killer: number?, victim: number?, cause: string?, assists: { number }?)
	tally:elimination({ at = at, killer = killer, victim = victim, cause = cause or "shot", assists = assists })
end

-- Nothing to give.
check(#RoundAwards.compute(RoundAwards.new(), everyone) == 0, "an empty round has no awards")
local quiet = RoundAwards.new()
kill(quiet, 1, nil, 1, "died")
kill(quiet, 2, nil, 2, "test")
check(#RoundAwards.compute(quiet, everyone) == 0, "deaths alone win nothing: nobody wins with 0")
check(quiet:statsOf(1).deaths == 1 and quiet:statsOf(3) == nil, "but they're counted")

-- Each award from its own number, in the cards' order.
local basic = RoundAwards.new()
kill(basic, 1, 1, 2)
kill(basic, 2, 1, 2, "shot", { 3 })
kill(basic, 3, 1, -1001, "lob", { 3, -1002 })
basic:barrel(2, 4)
local got, list = awardsOf(basic)
check(#list == 3 and list[1].award == "TopFragger" and list[2].award == "BarrelBuster" and list[3].award == "TeamPlayer", "Top Fragger, Barrel Buster, Team Player, in that order; no chain, no Chain Master")
check(got.TopFragger.id == 1 and got.TopFragger.value == 3 and got.TopFragger.name == "Ada" and got.TopFragger.team == "Stinkers" and got.TopFragger.bot == false, "Top Fragger: Ada, 3 eliminations")
check(got.BarrelBuster.id == 2 and got.BarrelBuster.value == 1, "Barrel Buster: Bo, 1 barrel")
check(got.TeamPlayer.id == 3 and got.TeamPlayer.value == 2, "Team Player: Cy, 2 assists")
local odd = RoundAwards.new()
kill(odd, 1, 1, 2, "shot", { 1, 2, 3 })
check(odd:statsOf(1).assists == 0 and odd:statsOf(2).assists == 0 and odd:statsOf(3).assists == 1, "the killer and the victim never assist")

-- Chains.
local GAP = RoundAwards.CHAIN_GAP_SECONDS
check(GAP == 3, "a chain's eliminations are at most 3 seconds apart")
local chains = RoundAwards.new()
-- Bo: a shot sets it off (not part of the chain), then three in a row, the
-- last after a barrel on the way (1.7 s).
kill(chains, 10, 2, 1, "shot")
kill(chains, 11, 2, 3, "chain")
kill(chains, 12.1, 2, -1002, "chain")
kill(chains, 13.8, 2, 1, "barrel")
-- Later, a separate one of two.
kill(chains, 40, 2, 3, "chain")
kill(chains, 41, 2, 1, "chain")
local boChains = chains:statsOf(2)
check(boChains.bestChain == 3 and boChains.chainKills == 5 and boChains.barrelKills == 1 and boChains.eliminations == 6, "Bo's biggest chain is 3: the shot that started it isn't in it, and a pause ends it")
-- Ada: exactly the gap apart joins, a moment more starts another.
kill(chains, 100, 1, 2, "chain")
kill(chains, 100 + GAP, 1, 2, "chain")
kill(chains, 100 + 2 * GAP + 0.01, 1, 2, "chain")
check(chains:statsOf(1).bestChain == 2, "the gap exactly joins the chain; any longer starts a new one")
-- Cy: bombs, clouds, pulses and deaths in gas are no chain.
for i, cause in { "lob", "cloud", "pulse", "died" } do
	kill(chains, 200 + i, 3, 1, cause)
end
check(chains:statsOf(3).bestChain == 0 and chains:statsOf(3).chainKills == 0 and chains:statsOf(3).eliminations == 4, "stink bombs, clouds and pulses aren't chain reactions")
got = awardsOf(chains)
check(got.ChainMaster.id == 2 and got.ChainMaster.value == 3, "Chain Master: Bo's 3")
check(got.TopFragger.id == 2 and got.TopFragger.value == 6, "and Top Fragger: one combatant can win several")

-- Ties. Top Fragger: fewer deaths first...
local t1 = RoundAwards.new()
kill(t1, 1, 1, 3)
kill(t1, 2, 1, 3)
kill(t1, 3, 3, 1)
kill(t1, 5, 2, 3)
kill(t1, 6, 2, 3)
check(awardsOf(t1).TopFragger.id == 2, "level on eliminations: fewer deaths wins (Bo), though Ada got there first")
-- ...then whoever got there first.
local t2 = RoundAwards.new()
kill(t2, 1, 1, 3)
kill(t2, 6, 1, 3)
kill(t2, 2, 2, 3)
kill(t2, 4, 2, 3)
check(awardsOf(t2).TopFragger.id == 2, "level on deaths too: whoever got there first (Bo, at 4 s)")
-- Dead level: a player over a bot, then the lower id.
local t3 = RoundAwards.new()
kill(t3, 5, -1001, 3)
kill(t3, 5, 1, 3)
check(awardsOf(t3).TopFragger.id == 1, "dead level: a player over a bot")
local t4 = RoundAwards.new()
kill(t4, 5, 3, 1)
kill(t4, 5, 2, 1)
check(awardsOf(t4).TopFragger.id == 2, "and between players the lower id, the same every time")
-- Chain Master: more chain eliminations in all.
local t5 = RoundAwards.new()
kill(t5, 1, 1, 2, "chain")
kill(t5, 2, 1, 2, "chain")
kill(t5, 10, 2, 1, "chain")
kill(t5, 11, 2, 1, "chain")
kill(t5, 30, 2, 1, "barrel")
check(awardsOf(t5).ChainMaster.id == 2, "level chains: more chain eliminations in all wins (Bo), though Ada's came first")
-- Barrel Buster: more barrel eliminations, then first.
local t6 = RoundAwards.new()
t6:barrel(1, 1)
t6:barrel(1, 2)
t6:barrel(2, 3)
t6:barrel(2, 4)
kill(t6, 5, 2, 1, "barrel")
check(awardsOf(t6).BarrelBuster.id == 2, "level barrels: the one whose barrels got someone")
local t7 = RoundAwards.new()
t7:barrel(1, 1)
t7:barrel(1, 2)
t7:barrel(2, 3)
t7:barrel(2, 4)
check(awardsOf(t7).BarrelBuster.id == 1, "then whoever set theirs off first")
-- Team Player: fewer deaths.
local t8 = RoundAwards.new()
kill(t8, 1, 3, 2, "shot", { 1 })
kill(t8, 2, 3, 2, "shot", { -1001 })
kill(t8, 3, 2, -1001)
check(awardsOf(t8).TeamPlayer.id == 1, "level assists: fewer deaths wins")

-- Bots.
local botty = RoundAwards.new()
kill(botty, 1, -1001, 1, "shot", { -1002 })
kill(botty, 2, -1001, 2, "chain", { -1002 })
botty:barrel(1, 3)
got = awardsOf(botty)
check(got.TopFragger.id == -1001 and got.TopFragger.bot and got.TopFragger.name == "[BOT] Toots", "a bot can be Top Fragger, named as a bot")
check(got.TeamPlayer.id == -1002 and got.TeamPlayer.bot and got.TeamPlayer.value == 2, "and Team Player")
check(got.ChainMaster.id == -1001 and got.ChainMaster.value == 1, "a chain of one is still a chain")
check(got.BarrelBuster.id == 1 and not got.BarrelBuster.bot, "and a player keeps their own")

-- Gone before the end.
local leaving = RoundAwards.new()
for i = 1, 5 do
	kill(leaving, i, 3, 2)
end
kill(leaving, 10, 1, 2)
kill(leaving, 11, 1, 2)
check(awardsOf(leaving).TopFragger.id == 3, "Cy has the most")
local function withoutCy(id: number)
	return if id == 3 then nil else roster[id]
end
check(awardsOf(leaving, withoutCy).TopFragger.id == 1, "but once Cy has left, the next best (Ada) gets it")
check(#RoundAwards.compute(leaving, function()
	return nil
end) == 0, "and with everyone gone, nobody does")

----------------------------------------------------------------------------
-- Through the real server, with my client.

local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
-- No bots of BotDirector's: these checks place their own.
require(server.Services.BotDirector).testSetEnabled(false)
local Awards = require(server.Services.AwardService)
local Round = require(server.Services.RoundService)
local Eliminations = require(server.Services.EliminationService)
local Gas = require(server.Services.GasService)
local Bots = require(server.Services.BotService)
local Barrels = require(server.Services.BarrelService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local AFK = require(server.Services.AFKService)
local TestControls = require(server.TestControls)
local Remotes = ReplicatedStorage.Remotes

-- What my client is sent.
local sent = {}
Remotes.RoundUpdate.FiredToClient:Connect(function(player, snapshot)
	if player.Name == "Me" then
		table.insert(sent, snapshot)
	end
end)

local function now(): number
	return workspace:GetServerTimeNow()
end
local function waitFor(condition: () -> boolean, limit: number): boolean
	local deadline = now() + limit
	while not condition() do
		if now() > deadline then
			return false
		end
		task.wait(0.05)
	end
	return true
end
-- Everyone counts as busy (the AFK check leaves them be).
task.spawn(function()
	while true do
		for _, player in Players:GetPlayers() do
			AFK.markActive(player)
		end
		task.wait(5)
	end
end)

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
task.wait(0.5)
local HUD = require(client.Controllers.HUDController)
local Settings = require(client.Settings)
local UI = require(client.UI)
local hud = HUD.parts
Lifecycle.requestPlay(me, nil)

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
-- A bot's avatar as BotDirector builds one, up where no blast reaches.
local function life(bot: any, x: number, z: number): Model
	local model = Instance.new("Model")
	model.Name = bot.name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(x, 700, z)
	root.Parent = model
	Instance.new("Humanoid").Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	Bots.attach(bot, model)
	return model
end
local function respawned(player: Player, old: Model?): boolean
	return waitFor(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return character ~= nil and character ~= old and humanoid ~= nil and humanoid.Health > 0
	end, 6)
end
-- Gas barrels with no other barrel near them (so one never sets off
-- another), ready to go.
local function loneBarrels(): { Model }
	local all, lone = Barrels.all(), {}
	for _, model in all do
		local at = model.PrimaryPart.Position
		local alone = true
		for _, other in all do
			if other ~= model and (other.PrimaryPart.Position - at).Magnitude < 50 then
				alone = false
			end
		end
		if alone and model:GetAttribute("Ready") then
			table.insert(lone, model)
		end
	end
	table.sort(lone, function(a, b)
		return a.PrimaryPart.Position.X < b.PrimaryPart.Position.X
	end)
	return lone
end

local ada = join("Ada", 901)
local mine, theirs = me:GetAttribute("TeamId"), ada:GetAttribute("TeamId")
check(mine ~= nil and theirs ~= nil and mine ~= theirs, "Ada and I on opposite teams")
check(waitFor(function()
	return Round.phase() == "ACTIVE"
end, 1), "a round starts")
local toots, puff, whiff = Bots.add(theirs, "Toots"), Bots.add(theirs, "Puff"), Bots.add(theirs, "Whiff")
local bo = join("Bo", 902)
check(bo:GetAttribute("TeamId") == mine, "Bo joins my side")

-- Ada gets me twice (Toots helping) and Bo once, for real: her gas, his
-- countdown, the bang (up where it reaches nobody and no barrel).
local myBody = me.Character
check(Eliminations.eliminate(me, myBody, { killer = ada, assistBots = { toots.id }, cause = "shot" }) ~= nil, "Ada gets me, Toots helping")
check(respawned(me, myBody), "I'm back")
myBody = me.Character
Eliminations.eliminate(me, myBody, { killer = ada, assistBots = { toots.id }, cause = "shot" })
check(respawned(me, myBody), "and back again")
local boBody = bo.Character
boBody:PivotTo(CFrame.new(0, 400, 0))
check(waitFor(function()
	return not Lifecycle.isProtected(bo)
end, 4), "Bo's spawn protection is over")
check(Gas.add(bo, 100, { attacker = ada, cause = "shot" }), "Ada fills Bo with gas")
check(respawned(bo, boBody), "Bo goes off, and is back")

-- Bo's chain reaction: Toots, then Puff a second later (by a barrel), me
-- helping with the first.
check(Eliminations.eliminateBot(toots.id, life(toots, 30, 30), { killer = bo, victimTeam = theirs, assists = { me }, cause = "chain" }) ~= nil, "Bo's chain gets Toots, with my help")
task.wait(1.1)
Eliminations.eliminateBot(puff.id, life(puff, -30, 30), { killer = bo, victimTeam = theirs, cause = "barrel" })

-- Barrels: two for Bo, one for me.
local lone = loneBarrels()
check(#lone >= 3, "three barrels standing alone")
check(Barrels.shoot(bo, lone[1].PrimaryPart, GameConfig.BARREL.HEALTH), "Bo lights one")
check(Barrels.shoot(bo, lone[2].PrimaryPart, GameConfig.BARREL.HEALTH), "and another")
check(Barrels.shoot(me, lone[3].PrimaryPart, GameConfig.BARREL.HEALTH), "I light one")
task.wait(GameConfig.BARREL.FUSE_SECONDS + 0.2)
check(not lone[1]:GetAttribute("Ready") and not lone[2]:GetAttribute("Ready") and not lone[3]:GetAttribute("Ready"), "all three blow")

-- Cy gets the most, then leaves before the end.
local cy = join("Cy", 903)
check(cy:GetAttribute("TeamId") == mine, "Cy joins my side")
for i = 1, 4 do
	Eliminations.eliminateBot(whiff.id, life(whiff, 0, 60 + 10 * i), { killer = cy, victimTeam = theirs, cause = "shot" })
	task.wait(0.1)
end
check(Awards.statsOf(cy.UserId).eliminations == 4, "Cy has four, the most")
cy.Parent = nil
task.wait(0.1)

local adaStats, myStats, boStats, tootsStats = Awards.statsOf(ada.UserId), Awards.statsOf(me.UserId), Awards.statsOf(bo.UserId), Awards.statsOf(toots.id)
check(adaStats.eliminations == 3 and adaStats.deaths == 0, "Ada: three eliminations, the real one too")
check(myStats.deaths == 2 and myStats.assists == 1 and myStats.barrels == 1 and myStats.eliminations == 0, "me: eliminated twice, an assist (on a bot), a barrel")
check(boStats.eliminations == 2 and boStats.deaths == 1 and boStats.bestChain == 2 and boStats.chainKills == 2 and boStats.barrelKills == 1, "Bo: a chain of two")
check(boStats.barrels == 2, "and two barrels")
check(tootsStats.assists == 2 and tootsStats.deaths == 1, "Toots: two assists, and eliminated once")
check(Round.snapshot().awards == nil, "no awards while the round is on")

-- The end, with Reduce Motion and a headshot already known.
Settings.reduceMotion = true
HUD.headshots[bo.UserId] = "rbxassetid://42"
TestControls.endPhase(0)
check(waitFor(function()
	return Round.phase() == "RESULTS"
end, 1), "the round ends")
task.wait(0.1)
local awards = Round.snapshot().awards
check(type(awards) == "table" and #awards == 4, "four awards")
check(awards[1].award == "TopFragger" and awards[1].id == ada.UserId and awards[1].name == "Ada" and awards[1].value == 3, "Top Fragger: Ada, 3 (Cy had more, but left)")
check(awards[1].team == theirs and awards[1].bot == false, "on her team, not a bot")
check(awards[2].award == "ChainMaster" and awards[2].id == bo.UserId and awards[2].value == 2, "Chain Master: Bo's chain of two")
check(awards[3].award == "BarrelBuster" and awards[3].id == bo.UserId and awards[3].value == 2, "Barrel Buster: Bo, two barrels")
check(awards[4].award == "TeamPlayer" and awards[4].id == toots.id and awards[4].bot and awards[4].name == "[BOT] Toots" and awards[4].value == 2, "Team Player: Toots, a bot, two assists")
local last = sent[#sent]
check(last.phase == "RESULTS" and type(last.awards) == "table" and #last.awards == 4 and last.awards[4].id == toots.id, "my client was sent them with the results")
check(last.result and last.result.winner == mine and last.result.scores[mine] == 6, "alongside the result (Bo's and Cy's bots won it for us, 6-3)")

-- The cards: all up at once, still, with Reduce Motion.
check(hud.results.Enabled and hud.awards.Visible, "the results show the award cards")
for i = 1, 4 do
	check(hud.awardCards[i].Visible, `card {i} is up at once with Reduce Motion`)
	check(hud.awardCards[i]:FindFirstChild("Press") == nil, `card {i} didn't pop`)
end
local topCard = hud.awardCards[1] :: any
check(topCard.Title.Text == "TOP FRAGGER" and topCard.Face.Badge.Text == UIConfig.awards.TopFragger.icon, "TOP FRAGGER, with its badge")
check(topCard.PlayerName.Text == "Ada" and topCard.Value.Text == "3" and topCard.Unit.Text == "ELIMINATIONS", "Ada, 3 ELIMINATIONS")
check(table.find(UIConfig.awards.TopFragger.lines, topCard.Line.Text) ~= nil, "and a line in the game's voice: " .. topCard.Line.Text)
check(topCard.Face.Headshot.Image == "rbxassetid://0" and not topCard.Face.Glyph.Visible, "Ada's headshot")
check(HUD.headshots[ada.UserId] == "rbxassetid://0", "kept for next time")
check(topCard.Face.Border.Color == TeamConfig.teams[theirs].color, "ringed in her team's colour")
check(topCard.PlayerName.TextColor3 == UIConfig.colors.text, "someone else's name, in the usual colour")
local chainCard, barrelCard = hud.awardCards[2] :: any, hud.awardCards[3] :: any
check(chainCard.Title.Text == "CHAIN MASTER" and chainCard.PlayerName.Text == "Bo" and chainCard.Value.Text == "2" and chainCard.Unit.Text == "IN ONE CHAIN", "CHAIN MASTER: Bo, 2 IN ONE CHAIN")
check(barrelCard.Title.Text == "BARREL BUSTER" and barrelCard.Value.Text == "2" and barrelCard.Unit.Text == "BARRELS POPPED", "BARREL BUSTER: 2 BARRELS POPPED")
check(chainCard.Face.Headshot.Image == "rbxassetid://42" and barrelCard.Face.Headshot.Image == "rbxassetid://42", "Bo's headshot from the cache, not asked for again")
local teamCard = hud.awardCards[4] :: any
check(teamCard.Title.Text == "TEAM PLAYER" and teamCard.PlayerName.Text == "[BOT] Toots" and teamCard.Value.Text == "2" and teamCard.Unit.Text == "ASSISTS", "TEAM PLAYER: [BOT] Toots, 2 ASSISTS")
check(teamCard.Face.Glyph.Visible and teamCard.Face.Glyph.Text == "🤖" and teamCard.Face.Headshot.Image == "", "a robot for a face")
check(teamCard.Line.Text == UIConfig.awardBotLine, "and a roast for the humans")

-- One block, scaled by the HUD size.
local stack = hud.resultStack
check(stack.Parent == hud.results and hud.awards.Parent == stack and hud.resultTitle:IsDescendantOf(stack), "the winner's card and the awards are one block")
check(stack.Size.Y.Offset > 220 and stack.Position.Y.Scale == 0.5, "which makes room for the cards")
local hudScale = stack:FindFirstChild("HudScale") :: UIScale
check(hudScale ~= nil and hudScale.Scale == 1, "and has the HUD size on it")
Settings.hudScale = 1.25
UI.applyScale()
check(hudScale.Scale == 1.25, "HUD SIZE 125%: the whole block grows, cards and all")
Settings.hudScale = 1
UI.applyScale()

-- After the round, nothing counts; the next one starts from nothing.
myBody = me.Character
Eliminations.eliminate(me, myBody, { killer = ada, cause = "shot" })
check(Awards.statsOf(ada.UserId).eliminations == 3, "an elimination in the results doesn't count")
check(waitFor(function()
	return Round.phase() == "ACTIVE"
end, 17), "the next round")
check(Awards.statsOf(ada.UserId) == nil and Awards.statsOf(toots.id) == nil, "starts from nothing")
check(Round.snapshot().awards == nil, "and the old awards are gone")

-- Round 2, with motion: the cards pop in one at a time. I'm Top Fragger
-- with one; Bo sets off a barrel.
Settings.reduceMotion = false
TestControls.barrels()
check(respawned(me, myBody), "I'm back for round 2")
Eliminations.eliminateBot(puff.id, life(puff, -30, 30), { killer = me, victimTeam = theirs, cause = "shot" })
check(Barrels.shoot(bo, loneBarrels()[1].PrimaryPart, GameConfig.BARREL.HEALTH), "Bo lights a barrel")
task.wait(GameConfig.BARREL.FUSE_SECONDS + 0.2)
TestControls.endPhase(0)
check(waitFor(function()
	return hud.results.Enabled
end, 1), "round 2's results")
check(#Round.snapshot().awards == 2, "two awards")
check(not hud.awardCards[1].Visible and not hud.awardCards[2].Visible, "with motion, the cards aren't out yet")
task.wait(UIConfig.awardRevealSeconds + 0.02)
check(hud.awardCards[1].Visible and not hud.awardCards[2].Visible, "they come in one at a time")
task.wait(UIConfig.awardRevealSeconds)
check(hud.awardCards[2].Visible and hud.awardCards[1]:FindFirstChild("Press") and hud.awardCards[2]:FindFirstChild("Press"), "each with a pop")
check(not hud.awardCards[3].Visible and not hud.awardCards[4].Visible, "two awards, two cards")
local myCard, boCard = hud.awardCards[1] :: any, hud.awardCards[2] :: any
check(myCard.Title.Text == "TOP FRAGGER" and myCard.PlayerName.Text == "Me" and myCard.Value.Text == "1" and myCard.Unit.Text == "ELIMINATION", "TOP FRAGGER: me, 1 ELIMINATION")
check(myCard.PlayerName.TextColor3 == UIConfig.colors.accent, "my own name stands out")
check(boCard.Title.Text == "BARREL BUSTER" and boCard.Unit.Text == "BARREL POPPED" and boCard.Face.Headshot.Image == "rbxassetid://42", "BARREL BUSTER: Bo, 1 BARREL POPPED")
local roundId = Round.snapshot().roundId
local lines = UIConfig.awards.TopFragger.lines
check(myCard.Line.Text == lines[roundId % #lines + 1], "this round's line")

-- Round 3: nobody does anything.
check(waitFor(function()
	return Round.phase() == "ACTIVE"
end, 17), "round 3")
TestControls.endPhase(0)
check(waitFor(function()
	return Round.phase() == "RESULTS"
end, 1), "ends with nothing done")
task.wait(0.1)
check(type(Round.snapshot().awards) == "table" and #Round.snapshot().awards == 0 and #sent[#sent].awards == 0, "an empty round: no awards, not even on 0")
check(hud.results.Enabled and not hud.awards.Visible, "no cards")
check(stack.Size.Y.Offset == 220 and stack.Position.Y.Scale == 0.45, "the winner's card alone, where it always was")
for i = 1, 4 do
	check(not hud.awardCards[i].Visible, `card {i} hidden`)
end

-- Round 4: awards off.
check(waitFor(function()
	return Round.phase() == "ACTIVE"
end, 17), "round 4")
Awards.testSetEnabled(false)
Eliminations.eliminateBot(puff.id, life(puff, -30, 30), { killer = me, victimTeam = theirs, cause = "shot" })
check(Awards.statsOf(me.UserId) == nil, "awards off: nothing is counted")
TestControls.endPhase(0)
check(waitFor(function()
	return Round.phase() == "RESULTS"
end, 1), "the round ends")
task.wait(0.1)
check(Round.snapshot().awards == nil and sent[#sent].awards == nil, "and nothing is sent")
check(hud.results.Enabled and not hud.awards.Visible, "the results show no cards")
Awards.testSetEnabled(nil)

return { status = "PASS", checks = checks }
