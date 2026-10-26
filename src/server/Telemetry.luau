-- Observability for every service: structured log lines, counters, errors
-- per service, rejected requests per remote and reason, and the first-
-- session metrics the masterplan asks for (time to first shot, first hit,
-- first elimination, session length). Kept in memory for this server; read
-- it with TestControls (`/fw stats`) or Telemetry.snapshot(). Nothing here
-- holds personal data beyond user IDs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)

local Telemetry = {}

local counters: { [string]: number } = {}
local errors: { [string]: number } = {}
local rejects: { [string]: { [string]: number } } = {}
-- Rejection times per player over the last minute, for abnormal rates.
local recentRejects: { [Player]: { number } } = setmetatable({}, { __mode = "k" }) :: any
local flagged: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local joinedAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local firsts: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local timings: { [string]: { count: number, total: number } } = {}
local samples: { [string]: { count: number, total: number } } = {}
local startedAt = workspace:GetServerTimeNow()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function format(fields: { [string]: any }?): string
	if not fields then
		return ""
	end
	local keys = {}
	for key in fields do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		local value = fields[key]
		if typeof(value) == "Instance" then
			value = if value:IsA("Player") then value.UserId else value.Name
		end
		table.insert(parts, `{key}={tostring(value)}`)
	end
	return " " .. table.concat(parts, " ")
end

function Telemetry.count(key: string, amount: number?)
	counters[key] = (counters[key] or 0) + (amount or 1)
end

-- One structured line: "[FW] service event key=value ...".
function Telemetry.log(service: string, event: string, fields: { [string]: any }?)
	Telemetry.count(`{service}.{event}`)
	if FeatureFlags.DEBUG_LOGS then
		print(`[FW] {service} {event}{format(fields)}`)
	end
end

function Telemetry.error(service: string, err: any)
	errors[service] = (errors[service] or 0) + 1
	warn(`[FW] {service} error: {tostring(err)}`)
end

-- Runs a remote handler, counting (not spreading) any error in it.
function Telemetry.guard(service: string, handler: (...any) -> ()): (...any) -> ()
	return function(...)
		local ok, err = pcall(handler, ...)
		if not ok then
			Telemetry.error(service, err)
		end
	end
end

-- A request the server turned down. Too many from one player in a minute
-- gets them logged once as abnormal.
function Telemetry.reject(remote: string, player: Player, reason: string)
	rejects[remote] = rejects[remote] or {}
	rejects[remote][reason] = (rejects[remote][reason] or 0) + 1
	local at = now()
	local recent = recentRejects[player] or {}
	recentRejects[player] = recent
	table.insert(recent, at)
	while recent[1] and at - recent[1] > 60 do
		table.remove(recent, 1)
	end
	if #recent > GameConfig.ABNORMAL_REJECTS_PER_MINUTE and not flagged[player] then
		flagged[player] = true
		Telemetry.count("abnormal.players")
		warn(`[FW] abnormal request rate from {player.UserId}: {#recent} rejected in a minute (latest {remote}/{reason})`)
	end
	if FeatureFlags.DEBUG_LOGS then
		print(`[FW] reject {remote} {reason} player={player.UserId}`)
	end
end

function Telemetry.isFlagged(player: Player): boolean
	return flagged[player] == true
end

-- Session metrics.

function Telemetry.joined(player: Player)
	joinedAt[player] = now()
	firsts[player] = {}
	Telemetry.count("session.joins")
end

-- Records how long into the session `player` first did `kind` ("shot",
-- "hit", "elimination"), once per session.
function Telemetry.first(player: Player, kind: string)
	local seen = firsts[player]
	local started = joinedAt[player]
	if not (seen and started) or seen[kind] then
		return
	end
	seen[kind] = true
	local timing = timings[kind] or { count = 0, total = 0 }
	timings[kind] = timing
	timing.count += 1
	timing.total += now() - started
end

-- Adds one measurement of `kind` (seconds) to its running average.
function Telemetry.time(kind: string, seconds: number)
	local timing = timings[kind] or { count = 0, total = 0 }
	timings[kind] = timing
	timing.count += 1
	timing.total += seconds
end

-- Adds one value of `kind` (not a time: coins a session, a balance) to its
-- running average.
function Telemetry.sample(kind: string, value: number)
	local entry = samples[kind] or { count = 0, total = 0 }
	samples[kind] = entry
	entry.count += 1
	entry.total += value
end

function Telemetry.left(player: Player)
	local started = joinedAt[player]
	if started then
		local timing = timings.session or { count = 0, total = 0 }
		timings.session = timing
		timing.count += 1
		timing.total += now() - started
	end
	joinedAt[player] = nil
	firsts[player] = nil
end

-- Everything so far, as plain tables: counters, errors, rejects, the
-- average seconds of each timing (firsts per session, time to explosion,
-- session length) with how many there were, and the average of each sample.
function Telemetry.snapshot(): { [string]: any }
	local averages = {}
	for kind, timing in timings do
		averages[kind] = { players = timing.count, averageSeconds = timing.total / math.max(1, timing.count) }
	end
	local sampleAverages = {}
	for kind, entry in samples do
		sampleAverages[kind] = { count = entry.count, average = entry.total / math.max(1, entry.count) }
	end
	local rejectCopy = {}
	for remote, reasons in rejects do
		rejectCopy[remote] = table.clone(reasons)
	end
	return {
		uptimeSeconds = now() - startedAt,
		counters = table.clone(counters),
		errors = table.clone(errors),
		rejects = rejectCopy,
		firsts = averages,
		samples = sampleAverages,
	}
end

return Telemetry
