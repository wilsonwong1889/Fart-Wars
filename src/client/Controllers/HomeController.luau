-- The home screen and the M menu.
--   HomeScreen  shown whenever the player isn't on a team (just joined,
--               spectating, AFK), over the live battlefield (blurred, so
--               the menu reads), laid out like a game lobby: big buttons
--               for the locker's pages down the left (Loadout, Shop,
--               Levels; a red badge counts what's waiting), tiles down the
--               right (Daily, Spin, Season, Players, Top, Settings), coins
--               top right, level bottom left; in the middle the featured
--               offers (two at a time, arrows for more), the title, PLAY
--               (or Space or F; a bubble points at it for someone who
--               hasn't played yet) and the round's status. The
--               later-phase screens say Coming Soon
--   TeamSelect  after PLAY: "CHOOSE A TEAM", each team's card with its
--               count (locked when joining it would make the teams
--               unfair), and AUTO; picking one joins the match
--   GameMenu    M in a match: resume, switch team (only when it evens the
--               teams), spectate, and the same sections. The mouse is free
--               while it's open, even in first person.
-- Every one of them frees the mouse from the crosshair while it shows
-- (MouseLock, each under its own name; the team screen only opens over the
-- home screen, so the home screen's covers it).
-- Buttons only send intent; the server decides, and the screens follow
-- the player's State attribute.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local States = require(Shared.States)
local TeamBalance = require(Shared.TeamBalance)
local RoundClock = require(Shared.RoundClock)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local MouseLock = require(Client.MouseLock)
local InputController = require(script.Parent.InputController)
local HUDController = require(script.Parent.HUDController)
local LockerController = require(script.Parent.LockerController)
local RewardsController = require(script.Parent.RewardsController)
local PlayersController = require(script.Parent.PlayersController)
local SeasonController = require(script.Parent.SeasonController)
local ReleaseConfig = require(Shared.Config.ReleaseConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local DailyShopConfig = require(Shared.Config.DailyShopConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponView = require(Client.WeaponView)

local C = UIConfig.colors
local Phase = States.Phase
-- How many of today's cosmetics the lobby's daily card shows.
local DAILY_CARD_ITEMS = 3

local HomeController = {}

HomeController.parts = {} :: { [string]: any }
-- The home screen's team choice: a team ID, or nil for automatic.
HomeController.selectedTeam = nil :: string?
HomeController.menuOpen = false

local started = false
local playCooldownUntil = 0

local function otherTeam(team: string?): string?
	for _, id in TeamConfig.order do
		if id ~= team then
			return id
		end
	end
	return nil
end

-- Shows or hides the Coming Soon card, freeing the mouse while it's up.
local function showComingSoon(on: boolean)
	HomeController.parts.comingSoon.Enabled = on
	MouseLock.setFree("ComingSoon", on)
end

local function openComingSoon(section: string)
	local p = HomeController.parts
	p.soonTitle.Text = string.upper(section)
	showComingSoon(true)
end

-- What a home-screen tile opens.
local function openTile(id: string)
	if id == "Rewards" then
		RewardsController.openDaily()
	elseif id == "Spin" then
		RewardsController.openSpin()
	elseif id == "Season" then
		SeasonController.open()
	elseif id == "Players" then
		PlayersController.open()
	elseif UIConfig.pages[id] then
		LockerController.open(id)
	else
		openComingSoon(id)
	end
end

-- The M menu's list: the locker's pages, then Players, Rewards and what's
-- coming, each a chunky button with its icon.
local function sectionButtons(parent: Instance, width: number)
	local function add(name: string, label: string, icon: string, color: Color3, order: number, onClick: () -> ())
		local button = UI.chunky(label, color, icon, {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(0, width, 0, 44),
			TextSize = 20,
			Parent = parent,
		})
		UI.onClick(button, onClick)
	end
	for i, section in UIConfig.menuSections do
		local page = UIConfig.pages[section]
		add(section, page.label, page.icon, page.color, 10 + i, function()
			LockerController.open(section)
		end)
	end
	for i, tile in UIConfig.lobbyTiles do
		if tile.id == "Players" or tile.id == "Rewards" or table.find(UIConfig.comingSoon, tile.id) then
			add(tile.id, string.upper(tile.id), tile.icon, tile.color, 20 + i, function()
				openTile(tile.id)
			end)
		end
	end
end

local function versionText(): string
	return `v{ReleaseConfig.label(workspace:GetAttribute("ReleaseChannel") :: any)} · PC beta`
end

-- Season is a tile only while one is on; the rest close up around it.
local function layoutTiles()
	local p = HomeController.parts
	local y = 0
	for _, entry in UIConfig.lobbyTiles do
		local tile = p.tiles[entry.id]
		tile.Visible = entry.id ~= "Season" or workspace:GetAttribute("SeasonActive") == true
		if tile.Visible then
			tile.Position = UDim2.new(0.5, 0, 0, y + 38)
			y += 86
		end
	end
	p.tileColumn.Size = UDim2.new(0, 86, 0, y)
end

-- The featured offers: what's worth a look right now, from what the player
-- has and the server says (never made up): today's daily shop while it has
-- something they don't own, the Starter Pack until it's owned, the next
-- weapon to buy (or the level it opens at), the daily reward, free spins
-- waiting, and the season while one is on.
type Offer = {
	id: string,
	tag: string,
	title: string,
	text: string,
	action: string,
	ready: boolean,
	color: Color3,
	weapon: string?,
	-- Cosmetics on sale today, shown in place of the text and action.
	items: { string }?,
	open: () -> (),
}

local function offers(): { Offer }
	local player = Players.LocalPlayer
	local profile = LockerController.profile or {}
	local function number(name: string, default: number): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else default
	end
	local list: { Offer } = {}
	local today = {}
	local ownedCosmetics = if type(profile.ownedCosmetics) == "table" then profile.ownedCosmetics else {}
	for _, item in DailyShopConfig.today(LockerController.now()) do
		if #today < DAILY_CARD_ITEMS and not ProgressionConfig.ownsCosmetic(ownedCosmetics, item.id) then
			table.insert(today, item.id)
		end
	end
	if #today > 0 then
		table.insert(list, {
			id = "DailyShop",
			tag = "",
			title = "DAILY COSMETICS",
			text = "",
			action = "",
			ready = true,
			color = UIConfig.pages.Progression.color,
			items = today,
			open = function()
				LockerController.open("Weapons", "Daily")
			end,
		})
	end
	for _, pass in MonetizationConfig.passes do
		local owned = type(profile.passes) == "table" and table.find(profile.passes, pass.key) ~= nil
		if not owned then
			local lines = {}
			for _, line in pass.contents do
				table.insert(lines, (string.gsub(line, " %b()", "")))
			end
			table.insert(list, {
				id = pass.key,
				tag = "NEW!",
				title = string.upper(pass.name),
				text = table.concat(lines, " · "),
				action = if pass.id == 0 then "SEE STORE" else LockerController.price(Enum.InfoType.GamePass, pass.id),
				ready = true,
				color = UIConfig.pages.Progression.color,
				open = function()
					LockerController.open("Store")
				end,
			})
		end
	end
	local level, coins = number("Level", 1), number("Coins", 0)
	for _, id in WeaponConfig.order do
		local weapon = WeaponConfig.weapons[id]
		local owned = type(profile.ownedWeapons) == "table" and table.find(profile.ownedWeapons, id) ~= nil
		if not owned and LockerController.profile then
			local price = LockerController.priceOf(id)
			table.insert(list, {
				id = "Weapon",
				tag = "WEAPON",
				title = string.upper(weapon.displayName),
				text = weapon.description,
				action = if level < weapon.level then `LEVEL {weapon.level}` elseif coins < price then `{UI.commas(price)} COINS` else `BUY {UI.commas(price)}`,
				ready = level >= weapon.level and coins >= price,
				color = weapon.tracerColor,
				weapon = id,
				open = function()
					LockerController.open("Weapons")
				end,
			})
			break
		end
	end
	local daily = player:GetAttribute("DailyReady") == true
	table.insert(list, {
		id = "Daily",
		tag = "DAILY",
		title = "DAILY REWARD",
		text = "A bigger reward every day you come back.",
		action = if daily then "CLAIM!" else "OPEN",
		ready = daily,
		color = UIConfig.gold,
		open = RewardsController.openDaily,
	})
	local spins = number("Spins", 0)
	if spins > 0 then
		table.insert(list, {
			id = "Spin",
			tag = "FREE",
			title = if spins == 1 then "FREE SPIN" else `{spins} FREE SPINS`,
			text = "Spin the wheel for a prize.",
			action = "SPIN!",
			ready = true,
			color = Color3.fromRGB(165, 90, 235),
			open = RewardsController.openSpin,
		})
	end
	if workspace:GetAttribute("SeasonActive") == true then
		table.insert(list, {
			id = "Season",
			tag = "SEASON",
			title = "THE SEASON",
			text = "Play to climb the tiers: cosmetics all the way up.",
			action = "OPEN",
			ready = true,
			color = Color3.fromRGB(240, 120, 40),
			open = SeasonController.open,
		})
	end
	return list
end

local function timeLeft(): string
	return DailyShopConfig.countdown(DailyShopConfig.secondsLeft(LockerController.now()))
end

-- The daily shop's card: the time left and a few of today's cosmetics.
local function dailyCard(items: { string }, title: string, card: Instance)
	local p = HomeController.parts
	UI.label(title, 18, {
		Name = "Title",
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -104, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIConfig.gold,
		Parent = card,
	})
	p.offerTimer = UI.label(timeLeft(), 14, {
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.new(0, 84, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 154, 216),
		Parent = card,
	})
	local row = UI.new("Frame", {
		Name = "Items",
		Position = UDim2.new(0, 10, 0, 34),
		Size = UDim2.new(1, -20, 0, 96),
		BackgroundTransparency = 1,
		Parent = card,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	for i, id in items do
		local item = DailyShopConfig.item(id)
		local cosmetic = ProgressionConfig.cosmetics[id]
		if item and cosmetic then
			local tile = UI.new("Frame", {
				Name = id,
				LayoutOrder = i,
				Size = UDim2.new(0, 88, 1, 0),
				BackgroundColor3 = DailyShopConfig.rarities[item.rarity].color,
				Parent = row,
			}, { UI.corner(10), UI.stroke(C.stroke, 2) })
			local window = UI.new("Frame", {
				Name = "Window",
				Size = UDim2.new(1, 0, 0, 70),
				BackgroundTransparency = 1,
				Parent = tile,
			})
			LockerController.swatch(id, window)
			UI.label(cosmetic.name, 12, {
				Name = "ItemName",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 4, 1, -4),
				Size = UDim2.new(1, -8, 0, 18),
				TextScaled = true,
				Parent = tile,
			})
		end
	end
end

-- One offer as a card: its colour, the gun turning in it for a weapon, and
-- what clicking does (BUY 400, LEVEL 15, CLAIM!...).
local function offerCard(offer: Offer, order: number, parent: Instance)
	local h, s, v = offer.color:ToHSV()
	local card = UI.new("TextButton", {
		Name = offer.id,
		LayoutOrder = order,
		Size = UDim2.new(0, 300, 0, 140),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	}, {
		UI.corner(16),
		UI.stroke(Color3.fromHSV(h, s * 0.7, math.min(1, v * 1.2)), 3),
		UI.gradient(Color3.fromHSV(h, math.min(s, 0.8), math.min(v, 0.5)), Color3.fromHSV(h, math.min(s, 0.9), math.min(v, 0.28))),
	})
	UI.springy(card, 1.04)
	UI.onClick(card, offer.open)
	if offer.items then
		dailyCard(offer.items, offer.title, card)
		return
	end
	local left = 12
	if offer.weapon then
		local preview = WeaponView.new(offer.weapon, {
			Name = "Preview",
			Position = UDim2.new(0, 6, 0, 30),
			Size = UDim2.new(0, 120, 0, 104),
			Parent = card,
		})
		WeaponView.spin(preview, 25)
		left = 128
	end
	UI.label(offer.tag, 15, {
		Name = "Tag",
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(0, 80, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIConfig.gold,
		Parent = card,
	})
	UI.label(offer.title, 20, {
		Name = "Title",
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	UI.label(offer.text, 14, {
		Name = "Text",
		Position = UDim2.new(0, left, 0, 34),
		Size = UDim2.new(1, -left - 12, 0, 54),
		Font = UIConfig.bodyFont,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local pill = UI.new("Frame", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.new(0, 150, 0, 36),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, {
		UI.corner(11),
		UI.stroke(C.stroke, 3),
		UI.gradient(if offer.ready then Color3.fromRGB(142, 232, 106) else Color3.fromRGB(120, 116, 136), if offer.ready then Color3.fromRGB(58, 154, 28) else Color3.fromRGB(70, 66, 84)),
	})
	UI.label(offer.action, 18, { Name = "Label", Size = UDim2.new(1, 0, 1, 0), Parent = pill })
end

-- Shows two offers from `offerStart`; the arrows page through the rest.
local function renderOffers()
	local p = HomeController.parts
	local list = offers()
	p.offerDay = DailyShopConfig.day(LockerController.now())
	for _, child in p.offerRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if #list == 0 then
		p.featured.Visible = false
		return
	end
	p.featured.Visible = true
	p.offerStart = ((p.offerStart or 1) - 1) % #list + 1
	for i = 0, math.min(1, #list - 1) do
		offerCard(list[(p.offerStart - 1 + i) % #list + 1], i + 1, p.offerRow)
	end
	p.prevOffer.Visible = #list > 2
	p.nextOffer.Visible = #list > 2
	-- A price still on its way from Roblox: look again in a moment.
	for _, offer in list do
		if offer.action == "..." then
			task.delay(2, renderOffers)
			break
		end
	end
end
HomeController.renderOffers = renderOffers

-- The daily card's time left, and a new day's cosmetics at midnight.
local function tickOffers()
	local p = HomeController.parts
	if DailyShopConfig.day(LockerController.now()) ~= p.offerDay then
		renderOffers()
	elseif p.offerTimer and p.offerTimer.Parent then
		p.offerTimer.Text = timeLeft()
	end
end
HomeController.tickOffers = tickOffers

local function pageOffers(by: number)
	local p = HomeController.parts
	p.offerStart = (p.offerStart or 1) + by
	renderOffers()
end

local function build()
	local p = HomeController.parts

	-- Home screen: over the blurred battlefield, a game lobby. The locker's
	-- pages down the left, the other screens as tiles down the right, coins
	-- top right, level bottom left; in the middle the featured offers, the
	-- title, PLAY and the round's status.
	local home = UI.screen("HomeScreen", 10)
	p.home = home
	UI.new("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.stroke,
		BackgroundTransparency = 0.78,
		Parent = home,
	})
	p.blur = Lighting:FindFirstChild("MenuBlur") or UI.new("BlurEffect", { Name = "MenuBlur", Size = 0, Parent = Lighting })

	local pages = UI.new("Frame", {
		Name = "Pages",
		AnchorPoint = Vector2.new(0, 0.5),
		-- Lower than the middle: Roblox's chat box sits above.
		Position = UDim2.new(0, 24, 0.5, 40),
		Size = UDim2.new(0, 250, 0, #UIConfig.lobbyPages * 84),
		BackgroundTransparency = 1,
		Parent = home,
	})
	p.pageButtons = {}
	for i, entry in UIConfig.lobbyPages do
		local page = UIConfig.pages[entry.page]
		local button = UI.chunky(entry.label or page.label, entry.color or page.color, entry.icon or page.icon, {
			Name = entry.name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 36 + (i - 1) * 84),
			Size = UDim2.new(0, 236, 0, 70),
			TextSize = 30,
			Parent = pages,
		})
		p.pageButtons[entry.page] = button
		UI.onClick(button, function()
			LockerController.open(entry.page)
		end)
	end

	p.tileColumn = UI.new("Frame", {
		Name = "Tiles",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.new(0, 86, 0, 0),
		BackgroundTransparency = 1,
		Parent = home,
	})
	p.tiles = {}
	for _, entry in UIConfig.lobbyTiles do
		local tile = UI.tile(entry.icon, entry.label, entry.color, {
			Name = entry.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0, 76, 0, 76),
			Parent = p.tileColumn,
		})
		p.tiles[entry.id] = tile
		UI.onClick(tile, function()
			openTile(entry.id)
		end)
	end
	layoutTiles()
	workspace:GetAttributeChangedSignal("SeasonActive"):Connect(layoutTiles)

	-- Coins, top right; + opens the shop's coin packs.
	local wallet = UI.new("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 52),
		Size = UDim2.new(0, 280, 0, 50),
		BackgroundTransparency = 1,
		Parent = home,
	})
	local plus = UI.chunky("+", UIConfig.gold, nil, {
		Name = "Plus",
		Position = UDim2.new(0, 0, 0, 4),
		Size = UDim2.new(0, 42, 0, 42),
		TextSize = 30,
		Parent = wallet,
	})
	UI.onClick(plus, function()
		LockerController.open("Weapons", "Coins")
	end)
	local pill = UI.new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(1, -52, 1, 0),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.12,
		Parent = wallet,
	}, { UI.corner(25), UI.stroke(C.stroke, 3) })
	UI.label("💰", 30, { Name = "CoinIcon", Position = UDim2.new(0, 6, 0, 3), Size = UDim2.new(0, 42, 0, 42), Parent = pill })
	p.coins = UI.label("0", 32, {
		Name = "Coins",
		Position = UDim2.new(0, 52, 0, 0),
		Size = UDim2.new(1, -62, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIConfig.gold,
		Parent = pill,
	})

	-- Level, XP and the build, bottom left.
	local level = UI.new("Frame", {
		Name = "Level",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -12),
		Size = UDim2.new(0, 300, 0, 80),
		BackgroundTransparency = 1,
		Parent = home,
	})
	UI.label("⭐", 32, { Name = "Star", Size = UDim2.new(0, 44, 0, 40), Parent = level })
	p.level = UI.label("LEVEL 1", 28, {
		Name = "Level",
		Position = UDim2.new(0, 50, 0, 2),
		Size = UDim2.new(0, 240, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = level,
	})
	local xpBar = UI.new("Frame", {
		Name = "XPBar",
		Position = UDim2.new(0, 4, 0, 42),
		Size = UDim2.new(0, 236, 0, 14),
		BackgroundColor3 = Color3.fromRGB(20, 18, 30),
		Parent = level,
	}, { UI.corner(7), UI.stroke(C.stroke, 2) })
	p.xpFill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = UIConfig.pages.Progression.color,
		Parent = xpBar,
	}, { UI.corner(7) })
	-- The build, so a screenshot or report says which one it was.
	p.version = UI.label(versionText(), 13, {
		Name = "Version",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = level,
	})
	workspace:GetAttributeChangedSignal("ReleaseChannel"):Connect(function()
		p.version.Text = versionText()
	end)

	-- The middle, from the bottom up: the round's status, PLAY with its key,
	-- the title, and the featured offers.
	local center = UI.new("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, 760, 0, 600),
		BackgroundTransparency = 1,
		Parent = home,
	}, {
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	p.featured = UI.new("Frame", {
		Name = "Featured",
		LayoutOrder = 1,
		Size = UDim2.new(0, 740, 0, 214),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		Parent = center,
	}, { UI.corner(20), UI.stroke(Color3.fromRGB(54, 224, 244), 4) })
	UI.label("TODAY IN THE SHOP", 28, {
		Name = "Heading",
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 32),
		TextColor3 = C.accent,
		Parent = p.featured,
	})
	UI.label("New cosmetics every day. Pick one to preview it on your gun.", 15, {
		Name = "Subheading",
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		Parent = p.featured,
	})
	p.offerRow = UI.new("Frame", {
		Name = "Offers",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(0, 612, 0, 140),
		BackgroundTransparency = 1,
		Parent = p.featured,
	}, { UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center) })
	local function arrow(name: string, text: string, x: number, by: number): TextButton
		local button = UI.chunky(text, C.panelLight, nil, {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, if x == 0 then 30 else -30, 0, 134),
			Size = UDim2.new(0, 44, 0, 44),
			TextSize = 28,
			Parent = p.featured,
		})
		UI.onClick(button, function()
			pageOffers(by)
		end)
		return button
	end
	p.prevOffer = arrow("Previous", "<", 0, -1)
	p.nextOffer = arrow("Next", ">", 1, 1)
	p.afkNotice = UI.label("You were moved to spectators for being AFK.", 18, {
		Name = "AFKNotice",
		LayoutOrder = 2,
		TextColor3 = C.warning,
		Visible = false,
		Parent = center,
	})
	UI.label(UIConfig.title, 60, {
		Name = "Title",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 64),
		Rotation = -2,
		TextColor3 = C.accent,
		Parent = center,
	})
	-- PLAY sits in its own slot so it springs from its middle.
	local slot = UI.new("Frame", {
		Name = "PlaySlot",
		LayoutOrder = 4,
		Size = UDim2.new(0, 380, 0, 100),
		BackgroundTransparency = 1,
		Parent = center,
	})
	local play = UI.chunky("PLAY", C.play, "▶️", {
		Name = "Play",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 340, 0, 92),
		TextSize = 60,
		Parent = slot,
	})
	p.play = play
	UI.onClick(play, HomeController.play)
	-- First time here: a bubble pointing at PLAY.
	p.firstTip = UI.new("Frame", {
		Name = "FirstTip",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 14, 0.5, 0),
		Size = UDim2.new(0, 230, 0, 70),
		BackgroundColor3 = C.stroke,
		Visible = false,
		Parent = slot,
	}, { UI.corner(14), UI.stroke(C.text, 3) })
	UI.new("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, -2, 0.5, 0),
		Size = UDim2.new(0, 20, 0, 20),
		Rotation = 45,
		BackgroundColor3 = C.stroke,
		Parent = p.firstTip,
	})
	UI.label("Press PLAY, pick a team and start farting!", 17, {
		Name = "Text",
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -24, 1, 0),
		TextWrapped = true,
		Parent = p.firstTip,
	})
	p.hint = UI.label("Press Space or F", 18, {
		Name = "Hint",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = center,
	})
	-- The beta is for PC: say so on a touch screen with no keyboard (in case
	-- the place's device settings let one in).
	p.deviceNotice = UI.label("Fart Wars is a PC beta for now: it needs a mouse and keyboard.", 16, {
		Name = "DeviceNotice",
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		TextColor3 = C.warning,
		Visible = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true,
		Parent = center,
	})
	local chip = UI.new("Frame", {
		Name = "StatusChip",
		LayoutOrder = 7,
		Size = UDim2.new(0, 520, 0, 40),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.2,
		Parent = center,
	}, { UI.corner(12), UI.stroke(C.stroke, 3) })
	UI.label("⏱️", 22, {
		Name = "Clock",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.new(0, 30, 0, 30),
		Parent = chip,
	})
	p.status = UI.label("", 18, {
		Name = "Status",
		Position = UDim2.new(0, 42, 0, 0),
		Size = UDim2.new(1, -50, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = chip,
	})

	-- Choose a Team
	local teamScreen = UI.screen("TeamSelect", 13)
	teamScreen.Enabled = false
	p.teamSelect = teamScreen
	UI.new("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Parent = teamScreen,
	})
	local title = UI.new("Frame", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0, 620, 0, 86),
		BackgroundColor3 = Color3.fromRGB(14, 12, 20),
		Parent = teamScreen,
	}, { UI.corner(16), UI.stroke(Color3.fromRGB(70, 66, 84), 4) })
	UI.label("CHOOSE A TEAM", 54, { Size = UDim2.new(1, 0, 1, 0), Parent = title })
	local closeSlot = UI.new("Frame", {
		Name = "CloseSlot",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 70),
		Size = UDim2.new(0, 60, 0, 60),
		BackgroundTransparency = 1,
		Parent = teamScreen,
	})
	local close = UI.chunky("X", Color3.fromRGB(235, 55, 60), nil, {
		Name = "Close",
		Size = UDim2.new(1, 0, 1, 0),
		TextSize = 32,
		Modal = true,
		Parent = closeSlot,
	})
	UI.onClick(close, function()
		teamScreen.Enabled = false
	end)
	p.teamButtons = {}
	for i, team in TeamConfig.order do
		local config = TeamConfig.teams[team]
		local card = UI.new("TextButton", {
			Name = team,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, if i == 1 then -190 else 190, 0.5, 0),
			Size = UDim2.new(0, 280, 0, 280),
			BackgroundColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = true,
			Text = "",
			Parent = teamScreen,
		}, {
			UI.corner(26),
			UI.stroke(Color3.new(1, 1, 1), 6),
		})
		local h, sat, v = config.color:ToHSV()
		UI.gradient(Color3.fromHSV(h, sat * 0.85, math.min(1, v * 1.1)), Color3.fromHSV(h, math.min(1, sat * 1.1), v * 0.62)).Parent = card
		UI.label(`{config.symbol} {config.shortName}`, 40, { Name = "TeamName", Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(1, 0, 0, 46), Parent = card })
		-- Friends already on this team (the server counts them).
		UI.label("", 18, { Name = "Friends", Position = UDim2.new(0, 0, 0, 228), Size = UDim2.new(1, 0, 0, 22), Font = UIConfig.bodyFont, Parent = card })
		UI.label("0", 96, { Name = "Count", Position = UDim2.new(0, 0, 0, 90), Size = UDim2.new(1, 0, 0, 104), Parent = card })
		UI.label("/ 10", 22, { Name = "Max", Position = UDim2.new(0, 0, 0, 196), Size = UDim2.new(1, 0, 0, 26), Parent = card })
		UI.label("🔒", 56, {
			Name = "Lock",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 18, 1, 18),
			Size = UDim2.new(0, 70, 0, 70),
			Visible = false,
			Parent = card,
		})
		p.teamButtons[team] = card
		UI.onClick(card, function()
			HomeController.pick(team)
		end)
	end
	UI.label("VS", 64, {
		Name = "VS",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 100, 0, 70),
		Rotation = -6,
		Parent = teamScreen,
	})
	local autoSlot = UI.new("Frame", {
		Name = "AutoSlot",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 168),
		Size = UDim2.new(0, 400, 0, 56),
		BackgroundTransparency = 1,
		Parent = teamScreen,
	})
	local auto = UI.chunky("AUTO: WHERE I'M NEEDED", Color3.fromRGB(45, 155, 245), "🎲", {
		Name = "Auto",
		Size = UDim2.new(1, 0, 1, 0),
		TextSize = 22,
		Parent = autoSlot,
	})
	p.teamButtons.Auto = auto
	UI.onClick(auto, function()
		HomeController.pick(nil)
	end)
	p.teamHint = UI.label("", 16, {
		Name = "TeamHint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 228),
		Size = UDim2.new(0, 620, 0, 22),
		Font = UIConfig.bodyFont,
		TextWrapped = true,
		Parent = teamScreen,
	})

	-- M menu
	local menu = UI.screen("GameMenu", 12)
	menu.Enabled = false
	p.menu = menu
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 320, 0, 680),
		BackgroundColor3 = C.panel,
		Parent = menu,
	}, { UI.corner(20), UI.stroke(C.stroke, 4), UI.padding(16), UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
	UI.label("MENU", 34, { Name = "Title", LayoutOrder = 0, TextColor3 = C.accent, Parent = panel })
	-- Modal frees the mouse from first person while the menu is up.
	local resume = UI.chunky("RESUME", C.play, "▶️", { Name = "Resume", LayoutOrder = 1, Size = UDim2.new(0, 288, 0, 50), TextSize = 24, Modal = true, Parent = panel })
	p.resume = resume
	UI.onClick(resume, function()
		HomeController.setMenu(false)
	end)
	local switch = UI.chunky("SWITCH TEAM", Color3.fromRGB(240, 120, 40), "🔁", { Name = "Switch", LayoutOrder = 2, Size = UDim2.new(0, 288, 0, 46), TextSize = 20, Parent = panel })
	p.switch = switch
	UI.onClick(switch, HomeController.switchTeam)
	local spectate = UI.chunky("SPECTATE", C.panelLight, "👀", { Name = "Spectate", LayoutOrder = 3, Size = UDim2.new(0, 288, 0, 46), TextSize = 20, Parent = panel })
	p.spectate = spectate
	UI.onClick(spectate, function()
		HomeController.setMenu(false)
		ClientState.send("RequestSpectate")
	end)
	sectionButtons(panel, 288)

	-- Coming Soon card
	local soon = UI.screen("ComingSoon", 20)
	soon.Enabled = false
	p.comingSoon = soon
	local card = UI.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 380, 0, 220),
		BackgroundColor3 = C.panel,
		Parent = soon,
	}, { UI.corner(20), UI.stroke(C.accent, 4), UI.padding(16) })
	p.soonTitle = UI.label("", 34, { Name = "Title", Parent = card })
	UI.label("🚧 COMING SOON 🚧", 26, { Name = "Soon", Position = UDim2.new(0, 0, 0, 56), TextColor3 = C.accent, Parent = card })
	local ok = UI.chunky("OK", C.play, nil, {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(0, 150, 0, 50),
		Modal = true,
		Parent = card,
	})
	UI.onClick(ok, function()
		showComingSoon(false)
	end)
