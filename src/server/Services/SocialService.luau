-- Playing with friends (masterplan 4.3): rewards for genuine co-play, not
-- invitations or alternate accounts.
--   * the squad bonus: active play with a Roblox friend who is active on
--     your team in the same server earns coins and XP every SQUAD_MINUTES,
--     SQUAD_PER_DAY times a UTC day
--   * the welcome: when a friend's very first session reaches
--     WELCOME_MINUTES of active play in your server, you both get coins.
--     A newcomer is welcomed once, by one friend; the friend must have
--     played before (two new accounts can't welcome each other) and can
--     welcome at most WELCOMES_PER_DAY a day.
-- Friendship is Roblox's, as TeamService looks it up when players join
-- (TeamService.checkFriends; it never waits).
-- Co-play is counted for the retention numbers either way.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardsConfig = require(Shared.Config.RewardsConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local TeamService = require(script.Parent.TeamService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local SocialService = {}

type Session = {
	squadSeconds: number,
	activeSeconds: number,
	-- This is their first session and nobody has welcomed them yet.
	newcomer: boolean,
	-- Played with a friend at some point this session.
	coplayed: boolean,
}
local sessions: { [Player]: Session } = {}
local started = false

local function today(): number
	return RewardsConfig.day(os.time())
end

local function active(player: Player): boolean
	return PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE
end

-- An active friend on the player's team, if any.
function SocialService.squadmate(player: Player): Player?
	local team = TeamService.teamOf(player)
	if not team then
		return nil
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and active(other) and TeamService.teamOf(other) == team and TeamService.areFriends(player, other) then
			return other
		end
	end
	return nil
end

local function saving(player: Player): any?
	local profile = DataService.get(player)
	if not profile or profile.temporary then
		return nil
	end
	return profile.data
end

-- Today's count in `countField` (reset when `dayField` isn't today).
local function countToday(player: Player, dayField: string, countField: string): number
	local data = saving(player)
	if not data then
		return math.huge
	end
	local day = today()
	if data[dayField] ~= day then
		DataService.update(player, function(d: any)
			d[dayField] = day
			d[countField] = 0
		end)
	end
	return data[countField]
end

local function squadBonus(player: Player)
	if countToday(player, "SquadDay", "SquadToday") >= RewardsConfig.SQUAD_PER_DAY then
		return
	end
	local count = 0
	DataService.update(player, function(d)
		d.SquadToday += 1
		count = d.SquadToday
	end)
	EconomyService.grant(player, `squad:{today()}:{count}`, "squad", RewardsConfig.SQUAD_COINS, RewardsConfig.SQUAD_XP)
	Telemetry.count("social.squadBonuses")
end

-- Whether `friend` may welcome `newcomer` now.
local function canWelcome(friend: Player, newcomer: Player): boolean
	local data = saving(friend)
	return data ~= nil
		and data.Sessions > 1
		and not table.find(data.WelcomedFriends, newcomer.UserId)
		and TeamService.areFriends(newcomer, friend)
		and countToday(friend, "WelcomeDay", "WelcomesToday") < RewardsConfig.WELCOMES_PER_DAY
end

-- A newcomer who has played long enough: welcomed by a friend here, if any.
local function welcome(newcomer: Player, session: Session)
	local data = saving(newcomer)
	if not data or data.WelcomedBy ~= 0 then
		session.newcomer = false
		return
	end
	for _, friend in Players:GetPlayers() do
		if friend ~= newcomer and sessions[friend] and canWelcome(friend, newcomer) then
			session.newcomer = false
			DataService.update(newcomer, function(d)
				d.WelcomedBy = friend.UserId
			end)
			DataService.update(friend, function(d)
				d.WelcomesToday += 1
				table.insert(d.WelcomedFriends, newcomer.UserId)
				while #d.WelcomedFriends > RewardsConfig.WELCOME_MEMORY do
					table.remove(d.WelcomedFriends, 1)
				end
			end)
			EconomyService.grant(newcomer, `welcome:{friend.UserId}`, "welcome", RewardsConfig.WELCOME_COINS, 0)
			EconomyService.grant(friend, `welcomed:{newcomer.UserId}`, "welcome", RewardsConfig.WELCOME_COINS, 0)
			Telemetry.count("social.welcomes")
			Telemetry.log("Social", "welcome", { player = newcomer, friend = friend })
			return
		end
	end
end

function SocialService.tick(dt: number)
	for player, session in sessions do
		if active(player) then
			session.activeSeconds += dt
			if SocialService.squadmate(player) then
				Telemetry.count("social.friendCoplaySeconds", dt)
				if not session.coplayed then
					session.coplayed = true
					-- Sessions with a friend (compare their length and returns).
					Telemetry.count("social.sessionsWithFriend")
				end
				if FeatureFlags.PROGRESSION then
					session.squadSeconds += dt
					if session.squadSeconds >= RewardsConfig.SQUAD_MINUTES * 60 then
						session.squadSeconds = 0
						squadBonus(player)
					end
				end
			end
			if session.newcomer and FeatureFlags.PROGRESSION and session.activeSeconds >= RewardsConfig.WELCOME_MINUTES * 60 then
				welcome(player, session)
			end
		end
	end
end

-- Whether this session has played with a friend (for the session summary).
function SocialService.coplayed(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.coplayed
end

function SocialService.start()
	if started then
		return
	end
	started = true
	DataService.Loaded:Connect(function(player, profile)
		sessions[player] = {
			squadSeconds = 0,
			activeSeconds = 0,
			-- Sessions is counted up as the profile loads: 1 is the first.
			newcomer = not profile.temporary and profile.data.Sessions == 1 and profile.data.WelcomedBy == 0,
			coplayed = false,
		}
	end)
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			Telemetry.count(if session.coplayed then "social.leftWithFriend" else "social.leftSolo")
		end
		sessions[player] = nil
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(1)
			SocialService.tick(dt)
		end
	end)
end

return SocialService
