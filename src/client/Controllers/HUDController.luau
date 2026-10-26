-- The match screens:
--   HUD           the score boxes (each team's colour, score and player
--                 count) either side of the timer and round state; your
--                 team; messages; the AFK warning; the one-time controls
--                 card on a first PLAY
--   ResultsScreen the winner (or draw) and the countdown to the next round
--   Scoreboard    Tab (held): who is on each team (stats come with combat)
-- Everything shown comes from ClientState; times come from the snapshot's
-- end time and the server clock, never a local countdown.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local States = require(Shared.States)
local RoundClock = require(Shared.RoundClock)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local InputController = require(script.Parent.InputController)

local C = UIConfig.colors
local Phase = States.Phase

local HUDController = {}

-- The pieces, for the controllers' own use and for tests.
HUDController.parts = {} :: { [string]: any }

local started = false
local toastToken = 0
local afkEndsAt: number? = nil
local shownControls = false

-- A team's score box: a chunky box in the team colour, the score big,
-- the team name and active count small.
local function teamPanel(team: string, order: number): Frame
	local config = TeamConfig.teams[team]
	local panel = UI.box(team, config.color, UDim2.new(0, 132, 0, 76), { LayoutOrder = order })
	UI.label("0", 44, {
		Name = "Score",
		Position = UDim2.new(0, 0, 0, 2),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = panel,
	})
	UI.label(config.shortName, 15, {
		Name = "TeamName",
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = panel,
	})
	UI.label("0/10", 12, {
		Name = "Count",
		Position = UDim2.new(0, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 14),
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	return panel
end

local function build()
	local p = HUDController.parts

	local hud = UI.screen("HUD", 5)
	p.hud = hud
	local top = UI.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.new(0, 500, 0, 80),
		BackgroundTransparency = 1,
		Parent = hud,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	p.left = teamPanel(TeamConfig.order[1], 1)
	p.left.Parent = top
	local center = UI.new("Frame", {
		Name = "Clock",
		LayoutOrder = 2,
		Size = UDim2.new(0, 190, 0, 58),
		BackgroundColor3 = Color3.fromRGB(14, 12, 20),
		Parent = top,
	}, { UI.corner(12), UI.stroke(Color3.fromRGB(70, 66, 84), 3) })
	p.time = UI.label("--:--", 40, { Name = "Time", Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 44), Parent = center })
	p.phase = UI.label(UIConfig.phaseLabels.WAITING, 13, {
		Name = "Phase",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.new(1, 40, 0, 16),
		TextColor3 = C.text,
		TextWrapped = true,
		Parent = center,
	})
	p.right = teamPanel(TeamConfig.order[2], 3)
	p.right.Parent = top

	p.yourTeam = UI.label("", 18, {
		Name = "YourTeam",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.new(0, 560, 0, 26),
		Visible = false,
		Parent = hud,
	})
	-- Live events: the banner (Bean Rain's warning, then the rain).
	p.event = UI.label("", 18, {
		Name = "Event",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.new(0, 640, 0, 24),
		TextColor3 = Color3.fromRGB(255, 200, 80),
		Visible = false,
		Parent = hud,
	})
	-- Gas Control: who holds the zone (in words as well as colour).
	p.zone = UI.label("", 18, {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 174),
		Size = UDim2.new(0, 560, 0, 24),
		Visible = false,
		Parent = hud,
	})
	p.waiting = UI.label("", 18, {
		Name = "Waiting",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 174),
		Size = UDim2.new(0, 560, 0, 24),
		TextColor3 = C.accent,
		Visible = false,
		Parent = hud,
	})

	local toast = UI.new("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -200),
		Size = UDim2.new(0, 520, 0, 52),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = hud,
	}, { UI.corner(12), UI.stroke(C.stroke, 3), UI.padding(8) })
	p.toast = toast
	p.toastText = UI.label("", 18, {
		Name = "Text",
		Size = UDim2.new(1, 0, 1, 0),
		TextWrapped = true,
		Parent = toast,
	})

	local afk = UI.new("Frame", {
		Name = "AFKWarning",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 620, 0, 150),
		BackgroundColor3 = C.warning,
		Visible = false,
		Parent = hud,
	}, { UI.corner(16), UI.stroke(C.stroke, 4), UI.padding(10) })
	p.afk = afk
	UI.label(UIConfig.afkWarning, 40, { Name = "Title", TextWrapped = true, Size = UDim2.new(1, 0, 0, 52), Parent = afk })
	p.afkDetail = UI.label("", 20, {
		Name = "Detail",
		Position = UDim2.new(0, 0, 0, 60),
		TextWrapped = true,
		Parent = afk,
	})
	p.afkCountdown = UI.label("", 26, { Name = "Countdown", Position = UDim2.new(0, 0, 0, 92), Parent = afk })

	local controls = UI.new("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.new(0, 280, 0, 36 + #UIConfig.controls * 26),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = hud,
	}, { UI.corner(12), UI.stroke(C.stroke, 3), UI.padding(10), UI.list(Enum.FillDirection.Vertical, 2) })
	p.controls = controls
	UI.label("CONTROLS", 18, { LayoutOrder = 0, TextColor3 = C.accent, Size = UDim2.new(1, 0, 0, 24), Parent = controls })
	for i, row in UIConfig.controls do
		UI.label(`{row[1]}  ·  {row[2]}`, 16, {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 22),
			Font = UIConfig.bodyFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = controls,
		})
	end

	-- Results
	local results = UI.screen("ResultsScreen", 6)
	results.Enabled = false
	p.results = results
	local card = UI.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 560, 0, 220),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Parent = results,
	}, { UI.corner(18), UI.stroke(C.stroke, 4), UI.padding(14) })
	p.resultTitle = UI.label("", 48, { Name = "Title", Size = UDim2.new(1, 0, 0, 56), Parent = card })
	p.resultScores = UI.label("", 34, { Name = "Scores", Position = UDim2.new(0, 0, 0, 64), Parent = card })
	p.resultYou = UI.label("", 22, {
		Name = "You",
		Position = UDim2.new(0, 0, 0, 110),
		TextColor3 = C.muted,
		Parent = card,
	})
	p.resultNext = UI.label("", 22, { Name = "Next", Position = UDim2.new(0, 0, 0, 150), Parent = card })

	-- Scoreboard
	local board = UI.screen("Scoreboard", 7)
	board.Enabled = false
	p.scoreboard = board
	local sheet = UI.new("Frame", {
		Name = "Sheet",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 640, 0, 440),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Parent = board,
	}, { UI.corner(16), UI.stroke(C.stroke, 4), UI.padding(14) })
	UI.label("SCOREBOARD", 26, { Name = "Title", Parent = sheet })
	p.columns = {}
	for i, team in TeamConfig.order do
		local config = TeamConfig.teams[team]
		local column = UI.new("Frame", {
			Name = team,
			Position = UDim2.new((i - 1) * 0.5, if i == 1 then 0 else 6, 0, 40),
			Size = UDim2.new(0.5, -6, 1, -76),
			BackgroundColor3 = config.darkColor,
			Parent = sheet,
		}, { UI.corner(10), UI.padding(8) })
		UI.label(config.name, 20, { Name = "Header", TextColor3 = config.color, Parent = column })
		local rows = UI.new("Frame", {
			Name = "Rows",
			Position = UDim2.new(0, 0, 0, 30),
			Size = UDim2.new(1, 0, 1, -30),
			BackgroundTransparency = 1,
			Parent = column,
		}, { UI.list(Enum.FillDirection.Vertical, 2) })
		p.columns[team] = rows
	end
	p.spectators = UI.label("", 15, {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		TextColor3 = C.muted,
		Parent = sheet,
	})
