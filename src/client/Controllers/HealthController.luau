-- How the game runs on this PC, reported to the server about once a minute
-- (ClientReport) for the health numbers: the frame rate over the last
-- minute, render spikes (frames over SPIKE_SECONDS), network ping, how
-- long the menus wait on the server (UI latency), script errors since the
-- last report and the Roblox graphics quality. Nothing else is sent, except
-- with a player's own feedback report (FeedbackController), which takes
-- current(): the frame rate, the ping and the last few error messages
-- (players' names scrubbed out). It also keeps the frame rate lately (over
-- the last couple of seconds), so effects can thin out on a PC that's
-- struggling (Detail).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

local FeedbackConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.FeedbackConfig)

local HealthController = {}

HealthController.REPORT_SECONDS = 60
HealthController.SPIKE_SECONDS = 0.05
-- The frame rate lately is an average over about this long, and under
-- SLOW_FPS this PC is struggling.
HealthController.RECENT_SECONDS = 2
HealthController.SLOW_FPS = 40

local player = Players.LocalPlayer
local frames = 0
local spikes = 0
local errors = 0
local latencyTotal, latencyCount = 0, 0
local windowStart = os.clock()
local lastFps: number? = nil
-- The frame time lately (a moving average, weighted by time), how much
-- time it's had to go on, and the seconds of frames since the frame rate
-- was last under SLOW_FPS (nil if it hasn't been this session).
local recentDt: number? = nil
local recentFor = 0
local sinceSlow: number? = nil
-- This session's errors: how many, and the last few messages (oldest
-- first, a repeat counted on its entry rather than added again).
local sessionErrors = 0
local recentErrors: { { text: string, count: number } } = {}
local started = false

-- The Roblox graphics quality this player has set: 1-10, 0 for Automatic,
-- nil if it can't be read.
function HealthController.quality(): number?
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel
	end)
	if ok and typeof(level) == "EnumItem" then
		return level.Value
	end
	return nil
end
local quality = HealthController.quality

-- One frame, `dt` seconds long.
function HealthController.frame(dt: number)
	frames += 1
	if dt > HealthController.SPIKE_SECONDS then
		spikes += 1
	end
	if not (dt > 0) then
		return
	end
	-- A window left in the background for a while counts as one slow
	-- second, not as minutes of nothing.
	local step = math.min(dt, 1)
	local share = 1 - math.exp(-step / HealthController.RECENT_SECONDS)
	recentDt = if recentDt then recentDt + (step - recentDt) * share else step
	recentFor += step
	local fps = HealthController.recentFps()
	if fps and fps < HealthController.SLOW_FPS then
		sinceSlow = 0
	elseif sinceSlow then
		sinceSlow += step
	end
end

-- The frame rate over the last couple of seconds, or nil before there
-- have been a couple of seconds of frames.
function HealthController.recentFps(): number?
	if recentDt and recentFor >= HealthController.RECENT_SECONDS then
		return 1 / recentDt
	end
	return nil
end

-- How many seconds of frames since the frame rate lately was last under
-- SLOW_FPS (0 while it is), or nil if it hasn't been this session.
function HealthController.sinceSlow(): number?
	return sinceSlow
end

-- The report as it would be sent now (and a new window started).
function HealthController.sample(): { [string]: number }
	local nowClock = os.clock()
	local elapsed = math.max(nowClock - windowStart, 0.001)
	local report: { [string]: number } = { errors = errors }
	if frames > 0 then
		report.fps = math.floor(frames / elapsed * 10) / 10
		report.spikes = spikes
		lastFps = report.fps
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

-- Keeps an error message for current(), with this player's names scrubbed
-- out (the server scrubs everyone's again).
function HealthController.noteError(message: unknown)
	sessionErrors += 1
	if type(message) ~= "string" then
		return
	end
	local text = FeedbackConfig.cut(string.sub(message, 1, FeedbackConfig.MAX_ERROR_LENGTH * 4), FeedbackConfig.MAX_ERROR_LENGTH)
	text = FeedbackConfig.scrub(FeedbackConfig.clean(text), { player.Name, player.DisplayName })
	if text == "" then
		return
	end
	for i, entry in recentErrors do
		if entry.text == text then
			entry.count += 1
			-- The newest goes last.
			table.remove(recentErrors, i)
			table.insert(recentErrors, entry)
			return
		end
	end
	table.insert(recentErrors, { text = text, count = 1 })
	while #recentErrors > FeedbackConfig.MAX_ERRORS do
		table.remove(recentErrors, 1)
	end
end

-- The numbers now, for a feedback report, without starting a new window:
-- the frame rate so far this window (or the last one's, early on), the
-- ping, the session's error count and the last few messages, oldest first.
function HealthController.current(): { fps: number?, ping: number?, errorCount: number, errors: { string } }
	local elapsed = os.clock() - windowStart
	local fps = if frames > 0 and elapsed >= 2 then math.floor(frames / elapsed * 10) / 10 else lastFps
	local ok, ping = pcall(player.GetNetworkPing, player)
	local messages = {}
	for _, entry in recentErrors do
		-- The count first, so cutting a long message never loses it.
		table.insert(messages, if entry.count > 1 then `(x{entry.count}) {entry.text}` else entry.text)
	end
	return {
		fps = fps,
		ping = if ok and type(ping) == "number" then ping else nil,
		errorCount = sessionErrors,
		errors = messages,
	}
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
	RunService.RenderStepped:Connect(HealthController.frame)
	ScriptContext.Error:Connect(function(message)
		errors += 1
		HealthController.noteError(message)
	end)
	task.spawn(function()
		while true do
			task.wait(HealthController.REPORT_SECONDS)
			HealthController.send()
		end
	end)
end

return HealthController
