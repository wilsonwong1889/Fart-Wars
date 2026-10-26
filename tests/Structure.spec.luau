-- The project's shape (plan sections 1-3):
--   * every ModuleScript loads, with no require cycles (the harness fails a
--     module that requires itself through others, as Roblox does)
--   * GameConfig holds the plan's numbers
--   * ReplicatedStorage.Remotes holds exactly the planned remotes
--   * the feature flags default to 5-minute rounds with gas combat on, and
--     the weapon and ability configs keep the masterplan's contracts (shop
--     weapons and Q abilities unlock at their level; every sound has a slot)
--   * the configured mode and map exist and fit their contracts, and every
--     map lists only modes that exist
--   * the teams are the Skibidi Stinkers (green) and Sigma Sharters (yellow)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

local roots = {
	ReplicatedStorage.Shared,
	game.ServerScriptService.Server,
	ServerStorage.Maps,
	game.StarterPlayer.StarterPlayerScripts.Client,
}
local loaded = 0
for _, root in roots do
	for _, item in root:GetDescendants() do
		if item:IsA("ModuleScript") then
			local ok, err = pcall(require, item)
			check(ok, `{item:GetFullName()} loads: {err}`)
			loaded += 1
		end
	end
end
check(loaded >= 25, "every module was tried")

local shared = ReplicatedStorage.Shared
local GameConfig = require(shared.Config.GameConfig)
check(GameConfig.ROUND_SECONDS == 300 and GameConfig.INTERMISSION_SECONDS == 15, "5-minute rounds, 15-second intermission")
check(GameConfig.MIN_ACTIVE_PLAYERS == 2 and GameConfig.MAX_TEAM_SIZE == 10 and GameConfig.MAX_PLAYERS == 20, "2 to start, 10 a team, 20 a server")
check(GameConfig.AFK_WARNING_SECONDS == 45 and GameConfig.AFK_SPECTATE_SECONDS == 60, "AFK at 45 and 60 seconds")
check(table.isfrozen(GameConfig), "the config can't be changed at runtime")

local remotes = {
	RequestPlay = "RemoteEvent",
	RequestTeam = "RemoteEvent",
	RequestSpectate = "RemoteEvent",
	RoundSnapshot = "RemoteFunction",
	RoundUpdate = "RemoteEvent",
	TeamUpdate = "RemoteEvent",
	UIMessage = "RemoteEvent",
	FireWeapon = "RemoteEvent",
	FartDash = "RemoteEvent",
	CombatEvent = "RemoteEvent",
	ProgressEvent = "RemoteEvent",
	UseAbility = "RemoteEvent",
	ShopRequest = "RemoteFunction",
	ProfileUpdate = "RemoteEvent",
}
local present = 0
for _, child in ReplicatedStorage.Remotes:GetChildren() do
	check(remotes[child.Name] == child.ClassName, `{child.Name} is a planned {remotes[child.Name] or "?"}`)
	present += 1
end
check(present == 14, "all fourteen remotes, nothing else")

local FeatureFlags = require(shared.Config.FeatureFlags)
check(FeatureFlags.MATCH_MODE == "Rounds", "5-minute rounds by default")
check(FeatureFlags.GAS_COMBAT and FeatureFlags.FART_DASH and FeatureFlags.SPAWN_PROTECTION, "gas combat is on")
check(FeatureFlags.PROGRESSION, "progression is on")
check(table.isfrozen(FeatureFlags), "flags can't change at runtime")
local WeaponConfig = require(shared.Config.WeaponConfig)
local ProgressionConfig = require(shared.Config.ProgressionConfig)
check(WeaponConfig.weapons[WeaponConfig.default], "the default weapon exists")
for id, weapon in WeaponConfig.weapons do
	check(weapon.id == id and weapon.gasPerHit > 0 and weapon.headshotGas >= weapon.gasPerHit, `{id} has gas per hit (more to the head)`)
	check(weapon.fireInterval > 0 and weapon.range > 0, `{id} has an interval and a range`)
	check((weapon.projectile == "hitscan" or weapon.projectile == "lob") and weapon.unlock ~= nil and typeof(weapon.tracerColor) == "Color3", `{id} has projectile, unlock and effects`)
	check(weapon.walkSpeed > 0 and weapon.walkSpeed <= GameConfig.WALK_SPEED, `{id}'s handling never outruns the movement checks`)
	check(table.find(WeaponConfig.order, id) ~= nil, `{id} is in the shop order`)
	if weapon.unlock == "shop" then
		local unlock = ProgressionConfig.unlocks[weapon.level]
		check(weapon.price > 0 and unlock and unlock.kind == "weapon" and unlock.id == id, `{id} goes on sale at its unlock level, for a price`)
	end
	if weapon.projectile == "lob" then
		check(weapon.lobSpeed and weapon.lobGravity and weapon.splashRadius and weapon.cloudRadius and weapon.cloudGas and weapon.cloudSeconds and weapon.cloudTickSeconds, `{id} has its lob, splash and cloud`)
	end
