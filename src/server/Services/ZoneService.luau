-- Gas Control's zone (Phase 6). While a round of a zone mode is on, every
-- ZONE.TICK_SECONDS it counts each team's players standing in the map's
-- control zone (ACTIVE, alive, not mid-explosion). A team alone in it
-- scores ZONE.POINTS; two teams there contest it and nobody scores. Each
-- player holding it earns a little (ZONE.COINS and XP every
-- REWARD_SECONDS, a few times a round).
-- What clients see: Workspace's ZoneActive, ZoneOwner (team ID or nil),
-- ZoneContested and Zone_<team> (players in it) attributes, and the floor
-- ring in the holder's colour (white when contested, grey when empty).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local MapBase = require(Shared.Interfaces.MapBase)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local MapService = require(script.Parent.MapService)
local TeamService = require(script.Parent.TeamService)
local MatchScoreService = require(script.Parent.MatchScoreService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local GasService = require(script.Parent.GasService)
local EconomyService = require(script.Parent.EconomyService)
local RoundService = require(script.Parent.RoundService)

local ZONE = GameConfig.ZONE
local CONTESTED_COLOR = Color3.fromRGB(245, 242, 250)
local EMPTY_COLOR = Color3.fromRGB(150, 146, 160)

local ZoneService = {}

-- (owner?, contested): fires when who holds the zone changes.
ZoneService.Changed = Signal.new()

type Holder = { seconds: number, rewards: number }
local holders: { [Player]: Holder } = {}
local active = false
local owner: string? = nil
local contested = false
local started = false

-- The current map's control zone and its floor ring, if it has them.
function ZoneService.parts(): (BasePart?, BasePart?)
	local model, entry = MapService.current()
	if not (model and entry and entry.zone) then
		return nil, nil
	end
	local zone = MapBase.resolve(model, entry.zone)
	local ring = entry.zoneRing and MapBase.resolve(model, entry.zoneRing)
	return if zone and zone:IsA("BasePart") then zone else nil, if ring and ring:IsA("BasePart") then ring else nil
end

function ZoneService.inside(position: Vector3, zone: BasePart): boolean
	local localPoint = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- Whether a zone round is on right now.
function ZoneService.isActive(): boolean
	return active
end

-- Who holds it (nil if nobody or contested), and whether it's contested.
function ZoneService.state(): (string?, boolean)
	return owner, contested
end

local function publish(counts: { [string]: number })
	workspace:SetAttribute("ZoneActive", active)
	workspace:SetAttribute("ZoneOwner", owner)
	workspace:SetAttribute("ZoneContested", contested)
	for _, team in TeamConfig.order do
		workspace:SetAttribute(`Zone_{team}`, if active then counts[team] or 0 else nil)
	end
	local _, ring = ZoneService.parts()
	if ring then
		ring.Transparency = if active then 0.55 else 1
		ring.Color = if owner then TeamConfig.teams[owner].color elseif contested then CONTESTED_COLOR else EMPTY_COLOR
	end
end

local function standing(player: Player, zone: BasePart): boolean
	if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE or GasService.isExploding(player) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart") and ZoneService.inside(root.Position, zone)
end

function ZoneService.tick(dt: number)
	local zone = ZoneService.parts()
	local nowActive = zone ~= nil and RoundService.phase() == States.Phase.ACTIVE
		and RoundService.getMode().objective == "zone" and MatchScoreService.isOpen()
	if not nowActive then
		if active then
			active, owner, contested = false, nil, false
			publish({})
			ZoneService.Changed:Fire(nil, false)
		end
		return
	end
	active = true
	local counts: { [string]: number } = {}
	local inZone: { Player } = {}
	for _, player in Players:GetPlayers() do
		local team = TeamService.teamOf(player)
		if team and standing(player, zone :: BasePart) then
			counts[team] = (counts[team] or 0) + 1
			table.insert(inZone, player)
		end
	end
	local present = {}
	for team, n in counts do
		if n > 0 then
			table.insert(present, team)
		end
	end
	local newOwner = if #present == 1 then present[1] else nil
	local newContested = #present > 1
	if newOwner ~= owner or newContested ~= contested then
		owner, contested = newOwner, newContested
		ZoneService.Changed:Fire(owner, contested)
		if owner then
			Telemetry.count("Zone.captures")
		end
	end
	if owner and MatchScoreService.record({ team = owner, source = "zone" }, ZONE.POINTS) then
		Telemetry.count("Zone.points", ZONE.POINTS)
		local roundId = RoundService.snapshot().roundId
		for _, player in inZone do
			local holder = holders[player] or { seconds = 0, rewards = 0 }
			holders[player] = holder
			holder.seconds += dt
			if holder.seconds >= ZONE.REWARD_SECONDS and holder.rewards < ZONE.REWARDS_PER_ROUND then
				holder.seconds -= ZONE.REWARD_SECONDS
				holder.rewards += 1
				EconomyService.grant(player, `zone:{roundId}:{holder.rewards}`, "zone", ZONE.COINS, ZONE.XP)
			end
		end
	elseif contested then
		Telemetry.count("Zone.contestedSeconds", dt)
	end
	publish(counts)
end

function ZoneService.start()
	if started then
		return
	end
	started = true
	-- Holding rewards count per round.
	RoundService.PhaseChanged:Connect(function(phase)
		if phase == States.Phase.ACTIVE then
			table.clear(holders)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		holders[player] = nil
	end)
	publish({})
	Health.loop("Zone", ZONE.TICK_SECONDS, ZoneService.tick)
end

return ZoneService
