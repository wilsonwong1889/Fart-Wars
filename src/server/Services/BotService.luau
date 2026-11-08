-- Bots: combatants that fill a quiet server (BotDirector decides how many
-- and where, BotBrain drives each one). A bot isn't a Player: it has a
-- negative ID (-1001, -1002, ..., never reused; Studio's test players
-- have -1, -2, ...) that stands in for a user ID in every CombatEvent, a
-- slot on a team (TeamService counts it), and in each life an avatar: a
-- Humanoid model in workspace.Bots, tagged "Bot", with BotId, TeamId and
-- DisplayName attributes.
-- Its gas meter keeps GasService's rules exactly: only enemy gas goes in
-- (friendly fire is off, and a protected or dead bot takes none); it's
-- clamped at 100. Five seconds without taking gas, it drains at 5% a
-- second. At 100 a one-second countdown runs and it explodes: the last
-- enemy to add gas (a player or a bot) is the killer if they did so in the
-- last ASSIST_WINDOW seconds, and other recent attackers assist. The
-- killer's team scores through EliminationService, which pays out nothing
-- for a bot. A bot that is removed, moved to the other team or given a new
-- avatar mid-countdown explodes on the spot; one that dies some other way
-- while gassed (a fall) is credited to its recent attacker. Every new
-- avatar gets spawn protection, which firing ends.
-- Each life carries a loadout, picked as it starts (BotConfig.pickLoadout:
-- leaning away from the guns its teammates carry): a gun from the arsenal,
-- held in its hand, at that gun's walking speed, and a Q ability.
-- Clients see what they see on a player's avatar: "Gas" (0-100),
-- "GasStage" (0-4), "ExplodesAt" and "ProtectedUntil" (server time), and
-- the SpawnProtection ForceField; and the life's "Weapon" and "Ability"
-- (ids), so every screen shows and hears the gun it really fires.
--   CombatEvent { kind = "explosion", victim, position, killer? }   all clients
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TeamConfig = require(Shared.Config.TeamConfig)
local FeatureFlags = require(Shared.Config.FeatureFlags)
local BotConfig = require(Shared.Config.BotConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local WeaponModel = require(Shared.WeaponModel)
local Signal = require(Shared.Signal)
local Server = script.Parent.Parent
local Telemetry = require(Server.Telemetry)
local Health = require(Server.Health)
local TeamService = require(script.Parent.TeamService)
local PlayerLifecycleService = require(script.Parent.PlayerLifecycleService)
local EliminationService = require(script.Parent.EliminationService)
local GasService = require(script.Parent.GasService)

local GAS = GameConfig.GAS
local TAG = "Bot"
local PREFIX = "[BOT] "
-- The first bot is -1001: below Studio's test players' -1, -2, ...
local FIRST_ID = -1001

local BotService = {}

export type Bot = {
	id: number, -- negative: -1001, -1002, ...
	name: string, -- display name, "[BOT] <name>"
	team: string, -- TeamConfig id
	character: Model?, -- current avatar, nil between lives
	-- This life's loadout (the last life's between lives): a WeaponConfig id
	-- and a Q ability's AbilityConfig id (nil: none).
	weapon: string,
	ability: string?,
}

-- A loadout to give a life instead of the pick (tests).
export type Loadout = { weapon: string, ability: string? }

-- (bot, character): attach() adopted a new avatar.
BotService.Spawned = Signal.new()
-- (bot, character): that life ended (exploded, fell, Health 0, removed,
-- moved, replaced). Once per character.
BotService.Died = Signal.new()
-- (bot, position, killer?, chainDepth, killerTeam?, killerBot?): a bot
-- exploded.
BotService.Exploded = Signal.new()

type Life = {
	bot: Bot,
	character: Model,
	humanoid: Humanoid,
	gas: number,
	stage: number,
	lastHitAt: number,
	firstHitAt: number?,
	contributors: { [Player]: number },
	botContributors: { [number]: number },
	-- The last to add gas: a player or a bot, never both.
	lastAttacker: Player?,
	lastAttackerBot: number?,
	lastAttackerTeam: string?,
	victimTeam: string,
	exploding: boolean,
	-- Credited already (exploded, or died while gassed).
	exploded: boolean,
	-- Over: Died has fired.
	ended: boolean,
	cause: string,
	chainDepth: number,
	-- The team behind the gas that started the countdown.
	finishTeam: string?,
	connections: { RBXScriptConnection },
}

