-- Hit feedback at the crosshair, on one client against the real server:
--   * no marker when you fire: only the server's verdict (CombatEvent
--     "hit") shows one, and which one is decided in order: blocked, the
--     hit that fills their gas, headshot, body
--   * a body hit: white, popping in and settling, then fading and gone;
--     a second hit restarts it without the first cutting it short
--   * a headshot: bigger and gold, and the hit sound higher and louder
--     (back to normal for the next body hit)
--   * the hit that fills their gas: bigger still, orange, with a ring
--     thrown out (and the headshot sound if it was one); a hit that did
--     nothing: small, grey, no pop, no ring, no sound
--   * REDUCE MOTION: no pop and no fade, just shown and hidden, and a
--     still ring; REDUCED EFFECTS: the pop stays, no fade, no ring
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)
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
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Remotes = ReplicatedStorage.Remotes

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
local Combat = require(client.Controllers.CombatController)
local Settings = require(client.Settings)
Lifecycle.requestPlay(me, nil)
task.wait(0.5)

local HIT = UIConfig.hitMarker
-- The hit sound's own mix (Audio): its volume, and the range its pitch
-- varies in from play to play.
local HIT_MIX = require(game.ReplicatedStorage.Shared.Config.AudioConfig).MIX.hit
local function usualPitch(sound: Sound): boolean
	return sound.PlaybackSpeed >= HIT_MIX.pitch.Min and sound.PlaybackSpeed <= HIT_MIX.pitch.Max
end
local LOOKS = HIT.looks
local p = Combat.parts
local marker = p.hitMarker
local ring = p.hitRing
check(marker.Parent == p.crosshair and ring.Parent == p.crosshair, "the marker and its ring sit on the crosshair")

-- What the marker's pop, its transparency and the ring's size go through
-- after each hit.
local pops, fades, rings = {}, {}, {}
p.hitPop:GetPropertyChangedSignal("Scale"):Connect(function()
	table.insert(pops, p.hitPop.Scale)
end)
marker:GetPropertyChangedSignal("TextTransparency"):Connect(function()
	table.insert(fades, marker.TextTransparency)
end)
ring:GetPropertyChangedSignal("Size"):Connect(function()
	table.insert(rings, ring.Size.X.Offset)
end)
local function hit(event: { [string]: any })
	table.clear(pops)
	table.clear(fades)
	table.clear(rings)
	event.kind = "hit"
	event.victim = 2
	Remotes.CombatEvent:FireClient(me, event)
	task.wait()
end
local function settle()
	task.wait(0.6) -- longer than any marker shows
end

-- Firing on its own: no marker.
check(Combat.fire(), "I fire")
task.wait(0.2)
check(not marker.Visible, "but no marker: only the server's verdict shows one")
check(Combat.hitKind({ blocked = true, gas = 100, headshot = true }) == "blocked", "a hit that did nothing is just that")
check(Combat.hitKind({ gas = 100, headshot = true }) == "kaboom", "then the hit that fills their gas")
check(Combat.hitKind({ gas = 25, headshot = true }) == "headshot" and Combat.hitKind({ gas = 20 }) == "body", "then headshot, then body")

