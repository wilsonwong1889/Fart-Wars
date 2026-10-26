-- The locker: the menu's Weapons, Abilities, Progression and Settings
-- screens, from the home screen or the M menu.
--   Weapons      every weapon with its preview colour, how it plays, gas
--                per hit, range, fire rate, handling, mastery, price and
--                level; BUY, EQUIP or what's missing
--   Abilities    Fart Dash (everyone's) and the Q abilities: what they do,
--                the cooldown, EQUIP or the level that unlocks them
--   Progression  level, XP, coins, the next goal and the unlock track,
--                lifetime stats, badges, and every cosmetic (tracers,
--                Fart Dash trails, emotes): equip it, or how to get it
--   Store        the Starter Pack and coin packs, contents in full, prices
--                from Roblox (cosmetics and coins only)
--   Settings     reduced effects, sound effects, tips, and the controls
-- Every button only asks (ShopRequest); while a request is out the buttons
-- wait and the status line says so, and the answer (or the refusal) is
-- shown. What the player owns comes from the server (ProfileUpdate); coins
-- and level from their attributes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local Audio = require(Client.Audio)
local Settings = require(Client.Settings)
local Signal = require(Shared.Signal)
local ProgressController = require(script.Parent.ProgressController)

local C = UIConfig.colors
local ABILITY_ORDER = { "FartDash", "RecoveryBurst", "GasPulse" }

local LockerController = {}

LockerController.parts = {} :: { [string]: any }
LockerController.tab = "Weapons"
LockerController.isOpen = false
-- The latest ProfileUpdate.
LockerController.profile = nil :: { [string]: any }?

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

local player = Players.LocalPlayer
local started = false

local function number(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function owns(list: any, id: string): boolean
	return type(list) == "table" and table.find(list, id) ~= nil
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

-- Sends one request; the buttons wait for the answer.
function LockerController.request(action: string, kind: string, id: string?)
	if LockerController.busy then
		return
	end
	LockerController.busy = true
	setStatus(if action == "buy" then "Buying... (saving your purchase)" else "Equipping...")
	render()
	task.spawn(function()
		local remote = ClientState.remote("ShopRequest") :: RemoteFunction
		local ok, answer = pcall(remote.InvokeServer, remote, action, kind, id)
		LockerController.busy = false
		if ok and type(answer) == "table" then
			setStatus(tostring(answer.message), if answer.ok then C.accent else C.warning)
			if answer.ok and action == "buy" then
				Audio.play("purchase")
			end
		else
			answer = { ok = false, reason = "unreachable", message = "Couldn't reach the server. Try again." }
			setStatus(answer.message, C.warning)
		end
		render()
		LockerController.Answered:Fire(answer, action, kind, id)
	end)
end

local function card(parent: Instance, name: string, order: number, height: number): Frame
	return UI.new("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(0, 172, 0, height),
		BackgroundColor3 = C.panelLight,
		Parent = parent,
	}, { UI.corner(10), UI.stroke(C.stroke, 2), UI.padding(8), UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center) })
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

local function actionButton(parent: Instance, label: string, enabled: boolean, onClick: (() -> ())?): TextButton
	local button = UI.button(label, if enabled then C.play else C.disabled, {
		Name = "Action",
		LayoutOrder = 100,
		Size = UDim2.new(1, 0, 0, 38),
		TextSize = 18,
		Parent = parent,
	})
	UI.setEnabled(button, enabled and not LockerController.busy)
	if onClick then
		UI.onClick(button, onClick)
	end
	return button
end

local function weaponsTab(content: Frame)
	local profile = LockerController.profile or {}
	local level, coins = number("Level", 1), number("Coins", 0)
	UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = content
	for i, id in WeaponConfig.order do
		local weapon = WeaponConfig.weapons[id]
		local box = card(content, id, i, 330)
		text(box, weapon.displayName, 20, 1, { TextColor3 = weapon.tracerColor })
		UI.new("Frame", {
			Name = "Preview",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = weapon.tracerColor,
			BorderSizePixel = 0,
			Parent = box,
		}, { UI.corner(3) })
		text(box, weapon.description, 13, 3, { Size = UDim2.new(1, 0, 0, 70), TextColor3 = C.muted, TextYAlignment = Enum.TextYAlignment.Top })
		local projectile = if weapon.projectile == "lob" then "lobbed" else "instant"
		local lines = {
			`Gas {weapon.gasPerHit}% (head {weapon.headshotGas}%)`,
			`Range {weapon.range} · {projectile}`,
			`Fire rate {string.format("%.1f", 1 / weapon.fireInterval)}/s`,
			`Handling {LockerController.handling(weapon)}`,
		}
		local mastery = profile.mastery and profile.mastery[id]
		local kills = if type(mastery) == "table" then tonumber(mastery.eliminations) or 0 else 0
		local nextMilestone = nil
		for _, milestone in ProgressionConfig.mastery do
			if kills < milestone.eliminations then
				nextMilestone = milestone
				break
			end
		end
		table.insert(lines, if nextMilestone then `Mastery {kills}/{nextMilestone.eliminations}` else `Mastery {kills} (all badges)`)
		for j, line in lines do
			text(box, line, 14, 3 + j, { Name = "Stat" })
		end
		local owned = owns(profile.ownedWeapons, id)
		if owned and profile.equippedWeapon == id then
			actionButton(box, "EQUIPPED", false)
		elseif owned then
			actionButton(box, "EQUIP", true, function()
				LockerController.request("equip", "weapon", id)
			end)
		elseif level < weapon.level then
			actionButton(box, `LEVEL {weapon.level}`, false)
		elseif coins < LockerController.priceOf(id) then
			actionButton(box, `{LockerController.priceOf(id)} COINS`, false)
		else
			actionButton(box, `BUY {LockerController.priceOf(id)}`, profile.saving ~= false, function()
				LockerController.request("buy", "weapon", id)
			end)
		end
	end
