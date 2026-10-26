-- The Season screen (FeatureFlags.SEASONS; SeasonConfig), from the SEASON
-- button top right while a season is on: the season's name and how long
-- it has left (real dates), the tier and the XP to the next one, the next
-- tiers' rewards, and this week's challenges with their progress. What
-- it shows comes from the server (ProgressEvent { kind = "season" }).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local SeasonConfig = require(Shared.Config.SeasonConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)

local C = UIConfig.colors
local GOLD = Color3.fromRGB(255, 200, 60)

local SeasonController = {}

SeasonController.parts = {} :: { [string]: any }
SeasonController.view = nil :: { [string]: any }?
local receivedAt = 0
local started = false

-- Seconds until the season ends, on the server's clock.
local function secondsLeft(view: { [string]: any }): number
	return view.endsAt - (view.serverNow or os.time()) - (os.clock() - receivedAt)
end

-- "12d 4h", "5h 20m", "40m".
function SeasonController.timeLeft(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days, hours, minutes = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m`
end

local function rewardText(tier: number): string
	local reward = SeasonConfig.tiers[tier]
	if not reward then
		return ""
	end
	local parts = { `{reward.coins} coins` }
	if reward.cosmetic then
		local cosmetic = ProgressionConfig.cosmetics[reward.cosmetic]
		table.insert(parts, if cosmetic then `{cosmetic.name} ({cosmetic.kind})` else reward.cosmetic)
	end
	if reward.badge then
		table.insert(parts, `the {reward.badge} badge`)
	end
	return `Tier {tier}: {table.concat(parts, " + ")}`
end

function SeasonController.render()
	local p = SeasonController.parts
	local view = SeasonController.view
	for _, child in p.list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if not view then
		p.title.Text = "SEASON"
		p.summary.Text = "No season is on right now."
		p.fill.Size = UDim2.new(0, 0, 1, 0)
		return
	end
	local tiers = #SeasonConfig.tiers
	local into = view.xp - view.tier * SeasonConfig.XP_PER_TIER
	p.title.Text = string.upper(view.name)
	p.summary.Text = if view.tier >= tiers then `Tier {tiers} of {tiers}: the whole track! Ends in {SeasonController.timeLeft(secondsLeft(view))}.`
		else `Tier {view.tier} of {tiers} · {into} / {SeasonConfig.XP_PER_TIER} season XP to the next · ends in {SeasonController.timeLeft(secondsLeft(view))}`
	p.fill.Size = UDim2.new(if view.tier >= tiers then 1 else math.clamp(into / SeasonConfig.XP_PER_TIER, 0, 1), 0, 1, 0)
	local order = 0
	local function line(text: string, color: Color3?, name: string?)
		order += 1
		UI.label(text, 15, {
			Name = name or `Line{order}`,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or C.text,
			Font = UIConfig.bodyFont,
			Parent = p.list,
		})
	end
	line("THIS WEEK", C.accent)
	for _, challenge in view.challenges do
		local mark = if challenge.done then "✓" else `{challenge.progress}/{challenge.goal}`
		line(`{mark}  {challenge.text} (+{SeasonConfig.XP_PER_CHALLENGE} season XP)`, if challenge.done then C.accent else C.text, `Challenge_{challenge.id}`)
	end
	line("NEXT REWARDS", GOLD)
	for tier = view.tier + 1, math.min(tiers, view.tier + 4) do
		line(rewardText(tier), nil, `Tier{tier}`)
	end
	line(`Season XP: {math.floor(SeasonConfig.XP_SHARE * 100)}% of all XP you earn, plus challenges. Free for everyone.`, C.muted)
	if view.saving == false then
		line("Progress isn't saving this session.", C.warning)
	end
end

function SeasonController.open()
	SeasonController.parts.screen.Enabled = true
	SeasonController.render()
end

function SeasonController.close()
	SeasonController.parts.screen.Enabled = false
end

local function build()
	local p = SeasonController.parts
	local screen = UI.screen("Season", 16)
	screen.Enabled = false
	p.screen = screen
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 620, 0, 440),
		BackgroundColor3 = C.panel,
		Parent = screen,
	}, { UI.corner(16), UI.stroke(GOLD, 4), UI.padding(16) })
	p.title = UI.label("SEASON", 26, { Name = "Title", TextColor3 = GOLD, Parent = panel })
	local close = UI.button("X", C.warning, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 40, 0, 40),
		Modal = true,
		Parent = panel,
	})
	UI.onClick(close, SeasonController.close)
	p.summary = UI.label("", 15, {
		Name = "Summary",
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, -50, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	local bar = UI.new("Frame", {
		Name = "Bar",
		Position = UDim2.new(0, 0, 0, 68),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = C.panelLight,
		Parent = panel,
	}, { UI.corner(7) })
	p.fill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = GOLD,
		Parent = bar,
	}, { UI.corner(7) })
	p.list = UI.new("Frame", {
		Name = "List",
		Position = UDim2.new(0, 0, 0, 94),
		Size = UDim2.new(1, 0, 1, -94),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, 4) })
end

function SeasonController.start()
	if started then
		return
	end
	started = true
	build()
	local remote = ClientState.remote("ProgressEvent") :: RemoteEvent
	remote.OnClientEvent:Connect(function(event)
		if type(event) == "table" and event.kind == "season" then
			SeasonController.view = event
			receivedAt = os.clock()
			if SeasonController.parts.screen.Enabled then
				SeasonController.render()
			end
		end
	end)
end

return SeasonController
