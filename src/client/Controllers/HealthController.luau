-- How the game runs on this PC, reported to the server about once a minute
-- (ClientReport) for the health numbers: the frame rate over the last
-- minute, render spikes (frames over SPIKE_SECONDS), network ping, how
-- long the menus wait on the server (UI latency), script errors since the
-- last report and the Roblox graphics quality. Nothing else is sent.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

local HealthController = {}

HealthController.REPORT_SECONDS = 60
HealthController.SPIKE_SECONDS = 0.05

local player = Players.LocalPlayer
local frames = 0
local spikes = 0
local errors = 0
local latencyTotal, latencyCount = 0, 0
local windowStart = os.clock()
local started = false

local function quality(): number?
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel
	end)
	if ok and typeof(level) == "EnumItem" then
		return level.Value
	end
	return nil
end

-- The report as it would be sent now (and a new window started).
function HealthController.sample(): { [string]: number }
	local nowClock = os.clock()
	local elapsed = math.max(nowClock - windowStart, 0.001)
	local report: { [string]: number } = { errors = errors }
	if frames > 0 then
		report.fps = math.floor(frames / elapsed * 10) / 10
		report.spikes = spikes
	end
	if latencyCount > 0 then
		report.uiLatency = latencyTotal / latencyCount
	end
	local ok, ping = pcall(player.GetNetworkPing, player)
	if ok and type(ping) == "number" then
		report.ping = ping
	end
	local level = quality()
	if level then
		report.quality = level
	end
	frames, spikes, errors, windowStart = 0, 0, 0, nowClock
	latencyTotal, latencyCount = 0, 0
	return report
end

-- A menu request's round trip (seconds), for the UI latency.
function HealthController.noteLatency(seconds: number)
	latencyTotal += seconds
	latencyCount += 1
end

function HealthController.send()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ClientReport") :: RemoteEvent?
	if remote then
		remote:FireServer(HealthController.sample())
	end
end

function HealthController.start()
	if started then
		return
	end
	started = true
	RunService.RenderStepped:Connect(function(dt: number)
		frames += 1
		if dt > HealthController.SPIKE_SECONDS then
			spikes += 1
		end
	end)
	ScriptContext.Error:Connect(function()
		errors += 1
	end)
	task.spawn(function()
		while true do
			task.wait(HealthController.REPORT_SECONDS)
			HealthController.send()
		end
	end)
end

return HealthController
