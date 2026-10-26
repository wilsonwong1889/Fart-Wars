-- Moderation hooks. Everything suspicious reaches here as a Telemetry flag
-- (an abnormal rate of refused requests, near-perfect accuracy, impossible
-- movement, anomalous coin gains, dashing through walls). Each is counted
-- per player; GameConfig.MODERATION decides what happens: by default
-- nothing beyond the log (review only), or a kick at KICK_AT_FLAGS. Banned
-- user IDs are turned away on joining. Nothing here acts on one client's
-- word: a player report (ReportPlayer, from the Players screen) is counted
-- and logged, and only reports from REPORTS_TO_FLAG different players in a
-- server flag someone for review. Roblox's own Report (Esc menu) is the
-- path that reaches Roblox moderation; the Players screen says so.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Telemetry = require(script.Parent.Telemetry)

local MODERATION = GameConfig.MODERATION

local Moderation = {}

Moderation.KICK_MESSAGE = "You were removed from this server for unusual activity."
Moderation.BAN_MESSAGE = "You can't join Fart Wars right now."

local flags: { [Player]: { { reason: string, detail: string?, at: number } } } = {}
-- Who each player has reported this session, and who reported each player.
local sent: { [Player]: { [number]: boolean } } = {}
local received: { [number]: { [number]: boolean } } = {}
local reportFlagged: { [number]: boolean } = {}
local started = false

export type ReportResult = { ok: boolean, reason: string }

-- `reporter` reports the player with `targetUserId` for `reason`.
function Moderation.report(reporter: Player, targetUserId: unknown, reason: unknown): ReportResult
	if type(targetUserId) ~= "number" or type(reason) ~= "string" or not table.find(MODERATION.REPORT_REASONS, reason) then
		Telemetry.reject("ReportPlayer", reporter, "badPayload")
		return { ok = false, reason = "badPayload" }
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == reporter then
		return { ok = false, reason = "notHere" }
	end
	local mine = sent[reporter] or {}
	sent[reporter] = mine
	if mine[targetUserId] then
		return { ok = false, reason = "already" }
	end
	local count = 0
	for _ in mine do
		count += 1
	end
	if count >= MODERATION.REPORTS_PER_SESSION then
		Telemetry.reject("ReportPlayer", reporter, "tooMany")
		return { ok = false, reason = "tooMany" }
	end
	mine[targetUserId] = true
	local against = received[targetUserId] or {}
	received[targetUserId] = against
	against[reporter.UserId] = true
	local reporters = 0
	for _ in against do
		reporters += 1
	end
	Telemetry.count("reports.total")
	Telemetry.count(`reports.{reason}`)
	Telemetry.log("Moderation", "report", { player = target, by = reporter, reason = reason, reporters = reporters })
	if reporters >= MODERATION.REPORTS_TO_FLAG and not reportFlagged[targetUserId] then
		reportFlagged[targetUserId] = true
		Telemetry.flag(target, "reported", `{reporters} players`)
	end
	return { ok = true, reason = "sent" }
end

-- The player's flags this session, oldest first.
function Moderation.flagsOf(player: Player): { { reason: string, detail: string?, at: number } }
	return table.clone(flags[player] or {})
end

local function onFlag(player: Player, reason: string, detail: string?)
	if player.Parent ~= Players then
		return
	end
	local list = flags[player] or {}
	flags[player] = list
	table.insert(list, { reason = reason, detail = detail, at = os.time() })
	if MODERATION.KICK_AT_FLAGS > 0 and #list >= MODERATION.KICK_AT_FLAGS then
		Telemetry.count("Moderation.kicks")
		Telemetry.log("Moderation", "kick", { player = player, flags = #list })
		player:Kick(Moderation.KICK_MESSAGE)
	end
end

local function onJoin(player: Player)
	if table.find(MODERATION.BANNED_USER_IDS, player.UserId) then
		Telemetry.count("Moderation.bannedJoins")
		player:Kick(Moderation.BAN_MESSAGE)
	end
end

function Moderation.start()
	if started then
		return
	end
	started = true
	Telemetry.Flagged:Connect(onFlag)
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportPlayer") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, targetUserId: unknown, reason: unknown)
		local ok, result = pcall(Moderation.report, player, targetUserId, reason)
		if not ok then
			Telemetry.error("Moderation", result)
			return { ok = false, reason = "error" }
		end
		return result
	end
	Players.PlayerRemoving:Connect(function(player)
		flags[player] = nil
		sent[player] = nil
		-- Reports against someone who has left go with them.
		received[player.UserId] = nil
		reportFlagged[player.UserId] = nil
		for _, against in received do
			against[player.UserId] = nil
		end
	end)
end

return Moderation