local bots: { [number]: Bot } = {}
-- Each bot's latest life (its corpse's, between lives).
local lives: { [Bot]: Life } = {}
local byCharacter: { [Instance]: Bot } = {}
local lastId = FIRST_ID + 1
local started = false
local random = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function combatEvent(): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent") :: RemoteEvent
end

-- workspace.Bots, where every bot avatar lives.
local function folder(): Instance
	local existing = workspace:FindFirstChild("Bots")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "Bots"
	made.Parent = workspace
	return made
end

-- Tells TeamService how many bots `team` has now.
local function recount(team: string)
	local n = 0
	for _, bot in bots do
		if bot.team == team then
			n += 1
		end
	end
	TeamService.setBotCount(team, n)
end

-- The bot's current life, if it's still going.
local function current(bot: Bot): Life?
	local life = lives[bot]
	return if life and not life.ended and bots[bot.id] == bot then life else nil
end

local function publish(life: Life)
	local rounded = math.round(life.gas)
	if life.character:GetAttribute("Gas") ~= rounded then
		life.character:SetAttribute("Gas", rounded)
	end
	local stage = GasService.stageOf(life.gas)
	if stage ~= life.stage or life.character:GetAttribute("GasStage") == nil then
		life.stage = stage
		life.character:SetAttribute("GasStage", stage)
	end
end

-- An empty meter owes nobody anything: attackers and assists go.
local function forget(life: Life)
	life.firstHitAt = nil
	life.lastAttacker = nil
	life.lastAttackerBot = nil
	life.lastAttackerTeam = nil
	table.clear(life.contributors)
	table.clear(life.botContributors)
end

-- Who gets the credit at `at`: the last attacker, if they're still here and
-- added gas in the last ASSIST_WINDOW seconds, and the other recent ones
-- (bots only while they're not on this bot's team now; EliminationService
-- checks the players).
local function credit(life: Life, at: number): (Player?, number?, { Player }, { number })
	local window = GAS.ASSIST_WINDOW_SECONDS
	local killer = life.lastAttacker
	if killer and (killer.Parent ~= Players or at - (life.contributors[killer] or -math.huge) > window) then
		killer = nil
	end
	local killerBot = life.lastAttackerBot
	if killerBot and (not bots[killerBot] or at - (life.botContributors[killerBot] or -math.huge) > window) then
		killerBot = nil
	end
	local assists, assistBots = {}, {}
	for helper, when in life.contributors do
		if helper ~= killer and at - when <= window then
			table.insert(assists, helper)
		end
	end
	for id, when in life.botContributors do
		local helper = bots[id]
		if id ~= killerBot and helper and helper.team ~= life.victimTeam and at - when <= window then
			table.insert(assistBots, id)
		end
	end
	table.sort(assists, function(a, b)
		return a.UserId < b.UserId
	end)
	table.sort(assistBots, function(a, b)
		return a > b
	end)
	return killer, killerBot, assists, assistBots
end

-- The life is over: Died fires (once) and the bot has no avatar until the
-- next attach.
local function finish(life: Life)
	if life.ended then
		return
	end
	life.ended = true
	for _, connection in life.connections do
		connection:Disconnect()
	end
	byCharacter[life.character] = nil
	local bot = life.bot
	if bot.character == life.character then
		bot.character = nil
	end
	BotService.Died:Fire(bot, life.character)
end

-- The countdown's end (or the bot is going mid-countdown): the point, the
-- bang, the chain (ExplosionService hears Exploded), and the life is over.
local function explode(life: Life)
	if not life.exploding or life.exploded or life.ended then
		return
	end
	life.exploded = true
	local bot = life.bot
	local character = life.character
	local root = character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else character:GetPivot().Position
	local killer, killerBot, assists, assistBots = credit(life, now())
	Telemetry.count("Bots.explosions")
	EliminationService.eliminateBot(bot.id, character, {
		killer = killer,
		killerBot = killerBot,
		killerTeam = life.lastAttackerTeam,
		victimTeam = life.victimTeam,
		assists = assists,
		assistBots = assistBots,
		cause = life.cause,
	})
	combatEvent():FireAllClients({
		kind = "explosion",
		victim = bot.id,
		position = position,
		killer = if killer then killer.UserId else killerBot,
	})
	local credited = killer ~= nil or killerBot ~= nil
	BotService.Exploded:Fire(bot, position, killer, life.chainDepth, if credited then life.lastAttackerTeam else life.finishTeam, killerBot)
	finish(life)
