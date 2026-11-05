-- The loadout: what you take into a match, on its own screen (LOADOUT on
-- the home screen, in the M menu and on the locker's tabs), laid out on a
-- 1280 x 720 stage scaled to fit.
--   left    your weapons in shop order: the hotbar key (1-4) of each one
--           you own, the level or the shop for the rest; under them Fart
--           Dash on SHIFT and your Q ability (pick from the ones you've
--           unlocked; a badge while one is new)
--   middle  the picked weapon turning, what it does, its gas, range and
--           rate against the shop's best, EQUIP (or what's missing: a
--           level, or the shop), and three slots for how your shots, Fart
--           Dash and boom look: pick from what you own
--   right   your emotes around E: pick the one E plays; empty spots go to
--           the daily shop
-- Every button only asks (LockerController.request: ShopRequest); the
-- answer shows on the status line. BACK, pressing PLAY, spectating or going
-- AFK closes it. The mouse is free while it's open (MouseLock "Loadout").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local MouseLock = require(Client.MouseLock)
local Settings = require(Client.Settings)
local WeaponView = require(Client.WeaponView)
local LockerController = require(script.Parent.LockerController)

local C = UIConfig.colors
local STAGE = Vector2.new(1280, 720)
-- The Q abilities, and each one's icon and colour.
local Q_ABILITIES = { "RecoveryBurst", "GasPulse" }
local ABILITY_LOOK = {
	FartDash = { icon = "💨", color = Color3.fromRGB(120, 200, 60) },
	RecoveryBurst = { icon = "🌬️", color = Color3.fromRGB(40, 170, 220) },
	GasPulse = { icon = "🌀", color = Color3.fromRGB(165, 90, 235) },
}
-- The look slots under the weapon, and what each shows with nothing on.
local SLOTS = {
	{ kind = "tracer", label = "TRACER", field = "equippedCosmetic", none = "Default" },
	{ kind = "trail", label = "DASH TRAIL", field = "equippedTrail", none = "None" },
	{ kind = "boom", label = "BOOM", field = "equippedBoom", none = "Default" },
}
local EMOTE_SPOTS = UIConfig.emoteSpots
local SELECTED = Color3.fromRGB(45, 155, 245)
local ROW = Color3.fromRGB(34, 28, 48)
local ROW_LOCKED = Color3.fromRGB(23, 18, 31)
local DIM = Color3.fromRGB(141, 134, 163)

local LoadoutController = {}

LoadoutController.parts = {} :: { [string]: any }
LoadoutController.isOpen = false
-- The weapon shown in the middle (the equipped one until another is
-- picked).
LoadoutController.selected = nil :: string?
-- The picker that's up ("tracer", "trail", "boom" or "ability"), if any.
LoadoutController.picking = nil :: string?

local player = Players.LocalPlayer
local started = false
local turn = 0

local function number(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function profile(): { [string]: any }
	return LockerController.profile or {}
end

local function owns(list: any, id: string): boolean
	return type(list) == "table" and table.find(list, id) ~= nil
end

local function ownsCosmetic(id: string): boolean
	local owned = profile().ownedCosmetics
	return ProgressionConfig.ownsCosmetic(if type(owned) == "table" then owned else {}, id)
end

local function setStatus(text: string, color: Color3?)
	local p = LoadoutController.parts
	p.status.Text = text
	p.status.TextColor3 = color or C.muted
end

-- The hotbar's key for each weapon owned (owned weapons in shop order).
local function hotbarKeys(): { [string]: number }
	local keys, n = {}, 0
	for _, id in WeaponConfig.order do
		if owns(profile().ownedWeapons, id) then
			n += 1
			keys[id] = n
		end
	end
	return keys
end

local function equippedEmote(): string
	local id = profile().equippedEmote
	return if type(id) == "string" and ProgressionConfig.cosmetics[id] then id else "Toot"
end

local render: () -> ()

-- Asks the server (one request at a time, as in the locker).
local function ask(action: string, kind: string, id: string?)
	if LockerController.busy then
		return
	end
	setStatus("Equipping...")
	LockerController.request(action, kind, id)
	render()
end

local function label(text: string, size: number, props: { [string]: any }): TextLabel
	return UI.label(text, size, props)
end

-- A stat row: its name, a bar for `fraction` of the shop's best, the value.
local function statRow(parent: Instance, name: string, order: number)
	local row = UI.new("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	label(string.upper(name), 16, {
		Name = "Label",
		Size = UDim2.new(0, 80, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local track = UI.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 84, 0.5, 0),
		Size = UDim2.new(1, -244, 0, 12),
		BackgroundColor3 = Color3.fromRGB(12, 10, 18),
		Parent = row,
	}, { UI.corner(6) })
	UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 225, 90),
		Parent = track,
	}, { UI.corner(6) })
	label("", 16, {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 150, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 225, 90),
		Parent = row,
	})
