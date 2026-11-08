-- The rewards screens.
--   DailyRewards  the seven-day track: each day's reward, the days already
--                 claimed ticked, today's lit up, CLAIM when it's open,
--                 and the exact time to the next reset. Opens by itself on
--                 the home screen when a claim is waiting (once a session).
--   SpinWheel     free spins: a prize wheel (SpinWheel) with every prize's
--                 exact chance, SPIN, the wheel winding up, spinning and
--                 landing on what the server drew, the win, and how long
--                 until the next free spin (active play only).
-- The server decides everything (RewardsRequest); these only ask and show.
-- Each frees the mouse while it's open (MouseLock, under its own name).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardsConfig = require(Shared.Config.RewardsConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local MouseLock = require(Client.MouseLock)
local Audio = require(Client.Audio)
local Settings = require(Client.Settings)
local SpinWheel = require(Client.SpinWheel)
local HealthController = require(script.Parent.HealthController)

local C = UIConfig.colors
local GOLD = Color3.fromRGB(255, 205, 50)
local MONEY = Color3.fromRGB(90, 210, 70)
local WHEEL_RADIUS = 175

local RewardsController = {}

RewardsController.parts = {} :: { [string]: any }
-- The latest status from the server.
RewardsController.status = nil :: { [string]: any }?
RewardsController.busy = false

local player = Players.LocalPlayer
local resetAt = 0 -- os.clock() when the daily resets
local shownToday = false
local started = false

local function ask(action: string): { [string]: any }?
	local remote = ClientState.remote("RewardsRequest") :: RemoteFunction
	local sentAt = os.clock()
	local ok, answer = pcall(remote.InvokeServer, remote, action)
	HealthController.noteLatency(os.clock() - sentAt)
	return if ok and type(answer) == "table" then answer else nil
end

local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%dh %02dm %02ds", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

local function closeButton(parent: Instance, onClose: () -> ())
	local close = UI.button("X", C.panelLight, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 46, 0, 46),
		TextSize = 26,
		Modal = true,
		Parent = parent,
	})
	UI.onClick(close, onClose)
end

local function panel(screen: Instance, name: string, size: UDim2): Frame
	return UI.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = size,
		BackgroundColor3 = Color3.fromRGB(20, 18, 28),
		BackgroundTransparency = 0.04,
		-- A click on the window stays on it (not PLAY under it).
		Active = true,
		Parent = screen,
	}, { UI.corner(18), UI.stroke(Color3.fromRGB(70, 66, 84), 4) })
end

