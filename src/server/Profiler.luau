-- What the server's hot paths cost (masterplan 5.2): how often each runs
-- and how long it takes (average and worst, in milliseconds). Health's
-- loops are timed per tick (loop.<name>), and the other hot paths are
-- timed where they run (Combat.fire, Data.save). Read it with `/fw perf`,
-- or in Health's report (the costliest few). Cheap enough to leave on:
-- two os.clock() calls per run.
local Profiler = {}

type Entry = { count: number, total: number, max: number }
local entries: { [string]: Entry } = {}

function Profiler.record(name: string, seconds: number)
	local entry = entries[name]
	if not entry then
		entry = { count = 0, total = 0, max = 0 }
		entries[name] = entry
	end
	entry.count += 1
	entry.total += seconds
	if seconds > entry.max then
		entry.max = seconds
	end
end

-- `fn`, timed under `name` on every call.
function Profiler.wrap<A..., R...>(name: string, fn: (A...) -> R...): (A...) -> R...
	return function(...: A...): R...
		local started = os.clock()
		local results = table.pack(fn(...))
		Profiler.record(name, os.clock() - started)
		return table.unpack(results, 1, results.n)
	end :: any
end

export type Cost = { name: string, count: number, averageMs: number, maxMs: number, totalMs: number }

-- Every path so far, costliest (total time) first.
function Profiler.costs(): { Cost }
	local list = {}
	for name, entry in entries do
		table.insert(list, {
			name = name,
			count = entry.count,
			averageMs = math.floor(entry.total / math.max(entry.count, 1) * 1e5) / 100,
			maxMs = math.floor(entry.max * 1e5) / 100,
			totalMs = math.floor(entry.total * 1e5) / 100,
		})
	end
	table.sort(list, function(a, b)
		return a.totalMs > b.totalMs
	end)
	return list
end

function Profiler.reset()
	table.clear(entries)
end

return Profiler
