-- The shop and loadouts (masterplan 3.3 and 3.5), with one client:
--   * junk requests, unknown or starter weapons, too low a level and too
--     few coins are refused, whatever the client claims
--   * a purchase takes the coins and gives the weapon together, saved
--     before the answer; buying twice is refused; a save that fails puts
--     both back; one request at a time; a profile that isn't saving can't
--     buy; a player who leaves mid-purchase keeps a consistent save
--   * equipping: only what you own; from the home screen it's in hand at
--     once, mid-fight it waits for the respawn (and the HUD says so); the
--     weapon's handling comes with it; abilities and tracers likewise
--   * the locker: tabs, each weapon's stats and button, BUY with its
--     pending state and the answer, EQUIP, the progression track, settings
--     (effects, sound, tips); a tip when a weapon becomes affordable
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
local Shop = require(server.Services.ShopService)
local Combat = require(server.Services.CombatService)
local Abilities = require(server.Services.AbilityService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Telemetry = require(server.Telemetry)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local Remotes = ReplicatedStorage.Remotes

local saved: { [string]: any } = {}
local failNext = 0
local latency = 0
local function copy(value: any): any
	return if value == nil then nil else HttpService:JSONDecode(HttpService:JSONEncode(value))
end
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		if latency > 0 then
			task.wait(latency)
		end
		if failNext > 0 then
			failNext -= 1
			error("503: DataStore request failed (test outage)")
		end
		local result = transform(copy(saved[key]))
		if result ~= nil then
			saved[key] = copy(result)
		end
		return result
	end,
})
local function rejects(remote: string, reason: string): number
	local snapshot = Telemetry.snapshot()
	return snapshot.rejects[remote] and snapshot.rejects[remote][reason] or 0
end

-- The client.
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
local Home = require(Controllers.HomeController)
local function click(button: GuiButton)
	button.Activated:Fire()
	task.wait(0.05)
end
local function data(): any
	return assert(Data.get(me)).data
end
local function request(action: any, kind: any, id: any): any
	task.wait(0.3) -- past the rate limit
	return Shop.request(me, action, kind, id)
end
local function xpTo(level: number)
	local need = -data().XP
	for l = data().Level, level - 1 do
		need += ProgressionConfig.xpToNext(l)
	end
	while need > 0 do
		local step = math.min(need, ProgressionConfig.MAX_XP_PER_GRANT)
		Economy.testGrant(me, 0, step)
		need -= step
	end
end
local function coins(n: number)
	while n > 0 do
		local step = math.min(n, ProgressionConfig.MAX_COINS_PER_GRANT)
		Economy.testGrant(me, step, 0)
		n -= step
	end
end

check(Data.isLoaded(me), "Me's profile is in")
task.wait(0.1)
check(Locker.profile and Locker.profile.ownedWeapons[1] == "GasBlaster" and Locker.profile.saving, "the client has the profile")

-- Refusals.
check(request(5, nil, nil).reason == "badPayload", "junk: refused")
check(request("buy", "weapon", string.rep("x", 100)).reason == "badPayload", "an absurd id: refused")
check(request("steal", "weapon", "Spritzer").reason == "badPayload", "an unknown action: refused")
check(rejects("ShopRequest", "badPayload") == 3, "and counted")
check(request("buy", "weapon", "Nuke").reason == "unknown", "a weapon that doesn't exist isn't for sale")
check(request("buy", "weapon", "GasBlaster").reason == "unknown", "nor is the starter")
check(request("buy", "weapon", "Spritzer").reason == "level", "level 1 can't buy the Spritzer")
xpTo(5)
check(data().Level == 5, "level 5")
check(request("buy", "weapon", "Spritzer").reason == "coins", "no coins, no Spritzer")
check(Shop.request(me, "buy", "weapon", "Spritzer").reason == "rateLimited", "requests spaced under a quarter second: refused")

