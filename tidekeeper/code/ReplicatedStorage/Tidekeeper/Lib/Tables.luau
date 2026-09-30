--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/Tables (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- Table utilities with a determinism bias. The important ones are
-- `sortedKeys`/`sortedPairs` (never iterate a hash table with raw `pairs` where
-- order affects output) and `insertionSort` (Lua's `table.sort` is quicksort
-- and is NOT stable, so equal-scoring shelf items could swap between runs).

local Tables = {}

local floor = math.floor

function Tables.isArray(t)
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

function Tables.count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

function Tables.copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

function Tables.deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			out[k] = Tables.deepCopy(v)
		else
			out[k] = v
		end
	end
	return out
end

function Tables.deepFreeze(t)
	if type(t) ~= "table" then
		return t
	end
	for _, v in pairs(t) do
		if type(v) == "table" then
			Tables.deepFreeze(v)
		end
	end
	-- `table.isfrozen` and `table.freeze` exist in Luau; the harness shims them
	-- as no-ops so this file loads unchanged in both environments.
	if table.freeze and not (table.isfrozen and table.isfrozen(t)) then
		table.freeze(t)
	end
	return t
end

-- Structural equality. Used by the replay proof to compare two resolved states
-- without serialising them first.
function Tables.deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not Tables.deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Deterministic key ordering. Numbers sort before strings; within a type the
-- natural order applies. Returns a fresh array, so this is NOT for hot paths.
function Tables.sortedKeys(t)
	local keys = {}
	local n = 0
	for k in pairs(t) do
		n = n + 1
		keys[n] = k
	end
	table.sort(keys, function(x, y)
		local tx = type(x)
		local ty = type(y)
		if tx ~= ty then
			return tx < ty
		end
		return x < y
	end)
	return keys
end

-- Stateful iterator over a hash table in deterministic key order.
function Tables.sortedPairs(t)
	local keys = Tables.sortedKeys(t)
	local i = 0
	return function()
		i = i + 1
		local k = keys[i]
		if k == nil then
			return nil
		end
		return k, t[k]
	end
end

-- STABLE sort of `arr[1..n]` using `less(a, b)`. Insertion sort: O(n^2) in the
-- worst case, but `n` here is at most a couple of dozen shelf items, and
-- stability is worth far more than asymptotics when the output is money.
function Tables.insertionSort(arr, n, less)
	for i = 2, n do
		local value = arr[i]
		local j = i - 1
		while j >= 1 and less(value, arr[j]) do
			arr[j + 1] = arr[j]
			j = j - 1
		end
		arr[j + 1] = value
	end
	return arr
end

-- Parallel-array variant: sorts `keys[1..n]` ascending and applies the same
-- permutation to `payload`. Allocation-free, which is why the match stage uses
-- it instead of building comparator closures.
function Tables.insertionSortPairs(keys, payload, n)
	for i = 2, n do
		local k = keys[i]
		local p = payload[i]
		local j = i - 1
		while j >= 1 and keys[j] > k do
			keys[j + 1] = keys[j]
			payload[j + 1] = payload[j]
			j = j - 1
		end
		keys[j + 1] = k
		payload[j + 1] = p
	end
end

-- Binary search over a dense array sorted ascending by `arr[i][field]`.
-- Returns (index, found). When not found, `index` is the insertion point.
function Tables.binarySearch(arr, n, field, target)
	local lo = 1
	local hi = n
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local v = arr[mid][field]
		if v == target then
			return mid, true
		elseif v < target then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return lo, false
end

function Tables.indexOf(arr, n, value)
	for i = 1, n do
		if arr[i] == value then
			return i
		end
	end
	return 0
end

-- Fill `arr[1..n]` with `value` without reallocating.
function Tables.fill(arr, n, value)
	for i = 1, n do
		arr[i] = value
	end
	return arr
end

-- A tiny fixed-capacity object pool. `factory` builds one object; `reset`
-- clears it for reuse. Used by `Visit.newContext` so the hot path allocates
-- once per session instead of once per visit.
local Pool = {}
Pool.__index = Pool

function Tables.pool(factory, reset, capacity)
	local self = setmetatable({}, Pool)
	self.factory = factory
	self.reset = reset
	self.capacity = capacity or 32
	self.free = {}
	self.freeCount = 0
	self.made = 0
	return self
end

function Pool:acquire()
	if self.freeCount > 0 then
		local obj = self.free[self.freeCount]
		self.free[self.freeCount] = nil
		self.freeCount = self.freeCount - 1
		return obj
	end
	self.made = self.made + 1
	return self.factory()
end

function Pool:release(obj)
	if self.reset then
		self.reset(obj)
	end
	if self.freeCount >= self.capacity then
		return false
	end
	self.freeCount = self.freeCount + 1
	self.free[self.freeCount] = obj
	return true
end

function Pool:size()
	return self.freeCount
end

Tables.Pool = Pool

return Tables
