-- The hotbar, under the gas and dash bars: your weapons in slots 1-4
-- (press the number or click), the one in your hands lifted and outlined,
-- and Q with your ability and its cooldown. Picking a weapon asks the
-- server to equip it: off the battlefield or on a fresh spawn it's in your
-- hands at once, mid-fight it's marked NEXT and swaps on your respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local WeaponView = require(Client.WeaponView)
local ArtAssets = require(Shared.Config.ArtAssets)
local InputController = require(script.Parent.InputController)
local HUDController = require(script.Parent.HUDController)
local LockerController = require(script.Parent.LockerController)

local C = UIConfig.colors
local SLOT = 64
local SLOT_COLOR = Color3.fromRGB(34, 30, 46)
local SHORT_NAMES = {
	GasBlaster = "BLASTER",
	Spritzer = "SPRITZER",
	Thunderclapper = "CLAPPER",
	StinkLobber = "LOBBER",
}

local HotbarController = {}

HotbarController.parts = {} :: { [string]: any }
-- The weapon id in each slot (owned weapons, in shop order).
HotbarController.slotWeapons = {} :: { string }

local player = Players.LocalPlayer
local started = false

-- A little gun drawn in the weapon's colour.
-- The weapon's picture in a slot: its icon rendered in Blender once
-- uploaded (ArtAssets), until then the model itself in a ViewportFrame.
local function gunIcon(parent: Instance, weaponId: string)
	local image = ArtAssets.icon(weaponId)
	if image then
		local label = UI.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -4),
			Size = UDim2.new(1, -8, 1, -18),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			Parent = parent,
		})
		label:SetAttribute("Weapon", weaponId)
		return
	end
	WeaponView.new(weaponId, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -4),
		Size = UDim2.new(1, -6, 1, -16),
		Parent = parent,
	})
end

local function slotFrame(parent: Instance, order: number, key: string): Frame
	local slot = UI.new("TextButton", {
		Name = `Slot{order}`,
		LayoutOrder = order,
		Size = UDim2.new(0, SLOT, 0, SLOT),
		BackgroundColor3 = SLOT_COLOR,
		AutoButtonColor = true,
		Text = "",
		Parent = parent,
	}, { UI.corner(10), UI.stroke(C.stroke, 3) })
	UI.label(key, 14, {
		Name = "Key",
		Position = UDim2.new(0, 5, 0, 2),
		Size = UDim2.new(0, 16, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = slot,
	})
	return slot
end

local function build()
	local p = HotbarController.parts
	local screen = UI.screen("Hotbar", 4)
	p.screen = screen
	local bar = UI.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -32),
		Size = UDim2.new(0, 4 * (SLOT + 6) + 18 + SLOT, 0, SLOT + 8),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, { UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	p.bar = bar
	p.slots = {}
	for i = 1, 4 do
		local slot = slotFrame(bar, i, tostring(i))
		p.slots[i] = slot
		UI.onClick(slot, function()
			HotbarController.pick(i)
		end)
	end
	UI.new("Frame", { Name = "Gap", LayoutOrder = 5, Size = UDim2.new(0, 12, 0, 1), BackgroundTransparency = 1, Parent = bar })
	local abilitySlot = slotFrame(bar, 6, "Q")
	p.abilitySlot = abilitySlot
	p.abilityShade = UI.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = abilitySlot,
	}, { UI.corner(10) })
	p.ability = UI.label("", 16, {
		Name = "Time",
		Position = UDim2.new(0, 0, 0, 16),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 3,
		Parent = abilitySlot,
	})
	p.abilityName = UI.label("", 10, {
		Name = "Name",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, -3),
		Size = UDim2.new(1, -4, 0, 12),
		Font = UIConfig.bodyFont,
		TextScaled = true,
		ZIndex = 3,
		Parent = abilitySlot,
	})
end