-- A body hit.
hit({ gas = 20, headshot = false, blocked = false })
check(marker.Visible and marker.TextSize == LOOKS.body.size and marker.TextColor3 == LOOKS.body.color, "a body hit: the marker, white")
check(marker.TextTransparency == 0 and pops[1] == LOOKS.body.pop and LOOKS.body.pop > 1 and p.hitPop.Scale == 1, "popping in and settling")
local sound = SoundService:FindFirstChild("hit") :: Sound
check(sound and sound.Playing and usualPitch(sound) and sound.Volume == HIT_MIX.volume * Settings.volume, "with the hit sound")
check(not ring.Visible, "no ring")
settle()
check(not marker.Visible and fades[#fades] == 1, "then it fades and goes")
hit({ gas = 20 })
task.wait(0.05)
hit({ gas = 40 })
task.wait(0.05) -- past when the first would fade, before the second does
check(marker.Visible and marker.TextTransparency == 0, "a second hit restarts it: the first's fade doesn't cut it short")
task.wait(0.1) -- past when the first would hide, before the second does
check(marker.Visible, "nor does the first's hide")
settle()

-- A headshot.
hit({ gas = 25, headshot = true, blocked = false })
check(marker.TextSize == LOOKS.headshot.size and LOOKS.headshot.size > LOOKS.body.size, "a headshot: a bigger marker")
check(marker.TextColor3 == LOOKS.headshot.color and LOOKS.headshot.color ~= LOOKS.body.color, "in gold")
check(pops[1] == LOOKS.headshot.pop and LOOKS.headshot.pop > LOOKS.body.pop, "with a bigger pop")
check(sound.Playing and sound.PlaybackSpeed == HIT.headshotPitch and HIT.headshotPitch > 1, "the hit sound, higher")
check(math.abs(sound.Volume - HIT_MIX.volume * Settings.volume * HIT.headshotVolume) < 1e-9 and HIT.headshotVolume > 1, "and louder")
settle()
hit({ gas = 45 })
check(usualPitch(sound) and sound.Volume == HIT_MIX.volume * Settings.volume, "the next body hit sounds as usual")
settle()

-- The hit that fills their gas.
hit({ gas = 100, headshot = false, blocked = false })
check(marker.TextSize == LOOKS.kaboom.size and LOOKS.kaboom.size > LOOKS.headshot.size, "the hit that sets them off: bigger still")
check(marker.TextColor3 == LOOKS.kaboom.color and LOOKS.kaboom.color ~= LOOKS.headshot.color, "in orange")
check(ring.Visible and rings[1] == LOOKS.kaboom.size and ring.Size.X.Offset == HIT.ringSize, "with a ring thrown out")
check(usualPitch(sound), "and the usual hit sound")
settle()
check(not marker.Visible and not ring.Visible, "both gone after")
hit({ gas = 100, headshot = true })
check(marker.TextSize == LOOKS.kaboom.size and sound.PlaybackSpeed == HIT.headshotPitch, "a finishing headshot: that marker, the headshot sound")
settle()

-- A hit that did nothing (a teammate, spawn protection, or already going off).
sound.Playing = false
hit({ gas = 100, headshot = true, blocked = true })
check(marker.Visible and marker.TextSize == LOOKS.blocked.size and marker.TextColor3 == LOOKS.blocked.color, "a hit that did nothing: small and grey")
check(#pops == 0 and not ring.Visible and not sound.Playing, "no pop, no ring, no sound")
settle()

-- REDUCE MOTION: shown and hidden.
Settings.reduceMotion = true
hit({ gas = 25, headshot = true })
check(marker.Visible and marker.TextSize == LOOKS.headshot.size and #pops == 0 and p.hitPop.Scale == 1, "REDUCE MOTION: the headshot's marker, no pop")
check(sound.PlaybackSpeed == HIT.headshotPitch, "the headshot sound all the same")
task.wait(LOOKS.headshot.seconds - 0.05)
check(marker.Visible and marker.TextTransparency == 0, "no fade: it stays solid")
task.wait(0.1)
check(not marker.Visible and not table.find(fades, 1), "then it's hidden")
hit({ gas = 100 })
check(ring.Visible and #rings == 0 and ring.Size.X.Offset == HIT.ringSize, "the finishing hit's ring stands still")
settle()
check(not ring.Visible, "and goes")
Settings.reduceMotion = false

-- REDUCED EFFECTS: the pop stays, the extras go.
Settings.reducedEffects = true
hit({ gas = 100 })
check(marker.Visible and marker.TextSize == LOOKS.kaboom.size and pops[1] == LOOKS.kaboom.pop, "REDUCED EFFECTS: the marker still pops")
check(not ring.Visible, "no ring")
settle()
check(not marker.Visible and not table.find(fades, 1), "no fade")
Settings.reducedEffects = false

return { status = "PASS", checks = checks }
