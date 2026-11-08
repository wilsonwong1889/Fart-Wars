-- Chain reactions, loud. The server counts the explosions in each chain
-- reaction (an explosion setting off players, bots and barrels, which set
-- off more) and sends each one's place in it with the explosion
-- (CombatEvent "explosion" and "barrel", `chain`: 1 for the first). This
-- screen never counts for itself. From the second link on
-- (UIConfig.chain):
--   * the chain's owner, the player it's all credited to (the explosion's
--     killer, or whoever set the barrel off), gets "CHAIN x2!", "CHAIN
--     x3!"... big above the crosshair with a tagline, a ring thrown out
--     behind it, the chain sting (a step higher each link) and a little
--     camera kick; each link restarts it, bigger
--   * anyone else in the match within nearStuds of the bang gets a smaller
--     line naming the owner ("💥 ▲ ACE: CHAIN x3!"), unless their own
--     chain's pop-up is up
-- REDUCE MOTION: no pop, tilt, fade or kick, and a still ring: it's just
-- shown and hidden. REDUCED EFFECTS (or low detail): the pop and kick
-- stay; no fade and no ring.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Combatants = require(Client.Combatants)
local UI = require(Client.UI)
local Audio = require(Client.Audio)
local Settings = require(Client.Settings)

local CHAIN = UIConfig.chain
local C = UIConfig.colors

local ChainController = {}

ChainController.parts = {} :: { [string]: any }

local player = Players.LocalPlayer
-- The camera kick now (degrees of roll; it settles to 0), and which way
-- the next one goes.
local kickAmount = 0
local kickSide = 1
local tweens: { [Instance]: Tween } = {}
local started = false

local function stopTween(item: Instance)
	local tween = tweens[item]
	if tween then
		tween:Cancel()
		tweens[item] = nil
	end
end

