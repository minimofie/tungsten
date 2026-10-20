--[[
	Tungsten · base/signal
	Lightweight signals plus a "bin" that cleans up connections,
	instances, threads and callbacks in reverse order of addition.
]]

local T = ...

----------------------------------------------------------------------
-- Signal
----------------------------------------------------------------------

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _connections = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	assert(type(handler) == "function", "Signal:Connect expects a function")
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_handler = handler,
	}, Connection)
	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(handler: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- Snapshot so handlers may connect/disconnect while firing.
	local snapshot = table.clone(self._connections)
	for _, connection in snapshot do
		if connection.Connected then
			local ok, err = xpcall(connection._handler, debug.traceback, ...)
			if not ok and T.Log then
				T.Log.error("signal", "handler failed:\n" .. tostring(err))
			end
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._connections) do
		connection:Disconnect()
	end
end

Signal.Destroy = Signal.DisconnectAll

----------------------------------------------------------------------
-- Bin
----------------------------------------------------------------------

local Bin = {}
Bin.__index = Bin

function Bin.new()
	return setmetatable({ _items = {} }, Bin)
end

function Bin:Add<V>(item: V): V
	table.insert(self._items, item)
	return item
end

local function dispose(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" and item ~= coroutine.running() then
			task.cancel(item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Bin:Clean()
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		local ok, err = pcall(dispose, items[index])
		if not ok and T.Log then
			T.Log.warn("signal", "cleanup step failed: " .. tostring(err))
		end
	end
end

Bin.Destroy = Bin.Clean

return {
	new = Signal.new,
	bin = Bin.new,
	Signal = Signal,
	Bin = Bin,
}
