-- The match state machine, on server timestamps:
--   WAITING  until at least MIN_ACTIVE_PLAYERS are active and neither team
--            is empty
--   ACTIVE   for the mode's round length (300 s); scores count
--   RESULTS  for the intermission (15 s); scores frozen, winner or draw shown
--   then ACTIVE again, or WAITING if the population has dropped. A round in
--   progress always runs to the end, even if players leave.
-- Every change goes to clients as a snapshot (RoundUpdate) holding absolute
-- end times; clients work out the countdown themselves, and can ask for the
-- current snapshot at any time (RoundSnapshot). The map and the game mode
-- are both swappable without changes here.
-- With FeatureFlags.MATCH_MODE = "Continuous" there are no rounds: one
-- ACTIVE match with no end time starts with the server and scores run on.
-- With FeatureFlags.MODE_ROTATION each round picks the next mode in
-- GameConfig.MODE_ROTATION that the map supports, once the server has
-- ROTATION_MIN_PLAYERS on teams; otherwise every round is DEFAULT_MODE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local MapConfig = require(Shared.Config.MapConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local TeamBalance = require(Shared.TeamBalance)
local GameModeBase = require(Shared.Interfaces.GameModeBase)
local RoundClock = require(Shared.RoundClock)
local Server = script.Parent.Parent
local Health = require(Server.Health)
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local MatchScoreService = require(script.Parent.MatchScoreService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local MapService = require(script.Parent.MapService)

local Phase = States.Phase

local RoundService = {}

-- (phase, snapshot): fires on every phase change.
RoundService.PhaseChanged = Signal.new()

local function loadMode(id: string): GameModeBase.GameMode?
	local module = Server.Modes:FindFirstChild(id)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end
local defaultMode = assert(loadMode(GameConfig.DEFAULT_MODE), "GameConfig.DEFAULT_MODE isn't in ServerScriptService.Server.Modes")
local mode: GameModeBase.GameMode = defaultMode
local rotationIndex = 0
local nextOverride: GameModeBase.GameMode? = nil
local rotationOverride: boolean? = nil

type State = {
	roundId: number,
	phase: string,
	phaseStartTime: number,
	phaseEndTime: number?,
	result: GameModeBase.Result?,
	participation: { [number]: number },
}
local state: State = {
	roundId = 0,
	phase = Phase.WAITING,
	phaseStartTime = 0,
	phaseEndTime = nil,
	result = nil,
	participation = {},
}
local lastStep: number? = nil
local started = false
local continuous = FeatureFlags.MATCH_MODE == "Continuous"
local publishQueued = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function context(): GameModeBase.Context
	return { roundId = state.roundId, teamIds = TeamConfig.order, teamOf = TeamService.teamOf }
end

function RoundService.getMode(): GameModeBase.GameMode
	return mode
end

function RoundService.phase(): string
	return state.phase
end

function RoundService.snapshot(): RoundClock.Snapshot
	local _, entry = MapService.current()
	return {
		roundId = state.roundId,
		phase = state.phase,
		phaseStartTime = state.phaseStartTime,
		phaseEndTime = state.phaseEndTime,
		scoresByTeam = MatchScoreService.getScores(),
		activePlayersByTeam = TeamService.counts(),
		result = state.result,
		mode = mode.id,
		modeName = mode.displayName,
		objective = mode.objective,
		matchMode = FeatureFlags.MATCH_MODE,
		map = if entry then entry.id else GameConfig.DEFAULT_MAP,
		serverTime = now(),
	}
end

local function publish()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local roundUpdate = remotes:WaitForChild("RoundUpdate") :: RemoteEvent
	roundUpdate:FireAllClients(RoundService.snapshot())
end

-- Many changes in one frame (a reset, a phase change, a spawn wave) go out
-- as one snapshot.
local function publishSoon()
	if publishQueued then
		return
	end
	publishQueued = true
	task.defer(function()
		publishQueued = false
		publish()
	end)
end

local function enter(phase: string, at: number, endsAt: number?)
	state.phase = phase
	state.phaseStartTime = at
	state.phaseEndTime = endsAt
	publishSoon()
	RoundService.PhaseChanged:Fire(phase, RoundService.snapshot())
end

local function canStart(): boolean
	return TeamBalance.canStart(TeamService.counts(), TeamConfig.order, GameConfig.MIN_ACTIVE_PLAYERS)
end

-- The mode for the next round.
function RoundService.nextMode(): GameModeBase.GameMode
	if nextOverride then
		local chosen = nextOverride
		nextOverride = nil
		return chosen
	end
	local rotating = if rotationOverride ~= nil then rotationOverride else FeatureFlags.MODE_ROTATION
	if not rotating or TeamService.activeCount() < GameConfig.ROTATION_MIN_PLAYERS then
		return defaultMode
	end
	local _, entry = MapService.current()
	local rotation = GameConfig.MODE_ROTATION
	for _ = 1, #rotation do
		rotationIndex = rotationIndex % #rotation + 1
		local id = rotation[rotationIndex]
		local candidate = loadMode(id)
		if candidate and (not entry or table.find(entry.modes, id)) then
			return candidate
		end
	end
	return defaultMode
end

local function startRound(at: number)
	state.roundId += 1
	mode = RoundService.nextMode()
	state.result = nil
	state.participation = {}
	local endsAt = at + mode.roundSeconds
	MatchScoreService.reset()
	MatchScoreService.open(mode, context(), endsAt)
	PlayerLifecycleService.beginRound(state.roundId)
	mode:onRoundStart(context())
	enter(Phase.ACTIVE, at, endsAt)
end

local function endRound(at: number)
	MatchScoreService.freeze()
	local result = mode:computeResult(MatchScoreService.getScores(), TeamConfig.order)
	state.result = result
	state.participation = PlayerLifecycleService.finishRound()
	mode:onRoundEnd(context(), result)
	enter(Phase.RESULTS, at, at + mode.intermissionSeconds)
end

-- Continuous play: one match that runs as long as the server does.
local function startContinuous(at: number)
	state.roundId = 1
	MatchScoreService.reset()
	MatchScoreService.open(mode, context(), math.huge)
	PlayerLifecycleService.beginRound(state.roundId)
	mode:onRoundStart(context())
	enter(Phase.ACTIVE, at, nil)
end

local function waitForPlayers(at: number)
	state.result = nil
	MatchScoreService.reset()
	enter(Phase.WAITING, at, nil)
end

-- Moves the machine on to `at` (server time). The loop calls this a few
-- times a second; it only ever compares timestamps, so a late call still
-- ends the round at its scheduled time.
function RoundService.step(at: number)
	if state.phase == Phase.ACTIVE and lastStep then
		local until_ = math.min(at, state.phaseEndTime or at)
		PlayerLifecycleService.accrue(math.max(0, until_ - lastStep))
	end
	lastStep = at
	if continuous then
		return
	end
	if state.phase == Phase.WAITING then
		if canStart() then
			startRound(at)
		end
	elseif state.phase == Phase.ACTIVE then
		if at >= (state.phaseEndTime :: number) then
			endRound(at)
		end
	elseif state.phase == Phase.RESULTS then
		if at >= (state.phaseEndTime :: number) then
			if canStart() then
				startRound(at)
			else
				waitForPlayers(at)
			end
		end
	end
end

-- The last round's participation (seconds ACTIVE by user ID), for the
-- Phase 4 completion rewards.
function RoundService.lastParticipation(): { [number]: number }
	return table.clone(state.participation)
end

-- Test-only: the next round's mode (`id`), whatever the rotation says.
function RoundService.testSetMode(id: string): (boolean, string)
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return false, "test controls are off (GameConfig.TEST_CONTROLS.ENABLED)"
	end
	local chosen = loadMode(id)
	if not chosen then
		return false, `no mode "{id}"`
	end
	nextOverride = chosen
	return true, `the next round is {chosen.displayName}`
end

-- Test seam: rotation on or off whatever FeatureFlags says (nil: the flag).
function RoundService.testRotation(enabled: boolean?)
	rotationOverride = enabled
end

-- Test-only: ends the current round or intermission `seconds` from now.
function RoundService.testEndPhaseIn(seconds: number): (boolean, string)
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return false, "test controls are off (GameConfig.TEST_CONTROLS.ENABLED)"
	end
	if continuous then
		return false, "continuous play has no rounds to end"
	end
	if state.phase == Phase.WAITING then
		return false, "nothing to end while waiting for players"
	end
	local endsAt = math.min(state.phaseEndTime :: number, now() + math.max(0, seconds))
	state.phaseEndTime = endsAt
	if state.phase == Phase.ACTIVE then
		MatchScoreService.closeAt(endsAt)
	end
	publishSoon()
	return true, `{state.phase} now ends in {math.max(0, seconds)}s`
end

function RoundService.start()
	if started then
		return
	end
	started = true
	local _, entry = MapService.current()
	if entry and not table.find(entry.modes, mode.id) then
		warn(`[Round] {entry.id} doesn't list {mode.id} in MapConfig.modes`)
	end
	assert(MapConfig[GameConfig.DEFAULT_MAP], "GameConfig.DEFAULT_MAP isn't in MapConfig")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local roundSnapshot = remotes:WaitForChild("RoundSnapshot") :: RemoteFunction
	roundSnapshot.OnServerInvoke = function()
		Telemetry.count("remote.in.RoundSnapshot")
		return RoundService.snapshot()
	end
	MatchScoreService.Changed:Connect(publishSoon)
	TeamService.Changed:Connect(publishSoon)

	state.phaseStartTime = now()
	if continuous then
		startContinuous(now())
	end
	RoundService.step(now())
	Health.loop("Rounds", GameConfig.ROUND_TICK_SECONDS, function()
		RoundService.step(now())
	end)
end

return RoundService
