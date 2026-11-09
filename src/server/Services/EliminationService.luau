-- Every elimination goes through here, exactly once per life, whatever
-- caused it: the death gets an event ID, the killer's team a point (if the
-- round is open, or the explosion was already counting down at its buzzer),
-- the killer a streak, and other recent attackers an assist. Kills in a row
-- without dying build a streak; reaching STREAK.ALPHA_AT tells the whole
-- server "BRO IS THE ALPHA FART!" once.
-- Streaks end with any death; the best one is kept for the session.
-- Other services hear about it through Eliminated and Alpha (rewards).
-- Bots (BotService) score and show in the kill feed like players, by their
-- negative ids, but earn nothing: a bot's death never fires Eliminated, a
-- player killed by a bot fires it with no killer (and `killerBot`), and
-- kills of or by bots build no streak.
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

-- (Elimination): a death was credited.
EliminationService.Eliminated = Signal.new()
-- (player, eventId): `player` reached STREAK.ALPHA_AT with that kill.
EliminationService.Alpha = Signal.new()
-- (Credit): every elimination, of a player or a bot, by the ids the kill
-- feed uses; the round's awards (AwardService) count from it.
EliminationService.Credited = Signal.new()

export type Info = {
	killer: Player?,
	-- A bot killer (its id), in place of `killer`; killerTeam is then needed.
	killerBot: number?,
	-- Teams as they were when the gas went in, so a player leaving or
	-- switching mid-countdown can't change who scores.
	killerTeam: string?,
	victimTeam: string?,
	assists: { Player }?,
	-- Bots that helped (kill feed only).
	assistBots: { number }?,
	cause: string, -- "shot", "chain", "barrel", "lob", "cloud", "pulse", "died" (reset or fell while gassed), "test"
	-- The weapon that set off the explosion (its shot, stink bomb or cloud).
	weapon: string?,
	-- An explosion's: when its countdown started. One finished before the
	-- buzzer scores though it lands after (MatchScoreService.counts).
	countdownAt: number?,
}
export type Elimination = {
	event: number,
	victim: Player,
	killer: Player?,
	-- The bot that got the kill (then `killer` is nil: bots earn nothing).
	killerBot: number?,
	assists: { Player },
	cause: string,
	weapon: string?,
	-- Whether it scored for the round (the round was live).
	counted: boolean,
}
-- What Credited carries: a player's UserId or a bot's BotId for each.
export type Credit = {
	victim: number,
	killer: number?,
	assists: { number },
	cause: string,
	-- An explosion's countdown start (Info.countdownAt).
	countdownAt: number?,
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

-- The killer's team, or nil if there's no killer who can score: nobody
-- scores off themselves or a teammate.
local function scoringTeam(killer: Player?, killerBot: number?, info: Info, victimTeam: string?): string?
	local team = if killer then info.killerTeam or TeamService.teamOf(killer) elseif killerBot then info.killerTeam else nil
	return if team ~= nil and team ~= victimTeam then team else nil
end

-- Recent attackers other than the killer who are still here and not (now)
-- on the victim's team, as players and as IDs for the kill feed.
local function helpers(info: Info, killer: Player?, victim: Player?, victimTeam: string?): ({ Player }, { number })
	local assists, ids = {}, {}
	if info.assists then
		for _, helper in info.assists do
			-- Not someone who has since joined the victim's team.
			if helper ~= killer and helper ~= victim and helper.Parent == Players and TeamService.teamOf(helper) ~= victimTeam then
				table.insert(assists, helper)
				table.insert(ids, helper.UserId)
			end
		end
	end
	for _, id in info.assistBots or {} do
		if id ~= info.killerBot then
			table.insert(ids, id)
		end
	end
	return assists, ids
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
	local killer = if info.killer ~= victim then info.killer else nil
	local killerBot = if killer then nil else info.killerBot
	local killerTeam = scoringTeam(killer, killerBot, info, victimTeam)
	if not killerTeam then
		killer, killerBot = nil, nil
	end
	local assists, assistIds = helpers(info, killer, victim, victimTeam)

	local counted = false
	if killerTeam then
		counted = MatchScoreService.recordElimination({
			team = killerTeam,
			source = "elimination",
			killer = killer,
			killerBot = killerBot,
			victim = victim,
			killerTeam = killerTeam,
			victimTeam = victimTeam,
			countdownAt = info.countdownAt,
		})
	end
	if killer then
		local entry = record(killer)
		entry.eliminations += 1
		entry.streak += 1
		entry.bestStreak = math.max(entry.bestStreak, entry.streak)
		if entry.streak == STREAK.ALPHA_AT then
			announce(killer)
			EliminationService.Alpha:Fire(killer, eventId)
		end
		Telemetry.first(killer, "elimination")
	end
	record(victim).deaths += 1
	Telemetry.count(`Elimination.cause.{info.cause}`)
	Telemetry.log("Elimination", "elimination", {
		event = eventId,
		victim = victim,
		killer = killer or killerBot,
		assists = #assistIds,
		cause = info.cause,
		counted = counted,
	})

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end

	combatEvent():FireAllClients({
		kind = "elimination",
		event = eventId,
		victim = victim.UserId,
		killer = if killer then killer.UserId else killerBot,
		team = killerTeam,
		assists = assistIds,
		cause = info.cause,
	})
	local elimination: Elimination = {
		event = eventId,
		victim = victim,
		killer = killer,
		killerBot = killerBot,
		assists = assists,
		cause = info.cause,
		weapon = if killer then info.weapon else nil,
		counted = counted,
	}
	EliminationService.Eliminated:Fire(elimination)
	EliminationService.Credited:Fire({
		victim = victim.UserId,
		killer = if killer then killer.UserId else killerBot,
		assists = assistIds,
		cause = info.cause,
		countdownAt = info.countdownAt,
	} :: Credit)
	return eventId
end

-- The same for a bot (`victim` is its id; info.victimTeam is needed): the
-- point, the kill feed and the avatar's death, but no Eliminated (nobody
-- earns anything off a bot) and no streak. Returns the event ID, or nil
-- if that life was already over.
function EliminationService.eliminateBot(victim: number, character: Model, info: Info): number?
	if done[character] then
		return nil
	end
	lastEvent += 1
	local eventId = lastEvent
	done[character] = eventId

	local victimTeam = info.victimTeam
	local killer = info.killer
	local killerBot = if killer or info.killerBot == victim then nil else info.killerBot
	local killerTeam = scoringTeam(killer, killerBot, info, victimTeam)
	if not killerTeam then
		killer, killerBot = nil, nil
	end
	local _, assistIds = helpers(info, killer, nil, victimTeam)

	local counted = false
	if killerTeam then
		counted = MatchScoreService.recordElimination({
			team = killerTeam,
			source = "elimination",
			killer = killer,
			killerBot = killerBot,
			victimBot = victim,
			killerTeam = killerTeam,
			victimTeam = victimTeam,
			countdownAt = info.countdownAt,
		})
	end
	Telemetry.count(`Elimination.cause.{info.cause}`)
	Telemetry.log("Elimination", "botElimination", {
		event = eventId,
		victim = victim,
		killer = killer or killerBot,
		assists = #assistIds,
		cause = info.cause,
		counted = counted,
	})

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end

	combatEvent():FireAllClients({
		kind = "elimination",
		event = eventId,
		victim = victim,
		killer = if killer then killer.UserId else killerBot,
		team = killerTeam,
		assists = assistIds,
		cause = info.cause,
	})
	EliminationService.Credited:Fire({
		victim = victim,
		killer = if killer then killer.UserId else killerBot,
		assists = assistIds,
		cause = info.cause,
		countdownAt = info.countdownAt,
	} :: Credit)
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
