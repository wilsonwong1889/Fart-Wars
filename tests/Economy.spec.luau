-- Coins, XP and levels (masterplan 3.1, 3.2, 3.4, 3.5), with one client:
--   * an elimination pays the killer 10 coins and 20 XP, an assist 5 and
--     10, a chain or barrel kill 5 more, the 5-kill streak 50 and 100;
--     each once, however often the death is reported or the grant retried
--   * grants outside the limits are refused; too many combat coins in a
--     minute get the player logged
--   * XP fills levels on the curve; each unlock lands (ability at 10,
--     cosmetic at 20); level 50 pays the cap reward and badge, then every
--     5,000 XP pays again; the level never passes 50; lifetime XP counts
--     everything
--   * stats: eliminations, deaths, best streak, playtime; weapon mastery
--     pays each milestone once
--   * participation pays at 5 and 10 minutes of ACTIVE play, once; menu
--     spectating and AFK time earn nothing
--   * a reward granted before the profile loads isn't lost
--   * the client shows coins, level, the XP bar, the next goal, reward
--     lines (a few at most), the level-up banner and the saving state
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
local Data = require(server.Services.DataService)
local Economy = require(server.Services.EconomyService)
local Gas = require(server.Services.GasService)
local Eliminations = require(server.Services.EliminationService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Telemetry = require(server.Telemetry)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local Remotes = ReplicatedStorage.Remotes

local saved: { [string]: any } = {}
local latency = 0
local function copy(value: any): any
	return if value == nil then nil else HttpService:JSONDecode(HttpService:JSONEncode(value))
end
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		if latency > 0 then
			task.wait(latency)
		end
		local result = transform(copy(saved[key]))
		if result ~= nil then
			saved[key] = copy(result)
		end
		return result
	end,
})
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end

-- What the server told the client.
local events = {}
Remotes.ProgressEvent.FiredToClient:Connect(function(player, event)
	if player.Name == "Me" then
		table.insert(events, event)
	end
end)
local function eventsOf(kind: string, reason: string?): { any }
	local found = {}
	for _, event in events do
		if event.kind == kind and (reason == nil or event.reason == reason) then
			table.insert(found, event)
		end
	end
	return found
end

-- The client.
local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
latency = 1
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Progress = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.ProgressController)
local ui = Progress.parts
Lifecycle.requestPlay(me, nil)
task.wait(0.1)
check(ui.panel.Visible and ui.status.Visible and ui.status.Text == "Loading progress...", "while the profile loads, the panel says so")
task.wait(1.5)
latency = 0
check(Data.isLoaded(me) and not ui.status.Visible, "loaded: no status line")
check(ui.level.Text == "LV 1" and ui.coins.Text == "0 coins" and ui.xpText.Text == "0 / 100 XP", "level 1, no coins, 100 XP to go")
check(ui.goal.Text == "Level 5: Spritzer in the shop", "the next goal")
local function data(player: Player): any
	return assert(Data.get(player)).data
end

local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = 900 + nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local function fidget()
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:PivotTo(p.Character:GetPivot() * CFrame.new(7, 0, 0))
		end
	end
end
local function settle()
	task.wait(3.2)
	fidget()
	task.wait(3.1)
end
local function shoot(killer: Player, victim: Player, amount: number)
	Gas.add(victim, amount, { attacker = killer, cause = "shot", weapon = "GasBlaster" })
end

local a, b, c = join("Ace"), join("Bea"), join("Cal")
local mine = me:GetAttribute("TeamId")
local foe, mate
for _, p in { a, b, c } do
	if p:GetAttribute("TeamId") ~= mine then
		foe = foe or p
	else
		mate = mate or p
	end
end
assert(foe and mate, "an enemy and a teammate")
settle()

