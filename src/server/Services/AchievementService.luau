-- Reasons to come back (FeatureFlags.BADGES; BadgeConfig):
--   * the Beta Tester: anyone who plays (spawns onto the field) while the
--     beta window is open earns the Beta Tester badge and the beta's boom,
--     once. A Beta Tester always owns that boom, after the beta too.
--   * achievements: a first elimination, a first chain or barrel
--     elimination (as the chain bonus counts them), and levels 10, 25 and
--     50 (a prestiged player has been to 50). Profiles from before the
--     badges catch up as they load (eliminations and levels; chains
--     weren't counted then). Bots earn nothing, and kills of bots, which
--     pay out nothing, don't count.
--   * the favorite prompt: once ever, after the first round the player's
--     team wins with them in it, or FAVORITE_MINUTES of active play. It
--     waits for a calm moment, the round's results or the home screen,
--     never mid-fight, and only for a profile that saves (so "once" holds).
-- A badge is earned in the profile first (BadgesEarned), then awarded
-- through Roblox's BadgeService on the server, once (BadgesAwarded when
-- Roblox has it: awarded now, or theirs already). One whose ID is still 0
-- is skipped and counted, and goes through once the ID is set. An award
-- Roblox refuses or fails is counted and tried again RETRY_SECONDS later,
-- RETRY_ATTEMPTS times a session, then on the player's next visit.
-- What the client hears:
--   ProgressEvent { kind = "beta", cosmetic }   the beta's boom is theirs
--   ProgressEvent { kind = "favorite" }         show Roblox's favorite prompt
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local BadgeConfig = require(Shared.Config.BadgeConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local DataService = require(script.Parent.DataService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local TeamService = require(script.Parent.TeamService)
local EliminationService = require(script.Parent.EliminationService)
local EconomyService = require(script.Parent.EconomyService)
local LoadoutService = require(script.Parent.LoadoutService)
local RoundService = require(script.Parent.RoundService)

type Data = DataService.Data

local AchievementService = {}

AchievementService.TICK_SECONDS = 1

-- Roblox's BadgeService, or a stand-in (setApi). Each may error.
export type Api = {
	-- Awards the badge; whether Roblox did.
	award: (userId: number, badgeId: number) -> boolean,
	-- Whether the user has it.
	owns: (userId: number, badgeId: number) -> boolean,
	-- GetBadgeInfoAsync's answer (IsEnabled, Name, ...).
	info: (badgeId: number) -> { [string]: any },
}

local function robloxApi(): Api
	local BadgeService = game:GetService("BadgeService")
	return {
		award = function(userId, badgeId)
			-- AwardBadgeAsync replaced AwardBadge, which is deprecated.
			local found, method = pcall(function()
				return (BadgeService :: any).AwardBadgeAsync
			end)
			if found and method then
				return method(BadgeService, userId, badgeId)
			end
			return BadgeService:AwardBadge(userId, badgeId)
		end,
		owns = function(userId, badgeId)
			return BadgeService:UserHasBadgeAsync(userId, badgeId)
		end,
		info = function(badgeId)
			return BadgeService:GetBadgeInfoAsync(badgeId)
		end,
	}
end

type Session = {
	-- An award pass is running (Roblox's calls yield), and whether more
	-- was earned meanwhile.
	awarding: boolean,
	again: boolean,
	-- Failed awards this session, and when each may be tried again.
	failures: { [string]: number },
	retryAt: { [string]: number },
	-- Badges counted as skipped (ID 0) this session.
	skipped: { [string]: boolean },
	-- The favorite prompt is due (a win, or the minutes), waiting for a
	-- calm moment.
	favoriteDue: boolean,
}
local sessions: { [Player]: Session } = {}
local config: any = BadgeConfig
local api: Api? = nil
local clock: () -> number = os.time
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function progressEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProgressEvent") :: RemoteEvent
end

local function getApi(): Api
	if not api then
		api = robloxApi()
	end
	return api :: Api
end

-- Test seams: a stand-in BadgeService; another BadgeConfig (badge IDs);
-- the clock the beta window goes by (Unix time).
function AchievementService.setApi(testApi: Api?)
	api = testApi
end
function AchievementService.setConfig(testConfig: any?)
	config = testConfig or BadgeConfig
end
function AchievementService.setClock(testClock: (() -> number)?)
	clock = testClock or os.time
end

function AchievementService.enabled(): boolean
	return FeatureFlags.BADGES
end

local function sessionOf(player: Player): Session?
	if not sessions[player] and player.Parent == Players and FeatureFlags.BADGES then
		sessions[player] = { awarding = false, again = false, failures = {}, retryAt = {}, skipped = {}, favoriteDue = false }
	end
	return sessions[player]
end

local function has(list: { string }, key: string): boolean
	return table.find(list, key) ~= nil
end

-- Whether `key` is earned and Roblox doesn't have it yet.
function AchievementService.pending(data: Data, key: string): boolean
	return has(data.BadgesEarned, key) and not has(data.BadgesAwarded, key)
end

-- Whether this session may try `key` now.
local function due(session: Session, key: string): boolean
	local failures = session.failures[key]
	return failures == nil or (failures < config.RETRY_ATTEMPTS and now() >= (session.retryAt[key] or 0))
end

-- One try at Roblox: (taken, why). Roblox saying no is "theirs already" if
-- they have it (kept from before, or awarded on an unsaved visit).
local function tryAward(player: Player, badge: BadgeConfig.Badge): (boolean, string)
	local calls = getApi()
	local ok, result = pcall(calls.award, player.UserId, badge.id)
	if ok and result == true then
		return true, "awarded"
	end
	local checked, owns = pcall(calls.owns, player.UserId, badge.id)
	if checked and owns == true then
		return true, "owned"
	end
	return false, if ok then "refused" else tostring(result)
end

-- One pass over what the player has earned and Roblox doesn't have, one
-- badge at a time, round again if more was earned meanwhile.
local function pass(player: Player, session: Session)
	repeat
		session.again = false
		for _, key in config.order do
			local profile = DataService.get(player)
			local badge = config.badges[key]
			if not (profile and badge and player.Parent == Players and sessions[player] == session) then
				break
			end
			if not AchievementService.pending(profile.data, key) or not due(session, key) then
				continue
			end
			if badge.id == 0 then
				if not session.skipped[key] then
					session.skipped[key] = true
					Telemetry.count("Badges.skippedNoId")
				end
				continue
			end
			local taken, why = tryAward(player, badge)
			if sessions[player] ~= session then
				break
			end
			if taken then
				session.failures[key] = nil
				session.retryAt[key] = nil
				DataService.update(player, function(d)
					if not has(d.BadgesAwarded, key) then
						table.insert(d.BadgesAwarded, key)
					end
				end)
				Telemetry.log("Badges", if why == "owned" then "alreadyOwned" else "awarded", { player = player, badge = key })
			else
				local failures = (session.failures[key] or 0) + 1
				session.failures[key] = failures
				session.retryAt[key] = now() + config.RETRY_SECONDS
				if failures >= config.RETRY_ATTEMPTS then
					-- Saved as earned; the next visit tries again.
					Telemetry.count("Badges.retryNextVisit")
				end
				Telemetry.log("Badges", "awardFailed", { player = player, badge = key, id = badge.id, why = why, tries = failures })
			end
		end
	until not session.again or sessions[player] ~= session
end

-- Sends what the player has earned to Roblox. A pass already running for
-- them goes round again instead of starting another.
local function awardAll(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	if session.awarding then
		session.again = true
		return
	end
	session.awarding = true
	local ok, err = pcall(pass, player, session)
	session.awarding = false
	if not ok then
		Telemetry.error("Badges", err)
	end
end

-- Whether a pass would have something to try right now.
local function anythingDue(player: Player, session: Session): boolean
	local profile = DataService.get(player)
	if not profile or session.awarding then
		return false
	end
	for _, key in config.order do
		local badge = config.badges[key]
		if badge and badge.id ~= 0 and AchievementService.pending(profile.data, key) and session.failures[key] and due(session, key) then
			return true
		end
	end
	return false
end

-- Earns `key` (once ever) and sends it to Roblox. Returns whether it was
-- new.
function AchievementService.earn(player: Player, key: string): boolean
	local profile = DataService.get(player)
	if not (FeatureFlags.BADGES and profile and config.badges[key] and sessionOf(player)) then
		return false
	end
	if has(profile.data.BadgesEarned, key) then
		return false
	end
	DataService.update(player, function(d)
		table.insert(d.BadgesEarned, key)
	end)
	Telemetry.count(`Badges.earned.{key}`)
	Telemetry.log("Badges", "earned", { player = player, badge = key })
	task.spawn(awardAll, player)
	return true
end

-- A Beta Tester owns the beta's cosmetic: given (and told) if they don't.
local function giveBetaCosmetic(player: Player)
	local id = config.BETA_COSMETIC
	local profile = DataService.get(player)
	if not (profile and ProgressionConfig.cosmetics[id] and has(profile.data.BadgesEarned, "BetaTester")) then
		return
	end
	if has(profile.data.OwnedCosmetics, id) then
		return
	end
	DataService.update(player, function(d)
		table.insert(d.OwnedCosmetics, id)
	end)
	Telemetry.log("Badges", "betaCosmetic", { player = player, cosmetic = id })
	progressEvent():FireClient(player, { kind = "beta", cosmetic = id })
	LoadoutService.push(player)
end

-- Playing in the beta: the Beta Tester, once.
function AchievementService.checkBeta(player: Player)
	local profile = DataService.get(player)
	if not (FeatureFlags.BADGES and profile) then
		return
	end
	if not has(profile.data.BadgesEarned, "BetaTester") then
		if PlayerLifecycleService.stateOf(player) ~= States.Player.ACTIVE or not config.inBeta(clock()) then
			return
		end
		AchievementService.earn(player, "BetaTester")
	end
	giveBetaCosmetic(player)
end

-- The level badges reached (a prestige rank means level 50 was).
local function checkLevels(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = profile.data
	local top = if data.Prestige > 0 then ProgressionConfig.MAX_LEVEL else data.Level
	for _, key in config.order do
		local badge = config.badges[key]
		if badge and badge.level and top >= badge.level then
			AchievementService.earn(player, key)
		end
	end
end

local function onEliminated(e: EliminationService.Elimination)
	local killer = e.killer
	if not (FeatureFlags.BADGES and killer) then
		return
	end
	AchievementService.earn(killer, "FirstElimination")
	if e.cause == "chain" or e.cause == "barrel" then
		AchievementService.earn(killer, "FirstChain")
	end
end

-- Not mid-fight: the round's results are up, or they're on the home screen.
function AchievementService.calm(player: Player): boolean
	return RoundService.phase() == States.Phase.RESULTS or PlayerLifecycleService.stateOf(player) == States.Player.MENU_SPECTATOR
end

-- The favorite prompt, if it's due and the moment is right.
local function checkFavorite(player: Player, session: Session)
	local profile = DataService.get(player)
	if not profile or profile.temporary or profile.data.FavoritePromptAt > 0 then
		return
	end
	if not session.favoriteDue and EconomyService.activeSecondsOf(player) >= config.FAVORITE_MINUTES * 60 then
		session.favoriteDue = true
	end
	if not (session.favoriteDue and AchievementService.calm(player)) then
		return
	end
	DataService.update(player, function(d)
		d.FavoritePromptAt = os.time()
	end)
	Telemetry.log("Badges", "favoritePrompt", { player = player })
	progressEvent():FireClient(player, { kind = "favorite" })
end

-- A round's results: its winners (who played in it) are due the prompt.
local function onPhase(phase: string, snapshot: { [string]: any })
	if phase ~= States.Phase.RESULTS then
		return
	end
	local result = snapshot.result
	local winner = if result and not result.draw then result.winner else nil
	local played = RoundService.lastParticipation()
	for player, session in sessions do
		if winner and TeamService.teamOf(player) == winner and (played[player.UserId] or 0) > 0 then
			session.favoriteDue = true
		end
		checkFavorite(player, session)
	end
end

function AchievementService.tick(_dt: number)
	for player, session in sessions do
		if player.Parent ~= Players then
			continue
		end
		checkFavorite(player, session)
		if anythingDue(player, session) then
			task.spawn(awardAll, player)
		end
	end
end

local function onLoaded(player: Player)
	local session = sessionOf(player)
	local profile = DataService.get(player)
	if not (session and profile) then
		return
	end
	-- Catching up a profile from before the badges.
	if profile.data.TotalEliminations > 0 then
		AchievementService.earn(player, "FirstElimination")
	end
	checkLevels(player)
	AchievementService.checkBeta(player)
	-- Earned on an earlier visit, not through yet.
	task.spawn(awardAll, player)
end

-- What /fw selftest says: each badge's ID (and, for those set, whether
-- Roblox knows it and it's enabled), and the beta window.
function AchievementService.checks(): { { string } }
	local lines = {}
	if not FeatureFlags.BADGES then
		table.insert(lines, { "OK", "Badges", "off (FeatureFlags.BADGES)" })
		return lines
	end
	local missing, problems, ready = {}, {}, 0
	for _, key in config.order do
		local badge = config.badges[key]
		if badge.id == 0 then
			table.insert(missing, badge.name)
		else
			local ok, info = pcall(getApi().info, badge.id)
			if not ok or type(info) ~= "table" then
				table.insert(problems, `{badge.name} ({badge.id}): couldn't look it up ({tostring(info)})`)
			elseif info.IsEnabled == false then
				table.insert(problems, `{badge.name} ({badge.id}) is disabled in the Creator Hub`)
			else
				ready += 1
			end
		end
	end
	local total = #config.order
	if #missing > 0 then
		table.insert(lines, { "WARN", "Badge IDs", `{#missing} of {total} still 0 in BadgeConfig, so never awarded (players still earn them, and get them once set): {table.concat(missing, ", ")}` })
	end
	if #problems > 0 then
		table.insert(lines, { "WARN", "Badges", table.concat(problems, "; ") })
	elseif #missing == 0 then
		table.insert(lines, { "OK", "Badges", `all {ready} set up and enabled` })
	end
	local cosmetic = ProgressionConfig.cosmetics[config.BETA_COSMETIC]
	if not (cosmetic and cosmetic.exclusive) then
		table.insert(lines, { "WARN", "Beta cosmetic", `{tostring(config.BETA_COSMETIC)} isn't an exclusive cosmetic in ProgressionConfig: Beta Testers get the badge only` })
	end
	local opens, closes = config.betaWindow()
	local at = clock()
	local window = `{config.BETA_FIRST_DAY} to {config.BETA_LAST_DAY} (UTC)`
	if at < opens then
		table.insert(lines, { "OK", "Beta window", `{window}: not open yet` })
	elseif at < closes then
		local gets = if cosmetic then `the Beta Tester badge and the {cosmetic.name}` else "the Beta Tester badge"
		table.insert(lines, { "OK", "Beta window", `{window}: open, players get {gets}` })
	else
		table.insert(lines, { "WARN", "Beta window", `{window}: over, nobody new becomes a Beta Tester` })
	end
	return lines
end

function AchievementService.start()
	if started or not FeatureFlags.BADGES then
		return
	end
	started = true
	DataService.Loaded:Connect(onLoaded)
	PlayerLifecycleService.Spawned:Connect(AchievementService.checkBeta)
	EliminationService.Eliminated:Connect(onEliminated)
	EconomyService.Changed:Connect(checkLevels)
	RoundService.PhaseChanged:Connect(onPhase)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end
	Health.loop("Badges", AchievementService.TICK_SECONDS, AchievementService.tick)
end

return AchievementService
