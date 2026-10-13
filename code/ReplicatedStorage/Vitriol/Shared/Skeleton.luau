--!strict
-- Skeleton.luau
-- Location: ReplicatedStorage > Vitriol > Shared > Skeleton  (ModuleScript)
-- Purpose:  The creature's logical joint chain. One Skeleton per tendril; a
--           TendrilRig owns N of them plus the core transform.
--           Flat arrays, no Instances, no per-frame allocation
--           (docs/03-MONSTER-TECH.md §2).
--
--           Deliberately a SUPERSET of the chain shape Lib/Fabrik operates on
--           ({count, x, y, z, len}). Fabrik.solve(skeleton, ...) therefore works
--           directly with no adapter: Skeleton only adds the fields FABRIK does
--           not need (visual taper, bend-plane reference, dirty flag).
--
--           Why flat arrays and not {Vector3}: 96 joints x 60 Hz is 5,760 Vector3
--           constructions per second per creature if you allocate. Three parallel
--           number arrays reuse their storage for free, and the arrays are also
--           what SkeletonCodec walks when it packs a snapshot.
-- Requires: (none)
-- Used by:  Creature/Body/TendrilRig, Shared/SkeletonCodec, Creature/Brain/Reach

local Skeleton = {}
Skeleton.__index = Skeleton

local DEFAULTS = {
	segmentLength = 2.0,
	rootRadius = 0.55,
	tipRadius = 0.05,
	upX = 0,
	upY = 1,
	upZ = 0,
	-- Rest pose: the origin, extending along +Z. Any direction works - what matters
	-- is that a fresh chain is STRAIGHT. All-zero construction (the obvious choice)
	-- produces a fully collapsed chain, and every consumer of it then reads
	-- totalLength() from a pose that cannot exist: FABRIK's unreachable branch, the
	-- codec's core-relative offsets and the reach checks in Locomotion all silently
	-- operate on a knot. reset() returns to this pose for the same reason.
	restX = 0,
	restY = 0,
	restZ = 0,
	dirX = 0,
	dirY = 0,
	dirZ = 1,
}

-- Normalise in place; returns false if the vector is degenerate (caller keeps
-- the previous up rather than getting a NaN that would poison every solve).
local function normalizeInto(t: any, x: number, y: number, z: number): boolean
	local m = math.sqrt(x * x + y * y + z * z)
	if m < 1e-6 then
		return false
	end
	t.x = x / m
	t.y = y / m
	t.z = z / m
	return true
end

-- new(count, opts?) -> Skeleton
-- count is clamped to >= 2: a 1-joint chain has no bones, and every bone length
-- read would index past the end (the same trap Fabrik.newChain guards against).
function Skeleton.new(count: number, opts: any?)
	local o = opts or {}
	local n = count
	if n == nil or n < 2 then
		n = 2
	end
	n = math.floor(n)

	local self = setmetatable({}, Skeleton)
	self.count = n
	self.x = {}
	self.y = {}
	self.z = {}
	self.len = {}
	self.radius = {}
	self.dirty = true

	local seg = o.segmentLength or DEFAULTS.segmentLength
	for i = 1, n do
		self.x[i] = 0
		self.y[i] = 0
		self.z[i] = 0
		if i < n then
			self.len[i] = seg
		end
	end

	-- The pose reset() returns to. Read as Vector3s when given (TendrilRig has one
	-- on hand), as three numbers otherwise; both are plain data, so the module stays
	-- free of any Instance or service reference.
	local ro = o.restOrigin
	local rd = o.restDirection
	self.restX = ro and ro.X or DEFAULTS.restX
	self.restY = ro and ro.Y or DEFAULTS.restY
	self.restZ = ro and ro.Z or DEFAULTS.restZ
	self.dirX = rd and rd.X or DEFAULTS.dirX
	self.dirY = rd and rd.Y or DEFAULTS.dirY
	self.dirZ = rd and rd.Z or DEFAULTS.dirZ

	self:setTaper(o.rootRadius or DEFAULTS.rootRadius, o.tipRadius or DEFAULTS.tipRadius)
	self.upX = o.upX or DEFAULTS.upX
	self.upY = o.upY or DEFAULTS.upY
	self.upZ = o.upZ or DEFAULTS.upZ
	-- Lay the chain out along the rest direction instead of leaving it collapsed.
	self:straighten(self.restX, self.restY, self.restZ, self.dirX, self.dirY, self.dirZ)
	return self
end

-- setLengths(skel, segmentLength) -> ()
function Skeleton:setLengths(segmentLength: number): ()
	for i = 1, self.count - 1 do
		self.len[i] = segmentLength
	end
	self.dirty = true
end

-- totalLength(skel) -> number
-- Reach of the tendril when fully extended. Drives target selection: a tendril
-- cannot grab what is further than this from its base.
function Skeleton:totalLength(): number
	local total = 0
	for i = 1, self.count - 1 do
		total += self.len[i]
	end
	return total
end

-- setTaper(skel, rootRadius, tipRadius) -> ()
-- Geometric taper from base to tip. Geometric (not linear) because tendrils thin
-- fast near the base and then hold a roughly constant fine gauge; a linear taper
-- reads as a traffic cone.
function Skeleton:setTaper(rootRadius: number, tipRadius: number): ()
	local n = self.count
	local r0 = rootRadius
	local r1 = tipRadius
	if r0 <= 0 then
		r0 = 1e-3
	end
	if r1 <= 0 then
		r1 = 1e-3
	end
	if n == 1 then
		self.radius[1] = r0
		return
	end
	local ratio = r1 / r0
	local steps = n - 1
	for i = 1, n do
		-- r0 * ratio^((i-1)/steps)
		self.radius[i] = r0 * (ratio ^ ((i - 1) / steps))
	end