end

-- The status line: what the round is doing right now.
local function statusText(): string
	local snapshot = ClientState.snapshot
	if not snapshot then
		return "Connecting to the battlefield..."
	end
	local counts = {}
	for _, team in TeamConfig.order do
		table.insert(counts, tostring(ClientState.counts[team] or 0))
	end
	local versus = table.concat(counts, "v")
	if snapshot.phase == Phase.ACTIVE and not snapshot.phaseEndTime then
		return `Live match · {versus}`
	elseif snapshot.phase == Phase.ACTIVE then
		local name = if snapshot.modeName and snapshot.mode ~= "TeamElimination" then ` ({snapshot.modeName})` else ""
		return `Round in progress{name} · {RoundClock.format(ClientState.remaining())} left · {versus}`
	elseif snapshot.phase == Phase.RESULTS then
		return `Next round in {RoundClock.format(ClientState.remaining())} · {versus}`
	end
	return `{HUDController.waitingText(ClientState.counts)} · {versus}`
end

-- The team counts as they'd be without this player, which is what a
-- choice is judged against (the server takes the slot before the state
-- change arrives, so the counts can already include it).
local function othersCounts(): { [string]: number }
	local counts = table.clone(ClientState.counts)
	local mine = ClientState.teamId()
	if mine and counts[mine] then
		counts[mine] = math.max(0, counts[mine] - 1)
	end
	return counts
