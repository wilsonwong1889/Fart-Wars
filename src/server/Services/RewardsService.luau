-- Rewards for coming back and for playing (masterplan 4.1), all free:
--   * the daily track: one claim per UTC day, seven days that loop; a
--     missed day doesn't reset it (the next claim is the next day). Day 3
--     and day 6 add a free spin, day 7 a cosmetic (coins if owned)
--   * ten-minute gifts: a free spin for every GIFT_ACTIVE_MINUTES (or the
--     player's giftMinutes experiment value) of
--     ACTIVE play (AFK and the home screen don't count), at most
--     GIFTS_PER_DAY a UTC day, banked up to MAX_SPINS; the day's count is
--     saved, the minutes toward the next gift are per session
--   * the free spin: a prize drawn on the server by RewardsConfig's
--     weights, which the client shows as exact percentages
-- Every payout goes through EconomyService.grant with an ID that can't
-- repeat (the UTC day, the spin's number), and the claim is recorded
-- before it pays, so nothing can be claimed twice. Temporary (unsaved)
-- profiles can't claim: it would be lost and claimable again.
--   RewardsRequest:InvokeServer("status" | "claimDaily" | "spin")
--     -> { ok, reason, message, ... }
--   ProgressEvent { kind = "gift", spins }
-- Player attributes for the HUD: DailyReady, DailyDay (1-7), Spins,
-- NextGiftSeconds (nil when no more gifts today).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardsConfig = require(Shared.Config.RewardsConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local RateLimit = require(Server.RateLimit)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local LoadoutService = require(script.Parent.LoadoutService)
local ExperimentService = require(script.Parent.ExperimentService)

type Data = DataService.Data
export type Result = { [string]: any }

-- Seconds of active play per gift, for this player.
local function giftSeconds(player: Player): number
	local minutes = ExperimentService.value(player, "giftMinutes")
	return (if type(minutes) == "number" and minutes > 0 then minutes else RewardsConfig.GIFT_ACTIVE_MINUTES) * 60
end

local RewardsService = {}

RewardsService.MESSAGES = table.freeze({
	claimed = "Claimed!",
	alreadyClaimed = "Already claimed today. Come back tomorrow!",
	spun = "You won!",
	noSpins = "No free spins yet: play for a few minutes to earn one.",
	loading = "Your progress is still loading.",
	notSaving = "Progress isn't saving this session, so rewards are paused.",
	disabled = "Rewards are off right now.",
	busy = "One moment...",
	badPayload = "That request didn't make sense.",
	rateLimited = "Slow down a little.",
})

type Session = { giftSeconds: number, sinceSync: number }
local sessions: { [Player]: Session } = {}
local busy: { [Player]: boolean } = {}
local limiter = RateLimit.new(0.25)
local rng = Random.new()
local started = false

local function today(): number
	return RewardsConfig.day(os.time())
end

local function result(ok: boolean, reason: string, extra: { [string]: any }?): Result
	local answer: Result = extra or {}
	answer.ok = ok
	answer.reason = reason
	answer.message = answer.message or RewardsService.MESSAGES[reason] or reason
	if not ok then
		Telemetry.count(`Rewards.refused.{reason}`)
	end
	return answer
end

local function progressEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProgressEvent") :: RemoteEvent
end

-- The next track day (1-7), and whether today's claim is open.
function RewardsService.dailyState(data: Data): (number, boolean)
	return data.DailyTrack % #RewardsConfig.daily + 1, data.LastDailyDay < today()
end

-- Gifts still to come today.
function RewardsService.giftsLeft(data: Data): number
	return if data.GiftDay == today() then math.max(0, RewardsConfig.GIFTS_PER_DAY - data.GiftsToday) else RewardsConfig.GIFTS_PER_DAY
end

-- The HUD's attributes.
function RewardsService.publish(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = profile.data
	local day, ready = RewardsService.dailyState(data)
	player:SetAttribute("DailyDay", day)
	player:SetAttribute("DailyReady", ready and not profile.temporary)
	player:SetAttribute("Spins", data.Spins)
	local session = sessions[player]
	local giving = session ~= nil and RewardsService.giftsLeft(data) > 0 and data.Spins < RewardsConfig.MAX_SPINS
	player:SetAttribute("NextGiftSeconds", if giving and session then math.max(0, math.ceil(giftSeconds(player) - session.giftSeconds)) else nil)
end

-- What the rewards screens show.
function RewardsService.status(player: Player): Result
	local profile = DataService.get(player)
	if not profile then
		return result(false, "loading")
	end
	local data = profile.data
	local day, ready = RewardsService.dailyState(data)
	local session = sessions[player]
	return result(true, "status", {
		day = day,
		ready = ready and not profile.temporary,
		claims = data.DailyClaims,
		spins = data.Spins,
		giftsLeft = RewardsService.giftsLeft(data),
		nextGiftSeconds = if session then math.max(0, math.ceil(giftSeconds(player) - session.giftSeconds)) else giftSeconds(player),
		secondsToReset = 86400 - os.time() % 86400,
		saving = not profile.temporary,
	})
end

-- Gives a cosmetic, or `false` if they already have it.
local function giveCosmetic(player: Player, id: string): boolean
	local fresh = false
	DataService.update(player, function(data)
		if not table.find(data.OwnedCosmetics, id) then
			table.insert(data.OwnedCosmetics, id)
			fresh = true
		end
	end)
	return fresh
end

local function usable(player: Player): (DataService.Profile?, string?)
	if not FeatureFlags.REWARDS or not FeatureFlags.PROGRESSION then
		return nil, "disabled"
	end
	local profile = DataService.get(player)
	if not profile then
		return nil, "loading"
	elseif profile.temporary or profile.lost then
		return nil, "notSaving"
	end
	return profile, nil
end

function RewardsService.claimDaily(player: Player): Result
	local profile, refused = usable(player)
	if not profile then
		return result(false, refused :: string)
	end
	local day, ready = RewardsService.dailyState(profile.data)
	if not ready then
		return result(false, "alreadyClaimed")
	end
	local reward = RewardsConfig.daily[day]
	local dayNumber = today()
	-- The claim is recorded before anything pays.
	DataService.update(player, function(data)
		data.LastDailyDay = dayNumber
		data.DailyTrack += 1
		data.DailyClaims += 1
		if reward.spins then
			data.Spins = math.min(RewardsConfig.MAX_SPINS, data.Spins + reward.spins)
		end
	end)
	local coins = reward.coins
	local cosmetic = nil
	if reward.cosmetic then
		if giveCosmetic(player, reward.cosmetic) then
			cosmetic = reward.cosmetic
			LoadoutService.push(player)
		else
			coins += RewardsConfig.DUPLICATE_COSMETIC_COINS
		end
	end
	EconomyService.grant(player, `daily:{dayNumber}`, "daily", coins, 0)
	Telemetry.count("Rewards.dailyClaims")
	Telemetry.count(`Rewards.dailyDay.{day}`)
	RewardsService.publish(player)
	task.spawn(DataService.save, player)
	return result(true, "claimed", {
		day = day,
		coins = coins,
		spins = reward.spins,
		cosmetic = cosmetic,
		message = `Day {day}: +{coins} coins` .. (if reward.spins then `, +{reward.spins} free spin` else "")
			.. (if cosmetic then `, {ProgressionConfig.cosmetics[cosmetic].name} tracer` else ""),
	})
end

-- One prize by the configured weights.
function RewardsService.draw(roll: number?): { [string]: any }
	local total = 0
	for _, prize in RewardsConfig.spin do
		total += prize.weight
	end
	local at = (roll or rng:NextNumber()) * total
	for _, prize in RewardsConfig.spin do
		at -= prize.weight
		if at < 0 then
			return prize
		end
	end
	return RewardsConfig.spin[#RewardsConfig.spin]
end

function RewardsService.spin(player: Player): Result
	local profile, refused = usable(player)
	if not profile then
		return result(false, refused :: string)
	end
	if profile.data.Spins <= 0 then
		return result(false, "noSpins")
	end
	local prize = RewardsService.draw()
	local number = 0
	DataService.update(player, function(data)
		data.Spins -= 1
		data.SpinsUsed += 1
		number = data.SpinsUsed
	end)
	local coins, xp = prize.coins or 0, prize.xp or 0
	local cosmetic = nil
	if prize.cosmetic then
		if giveCosmetic(player, prize.cosmetic) then
			cosmetic = prize.cosmetic
			LoadoutService.push(player)
		else
			coins += RewardsConfig.DUPLICATE_COSMETIC_COINS
		end
	end
	EconomyService.grant(player, `spin:{number}`, "spin", coins, xp)
	Telemetry.count("Rewards.spins")
	Telemetry.count(`Rewards.prize.{prize.id}`)
	RewardsService.publish(player)
	return result(true, "spun", {
		prize = prize.id,
		label = prize.label,
		coins = coins,
		xp = xp,
		cosmetic = cosmetic,
		spins = profile.data.Spins,
		message = if prize.cosmetic and not cosmetic
			then `You won {prize.label}, which you have: {coins} coins instead!`
			else `You won {prize.label}!`,
	})
end

-- Active play earns gifts.
function RewardsService.tick(dt: number)
	local day = today()
	for player, session in sessions do
		local profile = DataService.get(player)
		if profile and not profile.temporary and FeatureFlags.REWARDS then
			local data = profile.data
			if data.GiftDay ~= day then
				DataService.update(player, function(d)
					d.GiftDay = day
					d.GiftsToday = 0
				end)
			end
			if PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE
				and RewardsService.giftsLeft(data) > 0
				and data.Spins < RewardsConfig.MAX_SPINS
			then
				session.giftSeconds += dt
				if session.giftSeconds >= giftSeconds(player) then
					session.giftSeconds = 0
					DataService.update(player, function(d)
						d.Spins += 1
						d.GiftsToday += 1
					end)
					Telemetry.count("Rewards.gifts")
					progressEvent():FireClient(player, { kind = "gift", spins = data.Spins })
					RewardsService.publish(player)
				end
			end
		end
		session.sinceSync += dt
		if session.sinceSync >= 5 then
			session.sinceSync = 0
			RewardsService.publish(player)
		end
	end
end

-- One request from a client.
function RewardsService.request(player: Player, action: unknown): Result
	if type(action) ~= "string" then
		Telemetry.reject("RewardsRequest", player, "badPayload")
		return result(false, "badPayload")
	end
	if action == "status" then
		return RewardsService.status(player)
	end
	if not limiter:allow(player, "rewards") then
		Telemetry.reject("RewardsRequest", player, "rateLimited")
		return result(false, "rateLimited")
	end
	if busy[player] then
		return result(false, "busy")
	end
	busy[player] = true
	local ok, answer = pcall(function(): Result
		if action == "claimDaily" then
			return RewardsService.claimDaily(player)
		elseif action == "spin" then
			return RewardsService.spin(player)
		end
		Telemetry.reject("RewardsRequest", player, "badPayload")
		return result(false, "badPayload")
	end)
	busy[player] = nil
	if not ok then
		Telemetry.error("Rewards", answer)
		return result(false, "badPayload")
	end
	return answer :: Result
end

-- Test-only: progress toward the next gift.
function RewardsService.testGiftSeconds(player: Player, seconds: number)
	local session = sessions[player]
	if session then
		session.giftSeconds = seconds
	end
end

function RewardsService.start()
	if started then
		return
	end
	started = true
	local function onJoin(player: Player)
		sessions[player] = sessions[player] or { giftSeconds = 0, sinceSync = 0 }
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		busy[player] = nil
		limiter:forget(player)
	end)
	DataService.Loaded:Connect(function(player)
		RewardsService.publish(player)
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rewardsRequest = remotes:WaitForChild("RewardsRequest") :: RemoteFunction
	rewardsRequest.OnServerInvoke = function(player, action)
		return RewardsService.request(player, action)
	end
	Health.loop("Rewards", 1, RewardsService.tick)
end

return RewardsService
