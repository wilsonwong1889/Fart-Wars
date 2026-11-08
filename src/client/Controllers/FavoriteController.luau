-- Reasons to come back, on the client (FeatureFlags.BADGES). The server
-- decides when (AchievementService); this only shows:
--   ProgressEvent { kind = "favorite" }  Roblox's prompt to favorite the
--     game (once ever, at a calm moment the server picked), with the mouse
--     free while it's up (MouseLock "Favorite") until it's answered or
--     PROMPT_SECONDS pass
--   ProgressEvent { kind = "beta", cosmetic }  a line saying the beta's boom
--     is theirs
-- Roblox shows its own note for each badge it awards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local MouseLock = require(Client.MouseLock)
local Audio = require(Client.Audio)
local ProgressController = require(script.Parent.ProgressController)

local FavoriteController = {}

FavoriteController.PROMPT_SECONDS = 30
FavoriteController.BETA_SECONDS = 8
FavoriteController.BETA_COLOR = Color3.fromRGB(40, 255, 200)
-- Prompts shown this session.
FavoriteController.shown = 0

-- Roblox's favorite prompt for this game, and the signal it fires once it's
-- answered (nil if there isn't one). Test seams.
FavoriteController.prompt = function()
	local AvatarEditorService = game:GetService("AvatarEditorService")
	AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
end
FavoriteController.answered = function(): RBXScriptSignal?
	local ok, signal = pcall(function()
		return (game:GetService("AvatarEditorService") :: any).PromptSetFavoriteCompleted
	end)
	return if ok and typeof(signal) == "RBXScriptSignal" then signal else nil
end

local promptToken = 0
local started = false

-- What the beta's line says.
function FavoriteController.betaText(cosmetic: string?): string
	local entry = cosmetic and ProgressionConfig.cosmetics[cosmetic]
	local name = if entry then entry.name else "beta boom"
	return `🧪 OG BETA TESTER! The {name} is yours forever. Equip it in LOADOUT.`
end

-- Shows Roblox's prompt and frees the mouse until it's answered. Returns
-- whether it went up.
function FavoriteController.showPrompt(): boolean
	promptToken += 1
	local token = promptToken
	local done = false
	local signal = FavoriteController.answered()
	local connection = if signal then signal:Connect(function()
		done = true
	end) else nil
	local ok, err = pcall(FavoriteController.prompt)
	if not ok then
		if connection then
			connection:Disconnect()
		end
		warn(`[FW] couldn't show the favorite prompt: {err}`)
		return false
	end
	FavoriteController.shown += 1
	MouseLock.setFree("Favorite", true)
	task.spawn(function()
		local waited = 0
		while not done and waited < FavoriteController.PROMPT_SECONDS and promptToken == token do
			waited += task.wait(0.25)
		end
		if connection then
			connection:Disconnect()
		end
		if promptToken == token then
			MouseLock.setFree("Favorite", false)
		end
	end)
	return true
end

local function onEvent(event: any)
	if type(event) ~= "table" then
		return
	end
	if event.kind == "favorite" then
		FavoriteController.showPrompt()
	elseif event.kind == "beta" then
		ProgressController.line(FavoriteController.betaText(event.cosmetic), FavoriteController.BETA_COLOR, FavoriteController.BETA_SECONDS, "Beta")
		Audio.play("levelUp")
	end
end

function FavoriteController.start()
	if started or not FeatureFlags.BADGES then
		return
	end
	started = true
	local remote = ClientState.remote("ProgressEvent") :: RemoteEvent
	remote.OnClientEvent:Connect(onEvent)
end

return FavoriteController
