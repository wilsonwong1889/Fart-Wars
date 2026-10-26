-- Blasts: what an explosion does to everyone around it. A player who
-- explodes blasts the killer's enemies nearby with gas, credited to the
-- killer, which can set off more players (and, through BarrelService,
-- barrels): a chain reaction. A blast never touches the owner's own team
-- (friendly fire stays off) or anyone behind a wall from it. Each step of a
-- chain is one deeper; past EXPLOSION.CHAIN_MAX_DEPTH it stops. Blasts
-- queue up and at most PER_TICK resolve each tick, so a big chain costs a
-- few frames, not one spike. An explosion with nobody to credit (no killer)
-- blasts nobody.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local MapService = require(script.Parent.MapService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local GasService = require(script.Parent.GasService)

local EXPLOSION = GameConfig.EXPLOSION

local ExplosionService = {}

export type Blast = {
	position: Vector3,
	radius: number,
	gas: number,
	owner: Player?,
	ownerTeam: string,
	cause: string, -- "chain" or "barrel"
	depth: number,
	-- Who caused it (doesn't take its own blast).
	source: Player?,
}

-- (blast): a blast resolved; BarrelService sets off barrels in range.
ExplosionService.Blasted = Signal.new()

local queue: { Blast } = {}
local started = false

function ExplosionService.pending(): number
	return #queue
end

-- Queues a blast (dropped if the chain is already too deep).
function ExplosionService.blast(blast: Blast)
	if blast.depth > EXPLOSION.CHAIN_MAX_DEPTH then
		Telemetry.count("Explosion.depthCapped")
		return
	end
	table.insert(queue, blast)
end

-- Whether a wall or cover stands between the blast and `position`.
function ExplosionService.blocked(from: Vector3, to: Vector3): boolean
	local map = MapService.current()
	if not map then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local solid = {}
	for _, name in { "Walls", "Cover" } do
		local folder = map:FindFirstChild(name)
		if folder then
			table.insert(solid, folder)
		end
	end
	params.FilterDescendantsInstances = solid
	return workspace:Raycast(from, to - from, params) ~= nil
end

local function resolve(blast: Blast)
	Telemetry.count("Explosion.blasts")
	for _, player in Players:GetPlayers() do
		local team = TeamService.teamOf(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if player ~= blast.source and team and team ~= blast.ownerTeam
			and PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE
			and root and root:IsA("BasePart")
			and (root.Position - blast.position).Magnitude <= blast.radius
			and not ExplosionService.blocked(blast.position, root.Position)
		then
			GasService.add(player, blast.gas, {
				attacker = blast.owner,
				team = blast.ownerTeam,
				cause = blast.cause,
				chainDepth = blast.depth,
			})
		end
	end
	ExplosionService.Blasted:Fire(blast)
end

-- Resolves up to PER_TICK queued blasts, oldest first.
function ExplosionService.step()
	for _ = 1, math.min(EXPLOSION.PER_TICK, #queue) do
		resolve(table.remove(queue, 1) :: Blast)
	end
end

function ExplosionService.start()
	if started then
		return
	end
	started = true
	-- A player explosion blasts the killer's enemies around it.
	GasService.Exploded:Connect(function(victim, position, killer, depth, killerTeam)
		if killerTeam then
			ExplosionService.blast({
				position = position,
				radius = EXPLOSION.RADIUS,
				gas = EXPLOSION.CHAIN_GAS,
				owner = killer,
				ownerTeam = killerTeam,
				cause = "chain",
				depth = depth + 1,
				source = victim,
			})
		end
	end)
	task.spawn(function()
		while true do
			task.wait(EXPLOSION.TICK_SECONDS)
			ExplosionService.step()
		end
	end)
end

return ExplosionService
