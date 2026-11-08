-- The soft shutdown (SoftShutdownService), with stand-ins for what only a
-- live server has (teleports that can fail on demand, join data, not being
-- Studio) and a stand-in DataStore like the Data spec's:
--   * nothing happens in Studio, in a player's private server, on a server
--     closing because it's empty or for moderation, or with nobody in it:
--     no message, no saves, no teleports, no waiting
--   * a public server closing for an update shows the message, writes each
--     profile once (with DataService's own shutdown save running
--     alongside), and only then teleports each player: the ones whose
--     saves are done go together into one reserved server, marked as a
--     bounce, and a player with a slow save follows into the same one once
--     it's written; it lets go as soon as everyone has gone
--   * someone joining while it closes, after the final saves have finished,
--     is saved too before they're moved
--   * failures: a teleport call that throws is tried again, each player
--     alone; one Roblox reports as failed is tried again, and after
--     BOUNCE_TRIES the player goes straight to a public server; one that
--     never starts is tried again after STUCK_SECONDS; "already
--     teleporting" isn't retried; a save that never finishes holds nobody
--     past SAVE_WAIT_SECONDS; teleports that never work still let go by
--     DEADLINE_SECONDS, inside Roblox's 30, with none started after
--     LAST_TRY_SECONDS
--   * a closing reserved server sends its players straight to public servers
--   * in the reserved server, players who arrive with the bounce's teleport
--     data are sent on together to a public server once their profiles
--     have loaded (an ordinary player there isn't touched); after
--     RETURN_TRIES failures they stay and play there
--   * the client's screen: the update message word for word, over
--     everything, while the server closes; at once when arriving passing
--     through (and gone again if the server never marks them); "staying"
--     when nothing worked, then gone
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
-- No bots: these checks count the players themselves.
require(server.Services.BotDirector).testSetEnabled(false)
local Data = require(server.Services.DataService)
local Economy = require(server.Services.EconomyService)
local Telemetry = require(server.Telemetry)
local SoftShutdown = require(server.Services.SoftShutdownService)
local SoftShutdownConfig = require(ReplicatedStorage.Shared.Config.SoftShutdownConfig)
local ATTRIBUTE = SoftShutdownConfig.ATTRIBUTE
local KEY = SoftShutdownConfig.TELEPORT_KEY
local TEXT = SoftShutdownConfig.text
local UPDATE = Enum.CloseReason.DeveloperUpdate
game.PlaceId = 4242

-- The stand-in store: each write takes a moment, or as long as `slow` says
-- for that key.
local saved: { [string]: any } = {}
local slow: { [string]: number } = {}
local writes = 0
local function copy(value: any): any
	return if value == nil then nil else HttpService:JSONDecode(HttpService:JSONEncode(value))
end
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		task.wait(slow[key] or 0.2)
		local result = transform(copy(saved[key]))
		if result ~= nil then
			saved[key] = copy(result)
			writes += 1
		end
		return result
	end,
})

-- The stand-in TeleportService. Each call is kept: when, who, where to, and
-- for each player whether their last save was already in the store and
-- whether their profile was loaded on this server at that moment. What a
-- teleport does is planned per player, one outcome per teleport ("leave"
-- by default, or `defaultOutcome`): "leave" (they go a second later),
-- "fail" (Roblox reports TeleportInitFailed), "busy" (reported as already
-- teleporting, then they go), "hang" (nothing happens). `throwCalls` calls
-- error outright.
type Call = {
	at: number,
	placeId: number,
	names: { string },
	reserved: string?,
	data: any,
	banner: any,
	saved: { [string]: boolean },
	loaded: { [string]: boolean },
}
local calls: { Call } = {}
local plans: { [number]: { string } } = {}
local defaultOutcome = "leave"
local throwCalls = 0
-- User ID -> the coins their last save should hold.
local expected: { [number]: number } = {}
local failEvent = Instance.new("BindableEvent")
local function lastSaveIn(player: Player): boolean
	local entry = saved[`player_{player.UserId}`]
	return entry ~= nil and entry.Lock == nil and entry.Coins == expected[player.UserId]
