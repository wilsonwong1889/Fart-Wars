-- Who's in the fight, as this client sees it: the players and the bots
-- (the fillers the server runs while it's short of people; they aren't
-- Player objects). CombatEvents name a combatant by a number, a player's
-- UserId or a bot's BotId (negative); this turns that number into a name, a
-- team and the current avatar, and keeps the list of every avatar on the
-- field, so the controllers never look players and bots up separately.
--   * a bot's avatar is a Model in workspace.Bots, tagged "Bot", carrying
--     its BotId, TeamId and DisplayName ("[BOT] Toots"), and the Weapon its
--     life carries; each life is a new avatar, so watch() hears about every
--     one
--   * a bot's name and team are remembered after its avatar goes (ids are
--     never reused), so a kill feed line that arrives late still names it
--   * an id nobody here knows gives nil; nothing here errors on one
--   * a player with the id wins: only Studio's Local Server test players
--     have negative UserIds (-1, -2, ...), and those are the first bots'
--     ids too, so in that test the two can be mistaken for each other
-- It starts itself the first time it's asked anything.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local Combatants = {}

export type Combatant = {
	id: number,
	-- The display name (a bot's says it's a bot).
	name: string,
	team: string?,
	-- The current avatar: nil between lives.
	character: Model?,
	-- The Player, for a player (cosmetics, the Players screen); nil for a bot.
	player: Player?,
	bot: boolean,
	-- The gun in their hands (a WeaponConfig id: a player's equipped one, a
	-- bot's life's), nil if nothing says (a bot between lives).
	weapon: string?,
}

Combatants.TAG = "Bot"
Combatants.FOLDER = "Bots"
-- An avatar arrived on the field or left it, a player's or a bot's:
-- (character, combatant?).
Combatants.AvatarAdded = Signal.new()
Combatants.AvatarRemoved = Signal.new()

-- The bots' avatars on the field (each with the order it arrived in, so a
-- new life wins over a body that hasn't gone yet), and the last name and
-- team seen for each bot.
local avatars: { [Model]: number } = {}
local seen: { [number]: { name: string, team: string? } } = {}
local arrivals = 0
local started = false

local function teamOf(instance: Instance): string?
	local team = instance:GetAttribute("TeamId")
	return if type(team) == "string" then team else nil
end

-- The "Weapon" attribute (a player's on the Player, a bot's on its avatar),
-- else the gun held in the avatar's hands.
local function weaponOf(instance: Instance, avatar: Model?): string?
	local weapon = instance:GetAttribute("Weapon")
	if type(weapon) == "string" then
		return weapon
	end
	local held = avatar and avatar:FindFirstChild("HeldWeapon")
	weapon = held and held:GetAttribute("Weapon")
	return if type(weapon) == "string" then weapon else nil
end

local function fromPlayer(player: Player): Combatant
	return {
		id = player.UserId,
		name = player.DisplayName,
		team = teamOf(player),
		character = player.Character,
		player = player,
		bot = false,
		weapon = weaponOf(player, player.Character),
	}
end

local function fromBot(avatar: Model): Combatant?
	local id = avatar:GetAttribute("BotId")
	if type(id) ~= "number" then
		return nil
	end
	local name = avatar:GetAttribute("DisplayName")
	if type(name) ~= "string" or name == "" then
		local humanoid = avatar:FindFirstChildOfClass("Humanoid")
		name = if humanoid and type(humanoid.DisplayName) == "string" and humanoid.DisplayName ~= "" then humanoid.DisplayName else avatar.Name
	end
	local who: Combatant = {
		id = id,
		name = name :: string,
		team = teamOf(avatar),
		character = if avatar.Parent then avatar else nil,
		player = nil,
		bot = true,
		weapon = weaponOf(avatar, avatar),
	}
	seen[id] = { name = who.name, team = who.team }
	return who
end

-- A bot's newest avatar on the field.
local function avatarOf(id: number): Model?
	local best: Model?, newest = nil, 0
	for avatar, arrived in avatars do
		if arrived > newest and avatar.Parent and avatar:GetAttribute("BotId") == id then
			best, newest = avatar, arrived
		end
	end
	return best
end

local function drop(avatar: Model)
	if not avatars[avatar] then
		return
	end
	avatars[avatar] = nil
	Combatants.AvatarRemoved:Fire(avatar, fromBot(avatar))
