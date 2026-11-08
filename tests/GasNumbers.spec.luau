-- Floating gas numbers (GasNumbers), on one client against the real
-- server, with real shots:
--   * a hit of yours that lands: the server sends the gas it put in and
--     where it landed, and "+20%" pops in there, white, rises and fades;
--     a headshot's "+25%" is bigger and in the headshot marker's gold; a
--     bot you hit gets one too; the Spritzer's are "+9%"
--   * none for a hit that did nothing: spawn protection, a teammate, or
--     someone already going off (the server says it put in 0)
--   * your own hits only: someone else's hit never shows on your screen
--   * at most `pool` at once (reducedPool with REDUCED EFFECTS, which also
--     drops the fade); REDUCE MOTION: no pop and no rise, shown and hidden
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)
local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
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
-- No bots but the one made here.
require(server.Services.BotDirector).testSetEnabled(false)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local TeamService = require(server.Services.TeamService)
local Gas = require(server.Services.GasService)
local Bots = require(server.Services.BotService)
local Combat = require(server.Services.CombatService)
local AFK = require(server.Services.AFKService)
local Remotes = ReplicatedStorage.Remotes

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local client = game.StarterPlayer.StarterPlayerScripts.Client
local GasNumbers = require(client.GasNumbers)
local Settings = require(client.Settings)
Lifecycle.requestPlay(me, nil)

local NUMBERS = UIConfig.gasNumbers
local LOOKS = NUMBERS.looks
check(FeatureFlags.GAS_NUMBERS, "gas numbers are on")
check(LOOKS.headshot.color == UIConfig.hitMarker.looks.headshot.color and LOOKS.headshot.size > LOOKS.body.size, "a headshot's number: bigger, in the headshot marker's gold")
check(NUMBERS.reducedPool < NUMBERS.pool, "fewer at once with Reduced effects")

-- What every client is sent (the spec sees who each event was for).
local heard: { [Player]: { any } } = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	heard[player] = heard[player] or {}
	table.insert(heard[player], event)
end)
local function last(player: Player, kind: string): any
	local list = heard[player] or {}
	for i = #list, 1, -1 do
		if list[i].kind == kind then
			return list[i]
		end
	end
	return nil
end

local nextId = 1
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local function place(player: Player, x: number, z: number)
	player.Character:PivotTo(CFrame.new(x, 3, z))
end
local function awake()
	for _, player in Players:GetPlayers() do
		AFK.markActive(player)
	end
end
-- Across a clear stretch of the Gas Gutter lane (x = 53, z = -14 to 14):
-- level with the head, or down at the body.
local HEAD = Vector3.new(0, 0, 1)
local BODY = Vector3.new(0, -1.5, 28).Unit
local shots: { [Player]: number } = {}
local function shoot(player: Player, direction: Vector3)
	shots[player] = (shots[player] or 0) + 1
	Remotes.FireWeapon.OnServerEvent:Fire(player, direction, shots[player])
end
local function settle()
	task.wait(NUMBERS.seconds + 0.1)
end

local foe = join("Foe")
local mate = join("Mate")
local myTeam = me:GetAttribute("TeamId")
local otherTeam = if myTeam == "Stinkers" then "Sharters" else "Stinkers"
TeamService.testSetTeam(foe, otherTeam)
TeamService.testSetTeam(mate, myTeam)
task.wait(0.2)
check(TeamService.teamOf(foe) == otherTeam and TeamService.teamOf(mate) == myTeam, "a foe and a teammate")

-- What the newest number goes through: its pop, its rise and its fade.
local pops, rises, fades = {}, {}, {}
local watched: { [any]: boolean } = {}
local function watch()
	for _, entry in GasNumbers.numbers do
		if not watched[entry] then
			watched[entry] = true
			entry.pop:GetPropertyChangedSignal("Scale"):Connect(function()
				table.insert(pops, entry.pop.Scale)
			end)
			entry.board:GetPropertyChangedSignal("StudsOffset"):Connect(function()
				table.insert(rises, entry.board.StudsOffset.Y)
			end)
			entry.label:GetPropertyChangedSignal("TextTransparency"):Connect(function()
				table.insert(fades, entry.label.TextTransparency)
			end)
		end
	end
