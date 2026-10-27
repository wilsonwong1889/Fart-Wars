-- The admin code, with one client:
--   * a wrong code gives nothing; too many lock the box for the session
--   * the right code (any case, spaces around it) gives every weapon,
--     unlockable ability and cosmetic, coins and a full bank of spins,
--     saved, and turns the /fw commands on for that player
--   * the code itself never reaches the client
--   * the Settings page's code box sends it and shows the answer
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local Shop = require(server.Services.ShopService)
local AdminCode = require(server.AdminCode)
local TestControls = require(server.TestControls)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local RewardsConfig = require(ReplicatedStorage.Shared.Config.RewardsConfig)

local saved: { [string]: any } = {}
Data.setStore({
	UpdateAsync = function(_, key: string, transform: (any) -> any)
		local result = transform(saved[key])
		if result ~= nil then
			saved[key] = result
		end
		return result
	end,
})

local me = Instance.new("Player")
me.Name = "Me"
me.DisplayName = "Me"
me.UserId = 1
Instance.new("PlayerGui").Parent = me
Players.LocalPlayer = me
me.Parent = Players
task.wait(0.1)
run(game.StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap)
local Locker = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.LockerController)
task.wait(0.5)
local function data()
	return assert(Data.get(me)).data
end

-- The code is a server secret.
for _, item in ReplicatedStorage:GetDescendants() do
	if item:IsA("ModuleScript") then
		check(not string.find(string.lower(item.Source), "rematch", 1, true), `no code in {item:GetFullName()}`)
	end
end

-- A wrong code: nothing.
local coins = data().Coins
local answer = Shop.request(me, "redeem", "letmein")
check(not answer.ok and answer.reason == "wrong", "a wrong code is refused")
check(data().Coins == coins and #data().OwnedWeapons < #WeaponConfig.order, "and gives nothing")
check(not AdminCode.isAdmin(me), "no admin")
task.wait(0.3)

-- The right one, through the Settings page's box.
Locker.open("Settings")
task.wait(0.1)
local box = Locker.parts.content:FindFirstChild("CodeBox", true)
check(box ~= nil and box:IsA("TextBox"), "Settings has a code box")
box.Text = "  ReMatch "
Locker.request("redeem", box.Text)
task.wait(0.5)
check(AdminCode.isAdmin(me), "the right code (any case, spaces) makes an admin")
for id in WeaponConfig.weapons do
	check(table.find(data().OwnedWeapons, id), `owns {id}`)
end
for id, ability in AbilityConfig do
	if ability.ownership == "unlock" then
		check(table.find(data().UnlockedAbilities, id), `unlocked {id}`)
	end
end
for id in ProgressionConfig.cosmetics do
	check(table.find(data().OwnedCosmetics, id), `owns {id}`)
end
check(data().Coins >= coins + AdminCode.COINS, "coins")
check(data().Spins == RewardsConfig.MAX_SPINS and me:GetAttribute("Spins") == RewardsConfig.MAX_SPINS, "a full bank of spins")
check(saved["Player_1"] ~= nil or next(saved) ~= nil, "saved")
check(TestControls.allowed(me), "/fw commands on for the admin")
local equipped = Shop.request(me, "equip", "weapon", "Thunderclapper")
check(equipped.ok, "any weapon equips")

-- Too many wrong guesses lock the box.
local other = Instance.new("Player")
other.Name = "Other"
other.UserId = 2
other.Parent = Players
task.wait(0.5)
local last
for _ = 1, AdminCode.MAX_WRONG do
	task.wait(0.3)
	last = Shop.request(other, "redeem", "guess")
end
task.wait(0.3)
check(last.reason == "locked", "wrong guesses lock the box")
check(Shop.request(other, "redeem", "rematch").reason == "locked", "even for the right code after that")
check(not AdminCode.isAdmin(other), "no admin")

return { status = "PASS", checks = checks }
