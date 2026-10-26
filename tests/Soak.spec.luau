-- A full server, for a long time, with everything on (masterplan 2.5's
-- load test, as far as a stand-in can go: no frame rates, but every
-- system under churn). 19 simulated players and one real client play
-- for 20 virtual minutes: moving, shooting whoever they can see with
-- whatever they've equipped, dashing, using Q, buying and equipping,
-- spectating and coming back, going AFK, and leaving and rejoining.
-- Every few seconds, and at the end:
--   * nothing errors, anywhere (any background error fails the spec)
--   * teams never pass 10, only ACTIVE players have avatars, team counts
--     match the Roblox teams
--   * gas stays 0-100; coins never go negative; levels stay 1-50; nobody
--     owns a weapon that doesn't exist or holds one they don't own
--   * rounds keep turning over; blasts and clouds drain
--   * when everyone has left, every profile is saved with its lock let go
--     and no departed player is still held in memory
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
local function run(scriptInstance: Instance)
	local fn = assert(loadstring(scriptInstance.Source, scriptInstance.Name))
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv() }))
	fn()
end
run(server.Bootstrap)
local Services = server.Services
local Data = require(Services.DataService)
local Economy = require(Services.EconomyService)
local Gas = require(Services.GasService)
local Lifecycle = require(Services.PlayerLifecycleService)
local Teams = require(Services.TeamService)
local Rounds = require(Services.RoundService)
local Explosions = require(Services.ExplosionService)
local Projectiles = require(Services.ProjectileService)
local Combat = require(Services.CombatService)
local Telemetry = require(server.Telemetry)
local Health = require(server.Health)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local Remotes = ReplicatedStorage.Remotes

local saved: { [string]: string } = {}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})

local rng = Random.new(20261026)
local everyone = setmetatable({}, { __mode = "k" }) -- every Player ever, weakly

-- The real client.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
everyone[me] = true
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
Lifecycle.requestPlay(me, nil)

type Bot = { player: Player, shotId: number, lastShot: number, lazy: boolean, back: number? }
local bots: { [Player]: Bot } = {}
local nextId = 0
local function join(): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = `Bot{nextId}`
	player.DisplayName = player.Name
	player.UserId = 1000 + nextId
	player.Parent = Players
	everyone[player] = true
	-- Some come back with progress to spend; a few are veterans.
	local roll = rng:NextNumber()
	if Data.isLoaded(player) and roll < 0.6 then
		local grants = if roll < 0.25 then 16 else 2
		for _ = 1, grants do
			Economy.testGrant(player, rng:NextInteger(0, 1000), rng:NextInteger(1000, 2000))
		end
	end
	bots[player] = { player = player, shotId = 0, lastShot = -math.huge, lazy = rng:NextNumber() < 0.1 }
	task.wait(0.05)
	Remotes.RequestPlay.OnServerEvent:Fire(player, nil)
	return player
end
for _ = 1, 19 do
	join()
end

local LANES = { -53, 0, 53 }
local function wander(player: Player)
	local character = player.Character
	if character then
		local x = LANES[rng:NextInteger(1, 3)] + rng:NextNumber(-6, 6)
		character:PivotTo(CFrame.new(x, 3, rng:NextNumber(-45, 45)))
	end
