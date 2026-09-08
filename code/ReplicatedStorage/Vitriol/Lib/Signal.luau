--!strict
-- Signal.luau
-- Location: ReplicatedStorage > Vitriol > Lib > Signal  (ModuleScript)
-- Purpose:  Minimal observable. Used INSTEAD of BindableEvent everywhere except
--           when crossing an Actor boundary (docs/01-ARCHITECTURE.md §8.6).
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  all Services, CreatureCore, client Controllers

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Signal.new()
	local self = setmetatable({}, Signal)
	self._handlers = {}
	self._count = 0
	self._firing = false
	self._pendingRemoval = false
	return self
end

-- connect(signal, fn) -> connection
function Signal:connect(fn: any): any
	local conn = setmetatable({ _signal = self, _fn = fn, _connected = true }, Connection)
	self._count += 1
	self._handlers[self._count] = conn
	return conn
end

-- once(signal, fn) -> connection
function Signal:once(fn: any): any
	local conn
	conn = self:connect(function(...)
		conn:disconnect()
		fn(...)
	end)
	return conn
end

-- fire(signal, ...) -> ()
--
-- The loop bound is captured once, so a handler that connects during a fire is
-- NOT called until the next fire (the standard, least-surprising semantics).
-- A handler that disconnects during a fire is skipped via the _connected check,
-- and the array is compacted only after the fire completes so indices stay valid
-- for the rest of this pass.
function Signal:fire(...): ()
	if self._count == 0 then
		return
	end
	self._firing = true
	local n = self._count
	for i = 1, n do
		local conn = self._handlers[i]
		if conn and conn._connected then
			conn._fn(...)
		end
	end
	self._firing = false
	if self._pendingRemoval then
		self._pendingRemoval = false
		self:_compact()
	end
end

-- disconnect(connection) -> ()
function Connection:disconnect(): ()
	if not self._connected then
		return
	end
	self._connected = false
	local sig = self._signal
	if sig == nil then
		return
	end
	if sig._firing then
		sig._pendingRemoval = true
	else
		sig:_compact()
	end
end

function Connection:isConnected(): boolean
	return self._connected
end

-- disconnectAll(signal) -> ()
function Signal:disconnectAll(): ()
	for i = 1, self._count do
		local conn = self._handlers[i]
		if conn then
			conn._connected = false
			conn._signal = nil
		end
		self._handlers[i] = nil
	end
	self._count = 0
end

-- _compact(signal) -> ()
-- Removes disconnected entries while preserving order.
--
-- NOTE the `read > write` guard: when no entries have been removed yet, write
-- equals read, and clearing slot [read] unconditionally would erase the entry
-- that was just written to the same slot.
function Signal:_compact(): ()
	local write = 0
	for read = 1, self._count do
		local conn = self._handlers[read]
		if conn and conn._connected then
			write += 1
			self._handlers[write] = conn
		end
		if read > write then
			self._handlers[read] = nil
		end
	end
	self._count = write
end

-- handlerCount(signal) -> number
function Signal:handlerCount(): number
	return self._count
end

return Signal
