-- Everything the server tells one player in words goes through UIMessage,
-- so the client has one place to show it. `kind` picks the style; `text` is
-- what it says.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIMessage = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UIMessage") :: RemoteEvent

export type Kind =
	"afkWarning" -- the big idle warning; `endsAt` is when they'll be moved
	| "afkClear" -- they moved again; take the warning down
	| "afkMoved" -- they were moved to spectators
	| "teamFull" -- both teams are full
	| "team" -- which team they joined or switched to, and why
	| "denied" -- a request the server turned down
	| "test" -- feedback from the test-only controls

local Messages = {}

function Messages.send(player: Player, kind: Kind, text: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { kind = kind, text = text }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	UIMessage:FireClient(player, payload)
end

return Messages
