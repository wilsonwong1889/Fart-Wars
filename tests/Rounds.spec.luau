-- The round state machine and scoring, through the real Bootstrap:
--   * WAITING with fewer than two active players, or an empty team
--   * ACTIVE for exactly 300 server seconds, RESULTS for 15, then ACTIVE
--     again with the scores reset, over and over without a restart
--   * the most validated eliminations wins; level scores (0-0 too) draw
--   * scores freeze the moment the round ends, even between loop ticks
--   * a late loop tick still ends the round at its scheduled time
--   * every change goes to clients as a snapshot; any client can ask for it
--   * the test-only controls work from server code and chat, and the
--     remotes give clients no way to touch scores or timers
--   * every result names its mode, and rounds and draws are counted by
--     mode
--   * mode rotation on a small server: two players stay on the default;
--     at ROTATION_MIN_PLAYERS the next round is Gas Control, the full 300
--     seconds on the full-size map from 0-0, with the zone's points
--     counting (and test ones), running to the end when someone leaves
--     and the results naming it; then, under the minimum, the default
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
local RoundService = require(server.Services.RoundService)
local MatchScoreService = require(server.Services.MatchScoreService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TestControls = require(server.TestControls)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes
local function counted(key: string): number
	return Telemetry.snapshot().counters[key] or 0
end

local published = {}
Remotes.RoundUpdate.FiredToClient:Connect(function(player, snapshot)
	if player.Name == "Ada" then
		table.insert(published, snapshot)
	end
end)
local function latest()
	return published[#published]
end
local testMessages = {}
Remotes.UIMessage.FiredToClient:Connect(function(player, payload)
	if payload.kind == "test" then
		table.insert(testMessages, payload.text)
	end
end)

local function now(): number
	return workspace:GetServerTimeNow()
end
local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = 200 + nextId
	player.Parent = Players
	task.wait(0.1)
	return player
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
-- Keeps a player's avatar moving so the AFK check leaves them alone.
local function fidget(player: Player)
	task.spawn(function()
		local step = 1
		while player.Parent do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				step = -step
				root.CFrame = root.CFrame * CFrame.new(8 * step, 0, 0)
			end
			task.wait(5)
		end
	end)
end

-- Waiting.
local ada = join("Ada")
fidget(ada)
Lifecycle.requestPlay(ada, nil)
task.wait(2)
check(RoundService.phase() == "WAITING", "one active player: waiting")
local snap = RoundService.snapshot()
check(snap.phaseEndTime == nil and snap.activePlayersByTeam[ada:GetAttribute("TeamId")] == 1, "no end time while waiting")

-- 1v1 starts a round.
local bo = join("Bo")
fidget(bo)
Lifecycle.requestPlay(bo, nil)
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 1), "a second player starts the round within a tick")
snap = RoundService.snapshot()
check(snap.roundId == 1 and snap.phaseEndTime - snap.phaseStartTime == 300, "round 1 runs 300 seconds")
task.wait(0.1)
check(latest().phase == "ACTIVE" and latest().phaseEndTime == snap.phaseEndTime, "clients were sent the round")
check(Remotes.RoundSnapshot.OnServerInvoke(ada).roundId == 1, "and can ask for it")
check(not MatchScoreService.recordElimination({ team = "Stinkers", source = "client" }), "unknown score sources don't count")