end

local function abilitiesTab(content: Frame)
	local profile = LockerController.profile or {}
	UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = content
	for i, id in ABILITY_ORDER do
		local ability = AbilityConfig[id]
		local box = card(content, id, i, 300)
		text(box, ability.displayName, 20, 1, { TextColor3 = C.accent })
		text(box, if ability.input == Enum.KeyCode.Q then "Q" else "SHIFT", 15, 2)
		text(box, ability.description, 13, 3, { Size = UDim2.new(1, 0, 0, 96), TextColor3 = C.muted, TextYAlignment = Enum.TextYAlignment.Top })
		text(box, `Cooldown {ability.cooldownSeconds}s`, 14, 4, { Name = "Stat" })
		if ability.ownership == "everyone" then
			actionButton(box, "EVERYONE HAS IT", false)
		elseif owns(profile.unlockedAbilities, id) and profile.equippedAbility == id then
			actionButton(box, "EQUIPPED", false)
		elseif owns(profile.unlockedAbilities, id) then
			actionButton(box, "EQUIP", true, function()
				LockerController.request("equip", "ability", id)
			end)
		else
			actionButton(box, `LEVEL {ability.level}`, false)
		end
	end
end

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
	local grid = UI.new("Frame", {
		Name = "Cosmetics",
		LayoutOrder = 21,
		Size = UDim2.new(1, 0, 0, 3 * 44),
		BackgroundTransparency = 1,
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
	}
	for i, id in ProgressionConfig.cosmeticOrder do
		local cosmetic = ProgressionConfig.cosmetics[id]
		local owned = type(profile.ownedCosmetics) == "table" and ProgressionConfig.ownsCosmetic(profile.ownedCosmetics, id)
		local equipped = equippedBy[cosmetic.kind] == id
		local color = cosmetic.tracerColor or cosmetic.trailColor or C.text
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

-- The store: passes and coin packs from MonetizationConfig, contents in
-- full, prices from Roblox. Roblox's own purchase window does the buying.
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
		if LockerController.isOpen and LockerController.tab == "Store" then
			render()
		end
	end)
	return priceCache[key]
end

local function storeTab(content: Frame)
	local profile = LockerController.profile or {}
	UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center).Parent = content
	for i, pass in MonetizationConfig.passes do
		local card = UI.box(pass.key, Color3.fromRGB(150, 90, 230), UDim2.new(1, 0, 0, 150), { LayoutOrder = i })
		card.Parent = content
		UI.label(string.upper(pass.name), 28, {
			Name = "Name",
			Position = UDim2.new(0, 16, 0, 8),
			Size = UDim2.new(0.6, 0, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		for j, line in pass.contents do
			UI.label(`• {line}`, 15, {
				Name = `Line{j}`,
				Position = UDim2.new(0, 20, 0, 40 + (j - 1) * 24),
				Size = UDim2.new(0.62, 0, 0, 22),
				Font = UIConfig.bodyFont,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})
		end
		local owned = type(profile.passes) == "table" and table.find(profile.passes, pass.key) ~= nil
		local label = if owned then "OWNED" elseif pass.id == 0 then "UNAVAILABLE" else price(Enum.InfoType.GamePass, pass.id)
		local button = UI.button(label, C.play, {
			Name = "Action",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -18, 0.5, 0),
			Size = UDim2.new(0, 200, 0, 56),
			TextSize = 24,
			Parent = card,
		})
		UI.setEnabled(button, not owned and pass.id ~= 0)
		UI.onClick(button, function()
			pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.id)
		end)
	end
	local packs = UI.new("Frame", {
		Name = "Coins",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundTransparency = 1,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	for i, product in MonetizationConfig.products do
		local card = UI.box(product.key, Color3.fromRGB(255, 205, 50), UDim2.new(0, 220, 1, 0), { LayoutOrder = i })
		card.Parent = packs
		UI.label("💰", 40, { Name = "Icon", Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 46), Parent = card })
		UI.label(string.upper(product.name), 22, { Name = "Name", Position = UDim2.new(0, 0, 0, 54), Size = UDim2.new(1, 0, 0, 28), Parent = card })
		local button = UI.button(if product.id == 0 then "UNAVAILABLE" else price(Enum.InfoType.Product, product.id), C.play, {
			Name = "Action",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -24, 0, 44),
			TextSize = 20,
			Parent = card,
		})
		UI.setEnabled(button, product.id ~= 0)
		UI.onClick(button, function()
			pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, product.id)
		end)
	end
	text(content, "Everything here is cosmetic or coins: nothing you can buy makes your weapons stronger.", 14, 20, {
		TextColor3 = C.muted,
	})
