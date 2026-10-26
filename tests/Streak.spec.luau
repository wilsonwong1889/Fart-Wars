-- Streaks and "BRO IS THE ALPHA FART!" (masterplan 2.4), with one client:
--   * five eliminations without dying: the whole server gets the call,
--     word for word, once; the sixth doesn't repeat it
--   * a death resets the streak (the best is kept), and the next five call
--     it again
--   * two players reaching it together are announced a few seconds apart
--   * the client shows the banner with the player's name, inflates avatars
--     by gas stage (bellies only, never the hitbox), and keeps its effect
--     pool to a fixed size however many explosions happen
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
local Gas = require(server.Services.GasService)
local Eliminations = require(server.Services.EliminationService)
local Lifecycle = require(server.Services.PlayerLifecycleService)
local Remotes = ReplicatedStorage.Remotes

local calls = {}
Remotes.CombatEvent.FiredToClient:Connect(function(player, event)
	if event.kind == "alpha" and player.Name == "Me" then
		table.insert(calls, { at = workspace:GetServerTimeNow(), player = event.player, text = event.text })
	end
end)

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
local Effects = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.EffectsController)
Lifecycle.requestPlay(me, nil)

local nextId = 0
local function join(name: string): Player
	nextId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = 800 + nextId
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
-- `killer` blows up `victim` (who must be ready: alive, unprotected).
local function eliminate(killer: Player, victim: Player)
	Gas.add(victim, 100, { attacker = killer, cause = "shot" })
	task.wait(1.05)
end
-- Waits out every respawn and its protection.
local function settle()
	task.wait(3.2)
	fidget()
	task.wait(3.1)
end

local ace = join("Ace")
local foe = join("Foe")
check(ace:GetAttribute("TeamId") ~= foe:GetAttribute("TeamId"), "Ace and Foe on opposite teams")
local mine = me:GetAttribute("TeamId")
settle()

-- Five in a row.
for i = 1, 4 do
	eliminate(ace, foe)
	settle()
	check(Eliminations.streakOf(ace) == i, `streak {i}`)
end
check(#calls == 0, "nothing to announce yet")
eliminate(ace, foe)
task.wait(0.1)
check(#calls == 1 and calls[1].player == ace.UserId and calls[1].text == "BRO IS THE ALPHA FART!", "five: BRO IS THE ALPHA FART!")
local banner = Effects.parts.alpha
check(banner.Visible and Effects.parts.alphaText.Text == "BRO IS THE ALPHA FART!" and Effects.parts.alphaName.Text == "ACE", "the banner, with Ace's name")
settle()
check(not banner.Visible, "it goes after a few seconds")
eliminate(ace, foe)
settle()
check(Eliminations.streakOf(ace) == 6 and #calls == 1, "the sixth doesn't repeat it")

-- A death resets it.
eliminate(foe, ace)
settle()
check(Eliminations.streakOf(ace) == 0 and Eliminations.bestStreakOf(ace) == 6, "Ace's death resets the streak; the best stays 6")
for _ = 1, 5 do
	eliminate(ace, foe)
	settle()
end
check(#calls == 2, "five more: called again")

-- Two at once.
local twoA, twoB = join("Two A"), join("Two B")
local victimsOf = {}
for _, p in { twoA, twoB } do
	victimsOf[p] = if p:GetAttribute("TeamId") == ace:GetAttribute("TeamId") then foe else ace
end
settle()
for _ = 1, 4 do
	for _, p in { twoA, twoB } do
		Gas.add(victimsOf[p], 100, { attacker = p, cause = "shot" })
	end
	task.wait(1.05)
	settle()
end
local before = #calls
for _, p in { twoA, twoB } do
	Gas.add(victimsOf[p], 100, { attacker = p, cause = "shot" })
end
task.wait(4.5)
check(#calls == before + 2, "both get the call")
check(calls[#calls].at - calls[#calls - 1].at >= 2.99, "a few seconds apart, not on top of each other")

-- Inflation on the client, by stage.
settle()
local target = if foe:GetAttribute("TeamId") == mine then ace else foe
local enemy = if target == ace then foe else ace
for stage, amount in { [1] = 30, [2] = 25, [3] = 25 } do
	Gas.add(target, amount, { attacker = enemy, cause = "shot" })
	task.wait(0.3)
	local belly = target.Character:FindFirstChild("GasBelly")
	check(belly and belly.Size.X > 2 and belly.CanQuery == false and belly.CanCollide == false, `stage {stage}: a belly, out of the way of shots`)
	check(target.Character:GetAttribute("GasStage") == stage, `stage {stage} on the character`)
end
check(target.Character:FindFirstChild("GasWarning"), "critical: the warning outline")
check(target.Character.HumanoidRootPart.Size == Vector3.new(2, 2, 1), "the hitbox never changes")

-- The effect pool stays the same size.
for i = 1, 30 do
	Effects.explosion(Vector3.new(i, 3, 0))
end
local bursts = 0
for _, child in workspace:GetChildren() do
	if child.Name == "Burst" then
		bursts += 1
	end
end
check(bursts == 8 and #Effects.pool == 8, "30 explosions, 8 pooled bursts")

return { status = "PASS", checks = checks }