end

local function beginExplosion(life: Life, source: GasService.Source)
	life.exploding = true
	life.cause = source.cause
	life.chainDepth = source.chainDepth or 0
	life.finishTeam = source.team or (source.attacker and TeamService.teamOf(source.attacker))
	life.character:SetAttribute("ExplodesAt", now() + GAS.EXPLOSION_COUNTDOWN_SECONDS)
	Telemetry.count("Bots.countdowns")
	task.delay(GAS.EXPLOSION_COUNTDOWN_SECONDS, explode, life)
end

-- Ends a life however it ends. Mid-countdown it explodes (the killer keeps
-- the point). Otherwise only a death is credited, to a recent attacker
-- while gassed; being removed or moved is not.
local function endLife(life: Life, died: boolean)
	if life.ended or life.exploded then
		return -- already being credited, which finishes it
	end
	if life.exploding then
		explode(life)
		return
	end
	if died then
		local killer, killerBot, assists, assistBots = credit(life, now())
		if (killer or killerBot) and life.gas > 0 then
			life.exploded = true
			EliminationService.eliminateBot(life.bot.id, life.character, {
				killer = killer,
				killerBot = killerBot,
				killerTeam = life.lastAttackerTeam,
				victimTeam = life.victimTeam,
				assists = assists,
				assistBots = assistBots,
				cause = "died",
			})
		end
	end
	finish(life)
end

-- Ends the current life without credit (unless mid-countdown) and takes
-- its avatar away.
local function discard(bot: Bot)
	local life = lives[bot]
	if life then
		endLife(life, false)
		life.character:Destroy()
		lives[bot] = nil
	end
end

-- A new bot slot on `team`, counted there at once. `name` gets the
-- "[BOT] " prefix if it hasn't got it.
function BotService.add(team: string, name: string): Bot
	assert(TeamConfig.teams[team], `no team "{team}"`)
	lastId -= 1
	local bot: Bot = {
		id = lastId,
		name = if string.sub(name, 1, #PREFIX) == PREFIX then name else PREFIX .. name,
		team = team,
		character = nil,
		weapon = BotConfig.WEAPON,
		ability = nil,
	}
	bots[bot.id] = bot
	recount(team)
	Telemetry.count("Bots.added")
	return bot
end

-- Frees the bot's slot for good: mid-countdown it explodes first (the
-- killer keeps the point), then its avatar goes.
function BotService.remove(bot: Bot)
	if bots[bot.id] ~= bot then
		return
	end
	discard(bot)
	bots[bot.id] = nil
	recount(bot.team)
	-- Like a player leaving: nothing it did can be credited any more.
	GasService.forgetBot(bot.id)
	for _, life in lives do
		life.botContributors[bot.id] = nil
	end
	Telemetry.count("Bots.removed")
end

-- Moves the bot's slot to `team`. The current life ends with no credit
-- (mid-countdown it explodes, as a player switching would) and its avatar
-- goes; the next attach() is on the new team.
function BotService.setTeam(bot: Bot, team: string)
	assert(TeamConfig.teams[team], `no team "{team}"`)
	if bots[bot.id] ~= bot or bot.team == team then
		return
	end
	discard(bot)
	local from = bot.team
	bot.team = team
	recount(from)
	recount(team)
end

function BotService.all(): { Bot }
	local list = {}
	for _, bot in bots do
		table.insert(list, bot)
	end
	table.sort(list, function(a, b)
		return a.id > b.id
	end)
	return list
end

function BotService.get(id: number): Bot?
	return bots[id]
end

-- The bot whose live avatar contains `instance`, if any.
function BotService.fromInstance(instance: Instance): Bot?
	local node: Instance? = instance
	while node do
		local bot = byCharacter[node]
		if bot then
			return bot
		end
		node = node.Parent
	end
	return nil
end

-- The guns the other bots on `team` carry in the lives they're living.
local function teamWeapons(team: string, except: Bot): { string }
	local list = {}
	for _, other in bots do
		if other ~= except and other.team == team and current(other) then
			table.insert(list, other.weapon)
		end
	end
	return list
end

