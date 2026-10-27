-- Plays the game's sounds by AudioConfig name. A name with no asset ID is
-- silent. Volume follows Roblox's own setting, so muting Roblox mutes these;
-- Settings can also turn the game's sound effects off or down.
--   * flat: your own shots, hits and warnings, the screens' sounds and the
--     alpha call sound the same wherever you are (one Sound per name, in
--     SoundService)
--   * in the world: given a position, a sound plays there, so it fades
--     with distance and comes from its side (Roblox hears from the
--     camera). It takes one of a small pool of voices (attachments on one
--     invisible anchor), never more than AudioConfig.VOICES; one too far
--     away to hear isn't played at all
--   * each sound plays at its own volume, and a pitch picked at random in
--     its range, so repeats don't sound identical (AudioConfig.MIX)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.AudioConfig)
local Settings = require(script.Parent.Settings)

-- A pooled voice: what it last played, when, and until when it's busy.
type Voice = { attachment: Attachment, sound: Sound, name: string, startedAt: number, busyUntil: number }

local MIX: { [string]: AudioConfig.Mix } = AudioConfig.MIX
local RANGES: { [string]: AudioConfig.Range } = AudioConfig.RANGES
-- For a name without a mix (the old level for everything).
local DEFAULT_VOLUME = 0.5

local Audio = {}

-- The flat sounds, by name.
Audio.flat = {} :: { [string]: Sound }
-- The voices for sounds in the world, made as they're needed.
Audio.voices = {} :: { Voice }

local anchor: BasePart? = nil
local random = Random.new()

local function idOf(name: string): string?
	local id = (AudioConfig :: any)[name]
	return if type(id) == "string" and id ~= "" then id else nil
end

-- This play's volume and pitch.
local function tune(sound: Sound, name: string)
	local mix = MIX[name]
	sound.Volume = (if mix then mix.volume else DEFAULT_VOLUME) * Settings.volume
	local pitch = mix and mix.pitch
	sound.PlaybackSpeed = if pitch then random:NextNumber(pitch.Min, pitch.Max) else 1
end

-- The invisible anchor the voices hang on (made again, with fresh voices,
-- if something removed it).
local function anchored(): BasePart
	if anchor and anchor.Parent then
		return anchor
	end
	table.clear(Audio.voices)
	local part = Instance.new("Part")
	part.Name = "SoundFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new()
	part.Parent = workspace
	anchor = part
	return part
end

local function newVoice(parent: BasePart): Voice
	local attachment = Instance.new("Attachment")
	attachment.Name = `Voice{#Audio.voices + 1}`
	attachment.Parent = parent
	local sound = Instance.new("Sound")
	sound.Name = "Sound"
	sound.RollOffMode = AudioConfig.ROLL_OFF
	sound.Parent = attachment
	local voice: Voice = { attachment = attachment, sound = sound, name = "", startedAt = -math.huge, busyUntil = 0 }
	sound.Ended:Connect(function()
		voice.busyUntil = 0
	end)
	table.insert(Audio.voices, voice)
	return voice
end

-- The voice for `name`: when PER_SOUND of it are playing already, the
-- oldest of those (a spray of shots cuts itself short, not an explosion);
-- else a free one, a new one while there's room, or the oldest playing.
local function voiceFor(name: string, now: number): Voice
	local parent = anchored()
	local same, oldestSame, free, oldest = 0, nil :: Voice?, nil :: Voice?, nil :: Voice?
	for _, voice in Audio.voices do
		local busy = now < voice.busyUntil
		if busy and voice.name == name then
			same += 1
			if not oldestSame or voice.startedAt < oldestSame.startedAt then
				oldestSame = voice
			end
		end
		-- Free: one whose sound ended before one that only timed out.
		if not busy and (not free or voice.busyUntil < free.busyUntil) then
			free = voice
		end
		if not oldest or voice.startedAt < oldest.startedAt then
			oldest = voice
		end
	end
	if oldestSame and same >= AudioConfig.PER_SOUND then
		return oldestSame
	elseif free then
		return free
	elseif #Audio.voices < AudioConfig.VOICES or not oldest then
		return newVoice(parent)
	end
	return oldest :: Voice
end

local function playAt(name: string, id: string, at: Vector3): Sound?
	local mix = MIX[name]
	local range = RANGES[mix and mix.range or "shot"] or RANGES.shot
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude > range.max then
		return nil
	end
	local now = os.clock()
	local voice = voiceFor(name, now)
	voice.name = name
	voice.startedAt = now
	voice.busyUntil = now + AudioConfig.VOICE_SECONDS
	voice.attachment.WorldPosition = at
	local sound = voice.sound
	if sound.SoundId ~= id then
		sound.SoundId = id
	end
	sound.RollOffMinDistance = range.min
	sound.RollOffMaxDistance = range.max
	tune(sound, name)
	sound.TimePosition = 0
	sound:Play()
	return sound
end

local function playFlat(name: string, id: string): Sound
	local sound = Audio.flat[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Parent = SoundService
		Audio.flat[name] = sound
	end
	tune(sound, name)
	sound.TimePosition = 0
	sound:Play()
	return sound
end

-- Plays `name`: from `at` in the world when given (other players' shots,
-- explosions, abilities...), else flat. Returns the Sound, or nil when it
-- has no ID, sound is off in Settings, or it's too far away to hear.
function Audio.play(name: string, at: Vector3?): Sound?
	if not Settings.sound or Settings.volume <= 0 then
		return nil
	end
	local id = idOf(name)
	if not id then
		return nil
	end
	if at then
		return playAt(name, id, at)
	end
	return playFlat(name, id)
end

return Audio
