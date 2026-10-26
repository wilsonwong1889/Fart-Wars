-- Seasons and booms (masterplan 6.3), with one client:
--   * off as shipped, and outside a season's dates nothing happens
--   * season XP: a share of every XP point, challenges on top; each tier
--     paid once (coins, cosmetics at 5, 10, 15, 20, the badge at 20)
--   * this week's challenges: the same for everyone, only ones that can be
--     done, counted from real play (eliminations, assists, dashes,
--     barrels, minutes, streaks), done once; a new week starts them again
--   * a new season starts the track again and keeps what was earned
--   * the Season screen and its button; booms colour the explosions of
--     the players you eliminate
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
local SeasonConfig = require(Shared.Config.SeasonConfig)
local Data = require(server.Services.DataService)
local Season = require(server.Services.SeasonService)
local Economy = require(server.Services.EconomyService)
local Loadout = require(server.Services.LoadoutService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Team = require(server.Services.TeamService)
local Remotes = ReplicatedStorage.Remotes

local saved = {}
Data.setStore({
	UpdateAsync = function(_, key, transform)
		local result = transform(saved[key] and HttpService:JSONDecode(saved[key]))
		if result ~= nil then
			saved[key] = HttpService:JSONEncode(result)
		end
		return result
	end,
})
local now = 2000000000
Season.setClock(function()
	return now
end)
-- (Its ID puts eliminations, assists and Fart Dashes in week 1.)
local testSeason = { id = "T0", name = "Test Season", startsAt = now - 3600, endsAt = now + 30 * 86400 }
Season.setSeasons({ testSeason })

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
local Screen = require(Controllers.SeasonController)
local MenuBar = require(Controllers.MenuBarController)
local foe = Instance.new("Player")
foe.Name = "Foe"
foe.UserId = 2
foe.Parent = Players
task.wait(0.5)
local function data(player: Player?): any
	return assert(Data.get(player or me)).data
end

-- Off.
check(FeatureFlags.SEASONS == false and Season.current() == nil, "off as shipped")
check(workspace:GetAttribute("SeasonActive") == false and not MenuBar.parts.season.Visible, "no SEASON button")
Economy.grant(me, "s:xp0", "elimination", 0, 500)
check(data().SeasonXP == 0, "no season XP while off")

-- On.
Season.testEnable(true)
check(Season.current() == testSeason and workspace:GetAttribute("SeasonActive") == true, "a season on")
task.wait(0.1)
check(MenuBar.parts.season.Visible, "the SEASON button shows")
Economy.grant(me, "s:xp1", "elimination", 0, 1000)
task.wait(0.1)
check(data().SeasonId == "T0" and data().SeasonXP == math.floor(1000 * SeasonConfig.XP_SHARE), "a share of XP becomes season XP")
check(me:GetAttribute("SeasonXP") == data().SeasonXP, "published")

-- Challenges.
local weekly = Season.challenges()
check(#weekly == SeasonConfig.CHALLENGES_PER_WEEK, "three challenges a week")
for _, challenge in weekly do
	check(challenge.needs == nil, `{challenge.id} can be done with what's on`)
end
local again = Season.challenges()
check(again[1].id == weekly[1].id and again[3].id == weekly[3].id, "the same for everyone")
local byStat = {}
for _, challenge in weekly do
	byStat[challenge.stat] = challenge
end
-- Do each one this week through real events where possible.
Lifecycle.requestPlay(me, "Stinkers")
Lifecycle.requestPlay(foe, "Sharters")
task.wait(0.3)
Team.testSetTeam(me, "Stinkers")
Team.testSetTeam(foe, "Sharters")
task.wait(3.2)
local xpBefore = data().SeasonXP
for stat, challenge in byStat do
	if stat == "eliminations" then
		local AFK = require(server.Services.AFKService)
		for _ = 1, challenge.goal do
			Gas.add(foe, 100, { attacker = me, cause = "shot", weapon = "GasBlaster" })
			task.wait(1.2)
			while not (foe.Character and foe.Character:FindFirstChildOfClass("Humanoid") and foe.Character.Humanoid.Health > 0) do
				AFK.markActive(foe)
				task.wait(0.5)
			end
			AFK.markActive(me)
			AFK.markActive(foe)
			Lifecycle.endProtection(foe)
		end
	elseif stat == "dashes" then
		local Dash = require(server.Services.DashService)
		local cooldown = require(Shared.Config.AbilityConfig).FartDash.cooldownSeconds
		for _ = 1, challenge.goal do
			Dash.dash(me, Vector3.new(1, 0, 0))
			task.wait(cooldown + 0.05)
			me.Character:PivotTo(CFrame.new(0, 3, -40))
		end
	else
		Season.count(me, stat, challenge.goal)
	end
end
check(byStat.eliminations and byStat.dashes, "this week has eliminations and dashes, counted from real play")
task.wait(0.2)
check(#data().SeasonDone == 3, "all three done")
check(data().SeasonXP >= xpBefore + 3 * SeasonConfig.XP_PER_CHALLENGE, "each worth its season XP")
local doneXP = data().SeasonXP
Season.count(me, weekly[1].stat, 100)
task.wait(0.1)
check(data().SeasonXP == doneXP, "a challenge pays once")
-- Not this week's: nothing.
local other
for _, challenge in SeasonConfig.challenges do
	if not byStat[challenge.stat] and challenge.needs == nil then
		other = challenge
	end
end
if other then
	Season.count(me, other.stat, 1000)
	check(data().SeasonProgress[other.stat] == nil, "a stat no challenge this week uses isn't counted")
end

-- Tiers: paid once each, cosmetics on the way.
local coinsBefore = data().Coins
Season.addXP(me, SeasonConfig.XP_PER_TIER * 20)
task.wait(0.2)
check(data().SeasonTier == #SeasonConfig.tiers, "the whole track")
for tier, reward in SeasonConfig.tiers do
	if reward.cosmetic then
		check(table.find(data().OwnedCosmetics, reward.cosmetic), `tier {tier}: the {reward.cosmetic}`)
	end
end
check(table.find(data().Badges, "Season1"), "the badge at the top")
local paid = 0
for tier = 1, #SeasonConfig.tiers do
	paid += SeasonConfig.tiers[tier].coins
end
check(data().Coins >= coinsBefore + paid - 1000, "coins for the tiers")
local coinsAtTop = data().Coins
Season.addXP(me, SeasonConfig.XP_PER_TIER * 5)
task.wait(0.1)
check(data().Coins == coinsAtTop, "nothing more past the top")

-- The screen.
Screen.open()
task.wait(0.1)
check(string.find(Screen.parts.title.Text, "TEST SEASON", 1, true) and string.find(Screen.parts.summary.Text, "nds in 29d", 1, true), "the season, and its real end")
check(Screen.parts.list:FindFirstChild(`Challenge_{weekly[1].id}`) and string.find(Screen.parts.list[`Challenge_{weekly[1].id}`].Text, "✓", 1, true), "this week's challenges, ticked")
Screen.close()

-- A new week: new challenges, counts from zero.
now += 7 * 86400
Season.count(me, "minutes", 1)
task.wait(0.1)
check(data().SeasonWeek == 2 and #data().SeasonDone == 0, "a new week starts the challenges again")
local week2 = Season.challenges()
check(week2[1].id ~= weekly[1].id, "with different ones")

-- A new season.
local nextSeason = { id = "T2", name = "Next", startsAt = now - 60, endsAt = now + 86400 }
Season.setSeasons({ testSeason, nextSeason })
testSeason.endsAt = now - 120
Season.addXP(me, 10)
task.wait(0.1)
check(data().SeasonId == "T2" and data().SeasonTier == 0 and data().SeasonXP == 10, "a new season starts the track again")
check(table.find(data().OwnedCosmetics, "BrainrotGold") and table.find(data().Badges, "Season1"), "and keeps what was earned")
-- Between seasons.
now += 2 * 86400
check(Season.current() == nil, "between seasons: none")
local between = data().SeasonXP
Economy.grant(me, "s:xp2", "elimination", 0, 1000)
task.wait(0.1)
check(data().SeasonXP == between, "and no season XP")

-- Booms.
check(Loadout.equip(me, "cosmetic", "ToxicBoom") and me:GetAttribute("Boom") == "ToxicBoom", "a boom equipped")
local Effects = require(Controllers.EffectsController)
local pool = Effects.pool
Remotes.CombatEvent:FireClient(me, { kind = "explosion", victim = 2, killer = 1, position = Vector3.new(0, 5, 0) })
task.wait(0.05)
local purple = false
for _, burst in pool do
	if burst.Color == require(Shared.Config.ProgressionConfig).cosmetics.ToxicBoom.boomColor then
		purple = true
	end
end
check(purple, "my eliminations explode in my boom's colour")
check(Loadout.equip(me, "boom", nil) and me:GetAttribute("Boom") == nil, "and off again")
Season.testEnable(nil)

return { status = "PASS", checks = checks }