local function build()
	local p = RewardsController.parts

	-- Daily rewards
	local daily = UI.screen("DailyRewards", 16)
	daily.Enabled = false
	p.daily = daily
	local box = panel(daily, "Panel", UDim2.new(0, 860, 0, 420))
	UI.label("🎁 DAILY REWARDS!", 50, { Name = "Title", Position = UDim2.new(0, 0, 0, 18), Size = UDim2.new(1, 0, 0, 56), Parent = box })
	UI.label("Come back every day for a bigger reward! Missing a day doesn't reset your track.", 17, {
		Name = "Subtitle",
		Position = UDim2.new(0, 0, 0, 78),
		Size = UDim2.new(1, 0, 0, 24),
		Font = UIConfig.bodyFont,
		Parent = box,
	})
	closeButton(box, RewardsController.closeDaily)
	local row = UI.new("Frame", {
		Name = "Days",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 116),
		Size = UDim2.new(1, -40, 0, 170),
		BackgroundTransparency = 1,
		Parent = box,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	p.days = {}
	for day, reward in RewardsConfig.daily do
		local special = reward.spins ~= nil or reward.cosmetic ~= nil
		local column = UI.new("Frame", { Name = `Day{day}`, LayoutOrder = day, Size = UDim2.new(0, 106, 1, 0), BackgroundTransparency = 1, Parent = row })
		local tag = UI.new("Frame", {
			Name = "Tag",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.new(0, 86, 0, 30),
			BackgroundColor3 = Color3.fromRGB(40, 36, 52),
			Parent = column,
		}, { UI.corner(8), UI.stroke(C.stroke, 2) })
		UI.label(`Day {day}`, 18, { Size = UDim2.new(1, 0, 1, 0), Parent = tag })
		local card = UI.box("Card", if special then GOLD else MONEY, UDim2.new(1, 0, 0, 128), { Position = UDim2.new(0, 0, 0, 38) })
		card.Parent = column
		UI.label(if reward.cosmetic then "✨" elseif reward.spins then "🎡" else "💰", 40, {
			Name = "Icon",
			Position = UDim2.new(0, 0, 0, 10),
			Size = UDim2.new(1, 0, 0, 48),
			Parent = card,
		})
		local extra = if reward.cosmetic then ProgressionConfig.cosmetics[reward.cosmetic].name
			elseif reward.spins then `+{reward.spins} spin`
			else ""
		UI.label(`{reward.coins}`, 26, { Name = "Coins", Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 30), Parent = card })
		UI.label(extra, 12, {
			Name = "Extra",
			Position = UDim2.new(0, 4, 0, 94),
			Size = UDim2.new(1, -8, 0, 28),
			TextWrapped = true,
			Parent = card,
		})
		local done = UI.label("✓", 64, {
			Name = "Done",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 0.35,
			BackgroundColor3 = Color3.new(0, 0, 0),
			TextColor3 = C.accent,
			ZIndex = 3,
			Visible = false,
			Parent = card,
		})
		p.days[day] = { column = column, card = card, done = done }
	end
	local claim = UI.button("CLAIM!", C.play, {
		Name = "Claim",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 300),
		Size = UDim2.new(0, 280, 0, 64),
		TextSize = 40,
		Parent = box,
	})
	p.claim = claim
	UI.onClick(claim, RewardsController.claim)
	p.dailyNote = UI.label("", 22, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 372),
		Size = UDim2.new(1, -40, 0, 28),
		Parent = box,
	})

	-- The free spin: the wheel, SPIN under it, and a note.
	local wheel = UI.screen("SpinWheel", 16)
	wheel.Enabled = false
	p.wheel = wheel
	local spinBox = panel(wheel, "Panel", UDim2.new(0, 560, 0, 604))
	UI.label("🎡 FREE SPIN", 42, { Name = "Title", Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 46), Parent = spinBox })
	closeButton(spinBox, RewardsController.closeSpin)
	local spinner = SpinWheel.new(spinBox, RewardsConfig.spin, RewardsConfig.chance, WHEEL_RADIUS)
	spinner.holder.Position = UDim2.new(0.5, 0, 0, 84 + spinner.holder.Size.Y.Offset / 2)
	p.spinner = spinner
	-- Each prize's card on the wheel (its Chance shows the exact odds).
	p.prizes = spinner.cards
	local spin = UI.button("SPIN!", C.play, {
		Name = "Spin",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 480),
		Size = UDim2.new(0, 240, 0, 60),
		TextSize = 36,
		Parent = spinBox,
	})
	p.spin = spin
	UI.onClick(spin, RewardsController.spin)
	p.spinNote = UI.label("", 18, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 546),
		Size = UDim2.new(1, -40, 0, 50),
		TextWrapped = true,
		Font = UIConfig.bodyFont,
		Parent = spinBox,
	})
end

-- Daily: which days are done, which is today's, CLAIM or the countdown.
local function renderDaily()
	local p = RewardsController.parts
	local status = RewardsController.status
	local day = tonumber(player:GetAttribute("DailyDay")) or (status and status.day) or 1
	local ready = player:GetAttribute("DailyReady") == true
	-- Claimed so far this loop of the track: the days before the next one.
	local claimedThrough = day - 1
	for i, entry in p.days do
		local isToday = ready and i == day
		entry.done.Visible = i <= claimedThrough
		entry.card.Border.Color = if isToday then C.text else C.stroke
		entry.card.Border.Thickness = if isToday then 5 else 3
	end
	UI.setEnabled(p.claim, ready and not RewardsController.busy)
	p.claim.Text = if ready then "CLAIM!" else "CLAIMED"
	local left = resetAt - os.clock()
	p.dailyNote.Text = if ready then `Day {day} is waiting for you!` else `Next reward in {clockText(left)}`
end
RewardsController.renderDaily = renderDaily

local function renderSpin()
	local p = RewardsController.parts
	local spins = tonumber(player:GetAttribute("Spins")) or 0
	UI.setEnabled(p.spin, spins > 0 and not RewardsController.busy)
	p.spin.Text = if RewardsController.busy then "SPINNING..." elseif spins > 0 then `SPIN! ({spins})` else "NO SPINS"
	-- Mid-spin the note waits for the result.
	if RewardsController.busy then
		return
	end
	local nextGift = player:GetAttribute("NextGiftSeconds")
	p.spinNote.Text = if type(nextGift) == "number"
		then `Next free spin after {math.ceil(nextGift / 60)} more minute{if nextGift > 60 then "s" else ""} of play.`
		else "That's all the free spins for today. More tomorrow!"