end

-- One choice in the picker: how it looks, its name, and whether it can be
-- picked.
type Option = { id: string?, name: string, note: string?, enabled: boolean, chosen: boolean, draw: (Frame) -> () }

function LoadoutController.closePicker()
	local p = LoadoutController.parts
	p.picker.Visible = false
	LoadoutController.picking = nil
end

local function openPicker(kind: string, title: string, options: { Option }, onPick: (string?) -> (), shop: boolean)
	local p = LoadoutController.parts
	LoadoutController.picking = kind
	p.pickerTitle.Text = title
	for _, child in p.pickerOptions:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, option in options do
		local button = UI.chunky("", if option.chosen then SELECTED else C.panelLight, nil, {
			Name = option.id or "None",
			LayoutOrder = i,
			Parent = p.pickerOptions,
		})
		-- A note (why it's locked) takes a line off the top of the look.
		local top = if option.note then 24 else 6
		local look = UI.new("Frame", {
			Name = "Look",
			Position = UDim2.new(0, 6, 0, top),
			Size = UDim2.new(1, -12, 0, 58 - top),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = button,
		})
		option.draw(look)
		if option.note then
			label(option.note, 14, {
				Name = "Note",
				Position = UDim2.new(0, 6, 0, 5),
				Size = UDim2.new(1, -12, 0, 17),
				TextColor3 = C.gold,
				ZIndex = 2,
				Parent = button,
			})
		end
		label(option.name, 15, {
			Name = "ItemName",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6, 1, -6),
			Size = UDim2.new(1, -12, 0, 20),
			TextScaled = true,
			TextColor3 = if option.enabled then C.text else DIM,
			ZIndex = 2,
			Parent = button,
		})
		if option.chosen then
			button.Border.Color = C.text
			button.Border.Thickness = 4
		end
		UI.setEnabled(button, option.enabled)
		UI.onClick(button, function()
			LoadoutController.closePicker()
			if not option.chosen then
				onPick(option.id)
			end
		end)
	end
	p.pickerShop.Visible = shop
	p.picker.Visible = true
	UI.pop(p.pickerCard, 0.85)
end

-- What a slot shows with nothing on: a tracer in the weapon's own colour,
-- no trail, the plain boom.
local function drawNone(kind: string): (Frame) -> ()
	return function(holder: Frame)
		if kind == "tracer" then
			local weapon = WeaponConfig.weapons[profile().equippedWeapon or ""] or WeaponConfig.weapons[WeaponConfig.order[1]]
			UI.new("Frame", {
				Name = "Streak",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0.7, 0, 0, 10),
				Rotation = -16,
				BackgroundColor3 = weapon.tracerColor,
				ZIndex = 2,
				Parent = holder,
			}, { UI.corner(5), UI.stroke(C.stroke, 2) })
		else
			label(if kind == "boom" then "💥" else "—", 30, { Name = "Mark", Size = UDim2.new(1, 0, 1, 0), ZIndex = 2, Parent = holder })
		end
	end
end

local function drawCosmetic(id: string): (Frame) -> ()
	return function(holder: Frame)
		LockerController.swatch(id, holder)
		for _, child in holder:GetDescendants() do
			if child:IsA("GuiObject") then
				child.ZIndex = 2
			end
		end
	end
end

