-- Soft shutdown: a server that closes with players in it (a restart or
-- shutdown from the Creator Hub, Roblox maintenance) moves them to a fresh
-- server instead of dropping them on Roblox's own message:
--   1. every client shows "FART WARS JUST GOT AN UPDATE! Moving you to a
--      fresh server..." (Workspace's SoftShutdown attribute; the client's
--      ShutdownController draws it and keeps it up through the teleport)
--   2. the final saves go first: DataService.saveAll (DataService's own
--      BindToClose runs it too; together they still write each profile
--      once; it runs again for anyone who joins while the server closes),
--      and a player is moved only once this server is done with their
--      profile (DataService.isSettled). A save still going after
--      SAVE_WAIT_SECONDS doesn't hold them any longer, so there's time
--      left to move them: their next server waits for its session lock
--      as it always does, so nothing is lost or written twice
--   3. everyone goes together into one new reserved server, which sends
--      them straight on to a public server of this place. The bounce means
--      nobody lands back in an old server that's closing too. A teleport
--      that fails, or never starts, is tried again (alone, if a group
--      teleport with them failed); after BOUNCE_TRIES failures a player
--      goes straight to a public server instead. No new teleport starts
--      after LAST_TRY_SECONDS, and at DEADLINE_SECONDS it lets go (Roblox
--      closes the server at 30), leaving anyone still here to Roblox.
-- In the reserved server, a player who arrives with the soft shutdown's
-- teleport data sees the same screen and is sent on once their profile has
-- loaded there (so its lock is handed straight back when they go); if that
-- never works, they stay and play there. That half always runs, whatever
-- the flag, since an older build may have started the move.
-- Skipped in Studio (no teleports), in a player's private server (Roblox
-- puts its players back into it by itself), on a server closing because
-- it's empty or for moderation, and with FeatureFlags.SOFT_SHUTDOWN off.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local SoftShutdownConfig = require(Shared.Config.SoftShutdownConfig)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local DataService = require(script.Parent.DataService)

local SoftShutdownService = {}

-- Seconds from the moment the server starts closing:
-- the message is up this long before anyone moves,
SoftShutdownService.MESSAGE_SECONDS = 2
-- and nobody waits longer than this for their save,
SoftShutdownService.SAVE_WAIT_SECONDS = 15
-- no new teleport starts after this, and the shutdown lets go at the
-- deadline (Roblox closes the server at 30).
SoftShutdownService.LAST_TRY_SECONDS = 25
SoftShutdownService.DEADLINE_SECONDS = 29
-- Teleports: a player still here this long after one that reported no
-- failure is tried again; a failure is retried after RETRY_SECONDS (longer
-- when Roblox says too many were asked for); after BOUNCE_TRIES failed
-- tries through the reserved server, a player goes straight to a public one.
SoftShutdownService.STUCK_SECONDS = 10
SoftShutdownService.RETRY_SECONDS = 1
SoftShutdownService.FLOODED_RETRY_SECONDS = 5
SoftShutdownService.BOUNCE_TRIES = 2
-- The reserved server: how long a player passing through waits for their
-- profile before being sent on anyway, how long between tries, and how
-- many tries before they stay.
SoftShutdownService.ARRIVAL_WAIT_SECONDS = 10
SoftShutdownService.RETURN_RETRY_SECONDS = 3
SoftShutdownService.RETURN_TRIES = 5
-- Roblox's limit for one TeleportAsync call.
local MAX_GROUP = 50

export type Kind = "update" | "closing"
type Route = "bounce" | "public"
type Move = {
	since: number, -- when this player's move began
	tries: number, -- teleports that failed so far
	sentAt: number?, -- set while a teleport is under way
	retryAt: number,
	delay: number, -- the wait after a failure
	solo: boolean, -- teleport them alone: a group teleport with them failed
	unsaved: boolean, -- moved before their save was written
}

