-- Live events: Bean Rain (masterplan 6.3), with one client:
--   * off as shipped: rounds never book one
--   * announced: the banner WARNING_SECONDS before, a ring on the ground
--     before each bean lands; beans only on the lanes, never in a spawn
--     room; never more than MAX_BEANS parts at once
--   * a bean picked up pays a few coins (capped per event) and refills
--     the Fart Dash, on the server and the client; nobody takes gas
--   * it ends by itself, and a round's end clears it at once
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
local FeatureFlags = require(Shared.Config.FeatureFlags)
local EventConfig = require(Shared.Config.EventConfig)
local Events = require(server.Services.EventService)
local Round = require(server.Services.RoundService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Gas = require(server.Services.GasService)
local Dash = require(server.Services.DashService)
local AFK = require(server.Services.AFKService)
local Map = require(server.Services.MapService)
local Telemetry = require(server.Telemetry)
local Remotes = ReplicatedStorage.Remotes
local RAIN = EventConfig.BEAN_RAIN

local refills = 0
Remotes.CombatEvent.FiredToClient:Connect(function(_, event)
	if event.kind == "dashRefill" then
		refills += 1
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
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local HUD = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.HUDController)
local foe = Instance.new("Player")
foe.Name = "Foe"
foe.UserId = 2
foe.Parent = Players
task.wait(0.1)
Lifecycle.requestPlay(me, nil)
Lifecycle.requestPlay(foe, nil)
task.wait(0.5)

-- Off.
check(FeatureFlags.EVENTS == false, "off as shipped")
for _ = 1, 6 do
	Round.testEndPhaseIn(0)
	task.wait(0.4)
	Round.testEndPhaseIn(0)
	task.wait(0.4)
	check(Events.phase() == nil, "rounds don't book events while off")
end
AFK.markActive(me)
AFK.markActive(foe)
Lifecycle.requestPlay(me, nil)
Lifecycle.requestPlay(foe, nil)
task.wait(0.3)

-- Booked by a round when on (over a few rounds, about half get one).
Events.testEnable(true)
Events.setRandom(Random.new(3))
local booked = 0
for _ = 1, 10 do
	Round.testEndPhaseIn(0)
	task.wait(0.4)
	Round.testEndPhaseIn(0)
	task.wait(0.4)
	if Events.phase() == "booked" then
		booked += 1
	end
	AFK.markActive(me)
	AFK.markActive(foe)
end
check(booked >= 2 and booked <= 8, `rounds book Bean Rain about half the time ({booked} of 10)`)

-- Announced.
Lifecycle.requestPlay(me, nil)
Lifecycle.requestPlay(foe, nil)
task.wait(0.3)
check(Round.phase() == "ACTIVE", "a round on")
Events.book(workspace:GetServerTimeNow() + RAIN.WARNING_SECONDS + 1)
task.wait(1.5)
check(Events.phase() == "warning" and workspace:GetAttribute("EventPhase") == "warning", "warned first")
task.wait(0.1)
check(HUD.parts.event.Visible and string.find(HUD.parts.event.Text, "BEAN RAIN IN", 1, true), "the banner: " .. HUD.parts.event.Text)
check(#Events.beans() == 0, "and no beans yet")
task.wait(RAIN.WARNING_SECONDS)
check(Events.phase() == "active", "then the rain")
task.wait(0.6)
local marker = false
for _, bean in Events.beans() do
	if not bean.landed and bean.part.Name == "BeanMarker" then
		marker = true
	end
end
check(marker, "a ring shows where a bean will land, before it lands")
local gasBefore = Gas.gasOf(me) + Gas.gasOf(foe)
local most = 0
local inSpawn = false
local model = Map.current()
local rooms = {}
for _, zone in model.Zones:GetChildren() do
	if zone.Name == "SpawnZone" then
		table.insert(rooms, zone)
	end
end
for _ = 1, 40 do
	task.wait(0.25)
	most = math.max(most, #Events.beans())
	for _, bean in Events.beans() do
		for _, room in rooms do
			local p = room.CFrame:PointToObjectSpace(bean.part.Position)
			if math.abs(p.X) <= room.Size.X / 2 and math.abs(p.Z) <= room.Size.Z / 2 then
				inSpawn = true
			end
		end
	end
end
check(most > 0 and most <= RAIN.MAX_BEANS, `beans fall, never more than {RAIN.MAX_BEANS} at once ({most})`)
check(not inSpawn, "never in a spawn room")
for _ = 1, 200 do
	local spot = Events.spot()
	for _, room in rooms do
		local p = room.CFrame:PointToObjectSpace(spot :: Vector3)
		check(not (math.abs(p.X) <= room.Size.X / 2 and math.abs(p.Z) <= room.Size.Z / 2), "no spot in a spawn room")
	end
end

-- Picking them up.
local coins = me:GetAttribute("Coins") or 0
local picked = 0
for _ = 1, 60 do
	for _, bean in Events.beans() do
		if bean.landed and bean.goneAt > 0 and bean.part.Parent then
			me.Character:PivotTo(CFrame.new(bean.part.Position.X, 3, bean.part.Position.Z))
			task.wait(0.3)
			picked += 1
			break
		end
	end
	task.wait(0.1)
	AFK.markActive(me)
	if picked >= RAIN.MAX_PER_PLAYER + 2 then
		break
	end
end
check(picked >= RAIN.MAX_PER_PLAYER + 1, `I picked up {picked} beans`)
local counted = Telemetry.snapshot().counters["Event.beansPicked"] or 0
check(counted >= RAIN.MAX_PER_PLAYER + 1, "counted")
check(((me:GetAttribute("Coins") or 0) :: number) - coins == RAIN.COINS * RAIN.MAX_PER_PLAYER, `{RAIN.COINS} coins each, for {RAIN.MAX_PER_PLAYER} at most`)
check(refills >= picked - 1, "each one refills the Fart Dash")
Dash.dash(me, Vector3.new(1, 0, 0))
Dash.refill(me)
check(Dash.dash(me, Vector3.new(-1, 0, 0)), "a refilled dash goes at once")
check(Gas.gasOf(me) + Gas.gasOf(foe) == gasBefore, "nobody took gas")

-- It ends by itself.
task.wait(RAIN.DURATION_SECONDS + RAIN.BEAN_SECONDS + RAIN.TELEGRAPH_SECONDS + 1)
check(Events.phase() == nil and #workspace.Events:GetChildren() == 0 and workspace:GetAttribute("Event") == nil, "over: no parts, no attributes")
check(not HUD.parts.event.Visible, "and no banner")
-- A round's end clears it at once.
AFK.markActive(me)
Lifecycle.requestPlay(me, nil)
Lifecycle.requestPlay(foe, nil)
task.wait(0.2)
Events.book(workspace:GetServerTimeNow())
task.wait(1.5)
check(#Events.beans() > 0, "rain again")
Round.testEndPhaseIn(0)
task.wait(0.5)
check(Events.phase() == nil and #workspace.Events:GetChildren() == 0, "the round's end clears it")
Events.testEnable(nil)

return { status = "PASS", checks = checks }
