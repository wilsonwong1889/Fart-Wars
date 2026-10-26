-- The locker: the menu's Weapons, Abilities, Progression and Settings
-- screens, from the home screen or the M menu.
--   Weapons      every weapon with its preview colour, how it plays, gas
--                per hit, range, fire rate, handling, mastery, price and
--                level; BUY, EQUIP or what's missing
--   Abilities    Fart Dash (everyone's) and the Q abilities: what they do,
--                the cooldown, EQUIP or the level that unlocks them
--   Progression  level, XP, coins, the next goal and the unlock track,
--                lifetime stats, badges, tracer cosmetics to equip
--   Settings     reduced effects, sound effects, tips, and the controls
-- Every button only asks (ShopRequest); while a request is out the buttons
-- wait and the status line says so, and the answer (or the refusal) is
-- shown. What the player owns comes from the server (ProfileUpdate); coins
-- and level from their attributes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local Audio = require(Client.Audio)
local Settings = require(Client.Settings)
local ProgressController = require(script.Parent.ProgressController)

local C = UIConfig.colors
local ABILITY_ORDER = { "FartDash", "RecoveryBurst", "GasPulse" }
local COSMETIC_ORDER = { "GoldenGas", "RainbowRot" }

local LockerController = {}

LockerController.parts = {} :: { [string]: any }
LockerController.tab = "Weapons"
LockerController.isOpen = false
-- The latest ProfileUpdate.
LockerController.profile = nil :: { [string]: any }?
-- A request is out; buttons wait.
LockerController.busy = false

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
			setStatus("Couldn't reach the server. Try again.", C.warning)
		end
		render()
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
		elseif coins < weapon.price then
			actionButton(box, `{weapon.price} COINS`, false)
		else
			actionButton(box, `BUY {weapon.price}`, profile.saving ~= false, function()
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
	text(right, "TRACERS", 18, 20, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.accent })
	local row = UI.new("Frame", {
		Name = "Cosmetics",
		LayoutOrder = 21,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = right,
	}, { UI.list(Enum.FillDirection.Horizontal, 6) })
	local none = UI.button(if profile.equippedCosmetic == nil then "NONE ✓" else "NONE", C.panelLight, {
		Name = "None",
		Size = UDim2.new(0, 96, 0, 38),
		TextSize = 15,
		Parent = row,
	})
	UI.setEnabled(none, profile.equippedCosmetic ~= nil and not LockerController.busy)
	UI.onClick(none, function()
		LockerController.request("equip", "cosmetic", nil)
	end)
	for i, id in COSMETIC_ORDER do
		local cosmetic = ProgressionConfig.cosmetics[id]
		local owned = owns(profile.ownedCosmetics, id)
		local unlockLevel = 0
		for at, entry in ProgressionConfig.unlocks do
			if entry.id == id then
				unlockLevel = at
			end
		end
		local label = if not owned then `LEVEL {unlockLevel}` elseif profile.equippedCosmetic == id then `{string.upper(cosmetic.name)} ✓` else string.upper(cosmetic.name)
		local button = UI.button(label, C.panelLight, {
			Name = id,
			LayoutOrder = i,
			Size = UDim2.new(0, 140, 0, 38),
			TextSize = 15,
			TextColor3 = cosmetic.tracerColor,
			Parent = row,
		})
		UI.setEnabled(button, owned and profile.equippedCosmetic ~= id and not LockerController.busy)
		UI.onClick(button, function()
			LockerController.request("equip", "cosmetic", id)
		end)
	end
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

local TABS = { Weapons = weaponsTab, Abilities = abilitiesTab, Progression = progressionTab, Settings = settingsTab }

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
			Size = UDim2.new(0, 148, 0, 42),
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
		end
	end)
	-- The first look (a push can arrive before this script listens).
	task.spawn(function()
		local shopRequest = ClientState.remote("ShopRequest") :: RemoteFunction
		local ok, answer = pcall(shopRequest.InvokeServer, shopRequest, "profile", "all")
		if ok and type(answer) == "table" and type(answer.profile) == "table" and not LockerController.profile then
			LockerController.profile = answer.profile
			render()
		end
	end)
	for _, name in { "Coins", "Level", "XP" } do
		player:GetAttributeChangedSignal(name):Connect(render)
	end
	-- Pressing PLAY, spectating or going AFK closes it.
	ClientState.StateChanged:Connect(LockerController.close)
end

return LockerController