end

-- A bot's avatar, once it's on the field (it's seen both ways: by its tag
-- and in workspace.Bots, whichever comes first).
local function adopt(instance: Instance)
	if not instance:IsA("Model") or avatars[instance :: Model] or not instance:IsDescendantOf(workspace) then
		return
	end
	local avatar = instance :: Model
	arrivals += 1
	avatars[avatar] = arrivals
	local connection: RBXScriptConnection
	connection = avatar.AncestryChanged:Connect(function()
		if not avatar:IsDescendantOf(workspace) then
			connection:Disconnect()
			drop(avatar)
		end
	end)
	Combatants.AvatarAdded:Fire(avatar, fromBot(avatar))
end

local function watchFolder(folder: Instance)
	folder.ChildAdded:Connect(adopt)
	for _, child in folder:GetChildren() do
		adopt(child)
	end
end

-- (The handlers find the player from the character, so nothing here keeps a
-- player who has left.)
local function characterAdded(character: Model)
	Combatants.AvatarAdded:Fire(character, Combatants.fromCharacter(character))
end

local function characterRemoving(character: Model)
	Combatants.AvatarRemoved:Fire(character, Combatants.fromCharacter(character))
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(characterAdded)
	player.CharacterRemoving:Connect(characterRemoving)
end

local function ensure()
	if started then
		return
	end
	started = true
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	local folder = workspace:FindFirstChild(Combatants.FOLDER)
	if folder then
		watchFolder(folder)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == Combatants.FOLDER then
			watchFolder(child)
		end
	end)
	CollectionService:GetInstanceAddedSignal(Combatants.TAG):Connect(adopt)
	for _, tagged in CollectionService:GetTagged(Combatants.TAG) do
		adopt(tagged)
	end
end

-- Who `id` is (a UserId, or a bot's negative BotId), or nil.
function Combatants.get(id: any): Combatant?
	if type(id) ~= "number" then
		return nil
	end
	ensure()
	local player = Players:GetPlayerByUserId(id)
	if player then
		return fromPlayer(player)
	elseif id >= 0 then
		return nil
	end
	local avatar = avatarOf(id)
	local who = avatar and fromBot(avatar)
	if who then
		return who
	end
	local last = seen[id]
	return if last then { id = id, name = last.name, team = last.team, character = nil, player = nil, bot = true } else nil
end

-- Just the avatar (nil between lives, or for nobody).
function Combatants.character(id: any): Model?
	local who = Combatants.get(id)
	return who and who.character
end

-- Who an avatar belongs to: a player's character or a bot's avatar.
function Combatants.fromCharacter(character: Instance?): Combatant?
	if not (character and character:IsA("Model")) then
		return nil
	end
	ensure()
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return fromPlayer(player)
	end
	if avatars[character :: Model] or CollectionService:HasTag(character, Combatants.TAG) then
		return fromBot(character :: Model)
	end
	return nil
end

-- Every avatar on the field: the players' characters, then the bots'.
function Combatants.avatars(): { Model }
	ensure()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for avatar in avatars do
		if avatar.Parent then
			table.insert(list, avatar)
		end
	end
	return list
end

-- The bots on the field now (with an avatar), one each, by name.
function Combatants.bots(): { Combatant }
	ensure()
	local byId: { [number]: Combatant } = {}
	for avatar in avatars do
		local who = if avatar.Parent then fromBot(avatar) else nil
		if who and avatarOf(who.id) == avatar then
			byId[who.id] = who
		end
	end
	local list = {}
	for _, who in byId do
		table.insert(list, who)
	end
	table.sort(list, function(a, b)
		return if a.name ~= b.name then a.name < b.name else a.id > b.id
	end)
	return list
end

-- Calls `callback(character, combatant)` for every avatar on the field now
-- and for each one that arrives (a player's as they spawn, a bot's for each
-- life). Returns the connection for the arrivals.
function Combatants.watch(callback: (Model, Combatant?) -> ()): Signal.Connection
	ensure()
	local connection = Combatants.AvatarAdded:Connect(callback)
	for _, character in Combatants.avatars() do
		callback(character, Combatants.fromCharacter(character))
	end
	return connection
end

return Combatants
