-- Saving (masterplan 3.4), against a stand-in DataStore that stores JSON
-- like the real one and can fail or be slow on demand:
--   * a new player gets the default profile and the server's lock; coins
--     earned are in the store after an autosave, and after leaving (lock
--     released), and back on rejoining
--   * a profile locked by another live server waits for it; a lock that's
--     never released is taken after the wait; a crashed server's stale lock
--     is taken at once; a server that lost the lock stops writing
--   * outages: a load that fails a few times retries with backoff; one that
--     keeps failing (or a save from a newer version) gives a temporary
--     profile that is never written, so it can't overwrite the real one
--   * failed writes retry, and are counted when they all fail
--   * old, partial and damaged saves are migrated: missing fields filled,
--     bad numbers and types replaced, unowned equipment unequipped, owned
--     items kept
--   * leaving mid-load hands the lock back; rejoining the same server mid-
--     save waits for that save; a reward granted just before leaving is
--     saved; shutdown saves everyone; ten players joining at once each get
--     their own profile
local Players = game:GetService("Players")
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
local Telemetry = require(server.Telemetry)

-- The stand-in store.
local saved: { [string]: any } = {}
local failNext = 0
local latency = 0
local writes = 0
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
			writes += 1
		end
		return result
	end,
})
local function counter(name: string): number
	return Telemetry.snapshot().counters[name] or 0
