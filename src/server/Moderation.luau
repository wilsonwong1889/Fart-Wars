-- Moderation hooks. Everything suspicious reaches here as a Telemetry flag
-- (an abnormal rate of refused requests, near-perfect accuracy, impossible
-- movement, anomalous coin gains, dashing through walls). Each is counted
-- per player; GameConfig.MODERATION decides what happens: by default
-- nothing beyond the log (review only), or a kick at KICK_AT_FLAGS. Banned
-- user IDs are turned away on joining. Nothing here acts on a client's word.
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
local started = false

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
	Players.PlayerRemoving:Connect(function(player)
		flags[player] = nil
	end)
end

return Moderation
