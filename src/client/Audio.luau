-- Plays the game's sounds by AudioConfig name. A name with no asset ID is
-- silent. Volume follows Roblox's own setting, so muting Roblox mutes these;
-- Settings can also turn the game's sound effects off or down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.AudioConfig)
local Settings = require(script.Parent.Settings)

local Audio = {}

local sounds: { [string]: Sound } = {}

-- `options` can pitch a sound (pitch: playback speed, 1 as recorded) and
-- make it louder or quieter (volume: times the usual), as the headshot cue
-- does with the hit sound.
function Audio.play(name: string, options: { pitch: number?, volume: number? }?)
	if not Settings.sound or Settings.volume <= 0 then
		return
	end
	local id = (AudioConfig :: any)[name]
	if type(id) ~= "string" or id == "" then
		return
	end
	local sound = sounds[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Parent = SoundService
		sounds[name] = sound
	end
	sound.Volume = 0.5 * Settings.volume * (options and options.volume or 1)
	sound.PlaybackSpeed = options and options.pitch or 1
	sound.TimePosition = 0
	sound:Play()
end

return Audio
