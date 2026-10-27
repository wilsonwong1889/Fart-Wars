-- Fills a quiet server with bots (FeatureFlags.BOTS). While fewer than
-- BotConfig.FILL_TO people are in the server (everyone counts, playing or
-- not, and only while at least one is), bots make up the difference,
-- spread so the teams stay level; a human who joins takes a bot's place.
-- BotFill decides, a frame after any join, leave or team change, so a burst
-- of changes (and the team changes the bots themselves make) is settled in
-- one go.
-- Each bot is a BotService slot. Every life gets an avatar built here: an
-- R15 body in the team's colours, walking at the Gas Blaster's speed with
-- the Gas Blaster in hand (the same Tool a player holds, so every client
-- dresses it), standing on the team's safest spawn in workspace.Bots, with
-- Roblox's default animations played from the server, and one BotBrain
-- driving it. A bot that dies is back RESPAWN_SECONDS later (BotService
-- clears the old body away), every bot starts again from a spawn when a
-- round starts or the map reloads, and a bot no longer needed goes at once
-- (exploding first if it's mid-countdown, so the kill still counts).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local BotConfig = require(Shared.Config.BotConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local States = require(Shared.States)
local BotFill = require(Shared.BotFill)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local BotBrain = require(Server.Bots.BotBrain)
local TeamService = require(script.Parent.TeamService)
local MapService = require(script.Parent.MapService)
local BotService = require(script.Parent.BotService)
local LoadoutService = require(script.Parent.LoadoutService)
local RoundService = require(script.Parent.RoundService)

local WEAPON = WeaponConfig.weapons[BotConfig.WEAPON]

-- Roblox's default R15 animations. An avatar without a player has no
-- Animate script running, so the server plays these (they replicate).
local ANIMATIONS = {
	idle = "rbxassetid://507766388",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	-- The arm held up, as a player's is while holding a tool.
	hold = "rbxassetid://507768375",
}

local BotDirector = {}

export type Status = {
	enabled: boolean,
	fillTo: number,
	difficulty: number,
	bots: { { id: number, name: string, team: string, alive: boolean } },
}

type Slot = {
	bot: BotService.Bot,
	-- Bumped by every spawn, move and removal, so a respawn or a build that
	-- finishes late can tell it has been overtaken.
	token: number,
	-- This life's avatar (nil once it has ended).
	character: Model?,
	brain: BotBrain.Brain?,
	skin: number,
}

local slots: { [number]: Slot } = {}
-- Players on their way out (still in Players while PlayerRemoving runs).
local leaving: { [Player]: boolean } = {}
-- A body per team and skin tone, built once (Roblox builds it from a web
-- lookup) and cloned for every spawn.
local templates: { [string]: Model } = {}
local enabled = false
local started = false
local queued = false
-- True while this applies a plan: the team changes it makes don't call for
-- another one.
local applying = false
local fillOverride: number? = nil
local difficultyOverride: number? = nil
local skinCounter = 0
local random = Random.new()

local function difficulty(): number
	return difficultyOverride or BotConfig.DIFFICULTY
end

local function fillTo(): number
	return fillOverride or BotConfig.FILL_TO
end

local function botsFolder(): Instance
	local folder = workspace:FindFirstChild("Bots")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "Bots"
	made.Parent = workspace
	return made
end

-- Avatars.

-- The team's colours on the body: shirt (torso and arms) in the team colour,
-- trousers in its dark colour.
local function describe(team: string, skin: Color3): HumanoidDescription
	local colors = TeamConfig.teams[team]
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = skin
	description.TorsoColor = colors.color
	description.LeftArmColor = colors.color
	description.RightArmColor = colors.color
	description.LeftLegColor = colors.darkColor
	description.RightLegColor = colors.darkColor
	return description
end

-- A plain body of blocks, for when Roblox can't build one from the
-- description (an outage; the specs' stand-ins).
local function blockBody(team: string, skin: Color3): Model
	local colors = TeamConfig.teams[team]
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model
	local function limb(name: string, size: Vector3, offset: CFrame, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.CFrame = offset
		part.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	limb("UpperTorso", Vector3.new(2, 2, 1), CFrame.new(), colors.color)
	limb("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.6, 0), skin)
	limb("LowerTorso", Vector3.new(2, 1.5, 1), CFrame.new(0, -1.75, 0), colors.darkColor)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2.5
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function template(team: string, skinIndex: number): Model
	local key = `{team}/{skinIndex}`
	local cached = templates[key]
	if cached then
		return cached
	end
	local skin = BotConfig.SKIN_TONES[skinIndex]
	local ok, built = pcall(function()
		return Players:CreateHumanoidModelFromDescription(describe(team, skin), Enum.HumanoidRigType.R15)
	end)
	local model: Model
	if ok and typeof(built) == "Instance" and built:IsA("Model") then
		model = built
		-- Never runs without a player, and the server animates bots instead.
		local animate = model:FindFirstChild("Animate")
		if animate then
			animate:Destroy()
		end
	else
		Telemetry.log("BotDirector", "blockBody", { team = team, reason = tostring(built) })
		model = blockBody(team, skin)
	end
	-- Another spawn may have built the same one while this one waited.
	if templates[key] then
		model:Destroy()
	else
		templates[key] = model
	end
	return templates[key]
end

-- Plays idle, running, jumping and falling as the humanoid does them, and
-- the arm raised for the gun throughout.
local function animate(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local tracks: { [string]: AnimationTrack } = {}
	for name, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			tracks[name] = track
		end
	end
	local hold = tracks.hold
	if hold then
		hold.Priority = Enum.AnimationPriority.Action
		hold.Looped = true
		hold:Play()
	end
	local playing: AnimationTrack? = nil
	local function play(name: string, speed: number?)
		local track = tracks[name]
		if not track then
			return
		end
		if playing ~= track then
			if playing then
				playing:Stop(0.2)
			end
			playing = track
			track.Looped = name == "idle" or name == "run"
			track:Play(0.2)
		end
		if speed then
			track:AdjustSpeed(speed)
		end
	end
	play("idle")
	humanoid.Running:Connect(function(speed: number)
		if speed > 0.5 then
			play("run", math.clamp(speed / 16, 0.5, 1.5))
		else
			play("idle")
		end
	end)
	humanoid.StateChanged:Connect(function(_, state: Enum.HumanoidStateType)
		if state == Enum.HumanoidStateType.Jumping then
			play("jump")
		elseif state == Enum.HumanoidStateType.Freefall then
			play("fall")
		end
	end)
end

-- Where everyone against `team` stands (players and bots), so a bot isn't
-- spawned in front of them.
local function enemyPositions(team: string): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		local other = TeamService.teamOf(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if other and other ~= team and root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	for _, bot in BotService.all() do
		local root = if bot.team ~= team then BotService.rootOf(bot) else nil
		if root then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

-- Stands the avatar on the pad (somewhere on it, so two bots don't share a
-- spot), facing the middle of the map.
local function place(character: Model, spawn: SpawnLocation?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local height = (if humanoid then humanoid.HipHeight else 2) + (if root and root:IsA("BasePart") then root.Size.Y / 2 else 1)
	local map = MapService.current()
	local middle = if map then map:GetPivot().Position else Vector3.zero
	local at: Vector3
	if spawn then
		local reach = math.max(0, math.min(spawn.Size.X, spawn.Size.Z) / 2 - 2)
		local offset = Vector3.new(random:NextNumber(-reach, reach), 0, random:NextNumber(-reach, reach))
		at = spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + height + 0.5, 0) + offset
	else
		-- No pad (a broken map): the middle, from just above the ground.
		at = Vector3.new(middle.X, height + 4, middle.Z)
	end
	local look = Vector3.new(middle.X, at.Y, middle.Z)
	character:PivotTo(if (look - at).Magnitude > 1 then CFrame.lookAt(at, look) else CFrame.new(at))
end

local function stopBrain(slot: Slot)
	local brain = slot.brain
	slot.brain = nil
	if brain then
		brain:stop()
	end
end

-- A fresh avatar for the bot at its team's safest spawn, replacing any it
-- has (alive or not).
local function spawnBot(slot: Slot)
	slot.token += 1
	local token = slot.token
	local bot = slot.bot
	local team = bot.team
	-- The first build of a body yields; anything may have changed by then.
	local body = template(team, slot.skin)
	if slots[bot.id] ~= slot or slot.token ~= token or bot.team ~= team then
		return
	end
	stopBrain(slot)
	local character = body:Clone()
	character.Name = bot.name
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	character.PrimaryPart = root
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = bot.name
	humanoid.WalkSpeed = WEAPON.walkSpeed
	place(character, MapService.safeSpawn(team, enemyPositions(team)))
	character.Parent = botsFolder()
	-- Held as a player holds it (LoadoutService): being in the avatar equips it.
	local tool = LoadoutService.buildTool(WEAPON)
	tool.Parent = character
	-- The server moves it, so no client is handed its physics. After the
	-- gun: welding it into the hand puts ownership back to automatic.
	pcall(root.SetNetworkOwner, root, nil)
	-- Set first: attach ends the previous life, and that Died isn't this one's.
	slot.character = character
	BotService.attach(bot, character)
	if slots[bot.id] ~= slot or slot.token ~= token or slot.character ~= character then
		return
	end
	animate(character)
	slot.brain = BotBrain.new(bot, character, BotConfig.tuning(difficulty()))
	Telemetry.log("BotDirector", "spawned", { bot = bot.id, team = team })
end

local function respawnAll()
	for _, slot in slots do
		task.spawn(spawnBot, slot)
	end
end

-- A life ended: back in RESPAWN_SECONDS, unless the bot has been moved,
-- respawned or removed by then.
local function onDied(bot: BotService.Bot, character: Model)
	local slot = slots[bot.id]
	if not slot or slot.character ~= character then
		return
	end
	slot.character = nil
	stopBrain(slot)
	local token = slot.token
	task.delay(GameConfig.RESPAWN_SECONDS, function()
		if slots[bot.id] == slot and slot.token == token then
			spawnBot(slot)
		end
	end)
end

-- Filling.

local function pickName(): string
	local used = {}
	for _, slot in slots do
		used[slot.bot.name] = true
	end
	local free = {}
	for _, name in BotConfig.NAMES do
		if not used["[BOT] " .. name] and not used[name] then
			table.insert(free, name)
		end
	end
	if #free > 0 then
		return free[random:NextInteger(1, #free)]
	end
	return `{BotConfig.NAMES[random:NextInteger(1, #BotConfig.NAMES)]} {random:NextInteger(2, 99)}`
end

local function addSlot(team: string)
	skinCounter += 1
	local bot = BotService.add(team, pickName())
	local slot: Slot = { bot = bot, token = 0, character = nil, brain = nil, skin = (skinCounter - 1) % #BotConfig.SKIN_TONES + 1 }
	slots[bot.id] = slot
	task.spawn(spawnBot, slot)
end

local function removeSlot(slot: Slot)
	slots[slot.bot.id] = nil
	slot.token += 1
	slot.character = nil
	stopBrain(slot)
	BotService.remove(slot.bot)
end

local function moveSlot(slot: Slot, team: string)
	slot.token += 1
	slot.character = nil
	stopBrain(slot)
	BotService.setTeam(slot.bot, team)
	task.spawn(spawnBot, slot)
end

-- The bot on `team` that's best to take away: one between lives (nobody's
-- fighting it), else the newest.
local function takeFrom(byTeam: { [string]: { Slot } }, team: string): Slot?
	local list = byTeam[team]
	if not list or #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		local aIdle, bIdle = a.character == nil, b.character == nil
		if aIdle ~= bIdle then
			return aIdle
		end
		return a.bot.id < b.bot.id
	end)
	return table.remove(list, 1)
end

local function humansInServer(): number
	for player in leaving do
		if player.Parent ~= Players then
			leaving[player] = nil
		end
	end
	local count = 0
	for _, player in Players:GetPlayers() do
		if not leaving[player] then
			count += 1
		end
	end
	return count
end

local function apply(plan: BotFill.Plan)
	local byTeam: { [string]: { Slot } } = {}
	for _, slot in slots do
		local team = slot.bot.team
		byTeam[team] = byTeam[team] or {}
		table.insert(byTeam[team], slot)
	end
	for _, team in plan.remove do
		local slot = takeFrom(byTeam, team)
		if slot then
			removeSlot(slot)
		end
	end
	for _, move in plan.move do
		local slot = takeFrom(byTeam, move.from)
		if slot then
			moveSlot(slot, move.to)
		end
	end
	for _, team in plan.add do
		addSlot(team)
	end
end

-- Brings the bots in line with BotFill now (normally a frame after a
-- change; see schedule).
function BotDirector.reconcile()
	if not started then
		return
	end
	local humans = if enabled then humansInServer() else 0
	local botCounts: { [string]: number } = {}
	for _, team in TeamConfig.order do
		botCounts[team] = 0
	end
	for _, slot in slots do
		botCounts[slot.bot.team] = (botCounts[slot.bot.team] or 0) + 1
	end
	local plan = BotFill.plan(humans, TeamService.humanCounts(), botCounts, TeamConfig.order, fillTo())
	if #plan.add + #plan.remove + #plan.move == 0 then
		return
	end
	applying = true
	local ok, err = pcall(apply, plan)
	applying = false
	if not ok then
		Telemetry.error("BotDirector", err)
		task.spawn(error, `[FW] BotDirector: {tostring(err)}`, 0)
		return
	end
	local line = {}
	for _, team in TeamConfig.order do
		table.insert(line, `{team} {plan.bots[team] or 0}`)
	end
	Telemetry.log("BotDirector", "filled", {
		humans = humans,
		added = #plan.add,
		removed = #plan.remove,
		moved = #plan.move,
		bots = table.concat(line, ", "),
	})
end

-- One reconcile a frame from now, however many changes come before it.
local function schedule()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		BotDirector.reconcile()
	end)
end

-- Every brain thinks (never yields; each in its own thread, so one
-- failing doesn't stop the rest).
local function think(dt: number)
	for _, slot in slots do
		local brain = slot.brain
		if brain then
			task.spawn(brain.tick, brain, dt)
		end
	end
end

-- Test-only (TestControls): the fill off (every bot goes) or on again, a
-- different fill target, or a different difficulty (for the next lives
-- and the ones running). nil puts BotConfig's back. Each applies now.
function BotDirector.testSetEnabled(on: boolean): boolean
	if not (GameConfig.TEST_CONTROLS.ENABLED and started) then
		return false
	end
	enabled = on
	BotDirector.reconcile()
	return true
end

function BotDirector.testSetFill(target: number?): boolean
	if not (GameConfig.TEST_CONTROLS.ENABLED and started) then
		return false
	end
	fillOverride = if target then math.clamp(math.floor(target), 0, GameConfig.MAX_PLAYERS) else nil
	BotDirector.reconcile()
	return true
end

function BotDirector.testSetDifficulty(value: number?): boolean
	if not (GameConfig.TEST_CONTROLS.ENABLED and started) then
		return false
	end
	difficultyOverride = if value then math.clamp(value, 0, 1) else nil
	local tuning = BotConfig.tuning(difficulty())
	for _, slot in slots do
		if slot.brain then
			slot.brain.tuning = tuning
		end
	end
	return true
end

-- The bots now, for test controls.
function BotDirector.status(): Status
	local bots = {}
	for _, bot in BotService.all() do
		local slot = slots[bot.id]
		if slot then
			table.insert(bots, { id = bot.id, name = bot.name, team = bot.team, alive = BotService.isAlive(bot) })
		end
	end
	return { enabled = enabled, fillTo = fillTo(), difficulty = difficulty(), bots = bots }
end

function BotDirector.start()
	if started or not FeatureFlags.BOTS then
		return
	end
	started = true
	enabled = true
	botsFolder()
	Players.PlayerAdded:Connect(schedule)
	Players.PlayerRemoving:Connect(function(player)
		leaving[player] = true
		schedule()
	end)
	TeamService.Changed:Connect(function()
		if not applying then
			schedule()
		end
	end)
	BotService.Died:Connect(onDied)
	RoundService.PhaseChanged:Connect(function(phase: string)
		if phase == States.Phase.ACTIVE then
			respawnAll()
		end
	end)
	MapService.Loaded:Connect(respawnAll)
	Health.loop("BotBrains", BotConfig.THINK_SECONDS, think)
	schedule()
end

return BotDirector
