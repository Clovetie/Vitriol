--!strict
-- Tables.luau
-- Location: ReplicatedStorage > Vitriol > Lib > Tables  (ModuleScript)
-- Purpose:  Object pooling and table helpers. The frame path must allocate ZERO
--           tables (docs/01-ARCHITECTURE.md §4), which is what Pool is for.
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Creature/Body/TendrilRig, Brain/Memory, Services/DestructionService

local Tables = {}

local Pool = {}
Pool.__index = Pool

-- newPool(factory, prealloc?) -> Pool
-- factory() must return a fresh, reset object. Objects handed back via :release()
-- are NOT reset - the borrower is responsible for overwriting what it reads, so
-- the pool stays allocation-free and branch-free in the hot path.
function Tables.newPool(factory: any, prealloc: number?)
	local self = setmetatable({}, Pool)
	self.factory = factory
	self.free = {}
	self.freeCount = 0
	self.created = 0
	local n = prealloc or 0
	for _ = 1, n do
		self.freeCount += 1
		self.created += 1
		self.free[self.freeCount] = factory()
	end
	return self
end

-- get(pool) -> object
function Pool:get(): any
	if self.freeCount > 0 then
		local obj = self.free[self.freeCount]
		self.free[self.freeCount] = nil
		self.freeCount -= 1
		return obj
	end
	self.created += 1
	return self.factory()
end

-- release(pool, obj) -> ()
function Pool:release(obj: any): ()
	self.freeCount += 1
	self.free[self.freeCount] = obj
end

-- Stats for Profiler / telemetry.
function Pool:stats(): any
	return { free = self.freeCount, created = self.created }
end

-- shallowCopy(t) -> new table (one level)
function Tables.shallowCopy(t: any): any
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- deepFreeze(t) -> t
-- Freezes recursively. Config modules should be frozen at boot so a stray write
-- in gameplay code fails loudly instead of silently desyncing every client.
function Tables.deepFreeze(t: any): any
	if type(t) ~= "table" then
		return t
	end
	for _, v in pairs(t) do
		if type(v) == "table" then
			Tables.deepFreeze(v)
		end
	end
	-- table.freeze exists in Luau; guard so the module still loads in plain Lua
	-- test harnesses that do not provide it.
	if table.freeze then
		table.freeze(t)
	end
	return t
end

-- count(t) -> number
-- Length of a hash table (# is meaningless on those; see the Temperament test in
-- tools/vitriol/tests.luau for the bug this prevents).
function Tables.count(t: any): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

-- copyArray(t) -> new array
function Tables.copyArray(t: any): any
	local n = #t
	local out = table.create(n)
	for i = 1, n do
		out[i] = t[i]
	end
	return out
end

return Tables
