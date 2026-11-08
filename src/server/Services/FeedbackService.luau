-- Player feedback (FeedbackConfig), behind FeatureFlags.FEEDBACK: the M
-- menu's FEEDBACK window sends a type (Bug, Idea or Other) and up to
-- MAX_LENGTH characters, and each report is kept for the developer with
-- what helps fix a bug: the game version and channel, the place version,
-- the server's job ID, the player's ping (measured here) and frame rate,
-- and the client's last few script errors.
--   * Everything is checked: the type from the list, the text valid UTF-8
--     and cleaned (FeedbackConfig.clean) to MIN_LENGTH..MAX_LENGTH
--     characters, numbers in range; junk is refused and counted, and junk
--     in the optional numbers or errors is dropped.
--   * Limits per player: one report every COOLDOWN_SECONDS and PER_DAY a
--     UTC day, held across servers by a quota entry in the store, and on
--     each server in memory too, so a refusal costs no DataStore request.
--   * Storage: each report under its own key, starting with the user ID
--     (so a data deletion request can find it), in STORE_NAME, and listed
--     by time in the ordered INDEX_NAME, so admins read the newest first
--     (`/fw feedback [n]`, TestControls). Writes retry; if the report can't
--     be saved the player is told, and the day's quota is given back.
--   * Without DataStore access (Studio without API access, an unpublished
--     place) it fails quietly: reports are kept on this server only and
--     the player is thanked as usual.
--   * The text is only for the developer: it's never sent to any client or
--     written to the log (only `/fw feedback` prints it, to the server's
--     output). Nothing personal is kept beyond the user ID: players' names
--     are scrubbed out of the error messages.
--   SendFeedback (RemoteFunction): { kind, text, fps?, ping?, errors?,
--   errorCount? } -> { ok, reason, wait? }
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local FeedbackConfig = require(Shared.Config.FeedbackConfig)
local ReleaseConfig = require(Shared.Config.ReleaseConfig)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local RateLimit = require(Server.RateLimit)

local FeedbackService = {}

-- The server's clock (specs move it).
FeedbackService.now = os.time

export type Result = { ok: boolean, reason: string, wait: number? }
export type Report = {
	id: string,
	at: number,
	userId: number,
	kind: string,
	text: string,
	version: string,
	channel: string,
	placeVersion: number,
	jobId: string,
	pingMs: number?,
	fps: number?,
	errors: { string },
	errorCount: number?,
	state: string?,
	-- In memory only: whether it's in the DataStore too.
	saved: boolean?,
}
type Limit = { last: number, day: number, count: number }

local override: boolean? = nil
local reportStore: any = nil
local indexStore: any = nil
-- "unknown" until the first request, "ok", or "none" (no DataStore access
-- here: memory only, for good).
local storeState = "unknown"
-- This server's reports, oldest first, at most MEMORY_REPORTS.
local recent: { Report } = {}
-- This server's copy of the limits, by user ID (kept after they leave, so
-- rejoining the same server doesn't reset them).
local limits: { [number]: Limit } = {}
local busy: { [Player]: boolean } = {}
local requests = RateLimit.new(FeedbackConfig.REQUEST_SECONDS)
local sequence = 0
local started = false

-- Whether feedback is on (the flag, unless a test says otherwise). Clients
-- see it as Workspace's FeedbackOpen attribute.
function FeedbackService.enabled(): boolean
	if override ~= nil then
		return override
	end
	return FeatureFlags.FEEDBACK == true
end

-- Test seam: feedback on or off whatever the flag says (nil: the flag).
function FeedbackService.testEnable(enabled: boolean?)
	override = enabled
	workspace:SetAttribute("FeedbackOpen", FeedbackService.enabled())
end

-- Test seam: stand-ins for the reports store (UpdateAsync, SetAsync,
-- GetAsync) and the ordered index (SetAsync, GetSortedAsync).
function FeedbackService.setStores(reports: any, index: any)
	reportStore, indexStore = reports, index
	storeState = "ok"
end