-- Fills the weapon slots from the profile.
local function renderSlots()
	local p = HotbarController.parts
	local profile = LockerController.profile
	local owned = if type(profile) == "table" and type(profile.ownedWeapons) == "table" then profile.ownedWeapons else { WeaponConfig.default }
	local held = player:GetAttribute("Weapon")
	local equipped = if type(profile) == "table" then profile.equippedWeapon else held
	table.clear(HotbarController.slotWeapons)
	for _, id in WeaponConfig.order do
		if table.find(owned, id) and #HotbarController.slotWeapons < 4 then
			table.insert(HotbarController.slotWeapons, id)
		end
	end
	for i, slot in p.slots do
		local id = HotbarController.slotWeapons[i]
		for _, child in slot:GetChildren() do
			-- The 3D icon stays while the slot holds the same weapon.
			if (child.Name == "Icon" and child:GetAttribute("Weapon") ~= id) or child.Name == "Name" or child.Name == "Next" then
				child:Destroy()
			end
		end
		local weapon = id and WeaponConfig.weapons[id]
		slot:SetAttribute("Weapon", id)
		local inHand = id ~= nil and id == held
		slot.BackgroundColor3 = if inHand then Color3.fromRGB(70, 64, 92) else SLOT_COLOR
		slot.Border.Color = if inHand then C.text else C.stroke
		if weapon then
			if not slot:FindFirstChild("Icon") then
				gunIcon(slot, id)
			end
			UI.label(SHORT_NAMES[id] or string.upper(weapon.displayName), 10, {
				Name = "Name",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 2, 1, -3),
				Size = UDim2.new(1, -4, 0, 12),
				Font = UIConfig.bodyFont,
				TextScaled = true,
				Parent = slot,
			})
			if id == equipped and not inHand then
				UI.label("NEXT", 10, {
					Name = "Next",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -4, 0, 3),
					Size = UDim2.new(0, 30, 0, 12),
					TextColor3 = C.accent,
					Parent = slot,
				})
			end
		end
	end
end
HotbarController.renderSlots = renderSlots

-- The Q slot, every frame.
local function renderAbility()
	local p = HotbarController.parts
	p.bar.Visible = ClientState.isActive() and not InputController.menuOpen
	local id = player:GetAttribute("Ability")
	local ability = type(id) == "string" and AbilityConfig[id]
	if not ability then
		p.ability.Text = "—"
		p.abilityName.Text = "NO ABILITY"
		p.abilityShade.Size = UDim2.new(1, 0, 0, 0)
		return
	end
	p.abilityName.Text = string.upper(ability.displayName)
	local readyAt = player:GetAttribute("AbilityReadyAt")
	local left = if type(readyAt) == "number" then readyAt - workspace:GetServerTimeNow() else 0
	p.ability.Text = if left > 0 then `{math.ceil(left)}s` else "READY"
	p.ability.TextColor3 = if left > 0 then C.text else C.accent
	p.abilityShade.Size = UDim2.new(1, 0, math.clamp(left / ability.cooldownSeconds, 0, 1), 0)
end
HotbarController.renderAbility = renderAbility

-- Slot `index`: equip that weapon (nothing to do if it's already in hand).
function HotbarController.pick(index: number): boolean
	local id = HotbarController.slotWeapons[index]
	if not id or not ClientState.isActive() then
		return false
	end
	local profile = LockerController.profile
	if id == player:GetAttribute("Weapon") and (type(profile) ~= "table" or profile.equippedWeapon == id) then
		return false
	end
	LockerController.request("equip", "weapon", id)
	return true
end

function HotbarController.start()
	if started then
		return
	end
	started = true
	build()
	renderSlots()
	renderAbility()
	LockerController.ProfileChanged:Connect(renderSlots)
	player:GetAttributeChangedSignal("Weapon"):Connect(renderSlots)
	InputController.SlotPressed:Connect(HotbarController.pick)
	-- What the server said about a hotbar pick, when the locker isn't open.
	LockerController.Answered:Connect(function(answer, action, kind)
		if action == "equip" and kind == "weapon" and not LockerController.isOpen then
			HUDController.toast(tostring(answer.message), 2.5)
		end
	end)
	RunService.RenderStepped:Connect(renderAbility)
end

return HotbarController