-- The picker for a look slot: nothing, or anything of that kind you own.
function LoadoutController.pickLook(kind: string)
	local slot
	for _, entry in SLOTS do
		if entry.kind == kind then
			slot = entry
		end
	end
	local equipped = profile()[slot.field]
	local options: { Option } = {
		{ id = nil, name = slot.none, enabled = true, chosen = equipped == nil, draw = drawNone(kind) },
	}
	for _, id in ProgressionConfig.cosmeticOrder do
		local cosmetic = ProgressionConfig.cosmetics[id]
		if cosmetic.kind == kind and ownsCosmetic(id) then
			table.insert(options, { id = id, name = cosmetic.name, enabled = true, chosen = equipped == id, draw = drawCosmetic(id) })
		end
	end
	openPicker(kind, slot.label, options, function(id)
		if id then
			ask("equip", "cosmetic", id)
		else
			ask("equip", kind, nil)
		end
	end, true)
end

-- The picker for Q: every Q ability, the locked ones with their level.
function LoadoutController.pickAbility()
	local view = profile()
	local options: { Option } = {}
	for _, id in Q_ABILITIES do
		local ability = AbilityConfig[id]
		local unlocked = owns(view.unlockedAbilities, id)
		local look = ABILITY_LOOK[id]
		table.insert(options, {
			id = id,
			name = ability.displayName,
			note = if unlocked then nil else `🔒 LEVEL {ability.level}`,
			enabled = unlocked,
			chosen = view.equippedAbility == id,
			draw = function(holder)
				label(look.icon, 36, { Name = "Icon", Size = UDim2.new(1, 0, 1, 0), ZIndex = 2, Parent = holder })
			end,
		})
	end
	LockerController.seeAbilities()
	openPicker("ability", "Q ABILITY", options, function(id)
		ask("equip", "ability", id)
	end, false)
end

-- Opens the shop at `section`, leaving the loadout.
local function toShop(section: string)
	LoadoutController.close()
	LockerController.open("Weapons", section)
end

