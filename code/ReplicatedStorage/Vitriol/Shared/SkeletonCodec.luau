--!strict
-- SkeletonCodec.luau
-- Location: ReplicatedStorage > Vitriol > Shared > SkeletonCodec  (ModuleScript)
-- Purpose:  Packs a creature's skeleton into the byte stream described in
--           docs/03-MONSTER-TECH.md §7.1, and unpacks it on the client.
--           Joints are positions only; the ONE rotation in the payload is the
--           core's, because the client cannot derive it (see below).
--
--           PURE: it produces and consumes a plain array of numbers in [0,255].
--           The 'buffer' adapters (buffer.create / buffer.writeu8 / buffer.readu8)
--           are deliberately NOT here - they live in
--           ServerStorage > Vitriol > Creature > Replicator, so this module stays
--           unit-testable outside Roblox and so the quantisation maths cannot drift
--           from what the tests assert. Replicator's parity test is the proof that
--           the two representations carry identical bytes.
--
-- WHY THE CORE'S ORIENTATION IS SENT AND THE JOINTS' IS NOT
--   docs/03 §5.1: the core's "up" comes from the anchor centroid normal, so the
--   creature can hang from a ceiling with no special-casing. A client that tried to
--   recover that with CFrame.lookAt(forward, worldUp) hits the degenerate case
--   exactly when the core moves straight up or straight down - i.e. on the wall and
--   ceiling traversal this creature spends half its time doing - and rolls. Sending
--   4 bytes per snapshot kills the whole class of bug, and the skinned-mesh path
--   (docs/03 §4 mode B) needs a core CFrame anyway to place its root bone.
--   Joint orientations are still derived locally: they are a consequence of
--   consecutive joint positions, which are sent exactly.
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
-- WHY 'encode' RETURNS THE RECONSTRUCTED CORE
--   The core delta is quantised too. If the server always encoded against the
--   TRUE previous core, each snapshot's rounding error would be added to the
--   next one and the client's creature would random-walk away from the server's
--   over a long night. Instead 'encode' returns the core the CLIENT will compute
--   (recon = ref + quantised delta), and the caller passes that back as 'ref' on
--   the next snapshot. That is DPCM with feedback, and it makes the core error
--   bounded rather than accumulating - the test 'core error does not accumulate'
--   asserts exactly this over 1,000 snapshots.
-- Requires: (none)
-- Used by:  ServerStorage > Vitriol > Creature > Replicator (server),
--           StarterPlayer > ... > Client/SkeletonInterpolator (client)

local JOINT_STEP = 0.01 -- studs per unit, joints against the reconstructed core
local CORE_STEP = 0.02 -- studs per unit, core against the previous reconstructed core
local I16_MIN = -32768
local I16_MAX = 32767
local SQRT3 = math.sqrt(3)
local SQRT4 = 2 -- sqrt(4): the quaternion has four components

-- Core orientation: four int8 components of a unit quaternion, +-1/127 each.
local QUAT_SCALE = 127
local QUAT_STEP = 1 / QUAT_SCALE -- 0.007874 per unit step, so half a step is the error
local QUAT_ERROR = 0.5 * QUAT_STEP -- 0.003937 per component, before renormalising

-- Header layout (docs/03 §7.1). Fixed size: no branches, no per-field optionality,
-- because a variable header is one more way for server and client to disagree.
local CREATURE_ID_BYTES = 1
local SEQ_BYTES = 2
local CORE_BYTES = 6
local QUAT_BYTES = 4

local SkeletonCodec = {}

SkeletonCodec.JOINT_STEP = JOINT_STEP
SkeletonCodec.CORE_STEP = CORE_STEP
SkeletonCodec.QUAT_SCALE = QUAT_SCALE
-- Worst-case 3D error, per joint, in studs. Half a step per axis.
SkeletonCodec.MAX_JOINT_ERROR = JOINT_STEP * 0.5 * SQRT3 -- 0.00866
SkeletonCodec.MAX_CORE_ERROR = CORE_STEP * 0.5 * SQRT3 -- 0.01732
-- Worst-case rotation error, in radians. Derivation, and it is deliberately an
-- upper bound rather than a measurement:
--   four independent component roundings  -> |w - q| <= 2 * QUAT_ERROR = QUAT_DELTA
--   renormalising w costs a factor 1/(1 - QUAT_DELTA) in the worst case
--   the geodesic angle between unit quaternions a,b is 2*acos(|a.b|) = 2*asin(d/2)
-- Measured over 200,000 random orientations: worst 0.014755 rad against this bound
-- of 0.015873 rad (0.91 deg), asserted in the smoke test.
-- The displacement it implies is applied only to the CORE MESH and to the frame a
-- skinned rig hangs its tendrils from - joint positions are sent absolutely, so
-- nothing downstream of the core inherits it.
local QUAT_DELTA = QUAT_ERROR * SQRT4
SkeletonCodec.MAX_ANGLE_ERROR = 2 * QUAT_DELTA / (1 - QUAT_DELTA) -- 0.01587 rad
SkeletonCodec.MAX_ANGLE_ERROR_DEG = math.deg(SkeletonCodec.MAX_ANGLE_ERROR)
SkeletonCodec.CREATURE_ID_BYTES = CREATURE_ID_BYTES
SkeletonCodec.SEQ_BYTES = SEQ_BYTES
SkeletonCodec.CORE_BYTES = CORE_BYTES
SkeletonCodec.QUAT_BYTES = QUAT_BYTES
SkeletonCodec.HEADER_BYTES = CREATURE_ID_BYTES + SEQ_BYTES + CORE_BYTES + QUAT_BYTES -- 13
SkeletonCodec.JOINT_BYTES = 6

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