end

-- radiusAt(skel, i) -> number
function Skeleton:radiusAt(i: number): number
	local idx = i
	if idx < 1 then
		idx = 1
	elseif idx > self.count then
		idx = self.count
	end
	return self.radius[idx] or 0
end

-- setUp(skel, x, y, z) -> boolean
-- The bend-plane reference that stops a tendril from flipping through itself when
-- FABRIK's plane is degenerate (docs/03 §3.2). Returns false and keeps the old
-- value if the input is degenerate.
function Skeleton:setUp(x: number, y: number, z: number): boolean
	local n = math.sqrt(x * x + y * y + z * z)
	if n < 1e-6 then
		return false
	end
	self.upX = x / n
	self.upY = y / n
	self.upZ = z / n
	return true
end

-- straighten(skel, ox, oy, oz, dx, dy, dz) -> ()
-- Lays the chain out from 'o' along 'd', fully extended. Used at spawn and when a
-- tendril is released, so the first frame is a clean line rather than a knot.
function Skeleton:straighten(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): ()
	local m = math.sqrt(dx * dx + dy * dy + dz * dz)
	if m < 1e-6 then
		dx, dy, dz = 0, 0, 1
		m = 1
	end
	local ux, uy, uz = dx / m, dy / m, dz / m
	local dist = 0
	for i = 1, self.count do
		self.x[i] = ox + ux * dist
		self.y[i] = oy + uy * dist
		self.z[i] = oz + uz * dist
		if i < self.count then
			dist += self.len[i]
		end
	end
	self.dirty = true
end

-- setRestPose(skel, ox, oy, oz, dx, dy, dz) -> ()
-- Remembers the pose reset() returns to. TendrilRig calls this once when the rig is
-- built (root attach point on the core + the hang direction the genome implies), so
-- a released or wounded tendril returns to ITS pose and not to a generic one.
function Skeleton:setRestPose(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): ()
	self.restX = ox
	self.restY = oy
	self.restZ = oz
	self.dirX = dx
	self.dirY = dy
	self.dirZ = dz
end

-- restPose(skel) -> ox, oy, oz, dx, dy, dz
function Skeleton:restPose(): (number, number, number, number, number, number)
	return self.restX, self.restY, self.restZ, self.dirX, self.dirY, self.dirZ
end

-- reset(skel) -> ()
-- Back to the rest pose. Used at spawn, when a tendril releases its anchor, when
-- the creature dies, and by the pool when a Skeleton is recycled. It deliberately
-- does NOT touch lengths, taper or the bend-plane reference: those are genome data
-- replicated once at spawn, and a reset that silently re-authored them would let a
-- client-side re-initialisation disagree with the server's rig.
--
-- It re-lays-out rather than zeroing, for the reason documented in DEFAULTS: a
-- zeroed chain is a knot, and a knot is a legal-looking input to every consumer.
function Skeleton:reset(): ()
	self:straighten(self.restX, self.restY, self.restZ, self.dirX, self.dirY, self.dirZ)
end

-- setJoint(skel, i, x, y, z) -> ()
function Skeleton:setJoint(i: number, x: number, y: number, z: number): ()
	if i < 1 or i > self.count then
		return
	end
	self.x[i] = x
	self.y[i] = y
	self.z[i] = z
	self.dirty = true
end

-- jointDistance(skel, i, x, y, z) -> number
function Skeleton:jointDistance(i: number, x: number, y: number, z: number): number
	local idx = i
	if idx < 1 then
		idx = 1
	elseif idx > self.count then
		idx = self.count
	end
	local dx = self.x[idx] - x
	local dy = self.y[idx] - y
	local dz = self.z[idx] - z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- tipX/tipY/tipZ(skel) -> number
-- Separate accessors rather than one multi-return 'tip()': the render path reads
-- them independently and this avoids constructing anything.
function Skeleton:tipX(): number
	return self.x[self.count]
end

function Skeleton:tipY(): number
	return self.y[self.count]
end

function Skeleton:tipZ(): number
	return self.z[self.count]
end

-- copyFrom(skel, other) -> ()
-- Deep-copies joint state. Used by the interpolation ring buffer and by the
-- "hold the last solved pose" fallback when a solve fails.
function Skeleton:copyFrom(other: any): ()
	local n = other.count
	if n > self.count then
		n = self.count
	end
	for i = 1, n do
		self.x[i] = other.x[i]
		self.y[i] = other.y[i]
		self.z[i] = other.z[i]
		self.radius[i] = other.radius[i]
	end
	for i = 1, n - 1 do
		self.len[i] = other.len[i]
	end
	self.upX = other.upX
	self.upY = other.upY
	self.upZ = other.upZ
	-- The rest pose travels with the pose: copyFrom is also how a pooled Skeleton is
	-- re-initialised, and a recycled chain whose reset() pointed at some previous
	-- creature's attach point would snap to the wrong shoulder on release.
	self.restX = other.restX
	self.restY = other.restY
	self.restZ = other.restZ
	self.dirX = other.dirX
	self.dirY = other.dirY
	self.dirZ = other.dirZ
	self.dirty = true
end

-- markDirty / isDirty / clearDirty
-- 'dirty' lets the renderer skip work when a tendril has not moved (idle tendrils
-- that are simply hanging solve to the same pose every frame).
function Skeleton:markDirty(): ()
	self.dirty = true
end

function Skeleton:isDirty(): boolean
	return self.dirty
end

function Skeleton:clearDirty(): ()
	self.dirty = false
end

return Skeleton
