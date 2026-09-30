--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/Signal (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- A minimal synchronous signal. Deliberately NOT BindableEvent-backed:
--   * BindableEvent round-trips arguments through Roblox serialisation, which
--     copies tables and loses identity;
--   * it defers, which breaks the one-scheduler rule (doc 01 section 5);
--   * it cannot be tested headlessly.
--
-- Handlers fire synchronously, in connection order, and an error in one
-- handler does not prevent the rest from running -- the error is collected and
-- re-raised after the fire completes, so a bad listener cannot silently eat an
-- event.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Signal.new(name)
	local self = setmetatable({}, Signal)
	self.name = name or "signal"
	self._handlers = {}
	self._count = 0
	self._firing = false
	self._dirty = false
	return self
end

function Connection:disconnect()
	if not self._connected then
		return false
	end
	self._connected = false
	self._signal._dirty = true
	if not self._signal._firing then
		self._signal:_compact()
	end
	return true
end

Connection.Disconnect = Connection.disconnect

function Signal:_compact()
	local handlers = self._handlers
	local write = 0
	for i = 1, self._count do
		local c = handlers[i]
		if c._connected then
			write = write + 1
			handlers[write] = c
		end
	end
	for i = write + 1, self._count do
		handlers[i] = nil
	end
	self._count = write
	self._dirty = false
end

function Signal:connect(fn)
	assert(type(fn) == "function", "Signal:connect expects a function")
	local c = setmetatable({}, Connection)
	c._signal = self
	c._fn = fn
	c._connected = true
	c._once = false
	self._count = self._count + 1
	self._handlers[self._count] = c
	return c
end

Signal.Connect = Signal.connect

function Signal:once(fn)
	local c = self:connect(fn)
	c._once = true
	return c
end

function Signal:fire(a, b, c, d)
	if self._count == 0 then
		return 0
	end
	self._firing = true
	local handlers = self._handlers
	-- Snapshot the length: handlers connected during this fire run next time,
	-- which keeps a self-connecting listener from looping forever.
	local n = self._count
	local delivered = 0
	local firstError = nil
	for i = 1, n do
		local conn = handlers[i]
		if conn and conn._connected then
			if conn._once then
				conn._connected = false
				self._dirty = true
			end
			local ok, err = pcall(conn._fn, a, b, c, d)
			delivered = delivered + 1
			if not ok and firstError == nil then
				firstError = err
			end
		end
	end
	self._firing = false
	if self._dirty then
		self:_compact()
	end
	if firstError ~= nil then
		error(string.format("Signal(%s) handler error: %s", tostring(self.name), tostring(firstError)), 0)
	end
	return delivered
end

Signal.Fire = Signal.fire

function Signal:connectionCount()
	if self._dirty and not self._firing then
		self:_compact()
	end
	return self._count
end

function Signal:destroy()
	for i = 1, self._count do
		local c = self._handlers[i]
		if c then
			c._connected = false
		end
		self._handlers[i] = nil
	end
	self._count = 0
	self._dirty = false
end

Signal.Destroy = Signal.destroy
Signal.Connection = Connection

return Signal
