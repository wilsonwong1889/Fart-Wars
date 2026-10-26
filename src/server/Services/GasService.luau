-- The gas meter, which replaces health. Only enemy hits and explosions put
-- gas in (friendly fire is off, and protected or non-active players take
-- none); it's clamped at 100. Five seconds without taking gas, it starts
-- draining at 5% a second; taking gas stops that. At 100 the player can't
-- fire or dash, a one-second countdown runs, and they explode: the last
-- enemy to add gas is the killer and other recent attackers assist. A
-- player who leaves or is moved off their team mid-countdown explodes on
-- the spot, so the killer still gets the credit.
-- Clients see it on the character: "Gas" (0-100), "GasStage" (0-4) and
-- "ExplodesAt" (server time).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local EliminationService = require(script.Parent.EliminationService)

local GAS = GameConfig.GAS

local GasService = {}

-- (victim, position, killer?, chainDepth): someone exploded.
GasService.Exploded = Signal.new()

export type Source = {
	attacker: Player?,
	-- The attacker's team when the gas was sent (explosions keep it).
	team: string?,
	cause: string, -- "shot", "chain", "barrel", "test"
	chainDepth: number?,
	-- The weapon that fired it (shots only), for weapon mastery.
	weapon: string?,
}

type Meter = {
	character: Model,
	gas: number,
	stage: number,
	lastHitAt: number,
	firstHitAt: number?,
	contributors: { [Player]: number },
	lastAttacker: Player?,
	lastAttackerTeam: string?,
	victimTeam: string?,
	exploding: boolean,
	exploded: boolean,
	cause: string,
	chainDepth: number,
	weapon: string?,
}
local meters: { [Player]: Meter } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

-- 0 normal, 1 slight inflation, 2 obvious, 3 critical, 4 exploding.
function GasService.stageOf(gas: number): number
	local stage = 0
	for i, threshold in GAS.STAGES do
		if gas >= threshold then
			stage = i
		end
	end
	return stage
end

-- The meter for the player's current avatar (a new avatar, a new meter).
local function meter(player: Player): Meter?
	local character = player.Character
	if not character then
		return nil
	end
	local existing = meters[player]
	if existing and existing.character == character then
		return existing
	end
	local fresh: Meter = {
		character = character,
		gas = 0,
		stage = 0,
		lastHitAt = -math.huge,
		firstHitAt = nil,
		contributors = {},
		lastAttacker = nil,
		lastAttackerTeam = nil,
		victimTeam = TeamService.teamOf(player),
		exploding = false,
		exploded = false,
		cause = "shot",
		chainDepth = 0,
		weapon = nil,
	}
	meters[player] = fresh
	return fresh
end

local function publish(m: Meter)
	local rounded = math.round(m.gas)
	if m.character:GetAttribute("Gas") ~= rounded then
		m.character:SetAttribute("Gas", rounded)
	end
	local stage = GasService.stageOf(m.gas)
	if stage ~= m.stage or m.character:GetAttribute("GasStage") == nil then
		m.stage = stage
		m.character:SetAttribute("GasStage", stage)
	end
end

function GasService.gasOf(player: Player): number
	local m = meters[player]
	return if m and m.character == player.Character then m.gas else 0
end

function GasService.isExploding(player: Player): boolean
	local m = meters[player]
	return m ~= nil and m.character == player.Character and m.exploding
end

-- Blows up `victim` now (the countdown's end, or they're leaving).
function GasService.explode(victim: Player)
	local m = meters[victim]
	if not m or not m.exploding or m.exploded then
		return
	end
	m.exploded = true
	local root = m.character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else m.character:GetPivot().Position
	local at = now()
	local killer = m.lastAttacker
	if killer and killer.Parent ~= Players then
		killer = nil
	end
	local assists = {}
	for helper, when in m.contributors do
		if helper ~= killer and at - when <= GAS.ASSIST_WINDOW_SECONDS then
			table.insert(assists, helper)
		end
	end
	table.sort(assists, function(a, b)
		return a.UserId < b.UserId
	end)
	if m.firstHitAt then
		Telemetry.time("timeToExplosion", at - m.firstHitAt)
	end
	EliminationService.eliminate(victim, m.character, {
		killer = killer,
		killerTeam = m.lastAttackerTeam,
		victimTeam = m.victimTeam,
		assists = assists,
		cause = m.cause,
		weapon = m.weapon,
	})
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatEvent = remotes:WaitForChild("CombatEvent") :: RemoteEvent
	combatEvent:FireAllClients({
		kind = "explosion",
		victim = victim.UserId,
		position = position,
		killer = if killer then killer.UserId else nil,
	})
	GasService.Exploded:Fire(victim, position, killer, m.chainDepth, m.lastAttackerTeam)
