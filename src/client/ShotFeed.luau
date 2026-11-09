-- Every shot the server announces, one at a time. They come on the Shots
-- UnreliableRemoteEvent a frame's worth at once, as flat arrays (the
-- server's ShotFeed): shooters { number }, froms { Vector3 }, tos
-- { Vector3 }. Each becomes the same table a CombatEvent "shot" used to
-- be, { kind = "shot", shooter, from, to }, for every listener: Combat (the
-- bolt and the shooter's gun sound), WeaponFx (the recoil, the muzzle, the
-- puff where it stopped) and the compass (the fight marker). Unreliable: a
-- lost batch is a few pictures fewer, never anything that counts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local ShotFeed = {}

-- (shot): each shot. Its listeners each run in a thread of their own, so
-- one that fails doesn't keep the shot from the others.
ShotFeed.Shot = Signal.new()
-- A batch longer than this isn't one the server sends.
ShotFeed.MAX_SHOTS = 100

local started = false

-- Takes one batch: each shot in it to every listener. False if it isn't a
-- batch (its shots aren't all there, or don't add up).
function ShotFeed.receive(shooters: unknown, froms: unknown, tos: unknown): boolean
	if type(shooters) ~= "table" or type(froms) ~= "table" or type(tos) ~= "table" then
		return false
	end
	local count = #shooters
	if count == 0 or count > ShotFeed.MAX_SHOTS or #froms ~= count or #tos ~= count then
		return false
	end
	for i = 1, count do
		local shooter, from, to = shooters[i], froms[i], tos[i]
		if type(shooter) == "number" and typeof(from) == "Vector3" and typeof(to) == "Vector3" then
			ShotFeed.Shot:Fire({ kind = "shot", shooter = shooter, from = from, to = to })
		end
	end
	return true
end

-- Hears the server's shots (once, however many listen).
function ShotFeed.start()
	if started then
		return
	end
	started = true
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shots") :: UnreliableRemoteEvent
	remote.OnClientEvent:Connect(ShotFeed.receive)
end

-- `handler(shot)` for every shot from now on.
function ShotFeed.listen(handler: ({ [string]: any }) -> ())
	ShotFeed.Shot:Connect(handler)
	ShotFeed.start()
end

return ShotFeed
