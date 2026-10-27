-- The locker: the menu's Shop, Levels and Settings pages, from the home
-- screen or the M menu (Loadout, the fourth tab, is its own screen:
-- LoadoutController). One big window: the page's name and your coins on a
-- header in its colour, chunky tabs, a red X; the cards lift under the
-- pointer.
--   Shop         one long page, a rail beside it jumping to each part:
--     Featured   the passes (the Starter Pack), contents in full and drawn,
--                prices from Roblox (cosmetics and coins only)
--     Weapons    a card per weapon in its colour: the model turning in a
--                window (locked until your level reaches it), gas, range
--                and fire rate as bars against the shop's best, mastery,
--                and BUY (after "Buy it?"), EQUIP or what's missing; a
--                stamp on the card when it's bought or equipped
--     Daily      today's five cosmetics (DailyShopConfig: the same for
--                everyone, new at 00:00 UTC, counting down), by rarity,
--                for coins (after "Buy it?")
--     Coins      the coin packs, and that nothing here is power
--   Levels       level, XP, coins, the next goal and the unlock track,
--                lifetime stats, badges, and every cosmetic (tracers,
--                Fart Dash trails, emotes): equip it, or how to get it
--   Settings     reduced effects, sound effects, tips, and the controls
-- Every button only asks (ShopRequest); while a request is out the buttons
-- wait and the status line says so, and the answer (or the refusal) is
-- shown. What the player owns comes from the server (ProfileUpdate); coins
-- and level from their attributes. buyable() and newAbilities() are what
-- the Shop and Loadout buttons' badges count.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ReleaseConfig = require(Shared.Config.ReleaseConfig)
local PrestigeConfig = require(Shared.Config.PrestigeConfig)
local DailyShopConfig = require(Shared.Config.DailyShopConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local Audio = require(Client.Audio)
local Settings = require(Client.Settings)
local Detail = require(Client.Detail)
local HealthController = require(script.Parent.HealthController)
local WeaponView = require(Client.WeaponView)
local PrestigeController = require(script.Parent.PrestigeController)
local Signal = require(Shared.Signal)
local ProgressController = require(script.Parent.ProgressController)

local C = UIConfig.colors
-- How wide the shop's page is inside the window.
local SHOP_WIDTH = 888
local SECTION_GAP = 26
local KIND_NAMES = { tracer = "TRACER", trail = "DASH TRAIL", boom = "BOOM", emote = "EMOTE" }

local LockerController = {}

LockerController.parts = {} :: { [string]: any }
LockerController.tab = "Weapons"
LockerController.isOpen = false
-- The latest ProfileUpdate.
LockerController.profile = nil :: { [string]: any }?
-- Degrees a second the weapon previews turn.
LockerController.SPIN_SPEED = 40
-- The shop part lit on the rail.
LockerController.section = "Featured"
-- The clock the daily shop goes by (the server's: specs move it).
LockerController.now = function(): number
	return workspace:GetServerTimeNow()
end
-- The loadout screen (LoadoutController) hooks itself in here, so every way
-- into the menu's pages reaches it: open("Loadout") opens it, any other page
-- closes it.
LockerController.loadout = nil :: { open: () -> (), close: () -> () }?

-- What a shop weapon costs this player (the server's figure when it has
-- sent one: experiments can change early prices).
function LockerController.priceOf(id: string): number
	local profile = LockerController.profile
	local prices = profile and profile.prices
	local price = type(prices) == "table" and prices[id]
	return if type(price) == "number" then price else WeaponConfig.weapons[id].price
end
-- A request is out; buttons wait.
LockerController.busy = false
-- (profile): a new ProfileUpdate arrived.
LockerController.ProfileChanged = Signal.new()
-- (answer, action, kind, id?): the server answered a request.
LockerController.Answered = Signal.new()
-- What the badges count may have changed (buyable(), newAbilities()).
LockerController.BadgesChanged = Signal.new()

local player = Players.LocalPlayer
local started = false
-- Abilities the player has seen in the loadout (or had already when the
-- first profile arrived); nil until then.
local seenAbilities: { [string]: boolean }? = nil

local function number(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function owns(list: any, id: string): boolean
	return type(list) == "table" and table.find(list, id) ~= nil
end

-- The weapons this player could buy right now (the Shop button's badge).
function LockerController.buyable(): number
	local profile = LockerController.profile
	if not profile or profile.saving == false then
		return 0
	end
	local level, coins, count = number("Level", 1), number("Coins", 0), 0
	for _, id in WeaponConfig.order do
		if not owns(profile.ownedWeapons, id) and level >= WeaponConfig.weapons[id].level and coins >= LockerController.priceOf(id) then
			count += 1
		end
	end
	return count
end

-- Abilities unlocked since the player last looked at the loadout's Q
-- abilities.
function LockerController.newAbilities(): number
	local profile = LockerController.profile
	if not profile or not seenAbilities or type(profile.unlockedAbilities) ~= "table" then
		return 0
	end
	local count = 0
	for _, id in profile.unlockedAbilities do
		if not seenAbilities[id] then
			count += 1
		end
	end
	return count
end

local function seeAbilities()
	local profile = LockerController.profile
	seenAbilities = seenAbilities or {}
	if profile and type(profile.unlockedAbilities) == "table" then
		for _, id in profile.unlockedAbilities do
			(seenAbilities :: any)[id] = true
		end
	end
end

-- The loadout showed the Q abilities: they're not news any more.
function LockerController.seeAbilities()
	seeAbilities()
	LockerController.BadgesChanged:Fire()
end

function LockerController.handling(weapon: WeaponConfig.Weapon): string
	return if weapon.walkSpeed >= 16 then "Light" elseif weapon.walkSpeed >= 15 then "Steady" else "Heavy"
end

local function setStatus(text: string, color: Color3?)
	local p = LockerController.parts
	p.status.Text = text
	p.status.TextColor3 = color or C.muted
end

local render: () -> ()
local stamp: (id: string, text: string) -> ()

-- Sends one request; the buttons wait for the answer.
function LockerController.request(action: string, kind: string, id: string?)
	if LockerController.busy then
		return
	end
	LockerController.busy = true
	setStatus(if action == "buy" then "Buying... (saving your purchase)" elseif action == "redeem" then "Checking the code..." else "Equipping...")
	render()
	task.spawn(function()
		local remote = ClientState.remote("ShopRequest") :: RemoteFunction
		local sentAt = os.clock()
		local ok, answer = pcall(remote.InvokeServer, remote, action, kind, id)
		HealthController.noteLatency(os.clock() - sentAt)
		LockerController.busy = false
		if ok and type(answer) == "table" then
			setStatus(tostring(answer.message), if answer.ok then C.accent else C.warning)
			if answer.ok and (action == "buy" or action == "redeem") then
				Audio.play("purchase")
			end
		else
			answer = { ok = false, reason = "unreachable", message = "Couldn't reach the server. Try again." }
			setStatus(answer.message, C.warning)
		end
		render()
		if answer.ok and id and LockerController.isOpen then
			stamp(id, if action == "buy" then "PURCHASED!" else "EQUIPPED!")
		end
		LockerController.BadgesChanged:Fire()
		LockerController.Answered:Fire(answer, action, kind, id)
	end)
end

-- A shop card: a chunky box in `color` (darkened, so white text reads on
-- it) that lifts a little under the pointer.
local function card(parent: Instance, name: string, order: number, height: number, color: Color3?): Frame
	local h, s, v = (color or C.panelLight):ToHSV()
	local box = UI.box(name, Color3.fromHSV(h, math.min(s, 0.75), math.min(v, 0.62)), UDim2.new(0, 190, 0, height), {
		LayoutOrder = order,
		Parent = parent,
	})
	UI.padding(8).Parent = box
	UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center).Parent = box
	UI.springy(box, 1.03)
	return box
end

-- A stat: its name and value, and a bar for `fraction` of the shop's best.
local function statBar(parent: Instance, label: string, value: string, fraction: number, order: number, color: Color3)
	local row = UI.new("Frame", {
		Name = "Stat",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UI.label(label, 12, {
		Name = "Label",
		Size = UDim2.new(0.4, 0, 0, 14),
		Font = UIConfig.bodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	UI.label(value, 12, {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.6, 0, 0, 14),
		Font = UIConfig.bodyFont,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	local track = UI.new("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 0, 0, 17),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Color3.fromRGB(16, 14, 24),
		Parent = row,
	}, { UI.corner(5) })
	UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(math.clamp(fraction, 0.06, 1), 0, 1, 0),
		BackgroundColor3 = color,
		Parent = track,
	}, { UI.corner(5) })
end

local function text(parent: Instance, value: string, size: number, order: number, props: { [string]: any }?): TextLabel
	-- Wrapped text grows downward rather than spilling onto the next line.
	local label = UI.label(value, size, {
		LayoutOrder = order,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = if size <= 15 then UIConfig.bodyFont else UIConfig.font,
		Parent = parent,
	})
	if props then
		for key, v in props do
			(label :: any)[key] = v
		end
	end
	return label
end

local EQUIP_BLUE = Color3.fromRGB(45, 155, 245)

local function actionButton(parent: Instance, label: string, enabled: boolean, onClick: (() -> ())?, color: Color3?): TextButton
	local button = UI.chunky(label, if enabled then color or C.play else C.disabled, nil, {
		Name = "Action",
		LayoutOrder = 100,
		Size = UDim2.new(1, 0, 0, 42),
		TextSize = 20,
		Parent = parent,
	})
	UI.setEnabled(button, enabled and not LockerController.busy)
	if onClick then
		UI.onClick(button, onClick)
	end
	return button
end

-- How a cosmetic looks, drawn in `holder`: a tracer's streak, a trail's
-- puffs, a boom's ring or an emote's face.
local function swatch(id: string, holder: GuiObject)
	local cosmetic = ProgressionConfig.cosmetics[id]
	if not cosmetic then
		return
	end
	local color = cosmetic.tracerColor or cosmetic.trailColor or cosmetic.boomColor or C.text
	local look = UI.new("Frame", {
		Name = "Swatch",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	if cosmetic.kind == "tracer" then
		UI.new("Frame", {
			Name = "Streak",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0.7, 0, 0, 10),
			Rotation = -16,
			BackgroundColor3 = color,
			Parent = look,
		}, { UI.corner(5), UI.stroke(C.stroke, 2) })
	elseif cosmetic.kind == "trail" then
		for i, size in { 14, 20, 26 } do
			UI.new("Frame", {
				Name = "Puff",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.22 + i * 0.16, 0, 0.5, 0),
				Size = UDim2.new(0, size, 0, size),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.3 - i * 0.1,
				Parent = look,
			}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.stroke(C.stroke, 2) })
		end
	elseif cosmetic.kind == "boom" then
		UI.new("Frame", {
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 52, 0, 52),
			BackgroundTransparency = 1,
			Parent = look,
		}, {
			UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			UI.new("UIStroke", { Color = color, Thickness = 7 }),
		})
	else
		UI.label(cosmetic.emoji or "💨", 40, { Name = "Emoji", Size = UDim2.new(1, 0, 1, 0), Parent = look })
	end
end
LockerController.swatch = swatch

-- Recolours a UI.box.
local function tint(box: Frame, color: Color3)
	local h, s, v = color:ToHSV()
	local gradient = box:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(Color3.fromHSV(h, s * 0.9, math.min(1, v * 1.1)), Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.72))
	end
end

-- "Buy it?" before coins are spent: what it is, its price and what's left.
local function confirm(kind: string, id: string, title: string, cost: number, color: Color3, draw: (Frame) -> ())
	local p = LockerController.parts
	p.confirmKind, p.confirmId = kind, id
	p.confirmTitle.Text = title
	p.confirmPrice.Text = `💰 {UI.commas(cost)}`
	p.confirmLeft.Text = `You'll have {UI.commas(number("Coins", 0) - cost)} coins left.`
	tint(p.confirmCard, color)
	for _, child in p.confirmPreview:GetChildren() do
		if not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	draw(p.confirmPreview)
	p.confirm.Visible = true
	UI.pop(p.confirmCard, 0.8)
end

function LockerController.confirmBuy(id: string)
	local weapon = WeaponConfig.weapons[id]
	confirm("weapon", id, `BUY THE {string.upper(weapon.displayName)}?`, LockerController.priceOf(id), UIConfig.pages.Weapons.color, function(holder)
		WeaponView.new(id, { Name = "Preview", Size = UDim2.new(1, 0, 1, 0), Parent = holder })
	end)
end

-- The same for one of today's cosmetics.
function LockerController.confirmCosmetic(id: string)
	local item = DailyShopConfig.item(id)
	local cosmetic = ProgressionConfig.cosmetics[id]
	if not item or not cosmetic then
		return
	end
	confirm("cosmetic", id, `BUY {string.upper(cosmetic.name)}?`, item.price, DailyShopConfig.rarities[item.rarity].color, function(holder)
		swatch(id, holder)
	end)
end

function LockerController.closeConfirm()
	local p = LockerController.parts
	p.confirm.Visible = false
	p.confirmId = nil
end

-- A card or tile on the open page, by its weapon's or cosmetic's id.
function LockerController.card(id: string): Frame?
	return LockerController.parts.content:FindFirstChild(id, true) :: Frame?
end

-- A "PURCHASED!" stamp on a card, then gone.
stamp = function(id: string, text: string)
	local box = LockerController.card(id)
	local window = box and box:FindFirstChild("Window")
	if not box or not window then
		return
	end
	UI.pop(box :: GuiObject, 1.12)
	local label = UI.label(text, 30, {
		Name = "Stamp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 20, 0, 40),
		Rotation = -12,
		TextColor3 = UIConfig.gold,
		ZIndex = 6,
		Parent = window,
	})
	UI.pop(label, 1.8)
	task.delay(1.6, function()
		label:Destroy()
	end)
end

-- The weapon previews on screen now (the shop), and their turn.
local previews: { ViewportFrame } = {}
local turn = 0
-- Where each part of the shop starts on its page, and the day its daily
-- part shows.
local sectionTops: { [string]: number } = {}
local shownDay = -1

-- The store's prices come from Roblox, once each.
local priceCache: { [string]: string } = {}
local function price(kind: Enum.InfoType, id: number): string
	local key = `{kind.Name}:{id}`
	if priceCache[key] then
		return priceCache[key]
	end
	priceCache[key] = "..."
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, kind)
		priceCache[key] = if ok and type(info) == "table" and info.PriceInRobux then `R$ {info.PriceInRobux}` else "BUY"
		if LockerController.isOpen and LockerController.tab == "Weapons" then
			render()
		end
	end)
	return priceCache[key]
