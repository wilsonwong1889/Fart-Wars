-- Spreads a burst of work over a moment instead of one frame. A new
-- round's spawns go through here (players and bots): every avatar is a few
-- hundred instances for every client to receive, so all of them at once
-- was a hitch on every screen as the round started.
local Spread = {}

local random = Random.new()

-- Calls `fn(item)` for each of `items`: the first at once, the rest evenly
-- after it, the last `seconds` later.
function Spread.over<T>(seconds: number, items: { T }, fn: (T) -> ())
	local count = #items
	for i, item in items do
		local delay = if count > 1 then seconds * (i - 1) / (count - 1) else 0
		if delay <= 0 then
			task.spawn(fn, item)
		else
			task.delay(delay, fn, item)
		end
	end
end

-- One list from `groups` (a team's players, say), taking turns: each group
-- in a random order, a random group first, so no group always goes first
-- or last.
function Spread.alternate<T>(groups: { { T } }): { T }
	local lists = {}
	for _, group in groups do
		if #group > 0 then
			local list = table.clone(group)
			random:Shuffle(list)
			table.insert(lists, list)
		end
	end
	random:Shuffle(lists)
	local out = {}
	local index = 1
	local left = true
	while left do
		left = false
		for _, list in lists do
			local item = list[index]
			if item ~= nil then
				table.insert(out, item)
				left = true
			end
		end
		index += 1
	end
	return out
end

return Spread
