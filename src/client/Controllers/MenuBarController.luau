-- The top-right corner while playing: your coins (+ opens the store), the
-- menu's sections as big buttons: Shop (weapons), Abilities, Levels
-- (progression) and Settings, each opening that page of the locker; and
-- below them the free spin (how many, or the time to the next) and the
-- daily reward (lit when one is waiting).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local LockerController = require(script.Parent.LockerController)
local RewardsController = require(script.Parent.RewardsController)

local C = UIConfig.colors
local GOLD = Color3.fromRGB(255, 205, 50)
local BUTTONS = {
	{ tab = "Weapons", icon = "🛒", label = "SHOP" },
	{ tab = "Abilities", icon = "⚡", label = "ABILITIES" },
	{ tab = "Progression", icon = "⭐", label = "LEVELS" },
	{ tab = "Settings", icon = "⚙️", label = "SETTINGS" },
}

local MenuBarController = {}

MenuBarController.parts = {} :: { [string]: any }

local player = Players.LocalPlayer
local started = false

local function commas(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return if string.sub(formatted, 1, 1) == "," then string.sub(formatted, 2) else formatted
end

local function build()
	local p = MenuBarController.parts
	local screen = UI.screen("MenuBar", 6)
	p.screen = screen
	local corner = UI.new("Frame", {
		Name = "Corner",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 52),
		Size = UDim2.new(0, 300, 0, 184),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	p.corner = corner

	-- Coins, with + to the shop.
	local wallet = UI.new("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 300, 0, 52),
		BackgroundColor3 = Color3.fromRGB(14, 12, 20),
		Parent = corner,
	}, { UI.corner(12), UI.stroke(Color3.fromRGB(70, 66, 84), 3) })
	UI.new("Frame", {
		Name = "Coin",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.new(0, 30, 0, 30),
		BackgroundColor3 = GOLD,
		Parent = wallet,
	}, {
		UI.corner(15),
		UI.stroke(Color3.fromRGB(150, 100, 0), 3),
		UI.label("C", 18, { Size = UDim2.new(1, 0, 1, 0), TextColor3 = Color3.fromRGB(150, 100, 0) }),
	})
	p.coins = UI.label("0", 32, {
		Name = "Coins",
		Position = UDim2.new(0, 48, 0, 0),
		Size = UDim2.new(1, -110, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
		Parent = wallet,
	})
	local plus = UI.button("+", C.play, {
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

	-- The sections.
	local row = UI.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 60),
		Size = UDim2.new(0, 300, 0, 70),
		BackgroundTransparency = 1,
		Parent = corner,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right) })
	-- Free spin and daily reward.
	local extras = UI.new("Frame", {
		Name = "Rewards",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 138),
		Size = UDim2.new(0, 300, 0, 44),
		BackgroundTransparency = 1,
		Parent = corner,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right) })
	p.spin = UI.button("🎡 SPIN", Color3.fromRGB(150, 90, 230), {
		Name = "Spin",
		LayoutOrder = 1,
		Size = UDim2.new(0, 140, 0, 42),
		TextSize = 18,
		Parent = extras,
	})
	UI.onClick(p.spin, RewardsController.openSpin)
	p.daily = UI.button("🎁 DAILY", Color3.fromRGB(230, 170, 30), {
		Name = "Daily",
		LayoutOrder = 2,
		Size = UDim2.new(0, 140, 0, 42),
		TextSize = 18,
		Parent = extras,
	})
	UI.onClick(p.daily, RewardsController.openDaily)
	p.buttons = {}
	for i, entry in BUTTONS do
		local button = UI.new("TextButton", {
			Name = entry.tab,
			LayoutOrder = i,
			Size = UDim2.new(0, 66, 0, 66),
			BackgroundColor3 = Color3.fromRGB(34, 30, 46),
			AutoButtonColor = true,
			Text = "",
			Parent = row,
		}, { UI.corner(12), UI.stroke(C.stroke, 3) })
		UI.label(entry.icon, 28, { Name = "Icon", Position = UDim2.new(0, 0, 0, 4), Size = UDim2.new(1, 0, 0, 36), Parent = button })
		UI.label(entry.label, 11, {
			Name = "Label",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 2, 1, -4),
			Size = UDim2.new(1, -4, 0, 14),
			TextScaled = true,
			Parent = button,
		})
		p.buttons[entry.tab] = button
		UI.onClick(button, function()
			LockerController.open(entry.tab)
		end)
	end
end

local function refresh()
	local p = MenuBarController.parts
	local coins = player:GetAttribute("Coins")
	p.coins.Text = commas(if type(coins) == "number" then coins else 0)
	p.corner.Visible = ClientState.isActive()
	local spins = tonumber(player:GetAttribute("Spins")) or 0
	local nextGift = player:GetAttribute("NextGiftSeconds")
	p.spin.Text = if spins > 0
		then `🎡 SPIN ×{spins}`
		elseif type(nextGift) == "number" then `🎡 {nextGift // 60}:{string.format("%02d", nextGift % 60)}`
		else "🎡 SPIN"
	p.daily.Text = if player:GetAttribute("DailyReady") == true then "🎁 CLAIM!" else "🎁 DAILY"
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
end

return MenuBarController
