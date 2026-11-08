-- The FEEDBACK window (FeatureFlags.FEEDBACK; FeedbackConfig), opened from
-- the M menu: a type (BUG, IDEA or OTHER), a text box of up to MAX_LENGTH
-- characters with its count, and SEND. The report goes to the server
-- (SendFeedback) with the frame rate, ping and last few script errors
-- (HealthController.current), and the window shows the answer: thanks, or
-- how long until the next one (one every COOLDOWN_SECONDS, PER_DAY a day).
-- Only the developer reads reports, never other players; the window says so.
-- The mouse is free while it's open (MouseLock "Feedback"); keys typed
-- into the box never reach the game (InputController ignores them).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeedbackConfig = require(Shared.Config.FeedbackConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local UI = require(Client.UI)
local MouseLock = require(Client.MouseLock)
local HealthController = require(script.Parent.HealthController)

local C = UIConfig.colors
local LOOKS = FeedbackConfig.LOOKS

local FeedbackController = {}

-- The window's words for each answer (and for sending).
FeedbackController.MESSAGES = table.freeze({
	sent = "THANKS, LEGEND! THE DEV WILL SNIFF IT OUT 👃",
	sending = "SENDING...",
	tooSoon = "WHOA, SLOW YOUR ROLL! NEXT ONE IN %s",
	tooMany = `THAT'S {FeedbackConfig.PER_DAY} TODAY! THE DEV'S NOSE NEEDS A BREAK. BACK TOMORROW`,
	empty = `TYPE A BIT MORE, BRO ({FeedbackConfig.MIN_LENGTH}+ CHARACTERS)`,
	tooLong = `TOO LONG! {FeedbackConfig.MAX_LENGTH} CHARACTERS MAX`,
	badKind = "PICK BUG, IDEA OR OTHER FIRST",
	badPayload = "THAT ONE DIDN'T SEND. TRY AGAIN IN A BIT",
	error = "THE FART CLOUD IS DOWN. TRY AGAIN IN A BIT",
	off = "FEEDBACK IS TAKING A NAP RIGHT NOW",
	busy = "STILL SENDING THE LAST ONE...",
	tooFast = "ONE SEC...",
})
FeedbackController.TITLE = "FEEDBACK"
FeedbackController.SUBTITLE = "SPOTTED A BUG? GOT A BIG-BRAIN IDEA? TELL THE DEV."
FeedbackController.NOTE = "ONLY THE DEV READS THIS, NEVER OTHER PLAYERS. YOUR PING, FPS AND RECENT ERRORS TAG ALONG "
	.. `SO BUGS GET SQUASHED. {FeedbackConfig.PER_DAY} A DAY MAX.`

FeedbackController.parts = {} :: { [string]: any }
FeedbackController.isOpen = false
-- The chosen type, whether a report is on its way, and the answer showing.
FeedbackController.kind = FeedbackConfig.KINDS[1]
FeedbackController.sending = false
FeedbackController.status = ""
-- No SEND until then (os.clock), from the server's answers; and the UTC
-- day the daily limit was reached on, if it was.
FeedbackController.waitUntil = 0
FeedbackController.doneDay = nil :: number?

local started = false
local render: () -> ()

-- Whether feedback is on (the server says, as Workspace's FeedbackOpen).
function FeedbackController.enabled(): boolean
	return workspace:GetAttribute("FeedbackOpen") == true
end

local function today(): number
	return os.time() // 86400
end

local function clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return `{whole // 60}:{string.format("%02d", whole % 60)}`
end

-- The box's text as the server will count it.
local function cleaned(): string
	local box = FeedbackController.parts.box
	return FeedbackConfig.clean(if box then box.Text else "")
end

function FeedbackController.open()
	if not FeedbackController.enabled() then
		return
	end
	FeedbackController.isOpen = true
	-- A fresh look: last time's answer goes (SEND still shows any wait).
	if not FeedbackController.sending then
		FeedbackController.status = ""
	end
	FeedbackController.parts.screen.Enabled = true
	MouseLock.setFree("Feedback", true)
	render()
end

function FeedbackController.close()
	local box = FeedbackController.parts.box
	if box then
		-- Keys stop going to the box once it's hidden.
		pcall(function()
			box:ReleaseFocus()
		end)
	end
	FeedbackController.isOpen = false
	FeedbackController.parts.screen.Enabled = false
	MouseLock.setFree("Feedback", false)
end

function FeedbackController.choose(kind: string)
	if LOOKS[kind] then
		FeedbackController.kind = kind
		render()
	end
end

-- Sends what's in the box. Returns the server's answer ("sent", "tooSoon",
-- ...), or why it wasn't sent.
function FeedbackController.send(): string
	if FeedbackController.sending then
		return "busy"
	end
	local text = cleaned()
	if FeedbackConfig.length(text) < FeedbackConfig.MIN_LENGTH then
		FeedbackController.status = FeedbackController.MESSAGES.empty
		render()
		return "empty"
	end
	if os.clock() < FeedbackController.waitUntil or FeedbackController.doneDay == today() then
		return "tooSoon"
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("SendFeedback") :: RemoteFunction?
	if not remote then
		return "error"
	end
	FeedbackController.sending = true
	FeedbackController.status = FeedbackController.MESSAGES.sending
	render()
	local numbers = HealthController.current()
	local payload = {
		kind = FeedbackController.kind,
		text = text,
		fps = numbers.fps,
		ping = numbers.ping,
		errorCount = numbers.errorCount,
		errors = numbers.errors,
	}
	local began = os.clock()
	local ok, answer = pcall(remote.InvokeServer, remote, payload)
	HealthController.noteLatency(os.clock() - began)
	FeedbackController.sending = false
	local reason = if ok and type(answer) == "table" and type(answer.reason) == "string" then answer.reason else "error"
	local wait = if ok and type(answer) == "table" then tonumber(answer.wait) else nil
	if reason == "sent" then
		FeedbackController.parts.box.Text = ""
		FeedbackController.waitUntil = os.clock() + FeedbackConfig.COOLDOWN_SECONDS
	elseif reason == "tooSoon" and wait then
		FeedbackController.waitUntil = os.clock() + wait
	elseif reason == "tooMany" then
		FeedbackController.doneDay = today()
	end
	local message = FeedbackController.MESSAGES[reason] or FeedbackController.MESSAGES.error
	if reason == "tooSoon" then
		message = string.format(message, clock(wait or FeedbackConfig.COOLDOWN_SECONDS))
	end
	FeedbackController.status = message
	render()
	return reason
end

render = function()
	local p = FeedbackController.parts
	if p.menuButton then
		p.menuButton.Visible = FeedbackController.enabled()
	end
	if not (p.screen and FeedbackController.isOpen) then
		return
	end
	for kind, button in p.kinds do
		local chosen = kind == FeedbackController.kind
		UI.paint(button, if chosen then LOOKS[kind].color else C.panelLight)
		button.Border.Color = if chosen then C.text else C.stroke
	end
	local look = LOOKS[FeedbackController.kind]
	p.box.PlaceholderText = look.prompt
	local length = FeedbackConfig.length(p.box.Text)
	p.count.Text = `{length}/{FeedbackConfig.MAX_LENGTH}`
	p.count.TextColor3 = if length >= FeedbackConfig.MAX_LENGTH then C.warning else C.muted
	local left = FeedbackController.waitUntil - os.clock()
	local doneToday = FeedbackController.doneDay == today()
	local long = FeedbackConfig.length(cleaned()) >= FeedbackConfig.MIN_LENGTH
	local text
	if FeedbackController.sending then
		text = "SENDING..."
	elseif doneToday then
		text = "DONE FOR TODAY"
	elseif left > 0 then
		text = `WAIT {clock(left)}`
	else
		text = "SEND"
	end
	p.send.Text = text
	UI.setEnabled(p.send, FeedbackController.enabled() and not FeedbackController.sending and not doneToday and left <= 0 and long)
	p.status.Text = FeedbackController.status
end
FeedbackController.render = render

-- The M menu's FEEDBACK button, in `parent` (the menu's list), `width`
-- wide. Hidden while feedback is off.
function FeedbackController.menuButton(parent: Instance, width: number): TextButton
	local look = FeedbackConfig.BUTTON
	local button = UI.chunky(look.label, look.color, look.icon, {
		Name = "Feedback",
		LayoutOrder = 90,
		Size = UDim2.new(0, width, 0, 44),
		TextSize = 20,
		Visible = FeedbackController.enabled(),
		Parent = parent,
	})
	UI.onClick(button, FeedbackController.open)
	FeedbackController.parts.menuButton = button
	return button
end

local function build()
	local p = FeedbackController.parts
	local screen = UI.screen("Feedback", 18)
	screen.Enabled = false
	p.screen = screen
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 480, 0, 430),
		BackgroundColor3 = C.panel,
		-- A click on the window stays on it.
		Active = true,
		Parent = screen,
	}, { UI.corner(16), UI.stroke(C.stroke, 4), UI.padding(16) })
	p.panel = panel
	UI.label(FeedbackController.TITLE, 28, { Name = "Title", TextColor3 = C.accent, Parent = panel })
	local close = UI.button("X", C.warning, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 40, 0, 40),
		Modal = true,
		Parent = panel,
	})
	UI.onClick(close, FeedbackController.close)
	UI.label(FeedbackController.SUBTITLE, 14, {
		Name = "Subtitle",
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, -44, 0, 20),
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	p.kinds = {}
	for i, kind in FeedbackConfig.KINDS do
		local look = LOOKS[kind]
		local button = UI.chunky(look.label, look.color, look.icon, {
			Name = kind,
			Position = UDim2.new(0, (i - 1) * 154, 0, 66),
			Size = UDim2.new(0, 140, 0, 44),
			TextSize = 20,
			Parent = panel,
		})
		UI.onClick(button, function()
			FeedbackController.choose(kind)
		end)
		p.kinds[kind] = button
	end
	local box = UI.new("TextBox", {
		Name = "Box",
		Position = UDim2.new(0, 0, 0, 118),
		Size = UDim2.new(1, 0, 0, 130),
		BackgroundColor3 = C.panelLight,
		Text = "",
		PlaceholderText = LOOKS[FeedbackController.kind].prompt,
		PlaceholderColor3 = C.muted,
		TextColor3 = C.text,
		TextSize = 16,
		Font = UIConfig.bodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		MultiLine = true,
		ClearTextOnFocus = false,
		Parent = panel,
	}, { UI.corner(10), UI.stroke(C.stroke, 2), UI.padding(8) })
	p.box = box
	-- No more than MAX_LENGTH characters: anything past it is cut off.
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = FeedbackConfig.cut(box.Text, FeedbackConfig.MAX_LENGTH)
		if text ~= box.Text then
			box.Text = text
			return
		end
		render()
	end)
	p.count = UI.label(`0/{FeedbackConfig.MAX_LENGTH}`, 14, {
		Name = "Count",
		Position = UDim2.new(0, 0, 0, 252),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	UI.label(FeedbackController.NOTE, 12, {
		Name = "Note",
		Position = UDim2.new(0, 0, 0, 274),
		Size = UDim2.new(1, 0, 0, 34),
		TextWrapped = true,
		TextColor3 = C.muted,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	p.status = UI.label("", 15, {
		Name = "Status",
		Position = UDim2.new(0, 0, 0, 312),
		Size = UDim2.new(1, 0, 0, 22),
		TextWrapped = true,
		TextColor3 = C.accent,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	local send = UI.chunky("SEND", C.play, "📨", {
		Name = "Send",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 220, 0, 50),
		TextSize = 22,
		Parent = panel,
	})
	p.send = send
	UI.onClick(send, function()
		FeedbackController.send()
	end)
end

function FeedbackController.start()
	if started then
		return
	end
	started = true
	build()
	workspace:GetAttributeChangedSignal("FeedbackOpen"):Connect(function()
		if not FeedbackController.enabled() and FeedbackController.isOpen then
			FeedbackController.close()
		end
		render()
	end)
	-- The SEND button's countdown.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if FeedbackController.isOpen and FeedbackController.waitUntil > os.clock() - 1 then
				render()
			end
		end
	end)
end

return FeedbackController