local function build()
	local p = LoadoutController.parts
	local screen = UI.screen("Loadout", 16)
	screen.Enabled = false
	p.screen = screen
	-- Dark diagonal stripes over the whole screen.
	local keypoints = {}
	for i = 0, 9 do
		local color = if i % 2 == 0 then Color3.fromRGB(20, 16, 32) else Color3.fromRGB(27, 22, 41)
		table.insert(keypoints, ColorSequenceKeypoint.new(if i == 0 then 0 else i / 10 + 0.0001, color))
		table.insert(keypoints, ColorSequenceKeypoint.new(if i == 9 then 1 else (i + 1) / 10, color))
	end
	local backdrop = UI.new("Frame", {
		Name = "Backdrop",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Active = true,
		Parent = screen,
	}, { UI.new("UIGradient", { Color = ColorSequence.new(keypoints), Rotation = 35 }) })
	local stage = UI.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, STAGE.X, 0, STAGE.Y),
		BackgroundTransparency = 1,
		Parent = backdrop,
	})
	p.stage = stage
	local fit = UI.new("UIScale", { Name = "Fit", Parent = stage })
	local function refit()
		local size = screen.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			fit.Scale = math.min(size.X / STAGE.X, size.Y / STAGE.Y)
		end
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()

	label("LOADOUT", 46, {
		Name = "Title",
		Position = UDim2.new(0, 30, 0, 18),
		Size = UDim2.new(0, 400, 0, 52),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = stage,
	})
	local wallet = UI.new("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 18),
		Size = UDim2.new(0, 210, 0, 48),
		BackgroundColor3 = Color3.fromRGB(14, 12, 20),
		BackgroundTransparency = 0.1,
		Parent = stage,
	}, { UI.corner(24), UI.stroke(C.stroke, 3) })
	label("💰", 26, { Name = "Coin", Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(0, 36, 1, 0), Parent = wallet })
	p.coins = label("0", 28, {
		Name = "Coins",
		Position = UDim2.new(0, 50, 0, 0),
		Size = UDim2.new(1, -66, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UIConfig.gold,
		Parent = wallet,
	})

	-- Left: the weapons, then the abilities.
	local left = UI.new("Frame", {
		Name = "Weapons",
		Position = UDim2.new(0, 30, 0, 92),
		Size = UDim2.new(0, 310, 0, 420),
		BackgroundTransparency = 1,
		Parent = stage,
	})
	label("WEAPONS (1-4)", 15, {
		Name = "Heading",
		Size = UDim2.new(1, 0, 0, 20),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = left,
	})
	p.rows = {}
	for i, id in WeaponConfig.order do
		local weapon = WeaponConfig.weapons[id]
		local row = UI.new("TextButton", {
			Name = id,
			Position = UDim2.new(0, 0, 0, 26 + (i - 1) * 74),
			Size = UDim2.new(1, 0, 0, 66),
			BackgroundColor3 = ROW,
			AutoButtonColor = false,
			Text = "",
			Parent = left,
		}, { UI.corner(14), UI.stroke(C.stroke, 4) })
		UI.springy(row, 1.03)
		local key = UI.new("Frame", {
			Name = "Key",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.new(0, 32, 0, 32),
			BackgroundColor3 = Color3.fromRGB(12, 10, 18),
			Parent = row,
		}, { UI.corner(8) })
		label("", 18, { Name = "Number", Size = UDim2.new(1, 0, 1, 0), Parent = key })
		label(weapon.displayName, 21, {
			Name = "WeaponName",
			Position = UDim2.new(0, 56, 0, 8),
			Size = UDim2.new(1, -130, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		label("", 13, {
			Name = "Sub",
			Position = UDim2.new(0, 56, 0, 36),
			Size = UDim2.new(1, -130, 0, 18),
			Font = UIConfig.bodyFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		UI.new("Frame", {
			Name = "Swatch",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.new(0, 54, 0, 22),
			BackgroundColor3 = weapon.tracerColor,
			Parent = row,
		}, { UI.corner(6), UI.stroke(C.stroke, 2) })
		label("🔒", 22, {
			Name = "Lock",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.new(0, 54, 0, 30),
			Parent = row,
		})
		p.rows[id] = row
		UI.onClick(row, function()
			LoadoutController.selected = id
			render()
		end)
	end
	label("ABILITIES", 15, {
		Name = "AbilitiesHeading",
		Position = UDim2.new(0, 0, 0, 26 + #WeaponConfig.order * 74 + 6),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = left,
	})
	local abilityTop = 26 + #WeaponConfig.order * 74 + 32
	local function abilityBox(name: string, key: string, x: number): TextButton
		local box = UI.chunky("", Color3.fromRGB(42, 35, 60), nil, {
			Name = name,
			Position = UDim2.new(x, if x > 0 then 5 else 0, 0, abilityTop),
			Size = UDim2.new(0.5, -5, 0, 64),
			Parent = left,
		})
		label(key, 12, {
			Name = "Key",
			Position = UDim2.new(0, 12, 0, 8),
			Size = UDim2.new(1, -24, 0, 16),
			Font = UIConfig.bodyFont,
			TextColor3 = C.muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
			Parent = box,
		})
		label("", 17, {
			Name = "AbilityName",
			Position = UDim2.new(0, 12, 0, 26),
			Size = UDim2.new(1, -24, 0, 28),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
			Parent = box,
		})
		return box
	end
	p.dash = abilityBox("Dash", "SHIFT", 0)
	p.dash.AbilityName.Text = `{ABILITY_LOOK.FartDash.icon} {AbilityConfig.FartDash.displayName}`
	p.ability = abilityBox("Ability", "Q  ·  CHANGE", 0.5)
	UI.onClick(p.ability, LoadoutController.pickAbility)

	-- Middle: the picked weapon.
	local middle = UI.new("Frame", {
		Name = "Middle",
		Position = UDim2.new(0, 380, 0, 84),
		Size = UDim2.new(0, 520, 0, 600),
		BackgroundTransparency = 1,
		Parent = stage,
	})
	p.window = UI.new("Frame", {
		Name = "Window",
		Size = UDim2.new(1, 0, 0, 236),
		BackgroundColor3 = Color3.fromRGB(14, 12, 22),
		BackgroundTransparency = 0.4,
		Parent = middle,
	}, { UI.corner(18) })
	p.name = label("", 34, {
		Name = "WeaponName",
		Position = UDim2.new(0, 0, 0, 242),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = middle,
	})
	p.description = label("", 14, {
		Name = "Description",
		Position = UDim2.new(0, 10, 0, 282),
		Size = UDim2.new(1, -20, 0, 36),
		Font = UIConfig.bodyFont,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(215, 208, 232),
		Parent = middle,
	})
	p.stats = UI.new("Frame", {
		Name = "Stats",
		Position = UDim2.new(0, 0, 0, 322),
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundTransparency = 1,
		Parent = middle,
	}, { UI.list(Enum.FillDirection.Vertical, 6) })
	statRow(p.stats, "Gas", 1)
	statRow(p.stats, "Range", 2)
	statRow(p.stats, "Rate", 3)
	p.action = UI.chunky("EQUIP", SELECTED, nil, {
		Name = "Action",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 418),
		Size = UDim2.new(0, 300, 0, 52),
		TextSize = 24,
		Parent = middle,
	})
	UI.onClick(p.action, function()
		local id = LoadoutController.selected
		local view = profile()
		if not id then
			return
		elseif owns(view.ownedWeapons, id) then
			ask("equip", "weapon", id)
		else
			toShop("Weapons")
		end
	end)
	-- The look slots.
	local slots = UI.new("Frame", {
		Name = "Looks",
		Position = UDim2.new(0, 0, 0, 482),
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundTransparency = 1,
		Parent = middle,
	}, { UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center) })
	p.slots = {}
	for i, slot in SLOTS do
		local button = UI.chunky("", Color3.fromRGB(42, 35, 60), nil, {
			Name = slot.kind,
			LayoutOrder = i,
			Size = UDim2.new(0, 165, 0, 84),
			Parent = slots,
		})
		label(slot.label, 12, {
			Name = "Kind",
			Position = UDim2.new(0, 0, 0, 6),
			Size = UDim2.new(1, 0, 0, 16),
			Font = UIConfig.bodyFont,
			TextColor3 = C.muted,
			ZIndex = 2,
			Parent = button,
		})
		UI.new("Frame", {
			Name = "Look",
			Position = UDim2.new(0, 10, 0, 22),
			Size = UDim2.new(1, -20, 0, 34),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = button,
		})
		label("", 16, {
			Name = "ItemName",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 8, 1, -6),
			Size = UDim2.new(1, -16, 0, 20),
			TextScaled = true,
			ZIndex = 2,
			Parent = button,
		})
		p.slots[slot.kind] = button
		UI.onClick(button, function()
			LoadoutController.pickLook(slot.kind)
		end)
	end

	-- Right: the emotes around E.
	label("EMOTES (HOLD E)", 15, {
		Name = "EmotesHeading",
		Position = UDim2.new(0, 950, 0, 120),
		Size = UDim2.new(0, 290, 0, 20),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		Parent = stage,
	})
	p.ring = UI.new("Frame", {
		Name = "Emotes",
		Position = UDim2.new(0, 950, 0, 150),
		Size = UDim2.new(0, 290, 0, 290),
		BackgroundColor3 = Color3.fromRGB(29, 24, 40),
		Parent = stage,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.stroke(Color3.fromRGB(58, 51, 80), 5) })
	local center = UI.new("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 84, 0, 84),
		BackgroundColor3 = Color3.fromRGB(12, 10, 18),
		Parent = p.ring,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.stroke(Color3.fromRGB(58, 51, 80), 4) })
	p.centerEmoji = label("", 32, { Name = "Emoji", Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 40), Parent = center })
	label("E", 22, { Name = "Key", Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(1, 0, 0, 26), Parent = center })
	p.emoteName = label("", 18, {
		Name = "EmoteName",
		Position = UDim2.new(0, 950, 0, 452),
		Size = UDim2.new(0, 290, 0, 24),
		TextColor3 = UIConfig.gold,
		Parent = stage,
	})
	label("Tap E for the lit one, hold E for the wheel.", 13, {
		Name = "EmoteHint",
		Position = UDim2.new(0, 950, 0, 478),
		Size = UDim2.new(0, 290, 0, 18),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		Parent = stage,
	})

	p.status = label("", 15, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0, 520, 0, 22),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		Parent = stage,
	})
	-- BACK frees the mouse from first person while the loadout is up.
	local back = UI.chunky("BACK", Color3.fromRGB(235, 55, 60), nil, {
		Name = "Back",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 30, 1, -24),
		Size = UDim2.new(0, 190, 0, 60),
		TextSize = 30,
		Modal = true,
		Parent = stage,
	})
	p.back = back
	UI.onClick(back, LoadoutController.close)

	-- The picker, over everything.
	p.picker = UI.new("Frame", {
		Name = "Picker",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		Active = true,
		Visible = false,
		ZIndex = 10,
		Parent = stage,
	})
	p.pickerCard = UI.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 580, 0, 430),
		BackgroundColor3 = C.panel,
		Parent = p.picker,
	}, { UI.corner(20), UI.stroke(C.text, 4) })
	p.pickerTitle = label("", 32, { Name = "Title", Position = UDim2.new(0, 0, 0, 12), Size = UDim2.new(1, 0, 0, 38), Parent = p.pickerCard })
	p.pickerOptions = UI.new("ScrollingFrame", {
		Name = "Options",
		Position = UDim2.new(0, 20, 0, 60),
		Size = UDim2.new(1, -40, 0, 280),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = p.pickerCard,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.new(0, 166, 0, 90),
			CellPadding = UDim2.new(0, 10, 0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		UI.padding(4),
	})
	p.pickerShop = UI.chunky("MORE IN THE SHOP", C.play, "🛒", {
		Name = "Shop",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -16),
		Size = UDim2.new(0, 290, 0, 54),
		TextSize = 20,
		Parent = p.pickerCard,
	})
	UI.onClick(p.pickerShop, function()
		toShop("Daily")
	end)
	local closePicker = UI.chunky("CLOSE", Color3.fromRGB(235, 55, 60), nil, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -16),
		Size = UDim2.new(0, 160, 0, 54),
		TextSize = 22,
		Parent = p.pickerCard,
	})
	UI.onClick(closePicker, LoadoutController.closePicker)
