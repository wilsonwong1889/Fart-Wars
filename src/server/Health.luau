-- Server health (masterplan 5.4): whether this server is doing its job,
-- checked every CHECK_SECONDS and published as Workspace's ServerHealth
-- attribute ("OK", "DEGRADED", "FAILING"), logged when it changes and
-- counted (health.<status>). It looks at:
--   * the service loops (Health.loop): one that stops beating is FAILING;
--     an error in a tick is counted and reported, and the loop carries on
--   * errors per minute (Telemetry's, and any script error ScriptContext
--     reports)
--   * the server's frame rate and memory
--   * saving: a DataStore round trip every PROBE_SECONDS (DataService
--     .probe), and players put on temporary profiles since the last check
-- Clients send a small report every minute or so (ClientReport: frame
-- rate, ping, errors, graphics quality), checked and averaged here
-- (client.fps, client.ping, client.errors). Nothing personal is kept.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReleaseConfig = require(Shared.Config.ReleaseConfig)
local Telemetry = require(script.Parent.Telemetry)
local RateLimit = require(script.Parent.RateLimit)

local Health = {}

Health.CHECK_SECONDS = 30
Health.PROBE_SECONDS = 300
Health.LIMITS = table.freeze({
	errorsPerMinute = 20,
	serverFps = 30,
	failingServerFps = 15,
	memoryMb = 3000,
})
-- Clients report this often at most.
Health.CLIENT_REPORT_SECONDS = 25

export type Status = "OK" | "DEGRADED" | "FAILING"
export type Report = {
	status: Status,
	problems: { string },
	version: string,
	channel: string,
	players: number,
	serverFps: number,
	memoryMb: number?,
	errorsPerMinute: number,
	saving: string,
	at: number,
}

local loops: { [string]: { every: number, last: number } } = {}
local frames = 0
local windowStart = os.clock()
local lastErrors = 0
local lastTemporary = 0
local probeOk, probeDetail = true, "not checked yet"
local probe: (() -> (boolean, string))? = nil
local lastReport: Report? = nil
local clientLimit = RateLimit.new(Health.CLIENT_REPORT_SECONDS)
local started = false

local function totalErrors(): number
	local total = 0
	for _, n in Telemetry.snapshot().errors do
		total += n
	end
	return total
end

-- Runs `tick(dt)` every `every` seconds for good, beating as it goes. An
-- error in one tick is counted and re-raised on its own thread (so it
-- shows in the output, and fails a spec), and the loop goes on.
function Health.loop(name: string, every: number, tick: (number) -> ())
	loops[name] = { every = every, last = os.clock() }
	task.spawn(function()
		while true do
			local dt = task.wait(every)
			loops[name].last = os.clock()
			local ok, err = pcall(tick, dt)
			if not ok then
				Telemetry.error(name, err)
				task.spawn(error, `[FW] {name} loop: {tostring(err)}`, 0)
			end
		end
	end)
end

-- Test seam: when a loop last beat (to fake a stall).
function Health.testSetBeat(name: string, at: number)
	local loop = loops[name]
	if loop then
		loop.last = at
	end
end

function Health.loopNames(): { string }
	local names = {}
	for name in loops do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function worse(a: Status, b: Status): Status
	local rank = { OK = 0, DEGRADED = 1, FAILING = 2 }
	return if rank[b] > rank[a] then b else a
end