end
local teleport = {
	TeleportInitFailed = failEvent.Event,
	TeleportAsync = function(_, placeId: number, players: { Player }, options: any?)
		local call: Call = {
			at = os.clock(),
			placeId = placeId,
			names = {},
			reserved = options and options.ReservedServerId,
			data = options and options.data,
			banner = workspace:GetAttribute(ATTRIBUTE),
			saved = {},
			loaded = {},
		}
		for _, player in players do
			table.insert(call.names, player.Name)
			call.saved[player.Name] = lastSaveIn(player)
			call.loaded[player.Name] = Data.isLoaded(player)
		end
		table.insert(calls, call)
		task.wait(0.3)
		if throwCalls > 0 then
			throwCalls -= 1
			error("HTTP 500 (stand-in teleport outage)")
		end
		for _, player in players do
			local plan = plans[player.UserId]
			local outcome = if plan and #plan > 0 then table.remove(plan, 1) else defaultOutcome
			if outcome == "leave" then
				task.delay(1, function()
					player.Parent = nil
				end)
			elseif outcome == "fail" then
				task.delay(0.5, function()
					failEvent:Fire(player, Enum.TeleportResult.Failure, "stand-in failure", placeId, options)
				end)
			elseif outcome == "busy" then
				task.delay(0.5, function()
					failEvent:Fire(player, Enum.TeleportResult.IsTeleporting, "already teleporting", placeId, options)
				end)
				task.delay(2, function()
					player.Parent = nil
				end)
			end
		end
		return nil
	end,
}
local studio = true
local joinData: { [Player]: any } = {}
SoftShutdown.setLive({
	isStudio = function()
		return studio
	end,
	teleportService = teleport,
	newOptions = function()
		return {
			SetTeleportData = function(self, data)
				self.data = data
			end,
		}
	end,
	joinData = function(player: Player)
		return joinData[player] or {}
	end,
})