end

-- The emotes you own around E, the one E plays lit; empty spots lead to the
-- daily shop.
local function renderEmotes()
	local p = LoadoutController.parts
	for _, child in p.ring:GetChildren() do
		if child.Name == "Spot" or child:GetAttribute("Emote") then
			child:Destroy()
		end
	end
	local owned = {}
	for _, id in ProgressionConfig.cosmeticOrder do
		if ProgressionConfig.cosmetics[id].kind == "emote" and ownsCosmetic(id) then
			table.insert(owned, id)
		end
	end
	local current = equippedEmote()
	for i = 1, EMOTE_SPOTS do
		local angle = math.rad(-90 + (i - 1) * 360 / EMOTE_SPOTS)
		local position = UDim2.new(0.5, math.cos(angle) * 108, 0.5, math.sin(angle) * 108)
		local id = owned[i]
		local spot: TextButton
		if id then
			local cosmetic = ProgressionConfig.cosmetics[id]
			local lit = id == current
			spot = UI.chunky("", if lit then Color3.fromRGB(102, 220, 60) else Color3.fromRGB(70, 60, 98), nil, {
				Name = id,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = position,
				Size = UDim2.new(0, 64, 0, 64),
				Parent = p.ring,
			})
			spot:SetAttribute("Emote", id)
			spot:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0);
			(spot.Fill :: Frame):FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
			label(cosmetic.emoji, 30, { Name = "Emoji", Size = UDim2.new(1, 0, 1, 0), ZIndex = 2, Parent = spot })
			if lit then
				spot.Border.Color = C.text
				spot.Border.Thickness = 4
			end
			UI.onClick(spot, function()
				if equippedEmote() ~= id then
					ask("equip", "cosmetic", id)
				end
			end)
		else
			spot = UI.new("TextButton", {
				Name = "Spot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = position,
				Size = UDim2.new(0, 64, 0, 64),
				BackgroundTransparency = 1,
				Text = "+",
				TextSize = 28,
				Font = UIConfig.font,
				TextColor3 = DIM,
				Parent = p.ring,
			}, {
				UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				UI.new("UIStroke", { Color = Color3.fromRGB(90, 82, 112), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			})
			UI.onClick(spot, function()
				toShop("Daily")
			end)
		end
	end
	local cosmetic = ProgressionConfig.cosmetics[current]
	p.centerEmoji.Text = cosmetic.emoji or "💨"
	p.emoteName.Text = `E: {cosmetic.emoji or ""} {cosmetic.name}`
end

render = function()
	local p = LoadoutController.parts
	if not LoadoutController.isOpen then
		return
	end
	local view = profile()
	local level = number("Level", 1)
	p.coins.Text = UI.commas(number("Coins", 0))
	local keys = hotbarKeys()
	local selected = LoadoutController.selected
	if not selected or not WeaponConfig.weapons[selected] then
		selected = if type(view.equippedWeapon) == "string" and WeaponConfig.weapons[view.equippedWeapon] then view.equippedWeapon else WeaponConfig.order[1]
		LoadoutController.selected = selected
	end
	local busy = LockerController.busy

	-- The weapon rows.
	for id, row in p.rows do
		local weapon = WeaponConfig.weapons[id]
		local owned = keys[id] ~= nil
		local locked = not owned and level < weapon.level
		local equipped = owned and view.equippedWeapon == id
		row.BackgroundColor3 = if owned then ROW else ROW_LOCKED
		row.Border.Color = if id == selected then SELECTED else Color3.fromRGB(46, 40, 64)
		row.Key.Number.Text = if owned then tostring(keys[id]) else ""
		row.Key.Visible = owned
		row.WeaponName.TextColor3 = if owned then C.text else DIM
		local how = `{LockerController.handling(weapon)} · {if weapon.projectile == "lob" then "lobbed" else "instant"}`
		row.Sub.Text = if equipped then `EQUIPPED · {how}`
			elseif owned then how
			elseif locked then `Level {weapon.level}`
			else `In the shop · {UI.commas(LockerController.priceOf(id))} coins`
		row.Sub.TextColor3 = if equipped then C.accent elseif owned then Color3.fromRGB(185, 178, 204) else DIM
		row.Swatch.Visible = owned
		row.Lock.Text = if locked then "🔒" else "🛒"
		row.Lock.Visible = not owned
	end

	-- The abilities.
	local ability = view.equippedAbility and AbilityConfig[view.equippedAbility]
	p.ability.AbilityName.Text = if ability then `{ABILITY_LOOK[view.equippedAbility].icon} {ability.displayName}` else "None yet"
	UI.setBadge(p.ability, LockerController.newAbilities())

	-- The picked weapon.
	local weapon = WeaponConfig.weapons[selected]
	local preview = p.window:FindFirstChild("Preview")
	if not preview or preview:GetAttribute("Weapon") ~= selected then
		if preview then
			preview:Destroy()
		end
		preview = WeaponView.new(selected, { Name = "Preview", Size = UDim2.new(1, 0, 1, 0), Parent = p.window })
		WeaponView.spin(preview, turn)
	end
	p.name.Text = string.upper(weapon.displayName)
	p.description.Text = weapon.description
	local best = { gas = 0, range = 0, rate = 0 }
	for _, id in WeaponConfig.order do
		local other = WeaponConfig.weapons[id]
		best.gas = math.max(best.gas, other.gasPerHit)
		best.range = math.max(best.range, other.range)
		best.rate = math.max(best.rate, 1 / other.fireInterval)
	end
	local rows = {
		Gas = { weapon.gasPerHit / best.gas, `{weapon.gasPerHit}% (head {weapon.headshotGas}%)` },
		Range = { weapon.range / best.range, `{weapon.range} · {if weapon.projectile == "lob" then "lobbed" else "instant"}` },
		Rate = { (1 / weapon.fireInterval) / best.rate, `{string.format("%.1f", 1 / weapon.fireInterval)}/s` },
	}
	for name, values in rows do
		local row = p.stats[name]
		row.Track.Fill.Size = UDim2.new(math.clamp(values[1], 0.06, 1), 0, 1, 0)
		row.Value.Text = values[2]
	end
	local owned = keys[selected] ~= nil
	if owned and view.equippedWeapon == selected then
		p.action.Text = "EQUIPPED"
		UI.setEnabled(p.action, false)
	elseif owned then
		p.action.Text = "EQUIP"
		p.action:SetAttribute("Color", SELECTED)
		UI.setEnabled(p.action, not busy)
	elseif level < weapon.level then
		p.action.Text = `🔒 LEVEL {weapon.level}`
		UI.setEnabled(p.action, false)
	else
		p.action.Text = `GET IT IN THE SHOP`
		p.action:SetAttribute("Color", C.play)
		UI.setEnabled(p.action, true)
	end

	-- The look slots.
	for _, slot in SLOTS do
		local button = p.slots[slot.kind]
		local id = view[slot.field]
		local cosmetic = if type(id) == "string" then ProgressionConfig.cosmetics[id] else nil
		for _, child in button.Look:GetChildren() do
			child:Destroy()
		end
		if cosmetic then
			drawCosmetic(id)(button.Look)
			button.ItemName.Text = cosmetic.name
		else
			drawNone(slot.kind)(button.Look)
			button.ItemName.Text = slot.none
		end
		UI.setEnabled(button, not busy)
	end

	renderEmotes()
end
LoadoutController.render = render

function LoadoutController.open()
	local p = LoadoutController.parts
	LockerController.hide()
	if not LoadoutController.isOpen then
		LoadoutController.selected = nil
		setStatus(if LockerController.profile and LockerController.profile.saving == false
			then "Progress isn't saving this session: changes won't be kept."
			else "")
	end
	LoadoutController.isOpen = true
	p.screen.Enabled = true
	MouseLock.setFree("Loadout", true)
	render()
end

function LoadoutController.close()
	local p = LoadoutController.parts
	LoadoutController.isOpen = false
	if p.screen then
		LoadoutController.closePicker()
		p.screen.Enabled = false
	end
	MouseLock.setFree("Loadout", false)
end

function LoadoutController.start()
	if started then
		return
	end
	started = true
	build()
	LockerController.loadout = { open = LoadoutController.open, close = LoadoutController.close }
	-- The weapon in the window turns while it shows.
	RunService.RenderStepped:Connect(function(dt)
		if LoadoutController.isOpen and not Settings.reduceMotion then
			turn = (turn + dt * LockerController.SPIN_SPEED) % 360
			local preview = LoadoutController.parts.window:FindFirstChild("Preview")
			if preview then
				WeaponView.spin(preview, turn)
			end
		end
	end)
	LockerController.ProfileChanged:Connect(render)
	LockerController.BadgesChanged:Connect(render)
	LockerController.Answered:Connect(function(answer, action, kind, id)
		if not LoadoutController.isOpen then
			return
		end
		setStatus(tostring(answer.message), if answer.ok then C.accent else C.warning)
		render()
		if answer.ok and action == "equip" then
			local p = LoadoutController.parts
			local target = if kind == "weapon" then p.rows[id]
				elseif kind == "ability" then p.ability
				elseif id and ProgressionConfig.cosmetics[id] and ProgressionConfig.cosmetics[id].kind == "emote" then p.ring
				elseif id and ProgressionConfig.cosmetics[id] then p.slots[ProgressionConfig.cosmetics[id].kind]
				else p.slots[kind]
			if target then
				UI.pop(target, 1.12)
			end
		end
	end)
	for _, name in { "Coins", "Level" } do
		player:GetAttributeChangedSignal(name):Connect(render)
	end
	-- Pressing PLAY, spectating or going AFK closes it.
	ClientState.StateChanged:Connect(LoadoutController.close)
end

return LoadoutController
