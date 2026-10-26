-- Prestige (PrestigeConfig; masterplan 6.2), behind FeatureFlags.PRESTIGE.
-- A player at the required level, on the home screen, asks for a preview
-- first: the exact numbers that will reset and what stays, and a
-- confirmation token. Only a confirm with that token (within
-- CONFIRM_SECONDS) resets anything, and it's saved before it's confirmed:
-- if the save fails, everything is put back. Nothing a player bought with
-- Robux is taken: unspent store coins are kept.
--   PrestigeRequest (RemoteFunction): "preview" -> { ok, reason, message,
--   preview?, token? }; "confirm", token -> { ok, reason, message, rank? }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local PrestigeConfig = require(Shared.Config.PrestigeConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local RateLimit = require(Server.RateLimit)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LoadoutService = require(script.Parent.LoadoutService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)

local PrestigeService = {}

PrestigeService.MESSAGES = table.freeze({
	off = "Prestige isn't available yet.",
	loading = "Your profile is still loading.",
	notSaving = "Progress isn't saving right now, so you can't prestige.",
	level = `Reach level {PrestigeConfig.REQUIRED_LEVEL} to prestige.`,
	max = "You've reached the highest prestige rank.",
	inMatch = "Leave the match first (spectate or wait on the home screen).",
	preview = "Here's exactly what changes.",
	badToken = "That confirmation has run out. Look at the preview again.",
	saveFailed = "Couldn't save, so nothing changed. Try again in a moment.",
	done = "Prestige complete!",
	tooFast = "One moment...",
	badPayload = "That request didn't make sense.",
})

export type Result = { [string]: any }

local tokens: { [Player]: { token: string, expires: number } } = {}
local override: boolean? = nil

-- Whether prestige is on (the flag, unless a test says otherwise). Clients
-- see it as Workspace's PrestigeOpen attribute.
function PrestigeService.enabled(): boolean
	if override ~= nil then
		return override
	end
	return FeatureFlags.PRESTIGE
end

-- Test seam: prestige on or off whatever the flag says (nil: the flag).
function PrestigeService.testEnable(enabled: boolean?)
	override = enabled
	workspace:SetAttribute("PrestigeOpen", PrestigeService.enabled())
end
local limit = RateLimit.new(0.5)
local started = false

local function result(ok: boolean, reason: string, extra: { [string]: any }?): Result
	local answer: Result = { ok = ok, reason = reason, message = PrestigeService.MESSAGES[reason] or reason }
	if extra then
		for key, value in extra do
			answer[key] = value
		end
	end
	return answer
end

-- Whether the player can prestige now, and why not.
function PrestigeService.eligible(player: Player): (boolean, string)
	if not PrestigeService.enabled() then
		return false, "off"
	end
	local profile = DataService.get(player)
	if not profile then
		return false, "loading"
	elseif profile.temporary or profile.lost then
		return false, "notSaving"
	end
	local data = profile.data
	if data.Prestige >= PrestigeConfig.MAX_RANK then
		return false, "max"
	elseif data.Level < PrestigeConfig.REQUIRED_LEVEL then
		return false, "level"
	elseif PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE then
		return false, "inMatch"
	end
	return true, "ok"
end

-- Coin-bought weapons (they reset), in shop order.
local function boughtWeapons(data: any): { string }
	local list = {}
	for _, id in WeaponConfig.order do
		local weapon = WeaponConfig.weapons[id]
		if weapon.unlock == "shop" and table.find(data.OwnedWeapons, id) then
			table.insert(list, id)
		end
	end
	return list
end

-- Exactly what a prestige would do to this profile.
function PrestigeService.describe(data: any): { [string]: any }
	local rank = data.Prestige + 1
	local reward = PrestigeConfig.ranks[rank]
	local keptCoins = math.min(data.Coins, data.PurchasedCoins)
	return {
		rank = rank,
		resets = {
			level = data.Level,
			xp = data.XP,
			coins = data.Coins,
			keptCoins = keptCoins,
			weapons = boughtWeapons(data),
		},
		keeps = {
			cosmetics = #data.OwnedCosmetics,
			lifetimeXP = data.LifetimeXP,
			eliminations = data.TotalEliminations,
			badges = #data.Badges,
			abilities = #data.UnlockedAbilities,
			passes = #data.PassesGranted,
		},
		rewards = { badge = reward and reward.badge, cosmetic = reward and reward.cosmetic },
	}
end

function PrestigeService.preview(player: Player): Result
	local ok, reason = PrestigeService.eligible(player)
	if not ok then
		return result(false, reason)
	end
	local token = HttpService:GenerateGUID(false)
	tokens[player] = { token = token, expires = os.clock() + PrestigeConfig.CONFIRM_SECONDS }
	local data = (DataService.get(player) :: DataService.Profile).data
	Telemetry.count("Prestige.previews")
	return result(true, "preview", { preview = PrestigeService.describe(data), token = token })
end

function PrestigeService.confirm(player: Player, token: unknown): Result
	local pending = tokens[player]
	tokens[player] = nil
	if not (pending and type(token) == "string" and token == pending.token and os.clock() <= pending.expires) then
		return result(false, "badToken")
	end
	local ok, reason = PrestigeService.eligible(player)
	if not ok then
		return result(false, reason)
	end
	local profile = DataService.get(player) :: DataService.Profile
	local data = profile.data
	local before = {
		Level = data.Level,
		XP = data.XP,
		Coins = data.Coins,
		PurchasedCoins = data.PurchasedCoins,
		OwnedWeapons = table.clone(data.OwnedWeapons),
		EquippedWeapon = data.EquippedWeapon,
		Prestige = data.Prestige,
		LastPrestigeAt = data.LastPrestigeAt,
		Badges = table.clone(data.Badges),
		OwnedCosmetics = table.clone(data.OwnedCosmetics),
	}
	local rank = data.Prestige + 1
	local reward = PrestigeConfig.ranks[rank]
	DataService.update(player, function(d)
		local kept = math.min(d.Coins, d.PurchasedCoins)
		d.Level = 1
		d.XP = 0
		d.Coins = kept
		-- What's kept now is protected; only coins bought later count next time.
		d.PurchasedCoins = 0
		local owned = {}
		for _, id in d.OwnedWeapons do
			local weapon = WeaponConfig.weapons[id]
			if weapon and weapon.unlock ~= "shop" then
				table.insert(owned, id)
			end
		end
		d.OwnedWeapons = owned
		d.EquippedWeapon = WeaponConfig.default
		d.Prestige = rank
		d.LastPrestigeAt = os.time()
		if reward then
			if not table.find(d.Badges, reward.badge) then
				table.insert(d.Badges, reward.badge)
			end
			if reward.cosmetic and not table.find(d.OwnedCosmetics, reward.cosmetic) then
				table.insert(d.OwnedCosmetics, reward.cosmetic)
			end
		end
	end)
	if not DataService.save(player) then
		DataService.update(player, function(d)
			for key, value in before do
				(d :: any)[key] = value
			end
		end)
		Telemetry.count("Prestige.saveFailed")
		EconomyService.publish(player)
		return result(false, "saveFailed")
	end
	Telemetry.count("Prestige.count")
	Telemetry.count(`Prestige.rank.{rank}`)
	Telemetry.log("Prestige", "prestige", { player = player, rank = rank })
	EconomyService.publish(player)
	LoadoutService.apply(player)
	LoadoutService.push(player)
	return result(true, "done", { rank = rank, cosmetic = reward and reward.cosmetic, badge = reward and reward.badge })
end

function PrestigeService.request(player: Player, action: unknown, token: unknown): Result
	if type(action) ~= "string" or (token ~= nil and (type(token) ~= "string" or #(token :: string) > 64)) then
		Telemetry.reject("PrestigeRequest", player, "badPayload")
		return result(false, "badPayload")
	end
	if not limit:allow(player, "request") then
		return result(false, "tooFast")
	end
	if action == "preview" then
		return PrestigeService.preview(player)
	elseif action == "confirm" then
		return PrestigeService.confirm(player, token)
	end
	Telemetry.reject("PrestigeRequest", player, "badPayload")
	return result(false, "badPayload")
end

-- Test seam: the confirmation token's expiry for a player, moved.
function PrestigeService.testExpire(player: Player)
	local pending = tokens[player]
	if pending then
		pending.expires = os.clock() - 1
	end
end

function PrestigeService.start()
	if started then
		return
	end
	started = true
	workspace:SetAttribute("PrestigeOpen", PrestigeService.enabled())
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PrestigeRequest") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, action: unknown, token: unknown)
		Telemetry.count("remote.in.PrestigeRequest")
		local ok, answer = pcall(PrestigeService.request, player, action, token)
		if not ok then
			Telemetry.error("Prestige", answer)
			return result(false, "error")
		end
		return answer
	end
	Players.PlayerRemoving:Connect(function(player)
		tokens[player] = nil
		limit:forget(player)
	end)
end

return PrestigeService
