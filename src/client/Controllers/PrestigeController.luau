-- The Prestige screen (FeatureFlags.PRESTIGE; PrestigeConfig): the
-- server's exact preview of what resets and what stays, then two presses
-- to confirm (the second says it can't be undone). The server does the
-- reset and saves it before answering.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local UI = require(Client.UI)
local HealthController = require(script.Parent.HealthController)

local C = UIConfig.colors

local PrestigeController = {}

PrestigeController.parts = {} :: { [string]: any }
PrestigeController.preview = nil :: { [string]: any }?
-- 0: looking; 1: pressed PRESTIGE once (the next press confirms).
PrestigeController.stage = 0
PrestigeController.busy = false

local token: string? = nil
local started = false

local function commas(n: number): string
	local text = tostring(math.floor(n))
	while true do
		local replaced, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			return text
		end
	end
end

local function ask(action: string, value: string?): { [string]: any }
	local remote = ClientState.remote("PrestigeRequest") :: RemoteFunction
	local sentAt = os.clock()
	local ok, answer = pcall(remote.InvokeServer, remote, action, value)
	HealthController.noteLatency(os.clock() - sentAt)
	return if ok and type(answer) == "table" then answer else { ok = false, message = "Couldn't reach the server. Try again." }
end

-- The preview as lines of text.
function PrestigeController.lines(preview: { [string]: any }): { string }
	local resets, keeps, rewards = preview.resets, preview.keeps, preview.rewards
	local weapons = {}
	for _, id in resets.weapons do
		local weapon = WeaponConfig.weapons[id]
		table.insert(weapons, if weapon then weapon.displayName else id)
	end
	local coinsLine = `Coins {commas(resets.coins)} → {commas(resets.keptCoins)}`
	if resets.keptCoins > 0 then
		coinsLine ..= " (store coins you haven't spent are kept)"
	end
	local reward = { `the Prestige {preview.rank} badge` }
	if rewards.cosmetic then
		local cosmetic = ProgressionConfig.cosmetics[rewards.cosmetic]
		table.insert(reward, `the {if cosmetic then cosmetic.name else rewards.cosmetic} {if cosmetic then cosmetic.kind else ""}`)
	end
	return {
		`RESETS: Level {resets.level} → 1 · {commas(resets.xp)} XP → 0 · {coinsLine}`,
		`Weapons back to the Gas Blaster: {if #weapons > 0 then table.concat(weapons, ", ") else "none bought"} (buy them again with coins)`,
		`KEEPS: {keeps.cosmetics} cosmetics · {commas(keeps.lifetimeXP)} lifetime XP · {commas(keeps.eliminations)} eliminations · {keeps.badges} badges · {keeps.abilities} abilities · your passes and purchases`,
		`YOU GET: {table.concat(reward, " and ")}. No extra power: prestige is for show.`,
	}
end

local function render()
	local p = PrestigeController.parts
	local preview = PrestigeController.preview
	for _, child in p.body:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if preview then
		p.title.Text = `PRESTIGE {preview.rank}`
		for i, line in PrestigeController.lines(preview) do
			UI.label(line, 15, {
				Name = `Line{i}`,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = UIConfig.bodyFont,
				Parent = p.body,
			})
		end
	end
	p.confirm.Text = if PrestigeController.stage == 1 then "YES, RESET ME (CAN'T BE UNDONE)" else "PRESTIGE"
	UI.setEnabled(p.confirm, preview ~= nil and not PrestigeController.busy)
end
PrestigeController.render = render

local function setNote(text: string, color: Color3?)
	local p = PrestigeController.parts
	p.note.Text = text
	p.note.TextColor3 = color or C.muted
end

-- Opens the screen with a fresh preview from the server.
function PrestigeController.open()
	local p = PrestigeController.parts
	p.screen.Enabled = true
	PrestigeController.stage = 0
	PrestigeController.preview = nil
	setNote("Checking...")
	render()
	local answer = ask("preview")
	if answer.ok and type(answer.preview) == "table" and type(answer.token) == "string" then
		PrestigeController.preview = answer.preview
		token = answer.token
		setNote("Read it all: this resets your level, coins and weapons.")
	else
		setNote(tostring(answer.message), C.warning)
	end
	render()
end

function PrestigeController.close()
	PrestigeController.parts.screen.Enabled = false
	PrestigeController.stage = 0
	token = nil
end

-- The PRESTIGE button: the first press asks again, the second does it.
function PrestigeController.press(): { [string]: any }?
	if not (PrestigeController.preview and token) or PrestigeController.busy then
		return nil
	end
	if PrestigeController.stage == 0 then
		PrestigeController.stage = 1
		setNote("Are you sure? Press again to prestige.", C.warning)
		render()
		return nil
	end
	PrestigeController.busy = true
	render()
	local answer = ask("confirm", token)
	PrestigeController.busy = false
	token = nil
	PrestigeController.stage = 0
	if answer.ok then
		PrestigeController.preview = nil
		setNote(`{answer.message} You're Prestige {answer.rank}.`, C.accent)
	else
		setNote(tostring(answer.message), C.warning)
	end
	render()
	return answer
end

local function build()
	local p = PrestigeController.parts
	local screen = UI.screen("Prestige", 17)
	screen.Enabled = false
	p.screen = screen
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 600, 0, 400),
		BackgroundColor3 = C.panel,
		Parent = screen,
	}, { UI.corner(16), UI.stroke(Color3.fromRGB(255, 140, 60), 4), UI.padding(16) })
	p.title = UI.label("PRESTIGE", 30, { Name = "Title", TextColor3 = Color3.fromRGB(255, 160, 70), Parent = panel })
	p.body = UI.new("Frame", {
		Name = "Body",
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 1, -150),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, 8) })
	p.note = UI.label("", 15, {
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -58),
		Size = UDim2.new(1, 0, 0, 36),
		TextWrapped = true,
		Font = UIConfig.bodyFont,
		Parent = panel,
	})
	local cancel = UI.button("CANCEL", C.panelLight, {
		Name = "Cancel",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0, 180, 0, 48),
		Modal = true,
		Parent = panel,
	})
	UI.onClick(cancel, PrestigeController.close)
	p.confirm = UI.button("PRESTIGE", Color3.fromRGB(230, 110, 40), {
		Name = "Confirm",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 360, 0, 48),
		TextSize = 18,
		Parent = panel,
	})
	UI.onClick(p.confirm, function()
		PrestigeController.press()
	end)
end

function PrestigeController.start()
	if started then
		return
	end
	started = true
	build()
	render()
end

return PrestigeController
