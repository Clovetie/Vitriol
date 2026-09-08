--!strict
-- Replicator.luau
-- Location: ServerStorage > Vitriol > Creature > Replicator  (ModuleScript)
-- Purpose:  The ONLY writer of RE_SkeletonStream, for one creature. It does three
--           things and nothing else:
--             1. asks Shared/SkeletonCodec to quantise a snapshot,
--             2. converts the codec's plain byte array into a 'buffer' for the wire
--                (buffer.create + buffer.writeu8) and back on the client
--                (buffer.readu8), and
--             3. paces the stream at the per-LOD rate from GameConfig.Ticks.
--
--           WHY THE BUFFER ADAPTERS LIVE HERE AND NOT IN THE CODEC
--           'buffer' is a Roblox global, so anything that touches it cannot run in
--           the headless harness that guards the quantisation maths. Keeping the
--           codec array-only and the adapters here means the interesting part - the
--           error bounds - is executed by tools/vitriol-smoke-test.js, and the
--           adapter is thin enough to be proven by inspection plus the parity test
--           (the same snapshot through encode->toBuffer->toBytes->decode must be
--           byte-identical and pose-identical to encode->decode).
--
--           WHAT THIS MODULE DOES NOT DO
--           It does not build LOD proxies. docs/03 §8.3 collapses a tendril to a
--           4-joint proxy, and that is a rigging decision: TendrilRig decides which
--           Skeleton list to hand the replicator, so the wire format stays one
--           format. The tier only changes the RATE (and the list it is given).
--           It also never reads a client: outbound only.
-- Requires: Shared/SkeletonCodec, Shared/Remotes, Config/GameConfig (all via the
--           lazy accessors below, or injected by the caller for testability)
-- Used by:  ServerStorage > Vitriol > Creature > CreatureCore (WP5), and the
--           client-side mirror of this file's reader in SkeletonInterpolator

local Replicator = {}
Replicator.__index = Replicator

local LAZY = {}

-- Dependency resolution. Services own how a module is found; a test - and an Actor,
-- which cannot 'require' in a desynchronised phase (docs/08 §6) - passes the
-- dependency in instead, so Bootstrap injects and this lazy path is only the
-- fallback. WaitForChild here has NO timeout on purpose: this file only ever runs
-- on the server, where it is the same server that authored those children, and the
-- bind-timeout rule in docs/09 §WP3 is a client rule (Remotes.await implements it).
local function vitriolRoot(): any
	if LAZY.root == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.root = ReplicatedStorage:WaitForChild("Vitriol")
	end
	return LAZY.root
end

local function sharedModule(name: string): any
	local cacheKey = "shared_" .. name
	if LAZY[cacheKey] == nil then
		LAZY[cacheKey] = require(vitriolRoot():WaitForChild("Shared"):WaitForChild(name))
	end
	return LAZY[cacheKey]
end

local function resolveCodec(injected: any): any
	if injected ~= nil then
		return injected
	end
	return sharedModule("SkeletonCodec")
end

local function resolveConfig(injected: any): any
	if injected ~= nil then
		return injected
	end
	if LAZY.config == nil then
		LAZY.config = require(vitriolRoot():WaitForChild("Config"):WaitForChild("GameConfig"))
	end
	return LAZY.config
end

-- toBuffer(bytes, count) -> buffer
-- Array index i maps to buffer offset i-1: the codec counts from 1, 'buffer' counts
-- from 0. This is the whole adapter, and the only place either representation meets.
function Replicator.toBuffer(bytes: any, count: number): any
	local buf = buffer.create(count)
	for i = 1, count do
		buffer.writeu8(buf, i - 1, bytes[i])
	end
	return buf
end

-- toBytes(buf, out?) -> out, count
-- The reader side, used by the client before it hands the array to the codec.
-- 'out' is a reusable array so a renderer that decodes every frame does not
-- allocate one; without it a fresh table is made (fine on join, not in a loop).
function Replicator.toBytes(buf: any, out: any?): any
	local count = buffer.len(buf)
	local target = out
	if target == nil then
		target = {}
	end
	for i = 1, count do
		target[i] = buffer.readu8(buf, i - 1)
	end
	return target, count
end

-- checkParity(bytesA, bytesB, count) -> ok, firstMismatch?
-- A tiny helper so the harness (and a debug assert in a dev build) can compare a
-- buffer round trip against the array the codec produced without a third copy.
function Replicator.checkParity(a: any, b: any, count: number): boolean, number?
	for i = 1, count do
		if a[i] ~= b[i] then
			return false, i
		end
	end
	return true, nil
end

-- new(creatureId, cfg?) -> Replicator
-- cfg = { Codec, Config, Remote, SecondsPerSnapshot }
-- The default rate is the NEAR tier's, because a creature starts NEAR its spawn
-- player; setRate() follows the LOD ladder from then on.
function Replicator.new(creatureId: number, cfg: any?)
	local self = setmetatable({}, Replicator)
	local c = cfg or {}
	local config = resolveConfig(c.Config)
	self.config = config
	self.creatureId = creatureId
	self.codec = resolveCodec(c.Codec)
	self.remote = c.Remote
	self.secPerSnapshot = c.SecondsPerSnapshot or (1 / config.Ticks.SkeletonStreamHzNear)
	self.acc = self.secPerSnapshot -- fire on the first frame, not after a full period
	self.seq = 0
	self.bytesSent = 0
	self.snapshots = 0
	self.throttled = 0
	-- Reusable wire buffer: the codec writes a plain array, this converts it. The
	-- array is grown once to the largest payload the creature will produce and then
	-- never reallocated, so the steady-state encode path allocates nothing.
	self.bytes = {}
	self.byteCount = 0
	-- DPCM feedback state: the core the CLIENT currently believes it has. encode()
	-- returns the reconstruction and it is fed back as the next reference, which is
	-- what stops the core random-walking (docs/03 §7.1).
	self.refX = 0
	self.refY = 0
	self.refZ = 0
	self.hasRef = false
	return self