-- This life's gun in the avatar's hand (the one it was built holding, if
-- that's the one), and its walking speed.
local function arm(character: Model, humanoid: Humanoid, weapon: WeaponConfig.Weapon)
	local held = character:FindFirstChild("HeldWeapon")
	if not (held and held:IsA("Tool") and held:GetAttribute("Weapon") == weapon.id) then
		if held then
			held:Destroy()
		end
		-- Held as a player holds it (LoadoutService): being in the avatar
		-- equips it.
		local tool = WeaponModel.tool(weapon.id, weapon.displayName)
		tool.Parent = character
		-- Welding a gun into the hand gives the body's physics back to
		-- Roblox; the server moves bots, so it takes them again.
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			pcall(root.SetNetworkOwner, root, nil)
		end
	end
	humanoid.WalkSpeed = weapon.walkSpeed
end

-- Adopts a freshly built avatar that's already standing at a spawn: tags
-- and attributes, an empty meter, spawn protection, and this life's
-- loadout (`loadout`, or else the pick). A previous avatar (alive or not)
-- goes, ending that life as a respawn would.
function BotService.attach(bot: Bot, character: Model, loadout: Loadout?)
	if bots[bot.id] ~= bot then
		warn(`[Bots] attach: {bot.name} isn't in the game`)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[Bots] attach: {bot.name}'s avatar has no Humanoid`)
		return
	end
	local previous = lives[bot]
	if previous and previous.character == character and not previous.ended then
		return
	end
	if previous and previous.character ~= character then
		discard(bot)
	end
	-- Hats and hair don't stop shots (or hide the head from a headshot).
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") and item:FindFirstAncestorOfClass("Accessory") then
			item.CanCollide = false
			item.CanQuery = false
		end
	end
	local weaponId, ability
	if loadout then
		weaponId, ability = loadout.weapon, loadout.ability
	else
		weaponId, ability = BotConfig.pickLoadout(random, teamWeapons(bot.team, bot))
	end
	local weapon = WeaponConfig.weapons[weaponId] or WeaponConfig.weapons[BotConfig.WEAPON]
	local q = ability and AbilityConfig[ability]
	bot.weapon = weapon.id
	bot.ability = if q and q.input == Enum.KeyCode.Q then q.id else nil
	character:SetAttribute("BotId", bot.id)
	character:SetAttribute("TeamId", bot.team)
	character:SetAttribute("DisplayName", bot.name)
	character:SetAttribute("Weapon", bot.weapon)
	character:SetAttribute("Ability", bot.ability)
	character:SetAttribute("ExplodesAt", nil)
	humanoid.DisplayName = bot.name
	arm(character, humanoid, weapon)
	CollectionService:AddTag(character, TAG)
	local home = folder()
	if character.Parent ~= home then
		character.Parent = home
	end
	local life: Life = {
		bot = bot,
		character = character,
		humanoid = humanoid,
		gas = 0,
		stage = 0,
		lastHitAt = -math.huge,
		firstHitAt = nil,
		contributors = {},
		botContributors = {},
		lastAttacker = nil,
		lastAttackerBot = nil,
		lastAttackerTeam = nil,
		victimTeam = bot.team,
		exploding = false,
		exploded = false,
		ended = false,
		cause = "shot",
		chainDepth = 0,
		finishTeam = nil,
		connections = {},
	}
	lives[bot] = life
	bot.character = character
	byCharacter[character] = bot
	publish(life)
	PlayerLifecycleService.protect(character)
	table.insert(life.connections, humanoid.Died:Connect(function()
		endLife(life, true)
	end))
	table.insert(life.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			endLife(life, false)
		end
	end))
	Telemetry.count("Bots.spawned")
	BotService.Spawned:Fire(bot, character)
end

function BotService.isAlive(bot: Bot): boolean
	local life = current(bot)
	return life ~= nil and life.humanoid.Health > 0
end

-- The HumanoidRootPart of the live avatar.
function BotService.rootOf(bot: Bot): BasePart?
	if not BotService.isAlive(bot) then
		return nil
	end
	local root = (bot.character :: Model):FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function BotService.isProtected(bot: Bot): boolean
	local character = bot.character
	local protectedUntil = character and character:GetAttribute("ProtectedUntil")
	return type(protectedUntil) == "number" and now() < protectedUntil
end

