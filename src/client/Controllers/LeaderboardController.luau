-- The weekly leaderboard (FeatureFlags.LEADERBOARD; LeaderboardConfig), from
-- the home screen's TOP tile and the M menu's LEADERBOARD: this week's top 10
-- in eliminations and in round wins (a tab each; continuous play has no
-- rounds, so no wins tab), with avatars and ranks (a tie shares one), your
-- own line under them, and the countdown to Monday 00:00 UTC, when both
-- boards start again. What it shows comes from the server
-- (LeaderboardRequest): asked on opening, every REFRESH_SECONDS while open
-- and when the week turns. While the server can't read a board (or, once
-- the week is over, until the new week's boards arrive), the screen says
-- the leaderboard is napping. A change of state (PLAY, leaving the match)
-- closes it; the mouse is free while it's open (MouseLock "Leaderboard").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)
local UIConfig = require(Shared.Config.UIConfig)
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local MouseLock = require(Client.MouseLock)

local C = UIConfig.colors
-- The TOP tile's colour.
local TEAL = Color3.fromRGB(30, 185, 160)
local MINE = Color3.fromRGB(28, 92, 84)
local MEDALS = { Color3.fromRGB(255, 205, 50), Color3.fromRGB(205, 215, 230), Color3.fromRGB(230, 145, 80) }
local ROW_HEIGHT = 32
local ROW_GAP = 4

local LeaderboardController = {}

LeaderboardController.TEXT = table.freeze({
	title = "📊 THIS WEEK'S TOP STINKERS",
	resets = "⏰ RESETS IN %s · MONDAY 00:00 UTC",
	loading = "SNIFFING OUT THE TOP STINKERS...",
	napIcon = "😴",
	nap = "LEADERBOARD IS TAKING A NAP",
	napNote = "The scores are safe. Check back in a bit!",
	empty = "NOBODY'S ON THE BOARD YET. GO CLAIM #1!",
	you = "YOU",
	unknown = "?",
	footer = "REAL PLAYERS ONLY · BOTS DON'T COUNT",
})

LeaderboardController.parts = {} :: { [string]: any }
LeaderboardController.isOpen = false
-- The server's last answer (LeaderboardService.View), and the tab showing.
LeaderboardController.view = nil :: { [string]: any }?
LeaderboardController.tab = LeaderboardConfig.boards[1].id
-- The last request went unanswered and there's nothing older to show.
LeaderboardController.failed = false
LeaderboardController.busy = false

local TEXT = LeaderboardController.TEXT
local receivedAt = 0
-- The reset a request was already made for, once the countdown ran out.
local askedAtReset = 0
local enabledOverride: boolean? = nil
local started = false

-- Test seam: on or off whatever the flag says (nil: the flag).
function LeaderboardController.testEnable(enabled: boolean?)
	enabledOverride = enabled
end

function LeaderboardController.enabled(): boolean
	if enabledOverride ~= nil then
		return enabledOverride
	end
	return FeatureFlags.LEADERBOARD == true
end

-- "2d 04h 09m", "4h 09m 30s", "9m 30s".
function LeaderboardController.countdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days, hours, minutes = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if days > 0 then
		return string.format("%dd %02dh %02dm", days, hours, minutes)
	elseif hours > 0 then
		return string.format("%dh %02dm %02ds", hours, minutes, seconds % 60)
	end
	return string.format("%dm %02ds", minutes, seconds % 60)
end

-- Seconds until the boards start again, on the server's clock.
function LeaderboardController.secondsLeft(): number
	local view = LeaderboardController.view
	if view then
		return view.resetsAt - view.serverNow - (os.clock() - receivedAt)
	end
	local now = workspace:GetServerTimeNow()
	return LeaderboardConfig.resetsAt(now) - now
end

