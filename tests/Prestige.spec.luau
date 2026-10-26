-- Prestige (masterplan 6.2), with one client:
--   * off as shipped: refused, and nothing in the Progression tab
--   * on: refused below level 50, in a match, or unsaved; the preview's
--     exact numbers (level, XP, coins kept, weapons) and what stays
--   * nothing resets without the preview's token, a stale one, or a replay
--   * the reset: level 1, XP 0, coins down to unspent store coins, back
--     to the Gas Blaster; cosmetics, lifetime XP, stats, badges, mastery,
--     abilities and passes kept; the rank's badge and cosmetic; saved
--     before it's confirmed (a failed save changes nothing)
--   * the rank shows (level bar, scoreboard) and climbing again works
--   * the screen: the preview, two presses, the answer
--   * no power: weapons fire the same at any rank
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
local Shared = ReplicatedStorage.Shared
local FeatureFlags = require(Shared.Config.FeatureFlags)
local PrestigeConfig = require(Shared.Config.PrestigeConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local Data = require(server.Services.DataService)
local Prestige = require(server.Services.PrestigeService)
local Economy = require(server.Services.EconomyService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Combat = require(server.Services.CombatService)
local Metrics = require(server.Services.MetricsService)
local Telemetry = require(server.Telemetry)

local failNext = 0
local saved = {
	player_1 = HttpService:JSONEncode({
		Sessions = 30,
		Level = 50,
		XP = 1234,
		LifetimeXP = 250000,
		Coins = 3450,
		PurchasedCoins = 500,
		OwnedWeapons = { "GasBlaster", "Spritzer", "Thunderclapper" },
		EquippedWeapon = "Thunderclapper",
		UnlockedAbilities = { "RecoveryBurst", "GasPulse" },
		OwnedCosmetics = { "GoldenGas", "RainbowRot", "StarterSwirl" },
		EquippedCosmetic = "GoldenGas",
		Badges = { "AlphaFarter" },
		PassesGranted = { "StarterPack" },
		TotalEliminations = 1500,
		WeaponMastery = { Spritzer = { Eliminations = 120, Claimed = { 25, 100 } } },
	}),
}
Data.setStore({
	UpdateAsync = function(_, key, transform)
		if failNext > 0 then
			failNext -= 1
			error("503: DataStore request failed (test outage)")
		end
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})
local function data(): any
	return assert(Data.get(Players:GetPlayerByUserId(1))).data
end

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Controllers = game.StarterPlayer.StarterPlayerScripts.Client.Controllers
local Locker = require(Controllers.LockerController)
local Screen = require(Controllers.PrestigeController)
local Progress = require(Controllers.ProgressController)
task.wait(0.5)

-- Off as shipped.
check(FeatureFlags.PRESTIGE == false and PrestigeConfig.POWER_BONUS == 0, "off as shipped, and no power bonus")
check(Prestige.request(me, "preview").reason == "off", "refused while off")
Locker.open("Progression")
task.wait(0.1)
check(not Locker.parts.content.Track:FindFirstChild("Prestige"), "nothing in the Progression tab")
Locker.close()

-- On.
Prestige.testEnable(true)
check(workspace:GetAttribute("PrestigeOpen") == true, "the server tells clients")
Lifecycle.requestPlay(me, nil)
task.wait(0.3)
task.wait(0.6)
check(Prestige.request(me, "preview").reason == "inMatch", "not in the middle of a match")
ReplicatedStorage.Remotes.RequestSpectate.OnServerEvent:Fire(me)
task.wait(0.6)
local answer = Prestige.request(me, "preview")
check(answer.ok and type(answer.token) == "string", "the preview, with a confirmation token")
local preview = answer.preview
check(preview.rank == 1 and preview.resets.level == 50 and preview.resets.xp == 1234 and preview.resets.coins == 3450, "exact numbers: level, XP, coins")
check(preview.resets.keptCoins == 500, "coins bought in the store and not spent are kept")
check(table.concat(preview.resets.weapons, ",") == "Spritzer,Thunderclapper", "the weapons that go")
check(preview.keeps.cosmetics == 3 and preview.keeps.lifetimeXP == 250000 and preview.keeps.eliminations == 1500 and preview.keeps.passes == 1, "and what stays")
check(preview.rewards.badge == "Prestige1" and preview.rewards.cosmetic == "PrestigeFlame", "what rank 1 gives")

-- Tokens.
task.wait(0.6)
check(Prestige.request(me, "confirm", "made-up").reason == "badToken" and data().Level == 50, "a made-up token changes nothing")
task.wait(0.6)
check(Prestige.request(me, "confirm", answer.token).reason == "badToken", "and uses up the real one")
task.wait(0.6)
local fresh = Prestige.request(me, "preview")
Prestige.testExpire(me)
task.wait(0.6)
check(Prestige.request(me, "confirm", fresh.token).reason == "badToken" and data().Level == 50, "an expired token changes nothing")

-- A save that fails changes nothing.
task.wait(0.6)
local again = Prestige.request(me, "preview")
failNext = 3
task.wait(0.6)
local failed = Prestige.request(me, "confirm", again.token)
check(failed.reason == "saveFailed" and data().Level == 50 and data().Coins == 3450 and data().Prestige == 0, "a failed save: all put back")
check(table.find(data().OwnedWeapons, "Thunderclapper") and data().EquippedWeapon == "Thunderclapper", "weapons too")

-- The screen.
failNext = 0
task.wait(0.6)
Screen.open()
check(Screen.parts.screen.Enabled and Screen.preview and Screen.parts.title.Text == "PRESTIGE 1", "the Prestige screen")
local body = {}
for _, child in Screen.parts.body:GetChildren() do
	if child:IsA("TextLabel") then
		body[child.LayoutOrder] = child.Text
	end
end
check(string.find(body[1], "Level 50 → 1", 1, true) and string.find(body[1], "3,450 → 500", 1, true), "it shows the exact numbers")
check(string.find(body[2], "Spritzer, Thunderclapper", 1, true) and string.find(body[4], "No extra power", 1, true), "the weapons, and that it's for show")
check(Screen.press() == nil and Screen.stage == 1 and string.find(Screen.parts.confirm.Text, "CAN'T BE UNDONE", 1, true), "one press asks again")
check(data().Level == 50, "nothing yet")
task.wait(0.6)
local done = Screen.press()
check(done and done.ok and done.rank == 1, "the second press prestiges")

-- What changed and what stayed.
local d = data()
check(d.Level == 1 and d.XP == 0 and d.Prestige == 1 and d.Coins == 500, "level 1, no XP, the bought coins kept")
check(#d.OwnedWeapons == 1 and d.OwnedWeapons[1] == "GasBlaster" and d.EquippedWeapon == "GasBlaster", "back to the Gas Blaster")
check(me:GetAttribute("Weapon") == "GasBlaster", "in hand too")
check(d.LifetimeXP == 250000 and d.TotalEliminations == 1500 and d.WeaponMastery.Spritzer.Eliminations == 120, "lifetime XP, stats and mastery stay")
check(table.find(d.UnlockedAbilities, "GasPulse") and table.find(d.PassesGranted, "StarterPack"), "abilities and passes stay")
check(table.find(d.OwnedCosmetics, "GoldenGas") and table.find(d.OwnedCosmetics, "PrestigeFlame"), "cosmetics stay, plus the Prestige Flame")
check(table.find(d.Badges, "AlphaFarter") and table.find(d.Badges, "Prestige1"), "badges stay, plus Prestige 1")
check(string.find(saved.player_1, '"Prestige":1', 1, true), "saved before it was confirmed")
check(me:GetAttribute("Prestige") == 1 and me:GetAttribute("Level") == 1, "published")
check(Progress.parts.level.Text == "P1 · LV 1", "the level bar shows the rank")
check(Metrics.levelBand(me) == "prestige", "and the metrics put them in the prestige band")
check((Telemetry.snapshot().counters["Prestige.count"] or 0) == 1, "counted")
task.wait(0.6)
check(Prestige.request(me, "preview").reason == "level", "not again until level 50")

-- Climbing again: a Spritzer costs coins again, store coins aren't counted twice.
Data.update(me, function(x)
	x.Level = 50
	x.Coins = 800
end)
task.wait(0.6)
local second = Prestige.request(me, "preview")
check(second.ok and second.preview.rank == 2 and second.preview.resets.keptCoins == 0, "rank 2 next; coins kept last time aren't kept twice")
Economy.grantPurchase(me, "receipt:p2", 300)
task.wait(0.6)
check(Prestige.request(me, "preview").preview.resets.keptCoins == 300, "newly bought coins are kept")

-- No power: the same weapon numbers at any rank.
check(Combat.weaponOf(me).gasPerHit == WeaponConfig.weapons.GasBlaster.gasPerHit, "the Gas Blaster is the same Gas Blaster")

-- A temporary profile can't.
assert(Data.get(me)).temporary = true
task.wait(0.6)
check(Prestige.request(me, "preview").reason == "notSaving", "an unsaved session can't prestige")
assert(Data.get(me)).temporary = false
task.wait(0.6)
check(Prestige.request(me, 7).reason == "badPayload", "junk refused")
Prestige.testEnable(nil)

return { status = "PASS", checks = checks }