-- Attacking gives up the rest of the protection.
function BotService.endProtection(bot: Bot)
	local character = bot.character
	if character and character:GetAttribute("ProtectedUntil") ~= nil then
		character:SetAttribute("ProtectedUntil", nil)
		local field = character:FindFirstChild("SpawnProtection")
		if field then
			field:Destroy()
		end
	end
end

function BotService.gasOf(bot: Bot): number
	local life = current(bot)
	return if life then life.gas else 0
end

-- The gun this life carries (the last life's between lives).
function BotService.weaponOf(bot: Bot): WeaponConfig.Weapon
	return WeaponConfig.weapons[bot.weapon] or WeaponConfig.weapons[BotConfig.WEAPON]
end

-- Lets out up to `amount` of the bot's gas at once (Recovery Burst), as
-- GasService.vent does a player's. Returns how much went. Too late once
-- the countdown has started.
function BotService.vent(bot: Bot, amount: number): number
	local life = current(bot)
	if not life or life.exploding or life.gas <= 0 or amount <= 0 then
		return 0
	end
	local before = life.gas
	life.gas = math.max(0, life.gas - amount)
	if life.gas == 0 then
		forget(life)
	end
	publish(life)
	return before - life.gas
end

function BotService.isExploding(bot: Bot): boolean
	local life = current(bot)
	return life ~= nil and life.exploding
end

-- Adds gas to `bot` from `source` (GasService.add's rules). Returns whether
-- any went in.
function BotService.addGas(bot: Bot, amount: number, source: GasService.Source): boolean
	if not FeatureFlags.GAS_COMBAT or amount <= 0 then
		return false
	end
	local life = current(bot)
	if not life then
		return false
	end
	local victimTeam = bot.team
	local attacker = source.attacker
	local attackerTeam = source.team or (attacker and TeamService.teamOf(attacker))
	if source.bot == bot.id or (attackerTeam ~= nil and attackerTeam == victimTeam) then
		return false -- friendly fire is off
	end
	if source.bot and not attackerTeam then
		return false -- a bot's gas always says whose side it's on
	end
	-- An attacker who has since joined this bot's team (a chain still on its
	-- way) doesn't gas its new teammates. A bot that has gone still gasses
	-- for its team, credited to nobody.
	local attackerBot = source.bot and bots[source.bot]
	if (attacker and TeamService.teamOf(attacker) == victimTeam) or (attackerBot and attackerBot.team == victimTeam) then
		return false
	end
	if life.humanoid.Health <= 0 or life.exploding or BotService.isProtected(bot) then
		return false
	end
	local at = now()
	life.firstHitAt = life.firstHitAt or at
	life.gas = math.min(100, life.gas + amount)
	life.lastHitAt = at
	if attacker then
		life.contributors[attacker] = at
		life.lastAttacker, life.lastAttackerBot = attacker, nil
		life.lastAttackerTeam = attackerTeam
	elseif attackerBot then
		life.botContributors[attackerBot.id] = at
		life.lastAttacker, life.lastAttackerBot = nil, attackerBot.id
		life.lastAttackerTeam = attackerTeam
	end
	publish(life)
	if life.gas >= 100 then
		beginExplosion(life, source)
	end
	return true
end

-- Recovery: every bot that hasn't taken gas for a while drains.
function BotService.tick(dt: number)
	local at = now()
	for _, life in lives do
		if not life.ended and not life.exploding and life.gas > 0 and at - life.lastHitAt >= GAS.RECOVERY_DELAY_SECONDS then
			life.gas = math.max(0, life.gas - GAS.RECOVERY_PER_SECOND * dt)
			if life.gas == 0 then
				forget(life)
			end
			publish(life)
		end
	end
end

-- Where the live bots against `teamId` stand.
local function enemyPositions(teamId: string): { Vector3 }
	local positions = {}
	for _, bot in bots do
		local root = if bot.team ~= teamId then BotService.rootOf(bot) else nil
		if root then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

function BotService.start()
	if started then
		return
	end
	started = true
	folder()
	-- Players don't spawn on top of a bot.
	PlayerLifecycleService.enemyBotPositions = enemyPositions
	Players.PlayerRemoving:Connect(function(player)
		for _, life in lives do
			life.contributors[player] = nil
		end
	end)
	Health.loop("Bots", GAS.TICK_SECONDS, BotService.tick)
end

return BotService
