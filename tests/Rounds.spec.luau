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
local RoundService = require(server.Services.RoundService)
local MatchScoreService = require(server.Services.MatchScoreService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TestControls = require(server.TestControls)
local Remotes = ReplicatedStorage.Remotes

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
local names = {}
for _, remote in Remotes:GetChildren() do
	table.insert(names, remote.Name)
end
table.sort(names)
check(
	table.concat(names, ",") == "ClientReport,CombatEvent,Emote,FartDash,FireWeapon,ProfileUpdate,ProgressEvent,ReportPlayer,RequestPlay,RequestSpectate,RequestTeam,RewardsRequest,RoundSnapshot,RoundUpdate,ShopRequest,TeamUpdate,UIMessage,UseAbility",
	"exactly the planned remotes"
)
check(type(Remotes.RoundSnapshot.OnServerInvoke) == "function", "the snapshot can be asked for")
local selfOk, selfSummary = TestControls.selftest(ada)
check(selfOk and string.find(selfSummary, "0 failures", 1, true), "the in-game selftest passes here: " .. selfSummary)

return { status = "PASS", checks = checks }
