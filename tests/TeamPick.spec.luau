-- Choosing a team with bots in the server, through the real Bootstrap and
-- the Choose a Team screen (one client, Me; bots fill to 4 unless said):
--   * alone with 3 bots (2v1), neither card is locked, and each says how
--     many of its count are bots; either pick is honoured and a bot
--     crosses over, 2v2; AUTO takes the free slot, so no bot moves
--   * a team of 10 bots (fill 20) can still be picked: I take a bot's
--     place and it crosses over, 10v10
--   * between players nothing changes: a second player can't stack on my
--     team (2v0 players) and lands where a bot just left; a friend breaks
--     a 1v1 tie and joins me, a second friend can't make it 3v1
--   * SWITCH TEAM in a match goes by the players too: alone it evens
--     nothing; two of us against ten bots it does, and a bot crosses back
--   * on the home screen a team the players would unbalance is still
--     locked, even when the counts with bots look level
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local Shared = ReplicatedStorage.Shared
local TeamBalance = require(Shared.TeamBalance)
local ORDER = require(Shared.Config.TeamConfig).order
local TeamService = require(server.Services.TeamService)
local BotService = require(server.Services.BotService)
local BotDirector = require(server.Services.BotDirector)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Remotes = ReplicatedStorage.Remotes

-- Me (1) is friends with Pal (3) and Kit (4).
local FRIENDS = { [1] = { [3] = true, [4] = true }, [3] = { [1] = true }, [4] = { [1] = true } }
TeamService.checkFriends = function(a, b)
	local friends = FRIENDS[a.UserId]
	return friends ~= nil and friends[b.UserId] == true
end
-- The last team message each player got.
local told: { [Player]: string } = {}
Remotes.UIMessage.FiredToClient:Connect(function(player, payload)
	if payload.kind == "team" then
		told[player] = payload.text
	end
end)

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
-- The client starts after the bots came, so it learns of them from the
-- round snapshot it pulls, not from a TeamUpdate.
local Client = game.StarterPlayer.StarterPlayerScripts.Client
run(Client.ClientBootstrap)
task.wait(0.5)
local ClientState = require(Client.ClientState)
local Home = require(Client.Controllers.HomeController)
local home = Home.parts
local cards = home.teamButtons

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.5)
	return player
end
local function click(button: GuiButton)
	button.Activated:Fire()
	task.wait(0.05)
end
local function is(counts: { [string]: number }, stinkers: number, sharters: number): boolean
	return counts.Stinkers == stinkers and counts.Sharters == sharters
end
local function line(): string
	local counts, bots = TeamService.counts(), TeamService.botCounts()
	return `({counts.Stinkers}v{counts.Sharters}, bots {bots.Stinkers}/{bots.Sharters})`
end
local function open(team: string): boolean
	return cards[team]:GetAttribute("Enabled") ~= false and not cards[team].Lock.Visible
end
-- A team card (or AUTO) on the team screen, then past the cooldowns.
local function pick(card: GuiButton)
	click(card)
	task.wait(1.1)
end
local function spectate()
	click(home.spectate)
	task.wait(1.1)
end
-- Which team each bot is on, to tell whether any moved.
local function botTeams(): { [number]: string }
	local teams = {}
	for _, bot in BotService.all() do
		teams[bot.id] = bot.team
	end
	return teams
end
local function sameBots(a: { [number]: string }, b: { [number]: string }): boolean
	for id, team in a do
		if b[id] ~= team then
			return false
		end
	end
	for id in b do
		if a[id] == nil then
			return false
		end
	end
	return true
end

