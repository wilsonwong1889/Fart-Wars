-- Roblox asset IDs for the Blender art once it's uploaded (art/README.md):
-- the hotbar icons (art/export/icons) and the particle textures
-- (art/export/effects). Empty until then: the hotbar shows the weapon's 3D
-- model instead of an icon, and particles use Roblox's built-in textures.
-- The weapon meshes themselves aren't IDs: they're imported into
-- ReplicatedStorage.Assets.Weapons (WeaponModel finds them there).
local ArtAssets = {}

ArtAssets.icons = table.freeze({
	GasBlaster = "",
	Spritzer = "",
	Thunderclapper = "",
	StinkLobber = "",
})

ArtAssets.effects = table.freeze({
	puff = "",
	cloud = "",
	spark = "",
	ring = "",
	droplet = "",
})

-- Roblox's own textures, until the Blender ones are uploaded.
ArtAssets.fallback = table.freeze({
	puff = "rbxasset://textures/particles/smoke_main.dds",
	cloud = "rbxasset://textures/particles/smoke_main.dds",
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	ring = "rbxasset://textures/particles/sparkles_main.dds",
	droplet = "rbxasset://textures/particles/smoke_main.dds",
})

local function id(value: string): string
	if value == "" then
		return ""
	end
	return if string.find(value, "://", 1, true) then value else `rbxassetid://{value}`
end

-- The particle texture `name`: the uploaded one, or Roblox's stand-in.
function ArtAssets.effect(name: string): string
	local uploaded = ArtAssets.effects[name]
	if uploaded and uploaded ~= "" then
		return id(uploaded)
	end
	return ArtAssets.fallback[name] or ArtAssets.fallback.puff
end

-- A weapon's hotbar icon, or nil until it's uploaded.
function ArtAssets.icon(weaponId: string): string?
	local uploaded = ArtAssets.icons[weaponId]
	return if uploaded and uploaded ~= "" then id(uploaded) else nil
end

return table.freeze(ArtAssets)
