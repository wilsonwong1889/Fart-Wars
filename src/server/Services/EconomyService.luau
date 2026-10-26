-- Coins, XP, levels and stats. Every reward is a server-side transaction
-- with a unique ID (from the elimination's event ID, or the session's
-- participation step), refused if it's a repeat or outside the per-grant
-- limits, and kept in the profile's ledger. A reward for a player whose
-- profile hasn't loaded yet waits for it, so nothing earned is lost; it's
-- in the profile the moment it's granted, whatever the client is showing.
-- Coins are spendable; XP only fills levels. Levels 1-50 follow
-- ProgressionConfig's curve; each level's unlock is granted (abilities,
-- cosmetics) or announced (shop weapons). Level 50 pays the cap reward and
-- every CAP_REPEAT_XP after that pays again; LifetimeXP never stops.
-- Participation counts only ACTIVE time (AFK and spectating don't), so
-- idling earns nothing. Weapon mastery counts eliminations made with each
-- weapon's shots and pays each milestone once. With
-- FeatureFlags.PROGRESSION off nothing is paid; stats still count.
--   ProgressEvent { kind = "grant", id, reason, coins, xp }
--   ProgressEvent { kind = "levelUp", level, unlocks = { text }, coins }
--   ProgressEvent { kind = "mastery", weapon, badge, eliminations, coins }
-- The HUD reads player attributes: Coins, Level, XP, XPToNext, LifetimeXP.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local States = require(Shared.States)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local DataService = require(script.Parent.DataService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local EliminationService = require(script.Parent.EliminationService)

type Data = DataService.Data
type Event = { [string]: any }

local GRANTS = ProgressionConfig.grants
local COMBAT_REASONS = { elimination = true, assist = true, chainBonus = true, alpha = true }

local EconomyService = {}

EconomyService.TICK_SECONDS = 1

-- (player): what they own or have earned changed (a level's unlock, a
-- badge), beyond coins and XP.
EconomyService.Changed = Signal.new()

type Session = {
	-- Grant IDs already paid this session.
	granted: { [string]: boolean },
	-- Changes waiting for the profile to load.
	pending: { (Data, { Event }) -> () },
	activeSeconds: number,
	-- Participation steps reached (minutes).
	reached: { [number]: boolean },
	-- Active seconds not yet in TotalPlaytime (the profile isn't loaded).
	unsavedPlaytime: number,
	earned: number,
	-- Combat coins in the last minute, for the anomaly check.
	recent: { { at: number, coins: number } },
	flagged: boolean,
}
local sessions: { [Player]: Session } = {}
local testGrants = 0
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function progressEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProgressEvent") :: RemoteEvent
end

local function jobTag(): string
	return if game.JobId ~= "" then string.sub(game.JobId, 1, 8) else "studio"
end

-- XP still needed for the next level (at the cap, for the next repeat).
function EconomyService.xpToNext(data: Data): number
	return if data.Level < ProgressionConfig.MAX_LEVEL
		then ProgressionConfig.xpToNext(data.Level)
		else ProgressionConfig.CAP_REPEAT_XP
end

-- Refreshes the HUD attributes from the profile.
function EconomyService.publish(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = profile.data
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPToNext", EconomyService.xpToNext(data))
	player:SetAttribute("LifetimeXP", data.LifetimeXP)
end

-- Runs `change` on the player's profile now, or as soon as it loads; then
-- refreshes the HUD and tells the client what happened.
local function withProfile(player: Player, change: (Data, { Event }) -> ())
	local session = sessions[player]
	if not session then
		return
	end
	if not DataService.isLoaded(player) then
		table.insert(session.pending, change)
		return
	end
	local events = {}
	DataService.update(player, function(data)
		change(data, events)
	end)
	EconomyService.publish(player)
	local remote = progressEvent()
	local changed = false
	for _, event in events do
		remote:FireClient(player, event)
		changed = changed or event.kind == "levelUp" or event.kind == "mastery"
	end
	if changed then
		EconomyService.Changed:Fire(player)
	end
end

local function addToLedger(data: Data, id: string, reason: string, coins: number, xp: number)
	table.insert(data.Ledger, { id = `{jobTag()}:{id}`, reason = reason, coins = coins, xp = xp, at = os.time() })
	while #data.Ledger > ProgressionConfig.LEDGER_SIZE do
		table.remove(data.Ledger, 1)
	end
end

local function checkAnomaly(player: Player, session: Session, coins: number)
	local at = now()
	table.insert(session.recent, { at = at, coins = coins })
	local total = 0
	for i = #session.recent, 1, -1 do
		local entry = session.recent[i]
		if at - entry.at > 60 then
			table.remove(session.recent, i)
		else
			total += entry.coins
		end
	end
	if total > ProgressionConfig.ANOMALY_COINS_PER_MINUTE and not session.flagged then
		session.flagged = true
		Telemetry.count("Economy.anomalous")
		Telemetry.flag(player, "anomalousCoins", `{total} combat coins in a minute`)
	end
end

local credit: (Player, Data, { Event }, string, string, number, number) -> ()

-- What reaching `level` unlocks, applied to the profile.
local function unlock(player: Player, data: Data, events: { Event }, id: string, level: number)
	local reached: Event = { kind = "levelUp", level = level, unlocks = {}, coins = 0 }
	local entry = ProgressionConfig.unlocks[level]
	if entry then
		if entry.kind == "ability" and entry.id and not table.find(data.UnlockedAbilities, entry.id) then
			table.insert(data.UnlockedAbilities, entry.id)
		elseif entry.kind == "cosmetic" and entry.id and not table.find(data.OwnedCosmetics, entry.id) then
			table.insert(data.OwnedCosmetics, entry.id)
		end
		table.insert(reached.unlocks, entry.text)
	end
	Telemetry.count(`Economy.reachedLevel.{level}`)
	Telemetry.first(player, "levelUp")
	table.insert(events, reached)
	if level == ProgressionConfig.MAX_LEVEL then
		local cap = ProgressionConfig.CAP_REWARD
		if not table.find(data.Badges, cap.badge) then
			table.insert(data.Badges, cap.badge)
		end
		reached.coins = cap.coins
		credit(player, data, events, `{id}:cap`, "levelCap", cap.coins, 0)
	end
end

local function gainXP(player: Player, data: Data, events: { Event }, id: string, xp: number)
	data.LifetimeXP += xp
	data.XP += xp
	while true do
		local need = EconomyService.xpToNext(data)
		if data.XP < need then
			break
		end
		data.XP -= need
		if data.Level < ProgressionConfig.MAX_LEVEL then
			data.Level += 1
			unlock(player, data, events, id, data.Level)
		else
			data.CapRewards += 1
			table.insert(events, { kind = "levelUp", level = data.Level, unlocks = {}, coins = ProgressionConfig.CAP_REPEAT_COINS, repeated = data.CapRewards })
			credit(player, data, events, `{id}:repeat{data.CapRewards}`, "levelCapRepeat", ProgressionConfig.CAP_REPEAT_COINS, 0)
		end
	end
end

-- One transaction on a loaded profile.
credit = function(player: Player, data: Data, events: { Event }, id: string, reason: string, coins: number, xp: number)
	data.Coins += coins
	addToLedger(data, id, reason, coins, xp)
	Telemetry.count(`Economy.coins.{reason}`, coins)
	Telemetry.count(`Economy.xp.{reason}`, xp)
	local session = sessions[player]
	if session then
		session.earned += coins
		if COMBAT_REASONS[reason] then
			checkAnomaly(player, session, coins)
		end
	end
	if coins > 0 then
		Telemetry.first(player, "coins")
	end
	table.insert(events, { kind = "grant", id = id, reason = reason, coins = coins, xp = xp })
	if xp > 0 then
		gainXP(player, data, events, id, xp)
	end
end

local function validAmount(value: number, limit: number): boolean
	return value == value and value >= 0 and value <= limit and value == math.floor(value)
end

-- Pays `player` once for `id` (unique per session). Returns whether it was
-- accepted (paid now, or when their profile loads).
function EconomyService.grant(player: Player, id: string, reason: string, coins: number, xp: number): boolean
	local session = sessions[player]
	if not FeatureFlags.PROGRESSION or not session or player.Parent ~= Players then
		return false
	end
	if session.granted[id] then
		Telemetry.count("Economy.duplicates")
		return false
	end
	if not validAmount(coins, ProgressionConfig.MAX_COINS_PER_GRANT) or not validAmount(xp, ProgressionConfig.MAX_XP_PER_GRANT) then
		Telemetry.count("Economy.refused")
		warn(`[FW] refused grant {id} to {player.UserId}: {coins} coins, {xp} XP`)
		return false
	end
	session.granted[id] = true
	withProfile(player, function(data, events)
		credit(player, data, events, id, reason, coins, xp)
	end)
	return true
end

-- Takes `coins` for `id` (a purchase), if the player has them. Returns
-- whether it did. The caller saves and, if that fails, refunds.
function EconomyService.spend(player: Player, id: string, reason: string, coins: number): boolean
	local profile = DataService.get(player)
	if not profile or not validAmount(coins, math.huge) or profile.data.Coins < coins then
		return false
	end
	DataService.update(player, function(data)
		data.Coins -= coins
		addToLedger(data, id, reason, -coins, 0)
	end)
	Telemetry.count(`Economy.spent.{reason}`, coins)
	EconomyService.publish(player)
	return true
end

-- Gives back coins taken by `spend` for `id` (a purchase that didn't save).
function EconomyService.refund(player: Player, id: string, coins: number)
	if DataService.update(player, function(data)
		data.Coins += coins
		addToLedger(data, `{id}:refund`, "refund", coins, 0)
	end) then
		Telemetry.count("Economy.refunded", coins)
		EconomyService.publish(player)
	end
end

-- An elimination with `weapon`; pays each mastery milestone once.
local function addMastery(player: Player, data: Data, events: { Event }, weaponId: string)
	local weapon = WeaponConfig.weapons[weaponId]
	if not weapon then
		return
	end
	local mastery = data.WeaponMastery[weaponId] or { Eliminations = 0, Claimed = {} }
	data.WeaponMastery[weaponId] = mastery
	mastery.Eliminations += 1
	if not FeatureFlags.PROGRESSION then
		return
	end
	for _, milestone in ProgressionConfig.mastery do
		if mastery.Eliminations >= milestone.eliminations and not table.find(mastery.Claimed, milestone.eliminations) then
			table.insert(mastery.Claimed, milestone.eliminations)
			local badge = `{weapon.displayName} {milestone.badge}`
			if not table.find(data.Badges, badge) then
				table.insert(data.Badges, badge)
			end
			table.insert(events, {
				kind = "mastery",
				weapon = weaponId,
				badge = badge,
				eliminations = milestone.eliminations,
				coins = milestone.coins,
			})
			credit(player, data, events, `mastery:{weaponId}:{milestone.eliminations}`, "mastery", milestone.coins, 0)
		end
	end
end

local function onEliminated(e: EliminationService.Elimination)
	withProfile(e.victim, function(data)
		data.TotalDeaths += 1
	end)
	local killer = e.killer
	if killer then
		local grant = GRANTS.elimination
		EconomyService.grant(killer, `elimination:{e.event}`, "elimination", grant.coins, grant.xp)
		if e.cause == "chain" or e.cause == "barrel" then
			local bonus = GRANTS.chainBonus
			EconomyService.grant(killer, `chain:{e.event}`, "chainBonus", bonus.coins, bonus.xp)
		end
		local best = EliminationService.bestStreakOf(killer)
		withProfile(killer, function(data, events)
			data.TotalEliminations += 1
			data.BestStreak = math.max(data.BestStreak, best)
			if e.weapon then
				addMastery(killer, data, events, e.weapon)
			end
		end)
	end
	local assist = GRANTS.assist
	for _, helper in e.assists do
		EconomyService.grant(helper, `assist:{e.event}`, "assist", assist.coins, assist.xp)
	end
end

local function flushPlaytime(session: Session, player: Player)
	local seconds = session.unsavedPlaytime
	if seconds > 0 and DataService.update(player, function(data)
		data.TotalPlaytime += seconds
	end) then
		session.unsavedPlaytime = 0
	end
end

-- Active time: playtime and participation rewards.
function EconomyService.tick(dt: number)
	for player, session in sessions do
		if PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE then
			session.activeSeconds += dt
			session.unsavedPlaytime += dt
			for _, step in ProgressionConfig.participation do
				if not session.reached[step.minutes] and session.activeSeconds >= step.minutes * 60 then
					session.reached[step.minutes] = true
					-- Sessions that get this far (the first-ten-minutes rate).
					Telemetry.count(`session.reached{step.minutes}Minutes`)
					EconomyService.grant(player, `participation:{step.minutes}`, "participation", step.coins, step.xp)
				end
			end
			flushPlaytime(session, player)
		end
	end
end

function EconomyService.activeSecondsOf(player: Player): number
	local session = sessions[player]
	return if session then session.activeSeconds else 0
end

-- Test-only: coins and XP from nowhere, each grant with its own ID.
function EconomyService.testGrant(player: Player, coins: number, xp: number): boolean
	if not GameConfig.TEST_CONTROLS.ENABLED then
		return false
	end
	testGrants += 1
	return EconomyService.grant(player, `test:{testGrants}`, "test", coins, xp)
end

local function onJoin(player: Player)
	if sessions[player] then
		return
	end
	sessions[player] = {
		granted = {},
		pending = {},
		activeSeconds = 0,
		reached = {},
		unsavedPlaytime = 0,
		earned = 0,
		recent = {},
		flagged = false,
	}
	-- A profile that was ready before this (DataStores failing at once).
	if DataService.isLoaded(player) then
		EconomyService.publish(player)
	end
end

local function onLeave(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	flushPlaytime(session, player)
	local profile = DataService.get(player)
	local minutes = session.activeSeconds / 60
	if profile and minutes >= 1 then
		Telemetry.sample("coinsPer10Minutes", session.earned / minutes * 10)
		Telemetry.sample("unspentCoins", profile.data.Coins)
	end
	Telemetry.log("Economy", "session", { player = player, minutes = math.floor(minutes), earned = session.earned })
	sessions[player] = nil
end

function EconomyService.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	DataService.Loaded:Connect(function(player)
		local session = sessions[player]
		if not session then
			return
		end
		local queued = session.pending
		session.pending = {}
		for _, change in queued do
			withProfile(player, change)
		end
		EconomyService.publish(player)
	end)
	EliminationService.Eliminated:Connect(onEliminated)
	EliminationService.Alpha:Connect(function(player, eventId)
		local grant = GRANTS.alpha
		EconomyService.grant(player, `alpha:{eventId}`, "alpha", grant.coins, grant.xp)
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(EconomyService.TICK_SECONDS)
			EconomyService.tick(dt)
		end
	end)
end

return EconomyService
