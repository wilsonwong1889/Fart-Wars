-- Player profiles in a DataStore: load on join, autosave, save on leave and
-- on shutdown. Built so a player's progress is never lost or duplicated:
--   * session locking: a profile records which server holds it. Another
--     server waits for the lock (it's released on leave), and only takes it
--     over once it's stale, which a crashed server's lock becomes. A
--     server that no longer holds the lock never writes.
--   * every read and write retries with backoff; a profile that can't load
--     (an outage, or Studio without API access) is replaced by a temporary
--     one that is never saved, so it can't overwrite the real one
--   * versioned saves: older profiles are migrated field by field on load;
--     a profile from a newer version is never written by this one
-- Nothing else writes to the DataStore; everyone else changes a profile
-- through DataService.update and reads it with DataService.get.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)

local DataService = {}

DataService.STORE_NAME = "FartWarsProfiles"
DataService.VERSION = 1
DataService.AUTOSAVE_SECONDS = 60
-- A lock not refreshed for this long belongs to a server that's gone.
DataService.LOCK_TIMEOUT_SECONDS = 180
-- Load errors before giving up (a temporary profile); backoff 2, 4, 8 s.
DataService.LOAD_ATTEMPTS = 4
-- How long to wait for another server's lock before taking it, and how
-- often to look.
DataService.LOCK_WAIT_SECONDS = 15
DataService.LOCK_RETRY_SECONDS = 3
DataService.SAVE_ATTEMPTS = 3

-- (player, profile): a profile is ready (saved or temporary).
DataService.Loaded = Signal.new()

