-- Shots on the wire. Every shot the server casts (CombatService: players'
-- and bots') is shown on every client: the bolt, the shooter's recoil and
-- sound, the puff where it stops, the compass's fight marker. None of it
-- counts for anything, so it goes on the Shots UnreliableRemoteEvent: a
-- lost one is a picture fewer, and a hit marker (CombatEvent "hit", like
-- "damaged" and "elimination", still reliable) never waits behind a queue
-- of them. Twenty Spritzers fire about 200 shots a second, so they're
-- batched: once a frame (Heartbeat) the frame's shots go out together as
-- flat arrays,
--   Shots(shooters: { number }, froms: { Vector3 }, tos: { Vector3 })
-- (a player's user ID, or a bot's negative ID; where the server cast the
-- shot from, its head; where it stopped), to every client, and a practice
-- yard's shots to their shooter alone. An unreliable event carries at most
-- 900 bytes, and a shot is about 35 (a number 9, each Vector3 13), so a
-- busy frame goes in events of MAX_PER_EVENT.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShotFeed = {}

-- Shots to an event: about 700 bytes, well inside an unreliable event's 900.
ShotFeed.MAX_PER_EVENT = 20

type Batch = { shooters: { number }, froms: { Vector3 }, tos: { Vector3 } }

local function newBatch(): Batch
	return { shooters = {}, froms = {}, tos = {} }
end

-- This frame's shots for everyone, and those for one player only.
local everyone = newBatch()
local only: { [Player]: Batch } = {}
local started = false

local shotsRemote: UnreliableRemoteEvent? = nil
local function remote(): UnreliableRemoteEvent
	if not (shotsRemote and shotsRemote.Parent) then
		shotsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shots") :: UnreliableRemoteEvent
	end
	return shotsRemote :: UnreliableRemoteEvent
end

-- Queues a shot from `shooter` cast from `from`, stopping at `to`, for the
-- next send: to everyone, or only to `onlyTo`. (Looked up on the module
-- each time, so a test can watch the shots as they're cast.)
function ShotFeed.add(shooter: number, from: Vector3, to: Vector3, onlyTo: Player?)
	local batch = everyone
	if onlyTo then
		batch = only[onlyTo] or newBatch()
		only[onlyTo] = batch
	end
	table.insert(batch.shooters, shooter)
	table.insert(batch.froms, from)
	table.insert(batch.tos, to)
end

-- `batch` sent by `send(shooters, froms, tos)`, MAX_PER_EVENT at a time.
local function deliver(batch: Batch, send: ({ number }, { Vector3 }, { Vector3 }) -> ())
	local count = #batch.shooters
	local size = ShotFeed.MAX_PER_EVENT
	if count <= size then
		send(batch.shooters, batch.froms, batch.tos)
		return
	end
	for first = 1, count, size do
		local last = math.min(count, first + size - 1)
		send(
			table.move(batch.shooters, first, last, 1, {}),
			table.move(batch.froms, first, last, 1, {}),
			table.move(batch.tos, first, last, 1, {})
		)
	end
end

-- Sends what's queued (each Heartbeat; a test may call it).
function ShotFeed.flush()
	if #everyone.shooters == 0 and next(only) == nil then
		return
	end
	local event = remote()
	if #everyone.shooters > 0 then
		local batch = everyone
		everyone = newBatch()
		deliver(batch, function(shooters, froms, tos)
			event:FireAllClients(shooters, froms, tos)
		end)
	end
	if next(only) then
		local batches = only
		only = {}
		for player, batch in batches do
			if player.Parent == Players then
				deliver(batch, function(shooters, froms, tos)
					event:FireClient(player, shooters, froms, tos)
				end)
			end
		end
	end
end

-- How many shots are waiting for the next send (for tests).
function ShotFeed.pending(): number
	local n = #everyone.shooters
	for _, batch in only do
		n += #batch.shooters
	end
	return n
end

function ShotFeed.start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(ShotFeed.flush)
	Players.PlayerRemoving:Connect(function(player)
		only[player] = nil
	end)
end

return ShotFeed
