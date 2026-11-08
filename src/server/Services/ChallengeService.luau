-- Daily challenges (ChallengeConfig), behind FeatureFlags.CHALLENGES:
-- three a day for each player, new at 00:00 UTC (the daily shop's day),
-- counted from PlayStatsService (the same counts the season's weekly
-- challenges use, so nothing a bot does or suffers counts). Each pays
-- ChallengeConfig.REWARD the moment it's done, once: it's marked claimed in
-- the profile before EconomyService.grant pays it, under one grant ID per
-- challenge per day (`challenge:<day>:<id>`), so nothing repeats it. Nothing
-- earned is lost and nothing needs claiming by hand. Progress is in the
-- profile (Challenges), so it carries across sessions and servers that day;
-- a new day starts three new challenges from zero.
-- Like the daily track, a profile that isn't saving (outside Studio;
-- RewardsService.paused) counts nothing: it would be lost and could pay
-- again.
--   ProgressEvent { kind = "challenges", day, secondsToReset, saving,
--     loading, challenges = { { id, text, hint, kind, goal, progress,
--     claimed, coins, xp } } }
-- The DAILY screen also gets it in RewardsRequest "status" (`challenges`),
-- so it's there whenever the screen opens.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local ChallengeConfig = require(Shared.Config.ChallengeConfig)
local DailyShopConfig = require(Shared.Config.DailyShopConfig)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local Messages = require(Server.Messages)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RewardsService = require(script.Parent.RewardsService)
local PlayStatsService = require(script.Parent.PlayStatsService)

export type State = { day: number, ids: { string }, progress: { [string]: number }, claimed: { string } }

local ChallengeService = {}

ChallengeService.MESSAGES = table.freeze({
	done = "🎯 DAILY CHALLENGE CRUSHED: %s!",
	allDone = "🏆 ALL 3 DAILIES DONE! BRO IS UNSTOPPABLE!",
})

local enabledOverride: boolean? = nil
local clock: () -> number = os.time
-- The day each player's screen was last told about.
local shownDay: { [Player]: number } = {}
local started = false

-- Test seams: a clock, and on/off whatever the flag says.
function ChallengeService.setClock(fn: () -> number)
	clock = fn
end
function ChallengeService.testEnable(enabled: boolean?)
	enabledOverride = enabled
end

function ChallengeService.enabled(): boolean
	if enabledOverride ~= nil then
		return enabledOverride
	end
	return FeatureFlags.CHALLENGES == true and FeatureFlags.PROGRESSION
end

-- Today's UTC day number, the daily shop's.
function ChallengeService.today(): number
	return DailyShopConfig.day(clock())
end

local function doable(challenge: ChallengeConfig.Challenge): boolean
	return ChallengeConfig.doable(challenge, FeatureFlags :: any)
end

-- A profile that isn't saving counts nothing (outside Studio).
local paused = RewardsService.paused

local function valid(state: any): boolean
	if type(state) ~= "table" or type(state.day) ~= "number" or type(state.ids) ~= "table"
		or type(state.progress) ~= "table" or type(state.claimed) ~= "table"
	then
		return false
	end
	for _, id in state.ids do
		if type(id) ~= "string" then
			return false
		end
	end
	for id, value in state.progress do
		if type(id) ~= "string" or type(value) ~= "number" or value ~= value or value < 0 then
			return false
		end
	end
	return true
end

-- The player's state for today, starting today's three if it's a new day
-- (or the saved one is damaged). Nil while the profile is loading or not
-- saving.
local function sync(player: Player): State?
	local profile = DataService.get(player)
	if not profile or paused(profile) then
		return nil
	end
	local day = ChallengeService.today()
	local state = (profile.data :: any).Challenges
	if not valid(state) or state.day ~= day then
		local ids = {}
		for _, challenge in ChallengeConfig.pick(player.UserId, day, doable) do
			table.insert(ids, challenge.id)
		end
		DataService.update(player, function(data)
			(data :: any).Challenges = { day = day, ids = ids, progress = {}, claimed = {} }
		end)
		Telemetry.count("Challenges.days")
	end
	return (profile.data :: any).Challenges
end

-- Today's challenges for the player.
function ChallengeService.challenges(player: Player): { ChallengeConfig.Challenge }
	local state = sync(player)
	if not state then
		return ChallengeConfig.pick(player.UserId, ChallengeService.today(), doable)
	end
	local list = {}
	for _, id in state.ids do
		local challenge = ChallengeConfig.get(id)
		if challenge then
			table.insert(list, challenge)
		end
	end
	return list