end

local function waitingText(counts: { [string]: number }): string
	local total = 0
	for _, team in TeamConfig.order do
		total += counts[team] or 0
	end
	local missing = GameConfig.MIN_ACTIVE_PLAYERS - total
	if missing > 0 then
		return `Need {missing} more player{if missing == 1 then "" else "s"} to start`
	end
	for _, team in TeamConfig.order do
		if (counts[team] or 0) == 0 then
			return `Waiting for someone on {TeamConfig.teams[team].name}`
		end
	end
	return "Starting..."
end
HUDController.waitingText = waitingText

local function renderTeams()
	local p = HUDController.parts
	local snapshot = ClientState.snapshot
	for _, panel in { p.left, p.right } do
		local team = panel.Name
		panel.Score.Text = tostring(if snapshot then snapshot.scoresByTeam[team] or 0 else 0)
		panel.Count.Text = `{ClientState.counts[team] or 0}/{ClientState.maxTeamSize}`
	end
	local teamId = ClientState.teamId()
	p.yourTeam.Visible = ClientState.isActive() and teamId ~= nil
	if teamId and TeamConfig.teams[teamId] then
		p.yourTeam.Text = `YOU: {string.upper(TeamConfig.teams[teamId].name)}`
		p.yourTeam.TextColor3 = TeamConfig.teams[teamId].color
	end
	local waiting = snapshot ~= nil and snapshot.phase == Phase.WAITING
	p.waiting.Visible = waiting
	if waiting then
		p.waiting.Text = waitingText(ClientState.counts)
	end
