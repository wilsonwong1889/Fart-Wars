-- The admin code, for testing everything in a real server: typed into the
-- CODES box in Settings, it gives every weapon, Q ability and cosmetic
-- (saved for real), COINS coins, a full bank of free spins, and makes the
-- player an admin for the session (the /fw test commands work for them,
-- live servers included). The code lives only here, on the server, so
-- clients never see it; a few wrong guesses lock the box for the session.
--   ShopRequest:InvokeServer("redeem", code)
-- Turn ENABLED off before any public release.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local RewardsConfig = require(Shared.Config.RewardsConfig)
local Telemetry = require(script.Parent.Telemetry)
local Services = script.Parent.Services
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local LoadoutService = require(Services.LoadoutService)
local RewardsService = require(Services.RewardsService)

local AdminCode = {}

AdminCode.ENABLED = true
-- Compared without case or surrounding spaces.
local CODE = "rematch"
AdminCode.COINS = 50000
-- Wrong guesses before the box stops answering, for the session.
AdminCode.MAX_WRONG = 5

AdminCode.MESSAGES = table.freeze({
	redeemed = "Admin code accepted: every weapon, ability and cosmetic, coins and free spins are yours. /fw commands are on.",
	wrong = "That code didn't work.",
	locked = "Too many wrong codes. Try again next session.",
	loading = "Your progress is still loading.",
	disabled = "Codes are off right now.",
})

local admins: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local wrong: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local grants = 0

function AdminCode.isAdmin(player: Player): boolean
	return AdminCode.ENABLED and admins[player] == true
end

local function addAll(list: { string }, ids: { string })
	for _, id in ids do
		if not table.find(list, id) then
			table.insert(list, id)
		end
	end
end

-- Everything, saved to the profile, and in the player's hands now.
local function giveEverything(player: Player)
	local weapons, abilities, cosmetics = {}, {}, {}
	for id in WeaponConfig.weapons do
		table.insert(weapons, id)
	end
	for id, ability in AbilityConfig do
		if ability.ownership == "unlock" then
			table.insert(abilities, id)
		end
	end
	for id in ProgressionConfig.cosmetics do
		table.insert(cosmetics, id)
	end
	DataService.update(player, function(d)
		addAll(d.OwnedWeapons, weapons)
		addAll(d.UnlockedAbilities, abilities)
		addAll(d.OwnedCosmetics, cosmetics)
		d.Spins = math.max(d.Spins, RewardsConfig.MAX_SPINS)
	end)
	-- Coins through the normal grant path, in grants no bigger than allowed.
	local coins = AdminCode.COINS
	while coins > 0 do
		local amount = math.min(coins, ProgressionConfig.MAX_COINS_PER_GRANT)
		grants += 1
		if not EconomyService.grant(player, `admin:{grants}`, "admin", amount, 0) then
			break
		end
		coins -= amount
	end
	LoadoutService.apply(player)
	LoadoutService.push(player)
	RewardsService.publish(player)
	task.spawn(DataService.save, player)
end

-- One code from a client: (ok, reason).
function AdminCode.redeem(player: Player, code: unknown): (boolean, string)
	if not AdminCode.ENABLED then
		return false, "disabled"
	end
	if (wrong[player] or 0) >= AdminCode.MAX_WRONG then
		return false, "locked"
	end
	local typed = if type(code) == "string" and #code <= 40 then string.lower(string.gsub(code, "^%s*(.-)%s*$", "%1")) else ""
	if typed ~= CODE then
		wrong[player] = (wrong[player] or 0) + 1
		Telemetry.count("Admin.wrongCodes")
		return false, if wrong[player] >= AdminCode.MAX_WRONG then "locked" else "wrong"
	end
	if not DataService.isLoaded(player) then
		return false, "loading"
	end
	admins[player] = true
	giveEverything(player)
	Telemetry.count("Admin.redeemed")
	Telemetry.log("Admin", "redeemed", { player = player })
	return true, "redeemed"
end

Players.PlayerRemoving:Connect(function(player)
	admins[player] = nil
	wrong[player] = nil
end)

return AdminCode
