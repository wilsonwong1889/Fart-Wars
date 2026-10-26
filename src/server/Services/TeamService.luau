-- Who holds an active slot on which team. Only ACTIVE players have a team;
-- spectators are neutral. Every join, leave, spectate and switch goes
-- through here and is checked against TeamBalance, and the counts go to
-- every client (TeamUpdate) whenever they change.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local TeamBalance = require(Shared.TeamBalance)
local Signal = require(Shared.Signal)
local MatchScoreService = require(script.Parent.MatchScoreService)

local TeamService = {}

-- Fires after any change to who is on which team.
TeamService.Changed = Signal.new()

-- Whether two players are friends. Replaceable in tests; the real check is
-- a web call, so it runs once per pair as players join and is remembered.
TeamService.checkFriends = function(a: Player, b: Player): boolean
	local ok, result = pcall(a.IsFriendsWithAsync, a, b.UserId)
	return ok and result == true
end

local teamInstances: { [string]: Team } = {}
local teamOf: { [Player]: string } = {}
local friendsOf: { [Player]: { [Player]: boolean } } = {}
local started = false

local function teamUpdate(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TeamUpdate") :: RemoteEvent
end

function TeamService.counts(): { [string]: number }
	local counts = {}
	for _, team in TeamConfig.order do
		counts[team] = 0
	end
	for _, team in teamOf do
		counts[team] += 1
	end
	return counts
end

function TeamService.activeCount(): number
	local total = 0
	for _ in teamOf do
		total += 1
	end
	return total
end

function TeamService.teamOf(player: Player): string?
	return teamOf[player]
end

function TeamService.getTeamInstance(team: string): Team?
	return teamInstances[team]
end

function TeamService.members(team: string): { Player }
	local list = {}
	for player, id in teamOf do
		if id == team then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

-- Whether `a` and `b` are Roblox friends, as far as is known yet (looked
-- up as they join; never waits).
function TeamService.areFriends(a: Player, b: Player): boolean
	local friends = friendsOf[a]
	return friends ~= nil and friends[b] == true
end

-- How many of `player`'s friends hold a slot on each team.
function TeamService.friendCounts(player: Player): { [string]: number }
	local counts = {}
	local friends = friendsOf[player] or {}
	for other, team in teamOf do
		if friends[other] then
			counts[team] = (counts[team] or 0) + 1
		end
	end
	return counts
end

local function setTeam(player: Player, team: string?)
	if team then
		teamOf[player] = team
	else
		teamOf[player] = nil
	end
	local instance = if team then teamInstances[team] else nil
	player.Team = instance :: any
	player.Neutral = instance == nil
	player:SetAttribute("TeamId", team)
	TeamService.Changed:Fire()
end

-- Gives `player` a slot on the team the rules pick (their preference when
-- it doesn't unbalance anything). Returns the team and why, or nil and
-- "full" when every slot is taken.
function TeamService.assign(player: Player, preferred: string?): (string?, TeamBalance.Why)
	local current = teamOf[player]
	if current then
		return current, "preferred"
	end
	local team, why = TeamBalance.choose(TeamService.counts(), TeamConfig.order, GameConfig.MAX_TEAM_SIZE, {
		preferred = preferred,
		friends = TeamService.friendCounts(player),
		scores = MatchScoreService.getScores(),
	})
	if team then
		setTeam(player, team)
	end
	return team, why
end

-- Frees the player's slot (spectating, AFK or leaving).
function TeamService.release(player: Player)
	if teamOf[player] then
		setTeam(player, nil)
	end
end

-- A voluntary move to `to`, allowed only when it evens the teams out.
function TeamService.switch(player: Player, to: string): boolean
	local from = teamOf[player]
	if not from or not TeamBalance.canSwitch(TeamService.counts(), TeamConfig.order, GameConfig.MAX_TEAM_SIZE, from, to) then
		return false
	end
	setTeam(player, to)
	return true
end

-- Test-only: moves an active player to `team` whatever the balance (but
-- never into a full team).
function TeamService.testSetTeam(player: Player, team: string): boolean
	if not GameConfig.TEST_CONTROLS.ENABLED or not teamOf[player] or not teamInstances[team] then
		return false
	end
	if teamOf[player] ~= team and TeamService.counts()[team] >= GameConfig.MAX_TEAM_SIZE then
		return false
	end
	setTeam(player, team)
	return true
end

function TeamService.snapshot(): { counts: { [string]: number }, maxTeamSize: number }
	return { counts = TeamService.counts(), maxTeamSize = GameConfig.MAX_TEAM_SIZE }
end

local function noteFriends(player: Player)
	friendsOf[player] = friendsOf[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player and friendsOf[other] then
			local friends = TeamService.checkFriends(player, other)
			-- Either of them may have left while the check was out.
			if friendsOf[player] and friendsOf[other] then
				friendsOf[player][other] = friends or nil
				friendsOf[other][player] = friends or nil
			end
		end
	end
end

local function forget(player: Player)
	TeamService.release(player)
	friendsOf[player] = nil
	for _, friends in friendsOf do
		friends[player] = nil
	end
end

function TeamService.start()
	if started then
		return
	end
	started = true
	for _, id in TeamConfig.order do
		local config = TeamConfig.teams[id]
		local existing = Teams:FindFirstChild(config.name)
		local team: Team = if existing and existing:IsA("Team") then existing else Instance.new("Team")
		team.Name = config.name
		team.TeamColor = BrickColor.new(config.brickColor :: any)
		team.AutoAssignable = false
		team:SetAttribute("TeamId", id)
		team.Parent = Teams
		teamInstances[id] = team
	end
	TeamService.Changed:Connect(function()
		teamUpdate():FireAllClients(TeamService.snapshot())
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(noteFriends, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(noteFriends, player)
	end
	Players.PlayerRemoving:Connect(forget)
end

return TeamService