-- An elimination.
shoot(me, foe, 100)
task.wait(1.05)
check(data(me).Coins == 10 and data(me).XP == 20 and data(me).LifetimeXP == 20, "10 coins and 20 XP for the elimination")
check(data(me).TotalEliminations == 1 and data(foe).TotalDeaths == 1, "the kill and the death are counted")
check(data(me).WeaponMastery.GasBlaster.Eliminations == 1, "a Gas Blaster mastery elimination")
local ledger = data(me).Ledger
check(ledger[#ledger].reason == "elimination" and string.find(ledger[#ledger].id, "studio:elimination:", 1, true), "in the ledger with its event ID")
check(me:GetAttribute("Coins") == 10 and me:GetAttribute("XP") == 20 and me:GetAttribute("XPToNext") == 100, "the HUD attributes")
task.wait(0.1)
check(ui.coins.Text == "10 coins" and ui.xpText.Text == "20 / 100 XP", "the panel updates")
local line = ui.lines:FindFirstChild("Line")
check(line and line.Text == "+10 coins  +20 XP  Elimination", "a reward line: " .. tostring(line and line.Text))
settle()
check(ui.lines:FindFirstChild("Line") == nil, "it goes after a moment")

-- An assist.
shoot(mate, foe, 20)
task.wait(0.2)
shoot(me, foe, 80)
task.wait(1.05)
check(data(mate).Coins == 5 and data(mate).XP == 10, "5 coins and 10 XP for the assist")
check(data(me).Coins == 20, "the killer gets the elimination")

-- Repeats pay nothing.
local deadBody = foe.Character
check(Eliminations.eliminate(foe, deadBody, { killer = me, cause = "shot" }) == nil, "the same death twice isn't a second elimination")
check(not Economy.grant(me, eventsOf("grant", "elimination")[2].id, "elimination", 10, 20), "replaying a grant ID is refused")
check(data(me).Coins == 20 and counter("Economy.duplicates") == 1, "nothing extra, and it's counted")
settle()

-- A barrel kill.
Eliminations.eliminate(foe, foe.Character, { killer = me, cause = "barrel" })
task.wait(0.1)
check(data(me).Coins == 35, "a barrel kill: 10 plus a 5-coin chain bonus")
check(data(me).WeaponMastery.GasBlaster.Eliminations == 2, "not a Gas Blaster kill")
settle()

-- Limits.
check(not Economy.grant(me, "huge", "test", ProgressionConfig.MAX_COINS_PER_GRANT + 1, 0), "too many coins at once: refused")
check(not Economy.grant(me, "negative", "test", -5, 0), "negative: refused")
check(not Economy.grant(me, "fraction", "test", 0, 2.5), "fractions: refused")
check(not Economy.grant(me, "nan", "test", 0 / 0, 0), "not a number: refused")
check(data(me).Coins == 35 and counter("Economy.refused") == 4, "nothing paid, all counted")

-- The streak: two more kills make five.
for _ = 1, 2 do
	shoot(me, foe, 100)
	task.wait(1.05)
	settle()
end
check(Eliminations.streakOf(me) == 5, "five in a row")
check(#eventsOf("grant", "alpha") == 1 and eventsOf("grant", "alpha")[1].coins == 50, "the alpha bonus, once")
check(data(me).Coins == 35 + 20 + 50, "105 coins")
check(data(me).Level == 2 and data(me).XP == 100 and data(me).LifetimeXP == 200, "200 XP: level 2 with 100 toward 3")
check(#eventsOf("levelUp") == 1 and eventsOf("levelUp")[1].level == 2, "a level-up event")
check(data(me).BestStreak == 5 and data(me).TotalEliminations == 5, "best streak and total saved")
shoot(me, foe, 100)
task.wait(1.05)
settle()
check(#eventsOf("grant", "alpha") == 1, "the sixth doesn't pay the bonus again")

-- Levels by XP (through test grants, the same path).
local granted = data(me).LifetimeXP
local function giveXP(amount: number)
	while amount > 0 do
		local step = math.min(amount, ProgressionConfig.MAX_XP_PER_GRANT)
		assert(Economy.testGrant(me, 0, step))
		granted += step
		amount -= step
	end
end
local function xpTo(level: number): number
	local need = -data(me).XP
	for l = data(me).Level, level - 1 do
		need += ProgressionConfig.xpToNext(l)
	end
	return need
end
giveXP(xpTo(5) - 1)
check(data(me).Level == 4, "one XP short of level 5")
task.wait(0.1)
check(ui.banner.Visible and ui.bannerTitle.Text == "LEVEL 4!", "the banner shows the level reached")
giveXP(1)
task.wait(0.1)
check(data(me).Level == 5 and ui.bannerDetail.Text == "Unlocked: Spritzer in the shop", "level 5: the Spritzer goes on sale")
check(ui.goal.Text == "Level 10: Recovery Burst (Q)", "the next goal moves on")
giveXP(xpTo(10))
check(data(me).Level == 10 and table.find(data(me).UnlockedAbilities, "RecoveryBurst"), "level 10: Recovery Burst unlocked")
giveXP(xpTo(20))
check(table.find(data(me).OwnedCosmetics, "GoldenGas"), "level 20: Golden Gas tracers")
task.wait(0.1)
local lines = 0
for _, child in ui.lines:GetChildren() do
	if child:IsA("TextLabel") then
		lines += 1
	end
end
check(lines <= 4, "however many rewards at once, at most four lines")

local coins = data(me).Coins
giveXP(xpTo(50))
check(data(me).Level == 50 and table.find(data(me).Badges, "Alpha Farter"), "level 50 and the Alpha Farter badge")
check(data(me).Coins == coins + ProgressionConfig.CAP_REWARD.coins, "the 1,000-coin cap reward")
check(me:GetAttribute("XPToNext") == ProgressionConfig.CAP_REPEAT_XP, "the bar now counts to the next repeat reward")
task.wait(0.1)
check(ui.goal.Text == "Every 5,000 XP: 250 coins", "and the goal says so")
giveXP(ProgressionConfig.CAP_REPEAT_XP + 10)
check(data(me).Level == 50 and data(me).CapRewards == 1 and data(me).XP == 10, "past 50: the level stays, a repeat reward")
check(data(me).Coins == coins + 1000 + 250, "250 coins for it")
check(data(me).LifetimeXP == granted, "lifetime XP counts every point")
check(#data(me).Ledger == ProgressionConfig.LEDGER_SIZE, "the ledger keeps the latest transactions")
local reached = 0
for _, event in eventsOf("levelUp") do
	if not event.repeated then
		reached += 1
	end
end
check(reached == 49, "one level-up event for each level, 2 to 50")

-- Mastery.
settle()
Data.update(me, function(d)
	d.WeaponMastery.GasBlaster.Eliminations = 24
end)
coins = data(me).Coins
shoot(me, foe, 100)
task.wait(1.05)
check(table.find(data(me).WeaponMastery.GasBlaster.Claimed, 25) and table.find(data(me).Badges, "Gas Blaster Bronze"), "25 Gas Blaster eliminations: Bronze")
check(data(me).Coins == coins + 10 + 100, "and 100 coins")
check(#eventsOf("mastery") == 1, "the client hears about it")
settle()
Data.update(me, function(d)
	d.WeaponMastery.GasBlaster.Eliminations = 24
end)
coins = data(me).Coins
shoot(me, foe, 100)
task.wait(1.05)
check(data(me).Coins == coins + 10 and #eventsOf("mastery") == 1, "a milestone already claimed never pays twice")
settle()

-- A reward before the profile loads.
latency = 2
local lou = join("Lou")
check(not Data.isLoaded(lou) and Economy.testGrant(lou, 7, 0), "Lou earns before his profile is in")
task.wait(2.5)
latency = 0
check(Data.isLoaded(lou) and data(lou).Coins == 7, "it's there once it loads")

-- Anomalous combat earnings.
for i = 1, 4 do
	Economy.grant(lou, `burst:{i}`, "elimination", 100, 0)
end
check(counter("Economy.anomalous") == 1, "400 combat coins in a minute: logged once")

-- The test command splits big amounts into grants within the limit.
local TestControls = require(server.TestControls)
local before = data(lou).Coins
check(TestControls.coins(lou, 5000) and data(lou).Coins == before + 5000, "/fw coins 5000 pays all 5000")

-- Participation: active time only.
local zed = Instance.new("Player")
zed.Name = "Zed"
zed.UserId = 990
zed.Parent = Players
task.wait(0.1)
local pat = join("Pat")
local patStart = data(pat).Coins
for _ = 1, 11 do
	task.wait(30)
	fidget()
end
check(#(function()
	local found = {}
	for _, entry in data(pat).Ledger do
		if entry.reason == "participation" then
			table.insert(found, entry)
		end
	end
	return found
end)() == 1, "five minutes playing: participation pays")
check(data(pat).Coins == patStart + 25 and data(pat).XP == 50, "25 coins and 50 XP")
check(Economy.activeSecondsOf(zed) == 0 and data(zed).Coins == 0, "five minutes on the home screen: nothing")
for _ = 1, 10 do
	task.wait(30)
	fidget()
end
check(data(pat).Coins == patStart + 25 + 75, "ten minutes: 75 more")
for _ = 1, 4 do
	task.wait(30)
	fidget()
end
check(data(pat).Coins == patStart + 100, "and that's all for the session")
check(counter("session.reached10Minutes") >= 1 and counter("session.reached5Minutes") >= counter("session.reached10Minutes"), "sessions reaching 5 and 10 minutes are counted")
-- AFK time doesn't count.
local before = Economy.activeSecondsOf(pat)
task.wait(150)
check(pat:GetAttribute("State") == "AFK_SPECTATOR", "Pat dozes off")
check(Economy.activeSecondsOf(pat) - before < 75, "only the time before going AFK counted")

-- Playtime and the final save.
local playtime = Economy.activeSecondsOf(me)
me.Parent = nil
task.wait(0.2)
local stored = saved.player_1
check(stored and stored.Level == 50 and stored.Lock == nil, "Me's progress is saved on leaving")
check(math.abs(stored.TotalPlaytime - playtime) < 2, "with the active playtime")
check(Telemetry.snapshot().samples.coinsPer10Minutes ~= nil, "coins per 10 minutes is measured")
check(counter("Economy.coins.elimination") > 0 and counter("Economy.xp.alpha") == 100, "coins and XP by source")

-- The saving state, on the client.
me.Parent = Players
me:SetAttribute("DataStatus", "unsaved")
task.wait(0.1)
check(ui.status.Visible and ui.status.Text == "Progress isn't saving this session", "a session that won't save says so")

return { status = "PASS", checks = checks }