-- Test seam: this server forgets its reports and limits, as a fresh
-- server would start (what's in the store stays).
function FeedbackService.testFreshServer()
	table.clear(recent)
	table.clear(limits)
end

local function stores(): (any, any)
	if not reportStore then
		reportStore = DataStoreService:GetDataStore(FeedbackConfig.STORE_NAME)
		indexStore = DataStoreService:GetOrderedDataStore(FeedbackConfig.INDEX_NAME)
	end
	return reportStore, indexStore
end

-- An error that retrying can't fix: Studio without API access, or a place
-- that was never published.
local function hopeless(err: any): boolean
	local message = tostring(err)
	for _, sign in { "Studio access", "publish this place", "403" } do
		if string.find(message, sign, 1, true) then
			return true
		end
	end
	return false
end

-- No DataStore access here: memory only from now on, said once, quietly.
local function noStore()
	if storeState ~= "none" then
		storeState = "none"
		-- Counted as Feedback.memoryOnly.
		Telemetry.log("Feedback", "memoryOnly", { why = "no DataStore access, so reports stay on this server" })
	end
end

-- Runs `request` (DataStore calls, getting the stores included) up to
-- SAVE_ATTEMPTS times. Returns whether it worked; an error that can never
-- go away marks the store as missing instead.
local function attempt(request: () -> ()): boolean
	for try = 1, FeedbackConfig.SAVE_ATTEMPTS do
		local ok, err = pcall(request)
		if ok then
			if storeState == "unknown" then
				storeState = "ok"
			end
			return true
		end
		if hopeless(err) then
			noStore()
			return false
		end
		Telemetry.error("Feedback", err)
		if try < FeedbackConfig.SAVE_ATTEMPTS then
			task.wait(try)
		end
	end
	return false
end

local function result(ok: boolean, reason: string, wait: number?): Result
	return { ok = ok, reason = reason, wait = wait }
end

local function number(value: unknown, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value or value < low or value > high then
		return nil
	end
	return value
end

-- Every player's name and display name, to scrub out of error messages.
local function names(): { string }
	local list = {}
	for _, other in Players:GetPlayers() do
		table.insert(list, other.Name)
		table.insert(list, other.DisplayName)
	end
	return list
end

-- The client's error messages, as kept: strings only, the first
-- MAX_ERRORS, each cut to MAX_ERROR_LENGTH characters, cleaned, with
-- names scrubbed out. Anything else is dropped.
local function errorsFrom(value: unknown): { string }
	local kept = {}
	if type(value) ~= "table" then
		return kept
	end
	local list = value :: { [any]: unknown }
	local who = names()
	for i = 1, FeedbackConfig.MAX_ERRORS do
		local message = list[i]
		if type(message) == "string" then
			-- Cut by bytes first, so a huge one costs nothing.
			local text = FeedbackConfig.cut(string.sub(message, 1, FeedbackConfig.MAX_ERROR_LENGTH * 4), FeedbackConfig.MAX_ERROR_LENGTH)
			text = FeedbackConfig.scrub(FeedbackConfig.clean(text), who)
			if text ~= "" then
				table.insert(kept, text)
			end
		end
	end
	return kept
end

export type Draft = {
	kind: string,
	text: string,
	pingMs: number?,
	fps: number?,
	errors: { string },
	errorCount: number?,
}

-- Checks a payload from `player`'s window. Returns what would be kept, or
-- nil and why not ("badPayload", "badKind", "empty", "tooLong").
function FeedbackService.validate(player: Player, payload: unknown): (Draft?, string)
	if type(payload) ~= "table" then
		return nil, "badPayload"
	end
	local data = payload :: { [any]: unknown }
	local kind = data.kind
	if type(kind) ~= "string" or not table.find(FeedbackConfig.KINDS, kind) then
		return nil, "badKind"
	end
	local raw = data.text
	if type(raw) ~= "string" then
		return nil, "badPayload"
	end
	if #raw > FeedbackConfig.MAX_BYTES then
		return nil, "tooLong"
	end
	if utf8.len(raw) == nil then
		return nil, "badPayload"
	end
	local text = FeedbackConfig.clean(raw)
	local length = FeedbackConfig.length(text)
	if length < FeedbackConfig.MIN_LENGTH then
		return nil, "empty"
	elseif length > FeedbackConfig.MAX_LENGTH then
		return nil, "tooLong"
	end
	-- The ping measured here, or the client's own if that's unavailable.
	local okPing, measured = pcall(player.GetNetworkPing, player)
	local ping = (if okPing then number(measured, 0, 10) else nil) or number(data.ping, 0, 10)
	local fps = number(data.fps, 0, 1000)
	local errorCount = number(data.errorCount, 0, 1e6)
	return {
		kind = kind,
		text = text,
		pingMs = if ping then math.floor(ping * 1000 + 0.5) else nil,
		fps = if fps then math.floor(fps * 10 + 0.5) / 10 else nil,
		errors = errorsFrom(data.errors),
		errorCount = if errorCount then math.floor(errorCount) else nil,
	}, "ok"
end

local function dayOf(at: number): number
	return at // 86400
end

-- This server's limits for `userId` at `at`: nil if a report may go, or
-- why not (and the seconds to wait).
local function checkLimits(userId: number, at: number): (string?, number?)
	local limit = limits[userId]
	if not limit then
		return nil, nil
	end
	local since = at - limit.last
	if since >= 0 and since < FeedbackConfig.COOLDOWN_SECONDS then
		return "tooSoon", FeedbackConfig.COOLDOWN_SECONDS - since
	end
	if limit.day == dayOf(at) and limit.count >= FeedbackConfig.PER_DAY then
		return "tooMany", nil
	end
	return nil, nil
end

local function noteLimits(userId: number, at: number)
	local limit = limits[userId]
	local day = dayOf(at)
	if not limit or limit.day ~= day then
		limit = { last = at, day = day, count = 0 }
		limits[userId] = limit
	end
	limit.last = at
	limit.count += 1
end

local function quotaKey(userId: number): string
	return `quota_{userId}`
end

-- The same limits across servers, in the store: takes one of today's
-- reports for `userId` (nil), or says why not ("tooSoon" with the seconds
-- to wait, "tooMany", or "error" if the store didn't answer). `before` is
-- what to give back if the report then can't be saved.
local function claimQuota(userId: number, at: number): (string?, number?, { [string]: any }?)
	local refused: string?, waitFor: number?, before: { [string]: any }? = nil, nil, nil
	local ok = attempt(function()
		local reports = stores()
		reports:UpdateAsync(quotaKey(userId), function(old)
			refused, waitFor = nil, nil
			local entry = if type(old) == "table" then old else {}
			before = entry
			local last = tonumber(entry.last) or 0
			local day = dayOf(at)
			local count = if tonumber(entry.day) == day then math.max(0, tonumber(entry.count) or 0) else 0
			local since = at - last
			if since >= 0 and since < FeedbackConfig.COOLDOWN_SECONDS then
				refused, waitFor = "tooSoon", FeedbackConfig.COOLDOWN_SECONDS - since
				return nil
			end
			if count >= FeedbackConfig.PER_DAY then
				refused = "tooMany"
				return nil
			end
			return { day = day, count = count + 1, last = at }, { userId }
		end)
	end)
	if not ok then
		return "error", nil, nil
	end
	return refused, waitFor, before
end

-- Gives back the report taken at `at`, if nothing has changed since.
local function returnQuota(userId: number, at: number, before: { [string]: any })
	attempt(function()
		local reports = stores()
		reports:UpdateAsync(quotaKey(userId), function(old)
			if type(old) ~= "table" or old.last ~= at then
				return nil
			end
			return { day = tonumber(before.day) or 0, count = math.max(0, tonumber(before.count) or 0), last = tonumber(before.last) or 0 }, { userId }
		end)
	end)
end

local function remember(report: Report)
	table.insert(recent, report)
	while #recent > FeedbackConfig.MEMORY_REPORTS do
		table.remove(recent, 1)
	end
end

local function jobId(): string
	return if game.JobId ~= "" then game.JobId else "studio"
end

local function newId(userId: number, at: number): string
	sequence += 1
	local guid = string.gsub(HttpService:GenerateGUID(false), "-", "")
	return `{userId}_{at}_{string.sub(guid, -8)}{sequence}`
end

-- A report from `player`: checked, limited, stored. The remote's answer.
function FeedbackService.submit(player: Player, payload: unknown): Result
	if not FeedbackService.enabled() then
		return result(false, "off")
	end
	if busy[player] then
		return result(false, "busy")
	end
	if not requests:allow(player, "send") then
		Telemetry.reject("SendFeedback", player, "tooFast")
		return result(false, "tooFast")
	end
	local draft, why = FeedbackService.validate(player, payload)
	if not draft then
		Telemetry.reject("SendFeedback", player, why)
		return result(false, why)
	end
	local userId = player.UserId
	local at = FeedbackService.now()
	local limited, waitFor = checkLimits(userId, at)
	if limited then
		Telemetry.reject("SendFeedback", player, limited)
		return result(false, limited, waitFor)
	end
	busy[player] = true
	local ok, answer = pcall(function(): Result
		local before: { [string]: any }? = nil
		if storeState ~= "none" then
			local refused, wait, previous = claimQuota(userId, at)
			if refused == "tooSoon" or refused == "tooMany" then
				-- Sent from another server: remember it here too.
				local limit = limits[userId] or { last = 0, day = dayOf(at), count = 0 }
				limits[userId] = limit
				if refused == "tooSoon" then
					limit.last = at - (FeedbackConfig.COOLDOWN_SECONDS - (wait :: number))
				else
					limit.day, limit.count = dayOf(at), FeedbackConfig.PER_DAY
				end
				Telemetry.reject("SendFeedback", player, refused)
				return result(false, refused, wait)
			elseif refused == "error" and storeState ~= "none" then
				Telemetry.count("Feedback.saveFailures")
				return result(false, "error")
			end
			before = previous
		end
		local state = player:GetAttribute("State")
		local report: Report = {
			id = newId(userId, at),
			at = at,
			userId = userId,
			kind = draft.kind,
			text = draft.text,
			version = ReleaseConfig.VERSION,
			channel = ReleaseConfig.channel(game.PlaceId),
			placeVersion = tonumber(game.PlaceVersion) or 0,
			jobId = jobId(),
			pingMs = draft.pingMs,
			fps = draft.fps,
			errors = draft.errors,
			errorCount = draft.errorCount,
			state = if type(state) == "string" then state else nil,
		}
		local saved = false
		if storeState ~= "none" then
			saved = attempt(function()
				local reports = stores()
				reports:SetAsync(report.id, report, { userId })
			end)
			if saved then
				if not attempt(function()
					local _, index = stores()
					index:SetAsync(report.id, at)
				end) then
					-- Kept, just not listed: the store still has it.
					Telemetry.count("Feedback.indexFailures")
				end
			elseif storeState ~= "none" then
				Telemetry.count("Feedback.saveFailures")
				if before then
					returnQuota(userId, at, before)
				end
				return result(false, "error")
			end
		end
		local kept = table.clone(report)
		kept.saved = saved
		remember(kept)
		noteLimits(userId, at)
		-- Counted as Feedback.sent, and by type.
		Telemetry.count(`Feedback.kind.{draft.kind}`)
		Telemetry.log("Feedback", "sent", { player = player, kind = draft.kind, chars = FeedbackConfig.length(draft.text), saved = saved })
		return result(true, "sent")
	end)
	busy[player] = nil
	if not ok then
		Telemetry.error("Feedback", answer)
		return result(false, "error")
	end
	return answer
end

-- Reports in the store, newest first (nil if it can't be read).
local function readStored(count: number): { Report }?
	local list: { Report } = {}
	local ok = attempt(function()
		table.clear(list)
		local reports, index = stores()
		local pages = index:GetSortedAsync(false, count)
		for _, entry in pages:GetCurrentPage() do
			local okRead, record = pcall(reports.GetAsync, reports, entry.key)
			if okRead and type(record) == "table" and type(record.text) == "string" then
				table.insert(list, record)
			end
		end
	end)
	return if ok then list else nil
end

-- The newest `count` reports (READ_DEFAULT if nil, at most READ_MAX),
-- newest first: the store's with this server's own, and where they're
-- from: "saved" (the store), "server" (no DataStore here: this server's
-- only) or "unreadable" (the store didn't answer: this server's only).
function FeedbackService.latest(count: number?): ({ Report }, string)
	local wanted = if count and count == count then count else FeedbackConfig.READ_DEFAULT
	local n = math.clamp(math.floor(wanted), 1, FeedbackConfig.READ_MAX)
	local list: { Report } = {}
	local stored = if storeState ~= "none" then readStored(n) else nil
	local source = if stored then "saved" elseif storeState == "none" then "server" else "unreadable"
	local seen = {}
	for _, report in stored or {} do
		seen[tostring(report.id)] = true
		table.insert(list, report)
	end
	-- This server's own too: unsaved ones, and any the index missed.
	for _, report in recent do
		if not seen[report.id] then
			table.insert(list, report)
		end
	end
	-- (A stored record is only ever one of ours, but a damaged one mustn't
	-- break the read.)
	table.sort(list, function(a, b)
		local atA, atB = tonumber(a.at) or 0, tonumber(b.at) or 0
		if atA ~= atB then
			return atA > atB
		end
		return tostring(a.id) > tostring(b.id)
	end)
	while #list > n do
		table.remove(list)
	end
	return list, source
end

local function age(seconds: number): string
	seconds = math.max(0, seconds)
	if seconds < 60 then
		return `{seconds}s`
	elseif seconds < 3600 then
		return `{seconds // 60}m`
	elseif seconds < 86400 then
		return `{seconds // 3600}h`
	end
	return `{seconds // 86400}d`
end

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

local function stamp(at: number): string
	local t = os.date("!*t", at) :: any
	return string.format("%04d-%02d-%02d %02d:%02d UTC", t.year, t.month, t.day, t.hour, t.min)
end

-- `/fw feedback [n]`: the newest reports as lines for the server's output
-- (where only the developer sees them), and a one-line summary for the
-- admin's screen, which never includes anyone's words.
function FeedbackService.readout(count: number?): (boolean, string, { string })
	local list, source = FeedbackService.latest(count)
	local where = if source == "saved" then "saved"
		elseif source == "server" then "this server only: no DataStore access"
		else "this server only: the DataStore didn't answer"
	if #list == 0 then
		return true, `no feedback yet ({where})`, { `[FW] feedback: none yet ({where})` }
	end
	local lines = { `[FW] feedback: the {#list} newest ({where})` }
	local kinds: { [string]: number } = {}
	local now = FeedbackService.now()
	for i, report in list do
		local kind = tostring(report.kind)
		kinds[kind] = (kinds[kind] or 0) + 1
		local at = tonumber(report.at) or 0
		local ping = if report.pingMs then `{report.pingMs}ms` else "ping ?"
		local fps = if report.fps then `{report.fps} FPS` else "FPS ?"
		local errors = if type(report.errors) == "table" then report.errors else {}
		table.insert(lines, `[FW] feedback {i}. {stamp(at)} ({age(now - at)} ago) {string.upper(kind)} `
			.. `user {report.userId} v{report.version} ({report.channel}) place v{report.placeVersion} job {report.jobId}, `
			.. `{ping}, {fps}, {plural(tonumber(report.errorCount) or #errors, "error")}{if report.state then ", " .. tostring(report.state) else ""}`
			.. `{if report.saved == false then " (not saved)" else ""}`)
		table.insert(lines, `[FW]     "{report.text}"`)
		for _, message in errors do
			table.insert(lines, `[FW]     error: {message}`)
		end
	end
	local counts = {}
	for _, kind in FeedbackConfig.KINDS do
		if kinds[kind] then
			table.insert(counts, `{kinds[kind]} {string.lower(kind)}`)
		end
	end
	local newest = tonumber(list[1].at) or now
	local summary = `{#list} newest ({table.concat(counts, ", ")}; latest {age(now - newest)} ago, {where}): `
		.. "read them in the server output (F9 > Server)"
	return true, summary, lines
end

function FeedbackService.start()
	if started then
		return
	end
	started = true
	workspace:SetAttribute("FeedbackOpen", FeedbackService.enabled())
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SendFeedback") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, payload: unknown)
		Telemetry.count("remote.in.SendFeedback")
		local ok, answer = pcall(FeedbackService.submit, player, payload)
		if not ok then
			Telemetry.error("Feedback", answer)
			return result(false, "error")
		end
		return answer
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		requests:forget(player)
	end)
end

return FeedbackService
