-- The practice yard (FeatureFlags.PRACTICE), with the real server and one
-- client, profiles saved in a stand-in store:
--   * once per profile: a new profile's first PLAY goes to a yard of its
--     own far from the battlefield (no team slot, no spawn protection, the
--     Gas Blaster, the camera and crosshair as in a match), not to the team
--     screen; a veteran's and a temporary profile's PLAY, and a second
--     PLAY, go straight to the teams
--   * the steps in order: the intro; gas the dummies (their faces in front
--     of their heads; they swell, pop with the shooter's hit markers, set
--     their neighbours off and come back; headshots do more); a Fart Dash;
--     the barrel (two hits, the fuse, a blast that pops the dummies round
--     it); done, then home with the team screen open, and picking a team
--     joins the match from its own spawn
--   * nothing in the yard pays or counts: coins, XP, stats, the ledger,
--     playtime, match shots, the funnel, challenge dashes, team points
--   * the AFK check leaves the yard alone, and the yard ends by itself
--   * SKIP (Enter, or the button) and PLAY or spectating from the yard all
--     end it, done for good; leaving the game mid-yard takes the yard down
--     and keeps it due for next time
--   * nobody else's shots touch your yard; junk requests do nothing
--   * the PRACTICE tile and Settings replay it (not from a match)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
-- No bots: these checks count the players themselves.
require(server.Services.BotDirector).testSetEnabled(false)
local Shared = ReplicatedStorage.Shared
local PracticeConfig = require(Shared.Config.PracticeConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Data = require(server.Services.DataService)
local Practice = require(server.Services.PracticeService)
local Combat = require(server.Services.CombatService)
local Dash = require(server.Services.DashService)
local Team = require(server.Services.TeamService)
local MapService = require(server.Services.MapService)
local Scores = require(server.Services.MatchScoreService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes

-- Profiles in a stand-in store: a veteran is already in it, and one key
-- always fails the way Studio without API access does (a temporary profile).
local saved: { [string]: any } = {
	player_50 = { TotalPlaytime = 900, Coins = 40, LifetimeXP = 300, Sessions = 4 },
}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		if key == "player_51" then
			error("502: API Services rejected request with error. Error code: 7 Reason: Studio access to APIs is not allowed.")
		end
		local result = transform(saved[key])
		if result ~= nil then
			saved[key] = result
		end
		return result
	end,
})

-- What the server sends whom.
local events: { [Player]: { any } } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	events[player] = events[player] or {}
	table.insert(events[player], event)
end)
local function sent(player: Player, kind: string, test: ((any) -> boolean)?): number
	local n = 0
	for _, event in events[player] or {} do
		if event.kind == kind and (not test or test(event)) then
			n += 1
		end
	end
	return n
end
local messages: { [Player]: { any } } = {}
Remotes.UIMessage.FiredToClient:Connect(function(player, payload)
	messages[player] = messages[player] or {}
	table.insert(messages[player], payload)
end)
local function told(player: Player, kind: string): boolean
	for _, payload in messages[player] or {} do
		if payload.kind == kind then
			return true
		end
	end
	return false
end
local matchDashes, yardDashes = 0, 0
Dash.Dashed:Connect(function()
	matchDashes += 1
end)
Dash.PracticeDashed:Connect(function()
	yardDashes += 1
end)
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end

local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	task.wait(0.2)
	return player
end
local shotIds: { [Player]: number } = {}
-- `times` shots from `player`'s head at `target`, a fire interval apart.
local function shoot(player: Player, target: BasePart, times: number?)
	for _ = 1, times or 1 do
		local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
		shotIds[player] = (shotIds[player] or 0) + 1
		Combat.fire(player, (target.Position - head.Position).Unit, shotIds[player])
		task.wait(0.32)
	end
end
local function yards(): number
	local folder = workspace:FindFirstChild("PracticeYards")
	return if folder then #folder:GetChildren() else 0