end
local function newest(): any
	local best = nil
	for _, entry in GasNumbers.numbers do
		if entry.board.Enabled and (not best or entry.token > best.token) then
			best = entry
		end
	end
	return best
end
local function hitBy(shooter: Player, direction: Vector3): any
	watch()
	table.clear(pops)
	table.clear(rises)
	table.clear(fades)
	shoot(shooter, direction)
	task.wait()
	return last(shooter, "hit")
end

-- Spawn protection: the server says the hit did nothing, so no number.
place(me, 53, -14)
place(foe, 53, 14)
check(Lifecycle.isProtected(foe), "the foe is fresh from spawning")
local event = hitBy(me, BODY)
check(event and event.blocked and event.amount == 0, "a hit on a protected player: blocked, no gas put in")
check(GasNumbers.showing() == 0, "and no number")
task.wait(3.2)
awake()
check(not Lifecycle.isProtected(foe), "protection over")

-- A body hit that lands.
event = hitBy(me, BODY)
check(event and not event.blocked and event.amount == 20 and typeof(event.position) == "Vector3", "the server sends the gas it put in (20) and where it landed")
local number = newest()
check(GasNumbers.showing() == 1 and number, "one number")
check(number.label.Text == "+20%" and number.label.TextColor3 == LOOKS.body.color and number.label.TextSize == LOOKS.body.size, "\"+20%\", white")
check((number.attachment.WorldPosition - event.position).Magnitude < 1e-3, "right where the shot landed")
check(number.board.AlwaysOnTop and number.board.MaxDistance == NUMBERS.maxDistance, "drawn over the target, not past maxDistance")
settle()
event = hitBy(me, BODY)
number = newest()
check(number and number.label.Text == "+20%", "the next hit: its own number")
check(pops[1] == NUMBERS.pop and number.pop.Scale == 1, "it pops in and settles")
check(rises[1] and rises[#rises] - rises[1] == NUMBERS.rise, "and floats up")
check(number.label.TextTransparency == 0, "solid at first")
settle()
check(fades[#fades] == 1 and not number.board.Enabled and GasNumbers.showing() == 0, "then it fades and goes")

-- A headshot.
event = hitBy(me, HEAD)
number = newest()
check(event.headshot and event.amount == 25, "a headshot puts in 25")
check(number and number.label.Text == "+25%" and number.label.TextColor3 == LOOKS.headshot.color and number.label.TextSize == LOOKS.headshot.size, "\"+25%\", bigger and gold")
settle()

-- A teammate: friendly fire is off, so nothing.
place(mate, 53, 14)
place(foe, 70, 40)
event = hitBy(me, BODY)
check(event and event.victim == mate.UserId and event.blocked and event.amount == 0, "a hit on a teammate does nothing")
check(GasNumbers.showing() == 0, "and shows no number")
settle()

-- Someone already going off.
place(mate, 30, 40)
place(foe, 53, 14)
for _ = 1, 6 do
	if foe.Character:GetAttribute("ExplodesAt") then
		break
	end
	task.wait(0.31)
	hitBy(me, BODY)
end
check(Gas.isExploding(foe), "the foe is going off")
task.wait(0.31)
watch()
local before = #GasNumbers.numbers
local shown = 0
for _, entry in GasNumbers.numbers do
	shown = math.max(shown, entry.token)
end
event = hitBy(me, BODY)
check(event and event.blocked and event.amount == 0, "a hit on someone already going off does nothing")
local newer = false
for _, entry in GasNumbers.numbers do
	newer = newer or entry.token > shown
end
check(not newer and #GasNumbers.numbers == before, "and gets no number")
task.wait(1.2 + 3.2 + 3.1) -- it goes off, respawns, and its protection ends
awake()

-- Someone else's hit lands, but only they hear about it.
local function hitsFor(player: Player): number
	local n = 0
	for _, heardEvent in heard[player] or {} do
		if heardEvent.kind == "hit" then
			n += 1
		end
	end
	return n
end
place(me, 30, -40)
place(mate, 53, -14)
check(not Lifecycle.isProtected(foe) and foe.Character and Gas.gasOf(foe) == 0, "the foe is back")
place(foe, 53, 14)
local mine = hitsFor(me)
event = hitBy(mate, BODY)
check(event and not event.blocked and event.amount == 20, "a teammate's hit lands")
check(hitsFor(me) == mine, "the server tells them, not me")
check(GasNumbers.showing() == 0, "so my screen shows no number for it")
settle()

-- A bot.
-- (a bot avatar as BotDirector builds one, in the lane)
local botBody = Instance.new("Model")
botBody.Name = "Whiff"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(53, 3, 14)
root.Parent = botBody
local head = Instance.new("Part")
head.Name = "Head"
head.Size = Vector3.new(2, 1, 1)
head.CFrame = CFrame.new(53, 4.5, 14)
head.Parent = botBody
Instance.new("Humanoid").Parent = botBody
botBody.PrimaryPart = root
botBody.Parent = workspace
place(foe, 20, 40)
place(mate, 20, -40)
local bot = Bots.add(otherTeam, "Whiff")
Bots.attach(bot, botBody)
place(me, 53, -14)
task.wait(3.1)
awake()
event = hitBy(me, BODY)
number = newest()
check(event and event.victim == bot.id and not event.blocked and event.amount == 20, "a hit on a bot lands")
check(number and number.label.Text == "+20%", "and gets its number too")
settle()

-- The Spritzer: "+9%" a hit, ten a second.
check(Combat.setWeapon(me, "Spritzer"), "Spritzer in hand")
for _ = 1, 3 do
	task.wait(0.11)
	hitBy(me, BODY)
end
number = newest()
check(number and number.label.Text == "+9%", "the Spritzer's numbers: \"+9%\"")
check(GasNumbers.showing() == 3, "three quick hits, three numbers")
local spots = {}
for _, entry in GasNumbers.numbers do
	if entry.board.Enabled then
		spots[entry.board.StudsOffset.X] = true
	end
end
local sides = 0
for _ in spots do
	sides += 1
end
check(sides == 3, "side by side, not stacked")
settle()
Bots.remove(bot)
Gas.reset(foe)

-- REDUCED EFFECTS: no fade, and fewer at once.
place(me, 53, -14)
place(foe, 53, 14)
task.wait(0.2)
awake()
Settings.reducedEffects = true
for _ = 1, 7 do
	if foe.Character:GetAttribute("ExplodesAt") then
		break
	end
	task.wait(0.11)
	hitBy(me, BODY)
	check(GasNumbers.showing() <= NUMBERS.reducedPool, `REDUCED EFFECTS: never more than {NUMBERS.reducedPool} at once`)
end
check(GasNumbers.showing() == NUMBERS.reducedPool, "a spray fills them, the oldest making way")
check(#pops > 0 and pops[1] == NUMBERS.pop, "they still pop")
settle()
check(GasNumbers.showing() == 0 and not table.find(fades, 1), "and go without fading")
Settings.reducedEffects = false
Gas.reset(foe)

-- REDUCE MOTION: no pop, no rise.
Settings.reduceMotion = true
task.wait(0.31)
event = hitBy(me, BODY)
number = newest()
check(event and not event.blocked and number, "REDUCE MOTION: the number still shows")
check(#pops == 0 and number.pop.Scale == 1, "without a pop")
check(#rises <= 1 and number.board.StudsOffset.Y == NUMBERS.lift, "or a rise")
task.wait(NUMBERS.seconds - 0.05)
check(number.board.Enabled and number.label.TextTransparency == 0, "solid to the end")
task.wait(0.1)
check(not number.board.Enabled and not table.find(fades, 1), "then hidden")
Settings.reduceMotion = false

check(#GasNumbers.numbers <= NUMBERS.pool, `never more than {NUMBERS.pool} numbers made`)

return { status = "PASS", checks = checks }
