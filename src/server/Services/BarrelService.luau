-- Gas barrels: every GasBarrel model in the map's Barrels folder. Shots
-- (and blasts) wear their health down; at zero the fuse burns for a moment
-- (the barrel's "FuseAt" attribute, so clients can outline it), then it
-- blasts gas onto the enemies of whoever fired the last shot or set off the
-- chain. Credit only ever goes to that one player, so it's never
-- ambiguous; a barrel nobody shot (no owner) can't go off. It disappears
-- and is back, full, after RESPAWN_SECONDS.
--   CombatEvent { kind = "barrel", position }   all clients
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local MapService = require(script.Parent.MapService)
local CombatService = require(script.Parent.CombatService)
local ExplosionService = require(script.Parent.ExplosionService)

local BARREL = GameConfig.BARREL

local BarrelService = {}

-- (owner?): a barrel went off; the owner is whoever finished it.
BarrelService.Exploded = Signal.new()

type Barrel = {
	model: Model,
	health: number,
	state: "ready" | "fused" | "gone",
	owner: Player?,
	ownerTeam: string?,
	depth: number,
}
local barrels: { [Model]: Barrel } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Hides or shows every part of the barrel. Shown, each part is as it was
-- first found (an invisible hitbox under the Blender mesh stays invisible,
-- and the mesh never collides).
local function setVisible(model: Model, visible: boolean)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			for _, key in { "Transparency", "CanCollide", "CanQuery" } do
				if item:GetAttribute(key) == nil then
					item:SetAttribute(key, (item :: any)[key])
				end
			end
			item.Transparency = if visible then item:GetAttribute("Transparency") :: number else 1
			item.CanCollide = visible and item:GetAttribute("CanCollide") == true
			item.CanQuery = visible and item:GetAttribute("CanQuery") == true
		end
	end
end

local function publish(barrel: Barrel)
	barrel.model:SetAttribute("Health", barrel.health)
	barrel.model:SetAttribute("Ready", barrel.state == "ready")
end

local function reset(barrel: Barrel)
	barrel.health = BARREL.HEALTH
	barrel.state = "ready"
	barrel.owner, barrel.ownerTeam, barrel.depth = nil, nil, 0
	barrel.model:SetAttribute("FuseAt", nil)
	setVisible(barrel.model, true)
	publish(barrel)
end

local function position(barrel: Barrel): Vector3
	return (barrel.model.PrimaryPart or barrel.model:FindFirstChildWhichIsA("BasePart") :: BasePart).Position
end

local function explode(barrel: Barrel)
	if barrel.state ~= "fused" or not barrel.model.Parent then
		return
	end
	barrel.state = "gone"
	barrel.model:SetAttribute("FuseAt", nil)
	local at = position(barrel)
	setVisible(barrel.model, false)
	publish(barrel)
	Telemetry.count("Barrel.explosions")
	BarrelService.Exploded:Fire(barrel.owner)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatEvent = remotes:WaitForChild("CombatEvent") :: RemoteEvent
	combatEvent:FireAllClients({ kind = "barrel", position = at })
	if barrel.ownerTeam then
		ExplosionService.blast({
			position = at,
			radius = BARREL.RADIUS,
			gas = BARREL.GAS,
			owner = barrel.owner,
			ownerTeam = barrel.ownerTeam,
			cause = "barrel",
			depth = barrel.depth,
		})
	end
	local model = barrel.model
	task.delay(BARREL.RESPAWN_SECONDS, function()
		if barrels[model] == barrel and barrel.state == "gone" then
			reset(barrel)
		end
	end)
end

-- Lights the fuse (once), crediting `owner` (the last shot or the chain).
local function fuse(barrel: Barrel, owner: Player?, ownerTeam: string?, depth: number)
	if barrel.state ~= "ready" then
		return
	end
	barrel.state = "fused"
	barrel.health = 0
	barrel.owner, barrel.ownerTeam, barrel.depth = owner, ownerTeam, depth
	barrel.model:SetAttribute("FuseAt", now() + BARREL.FUSE_SECONDS)
	publish(barrel)
	task.delay(BARREL.FUSE_SECONDS, explode, barrel)
end

-- A shot at a barrel part: health down; the last shot owns the explosion.
function BarrelService.shoot(shooter: Player, part: Instance, amount: number): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	local barrel = model and barrels[model]
	local team = TeamService.teamOf(shooter)
	if not (barrel and barrel.state == "ready" and team) then
		return false
	end
	barrel.health = math.max(0, barrel.health - amount)
	publish(barrel)
	if barrel.health <= 0 then
		-- A shot starts a chain at depth 1, like a shot elimination's blast.
		fuse(barrel, shooter, team, 1)
	end
	return true
end

function BarrelService.get(model: Model): Barrel?
	return barrels[model]
end

function BarrelService.all(): { Model }
	local list = {}
	for model in barrels do
		table.insert(list, model)
	end
	return list
end

-- Test-only: every barrel back, full.
function BarrelService.resetAll()
	for _, barrel in barrels do
		reset(barrel)
	end
end

local function register(map: Model)
	table.clear(barrels)
	local folder = map:FindFirstChild("Barrels")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model.Name == "GasBarrel" then
			local barrel: Barrel = { model = model, health = BARREL.HEALTH, state = "ready", owner = nil, ownerTeam = nil, depth = 0 }
			barrels[model] = barrel
			reset(barrel)
		end
	end
end

function BarrelService.start()
	if started then
		return
	end
	started = true
	MapService.Loaded:Connect(register)
	local map = MapService.current()
	if map then
		register(map)
	end
	CombatService.PartHit:Connect(function(shooter, part, weapon)
		BarrelService.shoot(shooter, part, weapon.gasPerHit)
	end)
	-- Blasts set off barrels in range (with a clear line), one step deeper.
	ExplosionService.Blasted:Connect(function(blast)
		for _, barrel in barrels do
			local at = position(barrel)
			if barrel.state == "ready" and (at - blast.position).Magnitude <= blast.radius
				and not ExplosionService.blocked(blast.position, at)
			then
				fuse(barrel, blast.owner, blast.ownerTeam, blast.depth + 1)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, barrel in barrels do
			if barrel.owner == player then
				barrel.owner = nil -- the team still owns the blast; nobody scores
			end
		end
	end)
end

return BarrelService
