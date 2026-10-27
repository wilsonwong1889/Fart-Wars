-- Weapon balance on the full-size Brainrot Battlefield (WeaponConfig's
-- ranges and CombatService.gasAt), through the real Bootstrap and remotes:
--   * each weapon has its role: the Spritzer reaches least, all of it
--     inside the Gas Blaster's full gas; the Thunderclapper reaches
--     farthest, never the arena's length, and past its effective range it
--     out-gasses the Gas Blaster; the Stink Lobber in between
--   * fall-off: full gas out to the effective range, less past it, never
--     under the minimum share; a headshot always does more than a body hit
--     at the same distance, by about the same proportion
--   * the same on real shots down Bean Alley's clear outer edge, where the
--     server measures the distance: full gas close, less far away, nothing
--     past the range
--   * every stink bomb lands inside the flight limit, the farthest at the
--     Lobber's range, and one can be lobbed over the throne
--   * the shop's descriptions name the numbers in the config
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

Players.MaxPlayers = 20
local server = game.ServerScriptService.Server
do
	local run = assert(loadstring(server.Bootstrap.Source, "Bootstrap"))
	setfenv(run, setmetatable({ script = server.Bootstrap }, { __index = getfenv() }))
	run()
end
local Combat = require(server.Services.CombatService)
local Gas = require(server.Services.GasService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local MapService = require(server.Services.MapService)
local Projectiles = require(server.Services.ProjectileService)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local Remotes = ReplicatedStorage.Remotes
local W = WeaponConfig.weapons
local gasAt = Combat.gasAt

-- Roles.
local map, entry = MapService.current()
assert(map and entry, "the map is built")
local arena = entry.bounds.size.Z
check(arena == 480, "the arena is 480 studs long")
check(W.Spritzer.range < W.StinkLobber.range and W.StinkLobber.range < W.GasBlaster.range and W.GasBlaster.range < W.Thunderclapper.range, "reach: Spritzer, Stink Lobber, Gas Blaster, Thunderclapper")
check(W.Spritzer.range <= (W.GasBlaster.effectiveRange :: number), "all of the Spritzer's reach is inside the Gas Blaster's full gas")
check(W.Thunderclapper.range < arena, "the Thunderclapper reaches farthest, but not the arena's length")
check(W.StinkLobber.effectiveRange == nil and W.StinkLobber.minGasShare == nil, "a stink bomb's splash doesn't fall off")
-- Gas a second, with every shot landing.
local function perSecond(id: string, distance: number): number
	local weapon = W[id]
	return if distance > weapon.range then 0 else gasAt(weapon, distance, false) / weapon.fireInterval
end
local closeOk, longOk = true, true
for d = 0, W.Spritzer.effectiveRange :: number do
	closeOk = closeOk and perSecond("Spritzer", d) >= perSecond("GasBlaster", d)
end
for d = W.Thunderclapper.effectiveRange :: number, W.Thunderclapper.range do
	longOk = longOk and perSecond("Thunderclapper", d) >= perSecond("GasBlaster", d)
end
check(closeOk, "up close, the Spritzer gasses at least as fast as the Gas Blaster")
check(longOk, "past its effective range, the Thunderclapper out-gasses the Gas Blaster")

-- Fall-off, for every instant weapon.
for _, id in WeaponConfig.order do
	local weapon = W[id]
	if weapon.projectile == "hitscan" then
		local effective, share = weapon.effectiveRange, weapon.minGasShare
		check(effective and share and effective > 0 and effective < weapon.range and share > 0 and share < 1, `{id} falls off between its effective range and its range`)
		local fullRange = weapon.range :: number
		local floorBody = math.max(1, math.floor(weapon.gasPerHit * (share :: number) + 0.5))
		local floorHead = math.max(1, math.floor(weapon.headshotGas * (share :: number) + 0.5))
		check(gasAt(weapon, 0, false) == weapon.gasPerHit and gasAt(weapon, effective :: number, false) == weapon.gasPerHit, `{id}: full gas out to {effective} studs`)
		check(gasAt(weapon, effective :: number, true) == weapon.headshotGas, `{id}: full headshots too`)
		check(gasAt(weapon, fullRange, false) == floorBody and gasAt(weapon, fullRange, true) == floorHead, `{id}: {floorBody}% ({floorHead}% to the head) at {fullRange} studs`)
		check(floorBody < weapon.gasPerHit, `{id}: a long shot does less`)
		check(gasAt(weapon, fullRange * 3, false) == floorBody, `{id}: never under the minimum`)
		local ratio = weapon.headshotGas / weapon.gasPerHit
		local lastBody, lastHead = math.huge, math.huge
		local steady, floored, better, proportional = true, true, true, true
		for d = 0, fullRange do
			local body, head = gasAt(weapon, d, false), gasAt(weapon, d, true)
			steady = steady and body <= lastBody and head <= lastHead
			floored = floored and body >= floorBody and head >= floorHead
			better = better and head > body
			proportional = proportional and math.abs(head / ratio - body) < 1
			lastBody, lastHead = body, head
		end
		check(steady, `{id}: the farther, never the more gas`)
		check(floored, `{id}: never under the minimum share`)
		check(better and proportional, `{id}: a headshot stays proportionally better at every distance`)
	end
end

-- Real shots down Bean Alley's outer edge (x = -228), clear from end to end.
local LANE_X = -228
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {}
local blocker = workspace:Raycast(Vector3.new(LANE_X, 4.5, -200), Vector3.new(0, 0, 430), params)
check(blocker == nil, `nothing stands in Bean Alley's outer edge ({blocker and blocker.Instance.Name})`)

local heard = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	heard[player] = heard[player] or {}
	table.insert(heard[player], event)
end)
local function last(player: Player, kind: string): any
	local list = heard[player] or {}
	for i = #list, 1, -1 do
		if list[i].kind == kind then
			return list[i]
		end
	end
	return nil