-- What only a live server has, in one place so a spec can stand in for it
-- (the spec harness is always Studio, with no teleports or join data).
local live = {
	isStudio = function(): boolean
		return RunService:IsStudio()
	end,
	teleportService = TeleportService :: any,
	newOptions = function(): any
		return Instance.new("TeleportOptions")
	end,
	joinData = function(player: Player): any
		return player:GetJoinData()
	end,
}

-- Players being moved (on a closing server) or sent on (in the reserved
-- server they're passing through).
local moves: { [Player]: Move } = {}
local closing = false
local sendingOn = false
-- A final save (DataService.saveAll) of this shutdown's is running.
local saving = false
local started = false
-- The reserved server this shutdown bounces everyone through: the same ID
-- sends every teleport to the same one.
local bounceId = ""
local failureConnection: RBXScriptConnection? = nil

local function newMove(now: number, delay: number): Move
	return { since = now, tries = 0, sentAt = nil, retryAt = now, delay = delay, solo = false, unsaved = false }
end

-- "public", "reserved" (made by a teleport, like the one players bounce
-- through) or "private" (a player's own private server).
function SoftShutdownService.serverKind(): "public" | "reserved" | "private"
	local id = game.PrivateServerId
	if id == nil or id == "" then
		return "public"
	end
	return if game.PrivateServerOwnerId == 0 then "reserved" else "private"
end

-- The message for a close reason: anything but maintenance or memory reads
-- as an update (restarts and shutdowns from the Creator Hub, and unknowns).
local function kindOf(reason: EnumItem?): Kind
	local name = if reason then reason.Name else nil
	return if name == "RobloxMaintenance" or name == "OutOfMemory" then "closing" else "update"
end

-- Why a closing server wouldn't move its players (nil: it would).
function SoftShutdownService.skipReason(reason: EnumItem?): string?
	local name = if reason then reason.Name else nil
	if not FeatureFlags.SOFT_SHUTDOWN then
		return "off"
	elseif live.isStudio() then
		return "Studio"
	elseif SoftShutdownService.serverKind() == "private" then
		return "private server"
	elseif name == "ServerEmpty" then
		return "empty"
	elseif name == "Moderation" then
		-- Roblox turns teleports off for these.
		return "moderation"
	elseif #Players:GetPlayers() == 0 then
		return "no players"
	end
	return nil
end

-- A teleport that failed or never started: try again after a wait.
local function failed(player: Player, result: EnumItem?)
	local move = moves[player]
	if not (move and move.sentAt) then
		return
	end
	move.sentAt = nil
	move.tries += 1
	local flooded = result ~= nil and result.Name == "Flooded"
	move.retryAt = os.clock() + (if flooded then math.max(move.delay, SoftShutdownService.FLOODED_RETRY_SECONDS) else move.delay)
end

local function onTeleportFailed(player: Player, result: EnumItem?, message: string?)
	local move = moves[player]
	if not (move and move.sentAt) then
		return
	end
	local name = if result then result.Name else "Unknown"
	Telemetry.count(`SoftShutdown.failed.{name}`)
	Telemetry.log("SoftShutdown", "teleportFailed", { player = player, result = name, message = message })
	-- Already on the way somewhere (Roblox's own move, perhaps): leave it.
	if name == "IsTeleporting" then
		return
	end
	failed(player, result)
end

local function connectFailures()
	if failureConnection then
		failureConnection:Disconnect()
		failureConnection = nil
	end
	local event = (live.teleportService :: any).TeleportInitFailed
	if event then
		failureConnection = event:Connect(onTeleportFailed)
	end
end

-- One TeleportAsync: into the bounce's reserved server (marked with the
-- teleport data its server looks for) or to any public server of this
-- place. Each player is marked as under way first; a call that throws
-- counts as a failure for all of them.
local function send(players: { Player }, route: Route, kind: Kind)
	local at = os.clock()
	for _, player in players do
		local move = moves[player]
		if move then
			move.sentAt = at
		end
	end
	Telemetry.count(`SoftShutdown.sent.{route}`, #players)
	local ok, err = pcall(function()
		local options = nil
		if route == "bounce" then
			options = live.newOptions()
			options.ReservedServerId = bounceId
			options:SetTeleportData({ [SoftShutdownConfig.TELEPORT_KEY] = kind })
		end
		live.teleportService:TeleportAsync(game.PlaceId, players, options)
	end)
	if not ok then
		Telemetry.error("SoftShutdown", err)
		for _, player in players do
			local move = moves[player]
			if move and #players > 1 then
				move.solo = true
			end
			failed(player, nil)
		end
	end
end

-- Sends `players` on `route`: the solo ones alone, the rest together.
local function sendAll(players: { Player }, route: Route, kind: Kind)
	local group = {}
	for _, player in players do
		if moves[player].solo then
			task.spawn(send, { player }, route, kind)
		else
			table.insert(group, player)
		end
	end
	for first = 1, #group, MAX_GROUP do
		task.spawn(send, table.move(group, first, math.min(first + MAX_GROUP - 1, #group), 1, {}), route, kind)
	end
end

local function saveEveryone()
	saving = true
	DataService.saveAll()
	saving = false
end

-- The shutdown itself (bound with game:BindToClose; Roblox passes the
-- reason). Returns once everyone has gone, or at DEADLINE_SECONDS.
function SoftShutdownService.close(reason: EnumItem?)
	local reasonName = if reason then reason.Name else "none"
	local skip = SoftShutdownService.skipReason(reason)
	if skip then
		Telemetry.log("SoftShutdown", "skipped", { why = skip, reason = reasonName })
		return
	end
	closing = true
	local kind = kindOf(reason)
	local bounce = SoftShutdownService.serverKind() == "public"
	local began = os.clock()
	bounceId = HttpService:GenerateGUID(false)
	table.clear(moves)
	workspace:SetAttribute(SoftShutdownConfig.ATTRIBUTE, kind)
	Telemetry.log("SoftShutdown", "started", {
		players = #Players:GetPlayers(),
		reason = reasonName,
		route = if bounce then "bounce" else "public",
	})
	-- The final saves come first.
	task.spawn(saveEveryone)
	local moved, unsaved, elapsed = 0, 0, 0
	while true do
		local now = os.clock()
		elapsed = now - began
		for player, move in moves do
			if player.Parent ~= Players then
				moves[player] = nil
				if move.sentAt then
					moved += 1
				end
			end
		end
		local here = Players:GetPlayers()
		if #here == 0 or elapsed >= SoftShutdownService.DEADLINE_SECONDS then
			break
		end
		-- Someone who joined after the final saves had finished: theirs too.
		if not saving then
			for _, player in here do
				if DataService.isLoaded(player) then
					task.spawn(saveEveryone)
					break
				end
			end
		end
		if elapsed >= SoftShutdownService.MESSAGE_SECONDS and elapsed < SoftShutdownService.LAST_TRY_SECONDS then
			local due: { [Route]: { Player } } = { bounce = {}, public = {} }
			for _, player in here do
				local move = moves[player] or newMove(now, SoftShutdownService.RETRY_SECONDS)
				moves[player] = move
				if move.sentAt then
					if now - move.sentAt >= SoftShutdownService.STUCK_SECONDS then
						failed(player, nil)
					end
				elseif now >= move.retryAt then
					local settled = DataService.isSettled(player)
					if settled or elapsed >= SoftShutdownService.SAVE_WAIT_SECONDS then
						if not settled and not move.unsaved then
							move.unsaved = true
							unsaved += 1
						end
						local route: Route = if bounce and move.tries < SoftShutdownService.BOUNCE_TRIES then "bounce" else "public"
						table.insert(due[route], player)
					end
				end
			end
			for route, list in due do
				sendAll(list, route, kind)
			end
		end
		task.wait(0.1)
	end
	local stillHere = #Players:GetPlayers()
	Telemetry.count("SoftShutdown.moved", moved)
	if unsaved > 0 then
		Telemetry.count("SoftShutdown.movedUnsaved", unsaved)
	end
	if stillHere > 0 then
		Telemetry.count("SoftShutdown.leftover", stillHere)
	end
	Telemetry.log("SoftShutdown", "finished", {
		moved = moved,
		unsaved = unsaved,
		stillHere = stillHere,
		seconds = math.floor(elapsed * 10) / 10,
	})
end

-- The reserved server's half: sends everyone passing through on to a
-- public server, together where they're ready together.
local function sendOn()
	sendingOn = true
	while not closing do
		local now = os.clock()
		local due = {}
		local anyone = false
		for player, move in moves do
			if player.Parent ~= Players then
				moves[player] = nil
				continue
			end
			anyone = true
			if move.sentAt then
				if now - move.sentAt >= SoftShutdownService.STUCK_SECONDS then
					failed(player, nil)
				end
			elseif move.tries >= SoftShutdownService.RETURN_TRIES then
				-- Nothing worked: they stay and play here.
				moves[player] = nil
				player:SetAttribute(SoftShutdownConfig.ATTRIBUTE, "stay")
				Telemetry.count("SoftShutdown.stayed")
				Telemetry.log("SoftShutdown", "stayed", { player = player })
			elseif
				now >= move.retryAt
				and now - move.since >= SoftShutdownService.MESSAGE_SECONDS
				and (DataService.isLoaded(player) or now - move.since >= SoftShutdownService.ARRIVAL_WAIT_SECONDS)
			then
				table.insert(due, player)
			end
		end
		if #due > 0 then
			sendAll(due, "public", "update")
		end
		if not anyone then
			break
		end
		task.wait(0.25)
	end
	sendingOn = false
end

-- A player joining a reserved server with the soft shutdown's teleport
-- data is passing through: they're sent on.
local function arrived(player: Player)
	if closing or SoftShutdownService.serverKind() ~= "reserved" then
		return
	end
	local ok, join = pcall(live.joinData, player)
	local data = if ok and type(join) == "table" then join.TeleportData else nil
	local kind = if type(data) == "table" then data[SoftShutdownConfig.TELEPORT_KEY] else nil
	if kind ~= "update" and kind ~= "closing" then
		return
	end
	moves[player] = newMove(os.clock(), SoftShutdownService.RETURN_RETRY_SECONDS)
	player:SetAttribute(SoftShutdownConfig.ATTRIBUTE, "moving")
	Telemetry.count("SoftShutdown.arrived")
	if not sendingOn then
		task.spawn(sendOn)
	end
end

-- One line for /fw selftest: what closing would do on this server.
function SoftShutdownService.describe(): string
	if not FeatureFlags.SOFT_SHUTDOWN then
		return "off: a closing server leaves its players to Roblox"
	elseif live.isStudio() then
		return "on, but never in Studio (no teleports): try it on staging"
	end
	local kind = SoftShutdownService.serverKind()
	if kind == "private" then
		return "on, but not in private servers (Roblox puts their players back in them)"
	elseif kind == "reserved" then
		return "on; this is a reserved server, so players passing through are sent on to a public one"
	end
	return "on: closing with players shows the update message, saves everyone, then moves them through a reserved server to a fresh one"
end

-- Test seam: stands in for parts of `live` (isStudio, teleportService with
-- TeleportAsync and TeleportInitFailed, newOptions, joinData).
function SoftShutdownService.setLive(parts: { [string]: any })
	for key, value in parts do
		(live :: any)[key] = value
	end
	if parts.teleportService then
		connectFailures()
	end
end

-- Test seam: a fresh start for the next close in the same spec world.
function SoftShutdownService.testReset()
	closing = false
	table.clear(moves)
	workspace:SetAttribute(SoftShutdownConfig.ATTRIBUTE, nil)
end

function SoftShutdownService.start()
	if started then
		return
	end
	started = true
	connectFailures()
	Players.PlayerAdded:Connect(arrived)
	for _, player in Players:GetPlayers() do
		task.spawn(arrived, player)
	end
	if FeatureFlags.SOFT_SHUTDOWN then
		game:BindToClose(SoftShutdownService.close)
	end
end

return SoftShutdownService
