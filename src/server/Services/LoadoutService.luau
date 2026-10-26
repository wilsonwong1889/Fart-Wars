-- Loadouts: the weapon, Q ability and tracer cosmetic a player has
-- equipped, saved in their profile. Only what they own can be equipped
-- (anything else falls back to the default, as a damaged save does on
-- load). A change made while fighting waits for the next respawn, so
-- nobody swaps stats mid-combat; one made from the home screen or while
-- dead applies at once. Cosmetics change nothing in combat and apply at
-- once. Each spawn applies the saved loadout: the weapon (and its
-- walking speed), the ability, the "Tracer" attribute.
-- The client's screens get a view of the profile:
--   ProfileUpdate { ownedWeapons, equippedWeapon, unlockedAbilities,
--     equippedAbility?, ownedCosmetics, equippedCosmetic?, badges,
--     mastery = { [weapon] = { eliminations, claimed } }, stats, pending,
--     saving }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local States = require(Shared.States)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local DataService = require(script.Parent.DataService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local CombatService = require(script.Parent.CombatService)
local AbilityService = require(script.Parent.AbilityService)
local EconomyService = require(script.Parent.EconomyService)

type Data = DataService.Data

local LoadoutService = {}

-- Players whose saved loadout differs from what they're holding.
local pending: { [Player]: boolean } = {}
local started = false

local function profileUpdate(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProfileUpdate") :: RemoteEvent
end

-- What the saved loadout resolves to, owned items only.
function LoadoutService.resolve(data: Data): (string, string?, string?)
	local weapon = data.EquippedWeapon
	if not (WeaponConfig.weapons[weapon] and table.find(data.OwnedWeapons, weapon)) then
		weapon = WeaponConfig.default
	end
	local ability = data.EquippedAbility
	if ability and not (AbilityConfig[ability] and table.find(data.UnlockedAbilities, ability)) then
		ability = nil
	end
	local cosmetic = data.EquippedCosmetic
	if cosmetic and not (ProgressionConfig.cosmetics[cosmetic] and table.find(data.OwnedCosmetics, cosmetic)) then
		cosmetic = nil
	end
	return weapon, ability, cosmetic
end

local function applyCosmetic(player: Player, data: Data)
	local _, _, cosmetic = LoadoutService.resolve(data)
	player:SetAttribute("Tracer", cosmetic)
end

-- Puts the saved loadout in the player's hands (a spawn, or out of combat).
function LoadoutService.apply(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local weapon, ability = LoadoutService.resolve(profile.data)
	CombatService.setWeapon(player, weapon)
	AbilityService.setAbility(player, ability)
	applyCosmetic(player, profile.data)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = WeaponConfig.weapons[weapon].walkSpeed
	end
	pending[player] = nil
	player:SetAttribute("LoadoutPending", nil)
end

-- Whether a change now would land mid-fight (so it waits for a respawn).
local function inCombat(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE and humanoid ~= nil and humanoid.Health > 0
end

-- Mid-fight: the saved loadout waits for the next spawn, unless it's what
-- they're already holding. Returns "now" or "respawn".
local function waitForRespawn(player: Player, data: Data): string
	local weapon, ability = LoadoutService.resolve(data)
	if CombatService.weaponOf(player).id == weapon and AbilityService.abilityOf(player) == ability then
		pending[player] = nil
		player:SetAttribute("LoadoutPending", nil)
		return "now"
	end
	pending[player] = true
	player:SetAttribute("LoadoutPending", true)
	return "respawn"
end

-- The profile, as the client's screens show it.
function LoadoutService.view(player: Player): { [string]: any }?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local data = profile.data
	local weapon, ability, cosmetic = LoadoutService.resolve(data)
	local mastery = {}
	for id, entry in data.WeaponMastery do
		mastery[id] = { eliminations = entry.Eliminations, claimed = table.clone(entry.Claimed) }
	end
	return {
		ownedWeapons = table.clone(data.OwnedWeapons),
		equippedWeapon = weapon,
		unlockedAbilities = table.clone(data.UnlockedAbilities),
		equippedAbility = ability,
		ownedCosmetics = table.clone(data.OwnedCosmetics),
		equippedCosmetic = cosmetic,
		badges = table.clone(data.Badges),
		mastery = mastery,
		stats = {
			eliminations = data.TotalEliminations,
			deaths = data.TotalDeaths,
			bestStreak = data.BestStreak,
			playtime = data.TotalPlaytime,
			lifetimeXP = data.LifetimeXP,
		},
		pending = pending[player] == true,
		saving = not profile.temporary,
	}
end

function LoadoutService.push(player: Player)
	local view = LoadoutService.view(player)
	if view and player.Parent == Players then
		profileUpdate():FireClient(player, view)
	end
end

-- Equips `id` (a weapon, ability or cosmetic) if the player owns it.
-- Returns (ok, why): why is "now", "respawn" (it waits for the next
-- spawn), or the reason it was refused.
function LoadoutService.equip(player: Player, kind: string, id: string?): (boolean, string)
	local profile = DataService.get(player)
	if not profile then
		return false, "loading"
	end
	local data = profile.data
	if kind == "weapon" then
		if not (id and WeaponConfig.weapons[id] and table.find(data.OwnedWeapons, id)) then
			return false, "notOwned"
		end
	elseif kind == "ability" then
		if id ~= nil and not (AbilityConfig[id] and table.find(data.UnlockedAbilities, id)) then
			return false, "notOwned"
		end
	elseif kind == "cosmetic" then
		if id ~= nil and not (ProgressionConfig.cosmetics[id] and table.find(data.OwnedCosmetics, id)) then
			return false, "notOwned"
		end
	else
		return false, "badPayload"
	end
	DataService.update(player, function(d)
		if kind == "weapon" then
			d.EquippedWeapon = id :: string
		elseif kind == "ability" then
			d.EquippedAbility = id
		else
			d.EquippedCosmetic = id
		end
	end)
	Telemetry.count(`Loadout.equip.{kind}`)
	local why = "now"
	if kind == "cosmetic" then
		applyCosmetic(player, data)
	elseif inCombat(player) then
		why = waitForRespawn(player, data)
	else
		LoadoutService.apply(player)
	end
	LoadoutService.push(player)
	return true, why
end

-- Test-only: gives the player `id` (a weapon, ability or cosmetic, saved
-- for real) and puts it in their hands now, even mid-fight.
function LoadoutService.testGive(player: Player, kind: string, id: string): boolean
	if not GameConfig.TEST_CONTROLS.ENABLED or not DataService.isLoaded(player) then
		return false
	end
	local known = (kind == "weapon" and WeaponConfig.weapons[id])
		or (kind == "ability" and AbilityConfig[id])
		or (kind == "cosmetic" and ProgressionConfig.cosmetics[id])
	if not known then
		return false
	end
	DataService.update(player, function(d)
		local list = if kind == "weapon" then d.OwnedWeapons elseif kind == "ability" then d.UnlockedAbilities else d.OwnedCosmetics
		if not table.find(list, id) then
			table.insert(list, id)
		end
	end)
	LoadoutService.equip(player, kind, id)
	LoadoutService.apply(player)
	LoadoutService.push(player)
	return true
end

function LoadoutService.start()
	if started then
		return
	end
	started = true
	DataService.Loaded:Connect(function(player, profile)
		if inCombat(player) then
			waitForRespawn(player, profile.data)
			applyCosmetic(player, profile.data)
		else
			LoadoutService.apply(player)
		end
		LoadoutService.push(player)
	end)
	PlayerLifecycleService.Spawned:Connect(function(player)
		LoadoutService.apply(player)
	end)
	EconomyService.Changed:Connect(LoadoutService.push)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			LoadoutService.apply(player)
			LoadoutService.push(player)
		end
	end
end

return LoadoutService