end

-- What the DAILY screen shows, for one player (nil when challenges are off).
function ChallengeService.view(player: Player): { [string]: any }?
	if not ChallengeService.enabled() then
		return nil
	end
	local state = sync(player)
	local list = {}
	for _, challenge in ChallengeService.challenges(player) do
		local claimed = state ~= nil and table.find(state.claimed, challenge.id) ~= nil
		table.insert(list, {
			id = challenge.id,
			text = challenge.text,
			hint = challenge.hint,
			kind = challenge.kind,
			goal = challenge.goal,
			progress = if claimed then challenge.goal
				elseif state then math.min(challenge.goal, math.floor(state.progress[challenge.id] or 0))
				else 0,
			claimed = claimed,
			coins = ChallengeConfig.REWARD.coins,
			xp = ChallengeConfig.REWARD.xp,
		})
	end
	return {
		kind = "challenges",
		day = ChallengeService.today(),
		secondsToReset = DailyShopConfig.secondsLeft(clock()),
		challenges = list,
		saving = state ~= nil,
		loading = DataService.get(player) == nil,
	}
end

function ChallengeService.push(player: Player)
	local view = ChallengeService.view(player)
	if view and player.Parent == Players then
		shownDay[player] = view.day
		local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProgressEvent") :: RemoteEvent
		remote:FireClient(player, view)
	end
end

-- Counts `amount` of `stat` toward today's challenges; pays each one done.
function ChallengeService.count(player: Player, stat: string, amount: number?)
	local add = amount or 1
	if not ChallengeService.enabled() or type(add) ~= "number" or add ~= add or add <= 0 then
		return
	end
	local state = sync(player)
	if not state then
		return
	end
	local changed, finished = false, {}
	for _, id in state.ids do
		local challenge = ChallengeConfig.get(id)
		if challenge and challenge.stat == stat and not table.find(state.claimed, id) then
			changed = true
			local progress = math.min(challenge.goal, (state.progress[id] or 0) + add)
			local done = progress >= challenge.goal
			-- Claimed before it pays, so it can't pay twice.
			DataService.update(player, function(data)
				local today = (data :: any).Challenges
				today.progress[id] = progress
				if done then
					table.insert(today.claimed, id)
				end
			end)
			if done then
				table.insert(finished, challenge)
			end
		end
	end
	for _, challenge in finished do
		local reward = ChallengeConfig.REWARD
		EconomyService.grant(player, `challenge:{state.day}:{challenge.id}`, "challenge", reward.coins, reward.xp)
		Messages.send(player, "challenge", string.format(ChallengeService.MESSAGES.done, string.upper(challenge.text)))
		-- (The log counts Challenges.done.)
		Telemetry.log("Challenges", "done", { player = player, challenge = challenge.id, day = state.day })
		Telemetry.count(`Challenges.done.{challenge.id}`)
	end
	if #finished > 0 and #state.claimed >= #state.ids then
		Telemetry.count("Challenges.allDone")
		task.delay(1.5, function()
			if player.Parent == Players then
				Messages.send(player, "challenge", ChallengeService.MESSAGES.allDone)
			end
		end)
	end
	if changed then
		ChallengeService.push(player)
	end
end

-- A new day for everyone online: today's challenges, and the screen told.
function ChallengeService.tick()
	if not ChallengeService.enabled() then
		return
	end
	local day = ChallengeService.today()
	for _, player in Players:GetPlayers() do
		if shownDay[player] ~= day and DataService.isLoaded(player) then
			ChallengeService.push(player)
		end
	end
end

-- Test-only: today's challenges back to zero and unclaimed (the same three).
function ChallengeService.testReset(player: Player): boolean
	local state = sync(player)
	if not state then
		return false
	end
	DataService.update(player, function(data)
		local today = (data :: any).Challenges
		table.clear(today.progress)
		table.clear(today.claimed)
	end)
	ChallengeService.push(player)
	return true
end

function ChallengeService.start()
	if started then
		return
	end
	started = true
	RewardsService.challenges = ChallengeService.view
	PlayStatsService.Counted:Connect(ChallengeService.count)
	DataService.Loaded:Connect(ChallengeService.push)
	Players.PlayerRemoving:Connect(function(player)
		shownDay[player] = nil
	end)
	Health.loop("Challenges", 1, ChallengeService.tick)
end

return ChallengeService
