-- Blasts: what an explosion does to everyone around it. A player who
-- explodes blasts the killer's enemies nearby with gas, credited to the
-- killer, which can set off more players (and, through BarrelService,
-- barrels): a chain reaction. A blast never touches the owner's own team
-- (friendly fire stays off) or anyone behind a wall from it. Each step of a
-- chain is one deeper; past EXPLOSION.CHAIN_MAX_DEPTH it stops. Blasts
-- queue up and at most PER_TICK resolve each tick, so a big chain costs a
-- few frames, not one spike. A killer who has left still blasts for their
-- team, credited to nobody; an explosion with no team behind it (a test
-- gas) blasts nobody. Bots are in it like players: a blast gasses enemy
-- bots, an exploding bot blasts its killer's enemies (BotService.Exploded),
-- and a bot's blast is credited to that bot. A blast from an explosion
-- carries that explosion's chain (Chain), so whatever it sets off counts on
-- as the next link; a stink bomb's or Gas Pulse's carries none.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local Chain = require(Server.Chain)
local TeamService = require(script.Parent.TeamService)
local MapService = require(script.Parent.MapService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local GasService = require(script.Parent.GasService)
local BotService = require(script.Parent.BotService)

local EXPLOSION = GameConfig.EXPLOSION

local ExplosionService = {}

export type Blast = {
	position: Vector3,
	radius: number,
	gas: number,
	owner: Player?,
	-- A bot that owns it (its id), in place of `owner`.
	ownerBot: number?,
	ownerTeam: string,
	cause: string, -- "chain", "barrel", "lob" (a stink bomb), "pulse" (Gas Pulse)
	depth: number,
	-- Who caused it (doesn't take its own blast).
	source: Player?,
	sourceBot: number?,
	-- The weapon behind it, for mastery (stink bombs).
	weapon: string?,
	-- The chain reaction of the explosion behind it (none for a stink bomb
	-- or Gas Pulse): whatever it sets off is that chain's next link.
	chain: Chain.Chain?,
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

local function reaches(blast: Blast, root: Instance?): boolean
	return root ~= nil and root:IsA("BasePart")
		and (root.Position - blast.position).Magnitude <= blast.radius
		and not ExplosionService.blocked(blast.position, root.Position)
end

local function resolve(blast: Blast)
	Telemetry.count("Explosion.blasts")
	-- A bot that has gone still blasts for its team, credited to nobody;
	-- one that has since changed teams doesn't gas its new teammates.
	local ownerBot = blast.ownerBot and BotService.get(blast.ownerBot)
	local source: GasService.Source = {
		attacker = blast.owner,
		bot = ownerBot and ownerBot.id,
		team = blast.ownerTeam,
		cause = blast.cause,
		chainDepth = blast.depth,
		chain = blast.chain,
		weapon = blast.weapon,
	}
	for _, player in Players:GetPlayers() do
		local team = TeamService.teamOf(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if player ~= blast.source and team and team ~= blast.ownerTeam
			and not (ownerBot and ownerBot.team == team)
			and PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE
			and reaches(blast, root)
		then
			GasService.add(player, blast.gas, source)
		end
	end
	for _, bot in BotService.all() do
		if bot.id ~= blast.sourceBot and bot.team ~= blast.ownerTeam and reaches(blast, BotService.rootOf(bot)) then
			BotService.addGas(bot, blast.gas, source)
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
	-- A player or bot explosion blasts the killer's enemies around it.
	GasService.Exploded:Connect(function(victim, position, killer, depth, killerTeam, killerBot, chain)
		if killerTeam then
			ExplosionService.blast({
				position = position,
				radius = EXPLOSION.RADIUS,
				gas = EXPLOSION.CHAIN_GAS,
				owner = killer,
				ownerBot = killerBot,
				ownerTeam = killerTeam,
				cause = "chain",
				depth = depth + 1,
				source = victim,
				chain = chain,
			})
		end
	end)
	BotService.Exploded:Connect(function(bot, position, killer, depth, killerTeam, killerBot, chain)
		if killerTeam then
			ExplosionService.blast({
				position = position,
				radius = EXPLOSION.RADIUS,
				gas = EXPLOSION.CHAIN_GAS,
				owner = killer,
				ownerBot = killerBot,
				ownerTeam = killerTeam,
				cause = "chain",
				depth = depth + 1,
				sourceBot = bot.id,
				chain = chain,
			})
		end
	end)
	Health.loop("Explosions", EXPLOSION.TICK_SECONDS, function()
		ExplosionService.step()
	end)
end

return ExplosionService