end
local function alive(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end
local function nearestEnemy(player: Player): Player?
	local team = player:GetAttribute("TeamId")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (team and root) then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, other in Players:GetPlayers() do
		local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if other:GetAttribute("TeamId") and other:GetAttribute("TeamId") ~= team and otherRoot and alive(other) then
			local distance = (otherRoot.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local SHOP = { "Spritzer", "Thunderclapper", "StinkLobber" }
local function act(bot: Bot)
	local player = bot.player
	local state = player:GetAttribute("State")
	if state ~= "ACTIVE" then
		if bot.back and workspace:GetServerTimeNow() >= bot.back then
			bot.back = nil
			Remotes.RequestPlay.OnServerEvent:Fire(player, nil)
		elseif not bot.back then
			bot.back = workspace:GetServerTimeNow() + rng:NextNumber(2, 20)
		end
		return
	end
	if not bot.lazy and rng:NextNumber() < 0.5 then
		wander(player)
	end
	local now = workspace:GetServerTimeNow()
	local weapon = Combat.weaponOf(player)
	local enemy = nearestEnemy(player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if enemy and head and alive(player) and now - bot.lastShot >= weapon.fireInterval then
		local target = enemy.Character.HumanoidRootPart.Position + Vector3.new(0, if weapon.projectile == "lob" then 6 else 0, 0)
		bot.shotId += 1
		bot.lastShot = now
		Remotes.FireWeapon.OnServerEvent:Fire(player, (target - head.Position).Unit, bot.shotId)
	end
	local roll = rng:NextNumber()
	if roll < 0.04 then
		Remotes.FartDash.OnServerEvent:Fire(player, Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)))
	elseif roll < 0.07 then
		Remotes.UseAbility.OnServerEvent:Fire(player)
	elseif roll < 0.09 then
		task.spawn(Remotes.ShopRequest.OnServerInvoke, player, "buy", "weapon", SHOP[rng:NextInteger(1, 3)])
	elseif roll < 0.11 then
		local kind = ({ "weapon", "ability", "cosmetic" })[rng:NextInteger(1, 3)]
		local id = ({ weapon = SHOP[rng:NextInteger(1, 3)], ability = ({ "RecoveryBurst", "GasPulse" })[rng:NextInteger(1, 2)], cosmetic = "GoldenGas" })[kind]
		task.spawn(Remotes.ShopRequest.OnServerInvoke, player, "equip", kind, id)
	elseif roll < 0.115 then
		Remotes.RequestSpectate.OnServerEvent:Fire(player)
	elseif roll < 0.117 then
		-- Junk, as an exploiter would send it.
		Remotes.FireWeapon.OnServerEvent:Fire(player, Vector3.new(0 / 0, 1, 0), "x")
		task.spawn(Remotes.ShopRequest.OnServerInvoke, player, { "buy" }, 7, nil)
		task.spawn(Remotes.ReportPlayer.OnServerInvoke, player, "everyone", { 1 })
		Remotes.ClientReport.OnServerEvent:Fire(player, { fps = "fast", ping = 0 / 0 })
	elseif roll < 0.118 then
		-- Honest client reports, and the odd honest player report.
		Remotes.ClientReport.OnServerEvent:Fire(player, { fps = rng:NextInteger(40, 144), ping = rng:NextNumber(0.02, 0.2), errors = 0 })
		local others = Players:GetPlayers()
		local other = others[rng:NextInteger(1, #others)]
		task.spawn(Remotes.ReportPlayer.OnServerInvoke, player, other.UserId, "Other")
	end
end

local function invariants(label: string)
	local counts = Teams.counts()
	for team, n in counts do
		check(n <= 10, `{label}: {team} has {n} active players`)
	end
	for _, player in Players:GetPlayers() do
		local state = player:GetAttribute("State")
		local character = player.Character
		if character and state ~= "ACTIVE" then
			-- A spawn can finish a moment after a move off the team; look again.
			task.wait(0.5)
			check(player.Character == nil or player:GetAttribute("State") == "ACTIVE", `{label}: {player.Name} ({state}) has no slot but has an avatar`)
		end
		local gas = Gas.gasOf(player)
		check(gas >= 0 and gas <= 100, `{label}: {player.Name}'s gas is {gas}`)
		local profile = Data.get(player)
		if profile then
			local d = profile.data
			check(d.Coins >= 0 and d.Level >= 1 and d.Level <= 50, `{label}: {player.Name} has {d.Coins} coins at level {d.Level}`)
			for _, id in d.OwnedWeapons do
				check(WeaponConfig.weapons[id] ~= nil, `{label}: {player.Name} owns an unknown weapon {id}`)
			end
			local holding = Combat.weaponOf(player).id
			check(table.find(d.OwnedWeapons, holding) ~= nil, `{label}: {player.Name} holds a {holding} they don't own`)
		end
	end
	local active = 0
	for _, n in counts do
		active += n
	end
	check(active == Teams.activeCount(), `{label}: team counts add up`)
end

-- Play.
local MINUTES = 20
local roundsSeen, lastRound = 0, nil
for second = 1, MINUTES * 60 do
	for _, bot in bots do
		act(bot)
	end
	task.wait(0.5)
	for _, bot in bots do
		if not bot.lazy and rng:NextNumber() < 0.5 then
			wander(bot.player)
		end
	end
	if me.Character then
		wander(me)
	end
	task.wait(0.5)
	local snapshot = Rounds.snapshot()
	if snapshot.roundId ~= lastRound then
		lastRound = snapshot.roundId
		roundsSeen += 1
	end
	if second % 30 == 0 then
		-- Churn: someone leaves, someone new arrives.
		local leaving = nil
		for player in bots do
			if rng:NextNumber() < 0.2 then
				leaving = player
				break
			end
		end
		if leaving then
			bots[leaving] = nil
			leaving.Parent = nil
			join()
		end
	end
	if second % 15 == 0 then
		invariants(`after {second} s`)
	end
end

local snapshot = Telemetry.snapshot()
local counters = snapshot.counters
local errors = 0
for _, n in snapshot.errors do
	errors += n
end
check(errors == 0, `no errors in any service ({HttpService:JSONEncode(snapshot.errors)})`)
check((counters["Elimination.elimination"] or 0) > 50, `plenty of eliminations: {counters["Elimination.elimination"] or 0}`)
check((counters["Shop.purchases"] or 0) > 0, `purchases happened: {counters["Shop.purchases"] or 0}`)
check((counters["Ability.RecoveryBurst"] or 0) + (counters["Ability.GasPulse"] or 0) > 0, "abilities were used")
check((counters["Projectile.landed"] or 0) > 0, "stink bombs landed")
check(roundsSeen >= 3, `rounds kept turning over: {roundsSeen}`)
check(snapshot.rejects.FireWeapon and snapshot.rejects.FireWeapon.badPayload, "junk was refused")
check(snapshot.rejects.ReportPlayer and snapshot.rejects.ReportPlayer.badPayload, "junk reports refused")
check((counters["client.reports"] or 0) > 0, "client reports arrived")
local health = Health.check()
check(health.status ~= "FAILING", `the server stayed healthy: {health.status} {table.concat(health.problems, "; ")}`)
for _, name in Health.loopNames() do
	check(not string.find(table.concat(health.problems, ";"), name .. " loop", 1, true), `the {name} loop kept running`)
end

-- Everyone leaves.
for player in bots do
	player.Parent = nil
end
me.Parent = nil
table.clear(bots)
task.wait(30)
check(Explosions.pending() == 0 and Projectiles.cloudCount() == 0, "every blast and cloud has drained")
local unsaved, locked = 0, 0
for _, text in saved do
	local entry = HttpService:JSONDecode(text)
	if entry.Lock ~= nil then
		locked += 1
	end
	if entry.SaveVersion ~= Data.VERSION then
		unsaved += 1
	end
end
check(locked == 0 and unsaved == 0, `every profile saved and released ({locked} still locked)`)
check(#Players:GetPlayers() == 0 and Teams.activeCount() == 0, "the server is empty")
collectgarbage("collect")
collectgarbage("collect")
-- (The client's own player is held by its scripts, as on a real client.)
local held = {}
for player in everyone do
	if player ~= me then
		table.insert(held, player.Name)
	end
end
check(#held == 0, `no departed player is still held in memory: {table.concat(held, ", ")}`)

return {
	status = "PASS",
	checks = checks,
	players = nextId + 1,
	eliminations = counters["Elimination.elimination"],
	purchases = counters["Shop.purchases"],
	rounds = roundsSeen,
}
