-- Every elimination goes through here, exactly once per life, whatever
-- caused it: the death gets an event ID, the killer's team a point (if the
-- round is open), the killer a streak, and other recent attackers an
-- assist. Kills in a row without dying build a streak; reaching
-- STREAK.ALPHA_AT tells the whole server "BRO IS THE ALPHA FART!" once.
-- Streaks end with any death; the best one is kept for the session.
--   CombatEvent { kind = "elimination", event, victim, killer?, team?, assists, cause }
--   CombatEvent { kind = "alpha", player, text }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local TeamService = require(script.Parent.TeamService)
local MatchScoreService = require(script.Parent.MatchScoreService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local STREAK = GameConfig.STREAK

local EliminationService = {}

-- (victim, killer?, assists, cause, eventId)
EliminationService.Eliminated = Signal.new()

export type Info = {
	killer: Player?,
	-- Teams as they were when the gas went in, so a player leaving or
	-- switching mid-countdown can't change who scores.
	killerTeam: string?,
	victimTeam: string?,
	assists: { Player }?,
	cause: string, -- "shot", "chain", "barrel", "test"
}

type Record = { streak: number, bestStreak: number, eliminations: number, deaths: number }
local records: { [Player]: Record } = {}
local done: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastEvent = 0
local nextAnnounceAt = 0
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function record(player: Player): Record
	local entry = records[player]
	if not entry then
		entry = { streak = 0, bestStreak = 0, eliminations = 0, deaths = 0 }
		records[player] = entry
	end
	return entry
end

local function combatEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
end

function EliminationService.streakOf(player: Player): number
	return record(player).streak
end

function EliminationService.bestStreakOf(player: Player): number
	return record(player).bestStreak
end

function EliminationService.statsOf(player: Player): Record
	return table.clone(record(player))
end

-- The whole server hears it, one announcement at a time.
local function announce(player: Player)
	local at = now()
	local when = math.max(at, nextAnnounceAt)
	nextAnnounceAt = when + STREAK.ANNOUNCE_GAP_SECONDS
	task.delay(when - at, function()
		Telemetry.log("Elimination", "alpha", { player = player })
		combatEvent():FireAllClients({ kind = "alpha", player = player.UserId, text = STREAK.ALPHA_TEXT })
	end)
end

-- Ends `victim`'s life on `character` and credits it. Returns the death's
-- event ID, or nil if that life was already over.
function EliminationService.eliminate(victim: Player, character: Model, info: Info): number?
	if done[character] then
		return nil
	end
	lastEvent += 1
	local eventId = lastEvent
	done[character] = eventId

	local victimTeam = info.victimTeam or TeamService.teamOf(victim)
	local killer = info.killer
	local killerTeam = if killer then info.killerTeam or TeamService.teamOf(killer) else nil
	if killer and (killer == victim or killerTeam == nil or killerTeam == victimTeam) then
		killer, killerTeam = nil, nil
	end
	local assists = {}
	if info.assists then
		for _, helper in info.assists do
			if helper ~= killer and helper ~= victim and helper.Parent == Players then
				table.insert(assists, helper)
			end
		end
	end

	local counted = false
	if killer and killerTeam then
		counted = MatchScoreService.recordElimination({
			team = killerTeam,
			source = "elimination",
			killer = killer,
			victim = victim,
			killerTeam = killerTeam,
			victimTeam = victimTeam,
		})
		local entry = record(killer)
		entry.eliminations += 1
		entry.streak += 1
		entry.bestStreak = math.max(entry.bestStreak, entry.streak)
		if entry.streak == STREAK.ALPHA_AT then
			announce(killer)
		end
		Telemetry.first(killer, "elimination")
	end
	record(victim).deaths += 1
	Telemetry.count(`Elimination.cause.{info.cause}`)
	Telemetry.log("Elimination", "elimination", {
		event = eventId,
		victim = victim,
		killer = killer,
		assists = #assists,
		cause = info.cause,
		counted = counted,
	})

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end

	local assistIds = {}
	for _, helper in assists do
		table.insert(assistIds, helper.UserId)
	end
	combatEvent():FireAllClients({
		kind = "elimination",
		event = eventId,
		victim = victim.UserId,
		killer = if killer then killer.UserId else nil,
		team = killerTeam,
		assists = assistIds,
		cause = info.cause,
	})
	EliminationService.Eliminated:Fire(victim, killer, assists, info.cause, eventId)
	return eventId
end

function EliminationService.start()
	if started then
		return
	end
	started = true
	-- Any death, eliminated or not (a fall), ends the streak.
	PlayerLifecycleService.Died:Connect(function(player)
		record(player).streak = 0
	end)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
end

return EliminationService
