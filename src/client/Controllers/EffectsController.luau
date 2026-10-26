-- What gas looks like, on every client:
--   * inflation: each avatar carries a gas belly (a local, non-colliding
--     ball) that grows and changes colour with its gas stage, so the
--     hitbox and camera never change; at the critical stage and during the
--     countdown the avatar gets a slow red outline pulse (well under three
--     flashes a second)
--   * explosions: a burst and a lingering cloud, from a small pool so a
--     chain of explosions never piles up parts; barrels burst orange, and a
--     barrel with its fuse lit gets a steady red outline
--   * Fart Dash puffs behind other players' dashes
--   * stink bombs: the arc, the splash, and the cloud they leave (shown at
--     every quality: standing in one gasses you)
--   * Q abilities: Recovery Burst's vent puff, Gas Pulse's wind-up ring
--   * "BRO IS THE ALPHA FART!" across the screen when someone hits the
--     streak, with its sound
-- Effects thin out (no clouds or puffs) at Roblox graphics quality 3 or
-- lower, or with Reduced effects on in Settings.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local UIConfig = require(Shared.Config.UIConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local Audio = require(Client.Audio)
local Settings = require(Client.Settings)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)

local C = UIConfig.colors

local EffectsController = {}

EffectsController.parts = {} :: { [string]: any }

-- Belly diameter and colour per gas stage (0-4).
local BELLY = {
	{ size = 0, color = Color3.fromRGB(150, 220, 90) },
	{ size = 2.6, color = Color3.fromRGB(150, 220, 90) },
	{ size = 3.6, color = Color3.fromRGB(200, 220, 70) },
	{ size = 4.6, color = Color3.fromRGB(240, 150, 60) },
	{ size = 5.6, color = Color3.fromRGB(240, 70, 50) },
}
local POOL_SIZE = 8
local EXPLOSION_RADIUS = GameConfig.EXPLOSION.RADIUS
local GAS_GREEN = Color3.fromRGB(150, 230, 60)
local BARREL_ORANGE = Color3.fromRGB(255, 150, 40)

local player = Players.LocalPlayer
local pool: { BasePart } = {}
local poolNext = 0
local started = false

-- Whether to hold back on effects (Settings, or Roblox graphics quality
-- 1-3). Clouds that gas you are gameplay, so they always show.
function EffectsController.reduced(): boolean
	if Settings.reducedEffects or Settings.lowDetail then
		return true
	end
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel
	end)
	if not ok or typeof(level) ~= "EnumItem" or level == Enum.SavedQualitySetting.Automatic then
		return false
	end
	return level.Value <= 3
end

local function effectPart(name: string): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	return p
end

-- Short-lived effect parts (puffs, clouds, arcs, rings), at most
-- GameConfig.BUDGET.MAX_EFFECT_PARTS at once: past that the oldest goes.
local live: { BasePart } = {}
local liveNext = 0
local function transient(name: string): BasePart
	local p = effectPart(name)
	liveNext = liveNext % GameConfig.BUDGET.MAX_EFFECT_PARTS + 1
	local old = live[liveNext]
	if old and old.Parent then
		old:Destroy()
	end
	live[liveNext] = p
	return p
end

-- How many short-lived effect parts are showing now.
function EffectsController.liveEffects(): number
	local n = 0
	for _, p in live do
		if p.Parent then
			n += 1
		end
	end
	return n
end

-- The next pooled burst (the oldest is reused when all are busy).
local function pooled(): BasePart
	poolNext = poolNext % POOL_SIZE + 1
	local p = pool[poolNext]
	if not p then
		p = effectPart("Burst")
		p.Parent = workspace
		pool[poolNext] = p
	end
	return p
end
EffectsController.pool = pool

function EffectsController.explosion(position: Vector3, color: Color3?, radius: number?)
	local reach = radius or EXPLOSION_RADIUS
	local burst = pooled()
	burst.Color = color or GAS_GREEN
	burst.Size = Vector3.one * 2
	burst.CFrame = CFrame.new(position)
	burst.Transparency = 0.2
	TweenService:Create(burst, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * reach * 2,
		Transparency = 1,
	}):Play()
	if EffectsController.reduced() then
		return
	end
	local cloud = transient("GasCloud")
	cloud.Material = Enum.Material.SmoothPlastic
	cloud.Color = Color3.fromRGB(120, 170, 60)
	cloud.Size = Vector3.one * reach * 1.4
	cloud.CFrame = CFrame.new(position)
	cloud.Transparency = 0.6
	cloud.Parent = workspace
	TweenService:Create(cloud, TweenInfo.new(1.5), { Transparency = 1 }):Play()
	Debris:AddItem(cloud, 1.6)