end
local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = 900 + nextId
	player.Parent = Players
	task.wait(0.05)
	Lifecycle.requestPlay(player, nil)
	return player
end
local ada = join("Ada")
local bo = join("Bo")
check(ada:GetAttribute("TeamId") ~= bo:GetAttribute("TeamId"), "two players on opposite teams")
task.wait(3.2) -- past spawn protection
local shotId = 0
-- Ada shoots Bo from `distance` studs down the lane; returns the gas it
-- did and how far from Ada's head it landed.
local function shot(weapon: string, distance: number, headshot: boolean): (number, number)
	Combat.setWeapon(ada, weapon)
	Gas.reset(bo)
	ada.Character:PivotTo(CFrame.new(LANE_X, 3, -200))
	bo.Character:PivotTo(CFrame.new(LANE_X, 3, -200 + distance))
	task.wait(1.05) -- past any weapon's interval
	local from = ada.Character.Head.Position
	local target = if headshot then bo.Character.Head.Position else bo.Character.HumanoidRootPart.Position
	shotId += 1
	Remotes.FireWeapon.OnServerEvent:Fire(ada, (target - from).Unit, shotId)
	local fired = last(ada, "shot")
	return Gas.gasOf(bo), (fired.to - fired.from).Magnitude
end

local gas, reach = shot("GasBlaster", 30, false)
check(gas == 20, "the Gas Blaster at 30 studs: 20%")
gas = shot("GasBlaster", 30, true)
check(gas == 25, "and 25% to the head")
gas, reach = shot("GasBlaster", 195, false)
check(gas == gasAt(W.GasBlaster, reach, false) and gas >= 14 and gas <= 16, `at 195 studs: {gas}%, about three quarters`)
local body
body, reach = shot("GasBlaster", 255, false)
local head = shot("GasBlaster", 255, true)
check(body == gasAt(W.GasBlaster, reach, false) and body >= 10 and body < 20, `at 255 studs: {body}%, about half`)
check(head > body, `a headshot there still does more ({head}%)`)
gas, reach = shot("GasBlaster", W.GasBlaster.range + 20, false)
check(gas == 0 and reach <= W.GasBlaster.range + 0.5, `past {W.GasBlaster.range} studs, the Gas Blaster's shot stops short`)

gas = shot("Spritzer", 40, false)
check(gas == W.Spritzer.gasPerHit, "the Spritzer at 40 studs: full gas")
gas, reach = shot("Spritzer", 85, false)
check(gas == gasAt(W.Spritzer, reach, false) and gas < W.Spritzer.gasPerHit and gas > 0, `at 85 studs: weaker ({gas}%)`)
gas, reach = shot("Spritzer", W.Spritzer.range + 20, false)
check(gas == 0 and reach <= W.Spritzer.range + 0.5, `past {W.Spritzer.range} studs it fizzles out`)

gas = shot("Thunderclapper", 200, false)
check(gas == 40, "the Thunderclapper at 200 studs: 40%")
gas = shot("Thunderclapper", 200, true)
check(gas == 55, "and 55% to the head: two and they're gone")
body, reach = shot("Thunderclapper", 400, false)
head = shot("Thunderclapper", 400, true)
check(body == gasAt(W.Thunderclapper, reach, false) and body >= 20 and body < 40, `at 400 studs: {body}%`)
check(head > body, `a headshot there: {head}%`)

-- Stink bombs, on open ground down the same edge.
local lobber = W.StinkLobber
local from = Vector3.new(LANE_X, 4.5, -150)
local allLand, farthest = true, 0
for degrees = 0, 85 do
	local r = math.rad(degrees)
	local landing, flight = Projectiles.arc(from, Vector3.new(0, math.sin(r), math.cos(r)), lobber, {})
	allLand = allLand and landing.Y < 2 and flight < Projectiles.MAX_FLIGHT_SECONDS
	farthest = math.max(farthest, landing.Z - from.Z)
end
check(allLand, "every throw lands inside the flight limit, however steep")
check(farthest > lobber.range - 5 and farthest <= lobber.range + 0.5, `the farthest throw: {math.floor(farthest)} studs, its range`)
-- Over the throne: from 70 studs in front of it to 70 behind.
local throne = map:FindFirstChild("Cover"):FindFirstChild("ThroneLid") :: BasePart
local throneTop = throne.Position.Y + throne.Size.Y / 2
check(workspace:Raycast(Vector3.new(0, 4.5, -70), Vector3.new(0, -3.5, 140), params) ~= nil, "the throne blocks the straight line")
local best = math.huge
for degrees = 0, 85 do
	local r = math.rad(degrees)
	local landing = Projectiles.arc(Vector3.new(0, 4.5, -70), Vector3.new(0, math.sin(r), math.cos(r)), lobber, {})
	best = math.min(best, (landing - Vector3.new(0, 0, 70)).Magnitude)
end
check(throneTop > 40 and best < 6, `a stink bomb lobbed over the {math.floor(throneTop)}-stud throne lands behind it`)

-- The shop's words.
for id, weapon in W do
	for n in string.gmatch(weapon.description, "(%d+) studs") do
		local studs = tonumber(n)
		check(studs == weapon.range or studs == weapon.effectiveRange, `{id}'s description: {n} studs is its range or effective range`)
	end
end
check(string.find(W.Spritzer.description, `past {W.Spritzer.range} studs`, 1, true), "the Spritzer fizzles out past its range, says the shop")

return { status = "PASS", checks = checks }