-- writeQuatComponent(out, n, value) -> next index
-- value is expected to be in [-1,1] (encode() normalises first). Written as a
-- signed byte in the same arithmetic style as the int16 writer.
local function writeQuatComponent(out: any, n: number, value: number): number
	local v = value
	if v ~= v then
		v = 0
	end
	v = math.floor(v * QUAT_SCALE + 0.5)
	if v < -QUAT_SCALE then
		v = -QUAT_SCALE
	elseif v > QUAT_SCALE then
		v = QUAT_SCALE
	end
	if v < 0 then
		v = v + 256
	end
	out[n] = v
	return n + 1
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

-- readQuatComponent(bytes, i) -> signed value in [-1,1]
local function readQuatComponent(bytes: any, i: number): number
	local v = bytes[i]
	if v >= 128 then
		v = v - 256
	end
	return v / QUAT_SCALE
end

-- round(value / step) -> integer units
local function quantise(value: number, step: number): number
	local v = value / step
	if v ~= v then
		return 0
	end
	return math.floor(v + 0.5)
end

-- normaliseQuat(x,y,z,w) -> x,y,z,w (identity if the input is degenerate or nil)
-- Normalising on BOTH sides is what makes the round trip idempotent: encoding a
-- decoded quaternion reproduces the same four bytes, so a client that re-reports a
-- core pose cannot drift.
function SkeletonCodec.normaliseQuat(x: number?, y: number?, z: number?, w: number?): (number, number, number, number)
	local nx = x or 0
	local ny = y or 0
	local nz = z or 0
	local nw = w or 0
	local m = math.sqrt(nx * nx + ny * ny + nz * nz + nw * nw)
	if m ~= m or m < 1e-6 then
		-- identity: (0,0,0,1) in xyzw order, which is CFrame's (Vector3, number) split
		return 0, 0, 0, 1
	end
	return nx / m, ny / m, nz / m, nw / m
end

-- byteCount(skelCount, jointsPerSkel) -> number
-- header (13) + 6 per joint. 8 tendrils x 12 joints -> 589 B (docs/03 §7.1).
function SkeletonCodec.byteCount(skelCount: number, jointsPerSkel: number): number
	return SkeletonCodec.HEADER_BYTES + skelCount * jointsPerSkel * SkeletonCodec.JOINT_BYTES
end

-- coreDisplacement(radiusStuds) -> studs
-- How far a point on the core can move because its orientation was rounded to
-- int8s. Exists so nobody has to re-derive it: at the 8-stud radius a Braid's
-- outermost tendril root sits at, the whole cost is a fraction of a stud on a mesh
-- that is itself moving, while the joint budget (MAX_JOINT_ERROR) is untouched.
function SkeletonCodec.coreDisplacement(radiusStuds: number): number
	return radiusStuds * SkeletonCodec.MAX_ANGLE_ERROR
end

-- encode(out, skels, coreX, coreY, coreZ, refX, refY, refZ, seq, creatureId,
--        qX?, qY?, qZ?, qW?) -> byteCount, reconCoreX, reconCoreY, reconCoreZ
--   'out' is a reusable byte array (grow it once, keep it). Feed the returned
--   recon core back in as ref on the next snapshot. The quaternion is optional and
--   defaults to identity, so a caller that has not solved an orientation yet still
--   produces a fixed-size, decodable frame.
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
	creatureId: number?,
	qx: number?,
	qy: number?,
	qz: number?,
	qw: number?
): (number, number, number, number)
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

	-- Core orientation, four int8s. See the header for why this is in the payload
	-- at all, and why it is the only rotation the wire carries.
	local ux, uy, uz, uw = SkeletonCodec.normaliseQuat(qx, qy, qz, qw)
	n = writeQuatComponent(out, n, ux)
	n = writeQuatComponent(out, n, uy)
	n = writeQuatComponent(out, n, uz)
	n = writeQuatComponent(out, n, uw)

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

-- decode(bytes, skels, refX, refY, refZ) -> coreX, coreY, coreZ, seq, qX, qY, qZ, qW
-- Fills each skeleton's x/y/z in place. The skeletons must already have the right
-- joint counts; 'len' and 'radius' are static per genome and are replicated once
-- at spawn, never per snapshot.
function SkeletonCodec.decode(bytes: any, skels: any, refX: number, refY: number, refZ: number): (number, number, number, number, number, number, number, number)
	local seq = readU16(bytes, 2)
	local coreX = refX + readI16(bytes, 4) * CORE_STEP
	local coreY = refY + readI16(bytes, 6) * CORE_STEP
	local coreZ = refZ + readI16(bytes, 8) * CORE_STEP
	-- Renormalise: the four components are rounded independently, so their length
	-- is 1 +- 4*QUAT_ERROR. A CFrame built from a non-unit quaternion silently
	-- scales the rig, which is far more visible than the 1e-3 it would cost.
	local qx = readQuatComponent(bytes, 10)
	local qy = readQuatComponent(bytes, 11)
	local qz = readQuatComponent(bytes, 12)
	local qw = readQuatComponent(bytes, 13)
	qx, qy, qz, qw = SkeletonCodec.normaliseQuat(qx, qy, qz, qw)

	local n = SkeletonCodec.HEADER_BYTES + 1
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

	return coreX, coreY, coreZ, seq, qx, qy, qz, qw
end

-- creatureId(bytes) -> number
function SkeletonCodec.creatureId(bytes: any): number
	return bytes[1]
end

return SkeletonCodec
