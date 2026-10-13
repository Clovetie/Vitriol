--!strict
-- SpatialHash.luau
-- Location: ReplicatedStorage > Vitriol > Lib > SpatialHash  (ModuleScript)
-- Purpose:  Fixed-cell spatial hash. Backs NoiseField (noise sources), creature
--           episodic memory (interest cells), and any "what is near me" lookup
--           that is NOT a physics query.
--
--           Use this instead of workspace:GetPartBoundsInRadius when the things
--           being tracked are logical points (noise impulses, memory cells)
--           rather than physical parts: it costs no physics and no Instance
--           access, so it is parallel-safe and unit-testable.
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Shared/NoiseField, Creature/Brain/Memory, Services/DestructionService

local SpatialHash = {}
SpatialHash.__index = SpatialHash

-- Cell coordinates are packed into one number so cells can be table keys without
-- allocating a string. Bounds keep the packed value well inside exact-double
-- range: (8192)^3 ~= 5.5e11 << 2^53.
local BIAS = 4096
local SPAN = 8192
local CELL_MIN = -4096
local CELL_MAX = 4095

local function packKey(cx: number, cy: number, cz: number): number
	return ((cx + BIAS) * SPAN + (cy + BIAS)) * SPAN + (cz + BIAS)
end

-- new(cellSize) -> SpatialHash
function SpatialHash.new(cellSize: number?)
	local self = setmetatable({}, SpatialHash)
	self.cellSize = (cellSize and cellSize > 0) and cellSize or 8
	self.invCell = 1 / self.cellSize
	self.entries = {}
	self.cells = {}
	self.size = 0
	return self
end

-- cellIndex(hash, v) -> integer, clamped into the packable range
function SpatialHash:cellIndex(v: number): number
	local c = math.floor(v * self.invCell)
	if c < CELL_MIN then
		return CELL_MIN
	elseif c > CELL_MAX then
		return CELL_MAX
	end
	return c
end

-- _addToCell / _removeFromCell
function SpatialHash:_addToCell(key: number, id: any): ()
	local bucket = self.cells[key]
	if bucket == nil then
		bucket = {}
		self.cells[key] = bucket
	end
	bucket[id] = true
end

function SpatialHash:_removeFromCell(key: number, id: any): ()
	local bucket = self.cells[key]
	if bucket == nil then
		return
	end
	bucket[id] = nil
	if next(bucket) == nil then
		self.cells[key] = nil
	end
end

-- insert(hash, id, x, y, z, entry?) -> entry
-- `entry` is stored as-is; callers typically pass { intensity, time, halflife }.
-- If omitted, one is created. Re-inserting an existing id moves it.
-- insert(hash, id, x, y, z, entry?) -> entry
-- Returns the entry that is now stored for `id`. If `id` already exists the entry
-- is MOVED, not duplicated - so a fresh entry table REPLACES the stored one.
-- Mutating the old table instead would leave self.entries[id] pointing at a table
-- whose coordinates were never updated, while the cell index came from the new
-- ones; queries would then report the stale position forever.
function SpatialHash:insert(id: any, x: number, y: number, z: number, entry: any?): any
	local existing = self.entries[id]
	if existing then
		self:_removeFromCell(existing.cell, id)
	else
		self.size += 1
	end

	local e = entry
	if e == nil then
		e = {}
	end
	e.x = x
	e.y = y
	e.z = z
	self.entries[id] = e

	local key = packKey(self:cellIndex(x), self:cellIndex(y), self:cellIndex(z))
	e.cell = key
	self:_addToCell(key, id)
	return e
end

-- move(hash, id, x, y, z) -> boolean
function SpatialHash:move(id: any, x: number, y: number, z: number): boolean
	local e = self.entries[id]
	if e == nil then
		return false
	end
	local key = packKey(self:cellIndex(x), self:cellIndex(y), self:cellIndex(z))
	if key ~= e.cell then
		self:_removeFromCell(e.cell, id)
		e.cell = key
		self:_addToCell(key, id)
	end
	e.x, e.y, e.z = x, y, z
	return true
end