end
local function waitFor(condition: () -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while not condition() do
		if os.clock() > deadline then
			return false
		end
		task.wait(0.1)
	end
	return true
end
local function join(name: string, userId: number): Player
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	return player
end
local function ready(player: Player, seconds: number?): boolean
	return waitFor(function()
		return Data.isLoaded(player)
	end, seconds or 1)
end
local function leave(player: Player)
	player.Parent = nil
	task.wait(0.1)
end

-- A new player.
local ada = join("Ada", 101)
check(ready(ada), "Ada's profile loads")
local profile = assert(Data.get(ada))
check(not profile.temporary and ada:GetAttribute("DataStatus") == "ready", "a saved profile, and the client knows")
check(profile.data.Coins == 0 and profile.data.Level == 1 and profile.data.SaveVersion == Data.VERSION, "starts from the defaults")
check(profile.data.EquippedWeapon == "GasBlaster" and table.find(profile.data.OwnedWeapons, "GasBlaster"), "with the starter weapon")
check(saved.player_101 and saved.player_101.Lock and saved.player_101.Lock.Job == "studio", "this server holds the lock")

-- Earn, autosave, leave, come back.
check(Economy.testGrant(ada, 120, 0), "Ada earns 120 coins")
check(profile.data.Coins == 120 and saved.player_101.Coins == 0, "in the profile at once; the store catches up")
task.wait(Data.AUTOSAVE_SECONDS + 1)
check(saved.player_101.Coins == 120 and saved.player_101.Lock ~= nil, "the autosave writes it, keeping the lock")
check(Economy.testGrant(ada, 30, 0), "30 more")
leave(ada)
check(saved.player_101.Coins == 150 and saved.player_101.Lock == nil, "leaving saves everything and releases the lock")
local ada2 = join("Ada", 101)
check(ready(ada2), "Ada's back")
check(assert(Data.get(ada2)).data.Coins == 150, "with her 150 coins")
leave(ada2)

-- Another server holds the lock and lets go.
saved.player_102 = { SaveVersion = 1, Coins = 5, Lock = { Job = "other-server", At = os.time() } }
local bo = join("Bo", 102)
task.wait(2)
check(not Data.isLoaded(bo) and bo:GetAttribute("DataStatus") == "loading", "Bo waits while another server holds his profile")
saved.player_102.Lock = nil
check(ready(bo, 4), "and loads when it lets go")
check(assert(Data.get(bo)).data.Coins == 5, "with that server's last save")
leave(bo)

-- A lock that's never released is taken after the wait; the old server,
-- if it's still there, finds it's lost the lock.
saved.player_103 = { SaveVersion = 1, Coins = 9, Lock = { Job = "stuck-server", At = os.time() } }
local cy = join("Cy", 103)
local joinedAt = os.clock()
check(ready(cy, Data.LOCK_WAIT_SECONDS + Data.LOCK_RETRY_SECONDS + 1), "Cy gets his profile in the end")
check(os.clock() - joinedAt >= Data.LOCK_WAIT_SECONDS, "but only after the full wait")
check(counter("Data.lockTaken") == 1 and saved.player_103.Lock.Job == "studio", "the lock is taken (and counted)")
saved.player_103.Lock = { Job = "newest-server", At = os.time() }
Economy.testGrant(cy, 1000, 0)
check(not Data.save(cy) and assert(Data.get(cy)).lost, "once another server has it, this one can't save")
check(saved.player_103.Coins == 9 and counter("Data.lockLost") == 1, "nothing was overwritten")
leave(cy)
check(saved.player_103.Lock.Job == "newest-server" and saved.player_103.Coins == 9, "not even on leaving")

-- A crashed server's lock is stale: taken at once.
saved.player_104 = { SaveVersion = 1, Coins = 3, Lock = { Job = "crashed-server", At = os.time() - Data.LOCK_TIMEOUT_SECONDS - 5 } }
local di = join("Di", 104)
check(ready(di, 0.5), "a stale lock doesn't make Di wait")
check(assert(Data.get(di)).data.Coins == 3, "Di's coins are there")
leave(di)

-- A short outage: retried with backoff.
failNext = 2
local ed = join("Ed", 105)
task.wait(1)
check(not Data.isLoaded(ed), "Ed's first loads fail")
check(ready(ed, 8), "the retries get it")
check(not assert(Data.get(ed)).temporary, "a real, saved profile")
leave(ed)

-- A long outage: a temporary profile, never written.
failNext = 100
local flo = join("Flo", 106)
check(ready(flo, 20), "Flo plays even though her profile won't load")
local temp = assert(Data.get(flo))
check(temp.temporary and flo:GetAttribute("DataStatus") == "unsaved", "on a temporary profile, and the client knows")
failNext = 0
Economy.testGrant(flo, 50, 0)
check(temp.data.Coins == 50, "rewards still show this session")
check(not Data.save(flo), "but are never saved")
leave(flo)
check(saved.player_106 == nil, "nothing was written over her real profile")
check(counter("Data.temporaryProfiles") == 1, "counted")

-- A save from a newer version of the game is never touched.
saved.player_107 = { SaveVersion = Data.VERSION + 1, Coins = 7, NewField = true }
local gus = join("Gus", 107)
check(ready(gus), "Gus plays")
check(assert(Data.get(gus)).temporary, "on a temporary profile")
leave(gus)
check(saved.player_107.SaveVersion == Data.VERSION + 1 and saved.player_107.Coins == 7 and saved.player_107.NewField, "the newer save is as it was")

-- Old, partial and damaged saves.
saved.player_108 = {
	SaveVersion = 0,
	Coins = 50,
	Level = 3,
	XP = "lots",
	TotalDeaths = -5,
	BestStreak = 0 / 0,
	OwnedWeapons = { "Mystery" },
	EquippedWeapon = "Mystery",
	EquippedAbility = "GasPulse",
	EquippedCosmetic = "GoldenGas",
}
local hal = join("Hal", 108)
check(ready(hal), "Hal's old save loads")
local migrated = assert(Data.get(hal)).data
check(migrated.SaveVersion == Data.VERSION and migrated.Coins == 50 and migrated.Level == 3, "kept what was good")
check(migrated.XP == 0 and migrated.TotalDeaths == 0 and migrated.BestStreak == 0, "replaced bad types and impossible numbers")
check(table.find(migrated.OwnedWeapons, "Mystery") and table.find(migrated.OwnedWeapons, "GasBlaster"), "kept his weapons and added the starter")
check(migrated.EquippedWeapon == "GasBlaster", "unequipped a weapon that doesn't exist")
check(migrated.EquippedAbility == nil and migrated.EquippedCosmetic == nil, "and things he doesn't own")
for key in Data.defaults() :: any do
	check((migrated :: any)[key] ~= nil, `{key} is filled in`)
end
check(counter("Data.invalidEquip") >= 3, "invalid equipment is counted")
check(Data.migrate(Data.migrate(saved.player_108)).Coins == 50, "migrating twice changes nothing")
leave(hal)
check(saved.player_108.SaveVersion == Data.VERSION and saved.player_108.XP == 0, "saved at the new version")

-- Failed writes.
local ivy = join("Ivy", 109)
check(ready(ivy), "Ivy loads")
Economy.testGrant(ivy, 10, 0)
failNext = 1
check(Data.save(ivy) and saved.player_109.Coins == 10, "a failed write is retried")
failNext = Data.SAVE_ATTEMPTS
check(not Data.save(ivy) and counter("Data.saveFailures") == 1, "one that keeps failing gives up and is counted")
failNext = 0
Economy.testGrant(ivy, 5, 0)
leave(ivy)
check(saved.player_109.Coins == 15 and saved.player_109.Lock == nil, "the next save has everything")

-- Leaving while the profile loads.
latency = 1
local jo = join("Jo", 110)
task.wait(0.5)
leave(jo)
task.wait(3)
check(saved.player_110 and saved.player_110.Lock == nil, "the lock is handed straight back")
latency = 0

-- Rewards just before leaving; rejoining before that save is done.
local kai = join("Kai", 111)
check(ready(kai), "Kai loads")
Economy.testGrant(kai, 40, 0)
-- His last save is slow; loading again would be quick.
latency = 1.5
kai.Parent = nil
task.wait(0.1)
latency = 0
local kai2 = join("Kai", 111)
check(ready(kai2, 6), "Kai's back on the same server")
check(assert(Data.get(kai2)).data.Coins == 40, "after his last save landed, with the coins he got just before leaving")
check(saved.player_111.Lock ~= nil and saved.player_111.Lock.Job == "studio", "and holds the lock again")
leave(kai2)

-- Ten at once, then a shutdown.
local crowd = {}
for i = 1, 10 do
	table.insert(crowd, join(`P{i}`, 200 + i))
end
check(waitFor(function()
	for _, p in crowd do
		if not Data.isLoaded(p) then
			return false
		end
	end
	return true
end, 2), "ten joining together all load")
for i, p in crowd do
	Economy.testGrant(p, i, 0)
end
local before = writes
Data.saveAll()
check(writes - before == 10, "shutdown writes each profile once")
for i = 1, 10 do
	local entry = saved[`player_{200 + i}`]
	check(entry and entry.Coins == i and entry.Lock == nil, `P{i}'s own coins, lock released`)
end
check(not Data.isLoaded(crowd[1]), "profiles are let go")
for _, p in crowd do
	p.Parent = nil
end
task.wait(0.5)
check(writes - before == 10, "and leaving afterwards doesn't write them again")

return { status = "PASS", checks = checks }
