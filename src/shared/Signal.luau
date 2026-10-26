-- A small in-process event: modules on the same machine tell each other
-- about changes without BindableEvents or a require cycle.
export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }
export type Signal<T...> = {
	Connect: (Signal<T...>, (T...) -> ()) -> Connection,
	Fire: (Signal<T...>, T...) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return (setmetatable({ handlers = {} }, Signal) :: any) :: Signal<T...>
end

function Signal:Connect(handler)
	local connection = { Connected = true }
	function connection.Disconnect(c)
		c.Connected = false
		local index = table.find(self.handlers, handler)
		if index then
			table.remove(self.handlers, index)
		end
	end
	table.insert(self.handlers, handler)
	return connection
end

-- Handlers run in their own threads, so one that errors or yields doesn't
-- stop the rest.
function Signal:Fire(...)
	for _, handler in table.clone(self.handlers) do
		task.spawn(handler, ...)
	end
end

return Signal