export type Mastery = { Eliminations: number, Claimed: { number } }
export type Data = {
	SaveVersion: number,
	Coins: number,
	XP: number, -- toward the next level
	Level: number,
	LifetimeXP: number,
	TotalEliminations: number,
	TotalDeaths: number,
	BestStreak: number,
	OwnedWeapons: { string },
	EquippedWeapon: string,
	UnlockedAbilities: { string },
	EquippedAbility: string?,
	OwnedCosmetics: { string },
	-- The equipped tracer, Fart Dash trail and emote.
	EquippedCosmetic: string?,
	EquippedTrail: string?,
	EquippedEmote: string?,
	Badges: { string },
	WeaponMastery: { [string]: Mastery },
	TotalPlaytime: number,
	CapRewards: number,
	Ledger: { { id: string, coins: number, xp: number, reason: string, at: number } },
	-- Visits, for the return rate: how many sessions, and when (os.time).
	Sessions: number,
	FirstSeen: number,
	LastSeen: number,
	-- Rewards (Phase 4): the daily track's position and last claim (a UTC
	-- day number), free spins banked and used, today's ten-minute gifts.
	DailyTrack: number,
	LastDailyDay: number,
	DailyClaims: number,
	Spins: number,
	SpinsUsed: number,
	GiftDay: number,
	GiftsToday: number,
	-- Store (Phase 4): Roblox purchase IDs already granted (the latest
	-- RECEIPT_MEMORY), and game passes whose contents were given.
	Receipts: { string },
	PassesGranted: { string },
}
export type Profile = {
	data: Data,
	-- Temporary (couldn't load): played with, never saved.
	temporary: boolean,
	dirty: boolean,
	-- Another server took the lock; this one stops saving.
	lost: boolean,
	-- A write is under way (writes take turns), and the final one is done.
	writing: boolean?,
	released: boolean?,
}

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
-- User IDs whose last save is still being written.
local releasing: { [number]: number } = {}
local store: any = nil
local realStore = true
local started = false
local warnedUnavailable = false

function DataService.defaults(): Data
	return {
		SaveVersion = DataService.VERSION,
		Coins = 0,
		XP = 0,
		Level = 1,
		LifetimeXP = 0,
		TotalEliminations = 0,
		TotalDeaths = 0,
		BestStreak = 0,
		OwnedWeapons = { WeaponConfig.default },
		EquippedWeapon = WeaponConfig.default,
		UnlockedAbilities = {},
		EquippedAbility = nil,
		OwnedCosmetics = {},
		EquippedCosmetic = nil,
		Badges = {},
		WeaponMastery = {},
		TotalPlaytime = 0,
		CapRewards = 0,
		Ledger = {},
		Sessions = 0,
		FirstSeen = 0,
		LastSeen = 0,
		DailyTrack = 0,
		LastDailyDay = 0,
		DailyClaims = 0,
		Spins = 0,
		SpinsUsed = 0,
		GiftDay = 0,
		GiftsToday = 0,
		Receipts = {},
		PassesGranted = {},
	}
end

-- Brings an older, partial or damaged profile up to this version: missing
-- fields get their defaults, wrong types and impossible numbers are
-- replaced, and an equipped item the player doesn't own goes back to the
-- default. Nothing the player owns is dropped.
function DataService.migrate(old: { [string]: any }?): Data
	local data = table.clone(old or {})
	data.Lock = nil
	local defaults = DataService.defaults() :: any
	for key, value in defaults do
		local current = data[key]
		if current == nil or typeof(current) ~= typeof(value) then
			data[key] = value
		elseif type(value) == "number" and (current ~= current or current < 0 or current == math.huge) then
			data[key] = value
		end
	end
	data.Level = math.clamp(math.floor(data.Level), 1, ProgressionConfig.MAX_LEVEL)
	if not table.find(data.OwnedWeapons, WeaponConfig.default) then
		table.insert(data.OwnedWeapons, WeaponConfig.default)
	end
	if not WeaponConfig.weapons[data.EquippedWeapon] or not table.find(data.OwnedWeapons, data.EquippedWeapon) then
		if old and old.EquippedWeapon ~= nil and old.EquippedWeapon ~= WeaponConfig.default then
			Telemetry.count("Data.invalidEquip")
		end
		data.EquippedWeapon = WeaponConfig.default
	end
	if data.EquippedAbility ~= nil and not table.find(data.UnlockedAbilities, data.EquippedAbility) then
		Telemetry.count("Data.invalidEquip")
		data.EquippedAbility = nil
	end
	for field, kind in { EquippedCosmetic = "tracer", EquippedTrail = "trail", EquippedEmote = "emote" } do
		local id = data[field]
		local cosmetic = type(id) == "string" and ProgressionConfig.cosmetics[id]
		if id ~= nil and not (cosmetic and cosmetic.kind == kind and ProgressionConfig.ownsCosmetic(data.OwnedCosmetics, id)) then
			Telemetry.count("Data.invalidEquip")
			data[field] = nil
		end
	end
	data.SaveVersion = DataService.VERSION
	return data :: Data
end

-- A round trip to a scratch DataStore (never a player's): whether saving
-- works on this server right now, and the error if not.
function DataService.probe(): (boolean, string)
	if not realStore then
		return true, "stand-in store"
	end
	local ok, err = pcall(function()
		DataStoreService:GetDataStore("FartWarsSelfTest"):UpdateAsync("probe", function()
			return { at = os.time(), job = game.JobId }
		end)
	end)
	return ok, if ok then "read and write OK" else tostring(err)
end

-- Test seam: use `testStore` (anything with UpdateAsync) instead of the
-- real DataStore.
function DataService.setStore(testStore: any)
	store = testStore
	realStore = false
end

local function getStore(): any
	if not store then
		store = DataStoreService:GetDataStore(DataService.STORE_NAME)
	end
	return store
end

local function keyFor(userId: number): string
	return `player_{userId}`
end

local function jobId(): string
	return if game.JobId ~= "" then game.JobId else "studio"
end

-- Waits for DataStore request budget (live servers only).
local function waitForBudget()
	if not realStore then
		return
	end
	for _ = 1, 10 do
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, Enum.DataStoreRequestType.UpdateAsync)
		if not ok or budget > 0 then
			return
		end
		task.wait(1)
	end
end

-- An error that retrying can't fix: Studio without API access, or a place
-- that was never published.
local function hopeless(err: any): boolean
	local message = tostring(err)
	for _, sign in { "Studio access", "publish this place", "403" } do
		if string.find(message, sign, 1, true) then
			return true
		end
	end
	return false
end

local function now(): number
	return os.time()
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Changes the profile through `change` and marks it for saving.
function DataService.update(player: Player, change: (Data) -> ()): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	change(profile.data)
	profile.dirty = true
	return true
end

local function load(player: Player): (Data?, string)
	local key = keyFor(player.UserId)
	local failures = 0
	local stealAt: number? = nil
	while true do
		local result: Data? = nil
		local lockedBy: string? = nil
		local tooNew = false
		local steal = stealAt ~= nil and now() >= stealAt
		waitForBudget()
		local ok, err = pcall(function()
			getStore():UpdateAsync(key, function(old)
				result, lockedBy, tooNew = nil, nil, false
				local lock = old and old.Lock
				local fresh = lock and now() - (tonumber(lock.At) or 0) < DataService.LOCK_TIMEOUT_SECONDS
				if lock and lock.Job ~= jobId() and fresh and not steal then
					lockedBy = tostring(lock.Job)
					return nil
				end
				if old and (tonumber(old.SaveVersion) or 0) > DataService.VERSION then
					tooNew = true
					return nil
				end
				local data = DataService.migrate(old)
				local stored = table.clone(data) :: any
				stored.Lock = { Job = jobId(), At = now() }
				result = data
				return stored
			end)
		end)
		if ok and result then
			if steal then
				Telemetry.count("Data.lockTaken")
			end
			return result, "loaded"
		elseif ok and tooNew then
			return nil, "saved by a newer version"
		elseif ok and lockedBy then
			-- Wait for the other server to let go; take it if it doesn't.
			stealAt = stealAt or now() + DataService.LOCK_WAIT_SECONDS
			Telemetry.log("Data", "waitingForLock", { player = player, holder = lockedBy })
			task.wait(DataService.LOCK_RETRY_SECONDS)
		elseif hopeless(err) then
			Telemetry.count("Data.unavailable")
			if not warnedUnavailable then
				warnedUnavailable = true
				warn(
					"[FW] DataStores are unavailable, so progress won't save on this server. In Studio: Game Settings → Security → Enable Studio Access to API Services."
				)
			end
			return nil, "DataStores unavailable"
		else
			failures += 1
			Telemetry.error("Data", err)
			if failures >= DataService.LOAD_ATTEMPTS then
				return nil, "couldn't load"
			end
			task.wait(2 ^ failures)
		end
		if player.Parent ~= Players then
			return nil, "left"
		end
	end
end

-- Writes `profile` for `userId` (with `release`, giving up the lock).
-- Writes take turns, one per profile at a time, and each takes the profile
-- as it is at the moment it reaches the DataStore, so a slow or retried
-- write can never put back older data; once the release is written,
-- nothing writes again.
local function write(userId: number, profile: Profile, release: boolean): boolean
	if profile.temporary or profile.lost or profile.released then
		return false
	end
	while profile.writing do
		task.wait(0.05)
	end
	if profile.lost or profile.released then
		return false
	end
	profile.writing = true
	local key = keyFor(userId)
	local written, lost = false, false
	for attempt = 1, DataService.SAVE_ATTEMPTS do
		waitForBudget()
		local ok, err = pcall(function()
			getStore():UpdateAsync(key, function(old)
				local lock = old and old.Lock
				lost = lock ~= nil and lock.Job ~= jobId()
				if lost then
					return nil
				end
				local snapshot = table.clone(profile.data) :: any
				snapshot.Lock = if release then nil else { Job = jobId(), At = now() }
				return snapshot
			end)
		end)
		if ok then
			written = not lost
			break
		end
		Telemetry.error("Data", err)
		if attempt < DataService.SAVE_ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end
	profile.writing = false
	if lost then
		profile.lost = true
		Telemetry.count("Data.lockLost")
		warn(`[FW] {userId}'s profile is held by another server now; this one stops saving it`)
		return false
	elseif written then
		profile.dirty = false
		if release then
			profile.released = true
		end
		Telemetry.count("Data.saves")
		return true
	end
	Telemetry.count("Data.saveFailures")
	return false
end

-- Saves the player's profile now, keeping the lock. Returns whether it
-- was written (never for a temporary profile).
function DataService.save(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and write(player.UserId, profile, false)
end

-- The last save of a session: the profile is dropped first, so it's only
-- ever released once (leaving and shutting down both come here).
local function release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	local userId = player.UserId
	releasing[userId] = (releasing[userId] or 0) + 1
	write(userId, profile, true)
	releasing[userId] -= 1
	if releasing[userId] == 0 then
		releasing[userId] = nil
	end
end

local function onJoin(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true
	player:SetAttribute("DataStatus", "loading")
	-- Back on the same server before their last session finished saving.
	while releasing[player.UserId] and player.Parent == Players do
		task.wait(0.5)
	end
	local data, why = load(player)
	loading[player] = nil
	if player.Parent ~= Players then
		if data then
			-- They left while it loaded: hand the lock straight back.
			profiles[player] = { data = data, temporary = false, dirty = false, lost = false }
			release(player)
		end
		return
	end
	local profile: Profile
	if data then
		profile = { data = data, temporary = false, dirty = true, lost = false }
		player:SetAttribute("DataStatus", "ready")
		-- The return rate: session.returning over session.joins.
		local at = os.time()
		if data.Sessions > 0 then
			Telemetry.count("session.returning")
			Telemetry.sample("daysSinceLastVisit", (at - data.LastSeen) / 86400)
			-- Day-1 and day-7 retention: back the day after joining, or a
			-- week after (UTC days), over retention.newPlayers.
			local today, firstDay, lastDay = at // 86400, data.FirstSeen // 86400, data.LastSeen // 86400
			if today - lastDay == 1 then
				Telemetry.count("retention.nextDay")
			end
			if today - firstDay == 1 and lastDay < today then
				Telemetry.count("retention.D1")
			elseif today - firstDay == 7 and lastDay < today then
				Telemetry.count("retention.D7")
			end
		else
			Telemetry.count("retention.newPlayers")
		end
		data.Sessions += 1
		data.FirstSeen = if data.FirstSeen > 0 then data.FirstSeen else at
		data.LastSeen = at
	else
		profile = { data = DataService.defaults(), temporary = true, dirty = false, lost = false }
		player:SetAttribute("DataStatus", "unsaved")
		Telemetry.count("Data.temporaryProfiles")
		if why ~= "DataStores unavailable" then
			warn(`[FW] {player.UserId} plays on a temporary profile ({why}); nothing will save this session`)
		end
	end
	profiles[player] = profile
	Telemetry.log("Data", "loaded", { player = player, temporary = profile.temporary })
	DataService.Loaded:Fire(player, profile)
end

-- Shutdown: every profile's last save, together, before the server goes
-- (Roblox allows 30 seconds). It also waits for saves already under way
-- (players who just left) and for loads still running (released as soon
-- as they finish), since the server stops when this returns.
function DataService.saveAll()
	local deadline = os.clock() + 25
	repeat
		for player in profiles do
			task.spawn(release, player)
		end
		if next(releasing) == nil and next(loading) == nil and next(profiles) == nil then
			break
		end
		task.wait(0.1)
	until os.clock() >= deadline
end

function DataService.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onJoin)
	-- Deferred, so services still reacting to the leave (a last explosion,
	-- the session's playtime) get into the final save.
	Players.PlayerRemoving:Connect(function(player)
		task.defer(release, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	-- Autosave: every profile, so changes are kept and locks stay fresh.
	task.spawn(function()
		while true do
			task.wait(DataService.AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)
	game:BindToClose(DataService.saveAll)
end

return DataService