end

-- setRemote(replicator, remote) -> ()
-- Bootstrap hands over the remote after Remotes.init(), because a creature can be
-- spawned before the Comms folder exists in a test place.
function Replicator:setRemote(remote: any): ()
	self.remote = remote
end

-- reset(replicator) -> ()
-- Called on respawn/despawn reuse: the reconstructed-core reference must not
-- survive into the next creature's life, or its first snapshot is a delta from a
-- position it never occupied.
function Replicator:reset(): ()
	self.refX = 0
	self.refY = 0
	self.refZ = 0
	self.hasRef = false
	self.seq = 0
	self.acc = 0
end

-- _ensureCapacity(replicator, needed) -> ()
-- Grows the reusable array's length without touching element values (Lua tables are
-- sparse, so only '#self.bytes' matters to the codec's writer).
function Replicator:_ensureCapacity(needed: number): ()
	local have = #self.bytes
	if needed <= have then
		return
	end
	for i = have + 1, needed do
		self.bytes[i] = 0
	end
end

-- encode(replicator, skels, coreX, coreY, coreZ, qX?, qY?, qZ?, qW?) -> byteCount
-- Pure packing into self.bytes, no side effects on the network. Split out so a
-- caller can measure the encode cost separately from the send (docs/01 §9 puts a
-- 0.3 ms budget on "replication encode" alone).
function Replicator:encode(skels: any, coreX: number, coreY: number, coreZ: number, qX: number?, qY: number?, qZ: number?, qW: number?): number
	local codec = self.codec
	local joints = 0
	local skelCount = #skels
	for i = 1, skelCount do
		joints += skels[i].count
	end
	-- Size the buffer from the joint count, never from a guess: the codec returns
	-- exactly this many bytes (asserted in the smoke test), and a payload whose
	-- length the writer does not know would have to be truncated by the reader.
	local needed = codec.HEADER_BYTES + joints * codec.JOINT_BYTES
	self:_ensureCapacity(needed)

	local refX = coreX
	local refY = coreY
	local refZ = coreZ
	if self.hasRef then
		refX = self.refX
		refY = self.refY
		refZ = self.refZ
	end
	self.seq = (self.seq + 1) % 65536

	local count, reconX, reconY, reconZ = codec.encode(
		self.bytes,
		skels,
		coreX,
		coreY,
		coreZ,
		refX,
		refY,
		refZ,
		self.seq,
		self.creatureId,
		qX,
		qY,
		qZ,
		qW
	)
	self.byteCount = count
	self.refX = reconX
	self.refY = reconY
	self.refZ = reconZ
	self.hasRef = true
	return count
end

-- snapshot(replicator, skels, coreX, coreY, coreZ, qX?, qY?, qZ?, qW?) -> buffer, count
-- encode + convert. Returns the Buffer that goes on the wire.
function Replicator:snapshot(skels: any, coreX: number, coreY: number, coreZ: number, qX: number?, qY: number?, qZ: number?, qW: number?): any, number
	local count = self:encode(skels, coreX, coreY, coreZ, qX, qY, qZ, qW)
	return Replicator.toBuffer(self.bytes, count), count
end

-- publish(replicator, dt, skels, coreX, coreY, coreZ, quat..., recipients)
--        -> sent(boolean), byteCount
-- The cadence-aware entry point. Call it every frame from CreatureCore:step and it
-- will emit at the tier's rate. 'recipients' is the caller's filtered player list
-- (inside GameConfig.LOD.StreamRadius) - a nil list means FireAllClients, and an
-- empty table means "nobody is close enough", which is a real saving: nobody
-- on-screen pays for the stream.
function Replicator:publish(dt: number, recipients: any, skels: any, coreX: number, coreY: number, coreZ: number, qX: number?, qY: number?, qZ: number?, qW: number?): boolean, number
	self.acc = self.acc + dt
	if self.acc < self.secPerSnapshot then
		self.throttled = self.throttled + 1
		return false, 0
	end
	-- Subtract rather than zero: the remainder carries the overshoot, so a 15 Hz
	-- stream stays at 15 Hz under a 30 or 60 Hz frame rate instead of drifting down.
	self.acc = self.acc - self.secPerSnapshot
	local buf, count = self:snapshot(skels, coreX, coreY, coreZ, qX, qY, qZ, qW)
	local remote = self.remote
	if remote ~= nil then
		if recipients == nil then
			remote:FireAllClients(buf)
		else
			for i = 1, #recipients do
				remote:FireClient(recipients[i], buf)
			end
		end
	end
	self.snapshots = self.snapshots + 1
	self.bytesSent = self.bytesSent + count
	return true, count
end

-- setRate(replicator, hz) -> ()  (the LOD ladder changes the rate, nothing else)
function Replicator:setRate(hz: number): ()
	if hz > 0 then
		self.secPerSnapshot = 1 / hz
	end
end

-- stats(replicator) -> { snapshots, bytesSent, throttled, byteCount, seq }
function Replicator:stats(): any
	return {
		snapshots = self.snapshots,
		bytesSent = self.bytesSent,
		throttled = self.throttled,
		byteCount = self.byteCount,
		seq = self.seq,
	}
end

return Replicator
