-- Low detail (Settings): no shadows on this PC, and fewer effects (the
-- effects check Settings.lowDetail themselves). Lighting changed here is
-- local to this client.
local Lighting = game:GetService("Lighting")

local Settings = require(script.Parent.Settings)

local Detail = {}

local originalShadows: boolean? = nil

function Detail.apply()
	if originalShadows == nil then
		originalShadows = Lighting.GlobalShadows
	end
	Lighting.GlobalShadows = if Settings.lowDetail then false else originalShadows :: boolean
end

return Detail