end
local function onOwnSpawn(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local team = player:GetAttribute("TeamId")
	if not (root and team) then
		return false
	end
	for _, pad in MapService.spawns(team) do
		if (pad.Position - (root :: BasePart).Position).Magnitude < 5 then
			return true
		end
	end
	return false
end

-- The client.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
local client = game.StarterPlayer.StarterPlayerScripts.Client
run(client.ClientBootstrap)
task.wait(0.5)
local Controllers = client.Controllers
local Home = require(Controllers.HomeController)
local PracticeScreen = require(Controllers.PracticeController)
local CombatScreen = require(Controllers.CombatController)
local HUD = require(Controllers.HUDController)
local Locker = require(Controllers.LockerController)
local home, banner = Home.parts, PracticeScreen.parts
local function click(button: Instance)
	(button :: GuiButton).Activated:Fire()
	task.wait(0.05)
end
local function press(code: Enum.KeyCode)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	UserInputService.InputBegan:Fire(input, false)
	UserInputService.InputEnded:Fire(input, false)
end

check(Data.isLoaded(me) and not assert(Data.get(me)).temporary, "Me's new profile loaded, saving")
check(me:GetAttribute("PracticeDue") == true, "a new profile has the practice yard due")
check(home.tiles.Practice and home.tiles.Practice.Visible, "the home screen has a PRACTICE tile")
local data = assert(Data.get(me)).data
local before = {
	coins = data.Coins,
	xp = data.XP,
	lifetimeXP = data.LifetimeXP,
	eliminations = data.TotalEliminations,
	deaths = data.TotalDeaths,
	playtime = data.TotalPlaytime,
	ledger = #data.Ledger,
	shots = counter("Combat.shots"),
	hits = counter("Combat.hits"),
}

-- The first PLAY: the yard, not the team screen.
click(home.play)
task.wait(0.2)
local session = Practice.get(me)
check(me:GetAttribute("State") == "PRACTICE" and session ~= nil, "a first PLAY goes to the practice yard")
check(not home.teamSelect.Enabled and not home.home.Enabled, "not the team screen: the home screen goes")
check(banner.screen.Enabled and banner.title.Text == PracticeConfig.INTRO.title, "the welcome: " .. banner.title.Text)
check(yards() == 1 and session.yard.Parent == workspace.PracticeYards, "a yard of its own")
local character = assert(me.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
check(root.Position.X >= PracticeConfig.ORIGIN.X - 1 and (root.Position - session.start.Position).Magnitude < 1, "the avatar on its START pad, far from the battlefield")
check(me:GetAttribute("TeamId") == nil and Team.activeCount() == 0, "with no team slot")
check(character:GetAttribute("ProtectedUntil") == nil and character:FindFirstChildOfClass("ForceField") == nil, "and no spawn protection in the way")
check(me:GetAttribute("Weapon") == WeaponConfig.default and character:FindFirstChild("HeldWeapon"), "the Gas Blaster in hand")
local cam = workspace.CurrentCamera
check(cam.CameraType == Enum.CameraType.Custom and cam.CameraSubject == character:FindFirstChildOfClass("Humanoid"), "the camera follows the avatar")
RunService.RenderStepped:Fire(0.016)
check(CombatScreen.parts.crosshair.Visible, "with the crosshair")
-- The compass is the battlefield's: none in the yard, and no pings from it.
local Compass = require(Controllers.CompassController)
Compass.render()
check(not Compass.parts.screen.Enabled and not Compass.ping(), "no compass or pings in the yard")
-- A second PLAY while it opens does nothing more.
Home.play()
task.wait(0.1)
check(yards() == 1 and not home.teamSelect.Enabled, "PLAY again: still one yard")

-- Step 1: gas the dummies.
task.wait(PracticeConfig.INTRO_SECONDS + 0.1)
local shootStep = PracticeConfig.STEPS[1]
check(me:GetAttribute("PracticeStep") == "shoot" and banner.title.Text == shootStep.title, "step 1: " .. banner.title.Text)
check(banner.progress.Text == "0 / 3 POPPED" and banner.step.Text == "STEP 1 OF 3", "with its progress: " .. banner.progress.Text)
local dummies = session.yard.Dummies
local range1, range2, range3 = dummies.Range1, dummies.Range2, dummies.Range3
local minSize = PracticeConfig.DUMMY.MIN_SIZE
check(range2.Body.Size.X == minSize and range2:GetAttribute("Gas") == 0, "the dummies start empty")
-- A face the head can't hide: in front of it toward the camera (a
-- billboard's StudsOffset +Z), never drawn over walls.
for _, dummy in dummies:GetChildren() do
	local face = dummy.Head:FindFirstChild("Face")
	check(face and face.StudsOffset.Z > dummy.Head.Size.Z / 2 and face.StudsOffset.X == 0 and face.StudsOffset.Y == 0, `{dummy.Name}'s face sits in front of its head`)
	check(not face.AlwaysOnTop, `{dummy.Name}'s face doesn't show through walls`)
end
shoot(me, range2.Body, 4)
check(range2:GetAttribute("Gas") == 80 and range2.Body.Size.X > minSize, "four hits: 80% and swelling")
check(sent(me, "hit", function(e)
	return e.victim <= PracticeConfig.DUMMY_ID_BASE and not e.blocked and e.gas == 80
end) == 1, "each hit on the shooter's crosshair")
shoot(me, range2.Body)
check(range2:GetAttribute("Popped") == true and range2.Body.Transparency == 1 and not range2.Body.CanQuery, "the fifth pops it")
check(sent(me, "explosion") == 1 and sent(me, "hit", function(e)
	return e.gas == 100
end) == 1, "with the kaboom marker and the explosion")
check(me:GetAttribute("PracticeCount") == 1 and banner.progress.Text == "1 / 3 POPPED", "1 popped")
task.wait(0.2)
check(range1:GetAttribute("Gas") == GameConfig.EXPLOSION.CHAIN_GAS and range3:GetAttribute("Gas") == GameConfig.EXPLOSION.CHAIN_GAS, "its blast gassed the dummies either side")
shoot(me, range1.Head)
check(range1:GetAttribute("Gas") == 40 + WeaponConfig.weapons.GasBlaster.headshotGas, "a headshot does more")
check(sent(me, "hit", function(e)
	return e.headshot == true
end) == 1, "and says so")
shoot(me, range1.Body, 2)
check(range1:GetAttribute("Popped") == true and me:GetAttribute("PracticeCount") == 2, "2 popped")
shoot(me, range3.Body, 3)
check(range3:GetAttribute("Popped") == true and me:GetAttribute("PracticeCount") == 3, "3 popped")
check(banner.title.Text == shootStep.cheer, "a cheer: " .. banner.title.Text)
task.wait(PracticeConfig.DUMMY.RESPAWN_SECONDS + 0.1)
check(range3:GetAttribute("Popped") == false and range3:GetAttribute("Gas") == 0 and range3.Body.Size.X == minSize and range3.Body.CanQuery, "popped dummies come back, empty")

-- Step 2: a Fart Dash.
local dashStep = PracticeConfig.STEPS[2]
check(me:GetAttribute("PracticeStep") == "dash" and banner.title.Text == dashStep.title, "step 2: " .. banner.title.Text)
check(banner.progress.Visible == false, "nothing to count")
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
humanoid.FloorMaterial = Enum.Material.Grass
press(Enum.KeyCode.LeftShift)
task.wait(0.1)
check(yardDashes == 1 and matchDashes == 0, "Shift: a dash the yard hears, and nothing that counts for challenges")
check(me:GetAttribute("PracticeCount") == 1 and banner.title.Text == dashStep.cheer, "cleared: " .. banner.title.Text)
task.wait(PracticeConfig.CHEER_SECONDS + 0.2)

-- Step 3: the barrel.
local barrelStep = PracticeConfig.STEPS[3]
check(me:GetAttribute("PracticeStep") == "barrel" and banner.title.Text == barrelStep.title, "step 3: " .. banner.title.Text)
-- Down the lane, out of the way of the stink range.
character:PivotTo(session.start * CFrame.new(0, 0, -66))
local barrel = session.yard.PracticeBarrel
shoot(me, barrel.Barrel)
check(barrel:GetAttribute("Ready") == true and not barrel:FindFirstChild("Danger"), "one hit: still there")
shoot(me, barrel.Barrel)
check(barrel:FindFirstChild("Danger") ~= nil, "two: the fuse is lit (a red outline)")
task.wait(GameConfig.BARREL.FUSE_SECONDS + 0.3)
check(sent(me, "barrel") == 1 and barrel:GetAttribute("Ready") == false and barrel.Barrel.Transparency == 1, "KABOOM: the barrel goes")
local cornerPopped = 0
for _, name in { "Corner1", "Corner2", "Corner3" } do
	if dummies[name]:GetAttribute("Popped") then
		cornerPopped += 1
	end
end
check(cornerPopped == 3 and sent(me, "explosion") == 6, "and the chain pops the three dummies round it")
check(me:GetAttribute("PracticeCount") == 1 and banner.title.Text == barrelStep.cheer, "cleared: " .. banner.title.Text)
task.wait(PracticeConfig.CHEER_SECONDS + 0.2)
check(me:GetAttribute("PracticeStep") == "done" and banner.title.Text == PracticeConfig.DONE.title, "done: " .. banner.title.Text)
task.wait(PracticeConfig.DONE_SECONDS + 0.3)

-- Back to the match flow: home, the team screen open.
check(me:GetAttribute("State") == "MENU_SPECTATOR" and me.Character == nil, "the yard's done: back home")
check(home.home.Enabled and home.teamSelect.Enabled and not banner.screen.Enabled, "with the team screen open")
check(yards() == 0 and Practice.get(me) == nil, "the yard is gone")
check(me:GetAttribute("PracticeEnded") == "finished" and me:GetAttribute("PracticeDue") == false, "finished, and not due again")
check(data.PracticeDone == true, "saved in the profile")
check(data.Coins == before.coins and data.XP == before.xp and data.LifetimeXP == before.lifetimeXP, "no coins or XP from the yard")
check(data.TotalEliminations == before.eliminations and data.TotalDeaths == before.deaths and data.TotalPlaytime == before.playtime and #data.Ledger == before.ledger, "no stats, playtime or ledger entries")
check(counter("Combat.shots") == before.shots and counter("Combat.hits") == before.hits, "its shots aren't match shots")
check(counter("funnel.new.shot") == 0 and (Telemetry.snapshot().rejects.FireWeapon or {}).notActive == nil, "nor the funnel's first shot, and none was refused")
local scores = Scores.getScores()
check((scores.Stinkers or 0) == 0 and (scores.Sharters or 0) == 0, "no team points")
check(counter("Practice.started") == 1 and counter("Practice.finished") == 1 and counter("Practice.cleared.barrel") == 1, "counted: started, each step, finished")
click(home.teamButtons.Stinkers)
task.wait(0.6)
check(me:GetAttribute("State") == "ACTIVE" and me:GetAttribute("TeamId") == "Stinkers", "picking a team joins the match")
check(onOwnSpawn(me) and assert(me.Character):GetAttribute("ProtectedUntil") ~= nil, "from the team's own spawn, protected as usual")
check(me:GetAttribute("Weapon") == WeaponConfig.default and me.Character:FindFirstChild("HeldWeapon"), "with the loadout")
Locker.open("Settings")
local row = Locker.parts.content.Settings:FindFirstChild("PracticeRow")
check(row and row.Practice:GetAttribute("Enabled") == false, "Settings' PRACTICE YARD waits for the home screen")
Locker.close()
Home.setMenu(true)
click(home.spectate)
task.wait(0.6)
check(me:GetAttribute("State") == "MENU_SPECTATOR", "spectate: home")
click(home.play)
check(home.teamSelect.Enabled and Practice.get(me) == nil, "the next PLAY goes straight to the teams")
click(home.teamSelect:FindFirstChild("Close", true))

-- The PRACTICE tile: the yard again. Someone else's shots can't touch it.
click(home.tiles.Practice)
task.wait(0.2)
session = assert(Practice.get(me))
check(me:GetAttribute("State") == "PRACTICE" and me:GetAttribute("PracticeEnded") == nil, "PRACTICE replays the yard")
check(counter("Practice.replayed") == 1, "counted as a replay")
local nosy = join("Nosy", 55)
Remotes.Practice.OnServerEvent:Fire(nosy, "start")
task.wait(0.2)
check(Practice.get(nosy) and yards() == 2, "two players, two yards")
check(((Practice.get(nosy) :: any).yard.Floor.Ground.Position - session.yard.Floor.Ground.Position).Magnitude >= PracticeConfig.SPACING, "further apart than any gun reaches")
nosy.Character:PivotTo(session.start * CFrame.new(3, 0, 0))
local mine = session.yard.Dummies.Range2
shoot(nosy, mine.Body, 2)
check(mine:GetAttribute("Gas") == 0 and sent(nosy, "hit") == 0, "another player's shots don't touch my yard")
check(sent(me, "shot", function(e)
	return e.shooter == nosy.UserId
end) == 0, "and yard shots are only shown to the shooter")
press(PracticeConfig.SKIP_KEY)
task.wait(0.2)
check(me:GetAttribute("State") == "MENU_SPECTATOR" and me:GetAttribute("PracticeEnded") == "skipped", "Enter skips")
check(home.teamSelect.Enabled and yards() == 1, "on to the team screen; my yard is gone, Nosy's isn't")
Remotes.Practice.OnServerEvent:Fire(nosy, "skip")
task.wait(0.2)
check(nosy:GetAttribute("State") == "MENU_SPECTATOR" and yards() == 0 and nosy:GetAttribute("PracticeDue") == false, "Nosy skips too: done for good")
click(home.teamSelect:FindFirstChild("Close", true))

-- Settings: the yard again, and the SKIP button.
Locker.open("Settings")
row = Locker.parts.content.Settings:FindFirstChild("PracticeRow")
check(row and row.Practice:GetAttribute("Enabled") ~= false, "Settings has PRACTICE YARD on the home screen")
click(row.Practice)
task.wait(0.2)
check(me:GetAttribute("State") == "PRACTICE" and not Locker.isOpen, "it closes Settings and opens the yard")
click(banner.skip)
task.wait(0.2)
check(me:GetAttribute("State") == "MENU_SPECTATOR" and home.teamSelect.Enabled, "SKIP: on to the team screen")
click(home.teamSelect:FindFirstChild("Close", true))

-- Who gets it: not a veteran, not a temporary profile.
local vet = join("Vet", 50)
local temp = join("Temp", 51)
task.wait(0.3)
check(Data.isLoaded(vet) and vet:GetAttribute("PracticeDue") == false, "a veteran's profile: not due")
check(temp:GetAttribute("DataStatus") == "unsaved" and temp:GetAttribute("PracticeDue") == false, "a temporary profile: not due (everyone looks new in an outage)")
Remotes.Practice.OnServerEvent:Fire(vet, { "junk" })
Remotes.Practice.OnServerEvent:Fire(vet, "fly")
task.wait(0.6)
check(Practice.get(vet) == nil and yards() == 0, "junk requests do nothing")
Remotes.RequestPlay.OnServerEvent:Fire(vet)
task.wait(0.6)
Remotes.Practice.OnServerEvent:Fire(vet, "start")
task.wait(0.2)
check(vet:GetAttribute("State") == "ACTIVE" and Practice.get(vet) == nil, "and not from a match")

-- Leaving the game mid-yard: the yard comes down, and it's due next time.
local newbie = join("Newbie", 52)
check(newbie:GetAttribute("PracticeDue") == true, "Newbie's new profile: due")
Remotes.Practice.OnServerEvent:Fire(newbie, "start")
task.wait(0.2)
check(newbie:GetAttribute("State") == "PRACTICE" and yards() == 1, "Newbie in the yard")
newbie.Parent = nil
task.wait(0.5)
check(yards() == 0 and Practice.get(newbie) == nil, "leaving takes the yard down")
check(counter("Practice.quit") == 1 and saved.player_52 and saved.player_52.PracticeDone == false and saved.player_52.Lock == nil, "the save says it isn't done")
local back = join("Newbie", 52)
task.wait(0.3)
check(back:GetAttribute("PracticeDue") == true, "so it's offered again next time")

-- Spectating from the yard: home, and done.
Remotes.Practice.OnServerEvent:Fire(back, "start")
task.wait(0.2)
Remotes.RequestSpectate.OnServerEvent:Fire(back)
task.wait(0.2)
check(back:GetAttribute("State") == "MENU_SPECTATOR" and back.Character == nil and yards() == 0, "SPECTATE from the yard: home, the yard gone")
check(back:GetAttribute("PracticeEnded") == "left" and back:GetAttribute("PracticeDue") == false, "and it counts as done")

-- PLAY from the yard: straight into the match.
local jumper = join("Jumper", 56)
Remotes.Practice.OnServerEvent:Fire(jumper, "start")
task.wait(0.2)
Remotes.RequestPlay.OnServerEvent:Fire(jumper)
task.wait(0.3)
check(jumper:GetAttribute("State") == "ACTIVE" and jumper:GetAttribute("TeamId") ~= nil and onOwnSpawn(jumper), "PLAY from the yard joins the match")
check(yards() == 0 and jumper:GetAttribute("PracticeEnded") == "played" and jumper:GetAttribute("PracticeDue") == false, "the yard gone, done")

-- Idle in the yard: the AFK check leaves it alone, and it ends by itself.
local idler = join("Idler", 57)
Remotes.Practice.OnServerEvent:Fire(idler, "start")
task.wait(GameConfig.AFK_SPECTATE_SECONDS + 10)
check(idler:GetAttribute("State") == "PRACTICE" and not told(idler, "afkWarning") and not told(idler, "afkMoved"), "a minute idle in the yard: never AFK")
task.wait(PracticeConfig.MAX_SECONDS - GameConfig.AFK_SPECTATE_SECONDS)
check(idler:GetAttribute("State") == "MENU_SPECTATOR" and idler:GetAttribute("PracticeEnded") == "finished", "the yard ends by itself in time")
check(counter("Practice.timedOut") == 1 and yards() == 0 and idler:GetAttribute("PracticeDue") == false, "counted, and done")

return { status = "PASS", checks = checks }
