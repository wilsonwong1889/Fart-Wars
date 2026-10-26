-- How often a player may do something with a fixed interval (a weapon's
-- fire interval, a cooldown), judged on the server by when requests
-- arrive. A small bucket that refills one use per interval: a request
-- needs a whole use. The bucket holds a little more than one use (`slack`
-- seconds' worth), so network jitter that bunches two honest requests
-- together isn't refused, but over any stretch of time nobody gets more
-- than one use per interval (plus that slack), however they time them.
local Cadence = {}

export type State = { uses: number, at: number }

function Cadence.new(): State
	return { uses = math.huge, at = 0 }
end

-- Whether a use at `at` is allowed; takes it if so.
function Cadence.take(state: State, interval: number, slack: number, at: number): boolean
	local capacity = 1 + slack / interval
	local uses = math.min(capacity, state.uses + (at - state.at) / interval)
	state.at = at
	if uses < 1 then
		state.uses = uses
		return false
	end
	state.uses = uses - 1
	return true
end

-- When the next use will be allowed (for showing a cooldown).
function Cadence.readyAt(state: State, interval: number, slack: number): number
	local capacity = 1 + slack / interval
	local uses = math.min(capacity, state.uses)
	return if uses >= 1 then state.at else state.at + (1 - uses) * interval
end

return Cadence
