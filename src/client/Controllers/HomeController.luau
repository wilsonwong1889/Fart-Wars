-- The home screen and the M menu.
--   HomeScreen  shown whenever the player isn't on a team (just joined,
--               spectating, AFK), over the live battlefield: PLAY, an
--               optional team choice, the round status, and the later-phase
--               sections marked Coming Soon
--   GameMenu    M in a match: resume, switch team (only when it evens the
--               teams), spectate, and the same Coming Soon sections. The
--               mouse is free while it's open, even in first person.
-- Buttons only send intent; the server decides, and the screens follow
-- the player's State attribute.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function comingSoonButtons(parent: Instance, width: number)
	for i, section in UIConfig.comingSoon do
		local button = UI.button(string.upper(section), C.panelLight, {
			Name = section,
			LayoutOrder = 10 + i,
			Size = UDim2.new(0, width, 0, 40),
			TextSize = 18,
			Parent = parent,
		})
		UI.onClick(button, function()
			openComingSoon(section)
		end)
	end
end

local function build()
	local p = HomeController.parts

	-- Home screen
	local home = UI.screen("HomeScreen", 10)
	p.home = home
	local side = UI.new("Frame", {
		Name = "Side",
		Size = UDim2.new(0, 440, 1, 0),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		Parent = home,
	}, {
		UI.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.8, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
		UI.padding(28),
	})
	UI.label(UIConfig.title, 64, {
		Name = "Title",
		Position = UDim2.new(0, 0, 0, 60),
		Size = UDim2.new(1, 0, 0, 70),
		TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = side,
	})
	UI.label(UIConfig.tagline, 18, {
		Name = "Tagline",
		Position = UDim2.new(0, 0, 0, 134),
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = side,
	})
	p.status = UI.label("", 18, {
		Name = "Status",
		Position = UDim2.new(0, 0, 0, 176),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 48),
		Parent = side,
	})
	p.afkNotice = UI.label("You were moved to spectators for being AFK.", 18, {
		Name = "AFKNotice",
		Position = UDim2.new(0, 0, 0, 228),
		TextColor3 = C.warning,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = side,
	})

	UI.label("TEAM", 16, {
		Name = "TeamHeading",
		Position = UDim2.new(0, 0, 0, 270),
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = side,
	})
	local picker = UI.new("Frame", {
		Name = "TeamPicker",
		Position = UDim2.new(0, 0, 0, 296),
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		Parent = side,
	}, { UI.list(Enum.FillDirection.Horizontal, 8) })
	p.teamButtons = {}
	local auto = UI.button("AUTO", C.panelLight, { Name = "Auto", LayoutOrder = 0, Size = UDim2.new(0, 90, 0, 52), Parent = picker })
	p.teamButtons.Auto = auto
	UI.onClick(auto, function()
		HomeController.choose(nil)
	end)
	for i, team in TeamConfig.order do
		local config = TeamConfig.teams[team]
		local button = UI.button(config.shortName, config.darkColor, {
			Name = team,
			LayoutOrder = i,
			Size = UDim2.new(0, 146, 0, 52),
			TextSize = 17,
			TextColor3 = config.color,
			Parent = picker,
		})
		p.teamButtons[team] = button
		UI.onClick(button, function()
			HomeController.choose(team)
		end)
	end
	p.teamHint = UI.label("", 14, {
		Name = "TeamHint",
		Position = UDim2.new(0, 0, 0, 352),
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = side,
	})

	local play = UI.button("PLAY", C.play, {
		Name = "Play",
		Position = UDim2.new(0, 0, 0, 400),
		Size = UDim2.new(1, 0, 0, 84),
		TextSize = 48,
		Parent = side,
	})
	p.play = play
	UI.onClick(play, HomeController.play)

	local sections = UI.new("Frame", {
		Name = "Sections",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.5, 0),
		Size = UDim2.new(0, 200, 0, 7 * 48),
		BackgroundTransparency = 1,
		Parent = home,
	}, { UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right) })
	comingSoonButtons(sections, 200)

	-- M menu
	local menu = UI.screen("GameMenu", 12)
	menu.Enabled = false
	p.menu = menu
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 300, 0, 540),
		BackgroundColor3 = C.panel,
		Parent = menu,
	}, { UI.corner(16), UI.stroke(C.stroke, 4), UI.padding(16), UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
	UI.label("MENU", 30, { Name = "Title", LayoutOrder = 0, Parent = panel })
	-- Modal frees the mouse from first person while the menu is up.
	local resume = UI.button("RESUME", C.play, { Name = "Resume", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 46), Modal = true, Parent = panel })
	p.resume = resume
	UI.onClick(resume, function()
		HomeController.setMenu(false)
	end)
	local switch = UI.button("SWITCH TEAM", C.panelLight, { Name = "Switch", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 46), Parent = panel })
	p.switch = switch
	UI.onClick(switch, HomeController.switchTeam)
	local spectate = UI.button("SPECTATE", C.panelLight, { Name = "Spectate", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 46), Parent = panel })
	p.spectate = spectate
	UI.onClick(spectate, function()
		HomeController.setMenu(false)
		ClientState.send("RequestSpectate")
	end)
	comingSoonButtons(panel, 268)

	-- Coming Soon card
	local soon = UI.screen("ComingSoon", 20)
	soon.Enabled = false
	p.comingSoon = soon
	local card = UI.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 360, 0, 200),
		BackgroundColor3 = C.panel,
		Parent = soon,
	}, { UI.corner(16), UI.stroke(C.accent, 4), UI.padding(16) })
	p.soonTitle = UI.label("", 30, { Name = "Title", Parent = card })
	UI.label("COMING SOON", 24, { Name = "Soon", Position = UDim2.new(0, 0, 0, 50), TextColor3 = C.accent, Parent = card })
	local close = UI.button("OK", C.panelLight, {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 140, 0, 44),
		Modal = true,
		Parent = card,
	})
	UI.onClick(close, function()
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
	if snapshot.phase == Phase.ACTIVE then
		return `Round in progress · {RoundClock.format(ClientState.remaining())} left · {versus}`
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
		local button = p.teamButtons[team]
		local allowed = TeamBalance.preferenceAllowed(counts, TeamConfig.order, max, team)
		UI.setEnabled(button, allowed)
		button.Text = `{TeamConfig.teams[team].shortName} {counts[team] or 0}/{max}`
	end
	if selected and not TeamBalance.preferenceAllowed(counts, TeamConfig.order, max, selected) then
		-- The teams moved on; fall back to automatic rather than promise
		-- a team PLAY can't give.
		HomeController.choose(nil)
		return
	end
	for name, button in p.teamButtons do
		local isSelected = (name == "Auto" and selected == nil) or name == selected
		button.Border.Color = if isSelected then C.text else C.stroke
	end
	p.teamHint.Text = if selected
		then `You'll join {TeamConfig.teams[selected].name}.`
		else "Auto puts you where the teams need you. Teams that would get too big are greyed out."
end

local function render()
	local p = HomeController.parts
	local active = ClientState.isActive()
	p.home.Enabled = not active
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

function HomeController.play()
	local now = os.clock()
	if ClientState.isActive() or now < playCooldownUntil then
		return
	end
	playCooldownUntil = now + 1
	ClientState.send("RequestPlay", HomeController.selectedTeam)
end

function HomeController.setMenu(open: boolean)
	local p = HomeController.parts
	open = open and ClientState.isActive()
	HomeController.menuOpen = open
	p.menu.Enabled = open
	if not open then
		p.comingSoon.Enabled = false
	end
	InputController.menuOpen = open
	InputController.applySpeed()
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
	ClientState.StateChanged:Connect(render)
	ClientState.TeamChanged:Connect(render)
	ClientState.TeamsChanged:Connect(render)
	ClientState.SnapshotChanged:Connect(render)
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
