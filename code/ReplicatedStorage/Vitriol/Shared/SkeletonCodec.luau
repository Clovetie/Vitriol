--!strict
-- SkeletonCodec.luau
-- Location: ReplicatedStorage > Vitriol > Shared > SkeletonCodec  (ModuleScript)
-- Purpose:  Packs a creature's skeleton into the byte stream described in
--           docs/03-MONSTER-TECH.md §7.1, and unpacks it on the client.
--           Positions only - the client derives orientation from its own rig.
--
--           PURE: it produces and consumes a plain array of numbers in [0,255].
--           The `buffer` adapters (writebuffer/readbuffer) are the only part that
--           needs Studio, and they are deliberately NOT here - they live in
--           CreatureReplicator so this module stays unit-testable and so the
--           quantisation maths cannot drift from what the tests assert.
--
-- WHY JOINTS ARE QUANTISED AGAINST THE CORE, NOT THE PARENT JOINT
--   The obvious scheme is each joint as an int16 offset from its PARENT at 0.01
--   stud resolution. Implemented straightforwardly - encode against the true
--   parent, decode by accumulating - the rounding error of every joint feeds
--   forward into the next, so the tip drifts furthest from where the server
--   thinks it is. Measured on the 12-joint test pose: 0.02748 studs, which is
--   3.2x this codec's 0.00866 bound and past the 0.02 stud budget in docs/03.
--   Core-relative offsets measure every joint from one anchor, so the error stays
--   at +-0.005 per axis no matter how long the chain is.
--
--   To be precise about what that comparison does and does not show: a
--   parent-relative encoder that quantises against the previously DECODED joint
--   (DPCM with feedback) would also stay bounded. It would simply have to mirror
--   the decoder's entire chain state on the server, every snapshot, to do so.
--   Core-relative reaches the same bound from a single scalar anchor, which is
--   less state, less code, and one fewer way for server and client to disagree.
--
-- WHY `encode` RETURNS THE RECONSTRUCTED CORE
--   The core delta is quantised too. If the server always encoded against the
--   TRUE previous core, each snapshot's rounding error would be added to the
--   next one and the client's creature would random-walk away from the server's
--   over a long night. Instead `encode` returns the core the CLIENT will compute
--   (recon = ref + quantised delta), and the caller passes that back as `ref` on
--   the next snapshot. That is DPCM with feedback, and it makes the core error
--   bounded rather than accumulating - the test `core error does not accumulate`
--   asserts exactly this over 1,000 snapshots.
-- Requires: (none)
-- Used by:  Services/CreatureReplicator (server), Client/SkeletonInterpolator

local JOINT_STEP = 0.01 -- studs per unit, joints against the reconstructed core
local CORE_STEP = 0.02 -- studs per unit, core against the previous reconstructed core
local I16_MIN = -32768
local I16_MAX = 32767
local SQRT3 = math.sqrt(3)

local SkeletonCodec = {}

SkeletonCodec.JOINT_STEP = JOINT_STEP
SkeletonCodec.CORE_STEP = CORE_STEP
-- Worst-case 3D error, per joint, in studs. Half a step per axis.
SkeletonCodec.MAX_JOINT_ERROR = JOINT_STEP * 0.5 * SQRT3 -- 0.00866
SkeletonCodec.MAX_CORE_ERROR = CORE_STEP * 0.5 * SQRT3 -- 0.01732

-- Byte I/O uses arithmetic rather than bitwise ops on purpose: luaparse (which
-- tools/check-syntax.js runs) is Lua 5.1 and has no bitwise operators, so a
-- bitwise codec would drop this file out of the syntax check entirely. Shifts by
-- 8 are the same multiply/divide by 256 and cost nothing at 15 Hz.

-- writeI16(out, n, value) -> next index
local function writeI16(out: any, n: number, value: number): number
	local v = value
	if v ~= v then -- NaN guard: a failed solve must not poison the stream
		v = 0
	end
	v = math.floor(v + 0.5)
	if v < I16_MIN then
		v = I16_MIN
	elseif v > I16_MAX then
		v = I16_MAX
	end
	local u = v
	if u < 0 then
		u = u + 65536
	end
	out[n] = u % 256
	out[n + 1] = math.floor(u / 256)
	return n + 2
end

-- writeU16(out, n, value) -> next index
local function writeU16(out: any, n: number, value: number): number
	local v = math.floor((value or 0) + 0.5) % 65536
	if v < 0 then
		v = v + 65536
	end
	out[n] = v % 256
	out[n + 1] = math.floor(v / 256)
	return n + 2
