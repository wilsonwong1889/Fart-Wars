-- Sound (Audio, AudioConfig), with one client:
--   * the mix: every sound keeps its ID and has a volume; shots, dashes and
--     splats wobble in pitch; everything heard in the world has a range
--     that fits the 480-stud map, with an inverse roll-off
--   * flat sounds play from SoundService at their own volume and a pitch in
--     their range; Settings.sound and Settings.volume still rule every sound
--   * sounds in the world play where they happen, from a pooled voice with
--     their kind's range; one too far away to hear doesn't play; the pool
--     never grows past VOICES, a spray of one sound holds only PER_SOUND
--     voices, a voice is free again when its sound ends (or in time), the
--     oldest is reused when all are busy, and a lost anchor is rebuilt
--   * the game: other players' shots (their gun's sound), explosions,
--     barrels, their dashes, throws and emotes, stink bombs landing and Q
--     abilities play where they happen; your own shots, hits, warnings,
--     emote and throw, and the alpha call, stay flat (or aren't echoed),
--     and the screens' sounds have no position
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function near(a: any, b: Vector3): boolean
	return typeof(a) == "Vector3" and (a - b).Magnitude < 1e-3
end
local function close(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- The mix.
local MIX, RANGES = AudioConfig.MIX, AudioConfig.RANGES
local ids = 0
for name, id in AudioConfig do
	if type(id) == "string" then
		ids += 1
		check(string.match(id, "^rbxassetid://%d+$") ~= nil, `{name} keeps its asset ID`)
		local mix = MIX[name]
		check(mix ~= nil, `{name} has a mix`)
		check(type(mix.volume) == "number" and mix.volume > 0 and mix.volume <= 1, `{name}'s volume is between 0 and 1`)
		if mix.pitch then
			check(typeof(mix.pitch) == "NumberRange" and mix.pitch.Min >= 0.8 and mix.pitch.Max <= 1.25 and mix.pitch.Min <= mix.pitch.Max, `{name}'s pitch stays near its own`)
		end
		check(mix.range == nil or RANGES[mix.range] ~= nil, `{name}'s range is one of the kinds`)
	end
end
check(ids == 18, "all 18 sounds kept")
for name in MIX do
	check(type(AudioConfig[name]) == "string", `the mix for {name} is for a sound`)
end
for kind, range in RANGES do
	check(range.min > 0 and range.min < range.max and range.max <= 480, `{kind}: full volume close by, silent before the far side of the map`)
end
check(RANGES.shot.max >= 200 and RANGES.shot.max <= 300, "shots carry about 250 studs")
check(RANGES.blast.max >= 350 and RANGES.blast.max > RANGES.shot.max, "blasts carry furthest, about 400")
check(AudioConfig.ROLL_OFF == Enum.RollOffMode.InverseTapered or AudioConfig.ROLL_OFF == Enum.RollOffMode.Inverse, "an inverse roll-off")
for id, weapon in WeaponConfig.weapons do
	local mix = MIX[weapon.fireSound]
	check(mix.range ~= nil, `the {id}'s shots can be heard from where they're fired`)
	check(mix.pitch ~= nil and mix.pitch.Max > mix.pitch.Min, `and they vary in pitch`)
end
for _, name in { "explosion", "barrel", "splat", "vent", "pulse", "dash", "emote", "lobber" } do
	check(MIX[name].range ~= nil, `{name} can be heard from where it happens`)
end
for _, name in { "dash", "splat" } do
	check(MIX[name].pitch ~= nil and MIX[name].pitch.Max > MIX[name].pitch.Min, `{name} varies in pitch`)
end
for _, name in { "inflate", "critical", "alpha", "purchase", "coins", "levelUp", "hit" } do
	check(MIX[name].range == nil, `{name} is only ever flat`)
end
check(AudioConfig.VOICES >= 4 and AudioConfig.VOICES <= 32, "a small pool of voices")
check(AudioConfig.PER_SOUND >= 1 and AudioConfig.PER_SOUND < AudioConfig.VOICES and AudioConfig.VOICE_SECONDS > 0, "and a share for each sound")

local client = game.StarterPlayer.StarterPlayerScripts.Client
local Audio = require(client.Audio)
local Settings = require(client.Settings)

-- Flat.
local purchase = Audio.play("purchase")
check(purchase ~= nil and purchase.Parent == SoundService and purchase.Playing, "a flat sound plays from SoundService")
check(purchase.SoundId == AudioConfig.purchase, "with its own ID")
check(close(purchase.Volume, MIX.purchase.volume) and purchase.PlaybackSpeed == 1, "at its own volume, no pitch wobble")
local speeds = {}
for _ = 1, 12 do
	local sound = Audio.play("blaster")
	check(sound == Audio.flat.blaster, "one flat Sound per name, reused")
	check(sound.PlaybackSpeed >= MIX.blaster.pitch.Min and sound.PlaybackSpeed <= MIX.blaster.pitch.Max, "a pitch in its range")
	speeds[sound.PlaybackSpeed] = true
end
local distinct = 0
for _ in speeds do
	distinct += 1
end
check(distinct > 1, "and not the same one every time")
Settings.volume = 0.5
check(close(Audio.play("purchase").Volume, MIX.purchase.volume * 0.5), "Settings.volume scales it")
Settings.volume = 0
check(Audio.play("purchase") == nil and Audio.play("explosion", Vector3.new(5, 0, 0)) == nil, "volume 0: nothing plays")
Settings.volume = 1
Settings.sound = false
check(Audio.play("hit") == nil and Audio.flat.hit == nil and Audio.play("splat", Vector3.new(5, 0, 0)) == nil, "sound off: nothing plays, flat or in the world")
Settings.sound = true
check(#Audio.voices == 0, "and no voice was taken")
check(Audio.play("nope") == nil and Audio.play("nope", Vector3.zero) == nil, "a name with no sound is silent")

-- In the world (Roblox hears from the camera).
local camera = workspace.CurrentCamera
camera.CFrame = CFrame.new(0, 10, 0)
local at = Vector3.new(60, 10, 0)
local boom = Audio.play("explosion", at)
check(boom ~= nil and boom.Playing and boom:IsDescendantOf(workspace) and not boom:IsDescendantOf(SoundService), "a sound in the world plays in the workspace")
local voice = boom.Parent
check(voice:IsA("Attachment") and near(voice.WorldPosition, at), "from where it happened")
check(boom.SoundId == AudioConfig.explosion and boom.RollOffMode == AudioConfig.ROLL_OFF, "its own ID, with the roll-off")
check(boom.RollOffMinDistance == RANGES.blast.min and boom.RollOffMaxDistance == RANGES.blast.max, "over a blast's range")
check(close(boom.Volume, MIX.explosion.volume) and boom.PlaybackSpeed >= MIX.explosion.pitch.Min and boom.PlaybackSpeed <= MIX.explosion.pitch.Max, "at its volume and a pitch in its range")
Settings.volume = 0.5
local shot = Audio.play("spritzer", Vector3.new(0, 10, 100))
Settings.volume = 1
check(shot ~= nil and shot.Parent ~= voice and shot.RollOffMaxDistance == RANGES.shot.max, "a shot: another voice, a shot's range")
check(close(shot.Volume, MIX.spritzer.volume * 0.5), "Settings.volume scales sounds in the world too")
local voices = #Audio.voices
check(Audio.play("dash", Vector3.new(0, 10, RANGES.near.max + 20)) == nil and #Audio.voices == voices, "too far away to hear: not played, no voice taken")
check(Audio.play("barrel", Vector3.new(0, 10, RANGES.blast.max - 20)) ~= nil, "a barrel that far away is still heard")

-- The pool.
local function busy(name: string?): number
	local n = 0
	for _, v in Audio.voices do
		if os.clock() < v.busyUntil and (name == nil or v.name == name) then
			n += 1
		end
	end
	return n
end
task.wait(AudioConfig.VOICE_SECONDS + 0.1)
check(busy() == 0, "voices come free in time, even when no end is heard")
for i = 1, 40 do
	Audio.play("spritzer", Vector3.new(i, 10, 0))
end
check(busy("spritzer") == AudioConfig.PER_SOUND and busy() == AudioConfig.PER_SOUND, "a spray of one sound holds only PER_SOUND voices")
local names = { "blaster", "thunderclapper", "explosion", "splat", "vent", "pulse", "lobber", "emote", "dash", "barrel" }
for round = 1, 10 do
	for _, name in names do
		Audio.play(name, Vector3.new(round, 10, 0))
	end
end
check(#Audio.voices == AudioConfig.VOICES and busy() == AudioConfig.VOICES, "a busy fight fills the pool to VOICES")
local function soundsInWorld(): number
	local n = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("Sound") then
			n += 1
		end
	end
	return n
end
check(soundsInWorld() == AudioConfig.VOICES, "and never makes more Sounds than that")
for _, v in Audio.voices do
	check(busy(v.name) <= AudioConfig.PER_SOUND, `{v.name}: no more than its share`)
end
-- All busy, in order: the oldest goes first.
task.wait(AudioConfig.VOICE_SECONDS + 0.1)
local kinds = math.ceil(AudioConfig.VOICES / AudioConfig.PER_SOUND)
local first: Sound? = nil
for i = 1, AudioConfig.VOICES do
	local sound = Audio.play(names[(i - 1) % kinds + 1], Vector3.new(i, 10, 0))
	first = first or sound
	task.wait(0.01)
end
check(busy() == AudioConfig.VOICES, "every voice busy")
local stolen = Audio.play(names[kinds + 1], Vector3.new(0, 10, 9))
check(stolen ~= nil and stolen == first, "a new sound takes the oldest voice")
local ended
for _, v in Audio.voices do
	if v.sound ~= stolen then
		ended = v
		break
	end
end
ended.sound.Ended:Fire()
check(ended.busyUntil == 0, "a voice is free once its sound ends")
check(Audio.play("vent", Vector3.new(0, 10, 5)) == ended.sound and #Audio.voices == AudioConfig.VOICES, "and it's the next one used")
local anchor = (ended.attachment.Parent :: Instance)
anchor:Destroy()
local again = Audio.play("splat", Vector3.new(0, 10, 0))
check(again ~= nil and again:IsDescendantOf(workspace) and #Audio.voices == 1, "its anchor removed, the pool starts again")

-- The game.
Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring((scriptInstance :: any).Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local CombatService = require(server.Services.CombatService)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(client.ClientBootstrap)
local Controllers = client.Controllers
local CombatUI = require(Controllers.CombatController)
local ada = Instance.new("Player")
ada.Name = "Ada"
ada.UserId = 2
ada.Parent = Players
task.wait(0.05)
Lifecycle.requestPlay(me, nil)
Lifecycle.requestPlay(ada, nil)
task.wait(0.5)
check(me.Character ~= nil and ada.Character ~= nil, "both of us in the match")
CombatService.setWeapon(ada, "Spritzer")

-- What the controllers ask Audio to play.
type Heard = { name: string, at: Vector3?, sound: Sound? }
local heard: { Heard } = {}
local play = Audio.play
Audio.play = function(name: string, position: Vector3?, options: Audio.Options?): Sound?
	local sound = play(name, position, options)
	table.insert(heard, { name = name, at = position, sound = sound })
	return sound
end
local function listen(fn: () -> ()): { Heard }
	table.clear(heard)
	fn()
	return table.clone(heard)
end
local CombatEvent = ReplicatedStorage.Remotes.CombatEvent
local function event(payload: { [string]: any }): { Heard }
	return listen(function()
		CombatEvent.OnClientEvent:Fire(payload)
	end)
end
local eye = Vector3.new(0, 10, 0)
camera.CFrame = CFrame.new(eye)
local function inWorld(got: Heard, name: string, position: Vector3, kind: string): boolean
	local sound = got.sound
	return got.name == name
		and near(got.at, position)
		and sound ~= nil
		and sound:IsDescendantOf(workspace)
		and near((sound.Parent :: Attachment).WorldPosition, position)
		and sound.RollOffMaxDistance == RANGES[kind].max
end
local function flat(got: Heard, name: string): boolean
	return got.name == name and got.at == nil and got.sound ~= nil and got.sound.Parent == SoundService
end

-- Shots.
local from = eye + Vector3.new(40, 0, 0)
local got = event({ kind = "shot", shooter = ada.UserId, from = from, to = from + Vector3.new(0, 0, 30) })
check(#got == 1 and inWorld(got[1], "spritzer", from, "shot"), "another player's shot: their gun's sound, from where they fired")
got = event({ kind = "shot", shooter = 999, from = from, to = from + Vector3.new(0, 0, 30) })
check(#got == 1 and inWorld(got[1], WeaponConfig.weapons[WeaponConfig.default].fireSound, from, "shot"), "a shooter who's gone: the default gun's")
got = event({ kind = "shot", shooter = me.UserId, from = from, to = from + Vector3.new(0, 0, 30) })
check(#got == 0, "my own shot isn't heard again when the server announces it")
me.Character:PivotTo(CFrame.new(0, 3, -30 * MapConfig.BrainrotBattlefield.scale))
got = listen(function()
	check(CombatUI.fire(), "I fire")
end)
local mine = WeaponConfig.weapons[me:GetAttribute("Weapon") :: any] or WeaponConfig.weapons[WeaponConfig.default]
check(#got == 1 and flat(got[1], mine.fireSound), "my own shot: flat")
got = event({ kind = "hit", victim = ada.UserId, gas = 20, headshot = false, blocked = false })
check(#got == 1 and flat(got[1], "hit"), "my hit: flat")
check(#event({ kind = "hit", victim = ada.UserId, gas = 20, headshot = false, blocked = true }) == 0, "a blocked hit: no sound")

-- Blasts.
local where = eye + Vector3.new(0, 0, 120)
got = event({ kind = "explosion", victim = ada.UserId, position = where })
check(#got == 1 and inWorld(got[1], "explosion", where, "blast"), "an explosion: where it went off, over a blast's range")
got = event({ kind = "barrel", position = where, radius = 12 })
check(#got == 1 and inWorld(got[1], "barrel", where, "blast"), "a barrel: the same")

-- Others' dashes, throws and abilities.
local spot = eye + Vector3.new(-30, 0, 20)
got = event({ kind = "dash", player = ada.UserId, from = spot, direction = Vector3.new(1, 0, 0) })
check(#got == 1 and inWorld(got[1], "dash", spot, "near"), "another player's Fart Dash: from where they dashed")
check(#event({ kind = "dash", player = me.UserId, from = spot, direction = Vector3.new(1, 0, 0) }) == 0, "my own dash isn't echoed")
local lands = spot + Vector3.new(30, -5, 0)
local path = { spot, spot + Vector3.new(15, 10, 0), lands }
got = listen(function()
	CombatEvent.OnClientEvent:Fire({ kind = "lob", shooter = ada.UserId, from = spot, to = lands, path = path, flight = 0.5 })
	task.wait(0.6)
end)
check(#got == 2 and inWorld(got[1], "lobber", spot, "shot"), "another player's throw: from the thrower")
check(inWorld(got[2], "splat", lands, "area"), "and the splat where it lands")
got = listen(function()
	CombatEvent.OnClientEvent:Fire({ kind = "lob", shooter = me.UserId, from = spot, to = lands, path = path, flight = 0.5 })
	task.wait(0.6)
end)
check(#got == 1 and inWorld(got[1], "splat", lands, "area"), "my own throw isn't echoed (it played as I threw), but its splat is where it lands")
got = event({ kind = "ability", player = ada.UserId, ability = "RecoveryBurst", position = spot })
check(#got == 1 and inWorld(got[1], "vent", spot, "area"), "Recovery Burst: from where it vented")
got = event({ kind = "ability", player = ada.UserId, ability = "GasPulse", position = spot })
check(#got == 1 and inWorld(got[1], "pulse", spot, "area"), "Gas Pulse: from where it pulsed")

-- Emotes.
local head = ada.Character:FindFirstChild("Head") :: BasePart
check(head ~= nil, "Ada has a head")
camera.CFrame = CFrame.new(head.Position + Vector3.new(0, 0, 20))
got = event({ kind = "emote", player = ada.UserId, emote = "Toot" })
check(#got == 1 and inWorld(got[1], "emote", head.Position, "near"), "another player's emote: from their head, its own sound only (not Recovery Burst's vent)")
got = event({ kind = "emote", player = me.UserId, emote = "Toot" })
check(#got == 1 and flat(got[1], "emote"), "my own emote: flat")
camera.CFrame = CFrame.new(eye)

-- Announcements and my own warnings.
got = event({ kind = "alpha", player = ada.UserId, text = "BRO IS THE ALPHA FART!" })
check(#got == 1 and flat(got[1], "alpha"), "the alpha call: flat")
got = listen(function()
	me.Character:SetAttribute("GasStage", 1)
	CombatUI.render()
	me.Character:SetAttribute("GasStage", 3)
	CombatUI.render()
end)
check(#got == 2 and flat(got[1], "inflate") and flat(got[2], "critical"), "my own gas warnings: flat")
me.Character:SetAttribute("GasStage", 0)
CombatUI.render()

-- Sound off in Settings: asked for, but nothing plays.
Settings.sound = false
got = event({ kind = "explosion", victim = ada.UserId, position = where })
check(#got == 1 and got[1].sound == nil, "sound off: an explosion is silent")
Settings.sound = true

-- The screens' sounds never carry a position.
for _, name in { "LockerController", "RewardsController", "ProgressController" } do
	local calls = 0
	for args in string.gmatch((Controllers[name] :: any).Source, "Audio%.play(%b())") do
		calls += 1
		check(string.find(args, ",", 1, true) == nil, `{name}: its sounds stay flat`)
	end
	check(calls > 0, `{name} plays its sounds`)
end
check(#Audio.voices <= AudioConfig.VOICES and soundsInWorld() <= AudioConfig.VOICES, "after all that, still no more than VOICES in the world")
Audio.play = play

return { status = "PASS", checks = checks }