-- Scoring.
local adaTeam, boTeam = ada:GetAttribute("TeamId"), bo:GetAttribute("TeamId")
check(TestControls.score(adaTeam, 3), "test eliminations go in")
bo.Chatted:Fire(`/fw score {string.lower(boTeam)} 2`)
task.wait(0.1)
check(MatchScoreService.getScores()[adaTeam] == 3 and MatchScoreService.getScores()[boTeam] == 2, "3-2 from code and chat")
check(string.find(testMessages[#testMessages], "TEST:"), "the chat command answers")
check(latest().scoresByTeam[adaTeam] == 3, "clients see the score")
local endsAt = snap.phaseEndTime :: number
task.wait(endsAt - now() - 1)
check(RoundService.phase() == "ACTIVE", "still running a second before the end")
check(waitFor(function()
	return RoundService.phase() == "RESULTS"
end, 1.5), "results at 300 seconds")
snap = RoundService.snapshot()
check(snap.result.winner == adaTeam and not snap.result.draw, "most eliminations wins")
check(snap.result.mode == "TeamElimination" and counted("round.TeamElimination.ended") == 1, "the result names its mode, and it's counted")
check(snap.phaseEndTime - snap.phaseStartTime == 15, "15 seconds of results")
check(not TestControls.score(adaTeam, 1), "scores are frozen after the round")
check(MatchScoreService.getScores()[adaTeam] == 3, "3 stays 3")

-- The next round, without a restart, scores reset.
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 16), "round 2 starts after the intermission")
snap = RoundService.snapshot()
check(snap.roundId == 2 and snap.scoresByTeam[adaTeam] == 0 and snap.scoresByTeam[boTeam] == 0, "with the scores back at 0-0")
check(snap.result == nil, "and no old result")

-- Level scores draw.
TestControls.score(adaTeam, 2)
TestControls.score(boTeam, 2)
TestControls.endPhase(0)
check(not TestControls.score(adaTeam, 1), "frozen the moment it ends, before the loop notices")
check(waitFor(function()
	return RoundService.phase() == "RESULTS"
end, 1), "results")
check(RoundService.snapshot().result.draw and RoundService.snapshot().result.winner == nil, "2-2 is a draw")
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 16), "round 3")
TestControls.endPhase(1)
check(waitFor(function()
	return RoundService.phase() == "RESULTS"
end, 2), "results")
check(RoundService.snapshot().result.draw, "0-0 is a draw")
check(counted("round.TeamElimination.ended") == 3 and counted("round.TeamElimination.draws") == 2, "draws are counted by mode too")

-- A late tick: the loop is called long after the end time.
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 16), "round 4")
local round4 = RoundService.snapshot()
RoundService.step(round4.phaseEndTime - 1)
check(RoundService.phase() == "ACTIVE", "not over a second early")
RoundService.step(round4.phaseEndTime + 7)
check(RoundService.phase() == "RESULTS", "a late tick still ends it")
check(round4.phaseEndTime - round4.phaseStartTime == 300, "the round itself was 300 server seconds")
-- That tick was from the future; bring the intermission back to now.
TestControls.endPhase(0)

-- An empty team: the round in progress finishes, the next one waits.
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 16), "round 5")
Remotes.RequestSpectate.OnServerEvent:Fire(bo)
task.wait(1)
check(RoundService.phase() == "ACTIVE", "the round carries on with a team empty")
TestControls.endPhase(0)
check(waitFor(function()
	return RoundService.phase() == "RESULTS"
end, 1), "and finishes")
check(waitFor(function()
	return RoundService.phase() == "WAITING"
end, 16), "then waits for players")
task.wait(5)
check(RoundService.phase() == "WAITING" and latest().phase == "WAITING", "and keeps waiting")
check(latest().scoresByTeam[adaTeam] == 0, "with the scores cleared")
Lifecycle.requestPlay(bo, nil)
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 1), "Bo's back: round 6")
check(RoundService.snapshot().roundId == 6, "the round count carries on")

-- The test controls and the remote surface.
check(TestControls.allowed(nil) and TestControls.allowed(ada), "test controls work in Studio")
check(TestControls.run(ada, "hello") == nil, "ordinary chat isn't a command")
-- The command bar reaches the running copy through TestControls.Command.
TestControls.start()
local commandBar = server.TestControls:FindFirstChild("Command") :: BindableFunction
local scoreBefore = RoundService.snapshot().scoresByTeam.Stinkers or 0
check(commandBar ~= nil, "the command bar has TestControls.Command")
commandBar:Invoke("score stinkers 2")
check((RoundService.snapshot().scoresByTeam.Stinkers or 0) == scoreBefore + 2, "which runs /fw commands on the game's own copy")
check(string.find(commandBar:Invoke("dance"), "commands:") ~= nil, "and lists them for an unknown one")
local names = {}
for _, remote in Remotes:GetChildren() do
	table.insert(names, remote.Name)
