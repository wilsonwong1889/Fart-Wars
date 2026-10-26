-- Moves idle ACTIVE players off their team. The server decides what counts
-- as activity, conservatively: the avatar travelling AFK_MOVE_STUDS across
-- the ground from where it last proved activity, or another server system
-- calling markActive (Phase 2 weapons will). A held key, a jump on the spot
-- or a remote ping proves nothing. A new avatar (a spawn) isn't activity.
--   AFK_WARNING_SECONDS idle  -> "BRO FELL ASLEEP MID-FART!"
--   AFK_SPECTATE_SECONDS idle -> AFK_SPECTATOR, avatar removed, slot freed
-- An AFK spectator can watch and use the menus; PLAY puts them back through
-- the normal team rules. Their round clock is paused while they're out.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local UIConfig = require(Shared.Config.UIConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Messages = require(Server.Messages)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local PlayerState = States.Player

local AFKService = {}

type Watch = { character: Model?, anchor: Vector3?, warned: boolean }
local watching: { [Player]: Watch } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Server systems call this for meaningful actions (moving is noticed here).
function AFKService.markActive(player: Player)
	local runtime = PlayerLifecycleService.get(player)
	if not runtime or runtime.state ~= PlayerState.ACTIVE then
		return
	end
	runtime.lastMeaningfulActivityAt = now()
	local watch = watching[player]
	if watch and watch.warned then
		watch.warned = false
		Messages.send(player, "afkClear", "")
	end
end

local function noticeMovement(player: Player, watch: Watch)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = root.Position
	if watch.character ~= character or not watch.anchor then
		watch.character, watch.anchor = character, position
		return
	end
	local anchor = watch.anchor :: Vector3
	local travelled = Vector3.new(position.X - anchor.X, 0, position.Z - anchor.Z).Magnitude
	if travelled >= GameConfig.AFK_MOVE_STUDS then
		watch.anchor = position
		AFKService.markActive(player)
	end
end

-- One pass over every active player (the loop runs this every second).
function AFKService.check(at: number)
	for _, player in Players:GetPlayers() do
		local runtime = PlayerLifecycleService.get(player)
		if not runtime or runtime.state ~= PlayerState.ACTIVE then
			watching[player] = nil
			continue
		end
		local watch = watching[player]
		if not watch then
			watch = { character = nil, anchor = nil, warned = false }
			watching[player] = watch
		end
		noticeMovement(player, watch)
		local idle = at - runtime.lastMeaningfulActivityAt
		if idle >= GameConfig.AFK_SPECTATE_SECONDS then
			watching[player] = nil
			PlayerLifecycleService.toSpectator(player, PlayerState.AFK_SPECTATOR)
			Messages.send(player, "afkMoved", "You were moved to spectators for being AFK. Press PLAY to jump back in.")
		elseif idle >= GameConfig.AFK_WARNING_SECONDS and not watch.warned then
			watch.warned = true
			Messages.send(player, "afkWarning", UIConfig.afkWarning, {
				detail = "Move, or you'll be moved to spectators.",
				endsAt = runtime.lastMeaningfulActivityAt + GameConfig.AFK_SPECTATE_SECONDS,
			})
		end
	end
end

function AFKService.start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(player)
		watching[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(GameConfig.AFK_TICK_SECONDS)
			AFKService.check(now())
		end
	end)
end

return AFKService