local function tween(item: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	stopTween(item)
	local made = TweenService:Create(item, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	tweens[item] = made
	made:Play()
end

-- Shows `item` for `seconds`; a newer showing isn't cut short by an older
-- one's end. Returns this showing's token.
local function flash(item: GuiObject, seconds: number): number
	local token = ((item:GetAttribute("Flash") :: number?) or 0) + 1
	item:SetAttribute("Flash", token)
	item.Visible = true
	task.delay(seconds, function()
		if item:GetAttribute("Flash") == token then
			item.Visible = false
		end
	end)
	return token
end

-- Text and its outline back to solid.
local function solid(label: TextLabel)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	stopTween(label)
	label.TextTransparency = 0
	if stroke then
		stopTween(stroke)
		stroke.Transparency = 0
	end
end

-- Fades `labels` out over the end of `item`'s showing `token`, unless it's
-- shown again first.
local function fadeLater(item: GuiObject, token: number, seconds: number, labels: { TextLabel })
	task.delay(math.max(0, seconds - CHAIN.fadeSeconds), function()
		if item:GetAttribute("Flash") ~= token then
			return
		end
		for _, label in labels do
			tween(label, CHAIN.fadeSeconds, { TextTransparency = 1 })
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				tween(stroke, CHAIN.fadeSeconds, { Transparency = 1 })
			end
		end
	end)
end

-- The count an event carries (0 if none: then it's not part of a chain the
-- server told us about).
function ChainController.countOf(event: { [string]: any }): number
	local count = tonumber(event.chain)
	return if count and count >= 1 then math.floor(count) else 0
end

-- Whose chain it is: the explosion's killer, or whoever set the barrel off.
function ChainController.ownerOf(event: { [string]: any }): number?
	local owner = if event.kind == "barrel" then event.owner else event.killer
	return if type(owner) == "number" then owner else nil
end

-- What a count looks like: the pop-up's text, tagline, colour and size.
function ChainController.look(count: number): (string, string, Color3, number)
	local step = math.max(1, count - 1)
	local tagline = CHAIN.taglines[math.min(step, #CHAIN.taglines)]
	local color = CHAIN.colors[math.min(step, #CHAIN.colors)]
	local size = math.min(CHAIN.maxSize, CHAIN.size + CHAIN.growth * (step - 1))
	return string.format(CHAIN.text, count), tagline, color, size
end

-- The sting's pitch for a count: a step higher each link.
function ChainController.pitchOf(count: number): number
	return math.min(CHAIN.maxPitch, 1 + CHAIN.pitchStep * math.max(0, count - 2))
end

-- The camera kick for a count, in degrees.
function ChainController.kickOf(count: number): number
	return math.min(CHAIN.maxKick, CHAIN.kick + CHAIN.kickStep * math.max(0, count - 2))
end

-- The camera kick now (0 once settled).
function ChainController.kick(): number
	return kickAmount
end

-- Whether the owner's pop-up is up.
function ChainController.popupShowing(): boolean
	return ChainController.parts.popup ~= nil and ChainController.parts.popup.Visible
end

-- A player's or bot's name (with the team symbol) and team colour.
local function nameOf(id: number?): (string?, Color3)
	local who = id and Combatants.get(id)
	if not who then
		return nil, C.text
	end
	local team = who.team
	local color = if team and TeamConfig.teams[team] then TeamConfig.teams[team].color else C.text
	return `{UI.teamSymbol(team)}{who.name}`, color
end

-- Whether the bang at `position` is close enough to this player's avatar.
local function near(position: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - position).Magnitude <= CHAIN.nearStuds
end

local function build()
	local p = ChainController.parts
	local screen = UI.screen("Chain", 4)
	p.screen = screen
	-- The owner's pop-up: a holder (the HUD scale goes on it) around the
	-- part that pops and tilts, with the ring behind.
	local popup = UI.new("Frame", {
		Name = "ChainPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CHAIN.height, 0),
		Size = UDim2.new(0, 600, 0, 132),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	p.popup = popup
	p.ring = UI.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, CHAIN.ringSize, 0, CHAIN.ringSize),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = popup,
	}, {
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.new("UIStroke", { Color = CHAIN.colors[1], Thickness = 4 }),
	})
	local burst = UI.new("Frame", {
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = popup,
	})
	p.burst = burst
	p.pop = UI.new("UIScale", { Name = "Pop", Parent = burst })
	p.title = UI.label("", CHAIN.size, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 94),
		ZIndex = 3,
		Parent = burst,
	})
	p.tagline = UI.label("", CHAIN.taglineSize, {
		Name = "Tagline",
		Position = UDim2.new(0, 0, 0, 96),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 3,
		Parent = burst,
	})
	-- The line for everyone else near a chain, in the same spot.
	p.line = UI.label("", CHAIN.lineSize, {
		Name = "ChainLine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CHAIN.height, 0),
		Size = UDim2.new(0, 600, 0, CHAIN.lineSize + 8),
		Visible = false,
		Parent = screen,
	})
end

-- The owner's pop-up for link `count`.
local function showPopup(count: number)
	local p = ChainController.parts
	local calm = Settings.reduceMotion
	local plain = Settings.reducedEffects or Settings.lowDetail
	local text, tagline, color, size = ChainController.look(count)
	p.line.Visible = false
	p.title.Text = text
	p.title.TextColor3 = color
	p.title.TextSize = size
	p.tagline.Text = tagline
	p.tagline.TextColor3 = C.text
	solid(p.title)
	solid(p.tagline)
	local titleStroke = p.title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Thickness = math.max(3, size // 14)
	end
	kickSide = -kickSide
	stopTween(p.pop)
	stopTween(p.burst)
	p.pop.Scale = if calm then 1 else CHAIN.pop
	p.burst.Rotation = if calm then 0 else CHAIN.tilt * kickSide
	if not calm then
		tween(p.pop, CHAIN.popSeconds, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(p.burst, CHAIN.popSeconds, { Rotation = 0 }, Enum.EasingStyle.Back)
	end
	local token = flash(p.popup, CHAIN.seconds)
	if not (calm or plain) then
		fadeLater(p.popup, token, CHAIN.seconds, { p.title, p.tagline })
	end
	-- The ring: thrown out from behind the text and fading (still, with
	-- Reduce motion); none with Reduced effects.
	local ring: Frame = p.ring
	local ringStroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
	stopTween(ring)
	stopTween(ringStroke)
	if plain then
		ring.Visible = false
	else
		local full = UDim2.new(0, CHAIN.ringSize, 0, CHAIN.ringSize)
		ringStroke.Color = color
		ringStroke.Transparency = 0
		ring.Size = if calm then full else UDim2.new(0, size, 0, size)
		if not calm then
			tween(ring, CHAIN.seconds / 2, { Size = full })
			tween(ringStroke, CHAIN.seconds / 2, { Transparency = 1 })
		end
		flash(ring, if calm then CHAIN.seconds else CHAIN.seconds / 2)
	end
	Audio.play("chain", nil, { pitch = ChainController.pitchOf(count) })
	if not calm then
		kickAmount = ChainController.kickOf(count)
	end
end

-- The smaller line for a chain near you that isn't yours.
local function showLine(owner: number?, count: number)
	local p = ChainController.parts
	local name, color = nameOf(owner)
	p.line.Text = if name then string.format(CHAIN.line, string.upper(name), count) else string.format(CHAIN.lineNoOwner, count)
	p.line.TextColor3 = color
	solid(p.line)
	local token = flash(p.line, CHAIN.lineSeconds)
	if not (Settings.reduceMotion or Settings.reducedEffects or Settings.lowDetail) then
		fadeLater(p.line, token, CHAIN.lineSeconds, { p.line })
	end
end

-- One CombatEvent: an explosion or a barrel past the first link of its
-- chain gets the pop-up (yours) or the line (near you). Returns what it
-- showed: "popup", "line" or nil.
function ChainController.onEvent(event: { [string]: any }): string?
	if not FeatureFlags.CHAIN_CALLOUTS or (event.kind ~= "explosion" and event.kind ~= "barrel") then
		return nil
	end
	local count = ChainController.countOf(event)
	if count < 2 or typeof(event.position) ~= "Vector3" or not ClientState.isActive() then
		return nil
	end
	local owner = ChainController.ownerOf(event)
	if owner == player.UserId then
		showPopup(count)
		return "popup"
	elseif near(event.position) and not ChainController.popupShowing() then
		showLine(owner, count)
		return "line"
	end
	return nil
end

-- Every frame, after the camera has moved: the kick (a roll and a shove
-- down, alternating sides each link), settling. Rolling about the view
-- and shoving the camera leave where it looks alone, so nothing drifts.
function ChainController.step(dt: number)
	if kickAmount <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and not Settings.reduceMotion then
		camera.CFrame *= CFrame.new(0, -kickAmount * CHAIN.shove, 0) * CFrame.Angles(0, 0, math.rad(kickAmount * kickSide))
	end
	kickAmount *= math.exp(-dt / CHAIN.kickSeconds)
	if kickAmount < 0.01 then
		kickAmount = 0
	end
end

function ChainController.start()
	if started then
		return
	end
	started = true
	build()
	local combatEvent = ClientState.remote("CombatEvent") :: RemoteEvent
	combatEvent.OnClientEvent:Connect(function(event)
		if type(event) == "table" then
			ChainController.onEvent(event)
		end
	end)
	-- After the camera and the shot kick (both at Camera + 1).
	pcall(function()
		RunService:BindToRenderStep("FartWarsChainKick", Enum.RenderPriority.Camera.Value + 2, ChainController.step)
	end)
end

return ChainController