end
RewardsController.renderSpin = renderSpin

local function refreshStatus()
	local status = ask("status")
	if status and status.ok then
		RewardsController.status = status
		resetAt = os.clock() + (tonumber(status.secondsToReset) or 0)
	end
end

function RewardsController.openDaily()
	refreshStatus()
	RewardsController.parts.daily.Enabled = true
	MouseLock.setFree("DailyRewards", true)
	renderDaily()
end

function RewardsController.closeDaily()
	RewardsController.parts.daily.Enabled = false
	MouseLock.setFree("DailyRewards", false)
end

function RewardsController.openSpin()
	if not RewardsController.busy then
		RewardsController.parts.spinner:reset()
	end
	RewardsController.parts.wheel.Enabled = true
	MouseLock.setFree("SpinWheel", true)
	renderSpin()
end

function RewardsController.closeSpin()
	RewardsController.parts.wheel.Enabled = false
	MouseLock.setFree("SpinWheel", false)
end

function RewardsController.claim()
	if RewardsController.busy then
		return
	end
	RewardsController.busy = true
	renderDaily()
	local answer = ask("claimDaily")
	RewardsController.busy = false
	refreshStatus()
	renderDaily()
	RewardsController.parts.dailyNote.Text = if answer then tostring(answer.message) else "Couldn't reach the server. Try again."
	if answer and answer.ok then
		Audio.play("coins")
	end
end

-- What the banner says came.
local function winText(answer: { [string]: any }): string
	if answer.cosmetic then
		local cosmetic = ProgressionConfig.cosmetics[answer.cosmetic]
		return `✨ {if cosmetic then cosmetic.name else tostring(answer.label)} tracer`
	elseif (tonumber(answer.xp) or 0) > 0 then
		return `⭐ +{UI.commas(answer.xp)} XP`
	end
	return `💰 +{UI.commas(tonumber(answer.coins) or 0)} coins`
end

function RewardsController.spin()
	if RewardsController.busy then
		return
	end
	local p = RewardsController.parts
	RewardsController.busy = true
	renderSpin()
	p.spinNote.Text = "Spinning..."
	-- The server draws while the wheel winds up; then it spins and lands
	-- on what was drawn.
	local answer, answered = nil, false
	task.spawn(function()
		answer = ask("spin")
		answered = true
	end)
	p.spinner:windUp()
	while not answered do
		task.wait()
	end
	if answer and answer.ok and p.prizes[answer.prize] then
		p.spinner:spinTo(answer.prize)
		-- It's landed: the wallet can show the prize now.
		task.spawn(ask, "reveal")
		Audio.play(if answer.cosmetic then "levelUp" else "coins")
		p.spinner:celebrate(answer.prize, winText(answer))
	else
		p.spinner:settle()
	end
	RewardsController.busy = false
	renderSpin()
	p.spinNote.Text = if answer then tostring(answer.message) else "Couldn't reach the server. Try again."
end

function RewardsController.start()
	if started then
		return
	end
	started = true
	build()
	-- A claim waiting while on the home screen: show it, once a session.
	local function maybeOpen()
		renderDaily()
		if player:GetAttribute("DailyReady") == true and not shownToday and not ClientState.isActive() then
			shownToday = true
			RewardsController.openDaily()
		end
	end
	for _, name in { "DailyReady", "DailyDay" } do
		player:GetAttributeChangedSignal(name):Connect(maybeOpen)
	end
	maybeOpen()
	for _, name in { "Spins", "NextGiftSeconds" } do
		player:GetAttributeChangedSignal(name):Connect(renderSpin)
	end
	-- PLAY closes them. A spin still lands out of sight, and the wallet
	-- catches up then.
	ClientState.StateChanged:Connect(function()
		if ClientState.isActive() then
			RewardsController.closeDaily()
			RewardsController.closeSpin()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if RewardsController.parts.daily.Enabled then
				renderDaily()
			end
		end
	end)
	-- The wheel's lights chase slowly while it waits (they stay still
	-- with Reduce Motion).
	task.spawn(function()
		local phase = 0
		while true do
			task.wait(0.5)
			local p = RewardsController.parts
			if p.wheel.Enabled and not RewardsController.busy and not Settings.reduceMotion then
				phase += 1
				p.spinner:setLights(phase)
			end
		end
	end)
end

return RewardsController
