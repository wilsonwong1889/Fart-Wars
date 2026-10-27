-- The home screen and the M menu.
--   HomeScreen  shown whenever the player isn't on a team (just joined,
--               spectating, AFK), over the live battlefield, laid out like
--               a game lobby: big buttons for the locker's pages down the
--               left (Shop, Abilities, Levels, Store; a red badge counts
--               what's waiting), level and coins bottom left, tiles down
--               the right (Daily, Spin, Season, Players, Top, Settings),
--               and the title, PLAY and the round's status bottom middle;
--               the later-phase screens say Coming Soon
--   TeamSelect  after PLAY: "CHOOSE A TEAM", each team's card with its
--               count (locked when joining it would make the teams
--               unfair), and AUTO; picking one joins the match
--   GameMenu    M in a match: resume, switch team (only when it evens the
--               teams), spectate, and the same sections. The mouse is free
--               while it's open, even in first person.
-- Buttons only send intent; the server decides, and the screens follow
-- the player's State attribute.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local States = require(Shared.States)
local TeamBalance = require(Shared.TeamBalance)
local RoundClock = require(Shared.RoundClock)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local InputController = require(script.Parent.InputController)
local HUDController = require(script.Parent.HUDController)
local LockerController = require(script.Parent.LockerController)
local RewardsController = require(script.Parent.RewardsController)
local PlayersController = require(script.Parent.PlayersController)
local SeasonController = require(script.Parent.SeasonController)
local ReleaseConfig = require(Shared.Config.ReleaseConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)

local C = UIConfig.colors
local Phase = States.Phase

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

local function openComingSoon(section: string)
	local p = HomeController.parts
	p.soonTitle.Text = string.upper(section)
	p.comingSoon.Enabled = true
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

local function build()
	local p = HomeController.parts

	-- Home screen: over the live battlefield, a game lobby. The locker's
	-- pages down the left, coins and level bottom left, the other screens
	-- as tiles down the right, and the title, PLAY and the round's status
	-- at the bottom in the middle.
	local home = UI.screen("HomeScreen", 10)
	p.home = home

	local pages = UI.new("Frame", {
		Name = "Pages",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.55, 0),
		Size = UDim2.new(0, 240, 0, #UIConfig.lobbyPages * 80),
		BackgroundTransparency = 1,
		Parent = home,
	})
	p.pageButtons = {}
	for i, id in UIConfig.lobbyPages do
		local page = UIConfig.pages[id]
		local button = UI.chunky(page.label, page.color, page.icon, {
			Name = id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 34 + (i - 1) * 80),
			Size = UDim2.new(0, 228, 0, 66),
			TextSize = 30,
			Parent = pages,
		})
		p.pageButtons[id] = button
		UI.onClick(button, function()
			LockerController.open(id)
		end)
	end

	p.tileColumn = UI.new("Frame", {
		Name = "Tiles",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.47, 0),
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

	-- Level and coins, bottom left; + opens the store.
	local wallet = UI.new("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -10),
		Size = UDim2.new(0, 360, 0, 136),
		BackgroundTransparency = 1,
		Parent = home,
	})
	UI.label("⭐", 34, { Name = "Star", Size = UDim2.new(0, 48, 0, 44), Parent = wallet })
	p.level = UI.label("LEVEL 1", 28, {
		Name = "Level",
		Position = UDim2.new(0, 56, 0, 0),
		Size = UDim2.new(0, 260, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = wallet,
	})
	local xpBar = UI.new("Frame", {
		Name = "XPBar",
		Position = UDim2.new(0, 58, 0, 32),
		Size = UDim2.new(0, 210, 0, 12),
		BackgroundColor3 = Color3.fromRGB(20, 18, 30),
		Parent = wallet,
	}, { UI.corner(6), UI.stroke(C.stroke, 2) })
	p.xpFill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = UIConfig.pages.Progression.color,
		Parent = xpBar,
	}, { UI.corner(6) })
	UI.label("💰", 48, { Name = "CoinIcon", Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(0, 56, 0, 58), Parent = wallet })
	p.coins = UI.label("0", 54, {
		Name = "Coins",
		Position = UDim2.new(0, 66, 0, 48),
		Size = UDim2.new(0, 290, 0, 58),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIConfig.gold,
		Parent = wallet,
	})
	local plus = UI.chunky("+", C.play, nil, {
		Name = "Plus",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 50, 0, 98),
		Size = UDim2.new(0, 30, 0, 30),
		TextSize = 24,
		Parent = wallet,
	})
	UI.onClick(plus, function()
		LockerController.open("Store")
	end)
	-- The build, so a screenshot or report says which one it was.
	p.version = UI.label(versionText(), 13, {
		Name = "Version",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = wallet,
	})
	workspace:GetAttributeChangedSignal("ReleaseChannel"):Connect(function()
		p.version.Text = versionText()
	end)

	-- The title, PLAY and the round's status, bottom middle.
	local center = UI.new("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0, 560, 0, 320),
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
	p.afkNotice = UI.label("You were moved to spectators for being AFK.", 18, {
		Name = "AFKNotice",
		LayoutOrder = 1,
		TextColor3 = C.warning,
		Visible = false,
		Parent = center,
	})
	UI.label(UIConfig.title, 78, {
		Name = "Title",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 80),
		Rotation = -2,
		TextColor3 = C.accent,
		Parent = center,
	})
	UI.label(UIConfig.tagline, 20, {
		Name = "Tagline",
		LayoutOrder = 3,
		Parent = center,
	})
	-- PLAY sits in its own slot so it springs from its middle.
	local slot = UI.new("Frame", {
		Name = "PlaySlot",
		LayoutOrder = 4,
		Size = UDim2.new(0, 380, 0, 104),
		BackgroundTransparency = 1,
		Parent = center,
	})
	local play = UI.chunky("PLAY", C.play, nil, {
		Name = "Play",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 340, 0, 92),
		TextSize = 60,
		Parent = slot,
	})
	p.play = play
	UI.onClick(play, HomeController.play)
	-- The beta is for PC: say so on a touch screen with no keyboard (in case
	-- the place's device settings let one in).
	p.deviceNotice = UI.label("Fart Wars is a PC beta for now: it needs a mouse and keyboard.", 16, {
		Name = "DeviceNotice",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		TextColor3 = C.warning,
		Visible = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true,
		Parent = center,
	})
	local chip = UI.new("Frame", {
		Name = "StatusChip",
		LayoutOrder = 6,
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
		soon.Enabled = false
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
	UI.setBadge(p.pageButtons.Abilities, LockerController.newAbilities())
	UI.setBadge(p.tiles.Rewards, if player:GetAttribute("DailyReady") == true then "!" else nil)
	UI.setBadge(p.tiles.Spin, number("Spins", 0))
end
HomeController.renderWallet = renderWallet

local function render()
	local p = HomeController.parts
	local active = ClientState.isActive()
	p.home.Enabled = not active
	if active then
		p.teamSelect.Enabled = false
	end
	p.afkNotice.Visible = ClientState.state() == States.Player.AFK_SPECTATOR
	p.status.Text = statusText()
	if not active and HomeController.menuOpen then
		HomeController.setMenu(false)
	end
	if active then
		p.comingSoon.Enabled = p.comingSoon.Enabled and HomeController.menuOpen
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
	if not open then
		p.comingSoon.Enabled = false
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

function HomeController.start()
	if started then
		return
	end
	started = true
	build()
	render()
	renderWallet()
	for _, name in { "Coins", "Level", "XP", "XPToNext", "Spins", "DailyReady" } do
		Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(renderWallet)
	end
	LockerController.BadgesChanged:Connect(renderWallet)
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
		end
	end)
end

return HomeController
