-- The top-right corner while playing, in the home screen's style: your
-- coins (+ opens the store), the menu's sections as tiles: Shop (weapons),
-- Abilities, Levels (progression) and Settings, each opening that page of
-- the locker (Shop and Abilities with the home screen's badges); and below
-- them the free spin (how many, or the time to the next) and the daily
-- reward ("!" when one is waiting).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local LockerController = require(script.Parent.LockerController)
local RewardsController = require(script.Parent.RewardsController)
local SeasonController = require(script.Parent.SeasonController)

local C = UIConfig.colors
-- The locker pages along the top, in the home screen's colours.
local PAGES = { "Weapons", "Abilities", "Progression", "Settings" }

local MenuBarController = {}

MenuBarController.parts = {} :: { [string]: any }

local player = Players.LocalPlayer
local started = false

local function build()
	local p = MenuBarController.parts
	local screen = UI.screen("MenuBar", 6)
	p.screen = screen
	local corner = UI.new("Frame", {
		Name = "Corner",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 52),
		Size = UDim2.new(0, 330, 0, 196),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	p.corner = corner

	-- Coins, with + to the store.
	local wallet = UI.new("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 300, 0, 52),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		Parent = corner,
	}, { UI.corner(14), UI.stroke(C.stroke, 3) })
	UI.label("💰", 28, {
		Name = "Coin",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.new(0, 36, 0, 36),
		Parent = wallet,
	})
	p.coins = UI.label("0", 32, {
		Name = "Coins",
		Position = UDim2.new(0, 50, 0, 0),
		Size = UDim2.new(1, -110, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIConfig.gold,
		Parent = wallet,
	})
	local plus = UI.chunky("+", C.play, nil, {
		Name = "Plus",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, 40, 0, 40),
		TextSize = 30,
		Parent = wallet,
	})
	UI.onClick(plus, function()
		LockerController.open("Store")
	end)

	-- The locker's pages as tiles.
	local row = UI.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 62),
		Size = UDim2.new(0, 330, 0, 76),
		BackgroundTransparency = 1,
		Parent = corner,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right) })
	-- Free spin and daily reward.
	local extras = UI.new("Frame", {
		Name = "Rewards",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 148),
		Size = UDim2.new(0, 470, 0, 46),
		BackgroundTransparency = 1,
		Parent = corner,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right) })
	local function extra(name: string, text: string, icon: string, color: Color3, order: number): TextButton
		return UI.chunky(text, color, icon, {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(0, 148, 0, 44),
			TextSize = 18,
			Parent = extras,
		})
	end
	local tiles = {}
	for _, tile in UIConfig.lobbyTiles do
		tiles[tile.id] = tile
	end
	p.spin = extra("Spin", "SPIN", tiles.Spin.icon, tiles.Spin.color, 1)
	UI.onClick(p.spin, RewardsController.openSpin)
	p.daily = extra("Daily", "DAILY", tiles.Rewards.icon, tiles.Rewards.color, 2)
	UI.onClick(p.daily, RewardsController.openDaily)
	-- While a season is on.
	p.season = extra("Season", "SEASON", tiles.Season.icon, tiles.Season.color, 0)
	p.season.Visible = workspace:GetAttribute("SeasonActive") == true
	UI.onClick(p.season, SeasonController.open)
	workspace:GetAttributeChangedSignal("SeasonActive"):Connect(function()
		p.season.Visible = workspace:GetAttribute("SeasonActive") == true
	end)
	p.buttons = {}
	for i, tab in PAGES do
		local page = UIConfig.pages[tab]
		local button = UI.tile(page.icon, page.label, page.color, {
			Name = tab,
			LayoutOrder = i,
			Size = UDim2.new(0, 74, 0, 74),
			Parent = row,
		})
		p.buttons[tab] = button
		UI.onClick(button, function()
			LockerController.open(tab)
		end)
	end
end

local function refresh()
	local p = MenuBarController.parts
	local coins = player:GetAttribute("Coins")
	p.coins.Text = UI.commas(if type(coins) == "number" then coins else 0)
	p.corner.Visible = ClientState.isActive()
	local spins = tonumber(player:GetAttribute("Spins")) or 0
	local nextGift = player:GetAttribute("NextGiftSeconds")
	p.spin.Text = if spins > 0
		then `SPIN ×{spins}`
		elseif type(nextGift) == "number" then `{nextGift // 60}:{string.format("%02d", nextGift % 60)}`
		else "SPIN"
	p.daily.Text = if player:GetAttribute("DailyReady") == true then "CLAIM!" else "DAILY"
	UI.setBadge(p.daily, if player:GetAttribute("DailyReady") == true then "!" else nil)
	UI.setBadge(p.buttons.Weapons, LockerController.buyable())
	UI.setBadge(p.buttons.Abilities, LockerController.newAbilities())
end
MenuBarController.refresh = refresh

function MenuBarController.start()
	if started then
		return
	end
	started = true
	build()
	refresh()
	for _, name in { "Coins", "Spins", "NextGiftSeconds", "DailyReady" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	ClientState.StateChanged:Connect(refresh)
	LockerController.BadgesChanged:Connect(refresh)
end

return MenuBarController