end

local function renderPicker()
	local p = HomeController.parts
	local counts, max = othersCounts(), ClientState.maxTeamSize
	local selected = HomeController.selectedTeam
	for _, team in TeamConfig.order do
		local card = p.teamButtons[team]
		local allowed = TeamBalance.preferenceAllowed(counts, TeamConfig.order, max, team)
		card:SetAttribute("Enabled", allowed)
		card.AutoButtonColor = allowed
		card.Lock.Visible = not allowed
		card.Count.Text = tostring(counts[team] or 0)
		card.Max.Text = `/ {max}`
		card.Border.Color = if team == selected then C.text else C.stroke
		local friends = Players.LocalPlayer:GetAttribute(`Friends_{team}`)
		card.Friends.Text = if type(friends) == "number" and friends > 0
			then `👥 {friends} friend{if friends == 1 then "" else "s"} here`
			else ""
	end
	if selected and not TeamBalance.preferenceAllowed(counts, TeamConfig.order, max, selected) then
		-- The teams moved on; fall back to automatic rather than promise
		-- a team PLAY can't give.
		HomeController.choose(nil)
		return
	end
	p.teamHint.Text = "Locked teams would make the match unfair. AUTO puts you where you're needed (with friends when it's fair)."
end

-- Coins, level, the XP bar and the badges.
local function renderWallet()
	local p = HomeController.parts
	local player = Players.LocalPlayer
	local function number(name: string, default: number): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else default
	end
	local coins = UI.commas(number("Coins", 0))
	if p.coins.Text ~= coins and p.coins.Text ~= "0" then
		UI.pop(p.coins, 1.12)
	end
	p.coins.Text = coins
	local level = number("Level", 1)
	p.level.Text = `LEVEL {level}`
	local toNext = number("XPToNext", ProgressionConfig.xpToNext(level))
	p.xpFill.Size = UDim2.new(if toNext > 0 then math.clamp(number("XP", 0) / toNext, 0, 1) else 1, 0, 1, 0)
	UI.setBadge(p.pageButtons.Weapons, LockerController.buyable())
	UI.setBadge(p.pageButtons.Loadout, LockerController.newAbilities())
	UI.setBadge(p.tiles.Rewards, if player:GetAttribute("DailyReady") == true then "!" else nil)
	UI.setBadge(p.tiles.Spin, number("Spins", 0))