-- A purchase.
coins(1000)
local answer = request("buy", "weapon", "Spritzer")
check(answer.ok and answer.message == "Bought! It's yours.", "bought: " .. answer.message)
check(data().Coins == 600 and table.find(data().OwnedWeapons, "Spritzer"), "400 coins for the Spritzer")
check(saved.player_1.Coins == 600 and table.find(saved.player_1.OwnedWeapons, "Spritzer"), "already saved when the answer came back")
local ledger = data().Ledger
check(ledger[#ledger].reason == "purchase" and ledger[#ledger].coins == -400, "in the ledger")
check(me:GetAttribute("Coins") == 600, "the HUD's coins")
check((Telemetry.snapshot().counters["Shop.firstPurchases"] or 0) == 1, "a first purchase is counted (the first purchase rate)")
check(request("buy", "weapon", "Spritzer").reason == "owned", "buying it twice: refused")

-- A purchase that can't be saved.
xpTo(15)
coins(1200 - data().Coins)
failNext = 3
answer = request("buy", "weapon", "Thunderclapper")
check(not answer.ok and answer.reason == "saveFailed", "the save fails: so does the purchase")
check(data().Coins == 1200 and not table.find(data().OwnedWeapons, "Thunderclapper"), "coins back, no weapon")
check(not table.find(saved.player_1.OwnedWeapons, "Thunderclapper"), "nothing half-saved")
check(data().Ledger[#data().Ledger].reason == "refund", "the refund is in the ledger")

-- One at a time.
latency = 1
local first
task.spawn(function()
	first = Shop.request(me, "buy", "weapon", "Thunderclapper")
end)
task.wait(0.3)
check(Shop.request(me, "equip", "weapon", "Spritzer").reason == "busy", "a second request while the first saves: busy")
task.wait(1.5)
latency = 0
check(first and first.ok and data().Coins == 0, "the first went through")

-- A profile that isn't saving.
assert(Data.get(me)).temporary = true
check(request("buy", "weapon", "StinkLobber").reason == "notSaving", "a temporary profile can't buy")
assert(Data.get(me)).temporary = false

-- Equipping from the home screen: in hand at once.
check(request("equip", "weapon", "StinkLobber").reason == "notOwned", "can't equip what you don't own")
answer = request("equip", "weapon", "Spritzer")
check(answer.ok and answer.reason == "now" and Combat.weaponOf(me).id == "Spritzer", "on the home screen: equipped at once")
Lifecycle.requestPlay(me, nil)
task.wait(0.2)
check(Combat.weaponOf(me).id == "Spritzer" and me.Character.Humanoid.WalkSpeed == 16, "PLAY with it")
local held = me.Character:FindFirstChild("HeldWeapon")
check(held and held:IsA("Tool") and held:GetAttribute("Weapon") == "Spritzer" and held:FindFirstChild("Handle"), "the Spritzer is in my hands")
for _, part in held:GetDescendants() do
	if part:IsA("BasePart") then
		check(not part.CanQuery and not part.CanCollide and part.Massless, `the gun's {part.Name} can't be hit and weighs nothing`)
	end
end
-- In the first seconds of a spawn (still protected), a swap is immediate.
answer = request("equip", "weapon", "GasBlaster")
check(answer.ok and answer.reason == "now" and Combat.weaponOf(me).id == "GasBlaster", "a fresh spawn can still swap at once")
check(me.Character:FindFirstChild("HeldWeapon"):GetAttribute("Weapon") == "GasBlaster", "the gun in hand follows")
answer = request("equip", "weapon", "Spritzer")
check(answer.reason == "now", "and back")
task.wait(3.2)

-- Mid-fight: on the next respawn.
answer = request("equip", "weapon", "Thunderclapper")
check(answer.ok and answer.reason == "respawn" and answer.message == "Equipped: you'll have it when you respawn.", "mid-fight: next respawn")
check(Combat.weaponOf(me).id == "Spritzer" and me:GetAttribute("LoadoutPending"), "still the Spritzer for now, and the HUD says so")
check(data().EquippedWeapon == "Thunderclapper", "but it's saved")
Gas.testSetGas(me, 100)
task.wait(1.2 + 3.3)
check(Combat.weaponOf(me).id == "Thunderclapper" and me.Character.Humanoid.WalkSpeed == 14, "respawned with the Thunderclapper, and its walk")
check(me:GetAttribute("LoadoutPending") == nil, "nothing pending")
check(me.Character:FindFirstChild("HeldWeapon"):GetAttribute("Weapon") == "Thunderclapper", "the Thunderclapper in my hands")
task.wait(3.2) -- past the spawn's protection
answer = request("equip", "weapon", "Thunderclapper")
check(answer.ok and answer.reason == "now", "equipping what's in hand is simply done")

-- Abilities and tracers.
check(request("equip", "ability", "GasPulse").reason == "notOwned", "a locked ability: refused")
answer = request("equip", "ability", "RecoveryBurst")
check(answer.ok and answer.reason == "respawn" and Abilities.abilityOf(me) == nil, "Recovery Burst (level 10): on the next respawn")
Lifecycle.respawn(me)
task.wait(0.2)
check(Abilities.abilityOf(me) == "RecoveryBurst" and me:GetAttribute("Ability") == "RecoveryBurst", "now it's on Q")
check(request("equip", "cosmetic", "GoldenGas").reason == "notOwned", "Golden Gas needs level 20")
xpTo(20)
answer = request("equip", "cosmetic", "GoldenGas")
check(answer.ok and answer.reason == "now" and me:GetAttribute("Tracer") == "GoldenGas", "a tracer changes nothing in combat: at once")
answer = request("equip", "cosmetic", nil)
check(answer.ok and me:GetAttribute("Tracer") == nil, "and off again")

-- The locker.
Locker.open("Weapons")
task.wait(0.1)
local p = Locker.parts
check(p.screen.Enabled and p.tabs.Weapons and p.tabs.Abilities and p.tabs.Progression and p.tabs.Settings, "the locker with its four tabs")
local spritzer = p.content:FindFirstChild("Spritzer")
check(spritzer and spritzer:FindFirstChild("Action").Text == "EQUIP", "the Spritzer: owned, EQUIP")
check(p.content.Thunderclapper.Action.Text == "EQUIPPED", "the Thunderclapper: EQUIPPED")
local stats = {}
for _, child in spritzer:GetChildren() do
	if child.Name == "Stat" then
		table.insert(stats, child.Text)
	end
end
local statText = table.concat(stats, " | ")
check(string.find(statText, "Gas 7% (head 9%)", 1, true) and string.find(statText, "Range 60", 1, true) and string.find(statText, "Fire rate 10.0/s", 1, true) and string.find(statText, "Handling", 1, true), "its stats: " .. statText)
check(p.content.StinkLobber.Action.Text == "LEVEL 25", "the Stink Lobber: level 25 first")
xpTo(25)
task.wait(0.1)
check(p.content.StinkLobber.Action.Text == "2500 COINS", "level 25, but not the coins")
coins(2500)
task.wait(0.1)
local buy = p.content.StinkLobber.Action
check(buy.Text == "BUY 2500", "now: BUY 2500")
-- A tip says so too (once), between fights.
local Progress = require(Controllers.ProgressController)
local function tipShown(fragment: string): boolean
	for _, child in Progress.parts.lines:GetChildren() do
		if child.Name == "Tip" and string.find(child.Text, fragment, 1, true) then
			return true
		end
	end
	return false
end
task.wait(2.2)
check(tipShown("You can buy the Stink Lobber now"), "a tip: the Stink Lobber is affordable")
latency = 0.5
click(buy)
check(Locker.busy and string.find(p.status.Text, "Buying", 1, true), "while it saves: Buying...")
check(p.content.Spritzer.Action:GetAttribute("Enabled") == false, "and the other buttons wait")
task.wait(1)
latency = 0
check(not Locker.busy and p.status.Text == "Bought! It's yours.", "then the answer")
check(table.find(data().OwnedWeapons, "StinkLobber") and p.content.StinkLobber.Action.Text == "EQUIP", "it's yours: EQUIP")
task.wait(0.3)
click(p.content.StinkLobber.Action)
task.wait(0.1)
check(data().EquippedWeapon == "StinkLobber" and string.find(p.status.Text, "respawn", 1, true), "EQUIP mid-fight: on the next respawn")
click(p.tabs.Abilities)
check(p.content.RecoveryBurst.Action.Text == "EQUIPPED" and p.content.GasPulse.Action.Text == "LEVEL 30", "abilities: equipped and locked")
check(p.content.FartDash.Action.Text == "EVERYONE HAS IT", "Fart Dash is everyone's")
click(p.tabs.Progression)
check(p.content.Track.Level.Text == "LEVEL 25" and p.content.Track.Unlock20.Text:sub(1, 3) == "✓", "progression: the level and the track")
check(string.find(p.content.Stats.Badges.Text, "None yet", 1, true), "no badges yet")
click(p.tabs.Settings)
local Settings = require(game.StarterPlayer.StarterPlayerScripts.Client.Settings)
local Effects = require(Controllers.EffectsController)
click(p.content.ReducedEffectsRow.ReducedEffects)
check(Settings.reducedEffects and Effects.reduced() and p.content.ReducedEffectsRow.ReducedEffects.Text == "REDUCED EFFECTS: ON", "reduced effects on")
click(p.content.ReducedEffectsRow.ReducedEffects)
check(not Settings.reducedEffects, "and off")
click(p.content.SoundRow.Sound)
check(not Settings.sound and p.content.SoundRow.Sound.Text == "SOUND EFFECTS: OFF", "sound effects off")
click(p.content.SoundRow.Sound)
click(p.content.TipsRow.Tips)
check(not Settings.tips and p.content.TipsRow.Tips.Text == "TIPS: OFF", "tips off")
click(p.content.TipsRow.Tips)
click(p.content.LowDetailRow.LowDetail)
check(Settings.lowDetail and Effects.reduced() and game:GetService("Lighting").GlobalShadows == false, "low detail: no shadows, fewer effects")
click(p.content.LowDetailRow.LowDetail)
check(not Settings.lowDetail and game:GetService("Lighting").GlobalShadows == true, "and back")
click(p.content.VolumeRow.VolumeDown)
check(Settings.volume == 0.75 and p.content.VolumeRow.Volume.Text == "VOLUME 75%", "volume down a step")
for _ = 1, 5 do
	click(p.content.VolumeRow.VolumeDown)
end
check(Settings.volume == 0 and p.content.VolumeRow.Volume.Text == "VOLUME 0%", "down to silent, no further")
for _ = 1, 6 do
	click(p.content.VolumeRow.VolumeUp)
end
check(Settings.volume == 1, "and back up to full")
click(p.screen:FindFirstChild("Close", true))
check(not p.screen.Enabled, "closed")
-- From the M menu.
Home.setMenu(true)
click(Home.parts.menu:FindFirstChild("Weapons", true))
check(p.screen.Enabled and Locker.tab == "Weapons", "the M menu opens it")
Home.setMenu(false)
check(not p.screen.Enabled, "and closing the menu closes it")

-- Leaving in the middle of a purchase.
xpTo(30)
local lou = Instance.new("Player")
lou.Name = "Lou"
lou.UserId = 2
lou.Parent = Players
task.wait(0.1)
Data.update(lou, function(d)
	d.Level = 25
	d.Coins = 3000
end)
latency = 1
task.spawn(function()
	Shop.request(lou, "buy", "weapon", "StinkLobber")
end)
task.wait(0.3)
lou.Parent = nil
task.wait(3)
latency = 0
local stored = saved.player_2
check(stored and stored.Coins == 500 and table.find(stored.OwnedWeapons, "StinkLobber") and stored.Lock == nil, "the purchase and the coins were saved together")

return { status = "PASS", checks = checks }