end

local function renderResults()
	local p = HUDController.parts
	local snapshot = ClientState.snapshot
	local show = snapshot ~= nil and snapshot.phase == Phase.RESULTS and snapshot.result ~= nil
	p.results.Enabled = show
	if not show then
		return
	end
	local result = (snapshot :: RoundClock.Snapshot).result :: any
	local scores = {}
	for _, team in TeamConfig.order do
		table.insert(scores, tostring(result.scores[team] or 0))
	end
	p.resultScores.Text = table.concat(scores, "  —  ")
	local winner = result.winner and TeamConfig.teams[result.winner]
	if winner then
		p.resultTitle.Text = `{string.upper(winner.name)} WIN!`
		p.resultTitle.TextColor3 = winner.color
	else
		p.resultTitle.Text = "DRAW!"
		p.resultTitle.TextColor3 = C.text
	end
	local mine = ClientState.teamId()
	if not ClientState.isActive() or not mine then
		p.resultYou.Text = "You were spectating"
	elseif result.draw then
		p.resultYou.Text = "Nobody out-farted anybody"
	elseif result.winner == mine then
		p.resultYou.Text = "Your team won!"
	else
		p.resultYou.Text = "Your team lost. Next round!"
	end
end

local function render()
	renderTeams()
	renderResults()
end

local function tick()
	local p = HUDController.parts
	local snapshot = ClientState.snapshot
	local remaining = ClientState.remaining()
	local phase = if snapshot then snapshot.phase else Phase.WAITING
	local live = phase == Phase.ACTIVE and snapshot ~= nil and snapshot.phaseEndTime == nil
	p.phase.Text = if live then UIConfig.phaseLabels.LIVE else UIConfig.phaseLabels[phase] or phase
	-- Any mode but the default says its name while it's on.
	if phase == Phase.ACTIVE and snapshot and snapshot.modeName and snapshot.mode ~= "TeamElimination" then
		p.phase.Text = string.upper(snapshot.modeName)
	end
	HUDController.renderZone()
	HUDController.renderEvent()
	p.time.Text = if live then "LIVE" elseif phase == Phase.WAITING then "--:--" else RoundClock.format(remaining)
	if phase == Phase.RESULTS then
		p.resultNext.Text = `Next round in {RoundClock.format(remaining)}`
	end
	if afkEndsAt then
		local left = math.max(0, afkEndsAt - workspace:GetServerTimeNow())
		p.afkCountdown.Text = `Moving you to spectators in {math.ceil(left)}s`
	end
end
HUDController.tick = tick

function HUDController.toast(text: string, seconds: number?)
	local p = HUDController.parts
	toastToken += 1
	local token = toastToken
	p.toastText.Text = text
	p.toast.Visible = true
	task.delay(seconds or UIConfig.toastSeconds, function()
		if toastToken == token then
			p.toast.Visible = false
		end
	end)
end

local function hideAfk()
	afkEndsAt = nil
	HUDController.parts.afk.Visible = false
end

local function onMessage(payload: { [string]: any })
	local p = HUDController.parts
	if payload.kind == "afkWarning" then
		afkEndsAt = tonumber(payload.endsAt)
		p.afkDetail.Text = payload.detail or ""
		p.afk.Visible = true
		tick()
	elseif payload.kind == "afkClear" then
		hideAfk()
	elseif payload.kind == "afkMoved" then
		hideAfk()
		HUDController.toast(payload.text, 6)
	else
		HUDController.toast(payload.text)
	end