end
HomeController.renderWallet = renderWallet

-- The battlefield blurs behind the home screen and sharpens in a match.
local function blur(on: boolean)
	local p = HomeController.parts
	local size = if on then UIConfig.menuBlur else 0
	if p.blur.Size ~= size then
		TweenService:Create(p.blur, TweenInfo.new(0.4), { Size = size }):Play()
	end
end

-- The bubble pointing at PLAY: for someone who hasn't played yet, until
-- they press it.
local pressedPlay = false
local function renderFirstTip()
	local p = HomeController.parts
	p.firstTip.Visible = not pressedPlay and Players.LocalPlayer:GetAttribute("LifetimeXP") == 0
end

local function render()
	local p = HomeController.parts
	local active = ClientState.isActive()
	p.home.Enabled = not active
	MouseLock.setFree("HomeScreen", not active)
	blur(not active)
	if active then
		p.teamSelect.Enabled = false
	end
	renderFirstTip()
	p.afkNotice.Visible = ClientState.state() == States.Player.AFK_SPECTATOR
	p.status.Text = statusText()
	if not active and HomeController.menuOpen then
		HomeController.setMenu(false)
	end
	if active and p.comingSoon.Enabled and not HomeController.menuOpen then
		showComingSoon(false)
	end
	local mine = ClientState.teamId()
	local target = otherTeam(mine)
	local canSwitch = mine ~= nil
		and target ~= nil
		and TeamBalance.canSwitch(ClientState.counts, TeamConfig.order, ClientState.maxTeamSize, mine, target :: string)
	UI.setEnabled(p.switch, canSwitch)
	p.switch.Text = if canSwitch and target then `SWITCH TO {TeamConfig.teams[target].shortName}` else "SWITCH TEAM (only to even up)"
	-- The long greyed-out label needs a smaller size to fit the button.
	p.switch.TextSize = if canSwitch and target then 22 else 18
	-- The picker is for the home screen: in a match the counts include
	-- this player, which would make their own choice look unfair.
	if not active then
		renderPicker()
	end