local function waitFor(condition: () -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while not condition() do
		if os.clock() > deadline then
			return false
		end
		task.wait(0.1)
	end
	return true
end
local function join(name: string, userId: number, teleportData: any?): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	if teleportData then
		joinData[player] = { TeleportData = teleportData }
	end
	player.Parent = Players
	return player
end
local function loaded(list: { Player }): boolean
	return waitFor(function()
		for _, player in list do
			if not Data.isLoaded(player) then
				return false
			end
		end
		return true
	end, 3)
end
local function earn(player: Player, coins: number)
	Economy.testGrant(player, coins, 0)
	expected[player.UserId] = assert(Data.get(player)).data.Coins
end
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function callsFor(name: string): { Call }
	local list = {}
	for _, call in calls do
		if table.find(call.names, name) then
			table.insert(list, call)
		end
	end
	return list
end
local function timed(fn: () -> ()): number
	local began = os.clock()
	fn()
	return os.clock() - began
end
-- Between closes: whoever is left goes, and everything starts fresh.
local function reset()
	for _, player in Players:GetPlayers() do
		player.Parent = nil
	end
	task.wait(1)
	SoftShutdown.testReset()
	table.clear(calls)
	table.clear(plans)
	defaultOutcome = "leave"
	throwCalls = 0
end

-- Where nothing should happen.
local ada = join("Ada", 101)
local bo = join("Bo", 102)
check(loaded({ ada, bo }), "two players load")
earn(ada, 50)
local function nothingHappens(where: string, reason: EnumItem)
	local before = writes
	local seconds = timed(function()
		SoftShutdown.close(reason)
	end)
	check(seconds == 0, `{where}: it returns at once`)
	check(#calls == 0, `{where}: no teleport`)
	check(workspace:GetAttribute(ATTRIBUTE) == nil, `{where}: no message`)
	check(Data.isLoaded(ada) and writes == before, `{where}: profiles untouched (DataService's own shutdown save still runs)`)
end
check(SoftShutdown.skipReason(UPDATE) == "Studio", "Studio is skipped")
check(string.find(SoftShutdown.describe(), "Studio", 1, true) ~= nil, "and selftest says so")
nothingHappens("in Studio", UPDATE)
studio = false
game.PrivateServerId = "vip-server"
game.PrivateServerOwnerId = 77
check(SoftShutdown.serverKind() == "private" and SoftShutdown.skipReason(UPDATE) == "private server", "a player's private server is skipped")
check(string.find(SoftShutdown.describe(), "private servers", 1, true) ~= nil, "and selftest says so")
nothingHappens("in a private server", UPDATE)
game.PrivateServerId = ""
game.PrivateServerOwnerId = 0
check(SoftShutdown.serverKind() == "public" and SoftShutdown.skipReason(UPDATE) == nil, "a public server with players would move them")
check(string.find(SoftShutdown.describe(), "reserved server to a fresh one", 1, true) ~= nil, "and selftest says so")
nothingHappens("closing because it's empty", Enum.CloseReason.ServerEmpty)
nothingHappens("closing for moderation", Enum.CloseReason.Moderation)
ada.Parent = nil
bo.Parent = nil
task.wait(1)
check(SoftShutdown.skipReason(UPDATE) == "no players", "with nobody in the server")
local before = writes
local seconds = timed(function()
	SoftShutdown.close(UPDATE)
end)
check(seconds == 0 and #calls == 0 and writes == before, "nothing runs: no saves, no teleports, no waiting")
check(workspace:GetAttribute(ATTRIBUTE) == nil, "and no message")

-- A public server closing for an update: saves first, then the bounce.
local cy, di, ed = join("Cy", 201), join("Di", 202), join("Ed", 203)
check(loaded({ cy, di, ed }), "three players load")
earn(cy, 10)
earn(di, 20)
earn(ed, 30)
slow.player_203 = 6
before = writes
local began = os.clock()
-- Roblox runs every BindToClose function together: DataService's own
-- shutdown save alongside the soft shutdown.
task.spawn(Data.saveAll)
SoftShutdown.close(UPDATE)
seconds = os.clock() - began
slow.player_203 = nil
for _, call in calls do
	for name, done in call.saved do
		check(done, `{name}'s last save was in the store before their teleport`)
	end
end
check(#Players:GetPlayers() == 0, "everyone was moved")
check(writes - before == 3, `each profile was written once ({writes - before} writes)`)
check(#calls == 2, `two teleports ({#calls})`)
local together, after = calls[1], calls[2]
check(together.banner == "update", "the update message was up before anyone moved")
check(together.at - began >= SoftShutdown.MESSAGE_SECONDS, "long enough to read it")
check(#together.names == 2 and table.find(together.names, "Cy") and table.find(together.names, "Di"), "the two quick saves went together")
check(together.placeId == game.PlaceId and type(together.reserved) == "string" and #together.reserved > 0, "into a reserved server of this place")
check(type(together.data) == "table" and together.data[KEY] == "update", "marked as a bounce, with the reason")
check(after.names[1] == "Ed" and #after.names == 1 and after.reserved == together.reserved, "the slow save's player followed into the same reserved server")
check(after.at - began >= 6, "once their save was written")
check(seconds < SoftShutdown.SAVE_WAIT_SECONDS, `it let go as soon as everyone had gone ({seconds} s)`)

-- Someone who joins while the server closes, after the final saves have
-- finished: saved too, then moved.
reset()
local early = join("Ev", 251)
check(loaded({ early }), "Ev loads")
earn(early, 8)
local late: Player? = nil
task.delay(2.5, function()
	late = join("La", 252)
	expected[252] = 0
end)
began = os.clock()
SoftShutdown.close(UPDATE)
seconds = os.clock() - began
local lateCalls = callsFor("La")
check(late ~= nil and (late :: Player).Parent == nil and #lateCalls == 1, "the late joiner was moved")
check(lateCalls[1].saved.La, "after their save was written")
check(lateCalls[1].at - began < SoftShutdown.SAVE_WAIT_SECONDS, "without waiting out SAVE_WAIT_SECONDS")
check(seconds < SoftShutdown.SAVE_WAIT_SECONDS, `and it let go once they'd gone ({seconds} s)`)

-- A teleport call that throws: tried again, each player alone.
reset()
local fa, gu = join("Fa", 301), join("Gu", 302)
check(loaded({ fa, gu }), "two more load")
earn(fa, 5)
earn(gu, 6)
throwCalls = 1
local failuresBefore = Telemetry.snapshot().errors.SoftShutdown or 0
SoftShutdown.close(UPDATE)
check(#Players:GetPlayers() == 0, "both were moved after a teleport call threw")
check(#calls == 3 and #calls[1].names == 2 and #calls[2].names == 1 and #calls[3].names == 1, "one group call that threw, then one each")
check(calls[2].reserved == calls[1].reserved and calls[3].reserved == calls[1].reserved, "still into the same reserved server")
check(calls[2].at - calls[1].at >= SoftShutdown.RETRY_SECONDS, "after a short wait")
check((Telemetry.snapshot().errors.SoftShutdown or 0) == failuresBefore + 1, "the error is counted")

-- Teleports Roblox reports as failed: tried again, then straight to a
-- public server.
reset()
local ha = join("Ha", 401)
check(loaded({ ha }), "Ha loads")
earn(ha, 7)
plans[401] = { "fail", "fail" }
local reported = counter("SoftShutdown.failed.Failure")
SoftShutdown.close(UPDATE)
local mine = callsFor("Ha")
check(ha.Parent == nil and #mine == 3, `Ha was moved on the third teleport ({#mine})`)
check(mine[1].reserved ~= nil and mine[2].reserved ~= nil, "the first two through the reserved server")
check(mine[3].reserved == nil and mine[3].data == nil and mine[3].placeId == game.PlaceId, "then straight to a public server of this place")
check(counter("SoftShutdown.failed.Failure") == reported + 2, "the failures are counted")

-- A teleport that never starts, and one that's already under way.
reset()
local io, ju = join("Io", 501), join("Ju", 502)
check(loaded({ io, ju }), "two more load")
earn(io, 1)
earn(ju, 2)
plans[501] = { "hang" }
plans[502] = { "busy" }
SoftShutdown.close(UPDATE)
local ioCalls, juCalls = callsFor("Io"), callsFor("Ju")
check(io.Parent == nil and ju.Parent == nil, "both were moved")
check(#juCalls == 1, "\"already teleporting\" isn't tried again")
check(#ioCalls == 2 and ioCalls[2].at - ioCalls[1].at >= SoftShutdown.STUCK_SECONDS, "a teleport that never started is tried again after STUCK_SECONDS")
check(ioCalls[2].reserved == ioCalls[1].reserved, "still through the reserved server")

-- A save that never finishes holds nobody past SAVE_WAIT_SECONDS.
reset()
local ka = join("Ka", 601)
check(loaded({ ka }), "Ka loads")
earn(ka, 9)
slow.player_601 = 40
local unsavedBefore = counter("SoftShutdown.movedUnsaved")
began = os.clock()
SoftShutdown.close(UPDATE)
slow.player_601 = nil
local kaCalls = callsFor("Ka")
check(ka.Parent == nil and #kaCalls == 1 and not kaCalls[1].saved.Ka, "Ka was moved though their save hadn't landed")
local waited = kaCalls[1].at - began
check(waited >= SoftShutdown.SAVE_WAIT_SECONDS and waited < SoftShutdown.SAVE_WAIT_SECONDS + 1, `at SAVE_WAIT_SECONDS, with time left to move them ({waited} s)`)
check(counter("SoftShutdown.movedUnsaved") == unsavedBefore + 1, "and it's counted")

-- Teleports that never work: it still lets go in time.
reset()
local lu = join("Lu", 701)
check(loaded({ lu }), "Lu loads")
earn(lu, 3)
defaultOutcome = "fail"
local leftBefore = counter("SoftShutdown.leftover")
began = os.clock()
SoftShutdown.close(UPDATE)
seconds = os.clock() - began
local luCalls = callsFor("Lu")
check(seconds >= SoftShutdown.DEADLINE_SECONDS and seconds < 30, `it let go at the deadline, inside Roblox's 30 seconds ({seconds} s)`)
check(lu.Parent == Players and counter("SoftShutdown.leftover") == leftBefore + 1, "Lu is left to Roblox, and counted")
check(#luCalls >= 4 and luCalls[#luCalls].at - began < SoftShutdown.LAST_TRY_SECONDS, `{#luCalls} tries, none started after LAST_TRY_SECONDS`)
check(luCalls[#luCalls].reserved == nil, "the later tries went straight to a public server")
check(lastSaveIn(lu), "Lu's progress was saved all the same")

-- A reserved server closing: straight to public servers.
reset()
game.PrivateServerId = "reserved-server"
game.PrivateServerOwnerId = 0
check(SoftShutdown.serverKind() == "reserved", "a reserved server")
check(string.find(SoftShutdown.describe(), "reserved server", 1, true) ~= nil, "and selftest says so")
local mo = join("Mo", 801)
check(loaded({ mo }), "Mo loads")
earn(mo, 4)
check(mo:GetAttribute(ATTRIBUTE) == nil, "a player without the bounce's teleport data isn't passing through")
SoftShutdown.close(Enum.CloseReason.RobloxMaintenance)
local moCalls = callsFor("Mo")
check(mo.Parent == nil and #moCalls == 1, "Mo was moved")
check(moCalls[1].reserved == nil and moCalls[1].data == nil, "straight to a public server")
check(moCalls[1].banner == "closing", "maintenance says the server is closing, not that there's an update")
check(moCalls[1].saved.Mo, "after Mo's save")

-- The reserved server's half: players passing through are sent on.
reset()
local na = join("Na", 901, { [KEY] = "update" })
local ob = join("Ob", 902, { [KEY] = "update" })
local pi = join("Pi", 903)
check(na:GetAttribute(ATTRIBUTE) == "moving" and ob:GetAttribute(ATTRIBUTE) == "moving", "players passing through are marked at once")
check(pi:GetAttribute(ATTRIBUTE) == nil, "an ordinary player isn't")
check(waitFor(function()
	return na.Parent == nil and ob.Parent == nil
end, 15), "both are sent on")
local naCalls = callsFor("Na")
check(#naCalls == 1 and #naCalls[1].names == 2 and table.find(naCalls[1].names, "Ob"), "together")
check(naCalls[1].reserved == nil and naCalls[1].data == nil and naCalls[1].placeId == game.PlaceId, "to a public server of this place, no longer marked")
check(naCalls[1].loaded.Na and naCalls[1].loaded.Ob, "once their profiles had loaded here")
check(naCalls[1].banner == nil, "the reserved server itself isn't closing")
check(pi.Parent == Players and #callsFor("Pi") == 0, "the ordinary player stays put")
local qu = join("Qu", 904, { [KEY] = "closing" })
defaultOutcome = "fail"
check(waitFor(function()
	return qu:GetAttribute(ATTRIBUTE) == "stay"
end, 60), "when sending them on keeps failing, they stay")
defaultOutcome = "leave"
check(#callsFor("Qu") == SoftShutdown.RETURN_TRIES, `after RETURN_TRIES tries ({#callsFor("Qu")})`)
task.wait(5)
check(qu.Parent == Players and #callsFor("Qu") == SoftShutdown.RETURN_TRIES, "and are left to play here")

-- The client's screen.
reset()
game.PrivateServerId = ""
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
local client = game.StarterPlayer.StarterPlayerScripts.Client
local Shutdown = require(client.Controllers.ShutdownController)
Shutdown.start()
check(me.PlayerGui:FindFirstChild("SoftShutdown") == nil, "no screen until there's something to say")
workspace:SetAttribute(ATTRIBUTE, "update")
local parts = assert(Shutdown.parts)
check(parts.screen.Enabled and parts.title.Text == "FART WARS JUST GOT AN UPDATE!", "the update message, word for word")
check(parts.detail.Text == "Moving you to a fresh server...", "and what's happening")
check(parts.screen.DisplayOrder > 100 and parts.screen.IgnoreGuiInset, "over everything, the loading screen included")
workspace:SetAttribute(ATTRIBUTE, "closing")
check(parts.title.Text == TEXT.closing, "a server closing for other reasons says so")
workspace:SetAttribute(ATTRIBUTE, nil)
check(not parts.screen.Enabled, "gone when the server isn't closing")
Shutdown.arrive("update")
check(parts.screen.Enabled and parts.title.Text == TEXT.update, "arriving passing through shows it at once")
task.wait(Shutdown.PASSING_TRUST_SECONDS + 0.5)
check(not parts.screen.Enabled, "and it goes if the server never marks them, so nobody's trapped behind it")
Shutdown.arrive("update")
me:SetAttribute(ATTRIBUTE, "moving")
task.wait(Shutdown.PASSING_TRUST_SECONDS + 0.5)
check(parts.screen.Enabled and parts.detail.Text == TEXT.moving, "it stays up while the server sends them on")
me:SetAttribute(ATTRIBUTE, "stay")
check(parts.screen.Enabled and parts.title.Text == TEXT.stay, "if nothing worked, it says they're staying")
task.wait(SoftShutdownConfig.STAY_SECONDS + 0.5)
check(not parts.screen.Enabled, "then goes")

return { status = "PASS", checks = checks }