end

function EffectsController.dashPuff(from: Vector3, direction: Vector3, color: Color3?)
	Audio.play("dash")
	if EffectsController.reduced() then
		return
	end
	for i = 0, 2 do
		local puff = transient("DashPuff")
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = color or Color3.fromRGB(170, 200, 90)
		puff.Size = Vector3.one * (2.4 - i * 0.5)
		puff.CFrame = CFrame.new(from + direction * i * 4 + Vector3.new(0, -1, 0))
		puff.Transparency = 0.4
		puff.Parent = workspace
		TweenService:Create(puff, TweenInfo.new(0.6), { Transparency = 1, Size = puff.Size * 1.8 }):Play()
		Debris:AddItem(puff, 0.7)
	end
end

-- A stink bomb's flight along `path`, then its splash where it lands.
function EffectsController.lob(path: { Vector3 }, flight: number, color: Color3?)
	Audio.play("lobber")
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local length = (b - a).Magnitude
		if length > 0.1 then
			local segment = transient("LobArc")
			segment.Shape = Enum.PartType.Block
			segment.Color = color or GAS_GREEN
			segment.Size = Vector3.new(0.25, 0.25, length)
			segment.CFrame = CFrame.lookAt(a:Lerp(b, 0.5), b)
			segment.Transparency = 0.3
			segment.Parent = workspace
			Debris:AddItem(segment, flight + 0.15)
		end
	end
	local landing = path[#path]
	task.delay(flight, function()
		Audio.play("splat")
		EffectsController.explosion(landing, color or GAS_GREEN, 8)
	end)
end

-- A stink cloud that gasses enemies inside it until `endsAt`.
function EffectsController.cloud(position: Vector3, radius: number, endsAt: number)
	local cloud = transient("StinkCloud")
	cloud.Material = Enum.Material.SmoothPlastic
	cloud.Color = Color3.fromRGB(130, 180, 50)
	cloud.Size = Vector3.one * radius * 2
	cloud.CFrame = CFrame.new(position)
	cloud.Transparency = 0.7
	cloud.Parent = workspace
	Debris:AddItem(cloud, math.max(0.1, endsAt - workspace:GetServerTimeNow()))
	return cloud
end

-- An emote over someone's head for a moment (and a little puff).
function EffectsController.emote(userId: number, id: string): BillboardGui?
	if Settings.hiddenEmotes[userId] then
		return nil
	end
	local other = Players:GetPlayerByUserId(userId)
	local head = other and other.Character and other.Character:FindFirstChild("Head")
	local cosmetic = ProgressionConfig.cosmetics[id]
	if not (head and head:IsA("BasePart") and cosmetic and cosmetic.kind == "emote") then
		return nil
	end
	local old = head:FindFirstChild("Emote")
	if old then
		old:Destroy()
	end
	local board = Instance.new("BillboardGui")
	board.Name = "Emote"
	board.Size = UDim2.new(0, 260, 0, 64)
	board.StudsOffset = Vector3.new(0, 3.2, 0)
	board.AlwaysOnTop = true
	board.Adornee = head
	UI.label(`{cosmetic.emoji} {cosmetic.text}`, 30, { Size = UDim2.new(1, 0, 1, 0), Parent = board })
	board.Parent = head
	Debris:AddItem(board, 2.5)
	Audio.play("emote")
	if not EffectsController.reduced() then
		EffectsController.ability("RecoveryBurst", head.Position - Vector3.new(0, 2, 0))
	end
	return board
end

-- Someone used their Q ability: a vent puff or a pulse ring.
function EffectsController.ability(id: string, position: Vector3)
	if id == "RecoveryBurst" then
		Audio.play("vent")
		for i = 0, (if EffectsController.reduced() then 0 else 3) do
			local puff = transient("VentPuff")
			puff.Material = Enum.Material.SmoothPlastic
			puff.Color = Color3.fromRGB(200, 230, 120)
			puff.Size = Vector3.one * (3 - i * 0.4)
			puff.CFrame = CFrame.new(position + Vector3.new(0, i * 1.5, 0))
			puff.Transparency = 0.3
			puff.Parent = workspace
			TweenService:Create(puff, TweenInfo.new(0.8), { Transparency = 1, Size = puff.Size * 2 }):Play()
			Debris:AddItem(puff, 0.9)
		end
	elseif id == "GasPulse" then
		Audio.play("pulse")
		local radius = AbilityConfig.GasPulse.radius :: number
		local windup = AbilityConfig.GasPulse.durationSeconds
		local ring = transient("PulseRing")
		ring.Shape = Enum.PartType.Cylinder
		ring.Color = GAS_GREEN
		ring.Size = Vector3.new(0.4, 2, 2)
		ring.CFrame = CFrame.new(position + Vector3.new(0, -2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Transparency = 0.3
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(windup), { Size = Vector3.new(0.4, radius * 2, radius * 2) }):Play()
		task.delay(windup, function()
			TweenService:Create(ring, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end)
		Debris:AddItem(ring, windup + 0.35)
	end
end

-- Inflation: one belly per avatar, following its gas stage.
local function bellyFor(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local existing = character:FindFirstChild("GasBelly")
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local belly = effectPart("GasBelly")
	belly.Anchored = false
	belly.Massless = true
	belly.Material = Enum.Material.SmoothPlastic
	belly.Size = Vector3.one * 0.1
	belly.CFrame = root.CFrame * CFrame.new(0, 0, -0.6)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = belly
	weld.Parent = belly
	belly.Parent = character
	return belly
end

local function renderGas(character: Model)
	local stage = tonumber(character:GetAttribute("GasStage")) or 0
	local exploding = character:GetAttribute("ExplodesAt") ~= nil
	if exploding then
		stage = 4
	end
	local look = BELLY[math.clamp(stage, 0, 4) + 1]
	local belly = bellyFor(character)
	if belly then
		local hidden = look.size == 0 or (character == player.Character and CameraController.firstPerson)
		belly.Color = look.color
		TweenService:Create(belly, TweenInfo.new(0.25), {
			Size = Vector3.one * math.max(look.size, 0.1),
			Transparency = if hidden then 1 else 0.15,
		}):Play()
	end
	local outline = character:FindFirstChild("GasWarning")
	local critical = stage >= 3
	if critical and not outline then
		local highlight = Instance.new("Highlight")
		highlight.Name = "GasWarning"
		highlight.FillColor = Color3.fromRGB(240, 70, 50)
		highlight.OutlineColor = Color3.fromRGB(255, 110, 80)
		highlight.FillTransparency = 0.75
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = character
		highlight.Parent = character
		-- A slow pulse: one cycle a second at most.
		TweenService:Create(highlight, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			FillTransparency = 0.4,
		}):Play()
	elseif outline and not critical then
		outline:Destroy()
	end
end
EffectsController.renderGas = renderGas

-- A lit barrel: a steady red outline until it goes (no flashing).
local function renderBarrel(barrel: Model)
	local lit = barrel:GetAttribute("FuseAt") ~= nil
	local outline = barrel:FindFirstChild("Danger")
	if lit and not outline then
		local highlight = Instance.new("Highlight")
		highlight.Name = "Danger"
		highlight.FillColor = Color3.fromRGB(255, 60, 40)
		highlight.OutlineColor = Color3.fromRGB(255, 80, 60)
		highlight.FillTransparency = 0.5
		highlight.Adornee = barrel
		highlight.Parent = barrel
	elseif outline and not lit then
		outline:Destroy()
	end
end
EffectsController.renderBarrel = renderBarrel

local function watchMap(map: Instance)
	local folder = map:WaitForChild("Barrels", 10)
	if not folder then
		return
	end
	for _, barrel in folder:GetChildren() do
		if barrel:IsA("Model") then
			barrel:GetAttributeChangedSignal("FuseAt"):Connect(function()
				renderBarrel(barrel)
			end)
			renderBarrel(barrel)
		end
	end
end

local function watchCharacter(character: Model)
	for _, name in { "GasStage", "ExplodesAt" } do
		character:GetAttributeChangedSignal(name):Connect(function()
			renderGas(character)
		end)
	end
	renderGas(character)
end

local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(watchCharacter)
	if other.Character then
		watchCharacter(other.Character)
	end
end

local function build()
	local p = EffectsController.parts
	local screen = UI.screen("Announcements", 15)
	p.screen = screen
	local banner = UI.new("Frame", {
		Name = "Alpha",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.22, 0),
		Size = UDim2.new(0, 760, 0, 120),
		BackgroundColor3 = Color3.fromRGB(60, 40, 10),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = screen,
	}, { UI.corner(18), UI.stroke(C.accent, 4) })
	p.alpha = banner
	p.alphaText = UI.label(GameConfig.STREAK.ALPHA_TEXT, 54, {
		Name = "Text",
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 62),
		TextColor3 = Color3.fromRGB(255, 221, 26),
		Parent = banner,
	})
	p.alphaName = UI.label("", 24, { Name = "Player", Position = UDim2.new(0, 0, 0, 74), Parent = banner })
end

function EffectsController.alpha(userId: number, text: string)
	local p = EffectsController.parts
	local other = Players:GetPlayerByUserId(userId)
	local team = other and other:GetAttribute("TeamId")
	p.alphaText.Text = text
	p.alphaName.Text = if other then string.upper(other.DisplayName) else ""
	p.alphaName.TextColor3 = if team and TeamConfig.teams[team] then TeamConfig.teams[team].color else C.text
	Audio.play("alpha")
	local token = (p.alpha:GetAttribute("Shown") or 0) + 1
	p.alpha:SetAttribute("Shown", token)
	p.alpha.Visible = true
	task.delay(4, function()
		if p.alpha:GetAttribute("Shown") == token then
			p.alpha.Visible = false
		end
	end)
end

function EffectsController.start()
	if started then
		return
	end
	started = true
	build()
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	local map = workspace:FindFirstChild("Map")
	if map then
		task.spawn(watchMap, map)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Map" then
			watchMap(child)
		end
	end)
	-- Your own belly hides in first person.
	InputController.CameraToggled:Connect(function()
		task.defer(function()
			if player.Character then
				renderGas(player.Character)
			end
		end)
	end)
	local combatEvent = ClientState.remote("CombatEvent") :: RemoteEvent
	combatEvent.OnClientEvent:Connect(function(event)
		if type(event) ~= "table" then
			return
		end
		if event.kind == "explosion" and typeof(event.position) == "Vector3" then
			Audio.play("explosion")
			EffectsController.explosion(event.position)
		elseif event.kind == "barrel" and typeof(event.position) == "Vector3" then
			Audio.play("barrel")
			EffectsController.explosion(event.position, BARREL_ORANGE, GameConfig.BARREL.RADIUS)
		elseif event.kind == "dash" and event.player ~= player.UserId and typeof(event.from) == "Vector3" and typeof(event.direction) == "Vector3" then
			local dasher = Players:GetPlayerByUserId(event.player)
			local trail = dasher and ProgressionConfig.cosmetics[dasher:GetAttribute("Trail") :: any]
			EffectsController.dashPuff(event.from, event.direction, if trail then trail.trailColor else nil)
		elseif event.kind == "emote" and type(event.player) == "number" and type(event.emote) == "string" then
			EffectsController.emote(event.player, event.emote)
		elseif event.kind == "lob" and type(event.path) == "table" and type(event.flight) == "number" then
			local path = {}
			for _, point in event.path do
				if typeof(point) == "Vector3" then
					table.insert(path, point)
				end
			end
			if #path >= 2 then
				EffectsController.lob(path, math.clamp(event.flight, 0, 3))
			end
		elseif event.kind == "cloud" and typeof(event.position) == "Vector3" and type(event.radius) == "number" and type(event.endsAt) == "number" then
			EffectsController.cloud(event.position, event.radius, event.endsAt)
		elseif event.kind == "ability" and type(event.ability) == "string" and typeof(event.position) == "Vector3" then
			EffectsController.ability(event.ability, event.position)
		elseif event.kind == "alpha" and type(event.player) == "number" then
			EffectsController.alpha(event.player, if type(event.text) == "string" then event.text else GameConfig.STREAK.ALPHA_TEXT)
		end
	end)
end

return EffectsController
