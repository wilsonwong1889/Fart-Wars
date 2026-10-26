-- The server's player lifecycle, through the real Bootstrap and remotes:
--   * a new player is a menu spectator: no avatar, no team
--   * an avatar that turns up for a spectator is removed
--   * PLAY gives a slot and an avatar on the team's own spawn; spamming it
--     never makes a second avatar or a second slot
--   * a home-screen team choice counts when it keeps the teams even, and is
--     refused (with a message) when it doesn't
--   * spectating removes the avatar and frees the slot; a death respawns
--     after 3 seconds, but not for someone who spectated meanwhile
--   * a voluntary switch only goes through when it evens the teams
--   * leaving frees everything; reconnecting starts fresh; joining and
--     leaving over and over never duplicates an avatar or skews the counts
--   * round time only counts while ACTIVE
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
do
	local run = assert(loadstring(server.Bootstrap.Source, "Bootstrap"))
	setfenv(run, setmetatable({ script = server.Bootstrap }, { __index = getfenv() }))
	run()
end
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TeamService = require(server.Services.TeamService)
local MapService = require(server.Services.MapService)
local Remotes = ReplicatedStorage.Remotes

local messages: { [Player]: { any } } = {}
Remotes.UIMessage.FiredToClient:Connect(function(player, payload)
	messages[player] = messages[player] or {}
	table.insert(messages[player], payload)
end)
local function lastMessage(player: Player): any
	local list = messages[player] or {}
	return list[#list]
end

local nextId = 0
local function join(name: string, userId: number?): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId or 100 + nextId
	player.Parent = Players
	task.wait(0.1)
	return player
end
local function play(player: Player, team: string?)
	Remotes.RequestPlay.OnServerEvent:Fire(player, team)
	task.wait(0.6) -- past the request cooldown
end
local function avatars(name: string): number
	local n = 0
	for _, child in workspace:GetChildren() do
		if child.Name == name and child:FindFirstChild("Humanoid") then
			n += 1
		end
	end
	return n
end
local function onOwnSpawn(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local team = player:GetAttribute("TeamId")
	if not (root and team) then
		return false
	end
	for _, pad in MapService.spawns(team) do
		if (pad.Position - root.Position).Magnitude < 5 then
			return true
		end
	end
	return false
end

check(Players.CharacterAutoLoads == false, "avatars only come from PLAY")
check(#Teams:GetTeams() == 2 and Teams:FindFirstChild("Skibidi Stinkers") and Teams:FindFirstChild("Sigma Sharters"), "both teams exist")
check(workspace:FindFirstChild("Map"), "the map is up")

-- Joining.
local ada = join("Ada")
check(ada:GetAttribute("State") == "MENU_SPECTATOR", "a new player is a menu spectator")
check(ada.Character == nil and ada.Team == nil and ada.Neutral, "with no avatar and no team")
ada:LoadCharacterAsync() -- as if Studio auto-loaded one
task.wait(0.1)
check(ada.Character == nil and avatars("Ada") == 0, "a spectator's stray avatar is removed")

-- PLAY.
play(ada)
check(ada:GetAttribute("State") == "ACTIVE" and ada:GetAttribute("TeamId") ~= nil, "PLAY puts Ada on a team")
check(ada.Team == TeamService.getTeamInstance(ada:GetAttribute("TeamId")) and not ada.Neutral, "the Roblox team matches")
check(ada.Character and onOwnSpawn(ada), "with an avatar on her team's spawn")
check(string.find(lastMessage(ada).text, "You're on"), "and she's told her team")
for _ = 1, 5 do
	Remotes.RequestPlay.OnServerEvent:Fire(ada)
	Lifecycle.requestPlay(ada, nil)
end
task.wait(0.1)
check(TeamService.activeCount() == 1 and avatars("Ada") == 1, "spamming PLAY: still one slot and one avatar")

local bo = join("Bo")
Lifecycle.requestPlay(bo, nil)
Lifecycle.requestPlay(bo, nil)
task.wait(0.1)
check(TeamService.activeCount() == 2 and avatars("Bo") == 1, "two PLAYs in one frame: one slot, one avatar")
check(bo:GetAttribute("TeamId") ~= ada:GetAttribute("TeamId"), "Bo balances the teams")
local adaTeam, boTeam = ada:GetAttribute("TeamId"), bo:GetAttribute("TeamId")

-- Team choice from the home screen.
local cy = join("Cy")
Remotes.RequestTeam.OnServerEvent:Fire(cy, adaTeam)
task.wait(0.6)
check(cy:GetAttribute("PreferredTeam") == adaTeam, "a spectator's choice is remembered")
play(cy)
check(cy:GetAttribute("TeamId") == adaTeam and string.find(lastMessage(cy).text, "You're on"), "and honoured when the teams are level")
local dee = join("Dee")
play(dee, adaTeam)
check(dee:GetAttribute("TeamId") == boTeam, "a choice that would unbalance the teams is refused")
check(string.find(lastMessage(dee).text, "uneven"), "and Dee is told why")
Remotes.RequestPlay.OnServerEvent:Fire(join("Eve"), { "not", "a", "team" })
task.wait(0.6)
check(TeamService.activeCount() == 5, "junk in a request is ignored, not trusted or fatal")
local eve = Players:FindFirstChild("Eve") :: Player

-- Spectating.
Remotes.RequestSpectate.OnServerEvent:Fire(eve)
task.wait(0.6)
check(eve:GetAttribute("State") == "MENU_SPECTATOR" and eve.Character == nil and eve.Team == nil, "spectating removes the avatar")
check(TeamService.activeCount() == 4 and avatars("Eve") == 0, "and frees the slot")

-- Death and respawn.
local first = bo.Character :: Model
first.Humanoid.Died:Fire()
task.wait(2.5)
check(bo.Character == first, "no respawn before 3 seconds")
task.wait(1)
check(bo.Character ~= first and bo.Character ~= nil and onOwnSpawn(bo), "a fresh avatar on the team's spawn after 3 seconds")
check(avatars("Bo") == 1, "and the old one is gone")
local doomed = dee.Character :: Model
doomed.Humanoid.Died:Fire()
task.wait(1)
Remotes.RequestSpectate.OnServerEvent:Fire(dee)
task.wait(3)
check(dee.Character == nil and avatars("Dee") == 0, "someone who spectated after dying doesn't come back")

-- Switching. Ada and Cy against Bo now (Dee and Eve are spectating).
local counts = TeamService.counts()
check(counts[adaTeam] == 2 and counts[boTeam] == 1, "Ada's team is ahead 2v1")
Remotes.RequestTeam.OnServerEvent:Fire(bo, adaTeam)
task.wait(0.6)
check(bo:GetAttribute("TeamId") == boTeam and lastMessage(bo).kind == "denied", "Bo can't make it 3v0")
Remotes.RequestTeam.OnServerEvent:Fire(cy, boTeam)
task.wait(0.6)
check(cy:GetAttribute("TeamId") == adaTeam, "2v1 -> 1v2 evens nothing, so Cy stays")
play(dee)
play(eve, adaTeam)
counts = TeamService.counts()
check(counts[adaTeam] == 3 and counts[boTeam] == 2 and eve:GetAttribute("TeamId") == adaTeam, "Dee and Eve back: 3v2")
Remotes.RequestSpectate.OnServerEvent:Fire(dee)
task.wait(0.6)
counts = TeamService.counts()
check(counts[adaTeam] == 3 and counts[boTeam] == 1, "Dee steps out: 3v1, and nobody is moved for it")
local before = eve.Character
Remotes.RequestTeam.OnServerEvent:Fire(eve, boTeam)
task.wait(0.6)
check(eve:GetAttribute("TeamId") == boTeam and lastMessage(eve).kind == "team", "3v1: Eve may switch to even it")
check(eve.Character ~= before and onOwnSpawn(eve), "and starts again at her new team's spawn")

-- Leaving and reconnecting.
local boId = bo.UserId
local slotsBefore = TeamService.activeCount()
local wasActive = bo:GetAttribute("State") == "ACTIVE"
bo.Parent = nil
task.wait(0.1)
check(Lifecycle.get(bo) == nil and avatars("Bo") == 0, "leaving forgets the player and removes the avatar")
check(TeamService.activeCount() == slotsBefore - (if wasActive then 1 else 0), "and frees the slot")
local bo2 = join("Bo", boId)
check(bo2:GetAttribute("State") == "MENU_SPECTATOR" and bo2.Character == nil, "reconnecting starts on the home screen")
play(bo2)
check(bo2:GetAttribute("State") == "ACTIVE" and avatars("Bo") == 1, "and PLAY works again")

-- Round time only counts while ACTIVE (a round is running by now).
local active, watching = Lifecycle.get(bo2), Lifecycle.get(dee)
local frozen = watching and watching.activeSecondsThisRound
task.wait(10)
check(active and active.activeSecondsThisRound >= 9, "an active player's round time counts")
check(watching and watching.state == "MENU_SPECTATOR" and watching.activeSecondsThisRound == frozen, "a spectator's doesn't")

-- Churn: players come and go, some mid-PLAY.
local churn = {}
for i = 1, 30 do
	local p = join(`Churn{i}`, 900 + i)
	Lifecycle.requestPlay(p, nil)
	table.insert(churn, p)
	if i % 3 == 0 then
		churn[i - 1].Parent = nil
	end
	if i % 5 == 0 then
		Remotes.RequestSpectate.OnServerEvent:Fire(churn[i - 2])
	end
	if i % 7 == 0 then
		Lifecycle.requestPlay(p, nil) -- again, at once
	end
end
task.wait(1)
local active = 0
local byTeam = { Stinkers = 0, Sharters = 0 }
for _, p in Players:GetPlayers() do
	if p:GetAttribute("State") == "ACTIVE" then
		active += 1
		byTeam[p:GetAttribute("TeamId")] += 1
		check(avatars(p.Name) == 1, `{p.Name} has exactly one avatar`)
	else
		check(avatars(p.Name) == 0 and p:GetAttribute("TeamId") == nil, `{p.Name} (not playing) has no avatar or team`)
	end
end
local counts = TeamService.counts()
check(TeamService.activeCount() == active and counts.Stinkers == byTeam.Stinkers and counts.Sharters == byTeam.Sharters, "team counts match who is playing")
check(counts.Stinkers <= 10 and counts.Sharters <= 10, "and never past ten a team")
for _, p in churn do
	if not p.Parent then
		check(avatars(p.Name) == 0 and Lifecycle.get(p) == nil, `{p.Name} left nothing behind`)
	end
end

return { status = "PASS", checks = checks }