-- Checks everything now. Returns the report (also published).
function Health.check(): Report
	local status: Status = "OK"
	local problems = {}
	local nowClock = os.clock()
	for _, name in Health.loopNames() do
		local loop = loops[name]
		if nowClock - loop.last > math.max(10, loop.every * 5) then
			status = worse(status, "FAILING")
			table.insert(problems, `{name} loop stopped {math.floor(nowClock - loop.last)}s ago`)
		end
	end
	local elapsed = math.max(nowClock - windowStart, 0.001)
	local fps = frames / elapsed
	-- No frames at all means no frame clock (the specs' stand-in), not a
	-- frozen server: a frozen server wouldn't be running this check.
	local measured = frames > 0
	frames, windowStart = 0, nowClock
	if elapsed >= 5 and measured then
		if fps < Health.LIMITS.failingServerFps then
			status = worse(status, "FAILING")
			table.insert(problems, `server at {math.floor(fps)} FPS`)
		elseif fps < Health.LIMITS.serverFps then
			status = worse(status, "DEGRADED")
			table.insert(problems, `server at {math.floor(fps)} FPS`)
		end
	end
	local errors = totalErrors()
	-- Over at least half a minute, so a check run by hand right after
	-- another doesn't read a few errors as a flood.
	local perMinute = (errors - lastErrors) * 60 / math.max(elapsed, 30)
	lastErrors = errors
	if perMinute > Health.LIMITS.errorsPerMinute then
		status = worse(status, "DEGRADED")
		table.insert(problems, `{math.floor(perMinute)} errors a minute`)
	end
	local okMemory, memory = pcall(Stats.GetTotalMemoryUsageMb, Stats)
	local memoryMb = if okMemory and type(memory) == "number" then memory else nil
	if memoryMb and memoryMb > Health.LIMITS.memoryMb then
		status = worse(status, "DEGRADED")
		table.insert(problems, `{math.floor(memoryMb)} MB of memory`)
	end
	if not probeOk then
		status = worse(status, "DEGRADED")
		table.insert(problems, `saving failed its check: {probeDetail}`)
	end
	local temporary = Telemetry.snapshot().counters["Data.temporaryProfiles"] or 0
	if temporary > lastTemporary then
		status = worse(status, "DEGRADED")
		table.insert(problems, `{temporary - lastTemporary} players on unsaved profiles`)
	end
	lastTemporary = temporary
	local channel = ReleaseConfig.channel(game.PlaceId)
	local report: Report = {
		status = status,
		problems = problems,
		version = ReleaseConfig.VERSION,
		channel = channel,
		players = #Players:GetPlayers(),
		serverFps = math.floor(fps * 10) / 10,
		memoryMb = memoryMb,
		errorsPerMinute = math.floor(perMinute * 10) / 10,
		saving = probeDetail,
		at = os.time(),
	}
	Telemetry.count(`health.{status}`)
	if not lastReport or lastReport.status ~= status then
		Telemetry.log("Health", "status", { status = status, problems = table.concat(problems, "; ") })
		if status ~= "OK" then
			warn(`[FW] server health {status}: {table.concat(problems, "; ")}`)
		end
	end
	lastReport = report
	workspace:SetAttribute("ServerHealth", status)
	return report
end

-- The latest report (checking now if there isn't one).
function Health.report(): Report
	return lastReport or Health.check()
end

-- Test seam: another saving check.
function Health.setProbe(check: () -> (boolean, string))
	probe = check
end

-- Saving's round trip, now. Returns whether it worked.
function Health.probe(): boolean
	if probe then
		local ok, detail = probe()
		probeOk, probeDetail = ok, detail
		if not ok then
			Telemetry.count("health.probeFailures")
		end
	end
	return probeOk
end

local function number(value: unknown, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value or value < low or value > high then
		return nil
	end
	return value
end

-- One client's report: { fps, ping, errors, quality }, each optional.
function Health.clientReport(player: Player, payload: unknown)
	if type(payload) ~= "table" then
		Telemetry.reject("ClientReport", player, "badPayload")
		return
	end
	if not clientLimit:allow(player, "report") then
		Telemetry.reject("ClientReport", player, "tooFast")
		return
	end
	local data = payload :: { [string]: unknown }
	local fps = number(data.fps, 0, 1000)
	local ping = number(data.ping, 0, 10)
	local errors = number(data.errors, 0, 10000)
	local quality = number(data.quality, 0, 21)
	if fps then
		Telemetry.sample("client.fps", fps)
		if fps < 30 then
			Telemetry.count("client.lowFps")
		end
	end
	if ping then
		Telemetry.sample("client.pingMs", ping * 1000)
		if ping > 0.25 then
			Telemetry.count("client.highPing")
		end
	end
	if errors and errors > 0 then
		Telemetry.count("client.errors", math.min(math.floor(errors), 50))
	end
	if quality then
		Telemetry.sample("client.graphicsQuality", quality)
	end
	Telemetry.count("client.reports")
end

-- `options.probe`: the saving check (DataService.probe).
function Health.start(options: { probe: (() -> (boolean, string))? }?)
	if started then
		return
	end
	started = true
	probe = options and options.probe
	workspace:SetAttribute("GameVersion", ReleaseConfig.VERSION)
	workspace:SetAttribute("ReleaseChannel", ReleaseConfig.channel(game.PlaceId))
	RunService.Heartbeat:Connect(function()
		frames += 1
	end)
	ScriptContext.Error:Connect(function(message: string)
		-- Loop errors are counted already, under their loop's name.
		if not string.find(message, "[FW] ", 1, true) then
			Telemetry.error("Script", message)
		end
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local report = remotes:WaitForChild("ClientReport") :: RemoteEvent
	report.OnServerEvent:Connect(Telemetry.guard("ClientReport", Health.clientReport))
	Players.PlayerRemoving:Connect(function(player)
		clientLimit:forget(player)
	end)
	task.spawn(function()
		while true do
			Health.probe()
			task.wait(Health.PROBE_SECONDS)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Health.CHECK_SECONDS)
			Health.check()
		end
	end)
end

return Health
