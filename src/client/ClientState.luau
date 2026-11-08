-- What this client knows about the match, kept in step with the server:
-- the round snapshot (pulled once on start, then pushed on every change),
-- the team counts, this player's state and team (attributes the server
-- sets), and messages. Controllers read from here and never decide teams or
-- results themselves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local RoundClock = require(Shared.RoundClock)

local ClientState = {}

ClientState.SnapshotChanged = Signal.new() -- (snapshot)
ClientState.TeamsChanged = Signal.new() -- (counts)
ClientState.StateChanged = Signal.new() -- (state, previous)
ClientState.TeamChanged = Signal.new() -- (teamId?)
ClientState.Message = Signal.new() -- (payload from UIMessage)

ClientState.snapshot = nil :: RoundClock.Snapshot?
-- Everyone on each team, and how many of them are bots (the team rules
-- are about the players, so they're given both).
ClientState.counts = {} :: { [string]: number }
ClientState.bots = {} :: { [string]: number }
ClientState.maxTeamSize = GameConfig.MAX_TEAM_SIZE

local remotes: Folder
local started = false

function ClientState.remote(name: string): Instance
	return remotes:WaitForChild(name)
end

-- Sends a request to the server (it decides what happens).
function ClientState.send(name: string, ...: any)
	local remote = ClientState.remote(name) :: RemoteEvent
	remote:FireServer(...)
end

function ClientState.state(): string
	return Players.LocalPlayer:GetAttribute("State") or States.Player.MENU_SPECTATOR
end

-- Playing with an avatar: in a match, or in the practice yard (there the
-- crosshair, firing, the dash and the camera work as in a match, with no
-- team). inPractice says which.
function ClientState.isActive(): boolean
	local state = ClientState.state()
	return state == States.Player.ACTIVE or state == States.Player.PRACTICE
end

function ClientState.inPractice(): boolean
	return ClientState.state() == States.Player.PRACTICE
end

function ClientState.teamId(): string?
	return Players.LocalPlayer:GetAttribute("TeamId")
end

function ClientState.remaining(): number?
	return RoundClock.remaining(ClientState.snapshot, workspace:GetServerTimeNow())
end

local function setCounts(counts: { [string]: number }?, bots: { [string]: number }?)
	if type(counts) ~= "table" then
		return
	end
	local clean, cleanBots = {}, {}
	for _, team in TeamConfig.order do
		clean[team] = tonumber(counts[team]) or 0
		local n = if type(bots) == "table" then tonumber(bots[team]) else nil
		cleanBots[team] = math.max(0, math.min(n or 0, clean[team]))
	end
	ClientState.counts = clean
	ClientState.bots = cleanBots
	ClientState.TeamsChanged:Fire(clean)
end

local function setSnapshot(snapshot: RoundClock.Snapshot?)
	if type(snapshot) ~= "table" then
		return
	end
	ClientState.snapshot = snapshot
	setCounts(snapshot.activePlayersByTeam, snapshot.botsByTeam)
	ClientState.SnapshotChanged:Fire(snapshot)
end

-- Asks the server for the current snapshot (on start, and whenever the
-- client wants to be sure it is in step).
function ClientState.resync()
	local roundSnapshot = ClientState.remote("RoundSnapshot") :: RemoteFunction
	local ok, snapshot = pcall(roundSnapshot.InvokeServer, roundSnapshot)
	if ok then
		setSnapshot(snapshot)
	end
end

function ClientState.start()
	if started then
		return
	end
	started = true
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	local player = Players.LocalPlayer
	local roundUpdate = ClientState.remote("RoundUpdate") :: RemoteEvent
	local teamUpdate = ClientState.remote("TeamUpdate") :: RemoteEvent
	local uiMessage = ClientState.remote("UIMessage") :: RemoteEvent
	roundUpdate.OnClientEvent:Connect(setSnapshot)
	teamUpdate.OnClientEvent:Connect(function(update)
		if type(update) == "table" then
			ClientState.maxTeamSize = tonumber(update.maxTeamSize) or ClientState.maxTeamSize
			setCounts(update.counts, update.bots)
		end
	end)
	uiMessage.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.text) == "string" then
			ClientState.Message:Fire(payload)
		end
	end)
	local lastState = ClientState.state()
	player:GetAttributeChangedSignal("State"):Connect(function()
		local state = ClientState.state()
		local previous = lastState
		lastState = state
		ClientState.StateChanged:Fire(state, previous)
	end)
	player:GetAttributeChangedSignal("TeamId"):Connect(function()
		ClientState.TeamChanged:Fire(ClientState.teamId())
	end)
	task.spawn(ClientState.resync)
end

return ClientState