end

local function beginExplosion(victim: Player, m: Meter, source: Source)
	m.exploding = true
	m.cause = source.cause
	m.chainDepth = source.chainDepth or 0
	m.weapon = source.weapon
	local character = m.character
	character:SetAttribute("ExplodesAt", now() + GAS.EXPLOSION_COUNTDOWN_SECONDS)
	Telemetry.count("Gas.countdowns")
	task.delay(GAS.EXPLOSION_COUNTDOWN_SECONDS, function()
		if meters[victim] == m and m.character == character then
			GasService.explode(victim)
		end
	end)
end

-- Adds gas to `victim` from `source`. Returns whether any went in.
function GasService.add(victim: Player, amount: number, source: Source): boolean
	if not FeatureFlags.GAS_COMBAT or amount <= 0 then
		return false
	end
	local victimTeam = TeamService.teamOf(victim)
	local attacker = source.attacker
	local attackerTeam = source.team or (attacker and TeamService.teamOf(attacker))
	if not victimTeam or attacker == victim or (attackerTeam ~= nil and attackerTeam == victimTeam) then
		return false -- friendly fire is off
	end
	if PlayerLifecycleService.stateOf(victim) ~= States.Player.ACTIVE or PlayerLifecycleService.isProtected(victim) then
		return false
	end
	local humanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	local m = meter(victim)
	if not (humanoid and humanoid.Health > 0 and m) or m.exploding then
		return false
	end
	local at = now()
	m.firstHitAt = m.firstHitAt or at
	m.gas = math.min(100, m.gas + amount)
	m.lastHitAt = at
	m.victimTeam = victimTeam
	if attacker then
		m.contributors[attacker] = at
		m.lastAttacker = attacker
		m.lastAttackerTeam = attackerTeam
	end
	publish(m)
	if m.gas >= 100 then
		beginExplosion(victim, m, source)
	end
	return true
end

-- Recovery: everyone who hasn't taken gas for a while drains.
function GasService.tick(dt: number)
	local at = now()
	for _, m in meters do
		if not m.exploding and m.gas > 0 and at - m.lastHitAt >= GAS.RECOVERY_DELAY_SECONDS then
			local before = m.gas
			m.gas = math.max(0, m.gas - GAS.RECOVERY_PER_SECOND * dt)
			Telemetry.count("Gas.recovered", before - m.gas)
			if m.gas == 0 then
				m.firstHitAt = nil
				table.clear(m.contributors)
			end
			publish(m)
		end
	end
end

-- Test-only: set a player's gas directly (100 starts the countdown, with
-- no killer).
function GasService.testSetGas(player: Player, value: number): boolean
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return false
	end
	local m = meter(player)
	if not m or m.exploding then
		return false
	end
	m.gas = math.clamp(value, 0, 100)
	m.lastHitAt = now()
	publish(m)
	if m.gas >= 100 then
		beginExplosion(player, m, { cause = "test" })
	end
	return true
end

function GasService.reset(player: Player)
	local m = meters[player]
	if m and not m.exploding then
		m.gas = 0
		m.firstHitAt = nil
		table.clear(m.contributors)
		publish(m)
	end
end

function GasService.start()
	if started then
		return
	end
	started = true
	PlayerLifecycleService.Spawned:Connect(function(player)
		local m = meter(player)
		if m then
			publish(m)
		end
	end)
	-- Off the team mid-countdown (leaving, spectating, AFK): explode now.
	PlayerLifecycleService.Leaving:Connect(function(player)
		if GasService.isExploding(player) then
			GasService.explode(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if GasService.isExploding(player) then
			GasService.explode(player)
		end
		meters[player] = nil
		for _, m in meters do
			m.contributors[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(GAS.TICK_SECONDS)
			GasService.tick(dt)
		end
	end)
end

return GasService
