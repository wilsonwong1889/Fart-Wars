-- Release, health and safety (masterplan 5.1, 5.4), with one client:
--   * the version: semantic, published to clients, on the home screen and
--     in Settings; the channel from the place ID ("dev" anywhere but the
--     configured staging and live places)
--   * health: every service loop beating; a stopped loop is FAILING and
--     recovers; an error in a tick is counted, shown, and the loop goes on;
--     a burst of errors is DEGRADED; saving's check; /fw health
--   * client reports: frame rate, ping, errors and quality averaged; junk
--     and spam refused
--   * player reports: a fixed list of reasons, not yourself, once per
--     person, a few a session; three different players flag someone once
--     for review (nothing automatic beyond the flag)
--   * the Players screen: everyone else, BLOCK, HIDE EMOTES (their emotes
--     stop showing), REPORT with its reasons and the answer, and the note
--     about Roblox's own Report
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
local ReleaseConfig = require(Shared.Config.ReleaseConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Data = require(server.Services.DataService)
local Health = require(server.Health)
local Moderation = require(server.Moderation)
local Telemetry = require(server.Telemetry)
local TestControls = require(server.TestControls)
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
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end

-- The version.
check(string.match(ReleaseConfig.VERSION, "^%d+%.%d+%.%d+$"), "a major.minor.patch version")
check(ReleaseConfig.channel(game.PlaceId) == "dev" and ReleaseConfig.channel(0) == "dev", "no place IDs set: dev everywhere")
check(ReleaseConfig.label("live") == ReleaseConfig.VERSION and ReleaseConfig.label("staging") == `{ReleaseConfig.VERSION} (staging)`, "labels")
check(workspace:GetAttribute("GameVersion") == ReleaseConfig.VERSION and workspace:GetAttribute("ReleaseChannel") == "dev", "published to clients")

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
local Home = require(Controllers.HomeController)
local Locker = require(Controllers.LockerController)
local PlayersUI = require(Controllers.PlayersController)
local Effects = require(Controllers.EffectsController)
local ClientHealth = require(Controllers.HealthController)
local Settings = require(game.StarterPlayer.StarterPlayerScripts.Client.Settings)
local others = {}
for i = 2, 5 do
	local other = Instance.new("Player")
	other.Name = `P{i}`
	other.DisplayName = `Player {i}`
	other.UserId = i
	other.Parent = Players
	others[i] = other
end
task.wait(0.5)
check(string.find(Home.parts.version.Text, ReleaseConfig.VERSION, 1, true) and string.find(Home.parts.version.Text, "dev", 1, true), "the home screen shows the build")
Locker.open("Settings")
task.wait(0.1)
check(Locker.parts.content:FindFirstChild("Version") and Locker.parts.content.Version.Text == `Version {ReleaseConfig.VERSION} (dev)`, "and Settings")
Locker.close()

-- Health.
local loops = Health.loopNames()
for _, name in { "AFK", "Autosave", "Economy", "Experiments", "Gas", "Rewards", "Rounds", "Social" } do
	check(table.find(loops, name), `the {name} loop is watched`)
end
check(Health.probe(), "saving's check passes")
task.wait(Health.CHECK_SECONDS + 1)
local report = Health.report()
check(report.status == "OK" and #report.problems == 0, `a healthy server: OK ({table.concat(report.problems, "; ")})`)
check(workspace:GetAttribute("ServerHealth") == "OK" and report.players == 5 and report.version == ReleaseConfig.VERSION, "published, with the numbers")
check(report.memoryMb == 420 and report.serverFps >= 0, "memory and frame rate measured")
Health.testSetBeat("Gas", os.clock() - 120)
report = Health.check()
check(report.status == "FAILING" and string.find(report.problems[1], "Gas loop stopped", 1, true), "a stopped loop: FAILING")
check(workspace:GetAttribute("ServerHealth") == "FAILING" and counter("health.FAILING") >= 1, "published and counted")
task.wait(1)
check(Health.check().status == "OK", "it beats again: OK")
local ok, summary = TestControls.health()
check(ok and string.find(summary, `OK v{ReleaseConfig.VERSION} (dev)`, 1, true), "/fw health: " .. summary)
-- A tick that errors.
local runs = 0
Health.loop("Flaky", 1, function()
	runs += 1
	if runs == 2 then
		error("boom")
	end
end)
task.wait(4.5)
local raised = takeBackgroundErrors()
check(#raised == 1 and string.find(raised[1], "[FW] Flaky loop:", 1, true) and string.find(raised[1], "boom", 1, true), "an error in a tick is raised where it shows")
check(runs >= 4 and (Telemetry.snapshot().errors.Flaky or 0) == 1, "counted once, and the loop carried on")
for _ = 1, 50 do
	Telemetry.error("Burst", "test")
end
report = Health.check()
check(report.status == "DEGRADED" and string.find(table.concat(report.problems, ";"), "errors a minute", 1, true), "a burst of errors: DEGRADED")
task.wait(Health.CHECK_SECONDS + 1)
check(Health.report().status == "OK", "then OK again")
-- Saving failing its check.
local failures = counter("health.probeFailures")
Health.setProbe(function()
	return false, "502: test outage"
end)
check(not Health.probe(), "saving's check fails")
report = Health.check()
check(report.status == "DEGRADED" and string.find(table.concat(report.problems, ";"), "502: test outage", 1, true), "DEGRADED, saying why")
check(counter("health.probeFailures") == failures + 1, "counted")
Health.setProbe(Data.probe)
Health.probe()
check(Health.check().status == "OK", "saving back: OK")

-- Client reports (the client sent one by itself a minute in).
check(counter("client.reports") == 1, "the client reports by itself")
ClientHealth.REPORT_SECONDS = 1e6
task.wait(Health.CLIENT_REPORT_SECONDS + 1)
ClientHealth.send()
task.wait(0.1)
check(counter("client.reports") == 2, "a client report arrives")
local samples = Telemetry.snapshot().samples
check(samples["client.pingMs"] and math.abs(samples["client.pingMs"].average - 60) < 0.01, "ping averaged (ms)")
ClientHealth.send()
task.wait(0.1)
check(counter("client.reports") == 2 and Telemetry.snapshot().rejects.ClientReport.tooFast == 1, "again at once: refused")
task.wait(Health.CLIENT_REPORT_SECONDS + 1)
Remotes.ClientReport.OnServerEvent:Fire(others[2], { fps = 22, ping = 0.4, errors = 3, quality = 2 })
task.wait(0.1)
check(counter("client.lowFps") == 1 and counter("client.highPing") == 1 and counter("client.errors") == 3, "low frame rate, high ping and errors counted")
Remotes.ClientReport.OnServerEvent:Fire(others[3], "lag")
Remotes.ClientReport.OnServerEvent:Fire(others[4], { fps = 0 / 0, ping = -1, errors = 1e9 })
task.wait(0.1)
check(Telemetry.snapshot().rejects.ClientReport.badPayload == 1 and counter("client.errors") == 3, "junk refused or ignored")

-- Player reports.
local function report(by: Player, userId: unknown, reason: unknown)
	return Moderation.report(by, userId, reason).reason
end
check(report(me, 2, "Lag") == "badPayload" and report(me, "2", "Cheating") == "badPayload", "only the listed reasons, by user ID")
check(report(me, 1, "Cheating") == "notHere", "not yourself")
check(report(me, 999, "Cheating") == "notHere", "not someone who isn't here")
check(report(me, 2, "Cheating") == "sent" and report(me, 2, "Griefing") == "already", "once per person")
check(counter("reports.total") == 1 and counter("reports.Cheating") == 1, "counted by reason")
check(#Moderation.flagsOf(others[2]) == 0, "one report flags nobody")
check(report(others[3], 2, "Cheating") == "sent" and #Moderation.flagsOf(others[2]) == 0, "nor two")
check(report(others[4], 2, "Harassment") == "sent", "a third")
local flags = Moderation.flagsOf(others[2])
check(#flags == 1 and flags[1].reason == "reported", "three different players: flagged for review")
check(report(others[5], 2, "Other") == "sent" and #Moderation.flagsOf(others[2]) == 1, "once")
check(others[2].Parent == Players, "and nothing automatic beyond the flag (kicks are off)")
for i = 3, 5 do
	report(me, i, "Other")
end
local extra = Instance.new("Player")
extra.Name = "P6"
extra.UserId = 6
extra.Parent = Players
local extra2 = Instance.new("Player")
extra2.Name = "P7"
extra2.UserId = 7
extra2.Parent = Players
task.wait(0.2)
check(report(me, 6, "Other") == "sent", "a fifth")
check(report(me, 7, "Other") == "tooMany", `{GameConfig.MODERATION.REPORTS_PER_SESSION} a session`)

-- The Players screen.
Home.setMenu(true)
task.wait(0.1)
check(Home.parts.menu.Panel:FindFirstChild("Players"), "PLAYERS in the M menu")
Home.setMenu(false)
PlayersUI.open()
task.wait(0.1)
local list = PlayersUI.parts.list
local rows = 0
for _, child in list:GetChildren() do
	if child:IsA("Frame") then
		rows += 1
	end
end
check(rows == 6 and not list:FindFirstChild("1"), "everyone else, not me")
check(list["2"].PlayerName.Text == "Player 2  @P2" and list["2"]:FindFirstChild("Block"), "names and BLOCK")
check(string.find(PlayersUI.parts.note.Text, "Esc > Report", 1, true), "how to report through Roblox")
PlayersUI.toggleEmotes(3)
check(Settings.hiddenEmotes[3] and list["3"].Emotes.Text == "SHOW EMOTES", "HIDE EMOTES")
require(server.Services.PlayerLifecycleService).requestPlay(others[3], nil)
task.wait(0.1)
check(Effects.emote(3, "Toot") == nil, "their emotes stop showing")
-- A new report through the screen.
local newcomer = Instance.new("Player")
newcomer.Name = "P8"
newcomer.UserId = 8
newcomer.Parent = Players
task.wait(0.1)
check(list:FindFirstChild("8"), "a new player appears")
PlayersUI.reporting = 8
PlayersUI.render()
check(list["8"]:FindFirstChild("Cheating") and list["8"]:FindFirstChild("Other"), "REPORT shows the reasons")
check(PlayersUI.report(8, "Cheating") == "tooMany" and list["8"].Note.Text == PlayersUI.MESSAGES.tooMany, "and the server's answer")
PlayersUI.close()
check(not PlayersUI.parts.screen.Enabled, "closed")

return { status = "PASS", checks = checks }