end
table.sort(names)
check(
	table.concat(names, ",") == "ClientReport,CombatEvent,Emote,FartDash,FireWeapon,PrestigeRequest,ProfileUpdate,ProgressEvent,ReportPlayer,RequestPlay,RequestSpectate,RequestTeam,RewardsRequest,RoundSnapshot,RoundUpdate,ShopRequest,TeamUpdate,UIMessage,UseAbility",
	"exactly the planned remotes"
)
check(type(Remotes.RoundSnapshot.OnServerInvoke) == "function", "the snapshot can be asked for")
local selfOk, selfSummary = TestControls.selftest(ada)
check(selfOk and string.find(selfSummary, "0 failures", 1, true), "the in-game selftest passes here: " .. selfSummary)

-- Mode rotation on a small server (no bots here: they never count).
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local Zone = require(server.Services.ZoneService)
RoundService.testRotation(true)
local function nextRound(): any
	TestControls.endPhase(0)
	check(waitFor(function()
		return RoundService.phase() == "RESULTS"
	end, 1), "a round ends")
	check(waitFor(function()
		return RoundService.phase() == "ACTIVE"
	end, 16), "and the next starts")
	return RoundService.snapshot()
end
check(nextRound().mode == "TeamElimination", `two players, rotation on: the default (under {GameConfig.ROTATION_MIN_PLAYERS})`)
local extras = {}
for i = 3, GameConfig.ROTATION_MIN_PLAYERS do
	local extra = join(`Extra{i}`)
	fidget(extra)
	Lifecycle.requestPlay(extra, nil)
	table.insert(extras, extra)
end
task.wait(0.5)
local endedBefore = counted("round.GasControl.ended")
snap = nextRound()
check(snap.mode == "GasControl" and snap.objective == "zone" and snap.modeName == "Gas Control", `{GameConfig.ROTATION_MIN_PLAYERS} players: Gas Control next`)
check(snap.phaseEndTime - snap.phaseStartTime == 300 and snap.scoresByTeam[adaTeam] == 0 and snap.scoresByTeam[boTeam] == 0, "the full 300 seconds, from 0-0")
check(snap.map == "BrainrotBattlefield" and MapConfig[snap.map].scale == 3, "on the full-size map")
-- Ada takes the plaza and holds it; Bo's team gets a test point.
local zone = assert(Zone.parts())
ada.Character:PivotTo(CFrame.new(zone.Position.X + 42, 3, zone.Position.Z))
task.wait(GameConfig.ZONE.CAPTURE_SECONDS[1] + 3.1)
check(Zone.state() == adaTeam and MatchScoreService.getScores()[adaTeam] >= 2, "a player alone in the plaza takes it, then scores")
check(TestControls.score(boTeam, 1), "test points count in Gas Control too")
-- Someone leaving doesn't stop the round.
extras[#extras].Parent = nil
local gasEndsAt = snap.phaseEndTime :: number
task.wait(gasEndsAt - now() - 1)
check(RoundService.phase() == "ACTIVE" and RoundService.getMode().id == "GasControl", "a player left: the round still runs to the end")
check(waitFor(function()
	return RoundService.phase() == "RESULTS"
end, 1.5), "results at 300 seconds")
local result = RoundService.snapshot().result
check(result.mode == "GasControl" and result.winner == adaTeam and counted("round.GasControl.ended") == endedBefore + 1, `the results name Gas Control and the plaza's holder wins ({result.scores[adaTeam]}-{result.scores[boTeam]})`)
check(waitFor(function()
	return RoundService.phase() == "ACTIVE"
end, 16), "the next round")
check(RoundService.snapshot().mode == "TeamElimination", "under the minimum again: the default")
check(nextRound().mode == "TeamElimination", "and it stays there")
RoundService.testRotation(nil)

return { status = "PASS", checks = checks }