end
-- (The home screen's featured offers show the same prices.)
LockerController.price = price

-- A part's title, centred between two rules.
local function heading(parent: Instance, value: string)
	local row = UI.new("Frame", {
		Name = "Heading",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	for _, side in { 0, 1 } do
		UI.new("Frame", {
			Name = "Rule",
			AnchorPoint = Vector2.new(side, 0.5),
			Position = UDim2.new(side, 0, 0.5, 0),
			Size = UDim2.new(0.5, -160, 0, 3),
			BackgroundColor3 = Color3.fromRGB(74, 69, 96),
			BorderSizePixel = 0,
			Parent = row,
		})
	end
	UI.label(value, 30, { Name = "Title", Size = UDim2.new(1, 0, 1, 0), Parent = row })
end

-- Cards in rows of `perRow`, `height` tall.
local function grid(parent: Instance, top: number, perRow: number, height: number): Frame
	local gap = 12
	return UI.new("Frame", {
		Name = "Cards",
		Position = UDim2.new(0, 0, 0, top),
		Size = UDim2.new(1, 0, 1, -top),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.new(0, (SHOP_WIDTH - gap * (perRow - 1)) // perRow, 0, height),
			CellPadding = UDim2.new(0, gap, 0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function rows(count: number, perRow: number, height: number): number
	local n = math.max(1, math.ceil(count / perRow))
	return n * height + (n - 1) * 12
end

local FEATURED_HEIGHT = 196

-- The passes as wide banners: what's in each, drawn and listed, and its
-- price.
local function featuredPart(parent: Frame)
	local profile = LockerController.profile or {}
	for i, pass in MonetizationConfig.passes do
		local banner = UI.box(pass.key, Color3.fromRGB(110, 55, 195), UDim2.new(1, 0, 0, FEATURED_HEIGHT), {
			Position = UDim2.new(0, 0, 0, (i - 1) * (FEATURED_HEIGHT + 12)),
			Parent = parent,
		})
		local art = UI.new("Frame", {
			Name = "Art",
			Position = UDim2.new(0, 16, 0, 16),
			Size = UDim2.new(0, 200, 1, -32),
			BackgroundColor3 = Color3.fromRGB(12, 10, 18),
			BackgroundTransparency = 0.45,
			Parent = banner,
		}, { UI.corner(14) })
		for j, id in pass.cosmetics do
			local slot = UI.new("Frame", {
				Name = id,
				Position = UDim2.new(0, 0, (j - 1) / #pass.cosmetics, 0),
				Size = UDim2.new(1, 0, 1 / #pass.cosmetics, 0),
				BackgroundTransparency = 1,
				Parent = art,
			})
			swatch(id, slot)
		end
		local tag = UI.new("Frame", {
			Name = "Tag",
			Position = UDim2.new(0, 236, 0, 18),
			Size = UDim2.new(0, 220, 0, 26),
			BackgroundColor3 = Color3.fromRGB(235, 40, 50),
			Parent = banner,
		}, { UI.corner(8), UI.stroke(C.stroke, 2) })
		UI.label("BUY ONCE, KEEP FOREVER", 14, { Size = UDim2.new(1, 0, 1, 0), Parent = tag })
		UI.label(string.upper(pass.name), 40, {
			Name = "Name",
			Position = UDim2.new(0, 236, 0, 48),
			Size = UDim2.new(1, -470, 0, 44),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = banner,
		})
		for j, line in pass.contents do
			UI.label(`• {line}`, 15, {
				Name = `Line{j}`,
				Position = UDim2.new(0, 238, 0, 94 + (j - 1) * 22),
				Size = UDim2.new(1, -474, 0, 20),
				Font = UIConfig.bodyFont,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = banner,
			})
		end
		local owned = type(profile.passes) == "table" and table.find(profile.passes, pass.key) ~= nil
		local label = if owned then "OWNED" elseif pass.id == 0 then "UNAVAILABLE" else price(Enum.InfoType.GamePass, pass.id)
		local button = UI.chunky(label, C.play, nil, {
			Name = "Action",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -20, 0.5, 0),
			Size = UDim2.new(0, 200, 0, 60),
			TextSize = 24,
			Parent = banner,
		})
		UI.setEnabled(button, not owned and pass.id ~= 0)
		UI.onClick(button, function()
			pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.id)
		end)
	end
end

local WEAPON_CARD_HEIGHT = 326

local function weaponsPart(parent: Frame)
	local profile = LockerController.profile or {}
	local level, coins = number("Level", 1), number("Coins", 0)
	local cards = grid(parent, 48, 4, WEAPON_CARD_HEIGHT)
	-- Each stat's bar is a share of the best in the shop.
	local best = { gas = 0, range = 0, rate = 0 }
	for _, id in WeaponConfig.order do
		local weapon = WeaponConfig.weapons[id]
		best.gas = math.max(best.gas, weapon.gasPerHit)
		best.range = math.max(best.range, weapon.range)
		best.rate = math.max(best.rate, 1 / weapon.fireInterval)
	end
	for i, id in WeaponConfig.order do
		local weapon = WeaponConfig.weapons[id]
		local owned = owns(profile.ownedWeapons, id)
		local box = card(cards, id, i, WEAPON_CARD_HEIGHT, weapon.tracerColor)
		text(box, weapon.displayName, 22, 1, { Name = "WeaponName" })
		-- The weapon itself in a window, turning slowly (still with reduce
		-- motion); a lock over it until the player's level reaches it.
		local window = UI.new("Frame", {
			Name = "Window",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 92),
			BackgroundColor3 = Color3.fromRGB(14, 12, 22),
			BackgroundTransparency = 0.35,
			Parent = box,
		}, { UI.corner(10) })
		local preview = WeaponView.new(id, {
			Name = "Preview",
			Size = UDim2.new(1, 0, 1, 0),
			Parent = window,
		})
		table.insert(previews, preview)
		if level < weapon.level then
			UI.new("Frame", {
				Name = "Locked",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.45,
				ZIndex = 2,
				Parent = window,
			}, {
				UI.corner(10),
				UI.label(`🔒 LEVEL {weapon.level}`, 20, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 }),
			})
		elseif owned then
			UI.label(if profile.equippedWeapon == id then "✅" else "✔", 18, {
				Name = "Owned",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 2),
				Size = UDim2.new(0, 26, 0, 24),
				Parent = window,
			})
		end
		local bar = Color3.fromRGB(255, 225, 90)
		local projectile = if weapon.projectile == "lob" then "lobbed" else "instant"
		statBar(box, "GAS", `{weapon.gasPerHit}% (head {weapon.headshotGas}%)`, weapon.gasPerHit / best.gas, 4, bar)
		statBar(box, "RANGE", `{weapon.range} · {projectile}`, weapon.range / best.range, 5, bar)
		statBar(box, "RATE", `{string.format("%.1f", 1 / weapon.fireInterval)}/s`, (1 / weapon.fireInterval) / best.rate, 6, bar)
		local mastery = profile.mastery and profile.mastery[id]
		local kills = if type(mastery) == "table" then tonumber(mastery.eliminations) or 0 else 0
		local nextMilestone = nil
		for _, milestone in ProgressionConfig.mastery do
			if kills < milestone.eliminations then
				nextMilestone = milestone
				break
			end
		end
		text(box, `Handling: {LockerController.handling(weapon)}`, 12, 7, { Name = "Details" })
		text(box, if nextMilestone then `🏅 Mastery {kills}/{nextMilestone.eliminations}` else `🏅 Mastery {kills} (all badges)`, 12, 8, { Name = "Mastery" })
		if owned and profile.equippedWeapon == id then
			actionButton(box, "EQUIPPED", false)
		elseif owned then
			actionButton(box, "EQUIP", true, function()
				LockerController.request("equip", "weapon", id)
			end, EQUIP_BLUE)
		elseif level < weapon.level then
			actionButton(box, `LEVEL {weapon.level}`, false)
		elseif coins < LockerController.priceOf(id) then
			actionButton(box, `{LockerController.priceOf(id)} COINS`, false)
		else
			actionButton(box, `BUY {LockerController.priceOf(id)}`, profile.saving ~= false, function()
				LockerController.confirmBuy(id)
			end)
		end
	end
end

local DAILY_TILE_HEIGHT = 200

-- Today's cosmetics: a tile each in its rarity's colour, what it is, how it
-- looks, and its price (or OWNED).
local function dailyPart(parent: Frame)
	local p = LockerController.parts
	local profile = LockerController.profile or {}
	local now = LockerController.now()
	shownDay = DailyShopConfig.day(now)
	p.dailyTimer = UI.label(`⏳ Refreshes in {DailyShopConfig.countdown(DailyShopConfig.secondsLeft(now))}`, 20, {
		Name = "Timer",
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Color3.fromRGB(232, 138, 245),
		Parent = parent,
	})
	local coins = number("Coins", 0)
	local tiles = grid(parent, 76, DailyShopConfig.SLOTS, DAILY_TILE_HEIGHT)
	for i, item in DailyShopConfig.today(now) do
		local cosmetic = ProgressionConfig.cosmetics[item.id]
		local rarity = DailyShopConfig.rarities[item.rarity]
		if cosmetic then
			local tile = UI.box(item.id, rarity.color, UDim2.new(1, 0, 1, 0), { LayoutOrder = i, Parent = tiles })
			UI.springy(tile, 1.04)
			UI.label(cosmetic.name, 17, {
				Name = "ItemName",
				Position = UDim2.new(0, 8, 0, 8),
				Size = UDim2.new(1, -16, 0, 22),
				TextScaled = true,
				Parent = tile,
			})
			UI.label(`{rarity.label} {KIND_NAMES[cosmetic.kind]}`, 12, {
				Name = "Kind",
				Position = UDim2.new(0, 8, 0, 31),
				Size = UDim2.new(1, -16, 0, 16),
				Font = UIConfig.bodyFont,
				Parent = tile,
			})
			local window = UI.new("Frame", {
				Name = "Window",
				Position = UDim2.new(0, 8, 0, 52),
				Size = UDim2.new(1, -16, 0, 90),
				BackgroundColor3 = Color3.fromRGB(14, 12, 22),
				BackgroundTransparency = 0.45,
				Parent = tile,
			}, { UI.corner(10) })
			swatch(item.id, window)
			local owned = type(profile.ownedCosmetics) == "table" and ProgressionConfig.ownsCosmetic(profile.ownedCosmetics, item.id)
			local cost = `💰 {UI.commas(item.price)}`
			local button = if owned
				then actionButton(tile, "OWNED", false)
				else actionButton(tile, cost, coins >= item.price and profile.saving ~= false, function()
					LockerController.confirmCosmetic(item.id)
				end)
			button.AnchorPoint = Vector2.new(0.5, 1)
			button.Position = UDim2.new(0.5, 0, 1, -8)
			button.Size = UDim2.new(1, -16, 0, 40)
			button.TextSize = 19
		end
	end
end

local COIN_CARD_HEIGHT = 176

local function coinsPart(parent: Frame)
	local packs = grid(parent, 48, #MonetizationConfig.products, COIN_CARD_HEIGHT)
	for i, product in MonetizationConfig.products do
		local box = UI.box(product.key, Color3.fromRGB(255, 205, 50), UDim2.new(1, 0, 1, 0), { LayoutOrder = i, Parent = packs })
		UI.springy(box, 1.03)
		UI.label(string.rep("💰", i), 36, { Name = "Icon", Position = UDim2.new(0, 0, 0, 8), Size = UDim2.new(1, 0, 0, 44), Parent = box })
		UI.label(string.upper(product.name), 28, { Name = "Name", Position = UDim2.new(0, 0, 0, 58), Size = UDim2.new(1, 0, 0, 32), Parent = box })
		local button = UI.chunky(if product.id == 0 then "UNAVAILABLE" else price(Enum.InfoType.Product, product.id), C.play, nil, {
			Name = "Action",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -28, 0, 46),
			TextSize = 20,
			Parent = box,
		})
		UI.setEnabled(button, product.id ~= 0)
		UI.onClick(button, function()
			pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, product.id)
		end)
	end
	UI.label("Everything here is cosmetic or coins: nothing you can buy makes your weapons stronger.", 14, {
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		Parent = parent,
	})
end

-- Canvas positions are in screen pixels, so the HUD size scales them.
local function canvasScale(scroll: ScrollingFrame): number
	local height = scroll.CanvasSize.Y.Offset
	local absolute = scroll.AbsoluteCanvasSize.Y
	return if height > 0 and absolute > 0 then absolute / height else 1
end

-- The rail lights the part in view.
local function lightRail()
	local p = LockerController.parts
	for id, button in p.railButtons do
		local lit = id == LockerController.section
		button.Border.Color = if lit then C.text else C.stroke
		button.Border.Thickness = if lit then 4 else 3
	end
end

-- Which part is in view: the last to start above the window's top (the last
-- of all at the bottom, since short ones can't reach the top).
local function sectionInView(scroll: ScrollingFrame): string
	local y = scroll.CanvasPosition.Y / canvasScale(scroll)
	local window, canvas = scroll.AbsoluteWindowSize.Y, scroll.AbsoluteCanvasSize.Y
	local list = UIConfig.shopSections
	if canvas > 0 and window > 0 and scroll.CanvasPosition.Y >= canvas - window - 2 then
		return list[#list].id
	end
	local current = list[1].id
	for _, entry in list do
		if sectionTops[entry.id] and sectionTops[entry.id] <= y + 60 then
			current = entry.id
		end
	end
	return current
end

-- Scrolls the shop to one of its parts.
function LockerController.jump(id: string, instant: boolean?)
	local p = LockerController.parts
	local top = sectionTops[id]
	local scroll = p.shop
	if not top or not scroll or not scroll.Parent then
		return
	end
	local target = Vector2.new(0, top * canvasScale(scroll))
	if instant then
		scroll.CanvasPosition = target
	else
		TweenService:Create(scroll, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = target }):Play()
	end
	LockerController.section = id
	lightRail()
end

-- The shop: its parts down one scrolling page.
local function shopTab(content: Frame)
	local p = LockerController.parts
	local scroll = UI.new("ScrollingFrame", {
		Name = "Shop",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.muted,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = content,
	})
	p.shop = scroll
	table.clear(sectionTops)
	local heights = {
		Featured = #MonetizationConfig.passes * (FEATURED_HEIGHT + 12) - 12,
		Weapons = 48 + rows(#WeaponConfig.order, 4, WEAPON_CARD_HEIGHT),
		Daily = 76 + DAILY_TILE_HEIGHT,
		Coins = 48 + COIN_CARD_HEIGHT + 30,
	}
	local parts = { Featured = featuredPart, Weapons = weaponsPart, Daily = dailyPart, Coins = coinsPart }
	local titles = { Weapons = "WEAPONS", Daily = "DAILY COSMETICS", Coins = "COINS" }
	local top = 6
	for _, entry in UIConfig.shopSections do
		sectionTops[entry.id] = top
		local part = UI.new("Frame", {
			Name = entry.id,
			Position = UDim2.new(0, 4, 0, top),
			Size = UDim2.new(0, SHOP_WIDTH, 0, heights[entry.id]),
			BackgroundTransparency = 1,
			Parent = scroll,
		})
		if titles[entry.id] then
			heading(part, titles[entry.id])
		end
		parts[entry.id](part)
		top += heights[entry.id] + SECTION_GAP
	end
	scroll.CanvasSize = UDim2.new(0, 0, 0, top - SECTION_GAP + 10)
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local id = sectionInView(scroll)
		if id ~= LockerController.section then
			LockerController.section = id
			lightRail()
		end
	end)
end

-- The daily part's countdown, each frame the shop shows (a new day: a new
-- shop).
local function tickDaily()
	local p = LockerController.parts
	if not LockerController.isOpen or LockerController.tab ~= "Weapons" or not p.dailyTimer or not p.dailyTimer.Parent then
		return
	end
	local now = LockerController.now()
	if DailyShopConfig.day(now) ~= shownDay then
		render()
		return
	end
	local value = `⏳ Refreshes in {DailyShopConfig.countdown(DailyShopConfig.secondsLeft(now))}`
	if p.dailyTimer.Text ~= value then
		p.dailyTimer.Text = value
	end
end
LockerController.tickDaily = tickDaily

local function progressionTab(content: Frame)
	local profile = LockerController.profile or {}
	local level = number("Level", 1)
	local left = UI.new("Frame", {
		Name = "Track",
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundTransparency = 1,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 2) })
	text(left, `LEVEL {level}`, 26, 1, { Name = "Level", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.accent })
	text(left, `{number("XP", 0)} / {number("XPToNext", ProgressionConfig.xpToNext(level))} XP · {number("LifetimeXP", 0)} lifetime`, 15, 2, { TextXAlignment = Enum.TextXAlignment.Left })
	text(left, `{number("Coins", 0)} coins`, 15, 3, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 210, 70) })
	text(left, `Next: {ProgressController.nextGoal(level)}`, 15, 4, { Name = "Goal", TextXAlignment = Enum.TextXAlignment.Left })
	-- Prestige, when the server has it on (FeatureFlags.PRESTIGE).
	if workspace:GetAttribute("PrestigeOpen") == true then
		local rank = number("Prestige", 0)
		if level >= PrestigeConfig.REQUIRED_LEVEL and rank < PrestigeConfig.MAX_RANK then
			local button = UI.button(`PRESTIGE {rank + 1}...`, Color3.fromRGB(230, 110, 40), {
				Name = "Prestige",
				LayoutOrder = 5,
				Size = UDim2.new(0, 220, 0, 32),
				TextSize = 16,
				Parent = left,
			})
			UI.onClick(button, function()
				LockerController.close()
				PrestigeController.open()
			end)
		else
			local label = if rank >= PrestigeConfig.MAX_RANK then `Prestige {rank}: the highest rank`
				else `Prestige at level {PrestigeConfig.REQUIRED_LEVEL}: start again for a badge and cosmetics, no power.`
			text(left, if rank > 0 and rank < PrestigeConfig.MAX_RANK then `Prestige {rank} · ` .. label else label, 13, 5, {
				Name = "Prestige",
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 160, 70),
			})
		end
	end
	local levels = {}
	for at in ProgressionConfig.unlocks do
		table.insert(levels, at)
	end
	table.sort(levels)
	for i, at in levels do
		local reached = level >= at
		text(left, `{if reached then "✓" else "·"} Level {at}: {ProgressionConfig.unlocks[at].text}`, 14, 10 + i, {
			Name = `Unlock{at}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if reached then C.accent else C.muted,
		})
	end

	local right = UI.new("Frame", {
		Name = "Stats",
		Position = UDim2.new(0.5, 6, 0, 0),
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundTransparency = 1,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 2) })
	local stats = type(profile.stats) == "table" and profile.stats or {}
	local minutes = math.floor((tonumber(stats.playtime) or 0) / 60)
	text(right, "STATS", 18, 1, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.accent })
	for i, line in {
		`Eliminations {stats.eliminations or 0} · deaths {stats.deaths or 0}`,
		`Best streak {stats.bestStreak or 0}`,
		`Played {minutes // 60}h {minutes % 60}m`,
	} do
		text(right, line, 15, 1 + i, { TextXAlignment = Enum.TextXAlignment.Left })
	end
	local badges = if type(profile.badges) == "table" and #profile.badges > 0 then table.concat(profile.badges, ", ") else "None yet"
	text(right, "BADGES", 18, 10, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.accent })
	text(right, badges, 14, 11, { Name = "Badges", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 40) })
	text(right, "COSMETICS", 18, 20, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.accent })
	-- Three rows show; the rest scroll.
	local grid = UI.new("ScrollingFrame", {
		Name = "Cosmetics",
		LayoutOrder = 21,
		Size = UDim2.new(1, 0, 0, 3 * 44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = right,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.new(0, 112, 0, 40),
			CellPadding = UDim2.new(0, 6, 0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local equippedBy = {
		tracer = profile.equippedCosmetic,
		trail = profile.equippedTrail,
		emote = profile.equippedEmote or "Toot",
		boom = profile.equippedBoom,
	}
	for i, id in ProgressionConfig.cosmeticOrder do
		local cosmetic = ProgressionConfig.cosmetics[id]
		local owned = type(profile.ownedCosmetics) == "table" and ProgressionConfig.ownsCosmetic(profile.ownedCosmetics, id)
		local equipped = equippedBy[cosmetic.kind] == id
		local color = cosmetic.tracerColor or cosmetic.trailColor or cosmetic.boomColor or C.text
		local name = if cosmetic.kind == "emote" then `{cosmetic.emoji} {cosmetic.name}` else cosmetic.name
		local label = if not owned then string.upper(cosmetic.source) elseif equipped then `{name} ✓` else name
		local button = UI.button(label, if equipped then Color3.fromRGB(70, 64, 92) else C.panelLight, {
			Name = id,
			LayoutOrder = i,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = if owned then color else C.muted,
		})
		button.Parent = grid
		-- Owned: equip it; equipped (a tracer or trail): take it off.
		local canToggle = equipped and cosmetic.kind ~= "emote"
		UI.setEnabled(button, owned and (not equipped or canToggle) and not LockerController.busy)
		UI.onClick(button, function()
			if equipped then
				LockerController.request("equip", cosmetic.kind, nil)
			else
				LockerController.request("equip", "cosmetic", id)
			end
		end)
	end
end

local VOLUME_STEP = 0.25
local HUD_SIZES = { 0.8, 0.9, 1, 1.1, 1.25 }

local function settingsTab(content: Frame)
	-- Everything scrolls in one list.
	local list = UI.new("ScrollingFrame", {
		Name = "Settings",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 6) })
	local toggles = {
		{ key = "reducedEffects", name = "ReducedEffects", label = "REDUCED EFFECTS", note = "Fewer puffs and clouds (stink clouds that gas you always show)." },
		{ key = "lowDetail", name = "LowDetail", label = "LOW DETAIL", note = "No shadows and fewer effects, for slower PCs." },
		{ key = "reduceMotion", name = "ReduceMotion", label = "REDUCE MOTION", note = "Still spectator shots, no pulsing outlines, softer explosions." },
		{ key = "teamSymbols", name = "TeamSymbols", label = "TEAM SYMBOLS", note = "▲ and ● next to names and over teammates, not just colour." },
		{ key = "sound", name = "Sound", label = "SOUND EFFECTS", note = "The game's sounds (Roblox's own volume still applies)." },
		{ key = "tips", name = "Tips", label = "TIPS", note = "A short hint now and then, never mid-fight." },
	}
	local function row(name: string, order: number): Frame
		return UI.new("Frame", {
			Name = name .. "Row",
			LayoutOrder = order,
			Size = UDim2.new(1, -10, 0, 38),
			BackgroundTransparency = 1,
			Parent = list,
		})
	end
	local function note(parent: Instance, value: string)
		UI.label(value, 13, {
			Name = "Note",
			Position = UDim2.new(0, 312, 0, 0),
			Size = UDim2.new(1, -312, 1, 0),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.muted,
			Font = UIConfig.bodyFont,
			Parent = parent,
		})
	end
	-- A row with - and + around a value.
	local function stepper(name: string, order: number, label: string, onStep: (number) -> (), help: string)
		local holder = row(name, order)
		local down = UI.chunky("-", C.panelLight, nil, { Name = name .. "Down", Size = UDim2.new(0, 44, 0, 38), TextSize = 26, Parent = holder })
		UI.onClick(down, function()
			onStep(-1)
		end)
		UI.label(label, 17, {
			Name = name,
			Position = UDim2.new(0, 50, 0, 0),
			Size = UDim2.new(0, 200, 1, 0),
			Parent = holder,
		})
		local up = UI.chunky("+", C.panelLight, nil, { Name = name .. "Up", Position = UDim2.new(0, 256, 0, 0), Size = UDim2.new(0, 44, 0, 38), TextSize = 26, Parent = holder })
		UI.onClick(up, function()
			onStep(1)
		end)
		note(holder, help)
	end
	for i, toggle in toggles do
		local holder = row(toggle.name, i)
		local on = (Settings :: any)[toggle.key]
		-- Green when on, grey when off.
		local button = UI.chunky(`{toggle.label}: {if on then "ON" else "OFF"}`, if on then C.play else C.panelLight, nil, {
			Name = toggle.name,
			Size = UDim2.new(0, 300, 0, 38),
			TextSize = 17,
			Parent = holder,
		})
		UI.onClick(button, function()
			(Settings :: any)[toggle.key] = not (Settings :: any)[toggle.key]
			Settings.chosen[toggle.key] = true
			if toggle.key == "lowDetail" then
				Detail.apply()
			end
			render()
		end)
		note(holder, toggle.note)
	end
	stepper("Volume", #toggles + 1, `VOLUME {math.floor(Settings.volume * 100 + 0.5)}%`, function(by)
		Settings.volume = math.clamp(Settings.volume + by * VOLUME_STEP, 0, 1)
		Settings.chosen.volume = true
		render()
	end, "The game's sound effects, on top of Roblox's own volume.")
	stepper("HudSize", #toggles + 2, `HUD SIZE {math.floor(Settings.hudScale * 100 + 0.5)}%`, function(by)
		local index = table.find(HUD_SIZES, Settings.hudScale) or 3
		Settings.hudScale = HUD_SIZES[math.clamp(index + by, 1, #HUD_SIZES)]
		Settings.chosen.hudScale = true
		UI.applyScale()
		render()
	end, "Bigger or smaller panels and text, everywhere.")
	-- A code box (the admin code; the server checks it).
	local codeRow = row("Code", #toggles + 3)
	local codeBox = UI.new("TextBox", {
		Name = "CodeBox",
		Size = UDim2.new(0, 200, 0, 38),
		BackgroundColor3 = Color3.fromRGB(20, 18, 30),
		Text = "",
		PlaceholderText = "ENTER CODE",
		PlaceholderColor3 = C.muted,
		TextColor3 = C.text,
		Font = UIConfig.font,
		TextSize = 17,
		ClearTextOnFocus = false,
		Parent = codeRow,
	}, { UI.corner(10), UI.stroke(C.stroke, 3) })
	local redeem = UI.chunky("REDEEM", C.play, nil, {
		Name = "Redeem",
		Position = UDim2.new(0, 206, 0, 0),
		Size = UDim2.new(0, 94, 0, 38),
		TextSize = 16,
		Parent = codeRow,
	})
	local function submit()
		local code = codeBox.Text
		if code ~= "" then
			LockerController.request("redeem", code)
		end
	end
	UI.onClick(redeem, submit)
	codeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)
	note(codeRow, "Got a code? Type it here.")
	text(list, "CONTROLS", 18, 20, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.accent })
	local controls = {}
	for _, entry in UIConfig.controls do
		table.insert(controls, `{entry[1]} {entry[2]}`)
	end
	text(list, table.concat(controls, "  ·  "), 14, 21, {
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -10, 0, 60),
	})
	text(list, `Version {ReleaseConfig.label(workspace:GetAttribute("ReleaseChannel") :: any)}`, 13, 22, {
		Name = "Version",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.muted,
	})
end

local TABS = { Weapons = shopTab, Progression = progressionTab, Settings = settingsTab }
-- The page drawn last, and where the shop was scrolled to (kept when it's
-- drawn again for new coins or a purchase).
local drawnTab: string? = nil

render = function()
	local p = LockerController.parts
	if not LockerController.isOpen then
		return
	end
	-- The open page's tab is lit; the header takes its colour and name.
	for name, button in p.tabs do
		local selected = name == LockerController.tab
		button.Border.Color = if selected then C.text else C.stroke
		button.Border.Thickness = if selected then 4 else 3
	end
	UI.setBadge(p.tabs.Weapons, LockerController.buyable())
	UI.setBadge(p.tabs.Loadout, LockerController.newAbilities())
	local page = UIConfig.pages[LockerController.tab]
	UI.paint(p.header, page.color)
	p.title.Text = `{page.icon} {page.label}`
	p.wallet.Text = `💰 {UI.commas(number("Coins", 0))}`
	local scrolled = if drawnTab == "Weapons" and LockerController.tab == "Weapons" and p.shop then p.shop.CanvasPosition else nil
	for _, child in p.content:GetChildren() do
		child:Destroy()
	end
	table.clear(previews)
	p.shop, p.dailyTimer = nil, nil
	TABS[LockerController.tab](p.content)
	drawnTab = LockerController.tab
	p.rail.Visible = LockerController.tab == "Weapons"
	if scrolled and p.shop then
		p.shop.CanvasPosition = scrolled
	end
	lightRail()
	for _, preview in previews do
		WeaponView.spin(preview, turn)
	end
end
LockerController.render = render

local function build()
	local p = LockerController.parts
	local screen = UI.screen("Locker", 15)
	screen.Enabled = false
	p.screen = screen
	UI.new("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Parent = screen,
	})
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 940, 0, 600),
		BackgroundColor3 = C.panel,
		Parent = screen,
	}, { UI.corner(22), UI.stroke(C.stroke, 5) })
	p.panel = panel
	-- The header: the page's name on its colour, and your coins.
	-- (UI.paint recolours its Fill.)
	p.header = UI.new("Frame", {
		Name = "Header",
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(1, -24, 0, 62),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		UI.corner(16),
		UI.stroke(C.stroke, 3),
		UI.new("Frame", {
			Name = "Fill",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, { UI.corner(16), UI.new("UIGradient", { Name = "Gloss", Rotation = 90 }) }),
	})
	p.title = UI.label("", 40, {
		Name = "Title",
		Position = UDim2.new(0, 18, 0, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = p.header,
	})
	p.wallet = UI.label("", 28, {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -64, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UIConfig.gold,
		ZIndex = 2,
		Parent = p.header,
	})
	local tabs = UI.new("Frame", {
		Name = "Tabs",
		Position = UDim2.new(0, 12, 0, 84),
		Size = UDim2.new(1, -24, 0, 48),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	p.tabs = {}
	for i, name in UIConfig.menuSections do
		local page = UIConfig.pages[name]
		local button = UI.chunky(page.label, page.color, page.icon, {
			Name = name,
			LayoutOrder = i,
			Size = UDim2.new(0, 152, 0, 46),
			TextSize = 20,
			Parent = tabs,
		})
		p.tabs[name] = button
		UI.onClick(button, function()
			LockerController.open(name)
		end)
	end
	-- The red X on the corner. Modal frees the mouse from first person
	-- while the locker is up.
	local close = UI.chunky("X", Color3.fromRGB(235, 55, 60), nil, {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.new(0, 56, 0, 56),
		TextSize = 32,
		Modal = true,
		Parent = panel,
	})
	UI.onClick(close, LockerController.close)
	-- The shop's rail, outside the window's left edge: a tile per part.
	p.rail = UI.new("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0, 2, 0, 146),
		Size = UDim2.new(0, 80, 0, #UIConfig.shopSections * 82),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right) })
	p.railButtons = {}
	for i, entry in UIConfig.shopSections do
		local button = UI.tile(entry.icon, entry.label, entry.color, {
			Name = entry.id,
			LayoutOrder = i,
			Size = UDim2.new(0, 76, 0, 74),
			Parent = p.rail,
		})
		p.railButtons[entry.id] = button
		UI.onClick(button, function()
			LockerController.jump(entry.id)
		end)
	end
	p.content = UI.new("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 16, 0, 146),
		Size = UDim2.new(1, -32, 1, -184),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	p.status = UI.label("", 15, {
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -8),
		Size = UDim2.new(1, -36, 0, 22),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	-- "Buy it?": over the shop until YES or NO.
	p.confirm = UI.new("Frame", {
		Name = "Confirm",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	})
	p.confirmCard = UI.box("Card", UIConfig.pages.Weapons.color, UDim2.new(0, 440, 0, 330), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Parent = p.confirm,
	})
	p.confirmTitle = UI.label("", 30, { Name = "Title", Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 0, 36), Parent = p.confirmCard })
	p.confirmPreview = UI.new("Frame", {
		Name = "Preview",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(0, 300, 0, 110),
		BackgroundColor3 = Color3.fromRGB(14, 12, 22),
		BackgroundTransparency = 0.35,
		Parent = p.confirmCard,
	}, { UI.corner(12) })
	p.confirmPrice = UI.label("", 34, { Name = "Price", Position = UDim2.new(0, 0, 0, 172), Size = UDim2.new(1, 0, 0, 38), TextColor3 = UIConfig.gold, Parent = p.confirmCard })
	p.confirmLeft = UI.label("", 16, { Name = "Left", Position = UDim2.new(0, 0, 0, 210), Size = UDim2.new(1, 0, 0, 22), Font = UIConfig.bodyFont, Parent = p.confirmCard })
	p.confirmYes = UI.chunky("YES, BUY!", C.play, "✅", {
		Name = "Yes",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -95, 1, -18),
		Size = UDim2.new(0, 180, 0, 56),
		TextSize = 24,
		Parent = p.confirmCard,
	})
	UI.onClick(p.confirmYes, function()
		local id, kind = p.confirmId, p.confirmKind
		LockerController.closeConfirm()
		if id then
			LockerController.request("buy", kind or "weapon", id)
		end
	end)
	p.confirmNo = UI.chunky("NO", Color3.fromRGB(235, 55, 60), "✖️", {
		Name = "No",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 95, 1, -18),
		Size = UDim2.new(0, 160, 0, 56),
		TextSize = 24,
		Parent = p.confirmCard,
	})
	UI.onClick(p.confirmNo, LockerController.closeConfirm)
end

-- Opens a page (and on the shop, scrolls to `section`). "Store" is the
-- shop's Featured part; "Loadout" (and the old "Abilities") the loadout
-- screen.
function LockerController.open(tab: string?, section: string?)
	local p = LockerController.parts
	if tab == "Store" then
		tab, section = "Weapons", section or "Featured"
	elseif tab == "Abilities" then
		tab = "Loadout"
	end
	if tab == "Loadout" then
		LockerController.hide()
		if LockerController.loadout then
			LockerController.loadout.open()
		end
		return
	end
	if LockerController.loadout then
		LockerController.loadout.close()
	end
	if tab and TABS[tab] then
		if tab ~= LockerController.tab then
			drawnTab = nil
		end
		LockerController.tab = tab
	end
	if not LockerController.isOpen then
		setStatus(if LockerController.profile and LockerController.profile.saving == false
			then "Progress isn't saving this session: the shop is closed."
			else "")
	end
	if not LockerController.isOpen then
		UI.pop(p.panel, 0.85)
	end
	if not LockerController.isOpen then
		drawnTab = nil
	end
	LockerController.isOpen = true
	p.screen.Enabled = true
	render()
	if section and LockerController.tab == "Weapons" then
		LockerController.jump(section, true)
	end
end

-- Hides the locker (only: the loadout opening over it).
function LockerController.hide()
	LockerController.isOpen = false
	LockerController.closeConfirm()
	LockerController.parts.screen.Enabled = false
end

-- Closes the locker and the loadout.
function LockerController.close()
	LockerController.hide()
	if LockerController.loadout then
		LockerController.loadout.close()
	end
end

function LockerController.start()
	if started then
		return
	end
	started = true
	build()
	-- The weapon previews turn while the locker shows them.
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		tickDaily()
		if LockerController.isOpen and #previews > 0 and not Settings.reduceMotion then
			turn = (turn + dt * LockerController.SPIN_SPEED) % 360
			for _, preview in previews do
				if preview.Parent then
					WeaponView.spin(preview, turn)
				end
			end
		end
	end)
	local function arrived(view: { [string]: any })
		LockerController.profile = view
		-- What the player already has when they join isn't news.
		if not seenAbilities then
			seeAbilities()
		end
		render()
		LockerController.ProfileChanged:Fire(view)
		LockerController.BadgesChanged:Fire()
	end
	local remote = ClientState.remote("ProfileUpdate") :: RemoteEvent
	remote.OnClientEvent:Connect(function(view)
		if type(view) == "table" then
			arrived(view)
		end
	end)
	-- The first look (a push can arrive before this script listens).
	task.spawn(function()
		local shopRequest = ClientState.remote("ShopRequest") :: RemoteFunction
		local ok, answer = pcall(shopRequest.InvokeServer, shopRequest, "profile", "all")
		if ok and type(answer) == "table" and type(answer.profile) == "table" and not LockerController.profile then
			arrived(answer.profile)
		end
	end)
	for _, name in { "Coins", "Level", "XP" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			render()
			LockerController.BadgesChanged:Fire()
		end)
	end
	-- Pressing PLAY, spectating or going AFK closes it.
	ClientState.StateChanged:Connect(LockerController.close)
end

return LockerController