end

local function showControlsOnce()
	if shownControls then
		return
	end
	shownControls = true
	local controls = HUDController.parts.controls
	controls.Visible = true
	task.delay(UIConfig.controlsSeconds, function()
		controls.Visible = false
	end)
end

local function renderScoreboard()
	local p = HUDController.parts
	for team, rows in p.columns do
		for _, child in rows:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local instance = nil
		for _, candidate in Teams:GetTeams() do
			if candidate:GetAttribute("TeamId") == team then
				instance = candidate
			end
		end
		local members = if instance then instance:GetPlayers() else {}
		table.sort(members, function(a, b)
			return a.DisplayName < b.DisplayName
		end)
		for i, member in members do
			local rank = member:GetAttribute("Prestige")
			local tag = if type(rank) == "number" and rank > 0 then `  [P{rank}]` else ""
			UI.label(`{member.DisplayName}{tag}`, 17, {
				Name = member.Name,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 22),
				Font = UIConfig.bodyFont,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if member == Players.LocalPlayer then C.accent else C.text,
				Parent = rows,
			})
		end
	end
	local watching = 0
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("State") ~= States.Player.ACTIVE then
			watching += 1
		end
	end
	p.spectators.Text = `Spectating: {watching}`
end
HUDController.renderScoreboard = renderScoreboard

-- The event banner, from Workspace's Event* attributes.
function HUDController.renderEvent()
	local p = HUDController.parts
	if not p.event then
		return
	end
	local id, phase = workspace:GetAttribute("Event"), workspace:GetAttribute("EventPhase")
	local texts = type(id) == "string" and UIConfig.events[id]
	if not (texts and (phase == "warning" or phase == "active")) then
		p.event.Visible = false
		return
	end
	local target = if phase == "warning" then workspace:GetAttribute("EventStartsAt") else workspace:GetAttribute("EventEndsAt")
	local seconds = math.max(0, math.ceil((if type(target) == "number" then target else 0) - workspace:GetServerTimeNow()))
	p.event.Text = string.format(texts[phase], seconds)
	p.event.Visible = true
end

-- The zone line, from the server's Zone* attributes on Workspace.
function HUDController.renderZone()
	local p = HUDController.parts
	if not p.zone then
		return
	end
	local on = workspace:GetAttribute("ZoneActive") == true
	p.zone.Visible = on
	if not on then
		return
	end
	local owner = workspace:GetAttribute("ZoneOwner")
	local team = type(owner) == "string" and TeamConfig.teams[owner]
	if team then
		p.zone.Text = string.format(UIConfig.zone.held, team.shortName)
		p.zone.TextColor3 = team.color
	elseif workspace:GetAttribute("ZoneContested") == true then
		local a = workspace:GetAttribute(`Zone_{TeamConfig.order[1]}`) or 0
		local b = workspace:GetAttribute(`Zone_{TeamConfig.order[2]}`) or 0
		p.zone.Text = string.format(UIConfig.zone.contested, a :: number, b :: number)
		p.zone.TextColor3 = C.text
	else
		p.zone.Text = UIConfig.zone.empty
		p.zone.TextColor3 = C.muted
	end
end

function HUDController.start()
	if started then
		return
	end
	started = true
	build()
	render()
	ClientState.SnapshotChanged:Connect(render)
	ClientState.TeamsChanged:Connect(renderTeams)
	ClientState.TeamChanged:Connect(render)
	ClientState.Message:Connect(onMessage)
	ClientState.StateChanged:Connect(function(state)
		render()
		if state == States.Player.ACTIVE then
			showControlsOnce()
		else
			hideAfk()
		end
	end)
	InputController.ScoreboardHeld:Connect(function(held)
		HUDController.parts.scoreboard.Enabled = held
		if held then
			renderScoreboard()
		end
	end)
	for _, name in { "ZoneActive", "ZoneOwner", "ZoneContested" } do
		workspace:GetAttributeChangedSignal(name):Connect(HUDController.renderZone)
	end
	for _, name in { "Event", "EventPhase" } do
		workspace:GetAttributeChangedSignal(name):Connect(HUDController.renderEvent)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			tick()
		end
	end)
	tick()
end

return HUDController