-- Alone: 3 bots, 2v1.
check(#BotService.all() == 3 and is(TeamService.botCounts(), 2, 1), "alone: 3 bots, 2v1 " .. line())
check(is(ClientState.counts, 2, 1) and is(ClientState.bots, 2, 1), "the client knows which of the counts are bots")
click(home.play)
check(home.teamSelect.Enabled, "PLAY asks for a team")
check(open("Stinkers") and open("Sharters"), "alone with bots: neither team is locked")
check(cards.Stinkers.Count.Text == "2" and cards.Stinkers.Max.Text == "/ 10 · 🤖 2 bots", "the Stinkers card: 2, both bots: " .. cards.Stinkers.Max.Text)
check(cards.Sharters.Count.Text == "1" and cards.Sharters.Max.Text == "/ 10 · 🤖 1 bot", "the Sharters card: 1 bot: " .. cards.Sharters.Max.Text)
pick(cards.Stinkers)
check(me:GetAttribute("State") == "ACTIVE" and me:GetAttribute("TeamId") == "Stinkers", "the side with more bots: I'm on it")
check(told[me] == "You're on Skibidi Stinkers!", "and not told it's uneven: " .. tostring(told[me]))
check(is(TeamService.counts(), 2, 2) and is(TeamService.botCounts(), 1, 2) and #BotService.all() == 3, "a bot crossed over: 2v2 " .. line())
check(is(ClientState.counts, 2, 2) and is(ClientState.bots, 1, 2), "and the client sees it")
check(home.switch.Text == "SWITCH TEAM (only to even up)", "alone, SWITCH TEAM evens nothing: " .. home.switch.Text)

-- Home again, then the other side, the one with more bots now.
spectate()
check(me:GetAttribute("State") == "MENU_SPECTATOR" and is(TeamService.botCounts(), 1, 2), "home again; the bots stay put " .. line())
click(home.play)
check(open("Stinkers") and open("Sharters"), "still neither locked (1v2 bots)")
pick(cards.Sharters)
check(me:GetAttribute("TeamId") == "Sharters" and told[me] == "You're on Sigma Sharters!", "the Sharters: honoured too")
check(is(TeamService.counts(), 2, 2) and is(TeamService.botCounts(), 2, 1), "a bot crossed back: 2v2 " .. line())

-- AUTO: the free slot, so nothing has to move.
spectate()
local before = botTeams()
click(home.play)
pick(cards.Auto)
check(me:GetAttribute("TeamId") == "Sharters", "AUTO: the side with the free slot")
check(sameBots(before, botTeams()) and is(TeamService.counts(), 2, 2), "no bot moved " .. line())

-- A team of ten bots.
BotDirector.testSetFill(20)
task.wait(0.5)
check(#BotService.all() == 19 and is(TeamService.counts(), 10, 10), "fill 20: 19 bots, 10v10 " .. line())
spectate()
check(is(TeamService.counts(), 10, 9) and is(TeamService.botCounts(), 10, 9), "I step out: ten bots against nine " .. line())
click(home.play)
check(open("Stinkers") and open("Sharters"), "ten bots aren't a full team: open")
check(cards.Stinkers.Count.Text == "10" and cards.Stinkers.Max.Text == "/ 10 · 🤖 10 bots", "10 / 10, all bots: " .. cards.Stinkers.Max.Text)
pick(cards.Stinkers)
check(me:GetAttribute("TeamId") == "Stinkers" and told[me] == "You're on Skibidi Stinkers!", "I take a bot's place")
check(is(TeamService.counts(), 10, 10) and is(TeamService.botCounts(), 9, 10) and #BotService.all() == 19, "and it crosses over: 10v10 " .. line())
check(TeamService.counts().Stinkers <= 10, "never past ten once the bots have moved")

-- A second player: between players, nothing changes.
local rival = join("Rival", 2)
check(#BotService.all() == 18 and is(TeamService.botCounts(), 9, 9), "Rival arrives: a bot goes, from the side Rival will be sent to " .. line())
local counts, bots = TeamService.counts(), TeamService.botCounts()
check(not TeamBalance.preferenceAllowed(counts, ORDER, 10, "Stinkers", bots), "Rival's screen: my team is locked (2v0 players)")
check(TeamBalance.preferenceAllowed(counts, ORDER, 10, "Sharters", bots), "the bots' side is open")
Lifecycle.requestPlay(rival, "Stinkers")
task.wait(0.6)
check(rival:GetAttribute("TeamId") == "Sharters", "Rival can't stack on my team")
check(string.find(told[rival] or "", "uneven", 1, true) ~= nil, "and is told why: " .. tostring(told[rival]))
check(is(TeamService.counts(), 10, 10) and is(TeamService.humanCounts(), 1, 1), "10v10, a player a side " .. line())

-- Friends still only break a tie.
local pal = join("Pal", 3)
check(#BotService.all() == 17, "a third player: 17 bots " .. line())
Lifecycle.requestPlay(pal, nil)
task.wait(0.6)
check(pal:GetAttribute("TeamId") == "Stinkers", "1v1 players: my friend Pal breaks the tie and joins me")
check(is(TeamService.counts(), 10, 10) and is(TeamService.humanCounts(), 2, 1), "10v10 " .. line())
local kit = join("Kit", 4)
Lifecycle.requestPlay(kit, "Stinkers")
task.wait(0.6)
check(kit:GetAttribute("TeamId") == "Sharters", "2v1 players: my friend Kit can't make it 3v1")
check(string.find(told[kit] or "", "uneven", 1, true) ~= nil, "and is told why")
check(is(TeamService.counts(), 10, 10) and is(TeamService.humanCounts(), 2, 2) and #BotService.all() == 16, "10v10, two players a side " .. line())

-- Switching goes by the players: Pal and me against ten bots.
rival.Parent = nil
kit.Parent = nil
task.wait(0.5)
check(is(TeamService.humanCounts(), 2, 0) and is(TeamService.counts(), 10, 10) and is(TeamService.botCounts(), 8, 10), "Rival and Kit go: two of us against ten bots " .. line())
check(home.switch.Text == "SWITCH TO SHARTERS", "2v0 players: SWITCH TEAM evens us out, ten bots or not: " .. home.switch.Text)
click(home.switch)
task.wait(1.1)
check(me:GetAttribute("TeamId") == "Sharters" and told[me] == "You switched to Sigma Sharters.", "switched")
check(is(TeamService.humanCounts(), 1, 1) and is(TeamService.counts(), 10, 10) and is(TeamService.botCounts(), 9, 9), "and a bot crossed back: 10v10 " .. line())

-- Home again with one bot (fill 3): Pal alone on the Stinkers, a bot on
-- the Sharters. Level, but for me the Stinkers would be 2v0 players.
spectate()
BotDirector.testSetFill(3)
task.wait(0.5)
check(is(TeamService.counts(), 1, 1) and is(TeamService.botCounts(), 0, 1), "fill 3: Pal against one bot " .. line())
click(home.play)
check(not open("Stinkers") and open("Sharters"), "the players' lock holds: the Stinkers are locked for me, friend or not")
check(TeamBalance.preferenceAllowed(TeamService.counts(), ORDER, 10, "Stinkers"), "(counted as players, 1v1 would have let me stack)")
click(cards.Stinkers)
check(me:GetAttribute("State") == "MENU_SPECTATOR" and Home.selectedTeam ~= "Stinkers", "clicking the locked card does nothing")
pick(cards.Sharters)
check(me:GetAttribute("TeamId") == "Sharters" and is(TeamService.humanCounts(), 1, 1), "Sharters it is: against my friend, beside the bot " .. line())

return { status = "PASS", checks = checks }
