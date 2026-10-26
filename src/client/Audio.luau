-- Plays the game's sounds by AudioConfig name. A name with no asset ID is
-- silent. Volume follows Roblox's own setting, so muting Roblox mutes these;
-- Settings can also turn the game's sound effects off.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.AudioConfig)
local Settings = require(script.Parent.Settings)

local Audio = {}

local sounds: { [string]: Sound } = {}

function Audio.play(name: string)
	if not Settings.sound then
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
	sound.TimePosition = 0
	sound:Play()
end

return Audio
