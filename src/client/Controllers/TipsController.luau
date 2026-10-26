-- Contextual tips (masterplan 3.5's journey: discover dash and barrels in
-- the first minutes, then the next unlock). A tip is one short line with
-- the reward lines, shown once a session, only while playing, never in
-- the middle of a fight (holding fire, a shot in the last few seconds, or
-- carrying a lot of gas), and all of them can be turned off in Settings.
--   * a minute of play without a dash: SHIFT
--   * two minutes in: gas barrels
--   * a weapon you can now afford and haven't bought
--   * an ability you've unlocked but haven't equipped
-- Whether tips start on is the "tips" experiment's (on, unless the player
-- is in a cohort without them); Settings changes it either way.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local UIConfig = require(Shared.Config.UIConfig)
local ExperimentConfig = require(Shared.Config.ExperimentConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Settings = require(Client.Settings)
local InputController = require(script.Parent.InputController)
local ProgressController = require(script.Parent.ProgressController)
local LockerController = require(script.Parent.LockerController)

local TIP_COLOR = Color3.fromRGB(140, 210, 255)
-- No tips this soon after a shot.
local QUIET_SECONDS = 3

local TipsController = {}

-- Tips already shown this session, by id.
TipsController.shown = {} :: { [string]: boolean }

local player = Players.LocalPlayer
local activeSeconds = 0
local dashed = false
local lastFireAt = -math.huge
local started = false

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- Whether the player is busy fighting right now.
function TipsController.fighting(): boolean
	if InputController.fireHeld or os.clock() - lastFireAt < QUIET_SECONDS then
		return true
	end
	local character = player.Character
	local gas = character and character:GetAttribute("Gas")
	return type(gas) == "number" and gas >= 50
end

-- Shows tip `id` if it's allowed now. Returns whether it showed.
function TipsController.show(id: string, text: string): boolean
	if not Settings.tips or TipsController.shown[id] or not ClientState.isActive() or TipsController.fighting() then
		return false
	end
	TipsController.shown[id] = true
	ProgressController.line(text, TIP_COLOR, UIConfig.tipSeconds, "Tip")
	return true
end

-- What's worth saying now, at most one tip a check.
function TipsController.check()
	if not ClientState.isActive() then
		return
	end
	local tips = UIConfig.tips
	if activeSeconds >= 60 and not dashed and TipsController.show("dash", tips.dash) then
		return
	end
	if activeSeconds >= 120 and TipsController.show("barrels", tips.barrels) then
		return
	end
	local profile = LockerController.profile
	if type(profile) ~= "table" then
		return
	end
	for _, id in WeaponConfig.order do
		local weapon = WeaponConfig.weapons[id]
		local owned = type(profile.ownedWeapons) == "table" and table.find(profile.ownedWeapons, id)
		if weapon.unlock == "shop" and not owned and profile.saving ~= false
			and number("Level") >= weapon.level and number("Coins") >= LockerController.priceOf(id)
		then
			if TipsController.show(`buy:{id}`, string.format(tips.buy, weapon.displayName)) then
				return
			end
		end
	end
	if profile.equippedAbility == nil and type(profile.unlockedAbilities) == "table" then
		for _, id in profile.unlockedAbilities do
			local ability = AbilityConfig[id]
			if ability and TipsController.show(`ability:{id}`, string.format(tips.ability, ability.displayName)) then
				return
			end
		end
	end
end

function TipsController.start()
	if started then
		return
	end
	started = true
	-- The experiment's default, until the player picks in Settings.
	local function applyExperiment()
		if not Settings.chosen.tips then
			Settings.tips = ExperimentConfig.valueOf("tips", player:GetAttribute("Exp_tips")) ~= false
		end
	end
	applyExperiment()
	player:GetAttributeChangedSignal("Exp_tips"):Connect(applyExperiment)
	InputController.DashPressed:Connect(function()
		dashed = true
	end)
	InputController.FireHeld:Connect(function()
		lastFireAt = os.clock()
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(1)
			if ClientState.isActive() then
				activeSeconds += dt
			end
			TipsController.check()
		end
	end)
end

return TipsController
