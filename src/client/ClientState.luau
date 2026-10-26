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
ClientState.counts = {} :: { [string]: number }
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

function ClientState.isActive(): boolean
	return ClientState.state() == States.Player.ACTIVE
end

function ClientState.teamId(): string?
	return Players.LocalPlayer:GetAttribute("TeamId")
end

function ClientState.remaining(): number?
	return RoundClock.remaining(ClientState.snapshot, workspace:GetServerTimeNow())
end

local function setCounts(counts: { [string]: number }?)
	if type(counts) ~= "table" then
		return
	end
	local clean = {}
	for _, team in TeamConfig.order do
		clean[team] = tonumber(counts[team]) or 0
	end
	ClientState.counts = clean
	ClientState.TeamsChanged:Fire(clean)
end

local function setSnapshot(snapshot: RoundClock.Snapshot?)
	if type(snapshot) ~= "table" then
		return
	end
	ClientState.snapshot = snapshot
	setCounts(snapshot.activePlayersByTeam)
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
			setCounts(update.counts)
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
