-- Drops requests a player sends faster than once per `seconds`, per kind of
-- request. Clients only ever ask; this keeps a spammed button cheap.
local RateLimit = {}
RateLimit.__index = RateLimit

type Fields = { seconds: number, last: { [Player]: { [string]: number } } }
export type RateLimit = typeof(setmetatable({} :: Fields, RateLimit))

function RateLimit.new(seconds: number): RateLimit
	local fields: Fields = { seconds = seconds, last = setmetatable({}, { __mode = "k" }) :: any }
	return setmetatable(fields, RateLimit)
end

function RateLimit.allow(self: RateLimit, player: Player, kind: string): boolean
	local now = os.clock()
	local times = self.last[player]
	if not times then
		times = {}
		self.last[player] = times
	end
	local previous = times[kind]
	if previous and now - previous < self.seconds then
		return false
	end
	times[kind] = now
	return true
end

function RateLimit.forget(self: RateLimit, player: Player)
	self.last[player] = nil
end

return RateLimit