end

local function settingsTab(content: Frame)
	UI.list(Enum.FillDirection.Vertical, 6).Parent = content
	local toggles = {
		{ key = "reducedEffects", name = "ReducedEffects", label = "REDUCED EFFECTS", note = "Fewer puffs and clouds (stink clouds that gas you always show)." },
		{ key = "sound", name = "Sound", label = "SOUND EFFECTS", note = "The game's sounds (Roblox's own volume still applies)." },
		{ key = "tips", name = "Tips", label = "TIPS", note = "A short hint now and then, never mid-fight." },
	}
	for i, toggle in toggles do
		local on = (Settings :: any)[toggle.key]
		local button = UI.button(`{toggle.label}: {if on then "ON" else "OFF"}`, C.panelLight, {
			Name = toggle.name,
			LayoutOrder = i * 2 - 1,
			Size = UDim2.new(0, 320, 0, 38),
			TextSize = 17,
			Parent = content,
		})
		UI.onClick(button, function()
			(Settings :: any)[toggle.key] = not (Settings :: any)[toggle.key]
			Settings.chosen[toggle.key] = true
			render()
		end)
		text(content, toggle.note, 13, i * 2, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.muted })
	end
	text(content, "CONTROLS", 18, 10, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.accent })
	local controls = {}
	for _, row in UIConfig.controls do
		table.insert(controls, `{row[1]} {row[2]}`)
	end
	text(content, table.concat(controls, "  ·  "), 14, 11, {
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 60),
	})
end

local TABS = { Weapons = weaponsTab, Abilities = abilitiesTab, Progression = progressionTab, Store = storeTab, Settings = settingsTab }

render = function()
	local p = LockerController.parts
	if not LockerController.isOpen then
		return
	end
	for name, button in p.tabs do
		button.Border.Color = if name == LockerController.tab then C.text else C.stroke
	end
	for _, child in p.content:GetChildren() do
		child:Destroy()
	end
	TABS[LockerController.tab](p.content)
end
LockerController.render = render

local function build()
	local p = LockerController.parts
	local screen = UI.screen("Locker", 15)
	screen.Enabled = false
	p.screen = screen
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 760, 0, 470),
		BackgroundColor3 = C.panel,
		Parent = screen,
	}, { UI.corner(16), UI.stroke(C.stroke, 4), UI.padding(14) })
	local tabs = UI.new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -110, 0, 42),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Horizontal, 6) })
	p.tabs = {}
	for i, name in UIConfig.menuSections do
		local button = UI.button(string.upper(name), C.panelLight, {
			Name = name,
			LayoutOrder = i,
			Size = UDim2.new(0, 118, 0, 42),
			TextSize = 18,
			Parent = tabs,
		})
		p.tabs[name] = button
		UI.onClick(button, function()
			LockerController.open(name)
		end)
	end
	-- Modal frees the mouse from first person while the locker is up.
	local close = UI.button("CLOSE", C.panelLight, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 100, 0, 42),
		TextSize = 18,
		Modal = true,
		Parent = panel,
	})
	UI.onClick(close, LockerController.close)
	p.content = UI.new("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 0, 0, 54),
		Size = UDim2.new(1, 0, 1, -84),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	p.status = UI.label("", 15, {
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 22),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
end

function LockerController.open(tab: string?)
	local p = LockerController.parts
	if tab and TABS[tab] then
		LockerController.tab = tab
	end
	if not LockerController.isOpen then
		setStatus(if LockerController.profile and LockerController.profile.saving == false
			then "Progress isn't saving this session: the shop is closed."
			else "")
	end
	LockerController.isOpen = true
	p.screen.Enabled = true
	render()
end

function LockerController.close()
	LockerController.isOpen = false
	LockerController.parts.screen.Enabled = false
end

function LockerController.start()
	if started then
		return
	end
	started = true
	build()
	local remote = ClientState.remote("ProfileUpdate") :: RemoteEvent
	remote.OnClientEvent:Connect(function(view)
		if type(view) == "table" then
			LockerController.profile = view
			render()
			LockerController.ProfileChanged:Fire(view)
		end
	end)
	-- The first look (a push can arrive before this script listens).
	task.spawn(function()
		local shopRequest = ClientState.remote("ShopRequest") :: RemoteFunction
		local ok, answer = pcall(shopRequest.InvokeServer, shopRequest, "profile", "all")
		if ok and type(answer) == "table" and type(answer.profile) == "table" and not LockerController.profile then
			LockerController.profile = answer.profile
			render()
			LockerController.ProfileChanged:Fire(answer.profile)
		end
	end)
	for _, name in { "Coins", "Level", "XP" } do
		player:GetAttributeChangedSignal(name):Connect(render)
	end
	-- Pressing PLAY, spectating or going AFK closes it.
	ClientState.StateChanged:Connect(LockerController.close)
end

return LockerController