end
HomeController.render = render

-- Picks a team for PLAY (nil = automatic) and tells the server.
function HomeController.choose(team: string?)
	if team ~= nil and not TeamBalance.preferenceAllowed(othersCounts(), TeamConfig.order, ClientState.maxTeamSize, team) then
		return
	end
	if HomeController.selectedTeam ~= team then
		HomeController.selectedTeam = team
		ClientState.send("RequestTeam", team)
	end
	renderPicker()
end

-- PLAY: choose a team first.
function HomeController.play()
	if ClientState.isActive() then
		return
	end
	pressedPlay = true
	renderFirstTip()
	renderPicker()
	HomeController.parts.teamSelect.Enabled = true
end

-- A team (nil: wherever needed) from the team screen: join the match.
function HomeController.pick(team: string?)
	if team ~= nil and not TeamBalance.preferenceAllowed(othersCounts(), TeamConfig.order, ClientState.maxTeamSize, team) then
		return
	end
	HomeController.choose(team)
	local now = os.clock()
	if ClientState.isActive() or now < playCooldownUntil then
		return
	end
	playCooldownUntil = now + 1
	HomeController.parts.teamSelect.Enabled = false
	ClientState.send("RequestPlay", team)
end

function HomeController.setMenu(open: boolean)
	local p = HomeController.parts
	open = open and ClientState.isActive()
	HomeController.menuOpen = open
	p.menu.Enabled = open
	MouseLock.setFree("GameMenu", open)
	if not open then
		showComingSoon(false)
		LockerController.close()
	end
	InputController.menuOpen = open
