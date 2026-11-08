-- The practice yard (FeatureFlags.PRACTICE): a short warm-up before a
-- player's first match. The client asks for it ("start" on the Practice
-- remote) when a profile's first PLAY is pressed, and again whenever
-- PRACTICE is pressed on the home screen or in Settings. The server builds
-- the player a yard of their own (ServerStorage.Maps.PracticeYard) far from
-- the battlefield, moves them into it (PlayerLifecycleService.enterPractice:
-- State PRACTICE, an avatar holding the Gas Blaster, no team slot, no
-- spawn protection) and runs the steps (PracticeConfig): gas the dummies,
-- Fart Dash, blow up the barrel, done. Then they're back on the home
-- screen, where the client opens the team screen.
--   * once per profile: due while the profile has never finished or
--     skipped the yard and never played a match (no playtime), and never
--     on a temporary profile (in a DataStore outage everyone looks new)
--   * the dummies and the barrel are the server's, a set for each yard,
--     and only their owner's shots (CombatService.PracticeHit) and dashes
--     (DashService.PracticeDashed) reach them. Nothing in the yard pays or
--     counts: no coins, XP, stats, challenges, funnel steps or team points
--   * the AFK check only watches players in a match, and the yard gives no
--     spawn protection, so neither gets in the way
--   * finishing, skipping ("skip"), spectating (M) or PLAY from the yard
--     count it as done; leaving the game mid-yard doesn't, so it's offered
--     again next time
--   * the yard comes down whenever its player leaves PRACTICE, however
-- The Practice remote: the client asks "start" or "skip"; a start that's
-- refused gets "refused" (and why) straight back, so a first PLAY can go
-- on to the team screen at once. What the client reads, as Player
-- attributes:
--   PracticeDue    their next PLAY goes to the yard
--   PracticeStep   in the yard: "intro", a step's id, or "done"
--   PracticeCount  that step's progress (at its goal: done, cheering)
--   PracticeEnded  how their last yard ended: "finished", "skipped" or
--                  "failed" (set before they leave PRACTICE, so the team
--                  screen can follow), or "left" / "played" (after)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local PracticeConfig = require(Shared.Config.PracticeConfig)
local States = require(Shared.States)
local WeaponModel = require(Shared.WeaponModel)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local RateLimit = require(Server.RateLimit)
local DataService = require(script.Parent.DataService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local CombatService = require(script.Parent.CombatService)
local DashService = require(script.Parent.DashService)
local PracticeYard = require(ServerStorage:WaitForChild("Maps"):WaitForChild("PracticeYard")) :: any

local PlayerState = States.Player
local STEPS = PracticeConfig.STEPS
local DUMMY = PracticeConfig.DUMMY
local BARREL = GameConfig.BARREL
local EXPLOSION = GameConfig.EXPLOSION

local PracticeService = {}

type Dummy = {
	id: number,
	model: Model,
	body: BasePart,
	gas: number,
	popped: boolean,
	-- Bumped by each pop, so a respawn that comes late gives way.
	life: number,
}
type Barrel = { model: Model, body: BasePart, health: number, state: "ready" | "fused" | "gone" }
export type Session = {
	player: Player,
	slot: number,
	-- Their first time (it was due), or a replay.
	first: boolean,
	yard: Model,
	-- Where the avatar appears: on the START pad, looking down the yard.
	start: CFrame,
	dummies: { Dummy },
	-- Each dummy by its parts that take shots.
	parts: { [Instance]: Dummy },
	barrel: Barrel,
	-- 0 the intro, 1 to #STEPS the steps, #STEPS + 1 done.
	step: number,
	count: number,
	-- The step's goal is reached (its cheer is up).
	cleared: boolean,
	startedAt: number,
	-- How it's ending ("finished", "skipped", "failed"), once it is.
	ending: string?,
	-- False once the yard is down: anything that comes late gives way.
	alive: boolean,
	connections: { RBXScriptConnection },
}

local sessions: { [Player]: Session } = {}
-- Which player has each yard spot (1 to MAX_PLAYERS).
local slots: { [number]: Player } = {}
-- Test seam: due or not, whatever the profile says.
local dueOverride: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local limiter = RateLimit.new(GameConfig.REQUEST_COOLDOWN_SECONDS)
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function combatEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
end

-- Whether `player`'s next PLAY goes to the yard.
function PracticeService.due(player: Player): boolean
	if not FeatureFlags.PRACTICE then
		return false
	end
	local override = dueOverride[player]
	if override ~= nil then
		return override
	end
	local profile = DataService.get(player)
	if not profile or profile.temporary then
		return false
	end
	return profile.data.PracticeDone ~= true and profile.data.TotalPlaytime <= 0
end

local function publish(player: Player)
	player:SetAttribute("PracticeDue", PracticeService.due(player))
end

-- Done with for good: saved in the profile (when there is one).
local function markDone(player: Player)
	dueOverride[player] = nil
	DataService.update(player, function(data)
		data.PracticeDone = true
	end)
	publish(player)
end

-- Test-only: whether `player`'s next PLAY goes to the yard, whatever their
-- profile says (nil: as it says again).
function PracticeService.testSetDue(player: Player, due: boolean?)
	dueOverride[player] = due
	publish(player)
end

-- The yard `player` is in, if any.
function PracticeService.get(player: Player): Session?
	return sessions[player]
end

-- Where yard spot `slot` is built: a grid out past the battlefield.
function PracticeService.origin(slot: number): CFrame
	local column = (slot - 1) % PracticeConfig.COLUMNS
	local row = (slot - 1) // PracticeConfig.COLUMNS
	return CFrame.new(PracticeConfig.ORIGIN + Vector3.new(column * PracticeConfig.SPACING, 0, row * PracticeConfig.SPACING))
end

local function freeSlot(): number?
	for slot = 1, GameConfig.MAX_PLAYERS do
		if not slots[slot] then
			return slot
		end
	end
	return nil
end

local function yardsFolder(): Folder
	local folder = workspace:FindFirstChild("PracticeYards")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PracticeYards"
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function stepName(session: Session): string
	local step = STEPS[session.step]
	return if session.step == 0 then "intro" elseif step then step.id else "done"
end

local finish: (Session, string) -> ()

local function setStep(session: Session, index: number)
	session.step = index
	session.count = 0
	session.cleared = false
	local player = session.player
	player:SetAttribute("PracticeStep", stepName(session))
	player:SetAttribute("PracticeCount", 0)
	if index > #STEPS then
		-- The send-off, then on to the team screen.
		task.delay(PracticeConfig.DONE_SECONDS, function()
			if session.alive then
				finish(session, "finished")
			end
		end)
	end
end

-- `amount` more toward step `id`, if it's the one going; at its goal, a
-- cheer and then the next step.
local function progress(session: Session, id: string, amount: number)
	local step = STEPS[session.step]
	if not (session.alive and step and step.id == id) or session.cleared then
		return
	end
	session.count = math.min(step.goal, session.count + amount)
	session.player:SetAttribute("PracticeCount", session.count)
	if session.count < step.goal then
		return
	end
	session.cleared = true
	Telemetry.count(`Practice.cleared.{id}`)
	local index = session.step
	task.delay(PracticeConfig.CHEER_SECONDS, function()
		if session.alive and session.step == index then
			setStep(session, index + 1)
		end
	end)
end

local gasDummy: (Session, Dummy, number, number) -> ()

-- At 100: the dummy pops (the owner sees it go off, in their own boom
-- colour), its blast gasses the dummies near it like a player's would, and
-- it's back, empty, a moment later.
local function pop(session: Session, dummy: Dummy, depth: number)
	dummy.popped = true
	dummy.life += 1
	PracticeYard.setPopped(dummy.model, true)
	local at = dummy.body.Position
	combatEvent():FireClient(session.player, { kind = "explosion", position = at, killer = session.player.UserId })
	Telemetry.count("Practice.pops")
	progress(session, "shoot", 1)
	if depth < EXPLOSION.CHAIN_MAX_DEPTH then
		for _, other in session.dummies do
			if not other.popped and (other.body.Position - at).Magnitude <= EXPLOSION.RADIUS then
				task.delay(PracticeConfig.CHAIN_STAGGER_SECONDS, gasDummy, session, other, EXPLOSION.CHAIN_GAS, depth + 1)
			end
		end
	end
	local life = dummy.life
	task.delay(DUMMY.RESPAWN_SECONDS, function()
		if session.alive and dummy.life == life then
			dummy.gas = 0
			dummy.popped = false
			PracticeYard.inflate(dummy.model, 0)
			PracticeYard.setPopped(dummy.model, false)
		end
	end)
end

function gasDummy(session: Session, dummy: Dummy, amount: number, depth: number)
	if not session.alive or dummy.popped then
		return
	end
	dummy.gas = math.min(100, dummy.gas + amount)
	PracticeYard.inflate(dummy.model, dummy.gas)
	if dummy.gas >= 100 then
		pop(session, dummy, depth)
	end
end

-- The barrel's blast: every dummy it reaches goes off (the nearest first),
-- and it's back a few seconds later.
local function explodeBarrel(session: Session)
	local barrel = session.barrel
	barrel.state = "gone"
	local at = barrel.body.Position
	local size = barrel.body.Size
	local reach = BARREL.RADIUS + math.max(size.X, size.Y, size.Z) / 2
	PracticeYard.setBarrel(barrel.model, "gone")
	combatEvent():FireClient(session.player, { kind = "barrel", position = at, radius = reach })
	Telemetry.count("Practice.barrels")
	for _, dummy in session.dummies do
		local distance = (dummy.body.Position - at).Magnitude
		if not dummy.popped and distance <= reach then
			task.delay(PracticeConfig.CHAIN_STAGGER_SECONDS * distance / reach, gasDummy, session, dummy, PracticeConfig.BARREL.GAS, 1)
		end
	end
	progress(session, "barrel", 1)
	task.delay(PracticeConfig.BARREL.RESPAWN_SECONDS, function()
		if session.alive and barrel.state == "gone" then
			barrel.state = "ready"
			barrel.health = BARREL.HEALTH
			PracticeYard.setBarrel(barrel.model, "ready")
		end
	end)
end

-- A shot at the barrel: the battlefield's health and fuse.
local function shootBarrel(session: Session, amount: number)
	local barrel = session.barrel
	if barrel.state ~= "ready" then
		return
	end
	barrel.health = math.max(0, barrel.health - amount)
	if barrel.health > 0 then
		return
	end
	barrel.state = "fused"
	PracticeYard.setBarrel(barrel.model, "fused")
	task.delay(BARREL.FUSE_SECONDS, function()
		if session.alive and barrel.state == "fused" then
			explodeBarrel(session)
		end
	end)
end

-- What a shot in a yard hit: only the shooter's own yard reacts. A hit on
-- a dummy shows on the shooter's crosshair like any hit (a body hit, a
-- headshot, or the one that pops it), and does no more than a hit on a
-- player would at that range.
local function onHit(shooter: Player, part: Instance, weapon: WeaponConfig.Weapon, from: Vector3, at: Vector3)
	local session = sessions[shooter]
	if not (session and session.alive) then
		return
	end
	local dummy = session.parts[part]
	if dummy then
		if dummy.popped then
			return
		end
		local headshot = part.Name == "Head"
		gasDummy(session, dummy, CombatService.gasAt(weapon, (at - from).Magnitude, headshot), 0)
		combatEvent():FireClient(shooter, { kind = "hit", victim = dummy.id, gas = dummy.gas, headshot = headshot, blocked = false })
	elseif part:IsDescendantOf(session.barrel.model) then
		shootBarrel(session, weapon.gasPerHit)
	end