end

-- readI16(bytes, i) -> signed value
local function readI16(bytes: any, i: number): number
	local u = bytes[i + 1] * 256 + bytes[i]
	if u >= 32768 then
		u -= 65536
	end
	return u
end

-- readU16(bytes, i) -> unsigned value
local function readU16(bytes: any, i: number): number
	return bytes[i + 1] * 256 + bytes[i]
end

-- round(value / step) -> integer units
local function quantise(value: number, step: number): number
	local v = value / step
	if v ~= v then
		return 0
	end
	return math.floor(v + 0.5)
end

-- byteCount(skelCount, jointsPerSkel) -> number
-- Header is creatureId (1) + seq (2) + core delta (6) = 9 bytes, then 6 per joint.
function SkeletonCodec.byteCount(skelCount: number, jointsPerSkel: number): number
	return 9 + skelCount * jointsPerSkel * 6
end

-- encode(out, skels, coreX, coreY, coreZ, refX, refY, refZ, seq, creatureId)
--   -> byteCount, reconCoreX, reconCoreY, reconCoreZ
-- `out` is a reusable byte array (grow it once, keep it). Feed the returned
-- recon core back in as ref on the next snapshot.
function SkeletonCodec.encode(
	out: any,
	skels: any,
	coreX: number,
	coreY: number,
	coreZ: number,
	refX: number,
	refY: number,
	refZ: number,
	seq: number?,
	creatureId: number?
): number, number, number, number
	local n = 1
	out[n] = (creatureId or 0) % 256
	n += 1
	n = writeU16(out, n, seq or 0)

	-- Core, as a delta from the previous RECONSTRUCTED core.
	local dqx = quantise(coreX - refX, CORE_STEP)
	local dqy = quantise(coreY - refY, CORE_STEP)
	local dqz = quantise(coreZ - refZ, CORE_STEP)
	if dqx < I16_MIN then
		dqx = I16_MIN
	elseif dqx > I16_MAX then
		dqx = I16_MAX
	end
	if dqy < I16_MIN then
		dqy = I16_MIN
	elseif dqy > I16_MAX then
		dqy = I16_MAX
	end
	if dqz < I16_MIN then
		dqz = I16_MIN
	elseif dqz > I16_MAX then
		dqz = I16_MAX
	end
	n = writeI16(out, n, dqx)
	n = writeI16(out, n, dqy)
	n = writeI16(out, n, dqz)

	-- What the client will reconstruct. This - not the true core - is the anchor
	-- every joint offset is measured from, so encode and decode agree exactly.
	local reconX = refX + dqx * CORE_STEP
	local reconY = refY + dqy * CORE_STEP
	local reconZ = refZ + dqz * CORE_STEP

	for s = 1, #skels do
		local skel = skels[s]
		local count = skel.count
		for i = 1, count do
			n = writeI16(out, n, quantise(skel.x[i] - reconX, JOINT_STEP))
			n = writeI16(out, n, quantise(skel.y[i] - reconY, JOINT_STEP))
			n = writeI16(out, n, quantise(skel.z[i] - reconZ, JOINT_STEP))
		end
	end

	return n - 1, reconX, reconY, reconZ
end

-- decode(bytes, skels, refX, refY, refZ) -> coreX, coreY, coreZ, seq
-- Fills each skeleton's x/y/z in place. The skeletons must already have the right
-- joint counts; `len` and `radius` are static per genome and are replicated once
-- at spawn, never per snapshot.
function SkeletonCodec.decode(bytes: any, skels: any, refX: number, refY: number, refZ: number): number, number, number, number
	local seq = readU16(bytes, 2)
	local coreX = refX + readI16(bytes, 4) * CORE_STEP
	local coreY = refY + readI16(bytes, 6) * CORE_STEP
	local coreZ = refZ + readI16(bytes, 8) * CORE_STEP

	local n = 10
	for s = 1, #skels do
		local skel = skels[s]
		for i = 1, skel.count do
			skel.x[i] = coreX + readI16(bytes, n) * JOINT_STEP
			skel.y[i] = coreY + readI16(bytes, n + 2) * JOINT_STEP
			skel.z[i] = coreZ + readI16(bytes, n + 4) * JOINT_STEP
			n += 6
		end
		skel.dirty = true
	end

	return coreX, coreY, coreZ, seq
end

-- creatureId(bytes) -> number
function SkeletonCodec.creatureId(bytes: any): number
	return bytes[1]
end

return SkeletonCodec
