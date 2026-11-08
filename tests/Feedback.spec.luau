-- Player feedback (FeedbackService and the FEEDBACK window), with one client
-- and a second player:
--   * Studio without API access: a report is sent quietly (no errors),
--     kept on this server only, and read back as such
--   * validation: the three types only; the text valid UTF-8, cleaned
--     (control characters, invisible marks, extra blank lines) and 3 to 300
--     characters; numbers in range or dropped; the ping measured by the
--     server (the client's only as a fallback); errors strings only, five
--     at most, cut to 200 characters, every player's name scrubbed out
--   * junk payloads of every shape refused and counted, never stored
--   * storage in a stand-in DataStore (JSON, like the real one): the report
--     with the versions, job ID, ping, FPS and errors, under a key starting
--     with the user ID and tagged with it, listed by time in the ordered
--     index; no names anywhere in it
--   * limits: one every two minutes (with the wait), five a UTC day, more
--     the next day; held across servers by the store; refusals cost no
--     DataStore request; one request a second; one at a time
--   * outages: retried, then the player is told and the day's quota given
--     back; a report saved but not indexed is still read back
--   * /fw feedback: the newest first, every word in the server's output,
--     the admin's line counts and ages only; how many; off with the flag
--   * the window: FEEDBACK in the M menu, the types, the 300-character cut
--     and count, SEND's answers (thanks, then the wait), the mouse freed,
--     the window taking its clicks, the client's recent errors (scrubbed)
--     going along, and the text never reaching any client or the log
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

-- A published server, so the report can say which one.
game.JobId = "job-feedback-42"
game.PlaceVersion = 45
Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
require(server.Services.BotDirector).testSetEnabled(false)
local Shared = ReplicatedStorage.Shared
local FeedbackConfig = require(Shared.Config.FeedbackConfig)
local ReleaseConfig = require(Shared.Config.ReleaseConfig)
local Data = require(server.Services.DataService)
local Feedback = require(server.Services.FeedbackService)
local Telemetry = require(server.Telemetry)
local TestControls = require(server.TestControls)
local Remotes = ReplicatedStorage.Remotes

local profiles: { [string]: any } = {}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		local result = transform(profiles[key])
		if result ~= nil then
			profiles[key] = result
		end
		return result
	end,
})
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function rejects(reason: string): number
	local list = Telemetry.snapshot().rejects.SendFeedback
	return list and list[reason] or 0
end
local function feedbackErrors(): number
	return Telemetry.snapshot().errors.Feedback or 0
end