end

-- The yard's gun is the starter Gas Blaster, whatever's equipped (the next
-- match spawn puts the loadout back).
local function equip(player: Player, character: Model)
	local weapon = WeaponConfig.weapons[WeaponConfig.default]
	CombatService.setWeapon(player, weapon.id)
	local held = character:FindFirstChild("HeldWeapon")
	if held then
		held:Destroy()
	end
	WeaponModel.tool(weapon.id, weapon.displayName).Parent = character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = weapon.walkSpeed
	end
end

-- An avatar that dies in the yard (it shouldn't: nothing there hurts) is
-- back on the START pad a moment later.
local function watchAvatar(session: Session, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	table.insert(session.connections, humanoid.Died:Connect(function()
		task.delay(PracticeConfig.RESPAWN_SECONDS, function()
			local player = session.player
			if not (session.alive and player.Character == character) then
				return
			end
			local fresh = PlayerLifecycleService.enterPractice(player, session.start)
			if fresh and session.alive then
				equip(player, fresh)
				watchAvatar(session, fresh)
			end
		end)
	end))
end

-- Takes the yard down and lets its spot go. `reason`: how it ended
-- ("finished", "skipped", "failed"), or what took the player out of it
-- ("spectated", "played", "quit").
local function teardown(session: Session, reason: string)
	if not session.alive then
		return
	end
	session.alive = false
	local player = session.player
	if sessions[player] == session then
		sessions[player] = nil
	end
	if slots[session.slot] == player then
		slots[session.slot] = nil
	end
	for _, connection in session.connections do
		connection:Disconnect()
	end
	table.clear(session.connections)
	local step = stepName(session)
	session.yard:Destroy()
	if reason ~= "quit" then
		-- Spectating or playing from the yard means they're done with it.
		if reason == "spectated" or reason == "played" then
			markDone(player)
			player:SetAttribute("PracticeEnded", if reason == "spectated" then "left" else "played")
		end
		player:SetAttribute("PracticeStep", nil)
		player:SetAttribute("PracticeCount", nil)
	end
	Telemetry.count(`Practice.{reason}`)
	Telemetry.sample("Practice.seconds", now() - session.startedAt)
	Telemetry.log("Practice", "ended", { player = player, how = reason, step = step, first = session.first })
end

-- Ends the yard: saved as done (unless it never got going), then back to
-- the home screen, whose team screen follows (PracticeEnded is set first).
function finish(session: Session, how: string)
	if not session.alive or session.ending then
		return
	end
	session.ending = how
	local player = session.player
	if how ~= "failed" then
		markDone(player)
	end
	player:SetAttribute("PracticeEnded", how)
	if not PlayerLifecycleService.toSpectator(player, PlayerState.MENU_SPECTATOR) then
		teardown(session, how)
	end
end

-- Sends `player` (on the home screen) to a yard of their own. Returns
-- whether they're in one, and why not.
function PracticeService.begin(player: Player): (boolean, string)
	if not FeatureFlags.PRACTICE then
		return false, "off"
	end
	if sessions[player] then
		return false, "practicing"
	end
	local state = PlayerLifecycleService.stateOf(player)
	if state ~= PlayerState.MENU_SPECTATOR and state ~= PlayerState.AFK_SPECTATOR then
		return false, "notOnHomeScreen"
	end
	local slot = freeSlot()
	if not slot then
		return false, "full"
	end
	local yard = PracticeYard.build(PracticeService.origin(slot)) :: Model
	yard.Name = `Yard{slot}`
	yard:SetAttribute("UserId", player.UserId)
	local barrelModel = yard:FindFirstChild("PracticeBarrel") :: Model
	local session: Session = {
		player = player,
		slot = slot,
		first = PracticeService.due(player),
		yard = yard,
		start = (yard:FindFirstChild("Start") :: BasePart).CFrame * CFrame.new(0, 2.5, 0),
		dummies = {},
		parts = {},
		barrel = { model = barrelModel, body = barrelModel.PrimaryPart :: BasePart, health = BARREL.HEALTH, state = "ready" },
		step = 0,
		count = 0,
		cleared = false,
		startedAt = now(),
		ending = nil,
		alive = true,
		connections = {},
	}
	local models = (yard:FindFirstChild("Dummies") :: Folder):GetChildren()
	table.sort(models, function(a, b)
		return a.Name < b.Name
	end)
	for i, model in models do
		local dummy: Dummy = {
			id = PracticeConfig.DUMMY_ID_BASE - (slot - 1) * 10 - i,
			model = model :: Model,
			body = model:FindFirstChild("Body") :: BasePart,
			gas = 0,
			popped = false,
			life = 0,
		}
		table.insert(session.dummies, dummy)
		session.parts[dummy.body] = dummy
		session.parts[model:FindFirstChild("Head") :: BasePart] = dummy
	end
	sessions[player] = session
	slots[slot] = player
	yard.Parent = yardsFolder()
	player:SetAttribute("PracticeEnded", nil)
	setStep(session, 0)

	local character = PlayerLifecycleService.enterPractice(player, session.start)
	if not session.alive then
		-- They left, spectated or played while the avatar loaded.
		return false, "gone"
	end
	if not character then
		finish(session, "failed")
		return false, "noAvatar"
	end
	equip(player, character)
	watchAvatar(session, character)
	-- (The log counts every start, Practice.started.)
	if not session.first then
		Telemetry.count("Practice.replayed")
	end
	Telemetry.log("Practice", "started", { player = player, first = session.first, slot = slot })
	task.delay(PracticeConfig.INTRO_SECONDS, function()
		if session.alive and session.step == 0 then
			setStep(session, 1)
		end
	end)
	-- However it's going, it doesn't go on for ever.
	task.delay(PracticeConfig.MAX_SECONDS, function()
		if session.alive and not session.ending then
			Telemetry.count("Practice.timedOut")
			finish(session, "finished")
		end
	end)
	return true, "started"
end

-- SKIP: out of the yard now, done with it, on to the team screen.
function PracticeService.skip(player: Player): boolean
	local session = sessions[player]
	if not (session and session.alive) or session.ending then
		return false
	end
	Telemetry.count(`Practice.skippedAt.{stepName(session)}`)
	finish(session, "skipped")
	return true
end

function PracticeService.start()
	if started then
		return
	end
	started = true
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Practice") :: RemoteEvent
	-- Clients only ask; the server checks everything.
	local function refuse(player: Player, why: string)
		Telemetry.reject("Practice", player, why)
		if player.Parent == Players then
			remote:FireClient(player, "refused", why)
		end
	end
	remote.OnServerEvent:Connect(Telemetry.guard("Practice", function(player, action)
		if action ~= "start" and action ~= "skip" then
			Telemetry.reject("Practice", player, "badPayload")
			return
		end
		if not limiter:allow(player, action) then
			if action == "start" then
				refuse(player, "rateLimited")
			else
				Telemetry.reject("Practice", player, "rateLimited")
			end
			return
		end
		if action == "skip" then
			PracticeService.skip(player)
			return
		end
		local ok, why = PracticeService.begin(player)
		if not ok then
			refuse(player, why)
		end
	end))
	CombatService.PracticeHit:Connect(onHit)
	DashService.PracticeDashed:Connect(function(player)
		local session = sessions[player]
		if session then
			progress(session, "dash", 1)
		end
	end)
	-- However they left PRACTICE, the yard comes down.
	PlayerLifecycleService.StateChanged:Connect(function(player, state, previous)
		local session = sessions[player]
		if not session or previous ~= PlayerState.PRACTICE or state == PlayerState.PRACTICE then
			return
		end
		local reason = session.ending
			or (if state == nil then "quit" elseif state == PlayerState.ACTIVE then "played" else "spectated")
		teardown(session, reason)
	end)
	DataService.Loaded:Connect(publish)
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			teardown(session, "quit")
		end
		limiter:forget(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			publish(player)
		end
	end
end

return PracticeService