end

function HomeController.switchTeam()
	local target = otherTeam(ClientState.teamId())
	if target then
		HomeController.setMenu(false)
		ClientState.send("RequestTeam", target)
	end
end

-- Screens over the home screen that Space and F leave alone.
local OVERLAYS = { "Locker", "Loadout", "ComingSoon", "DailyRewards", "SpinWheel", "Players", "Season", "Prestige", "GameMenu" }

-- Space or F: PLAY on the home screen, AUTO on the team screen.
local function onKey(input: InputObject, processed: boolean)
	local p = HomeController.parts
	if processed or (input.KeyCode ~= Enum.KeyCode.Space and input.KeyCode ~= Enum.KeyCode.F) then
		return
	end
	if not p.home.Enabled or ClientState.isActive() then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, name in OVERLAYS do
		local screen = playerGui and playerGui:FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") and screen.Enabled then
			return
		end
	end
	if p.teamSelect.Enabled then
		HomeController.pick(nil)
	else
		HomeController.play()
	end
end
HomeController.onKey = onKey

function HomeController.start()
	if started then
		return
	end
	started = true
	build()
	render()
	renderWallet()
	renderOffers()
	for _, name in { "Coins", "Level", "XP", "XPToNext", "Spins", "DailyReady" } do
		Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(renderWallet)
	end
	for _, name in { "Coins", "Level", "Spins", "DailyReady" } do
		Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(renderOffers)
	end
	Players.LocalPlayer:GetAttributeChangedSignal("LifetimeXP"):Connect(renderFirstTip)
	workspace:GetAttributeChangedSignal("SeasonActive"):Connect(renderOffers)
	LockerController.ProfileChanged:Connect(renderOffers)
	LockerController.BadgesChanged:Connect(renderWallet)
	UserInputService.InputBegan:Connect(onKey)
	ClientState.StateChanged:Connect(render)
	ClientState.TeamChanged:Connect(render)
	ClientState.TeamsChanged:Connect(render)
	ClientState.SnapshotChanged:Connect(render)
	for _, team in TeamConfig.order do
		Players.LocalPlayer:GetAttributeChangedSignal(`Friends_{team}`):Connect(render)
	end
	InputController.MenuToggled:Connect(function()
		HomeController.setMenu(not HomeController.menuOpen)
	end)
	-- The status line's countdown.
	task.spawn(function()
		while true do
			task.wait(0.5)
			HomeController.parts.status.Text = statusText()
			tickOffers()
		end
	end)
end

return HomeController