-- Everything printed or warned from here on, and everything sent to any
-- client, to check what never shows up in either.
local globals = getmetatable(getfenv(1)).__index
local printed: { string } = {}
local realPrint, realWarn = globals.print, globals.warn
local function capture(...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	table.insert(printed, table.concat(parts, " "))
end
globals.print = function(...)
	capture(...)
	realPrint(...)
end
globals.warn = function(...)
	capture(...)
	realWarn(...)
end
local toClients: { any } = {}
for _, remote in Remotes:GetChildren() do
	if remote:IsA("RemoteEvent") then
		remote.FiredToClient:Connect(function(player, ...)
			table.insert(toClients, { player = player, args = { ... } })
		end)
	end
end
local function holds(value: any, needle: string, seen: { [any]: boolean }?): boolean
	if type(value) == "string" then
		return string.find(value, needle, 1, true) ~= nil
	elseif type(value) == "table" then
		local visited = seen or {}
		if visited[value] then
			return false
		end
		visited[value] = true
		for key, item in value do
			if holds(key, needle, visited) or holds(item, needle, visited) then
				return true
			end
		end
	end
	return false
end
local function anyClientGot(needle: string): boolean
	for _, sent in toClients do
		if holds(sent.args, needle) then
			return true
		end
	end
	return false
end
local function anyLineHas(needle: string, from: number?): boolean
	for i = from or 1, #printed do
		if string.find(printed[i], needle, 1, true) then
			return true
		end
	end
	return false
end

local me = Instance.new("Player")
me.Name = "StinkyTester"
me.DisplayName = "Stinky Legend"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
local bob = Instance.new("Player")
bob.Name = "Bobsworth"
bob.DisplayName = "Bob the Sharter"
bob.UserId = 2
bob.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
task.wait(0.5)
local Window = require(client.Controllers.FeedbackController)
local Home = require(client.Controllers.HomeController)
local ClientHealth = require(client.Controllers.HealthController)
local MouseLock = require(client.MouseLock)
local NAMES = { "StinkyTester", "Stinky Legend", "Bobsworth", "Bob the Sharter" }
check(FeedbackConfig.MAX_LENGTH == 300 and FeedbackConfig.COOLDOWN_SECONDS == 120 and FeedbackConfig.PER_DAY == 5, "300 characters, one every two minutes, five a day")
check(table.concat(FeedbackConfig.KINDS, ",") == "Bug,Idea,Other", "Bug, Idea or Other")
check(workspace:GetAttribute("FeedbackOpen") == true, "on as shipped (the flag), and the clients know")

-- The server, as the remote calls it, a second apart (one request a second).
local function send(player: Player, payload: any): { [string]: any }
	task.wait(FeedbackConfig.REQUEST_SECONDS + 0.05)
	return (Remotes.SendFeedback :: any).OnServerInvoke(player, payload)
end
local serial = 0
-- The wait a refusal reports is the two minutes less the time since the last
-- report (about as long as send waits).
local function waited(answer: { [string]: any }, low: number, high: number): boolean
	return type(answer.wait) == "number" and answer.wait >= low and answer.wait <= high
end
local function report(kind: string?, text: string?): { [string]: any }
	serial += 1
	return { kind = kind or "Bug", text = text or `report number {serial}: the gas meter got stuck`, fps = 58.26, ping = 0.2, errorCount = 1, errors = { "Workspace.Bobsworth.HumanoidRootPart is not a valid member" } }
end

-- Studio without API access (the harness's DataStores refuse, as Studio's
-- do): sent, quietly, and kept on this server.
local quiet = send(bob, report("Idea", "a quiet idea from studio"))
check(quiet.ok and quiet.reason == "sent", "without DataStores it still goes through")
check(feedbackErrors() == 0 and counter("Feedback.memoryOnly") == 1, "quietly: no errors, one note that it's memory only")
local list, source = Feedback.latest()
check(#list == 1 and source == "server" and list[1].saved == false and list[1].text == "a quiet idea from studio", "kept on this server, not saved")
local ok, summary = Feedback.readout()
check(ok and string.find(summary, "this server only", 1, true) and string.find(summary, "1 idea", 1, true), "and /fw feedback says so")
local again = send(bob, report())
check(not again.ok and again.reason == "tooSoon" and waited(again, 115, 120), "the limits hold without DataStores too")

-- The stand-in DataStore from here on: JSON like the real one, user ID tags,
-- an ordered index, every request counted, and failures on demand.
local stored: { [string]: string } = {}
local tags: { [string]: any } = {}
local ordered: { [string]: number } = {}
local requests, writes = 0, 0
local fail = { UpdateAsync = 0, SetAsync = 0, GetAsync = 0, IndexSetAsync = 0, GetSortedAsync = 0 }
local latency = 0
local function call(name: string)
	requests += 1
	if latency > 0 then
		task.wait(latency)
	end
	if fail[name] > 0 then
		fail[name] -= 1
		error("503: DataStore request failed (test outage)")
	end
end
local function decode(key: string): any
	local text = stored[key]
	return if text then HttpService:JSONDecode(text) else nil
end
local reportStore = {
	GetAsync = function(_, key: string)
		call("GetAsync")
		return decode(key)
	end,
	SetAsync = function(_, key: string, value: any, userIds: any)
		call("SetAsync")
		stored[key] = HttpService:JSONEncode(value)
		tags[key] = userIds
		writes += 1
	end,
	UpdateAsync = function(_, key: string, transform: (any) -> ...any)
		call("UpdateAsync")
		local value, userIds = transform(decode(key))
		if value ~= nil then
			stored[key] = HttpService:JSONEncode(value)
			tags[key] = userIds
			writes += 1
		end
		return value
	end,
}
local indexStore = {
	SetAsync = function(_, key: string, value: any)
		call("IndexSetAsync")
		assert(type(value) == "number" and value % 1 == 0, "ordered values are whole numbers")
		assert(#key <= 50, "keys fit a DataStore")
		ordered[key] = value
		writes += 1
	end,
	GetSortedAsync = function(_, ascending: boolean, pageSize: number)
		call("GetSortedAsync")
		local entries = {}
		for key, value in ordered do
			table.insert(entries, { key = key, value = value })
		end
		table.sort(entries, function(a, b)
			if a.value ~= b.value then
				return if ascending then a.value < b.value else a.value > b.value
			end
			return a.key > b.key
		end)
		local page = { table.unpack(entries, 1, math.min(pageSize, #entries)) }
		return {
			IsFinished = #entries <= pageSize,
			GetCurrentPage = function()
				return page
			end,
		}
	end,
}
Feedback.setStores(reportStore, indexStore)
Feedback.testFreshServer()
local offset = 0
Feedback.now = function()
	return os.time() + offset
end
local function reportKeys(): { string }
	local keys = {}
	for key in stored do
		if not string.find(key, "^quota_") then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

-- Validation, on what it would keep.
local draft, why = Feedback.validate(bob, {
	kind = "Bug",
	text = "  the gas meter\0 got stuck\r\n\r\n\r\n\r\nat 75%\t!  \226\128\174",
	fps = 58.26,
	ping = 0.2,
	errorCount = 7.9,
	errors = {
		"Players.StinkyTester.PlayerScripts.Client.Controllers.HUDController:45: attempt to index nil with 'Text'",
		"Bob the Sharter's label broke",
	},
})
check(draft and why == "ok", "a good report passes")
check(draft.text == "the gas meter got stuck\n\nat 75% !", `cleaned: control characters, invisible marks, extra blank lines and spaces gone ({draft.text})`)
check(draft.pingMs == 60, "the ping the server measures (60 ms), not the client's say-so")
check(draft.fps == 58.3 and draft.errorCount == 7, "FPS to a tenth, the error count whole")
check(draft.errors[1] == "Players.<player>.PlayerScripts.Client.Controllers.HUDController:45: attempt to index nil with 'Text'", "the reporter's name scrubbed from errors")
check(draft.errors[2] == "<player>'s label broke", "and everyone else's (display names too)")
local fallback = Feedback.validate({ GetNetworkPing = function()
	error("unavailable")
end } :: any, { kind = "Other", text = "abc", ping = 0.25 })
check(fallback and fallback.pingMs == 250, "the client's ping only when the server can't measure one")
for _, kind in FeedbackConfig.KINDS do
	check(Feedback.validate(bob, { kind = kind, text = "abc" }) ~= nil, `{kind} is a type`)
end
local function reason(payload: any): string
	local _, said = Feedback.validate(bob, payload)
	return said
end
check(reason({ kind = "bug", text = "abc" }) == "badKind" and reason({ kind = "Spam", text = "abc" }) == "badKind", "only the listed types, exactly")
check(reason({ text = "abc" }) == "badKind" and reason({ kind = 1, text = "abc" }) == "badKind", "a type is required")
check(reason({ kind = "Bug" }) == "badPayload" and reason({ kind = "Bug", text = 42 }) == "badPayload" and reason({ kind = "Bug", text = { "abc" } }) == "badPayload", "text must be text")
check(reason({ kind = "Bug", text = "" }) == "empty" and reason({ kind = "Bug", text = " \n\t \r\n " }) == "empty" and reason({ kind = "Bug", text = "ab" }) == "empty", "empty or too short")
check(reason({ kind = "Bug", text = "\226\128\139\226\128\139\226\128\139\226\128\139" }) == "empty", "invisible characters don't count")
check(reason({ kind = "Bug", text = string.rep("é", 300) }) == "ok", "300 characters (600 bytes) is fine")
check(reason({ kind = "Bug", text = string.rep("a", 301) }) == "tooLong", "301 is too long")
check(reason({ kind = "Bug", text = string.rep("a", 50000) }) == "tooLong", "a huge one is refused by size")
check(reason({ kind = "Bug", text = "bad\255bytes" }) == "badPayload", "text that isn't UTF-8")
local numbers = assert(Feedback.validate(bob, { kind = "Bug", text = "abc", fps = 0 / 0, errorCount = -1 }))
check(numbers.fps == nil and numbers.errorCount == nil, "NaN and negative numbers are dropped")
numbers = assert(Feedback.validate(bob, { kind = "Bug", text = "abc", fps = math.huge, errorCount = "7" }))
check(numbers.fps == nil and numbers.errorCount == nil, "infinite and non-numbers too")
check(#assert(Feedback.validate(bob, { kind = "Bug", text = "abc", errors = "oops" })).errors == 0, "errors that aren't a list are dropped")
local mixed = assert(Feedback.validate(bob, { kind = "Bug", text = "abc", errors = { 1, true, { "x" }, "a real one", "" } }))
check(#mixed.errors == 1 and mixed.errors[1] == "a real one", "only text errors are kept")
local many = {}
for i = 1, 40 do
	many[i] = `error {i}`
end
check(#assert(Feedback.validate(bob, { kind = "Bug", text = "abc", errors = many })).errors == FeedbackConfig.MAX_ERRORS, "five errors at most")
local long = assert(Feedback.validate(bob, { kind = "Bug", text = "abc", errors = { string.rep("x", 100000), "half\255done" } }))
check(FeedbackConfig.length(long.errors[1]) == FeedbackConfig.MAX_ERROR_LENGTH and long.errors[2] == "half", "each cut to 200 characters, bad bytes dropped")

-- Junk through the remote: refused, counted, and nothing stored.
local junk = {
	{ nil, "badPayload" },
	{ "lag", "badPayload" },
	{ 42, "badPayload" },
	{ true, "badPayload" },
	{ {}, "badKind" },
	{ { kind = "Bug", text = string.rep("💨", 400) }, "tooLong" },
	{ { kind = "Bug", text = "   " }, "empty" },
	{ { kind = "Idea!", text = "valid words" }, "badKind" },
	{ { kind = "Bug", text = "\255\254\253" }, "badPayload" },
	{ { [1] = "Bug", [2] = "words" }, "badKind" },
	{ { kind = { "Bug" }, text = "words" }, "badKind" },
}
local before = Telemetry.snapshot().rejects.SendFeedback or {}
local refusedBefore = {}
for name, n in before do
	refusedBefore[name] = n
end
for i, case in junk do
	local answer = send(bob, case[1])
	check(not answer.ok and answer.reason == case[2], `junk {i} refused as {case[2]} (got {answer.reason})`)
end
check(rejects("badPayload") - (refusedBefore.badPayload or 0) == 5 and rejects("badKind") - (refusedBefore.badKind or 0) == 4, "and counted")
check(next(stored) == nil and requests == 0, "nothing stored, no DataStore request")
local spam = (Remotes.SendFeedback :: any).OnServerInvoke(bob, "again")
check(spam.reason == "tooFast" and rejects("tooFast") == 1, "one request a second")

-- Storage.
local firstLine = #printed
local sent = send(bob, { kind = "Bug", text = "  the dash went THROUGH the wall by the throne  ", fps = 61.04, ping = 3, errorCount = 2, errors = { "Players.Bobsworth.PlayerScripts.Client:9: oops" } })
check(sent.ok and sent.reason == "sent" and sent.wait == nil, "sent")
local keys = reportKeys()
check(#keys == 1 and string.sub(keys[1], 1, 2) == "2_", "one report, its key starting with the user ID")
local record = decode(keys[1])
check(record.kind == "Bug" and record.text == "the dash went THROUGH the wall by the throne", "the type and the cleaned text")
check(record.userId == 2 and record.at == Feedback.now(), "who and when")
check(record.version == ReleaseConfig.VERSION and record.channel == "dev", "the game version and channel")
check(record.placeVersion == 45 and record.jobId == "job-feedback-42", "the place version and the server's job ID")
check(record.pingMs == 60 and record.fps == 61, "the player's ping and FPS")
check(record.errorCount == 2 and #record.errors == 1 and record.errors[1] == "Players.<player>.PlayerScripts.Client:9: oops", "the client's errors, scrubbed")
check(type(record.state) == "string" and record.saved == nil, "the player's state; nothing that's memory only")
check(type(tags[keys[1]]) == "table" and tags[keys[1]][1] == 2, "tagged with the user ID (for data deletion requests)")
check(ordered[keys[1]] == record.at, "listed by time in the index")
local quota = decode("quota_2")
check(quota and quota.count == 1 and quota.last == record.at and quota.day == record.at // 86400 and tags.quota_2[1] == 2, "the day's quota, in the store")
for _, name in NAMES do
	for key, text in stored do
		check(not string.find(text, name, 1, true), `no "{name}" in {key}`)
	end
	check(not anyLineHas(name, firstLine + 1), `no "{name}" in the log`)
end
check(not anyLineHas("THROUGH the wall", firstLine + 1), "the text isn't logged")
check(anyLineHas("[FW] Feedback sent", firstLine + 1) and anyLineHas("player=2", firstLine + 1), "the log has the user ID only")

-- Limits.
local cost = requests
local soon = send(bob, report())
check(not soon.ok and soon.reason == "tooSoon" and waited(soon, 115, 120), "again at once: too soon, about two minutes to wait")
offset += 100
soon = send(bob, report())
check(soon.reason == "tooSoon" and waited(soon, 14, 19), "100 seconds later: under 20 to go")
check(requests == cost, "refusals cost no DataStore request")
for n = 2, FeedbackConfig.PER_DAY do
	offset += FeedbackConfig.COOLDOWN_SECONDS
	local answer = send(bob, report())
	check(answer.ok, `report {n} of the day`)
end
offset += FeedbackConfig.COOLDOWN_SECONDS
cost = requests
local done = send(bob, report())
check(not done.ok and done.reason == "tooMany" and done.wait == nil, "a sixth: that's all for today")
check(requests == cost and #reportKeys() == FeedbackConfig.PER_DAY, "without asking the store; five stored")
-- Another server: its memory is empty, the store remembers.
Feedback.testFreshServer()
done = send(bob, report())
check(done.reason == "tooMany" and #reportKeys() == FeedbackConfig.PER_DAY, "another server: still five for today, from the store")
cost = requests
done = send(bob, report())
check(done.reason == "tooMany" and requests == cost, "and then that server knows it too")
-- The next UTC day.
offset += (Feedback.now() // 86400 + 1) * 86400 - Feedback.now() + 30
local tomorrow = send(bob, report("Other", "a brand new day of feedback"))
check(tomorrow.ok and decode("quota_2").count == 1, "the next UTC day: reports again")
Feedback.testFreshServer()
local hop = send(bob, report())
check(hop.reason == "tooSoon" and waited(hop, 115, 120), "hopping servers doesn't skip the two minutes")
check(#reportKeys() == FeedbackConfig.PER_DAY + 1, "nothing extra stored")

-- One at a time.
offset += FeedbackConfig.COOLDOWN_SECONDS
Feedback.testFreshServer()
task.wait(FeedbackConfig.REQUEST_SECONDS + 0.05)
latency = 2
local first: any = nil
task.spawn(function()
	first = Feedback.submit(bob, report("Idea", "a slow one"))
end)
task.wait(1.1)
local second = Feedback.submit(bob, report("Idea", "an impatient one"))
check(second.reason == "busy", "a second report while the first is on its way: busy")
while first == nil do
	task.wait(0.5)
end
latency = 0
check(first.ok, "the first one lands")

-- Outages: the claim fails (retried, then the player is told).
offset += FeedbackConfig.COOLDOWN_SECONDS
local errorsBefore = feedbackErrors()
local keysBefore = #reportKeys()
local quotaBefore = stored.quota_2
fail.UpdateAsync = FeedbackConfig.SAVE_ATTEMPTS
task.wait(FeedbackConfig.REQUEST_SECONDS + 0.05)
local down = Feedback.submit(bob, report())
check(not down.ok and down.reason == "error", "the store down: the player is told it didn't send")
check(feedbackErrors() == errorsBefore + FeedbackConfig.SAVE_ATTEMPTS, "each try counted as an error")
check(stored.quota_2 == quotaBefore and #reportKeys() == keysBefore, "nothing changed")
-- A flaky store: one failure, then it works.
fail.UpdateAsync = 1
local flaky = send(bob, report("Bug", "made it on the second try"))
check(flaky.ok and #reportKeys() == keysBefore + 1, "a failed try is retried")
-- The quota is taken but the report can't be written: the quota goes back.
offset += FeedbackConfig.COOLDOWN_SECONDS
local countBefore = decode("quota_2").count
fail.SetAsync = FeedbackConfig.SAVE_ATTEMPTS
local lost = send(bob, report("Bug", "this one never lands"))
check(not lost.ok and lost.reason == "error", "the report can't be written: the player is told")
check(decode("quota_2").count == countBefore and #reportKeys() == keysBefore + 1, "and the day's quota is given back")
local retry = send(bob, report("Bug", "this one lands after all"))
check(retry.ok, "so they can send it again at once")
-- Saved but not indexed: still read back (by the server that has it).
offset += FeedbackConfig.COOLDOWN_SECONDS
fail.IndexSetAsync = FeedbackConfig.SAVE_ATTEMPTS
local unlisted = send(bob, report("Idea", "saved but never listed"))
check(unlisted.ok and counter("Feedback.indexFailures") == 1, "saved, just not listed: counted")
local newest = Feedback.latest(1)
check(newest[1] and newest[1].text == "saved but never listed", "and still read back here")

-- The window, on the client.
offset += FeedbackConfig.COOLDOWN_SECONDS
local menuButton = Home.parts.menu.Panel:FindFirstChild("Feedback")
check(menuButton and menuButton:IsA("TextButton") and menuButton.Visible, "FEEDBACK in the M menu")
menuButton.Activated:Fire()
task.wait(0.05)
local p = Window.parts
check(Window.isOpen and p.screen.Enabled and MouseLock.holds("Feedback"), "it opens the window and frees the mouse")
check(p.panel.Active and p.panel.Size.X.Offset <= 520, "a small window that takes the clicks on it")
check(string.find(p.panel.Note.Text, "NEVER OTHER PLAYERS", 1, true), "it says only the developer reads it")
for _, kind in FeedbackConfig.KINDS do
	check(p.kinds[kind] and p.panel:FindFirstChild(kind), `a {kind} button`)
end
check(Window.kind == "Bug" and p.box.PlaceholderText == FeedbackConfig.LOOKS.Bug.prompt, "BUG to start with")
p.kinds.Idea.Activated:Fire()
task.wait(0.05)
check(Window.kind == "Idea" and p.box.PlaceholderText == FeedbackConfig.LOOKS.Idea.prompt, "IDEA chosen")
p.box.Text = string.rep("💨", 350)
check(FeedbackConfig.length(p.box.Text) == 300 and p.count.Text == "300/300", "the box stops at 300 characters, and says so")
p.box.Text = "hi"
check(p.send:GetAttribute("Enabled") == false and p.count.Text == "2/300", "SEND waits for a few characters")
check(Window.send() == "empty" and Window.status == Window.MESSAGES.empty, "and says why")
-- The client's recent errors, its names scrubbed before they leave.
for _ = 1, 2 do
	ScriptContext.Error:Fire("Players.StinkyTester.PlayerScripts.Client.Controllers.HUDController:45: attempt to index nil", "stack", nil)
end
ScriptContext.Error:Fire("Workspace.Stinky Legend.Head is gone", "stack", nil)
local numbersNow = ClientHealth.current()
check(#numbersNow.errors == 2 and numbersNow.errors[1] == "(x2) Players.<player>.PlayerScripts.Client.Controllers.HUDController:45: attempt to index nil", "repeats counted on one entry, names scrubbed")
check(numbersNow.errors[2] == "Workspace.<player>.Head is gone" and numbersNow.errorCount >= 3, "display names too, and the session's count")
for i = 1, 60 do
	RunService.RenderStepped:Fire(1 / 60)
	if i % 20 == 0 then
		task.wait(1)
	end
end
p.box.Text = "IDEA: a  bean  launcher that fires beans"
check(p.send:GetAttribute("Enabled") ~= false, "SEND ready")
local keysBeforeWindow = #reportKeys()
p.send.Activated:Fire()
task.wait(0.1)
check(Window.status == Window.MESSAGES.sent and p.status.Text == Window.MESSAGES.sent, "thanks for it")
check(p.box.Text == "" and string.sub(p.send.Text, 1, 4) == "WAIT" and p.send:GetAttribute("Enabled") == false, "the box cleared, SEND counting down")
local mine = reportKeys()
check(#mine == keysBeforeWindow + 1, "stored")
local windowRecord
for _, key in mine do
	local entry = decode(key)
	if entry.userId == 1 then
		windowRecord = entry
	end
end
check(windowRecord and windowRecord.kind == "Idea" and windowRecord.text == "IDEA: a  bean  launcher that fires beans", "the type and text from the window")
check(type(windowRecord.fps) == "number" and windowRecord.fps > 0 and windowRecord.pingMs == 60, "with the FPS and ping")
check(windowRecord.errors[1] == "(x2) Players.<player>.PlayerScripts.Client.Controllers.HUDController:45: attempt to index nil" and windowRecord.errorCount >= 3, "and the recent errors")
-- The server's wait, shown.
Window.waitUntil = 0
p.box.Text = "one more thing right away"
task.wait(FeedbackConfig.REQUEST_SECONDS + 0.05)
check(Window.send() == "tooSoon", "straight after: too soon")
check(string.find(Window.status, "NEXT ONE IN 1:5", 1, true) and string.sub(p.send.Text, 1, 6) == "WAIT 1", `the wait, from the server ({Window.status})`)
task.wait(FeedbackConfig.COOLDOWN_SECONDS + 1)
check(p.send.Text == "SEND", "SEND again once it's over")
p.panel.Close.Activated:Fire()
task.wait(0.05)
check(not Window.isOpen and not p.screen.Enabled and not MouseLock.holds("Feedback"), "X closes it and locks the mouse again")

-- Nothing anyone wrote ever reached a client.
for _, text in { "a quiet idea", "THROUGH the wall", "a brand new day", "a slow one", "never listed", "bean  launcher", "one more thing", "the gas meter got stuck" } do
	check(not anyClientGot(text), `"{text}" never reached a client`)
end

-- /fw feedback, as an admin (anyone, in Studio).
local list3, from3 = Feedback.latest(3)
check(#list3 == 3 and from3 == "saved", "the store's three newest")
check(list3[1].at >= list3[2].at and list3[2].at >= list3[3].at, "newest first")
local _, summary3, lines = Feedback.readout(3)
check(string.find(summary3, "3 newest", 1, true) and string.find(summary3, "saved", 1, true), `the summary: how many and where from ({summary3})`)
for _, listed in list3 do
	check(not string.find(summary3, listed.text, 1, true), "the summary never has anyone's words")
end
local joined = table.concat(lines, "\n")
check(string.find(joined, `"{list3[1].text}"`, 1, true) and string.find(joined, `"{list3[3].text}"`, 1, true), "every word in the lines for the output")
check(string.find(joined, "job job-feedback-42", 1, true) and string.find(joined, "place v45", 1, true) and string.find(joined, "60ms", 1, true), "with the job ID, place version and ping")
check(string.find(lines[2], "IDEA", 1, true) and string.find(lines[2], "user 1", 1, true), "the newest first (the window's idea)")
local sentToMe = #toClients
local printedBefore = #printed
local answer = TestControls.run(me, "/fw feedback 3")
check(answer == summary3, "/fw feedback 3 answers with the summary")
check(anyLineHas(`"{list3[1].text}"`, printedBefore + 1), "and prints every word to the output")
local toast = toClients[sentToMe + 1]
check(toast and toast.player == me and string.find(toast.args[1].text, "TEST: 3 newest", 1, true), "the admin sees the summary")
for _, listed in list3 do
	check(not holds(toast.args, listed.text), "never the words")
end
check(#Feedback.latest() <= FeedbackConfig.READ_DEFAULT and #Feedback.latest(1000) <= FeedbackConfig.READ_MAX, "ten by default, 25 at most")
check(TestControls.run(me, "/fw feedback") ~= nil, "/fw feedback alone works too")

-- Off with the flag.
Feedback.testEnable(false)
task.wait(0.05)
check(not menuButton.Visible, "off: no FEEDBACK in the M menu")
Window.open()
check(not Window.isOpen, "and the window won't open")
check(send(bob, report()).reason == "off", "the server refuses reports")
local okOff, offMessage = TestControls.feedback()
check(not okOff and string.find(offMessage, "FeatureFlags.FEEDBACK", 1, true), "/fw feedback says it's off")
Feedback.testEnable(nil)
task.wait(0.05)
check(menuButton.Visible and workspace:GetAttribute("FeedbackOpen") == true, "back on with the flag")

-- The only errors were the outages' (each failed try once).
check(feedbackErrors() == errorsBefore + 3 * FeedbackConfig.SAVE_ATTEMPTS + 1, `no other errors ({feedbackErrors() - errorsBefore})`)

globals.print, globals.warn = realPrint, realWarn
return { status = "PASS", checks = checks }
