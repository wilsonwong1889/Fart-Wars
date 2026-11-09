-- The match screens:
--   HUD           the score boxes (each team's colour, score and player
--                 count) either side of the timer and round state; your
--                 team; messages; the AFK warning; the one-time controls
--                 card on a first PLAY
--   ResultsScreen the winner (or draw) and the countdown to the next round,
--                 over the round's award cards (Top Fragger and co.: the
--                 winner's headshot, name and number)
--   Scoreboard    Tab (held): who is on each team, any bots after the
--                 players (stats come with combat)
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
local Combatants = require(Client.Combatants)
local UI = require(Client.UI)
local Settings = require(Client.Settings)
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
	UI.label(`{config.symbol} {config.shortName}`, 15, {
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

-- The results: the winner's card with up to four award cards in a row
-- under it, all in one block (Stack), so the HUD size scales them as one.
local RESULT_CARD = Vector2.new(560, 220)
local AWARD_CARD = Vector2.new(150, 190)
local AWARD_GAP = 10
local AWARD_SLOTS = 4
local STACK_WIDTH = AWARD_SLOTS * AWARD_CARD.X + (AWARD_SLOTS - 1) * AWARD_GAP
local STACK_HEIGHT = RESULT_CARD.Y + 12 + AWARD_CARD.Y
local AWARD_GOLD = Color3.fromRGB(255, 205, 50)

-- One award card: the award, the winner's face (a headshot; a bot's is a
-- robot), the award's badge on it, their name, the number and a line to go
-- with it. renderAwards fills it in.
local function awardCard(order: number, parent: Instance): Frame
	local card = UI.new("Frame", {
		Name = `Award{order}`,
		LayoutOrder = order,
		Size = UDim2.new(0, AWARD_CARD.X, 0, AWARD_CARD.Y),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = parent,
	}, { UI.corner(14), UI.stroke(C.stroke, 3), UI.padding(6) })
	local title = UI.label("", 16, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = AWARD_GOLD,
		TextScaled = true,
		Parent = card,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = title })
	local face = UI.new("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		Size = UDim2.new(0, 64, 0, 64),
		BackgroundColor3 = C.panelLight,
		Parent = card,
	}, { UI.corner(32), UI.stroke(C.stroke, 3) })
	UI.new("ImageLabel", {
		Name = "Headshot",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Image = "",
		Parent = face,
	}, { UI.corner(32) })
	-- A bot's robot, or a player's initial until their headshot arrives.
	UI.label("", 30, { Name = "Glyph", Size = UDim2.new(1, 0, 1, 0), Parent = face })
	local badge = UI.label("", 16, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 1, -6),
		Size = UDim2.new(0, 28, 0, 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.panel,
		ZIndex = 2,
		Parent = face,
	})
	UI.corner(14).Parent = badge
	UI.label("", 15, {
		Name = "PlayerName",
		Position = UDim2.new(0, 0, 0, 92),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UIConfig.bodyFont,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	UI.label("", 28, { Name = "Value", Position = UDim2.new(0, 0, 0, 108), Size = UDim2.new(1, 0, 0, 28), Parent = card })
	UI.label("", 11, {
		Name = "Unit",
		Position = UDim2.new(0, 0, 0, 135),
		Size = UDim2.new(1, 0, 0, 13),
		Font = UIConfig.bodyFont,
		TextColor3 = C.muted,
		Parent = card,
	})
	UI.label("", 12, {
		Name = "Line",
		Position = UDim2.new(0, 0, 0, 149),
		Size = UDim2.new(1, 0, 0, 29),
		TextWrapped = true,
		TextColor3 = C.accent,
		Parent = card,
	})
	return card
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
	-- Gas Control: who holds the zone (in words as well as colour), and
	-- under it, while a team is taking it, a bar filling in its colour.
	p.zone = UI.label("", 18, {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 174),
		Size = UDim2.new(0, 560, 0, 24),
		Visible = false,
		Parent = hud,
	})
	p.zoneBar = UI.new("Frame", {
		Name = "Capture",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(0, 260, 0, 6),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Visible = false,
		Parent = p.zone,
	}, { UI.corner(3) })
	p.zoneFill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BorderSizePixel = 0,
		Parent = p.zoneBar,
	}, { UI.corner(3) })
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

	-- On its own screen above every menu and the results (the HUD is under
	-- them), so someone idling in the shop sees it before being moved off
	-- their team; under the update screen.
	local afkScreen = UI.screen("AFKWarning", 25)
	p.afkScreen = afkScreen
	local afk = UI.new("Frame", {
		Name = "AFKWarning",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 620, 0, 150),
		BackgroundColor3 = C.warning,
		Visible = false,
		Parent = afkScreen,
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
	local stack = UI.new("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, STACK_WIDTH, 0, RESULT_CARD.Y),
		BackgroundTransparency = 1,
		Parent = results,
	})
	p.resultStack = stack
	local card = UI.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, RESULT_CARD.X, 0, RESULT_CARD.Y),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Parent = stack,
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
	p.awards = UI.new("Frame", {
		Name = "Awards",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, AWARD_CARD.Y),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = stack,
	}, { UI.list(Enum.FillDirection.Horizontal, AWARD_GAP, Enum.HorizontalAlignment.Center) })
	p.awardCards = {}
	for i = 1, AWARD_SLOTS do
		p.awardCards[i] = awardCard(i, p.awards)
	end

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

