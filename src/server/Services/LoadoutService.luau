-- Loadouts: the weapon, Q ability and tracer cosmetic a player has
-- equipped, saved in their profile. Only what they own can be equipped
-- (anything else falls back to the default, as a damaged save does on
-- load). A change made while fighting waits for the next respawn, so
-- nobody swaps stats mid-combat; one made from the home screen, while
-- dead or in the first seconds of a spawn (still protected) applies at
-- once. Cosmetics (a tracer, a Fart Dash trail, an emote for E) change
-- nothing in combat and apply at once. Each spawn applies the saved
-- loadout: the weapon (held in the avatar's hand, with its walking speed),
-- the ability, and the "Tracer", "Trail" and "Emote" attributes.
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
local RateLimit = require(Server.RateLimit)
local DataService = require(script.Parent.DataService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local CombatService = require(script.Parent.CombatService)
local AbilityService = require(script.Parent.AbilityService)
local EconomyService = require(script.Parent.EconomyService)
local ExperimentService = require(script.Parent.ExperimentService)

type Data = DataService.Data

local LoadoutService = {}

-- Players whose saved loadout differs from what they're holding.
local pending: { [Player]: boolean } = {}
local emoteLimiter = RateLimit.new(3)
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
	return weapon, ability, LoadoutService.cosmetic(data, "tracer")
end

local SLOTS = { tracer = "EquippedCosmetic", trail = "EquippedTrail", emote = "EquippedEmote" }

-- The equipped cosmetic of `kind` ("tracer", "trail", "emote"), owned only;
-- the emote falls back to the free one everybody has.
function LoadoutService.cosmetic(data: Data, kind: string): string?
	local id = (data :: any)[SLOTS[kind]]
	local cosmetic = type(id) == "string" and ProgressionConfig.cosmetics[id]
	if cosmetic and cosmetic.kind == kind and ProgressionConfig.ownsCosmetic(data.OwnedCosmetics, id) then
		return id
	end
	return if kind == "emote" then "Toot" else nil
end

local function applyCosmetic(player: Player, data: Data)
	player:SetAttribute("Tracer", LoadoutService.cosmetic(data, "tracer"))
	player:SetAttribute("Trail", LoadoutService.cosmetic(data, "trail"))
	player:SetAttribute("Emote", LoadoutService.cosmetic(data, "emote"))
end

-- The weapon as something to hold: a Tool built from parts in the
-- weapon's colour, barrel along the handle's look direction. Being in the
-- character equips it (Roblox raises the arm to hold it); nothing in it can
-- be hit, touched or collided with.
function LoadoutService.buildTool(weapon: WeaponConfig.Weapon): Tool
	local tool = Instance.new("Tool")
	tool.Name = "HeldWeapon"
	tool.ToolTip = weapon.displayName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool:SetAttribute("Weapon", weapon.id)
	local heavy = weapon.walkSpeed < 16
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.CFrame = offset
		part.Parent = tool
		return part
	end
	local dark = Color3.fromRGB(45, 42, 55)
	local handle = piece("Handle", Vector3.new(0.4, 0.9, 0.5), CFrame.new(), dark)
	local length = if weapon.projectile == "lob" then 1.6 elseif heavy then 2.6 else 2
	local parts = {
		piece("Body", Vector3.new(0.6, 0.6, length), CFrame.new(0, 0.45, -length / 2 + 0.3), weapon.tracerColor),
		piece("Barrel", Vector3.new(0.3, 0.3, 0.9), CFrame.new(0, 0.5, -length + 0.05), dark),
		piece("Tank", Vector3.new(0.5, 0.5, 0.7), CFrame.new(0, 0.95, -length / 2 + 0.4), weapon.tracerColor:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Material.Neon),
	}
	if weapon.projectile == "lob" then
		table.insert(parts, piece("Bomb", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 0.5, -length - 0.2), Color3.fromRGB(120, 160, 50)))
	end
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end
	return tool
end

-- Swaps the tool in the avatar's hands for `weaponId`'s.
local function holdWeapon(player: Player, weaponId: string)
	local character = player.Character
	if not character then
		return
	end
	local current = character:FindFirstChild("HeldWeapon")
	if current and current:GetAttribute("Weapon") == weaponId then
		return
	end
	if current then
		current:Destroy()
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local stray = backpack and backpack:FindFirstChild("HeldWeapon")
	if stray then
		stray:Destroy()
	end
	local tool = LoadoutService.buildTool(WeaponConfig.weapons[weaponId])
	tool.Parent = character
end

-- Puts the saved loadout in the player's hands (a spawn, or out of combat).
function LoadoutService.apply(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local weapon, ability = LoadoutService.resolve(profile.data)
	CombatService.setWeapon(player, weapon)
	holdWeapon(player, weapon)
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
-- (A fresh spawn, still protected, isn't in combat yet.)
local function inCombat(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE
		and humanoid ~= nil
		and humanoid.Health > 0
		and not PlayerLifecycleService.isProtected(player)
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
	-- Shop prices for this player (experiments can change early ones).
	local prices = {}
	for id, entry in WeaponConfig.weapons do
		if entry.unlock == "shop" then
			prices[id] = ExperimentService.weaponPrice(player, entry.price)
		end
	end
	return {
		ownedWeapons = table.clone(data.OwnedWeapons),
		equippedWeapon = weapon,
		unlockedAbilities = table.clone(data.UnlockedAbilities),
		equippedAbility = ability,
		ownedCosmetics = table.clone(data.OwnedCosmetics),
		equippedCosmetic = cosmetic,
		equippedTrail = LoadoutService.cosmetic(data, "trail"),
		equippedEmote = LoadoutService.cosmetic(data, "emote"),
		passes = table.clone(data.PassesGranted),
		badges = table.clone(data.Badges),
		mastery = mastery,
		prices = prices,
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

-- Equips `id` (a weapon, ability or cosmetic) if the player owns it. A
-- cosmetic goes in its kind's slot; kind "tracer", "trail" or "emote" with
-- no id empties that slot. Returns (ok, why): why is "now", "respawn" (it
-- waits for the next spawn), or the reason it was refused.
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
	elseif kind == "cosmetic" or SLOTS[kind] then
		local cosmetic = id and ProgressionConfig.cosmetics[id]
		if id ~= nil and not (cosmetic and ProgressionConfig.ownsCosmetic(data.OwnedCosmetics, id)) then
			return false, "notOwned"
		end
		if cosmetic then
			kind = cosmetic.kind
		elseif kind == "cosmetic" then
			kind = "tracer"
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
			(d :: any)[SLOTS[kind]] = id
		end
	end)
	Telemetry.count(`Loadout.equip.{kind}`)
	local why = "now"
	if SLOTS[kind] then
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

-- E: the player's emote, seen by everyone (cosmetic only, a few seconds
-- apart).
--   CombatEvent { kind = "emote", player, emote }
function LoadoutService.emote(player: Player): boolean
	local profile = DataService.get(player)
	local character = player.Character
	if not (profile and character and PlayerLifecycleService.stateOf(player) == States.Player.ACTIVE) then
		return false
	end
	if not emoteLimiter:allow(player, "emote") then
		Telemetry.reject("Emote", player, "rateLimited")
		return false
	end
	local id = LoadoutService.cosmetic(profile.data, "emote")
	Telemetry.count("Loadout.emotes")
	local combatEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
	combatEvent:FireAllClients({ kind = "emote", player = player.UserId, emote = id })
	return true
end

function LoadoutService.start()
	if started then
		return
	end
	started = true
	local emoteRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Emote") :: RemoteEvent
	emoteRemote.OnServerEvent:Connect(Telemetry.guard("Loadout", function(player)
		LoadoutService.emote(player)
	end))
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
