-- The Players screen (masterplan 5.4): everyone else in the server, each
-- with BLOCK (Roblox's own block prompt, which also mutes them in chat),
-- HIDE EMOTES (on this screen only) and REPORT (a reason, sent to the
-- server for review). The note at the bottom says how to report through
-- Roblox too (Esc > Report), which is what reaches Roblox moderation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local Settings = require(Client.Settings)
local UI = require(Client.UI)

local C = UIConfig.colors

local PlayersController = {}

PlayersController.MESSAGES = table.freeze({
	sent = "Reported. Thanks for helping keep the game fair.",
	already = "You've already reported them this session.",
	tooMany = "That's all the reports you can send this session.",
	notHere = "They've left the server.",
	badPayload = "That report didn't go through.",
	error = "That report didn't go through. Try again in a moment.",
})
PlayersController.NOTE = "Reports here go to the game's team. For Roblox to act, report through the Roblox menu too: "
	.. "Esc > Report. Blocking also mutes them in chat."

PlayersController.parts = {} :: { [string]: any }
PlayersController.isOpen = false
-- The player whose REPORT reasons are showing, and the last answer per player.
PlayersController.reporting = nil :: number?
PlayersController.notes = {} :: { [number]: string }

local player = Players.LocalPlayer
local started = false
local render: () -> ()

function PlayersController.open()
	PlayersController.isOpen = true
	PlayersController.parts.screen.Enabled = true
	render()
end

function PlayersController.close()
	PlayersController.isOpen = false
	PlayersController.reporting = nil
	PlayersController.parts.screen.Enabled = false
end

function PlayersController.block(other: Player)
	pcall(StarterGui.SetCore, StarterGui, "PromptBlockPlayer", other)
end

function PlayersController.toggleEmotes(userId: number)
	if Settings.hiddenEmotes[userId] then
		Settings.hiddenEmotes[userId] = nil
	else
		Settings.hiddenEmotes[userId] = true
	end
	render()
end

-- Sends a report and shows the answer on the row.
function PlayersController.report(userId: number, reason: string): string
	local remote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ReportPlayer") :: RemoteFunction?
	local answer = "error"
	if remote then
		local ok, result = pcall(remote.InvokeServer, remote, userId, reason)
		if ok and type(result) == "table" and type(result.reason) == "string" then
			answer = result.reason
		end
	end
	PlayersController.reporting = nil
	PlayersController.notes[userId] = PlayersController.MESSAGES[answer] or PlayersController.MESSAGES.error
	render()
	return answer
end

local function others(): { Player }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		local ta, tb = tostring(a:GetAttribute("TeamId") or "~"), tostring(b:GetAttribute("TeamId") or "~")
		if ta ~= tb then
			return ta < tb
		end
		return a.DisplayName < b.DisplayName
	end)
	return list
end

local function small(text: string, color: Color3, x: number, width: number, parent: Instance, name: string): TextButton
	return UI.button(text, color, {
		Name = name,
		Position = UDim2.new(0, x, 0, 6),
		Size = UDim2.new(0, width, 0, 30),
		TextSize = 14,
		Parent = parent,
	})
end

render = function()
	local p = PlayersController.parts
	if not PlayersController.isOpen then
		return
	end
	for _, child in p.list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local list = others()
	p.empty.Visible = #list == 0
	for i, other in list do
		local userId = other.UserId
		local expanded = PlayersController.reporting == userId
		local note = PlayersController.notes[userId]
		local row = UI.new("Frame", {
			Name = tostring(userId),
			LayoutOrder = i,
			Size = UDim2.new(1, -8, 0, if expanded or note then 78 else 42),
			BackgroundColor3 = C.panelLight,
			Parent = p.list,
		}, { UI.corner(8) })
		local team = TeamConfig.teams[other:GetAttribute("TeamId") :: any]
		UI.new("Frame", {
			Name = "Team",
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(0, 6, 1, 0),
			BackgroundColor3 = if team then team.color else C.muted,
			BorderSizePixel = 0,
			Parent = row,
		})
		UI.label(`{UI.teamSymbol(other:GetAttribute("TeamId") :: any)}{other.DisplayName}  @{other.Name}`, 15, {
			Name = "PlayerName",
			Position = UDim2.new(0, 14, 0, 10),
			Size = UDim2.new(0, 210, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = UIConfig.bodyFont,
			Parent = row,
		})
		local block = small("BLOCK", C.panel, 230, 70, row, "Block")
		UI.onClick(block, function()
			PlayersController.block(other)
		end)
		local hidden = Settings.hiddenEmotes[userId] == true
		local emotes = small(if hidden then "SHOW EMOTES" else "HIDE EMOTES", C.panel, 306, 110, row, "Emotes")
		UI.onClick(emotes, function()
			PlayersController.toggleEmotes(userId)
		end)
		local report = small("REPORT", C.warning, 422, 76, row, "Report")
		UI.onClick(report, function()
			PlayersController.reporting = if expanded then nil else userId
			PlayersController.notes[userId] = nil
			render()
		end)
		if expanded then
			for j, reason in GameConfig.MODERATION.REPORT_REASONS do
				local button = UI.button(string.upper(reason), C.panel, {
					Name = reason,
					Position = UDim2.new(0, 14 + (j - 1) * 120, 0, 44),
					Size = UDim2.new(0, 112, 0, 28),
					TextSize = 13,
					Parent = row,
				})
				UI.onClick(button, function()
					PlayersController.report(userId, reason)
				end)
			end
		elseif note then
			UI.label(note, 14, {
				Name = "Note",
				Position = UDim2.new(0, 14, 0, 46),
				Size = UDim2.new(1, -28, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = C.accent,
				Font = UIConfig.bodyFont,
				Parent = row,
			})
		end
	end
end
PlayersController.render = render

local function build()
	local p = PlayersController.parts
	local screen = UI.screen("Players", 16)
	screen.Enabled = false
	p.screen = screen
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 560, 0, 470),
		BackgroundColor3 = C.panel,
		Parent = screen,
	}, { UI.corner(16), UI.stroke(C.stroke, 4), UI.padding(14) })
	UI.label("PLAYERS", 28, { Name = "Title", Parent = panel })
	local close = UI.button("X", C.warning, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 40, 0, 40),
		Modal = true,
		Parent = panel,
	})
	UI.onClick(close, PlayersController.close)
	local list = UI.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 1, -120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, 6) })
	p.list = list
	p.empty = UI.label("Nobody else is here yet.", 16, {
		Name = "Empty",
		Position = UDim2.new(0, 0, 0, 60),
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Visible = false,
		Parent = panel,
	})
	p.note = UI.label(PlayersController.NOTE, 13, {
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 62),
		TextWrapped = true,
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
end

function PlayersController.start()
	if started then
		return
	end
	started = true
	build()
	Players.PlayerAdded:Connect(function()
		render()
	end)
	Players.PlayerRemoving:Connect(function(other)
		PlayersController.notes[other.UserId] = nil
		if PlayersController.reporting == other.UserId then
			PlayersController.reporting = nil
		end
		task.defer(render)
	end)
end

return PlayersController