-- Players' headshots by user ID: asked for once (GetUserThumbnailAsync
-- yields, so never while drawing), then kept for the session. One that
-- fails (a Studio test player) is asked again next round at most.
HUDController.headshots = {} :: { [number]: string }
local askedInRound: { [number]: number } = {}

local function showHeadshot(card: Frame, userId: number, roundId: number)
	local face = (card :: any).Face
	local image = HUDController.headshots[userId]
	face.Headshot.Image = image or ""
	face.Glyph.Visible = image == nil
	if image or askedInRound[userId] == roundId then
		return
	end
	askedInRound[userId] = roundId
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if not (ok and type(content) == "string" and content ~= "") then
			return
		end
		HUDController.headshots[userId] = content
		for _, other in HUDController.parts.awardCards do
			if other:GetAttribute("UserId") == userId then
				local otherFace = (other :: any).Face
				otherFace.Headshot.Image = content
				otherFace.Glyph.Visible = false
			end
		end
	end)
end

-- A name's first letter or digit, for the face until the headshot comes.
local function initial(name: string): string
	return string.upper(string.match(name, "%w") or "?")
end

local function fillAward(card: Frame, award: RoundClock.Award, look: any, roundId: number)
	local c = card :: any
	c.Title.Text = look.title
	c.Face.Badge.Text = look.icon
	c.PlayerName.Text = award.name
	local mine = not award.bot and award.id == Players.LocalPlayer.UserId
	c.PlayerName.TextColor3 = if mine then C.accent else C.text
	c.Value.Text = tostring(award.value)
	c.Unit.Text = if award.value == 1 then look.one else look.many
	-- One line a round, the same on every screen; a bot gets roasted.
	c.Line.Text = if award.bot then UIConfig.awardBotLine else look.lines[roundId % #look.lines + 1]
	local team = award.team and TeamConfig.teams[award.team]
	c.Face.Border.Color = if team then team.color else C.stroke
	card:SetAttribute("UserId", if award.bot then nil else award.id)
	if award.bot then
		c.Face.Headshot.Image = ""
		c.Face.Glyph.Text = "🤖"
		c.Face.Glyph.Visible = true
	else
		c.Face.Glyph.Text = initial(award.name)
		showHeadshot(card, award.id, roundId)
	end
end

-- Which round's awards are up, and how many of its cards are out yet.
local awardsRound: number? = nil
local revealed = 0
local revealToken = 0

-- A new round's cards come in one at a time, each with a pop; with Reduce
-- Motion they're all there at once, still.
local function revealAwards(count: number)
	revealToken += 1
	local token = revealToken
	if Settings.reduceMotion or count == 0 then
		revealed = AWARD_SLOTS
		return
	end
	revealed = 0
	task.spawn(function()
		for i = 1, count do
			task.wait(UIConfig.awardRevealSeconds)
			if token ~= revealToken then
				return
			end
			revealed = i
			local card = HUDController.parts.awardCards[i]
			card.Visible = true
			UI.pop(card, 1.25)
		end
	end)
end

-- The award cards from the snapshot (nothing earned, or awards off: none,
-- and the winner's card sits where it always did).
local function renderAwards(snapshot: RoundClock.Snapshot)
	local p = HUDController.parts
	local list = if type(snapshot.awards) == "table" then snapshot.awards else {}
	local filled = 0
	for _, award in list do
		local look = type(award) == "table" and UIConfig.awards[award.award]
		if look and filled < AWARD_SLOTS then
			filled += 1
			fillAward(p.awardCards[filled], award, look, snapshot.roundId)
		end
	end
	if awardsRound ~= snapshot.roundId then
		awardsRound = snapshot.roundId
		revealAwards(filled)
	end
	for i, card in p.awardCards do
		card.Visible = i <= filled and i <= revealed
	end
	local any = filled > 0
	p.awards.Visible = any
	p.resultStack.Size = UDim2.new(0, STACK_WIDTH, 0, if any then STACK_HEIGHT else RESULT_CARD.Y)
	p.resultStack.Position = UDim2.new(0.5, 0, if any then 0.5 else 0.45, 0)
end

local function renderResults()
	local p = HUDController.parts
	local snapshot = ClientState.snapshot
	-- (Not over the practice yard: it isn't in the round.)
	local show = snapshot ~= nil and snapshot.phase == Phase.RESULTS and snapshot.result ~= nil and not ClientState.inPractice()
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
	-- A zone round's results say which mode it was, in its own words.
	local zone = if (snapshot :: RoundClock.Snapshot).objective == "zone" then UIConfig.zone.results else nil
	if not ClientState.isActive() or not mine then
		p.resultYou.Text = "You were spectating"
	elseif result.draw then
		p.resultYou.Text = if zone then zone.draw else "Nobody out-farted anybody"
	elseif result.winner == mine then
		p.resultYou.Text = if zone then zone.won else "Your team won!"
	else
		p.resultYou.Text = if zone then zone.lost else "Your team lost. Next round!"
	end
	renderAwards(snapshot :: RoundClock.Snapshot)
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
	-- Each team's bots: the ones on the field, then, up to the team's bot
	-- count, the ones between lives, so a bot waiting to respawn stays
	-- listed the way a player who's down does.
	local botsOn: { [string]: { Combatants.Combatant } } = {}
	for _, bot in Combatants.bots(true) do
		local team = bot.team
		if team then
			local list = botsOn[team] or {}
			botsOn[team] = list
			if bot.character or #list < (ClientState.bots[team] or 0) then
				table.insert(list, bot)
			end
		end
	end
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
		-- The bots after the players, by name (their names say they're bots).
		local bots = botsOn[team] or {}
		table.sort(bots, function(a, b)
			return if a.name ~= b.name then a.name < b.name else a.id > b.id
		end)
		for i, bot in bots do
			UI.label(bot.name, 17, {
				Name = tostring(bot.id),
				LayoutOrder = #members + i,
				Size = UDim2.new(1, 0, 0, 22),
				Font = UIConfig.bodyFont,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = C.muted,
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

-- The zone line, from the server's Zone* attributes on Workspace: the
-- standoff; the holder in it and scoring; a team in it taking it; the
-- holder away; or nobody's yet. The bar under it shows any capture (going
-- up, frozen in a standoff, or running back down).
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
	local words = UIConfig.zone
	local function teamAt(attribute: string): string?
		local id = workspace:GetAttribute(attribute)
		return if type(id) == "string" and TeamConfig.teams[id] then id else nil
	end
	local function inZone(team: string?): number
		local n = team and workspace:GetAttribute(`Zone_{team}`)
		return if type(n) == "number" then n else 0
	end
	local owner, taker = teamAt("ZoneOwner"), teamAt("ZoneCapturing")
	local progress = math.clamp(tonumber(workspace:GetAttribute("ZoneProgress")) or 0, 0, 1)
	if workspace:GetAttribute("ZoneContested") == true then
		p.zone.Text = string.format(words.contested, inZone(TeamConfig.order[1]), inZone(TeamConfig.order[2]))
		p.zone.TextColor3 = C.text
	elseif owner and inZone(owner) > 0 then
		p.zone.Text = string.format(words.held, TeamConfig.teams[owner].shortName)
		p.zone.TextColor3 = TeamConfig.teams[owner].color
	elseif taker and inZone(taker) > 0 then
		p.zone.Text = string.format(words.capturing, TeamConfig.teams[taker].shortName, math.floor(progress * 100 + 1e-6))
		p.zone.TextColor3 = TeamConfig.teams[taker].color
	elseif owner then
		p.zone.Text = string.format(words.idle, TeamConfig.teams[owner].shortName)
		p.zone.TextColor3 = TeamConfig.teams[owner].color
	else
		p.zone.Text = words.empty
		p.zone.TextColor3 = C.muted
	end
	p.zoneBar.Visible = taker ~= nil and progress > 0
	if taker then
		p.zoneFill.BackgroundColor3 = TeamConfig.teams[taker].color
		p.zoneFill.Size = UDim2.new(progress, 0, 1, 0)
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
	-- Held open, it keeps up: lives, joins, leaves and team moves.
	local function refreshScoreboard()
		if HUDController.parts.scoreboard.Enabled then
			renderScoreboard()
		end
	end
	Combatants.AvatarAdded:Connect(refreshScoreboard)
	Combatants.AvatarRemoved:Connect(refreshScoreboard)
	ClientState.TeamsChanged:Connect(refreshScoreboard)
	for _, name in { "ZoneActive", "ZoneOwner", "ZoneContested", "ZoneCapturing", "ZoneProgress" } do
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