end
check(WeaponConfig.weapons.GasBlaster.gasPerHit == 20 and WeaponConfig.weapons.GasBlaster.headshotGas == 25, "20% a body hit, 25% to the head")
check(GameConfig.SPAWN_PROTECTION_SECONDS == 3, "3 seconds of spawn protection")
local GAS = GameConfig.GAS
check(table.concat(GAS.STAGES, ",") == "25,50,75,100", "four stages before the explosion at 100%")
check(GAS.RECOVERY_DELAY_SECONDS == 5 and GAS.RECOVERY_PER_SECOND == 5, "recovery: 5 seconds, then 5% a second")
check(GameConfig.STREAK.ALPHA_AT == 5 and GameConfig.STREAK.ALPHA_TEXT == "BRO IS THE ALPHA FART!", "the five-kill call, exactly")
local AbilityConfig = require(shared.Config.AbilityConfig)
for id, ability in AbilityConfig do
	check(ability.id == id and typeof(ability.input) == "EnumItem" and ability.durationSeconds > 0 and ability.cooldownSeconds > 0, `{id} has input, duration and cooldown`)
	check(#ability.allowedStates > 0 and #ability.effects > 0 and ability.ownership ~= nil, `{id} has states, effects and ownership`)
	if ability.ownership == "unlock" then
		local unlock = ability.level and ProgressionConfig.unlocks[ability.level]
		check(unlock and unlock.kind == "ability" and unlock.id == id, `{id} unlocks at its level`)
		check(ability.input == Enum.KeyCode.Q, `{id} is a Q ability (one at a time)`)
	end
end
local AudioConfig = require(shared.Config.AudioConfig)
for _, key in { "blaster", "hit", "explosion", "dash", "alpha", "coins", "levelUp", "splat", "vent", "pulse", "purchase" } do
	check(type(AudioConfig[key]) == "string", `a sound slot for {key}`)
end
for id, weapon in WeaponConfig.weapons do
	check(type(AudioConfig[weapon.fireSound]) == "string", `a sound slot for the {id}`)
end

local GameModeBase = require(shared.Interfaces.GameModeBase)
local MapBase = require(shared.Interfaces.MapBase)
local MapConfig = require(shared.Config.MapConfig)
local modes = game.ServerScriptService.Server.Modes
local mode = require(modes:FindFirstChild(GameConfig.DEFAULT_MODE))
check(mode.id == GameConfig.DEFAULT_MODE and type(mode.computeResult) == "function", "the default mode keeps the contract")
check(GameModeBase.mostPointsWins({ Stinkers = 1, Sharters = 0 }, { "Stinkers", "Sharters" }).winner == "Stinkers", "and the base works")
check(MapConfig[GameConfig.DEFAULT_MAP], "the default map has a MapConfig entry")
for id, entry in MapConfig do
	check(entry.id == id, `{id}'s entry names itself`)
	local template = ServerStorage.Maps:FindFirstChild(entry.template)
	check(template, `{id} has a template in ServerStorage.Maps`)
	if template and template:IsA("ModuleScript") then
		check(MapBase.isDefinition(require(template)), `{id}'s module returns a MapDefinition`)
	end
	for _, modeId in entry.modes do
		check(modes:FindFirstChild(modeId), `{id} supports {modeId}, which exists`)
	end
	check(entry.bounds.size.X == 160 and entry.bounds.size.Z == 160, `{id} is 160 x 160`)
end

local TeamConfig = require(shared.Config.TeamConfig)
check(#TeamConfig.order == 2, "two teams")
local green, yellow = TeamConfig.teams.Stinkers, TeamConfig.teams.Sharters
check(green.name == "Skibidi Stinkers" and yellow.name == "Sigma Sharters", "the team names")
check(green.color.G > 0.9 and green.color.R < 0.5, "Stinkers are toxic green")
check(yellow.color.R > 0.9 and yellow.color.G > 0.8 and yellow.color.B < 0.3, "Sharters are bright yellow")

return { status = "PASS", checks = checks, modules = loaded }