-- remove(hash, id) -> boolean
function SpatialHash:remove(id: any): boolean
	local e = self.entries[id]
	if e == nil then
		return false
	end
	self:_removeFromCell(e.cell, id)
	self.entries[id] = nil
	self.size -= 1
	return true
end

-- get(hash, id) -> entry?
function SpatialHash:get(id: any): any
	return self.entries[id]
end

-- count(hash) -> number
function SpatialHash:count(): number
	return self.size
end

-- clear(hash) -> ()
function SpatialHash:clear(): ()
	self.entries = {}
	self.cells = {}
	self.size = 0
end

-- query(hash, x, y, z, radius, fn) -> number
-- Calls fn(id, entry, dx, dy, dz, distSq) for every entry whose centre is inside
-- the sphere. Allocates nothing: pass a closure or a bound method.
-- Returns the number of entries visited.
function SpatialHash:query(x: number, y: number, z: number, radius: number, fn: any): number
	if radius <= 0 or fn == nil then
		return 0
	end
	local rSq = radius * radius
	local cMinX = self:cellIndex(x - radius)
	local cMaxX = self:cellIndex(x + radius)
	local cMinY = self:cellIndex(y - radius)
	local cMaxY = self:cellIndex(y + radius)
	local cMinZ = self:cellIndex(z - radius)
	local cMaxZ = self:cellIndex(z + radius)

	local visited = 0
	for cx = cMinX, cMaxX do
		for cy = cMinY, cMaxY do
			for cz = cMinZ, cMaxZ do
				local bucket = self.cells[packKey(cx, cy, cz)]
				if bucket then
					for id in pairs(bucket) do
						local e = self.entries[id]
						if e then
							local dx = e.x - x
							local dy = e.y - y
							local dz = e.z - z
							local dSq = dx * dx + dy * dy + dz * dz
							if dSq <= rSq then
								visited += 1
								fn(id, e, dx, dy, dz, dSq)
							end
						end
					end
				end
			end
		end
	end
	return visited
end

-- queryNearest(hash, x, y, z, radius) -> id?, entry?, distSq?
function SpatialHash:queryNearest(x: number, y: number, z: number, radius: number): (any, any, number?)
	local bestId, bestEntry, bestSq = nil, nil, math.huge
	self:query(x, y, z, radius, function(id, e, _, _, _, dSq)
		if dSq < bestSq then
			bestId, bestEntry, bestSq = id, e, dSq
		end
	end)
	if bestId == nil then
		return nil, nil, nil
	end
	return bestId, bestEntry, bestSq
end

-- sampleDecay(hash, x, y, z, radius, now) -> number
-- Sums entry.intensity with exponential half-life decay:
--     contribution = intensity * 0.5 ^ ((now - time) / halflife)
-- Entries with no `time` are treated as permanent (no decay).
-- This is the core of NoiseField: one call answers "how loud is it here, on this
-- channel, right now?" (docs/02-MONSTER-DESIGN.md §2).
function SpatialHash:sampleDecay(x: number, y: number, z: number, radius: number, now: number): number
	local total = 0
	self:query(x, y, z, radius, function(_, e)
		local intensity = e.intensity
		if intensity and intensity > 0 then
			if e.time and e.halflife and e.halflife > 0 then
				local age = now - e.time
				if age < 0 then
					age = 0
				end
				total += intensity * (0.5 ^ (age / e.halflife))
			else
				total += intensity
			end
		end
	end)
	return total
end

-- prune(hash, now, maxAgeSeconds) -> number removed
-- Drops entries older than maxAgeSeconds. Called on the slow cadence, never per
-- frame (docs/01-ARCHITECTURE.md §4).
-- onRemove(id, entry) is optional and exists so callers that POOL their entries
-- (Shared/NoiseField) can hand them back instead of leaking them to the GC.
function SpatialHash:prune(now: number, maxAgeSeconds: number, onRemove: any?): number
	local expired = {}
	local n = 0
	for id, e in pairs(self.entries) do
		if e.time and (now - e.time) > maxAgeSeconds then
			n += 1
			expired[n] = id
		end
	end
	for i = 1, n do
		local id = expired[i]
		if onRemove then
			onRemove(id, self.entries[id])
		end
		self:remove(id)
	end
	return n
end

return SpatialHash