local function thumbnail(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

local function boardDef(id: string): LeaderboardConfig.Board?
	for _, board in LeaderboardConfig.boards do
		if board.id == id then
			return board
		end
	end
	return nil
end

local function renderCountdown()
	LeaderboardController.parts.countdown.Text = string.format(TEXT.resets, LeaderboardController.countdown(LeaderboardController.secondsLeft()))
end

local function fill(row: any, rank: string, rankColor: Color3, userId: number, name: string, value: string)
	row.Rank.Text = rank
	row.Rank.TextColor3 = rankColor
	row.Avatar.Image = thumbnail(userId)
	row.PlayerName.Text = name
	row.Count.Text = value
end

local function render()
	local p = LeaderboardController.parts
	local view = LeaderboardController.view
	-- The tabs this view has (all of them until one arrives).
	local board = nil
	if view then
		board = view.boards[LeaderboardController.tab]
		if not board then
			for _, def in LeaderboardConfig.boards do
				if view.boards[def.id] then
					LeaderboardController.tab = def.id
					board = view.boards[def.id]
					break
				end
			end
		end
	end
	for _, def in LeaderboardConfig.boards do
		local tab = p.tabs[def.id]
		tab.Visible = view == nil or view.boards[def.id] ~= nil
		UI.paint(tab, if def.id == LeaderboardController.tab then def.color else C.panelLight)
	end
	renderCountdown()

	local loading = view == nil and not LeaderboardController.failed
	-- A view from a week that has ended isn't shown as if it were this one.
	local over = view ~= nil and LeaderboardController.secondsLeft() <= 0
	local napping = LeaderboardController.failed or over or (view ~= nil and (board == nil or board.napping))
	local showing = not loading and not napping
	p.nap.Visible = napping
	p.list.Visible = showing
	p.you.Visible = showing
	p.status.Visible = loading or (showing and #board.top == 0)
	p.status.Text = if loading then TEXT.loading else TEXT.empty
	if not showing then
		return
	end

	for i, row in p.rows do
		local entry = board.top[i]
		row.Visible = entry ~= nil
		if entry then
			fill(
				row,
				`#{entry.rank}`,
				MEDALS[entry.rank] or C.text,
				entry.userId,
				if entry.you then `{entry.name} ({TEXT.you})` else entry.name,
				UI.commas(entry.value)
			)
			row.BackgroundColor3 = if entry.you then MINE else C.panelLight
		end
	end

	local you = board.you
	local me = Players.LocalPlayer.UserId
	local def = boardDef(board.id)
	if you.rank then
		fill(p.you, `#{you.rank}`, MEDALS[you.rank] or C.text, me, TEXT.you, UI.commas(you.value))
	elseif you.beyond then
		fill(p.you, `#{LeaderboardConfig.PAGE_SIZE}+`, C.text, me, TEXT.you, if you.value then UI.commas(you.value) else TEXT.unknown)
	else
		fill(p.you, "—", C.muted, me, `{TEXT.you} · {if def then def.hint else ""}`, "0")
	end
end
LeaderboardController.render = render

-- Asks the server for the boards (one request at a time). Without an
-- answer, an older view stays up; with none, the screen naps.
function LeaderboardController.refresh()
	if LeaderboardController.busy then
		return
	end
	LeaderboardController.busy = true
	local remote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("LeaderboardRequest") :: RemoteFunction?
	local ok, answer = false, nil
	if remote then
		ok, answer = pcall(remote.InvokeServer, remote)
	end
	LeaderboardController.busy = false
	if ok and type(answer) == "table" and answer.ok == true and type(answer.boards) == "table" then
		LeaderboardController.view = answer
		LeaderboardController.failed = false
		receivedAt = os.clock()
	elseif not (ok and type(answer) == "table" and answer.reason == "tooFast") then
		LeaderboardController.failed = LeaderboardController.view == nil
	end
	if LeaderboardController.isOpen then
		render()
	end
end

function LeaderboardController.open()
	LeaderboardController.isOpen = true
	LeaderboardController.parts.screen.Enabled = true
	MouseLock.setFree("Leaderboard", true)
	render()
	task.spawn(LeaderboardController.refresh)
end

function LeaderboardController.close()
	LeaderboardController.isOpen = false
	LeaderboardController.parts.screen.Enabled = false
	MouseLock.setFree("Leaderboard", false)
end

function LeaderboardController.select(tab: string)
	if boardDef(tab) then
		LeaderboardController.tab = tab
		render()
	end
end

-- One line of the board: Rank, Avatar, PlayerName and Count (not "Name":
-- that's the frame's own name).
local function row(name: string, order: number, props: { [string]: any }): Frame
	local frame = UI.new("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = C.panelLight,
	}, { UI.corner(8) })
	for key, value in props do
		(frame :: any)[key] = value
	end
	UI.label("", 18, {
		Name = "Rank",
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(0, 58, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	UI.new("ImageLabel", {
		Name = "Avatar",
		Position = UDim2.new(0, 68, 0.5, -13),
		Size = UDim2.new(0, 26, 0, 26),
		BackgroundColor3 = C.panel,
		Image = "",
		Parent = frame,
	}, { UI.corner(13) })
	UI.label("", 16, {
		Name = "PlayerName",
		Position = UDim2.new(0, 102, 0, 0),
		Size = UDim2.new(1, -214, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = UIConfig.bodyFont,
		Parent = frame,
	})
	UI.label("", 18, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 100, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})
	return frame
end

local function build()
	local p = LeaderboardController.parts
	local screen = UI.screen("Leaderboard", 16)
	screen.Enabled = false
	p.screen = screen
	local listTop = 124
	local listHeight = LeaderboardConfig.SHOWN * (ROW_HEIGHT + ROW_GAP)
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 600, 0, listTop + listHeight + 116),
		BackgroundColor3 = C.panel,
		-- A click on the window stays on it.
		Active = true,
		Parent = screen,
	}, { UI.corner(16), UI.stroke(TEAL, 4), UI.padding(16) })
	p.panel = panel
	p.title = UI.label(TEXT.title, 28, {
		Name = "Title",
		Size = UDim2.new(1, -50, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = TEAL,
		Parent = panel,
	})
	local close = UI.button("X", C.warning, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 40, 0, 40),
		Modal = true,
		Parent = panel,
	})
	UI.onClick(close, LeaderboardController.close)
	p.countdown = UI.label("", 15, {
		Name = "Countdown",
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(1, -50, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	p.tabs = {}
	for i, board in LeaderboardConfig.boards do
		local tab = UI.chunky(board.label, board.color, board.icon, {
			Name = board.id,
			Position = UDim2.new(0, (i - 1) * 222, 0, 68),
			Size = UDim2.new(0, 212, 0, 44),
			TextSize = 18,
			Parent = panel,
		})
		p.tabs[board.id] = tab
		UI.onClick(tab, function()
			LeaderboardController.select(board.id)
		end)
	end

	p.list = UI.new("Frame", {
		Name = "List",
		Position = UDim2.new(0, 0, 0, listTop),
		Size = UDim2.new(1, 0, 0, listHeight),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, ROW_GAP) })
	p.rows = {}
	for i = 1, LeaderboardConfig.SHOWN do
		p.rows[i] = row(`Row{i}`, i, { Visible = false, Parent = p.list })
	end
	p.status = UI.label(TEXT.loading, 20, {
		Name = "Status",
		Position = UDim2.new(0, 0, 0, listTop + 40),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = C.muted,
		Parent = panel,
	})
	p.nap = UI.new("Frame", {
		Name = "Nap",
		Position = UDim2.new(0, 0, 0, listTop),
		Size = UDim2.new(1, 0, 0, listHeight),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = panel,
	})
	UI.label(TEXT.napIcon, 64, { Name = "Icon", Position = UDim2.new(0, 0, 0, 70), Size = UDim2.new(1, 0, 0, 70), Parent = p.nap })
	UI.label(TEXT.nap, 26, { Name = "Title", Position = UDim2.new(0, 0, 0, 150), TextColor3 = TEAL, Parent = p.nap })
	UI.label(TEXT.napNote, 16, {
		Name = "Note",
		Position = UDim2.new(0, 0, 0, 186),
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = p.nap,
	})
	p.you = row("You", 0, {
		Position = UDim2.new(0, 0, 0, listTop + listHeight + 8),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = MINE,
		Visible = false,
		Parent = panel,
	})
	UI.stroke(TEAL, 3).Parent = p.you
	p.footer = UI.label(TEXT.footer, 13, {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	render()
end

function LeaderboardController.start()
	if started then
		return
	end
	started = true
	build()
	-- PLAY, leaving the match or being moved out of it.
	ClientState.StateChanged:Connect(LeaderboardController.close)
	task.spawn(function()
		local sinceAsked = 0
		while true do
			task.wait(1)
			if LeaderboardController.isOpen then
				sinceAsked += 1
				local view = LeaderboardController.view
				local turned = view ~= nil and LeaderboardController.secondsLeft() <= 0 and askedAtReset ~= view.resetsAt
				if turned or sinceAsked >= LeaderboardConfig.REFRESH_SECONDS then
					if turned then
						askedAtReset = (view :: any).resetsAt
					end
					sinceAsked = 0
					task.spawn(LeaderboardController.refresh)
				end
				renderCountdown()
			else
				sinceAsked = 0
			end
		end
	end)
end

return LeaderboardController
