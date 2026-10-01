-- tools/tests/pure-tests.lua
--
-- The TIDEKEEPER iteration-2 assertion suite. Run by tidekeeper-smoke-test.js
-- against the REAL modules under code/ReplicatedStorage/Tidekeeper.
--
-- Coverage targets from doc 04 section 8:
--   Tide >= 30 | RNG >= 20 | Codec >= 40 | Orders >= 50 | Visit >= 80
--   Resolve >= 40 | determinism >= 10 | economy >= 30    -> >= 300 total
--
-- Written in plain Lua so the transform is a no-op on it. No `continue`, no
-- interpolated strings, no compound assignment.

TESTS = { passed = 0, failed = 0, failures = {} }

local SECTION = "?"
local SECTION_COUNTS = {}
local SECTION_ORDER = {}

local function section(name)
	SECTION = name
	if SECTION_COUNTS[name] == nil then
		SECTION_COUNTS[name] = 0
		SECTION_ORDER[#SECTION_ORDER + 1] = name
	end
end

local function record(pass, name, detail)
	SECTION_COUNTS[SECTION] = (SECTION_COUNTS[SECTION] or 0) + 1
	if pass then
		TESTS.passed = TESTS.passed + 1
	else
		TESTS.failed = TESTS.failed + 1
		TESTS.failures[#TESTS.failures + 1] = SECTION .. " / " .. name .. " -- " .. tostring(detail)
		print("FAIL [" .. SECTION .. "] " .. name .. " -- " .. tostring(detail))
	end
end

local function ok(cond, name)
	record(cond == true, name, "expected true, got " .. tostring(cond))
end

local function notOk(cond, name)
	record(cond ~= true, name, "expected not-true, got " .. tostring(cond))
end

local function eq(actual, expected, name)
	record(actual == expected, name, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function neq(actual, unexpected, name)
	record(actual ~= unexpected, name, "expected anything but " .. tostring(unexpected))
end

local function near(actual, expected, eps, name)
	local delta = math.abs(actual - expected)
	record(delta <= eps, name, "expected " .. tostring(expected) .. " +/- " .. tostring(eps) .. ", got " .. tostring(actual) .. " (delta " .. tostring(delta) .. ")")
end

local function between(actual, lo, hi, name)
	record(actual >= lo and actual <= hi, name, "expected [" .. tostring(lo) .. ", " .. tostring(hi) .. "], got " .. tostring(actual))
end

local function errors(fn, name)
	local success = pcall(fn)
	record(success == false, name, "expected the call to error, but it returned")
end

local function noErrors(fn, name)
	local success, err = pcall(fn)
	record(success == true, name, "expected no error, got " .. tostring(err))
end

-- ---------------------------------------------------------------- modules

local MathExt = TidekeeperRequire("MathExt")
local Hash = TidekeeperRequire("Hash")
local RNG = TidekeeperRequire("RNG")
local Tables = TidekeeperRequire("Tables")
local Signal = TidekeeperRequire("Signal")
local Codec = TidekeeperRequire("Codec")
local Schema = TidekeeperRequire("Schema")
local Tide = TidekeeperRequire("Tide")
local Version = TidekeeperRequire("Version")
local DrifterCodec = TidekeeperRequire("DrifterCodec")
local PostCodec = TidekeeperRequire("PostCodec")
local Standing = TidekeeperRequire("Standing")
local Almanac = TidekeeperRequire("Almanac")
local Drifter = TidekeeperRequire("Drifter")
local Post = TidekeeperRequire("Post")
local Orders = TidekeeperRequire("Orders")
local Ledger = TidekeeperRequire("Ledger")
local Visit = TidekeeperRequire("Visit")
local Resolve = TidekeeperRequire("Resolve")

local GameConfig = TidekeeperRequire("GameConfig")
local EconomyConfig = TidekeeperRequire("EconomyConfig")
local DrifterConfig = TidekeeperRequire("DrifterConfig")
local OrdersConfig = TidekeeperRequire("OrdersConfig")
local FindsConfig = TidekeeperRequire("FindsConfig")

-- ---------------------------------------------------------------- fixtures

local function mkDrifter(owner, epoch, class, current, tier, budget, taste, wants, cargo)
	local t = taste
	if t == nil then
		t = { 0, 0, 0, 0, 0, 0, 0, 0 }
	end
	return {
		v = 1,
		id = DrifterCodec.makeId(owner, epoch),
		owner = owner,
		epoch = epoch,
		current = current,
		class = class,
		tier = tier,
		standing = 0,
		renown = 0,
		budget = budget,
		taste = t,
		wants = wants or {},
		cargo = cargo or {},
		letterId = 0,
		beacons = 0,
		look = 12345,
	}
end

local function mkPost(tier)
	local S = Post.new(1001, 4455667788, 987654321, Tide.EPOCH)
	S.tier = tier or 3
	S.current = 0
	Post.addStock(S, 1, 40)
	Post.addStock(S, 3, 25)
	Post.addStock(S, 7, 12)
	Post.addStock(S, 9, 6)
	Post.addStock(S, 10, 30)
	Post.addStock(S, 12, 3)
	Post.addStock(S, 19, 8)
	Post.setShelf(S, 1, 1, 4)
	Post.setShelf(S, 2, 3, 12)
	Post.setShelf(S, 3, 7, 18)
	Post.setShelf(S, 4, 9, 110)
	Post.setShelf(S, 5, 12, 240)
	Post.setShelf(S, 6, 19, 80)
	S.orders = Orders.empty()
	S.ordersBytecode = Orders.encode(S.orders)
	return S
end

local tideNames = { "LOW", "EBB", "FLOOD", "SLACK", "HIGH" }
local startAt = nil

local function mkContext(epoch, tide)
	local ctx = Visit.newContext()
	ctx.epoch = epoch
	ctx.tide = tide
	ctx.hostId = 4455667788
	ctx.berthsUsed = 0
	ctx.maxBerths = GameConfig.MAX_BERTHS
	return ctx
end

local function baseScenario(tier)
	local S = mkPost(tier or 4)
	S.orders = Orders.empty()
	S.ordersBytecode = Orders.encode(S.orders)
	local inbound = {}
	for i = 1, 9 do
		local rngD = RNG.new(1000 + i)
		inbound[i] = Drifter.synthesize(rngD, 900000 + i, 5, (i - 1) % 5, 4)
	end
	return S, inbound
end

-- Canonical serialisation of a resolve result, used by the determinism proofs.
local function canonical(state, entries, receipts)
	local parts = { Codec.toHex(PostCodec.encode(state)) }
	for i = 1, #entries do
		local e = entries[i]
		local slotText = ""
		for j = 1, #e.slots do
			slotText = slotText .. "," .. tostring(e.slots[j])
		end
		parts[#parts + 1] = tostring(e.templateId) .. ":" .. tostring(e.epoch) .. ":" .. tostring(e.actorId) .. slotText
	end
	for i = 1, #receipts do
		local r = receipts[i]
		parts[#parts + 1] = table.concat({ r.drifterId, r.hostId, r.epoch, r.outcome, r.spent, r.warmth, r.flags, r.noteId }, "/")
	end
	return table.concat(parts, "|")
end

-- ================================================================ MathExt
section("MathExt")
do

eq(MathExt.clamp(5, 1, 3), 3, "clamp above")
eq(MathExt.clamp(-5, 1, 3), 1, "clamp below")
eq(MathExt.clamp(2, 1, 3), 2, "clamp inside")
eq(MathExt.sign(-4), -1, "sign negative")
eq(MathExt.sign(0), 0, "sign zero")
eq(MathExt.sign(4), 1, "sign positive")
eq(MathExt.round(0.5), 1, "round half up")
eq(MathExt.round(-0.5), -1, "round half away from zero")
eq(MathExt.round(2.49), 2, "round down")
eq(MathExt.idiv(-7, 2), -4, "idiv floors toward negative infinity")
eq(MathExt.idiv(7, 2), 3, "idiv positive")
eq(MathExt.lerp(0, 10, 0.25), 2.5, "lerp")
ok(MathExt.approx(1.0, 1.0 + 1e-12), "approx within default epsilon")
notOk(MathExt.approx(1.0, 1.1), "approx rejects a real difference")
eq(MathExt.scalePerMille(1000, 25), 25, "scalePerMille exact")
eq(MathExt.scalePerMille(7, 25), 0, "scalePerMille floors")
eq(MathExt.applyPercent(100, -40), 60, "applyPercent negative")
eq(MathExt.applyPercent(100, 40), 140, "applyPercent positive")
eq(MathExt.clampInt(3.9, 0, 10), 3, "clampInt floors")
eq(MathExt.clampInt(-3.9, 0, 10), 0, "clampInt clamps low")
ok(MathExt.isInteger(5), "isInteger accepts an integer")
notOk(MathExt.isInteger(5.5), "isInteger rejects a fraction")
notOk(MathExt.isInteger("5"), "isInteger rejects a string")
notOk(MathExt.isInteger(0 / 0), "isInteger rejects NaN")
near(MathExt.cosine({ 1, 0 }, { 1, 0 }, 2), 1, 1e-12, "cosine of identical vectors")
near(MathExt.cosine({ 1, 0 }, { -1, 0 }, 2), -1, 1e-12, "cosine of opposite vectors")
near(MathExt.cosine({ 1, 0 }, { 0, 1 }, 2), 0, 1e-12, "cosine of orthogonal vectors")
eq(MathExt.cosine({ 0, 0 }, { 1, 1 }, 2), 0, "cosine of the zero vector is 0, not an error")

-- ================================================================ Hash
end
section("Hash")
do

eq(Hash.mul32(65536, 65536), 0, "mul32 wraps at 2^32")
eq(Hash.mul32(3, 4), 12, "mul32 small")
eq(Hash.mul32(4294967295, 1), 4294967295, "mul32 identity at the top of the range")
eq(Hash.mul32(2654435769, 2654435769), 3814614961, "mul32 matches exact arithmetic")
eq(Hash.word(-5), 4294967291, "word normalises a negative")
eq(Hash.word(4294967296), 0, "word wraps")
ok(Hash.fmix32(0) >= 0 and Hash.fmix32(0) < 4294967296, "fmix32 stays in uint32")
eq(Hash.mix(1, 2, 3), Hash.mix(1, 2, 3), "mix is a function, not a generator")
neq(Hash.mix(1, 2, 3), Hash.mix(1, 3, 2), "mix is order sensitive")
neq(Hash.mix(1), Hash.mix(1, 0), "mix distinguishes arity")
neq(Hash.mix(5), Hash.mix(5 + 4294967296), "mix sees above 32 bits")
ok(Hash.mix(0) >= 0 and Hash.mix(0) < 4294967296, "mix stays in uint32")
eq(Hash.string(""), 2166136261, "FNV-1a of the empty string is the offset basis")
eq(Hash.string("a"), 3826002220, "FNV-1a of 'a' matches the published vector")
eq(Hash.string("foobar"), 3214735720, "FNV-1a of 'foobar' matches the published vector")
neq(Hash.string("ab"), Hash.string("ba"), "FNV-1a is order sensitive")
eq(Hash.bytes({ 97 }, 1, 1), Hash.string("a"), "Hash.bytes agrees with Hash.string")
eq(Hash.reduce(0, 27), 0, "reduce of 0")
eq(Hash.reduce(4294967295, 27), 26, "reduce of the maximum stays in range")
local reduceSeen = {}
for i = 0, 2000 do
	local r = Hash.reduce(Hash.mix(i, 99), 27)
	reduceSeen[r] = true
end
local reduceCount = 0
for _ in pairs(reduceSeen) do
	reduceCount = reduceCount + 1
end
eq(reduceCount, 27, "reduce covers every bucket over 2000 samples")
local collisions = 0
local seenHashes = {}
for i = 1, 5000 do
	local h = Hash.mix(i, 7)
	if seenHashes[h] then
		collisions = collisions + 1
	end
	seenHashes[h] = true
end
between(collisions, 0, 5, "mix has few collisions over 5000 sequential inputs")

-- ================================================================ RNG
end
section("RNG")
do

local r1 = RNG.new(12345)
local r2 = RNG.new(12345)
for i = 1, 20 do
	if r1:nextUInt() ~= r2:nextUInt() then
		ok(false, "two generators with the same seed diverged at step " .. i)
	end
end
ok(true, "same seed produces the same stream for 20 steps")
local r3 = RNG.new(12346)
neq(RNG.new(12345):nextUInt(), r3:nextUInt(), "different seeds produce different streams")

local rr = RNG.new(7)
local minU, maxU = 4294967296, -1
for _ = 1, 4000 do
	local v = rr:nextUInt()
	if v < minU then minU = v end
	if v > maxU then maxU = v end
	if v ~= math.floor(v) then
		ok(false, "nextUInt returned a non-integer")
	end
end
ok(minU >= 0, "nextUInt is never negative")
ok(maxU < 4294967296, "nextUInt stays below 2^32")
between(maxU, 4200000000, 4294967295, "nextUInt reaches the top of its range")

local rn = RNG.new(99)
local sum = 0
local outOfRange = 0
for _ = 1, 20000 do
	local v = rn:nextNumber()
	if v < 0 or v >= 1 then outOfRange = outOfRange + 1 end
	sum = sum + v
end
eq(outOfRange, 0, "nextNumber stays in [0, 1)")
near(sum / 20000, 0.5, 0.01, "nextNumber is uniform in the mean")

local rg = RNG.new(4242)
local buckets = { 0, 0, 0, 0, 0, 0 }
for _ = 1, 60000 do
	local v = rg:range(1, 6)
	buckets[v] = buckets[v] + 1
end
for i = 1, 6 do
	between(buckets[i], 9400, 10600, "range(1,6) bucket " .. i .. " is unbiased")
end
eq(RNG.new(1):range(5, 5), 5, "range with a single value")
eq(RNG.new(1):range(9, 3), 9, "range with an inverted span returns the low bound")

local rnorm = RNG.new(2024)
local nsum, nsq = 0, 0
local N = 40000
for _ = 1, N do
	local v = rnorm:normal(0, 0.12)
	nsum = nsum + v
	nsq = nsq + v * v
end
near(nsum / N, 0, 0.005, "normal(0, 0.12) has mean 0")
near(math.sqrt(nsq / N), 0.12, 0.005, "normal(0, 0.12) has the requested sd")
between(RNG.new(5):normal(0, 1), -3.47, 3.47, "the Bates variate is bounded")

local rs = RNG.new(31337)
local before = rs:nextUInt()
rs:reseed(31337)
eq(rs:nextUInt(), before, "reseed restores the stream exactly")
local rc = RNG.new(555)
rc:nextUInt()
local clone = rc:clone()
eq(clone:nextUInt(), rc:nextUInt(), "clone continues the same stream")
local split1 = RNG.new(8):split(11)
local split2 = RNG.new(8):split(11)
eq(split1:nextUInt(), split2:nextUInt(), "split is deterministic")
neq(RNG.new(8):split(1):nextUInt(), RNG.new(8):split(2):nextUInt(), "different split tags diverge")

local rw = RNG.new(17)
local weighted = { 0, 0, 0 }
for _ = 1, 30000 do
	weighted[rw:weightedIndex({ 1, 0, 3 }, 3)] = weighted[rw:weightedIndex({ 1, 0, 3 }, 3)] + 1
end
eq(weighted[2], 0, "weightedIndex never picks a zero-weight entry")
eq(RNG.new(1):weightedIndex({ 0, 0 }, 2), 0, "weightedIndex returns 0 when every weight is zero")

local shuffled = { 1, 2, 3, 4, 5, 6, 7, 8 }
RNG.new(9):shuffle(shuffled, 8)
local shuffleSum = 0
for i = 1, 8 do
	shuffleSum = shuffleSum + shuffled[i]
end
eq(shuffleSum, 36, "shuffle is a permutation")
local a1 = { 1, 2, 3, 4, 5, 6, 7, 8 }
local a2 = { 1, 2, 3, 4, 5, 6, 7, 8 }
RNG.new(9):shuffle(a1, 8)
RNG.new(9):shuffle(a2, 8)
local sameShuffle = true
for i = 1, 8 do
	if a1[i] ~= a2[i] then sameShuffle = false end
end
ok(sameShuffle, "shuffle with the same seed gives the same permutation")
eq(RNG.new(3):pick({}, 0), nil, "pick of an empty array is nil")

local rcp = RNG.new(606)
local hits = 0
for _ = 1, 20000 do
	if rcp:chancePerMille(250) then hits = hits + 1 end
end
between(hits, 4700, 5300, "chancePerMille(250) fires about a quarter of the time")

-- ================================================================ Tables
end
section("Tables")
do

ok(Tables.isArray({ 1, 2, 3 }), "isArray accepts a dense array")
notOk(Tables.isArray({ [1] = 1, [3] = 3 }), "isArray rejects a holed array")
notOk(Tables.isArray({ a = 1 }), "isArray rejects a map")
eq(Tables.count({ a = 1, b = 2 }), 2, "count of a map")
local copied = Tables.copy({ a = 1, b = { c = 2 } })
eq(copied.a, 1, "copy preserves scalars")
local nested = { c = 2 }
local shallow = Tables.copy({ b = nested })
ok(shallow.b == nested, "copy is shallow")
local deep = Tables.deepCopy({ b = nested })
ok(deep.b ~= nested, "deepCopy makes a new table")
eq(deep.b.c, 2, "deepCopy preserves values")
ok(Tables.deepEqual({ 1, { 2, 3 } }, { 1, { 2, 3 } }), "deepEqual on identical structures")
notOk(Tables.deepEqual({ 1, { 2, 3 } }, { 1, { 2, 4 } }), "deepEqual on a differing leaf")
notOk(Tables.deepEqual({ a = 1 }, { a = 1, b = 2 }), "deepEqual notices an extra key")
local keys = Tables.sortedKeys({ z = 1, a = 1, m = 1 })
eq(keys[1] .. keys[2] .. keys[3], "amz", "sortedKeys sorts strings")
local mixed = Tables.sortedKeys({ [2] = 1, b = 1, [1] = 1, a = 1 })
eq(mixed[1], 1, "sortedKeys puts numbers before strings")
eq(mixed[4], "b", "sortedKeys orders the string tail")
local iterated = ""
for k in Tables.sortedPairs({ c = 1, a = 1, b = 1 }) do
	iterated = iterated .. k
end
eq(iterated, "abc", "sortedPairs iterates deterministically")

local toSort = { { k = 2, tag = "a" }, { k = 1, tag = "b" }, { k = 2, tag = "c" }, { k = 1, tag = "d" } }
Tables.insertionSort(toSort, 4, function(x, y)
	return x.k < y.k
end)
eq(toSort[1].tag .. toSort[2].tag, "bd", "insertionSort is stable for equal keys (low half)")
eq(toSort[3].tag .. toSort[4].tag, "ac", "insertionSort is stable for equal keys (high half)")

local pk = { 3, 1, 2 }
local pv = { "c", "a", "b" }
Tables.insertionSortPairs(pk, pv, 3)
ok(pk[1] == 1 and pk[2] == 2 and pk[3] == 3, "insertionSortPairs sorts the keys")
eq(pv[1] .. pv[2] .. pv[3], "abc", "insertionSortPairs permutes the payload identically")

local sortedArr = { { id = 1 }, { id = 4 }, { id = 9 } }
local idx, found = Tables.binarySearch(sortedArr, 3, "id", 4)
eq(idx, 2, "binarySearch finds the index")
ok(found, "binarySearch reports found")
idx, found = Tables.binarySearch(sortedArr, 3, "id", 5)
eq(idx, 3, "binarySearch returns the insertion point")
notOk(found, "binarySearch reports not-found")
eq(Tables.indexOf({ "a", "b" }, 2, "b"), 2, "indexOf finds")
eq(Tables.indexOf({ "a", "b" }, 2, "z"), 0, "indexOf misses")
local filled = Tables.fill({ 1, 2, 3 }, 3, 0)
eq(filled[1] + filled[2] + filled[3], 0, "fill overwrites in place")

local made = 0
local pool = Tables.pool(function()
	made = made + 1
	return { n = 0 }
end, function(o)
	o.n = 0
end, 2)
local o1 = pool:acquire()
o1.n = 5
pool:release(o1)
local o2 = pool:acquire()
ok(o1 == o2, "pool reuses a released object")
eq(o2.n, 0, "pool resets a released object")
eq(made, 1, "pool did not build a second object")
pool:release(o2)
pool:release({ n = 0 })
eq(pool:size(), 2, "pool respects its capacity")
notOk(pool:release({ n = 0 }), "pool refuses beyond capacity")

local frozen = Tables.deepFreeze({ a = 1, b = { c = 2 } })
eq(frozen.a, 1, "deepFreeze keeps values readable")
errors(function()
	frozen.a = 2
end, "a frozen table rejects writes")

-- ================================================================ Signal
end
section("Signal")
do

local sig = Signal.new("test")
local fired = 0
local lastArg = nil
local conn = sig:connect(function(v)
	fired = fired + 1
	lastArg = v
end)
eq(sig:fire(42), 1, "fire reports one delivery")
eq(fired, 1, "handler ran")
eq(lastArg, 42, "handler received the argument")
eq(sig:connectionCount(), 1, "one connection")
conn:disconnect()
eq(sig:fire(1), 0, "a disconnected handler does not run")
eq(sig:connectionCount(), 0, "disconnect removes the connection")
notOk(conn:disconnect(), "double disconnect is a no-op")

local onceCount = 0
sig:once(function()
	onceCount = onceCount + 1
end)
sig:fire()
sig:fire()
eq(onceCount, 1, "once fires exactly once")
eq(sig:connectionCount(), 0, "once self-disconnects")

local order = ""
sig:connect(function()
	order = order .. "a"
end)
sig:connect(function()
	order = order .. "b"
end)
sig:fire()
eq(order, "ab", "handlers run in connection order")

local sig2 = Signal.new("errors")
local afterRan = false
sig2:connect(function()
	error("boom")
end)
sig2:connect(function()
	afterRan = true
end)
errors(function()
	sig2:fire()
end, "a handler error is re-raised")
ok(afterRan, "a handler error does not stop later handlers")

local sig3 = Signal.new("reentrant")
local adds = 0
sig3:connect(function()
	adds = adds + 1
	sig3:connect(function()
		adds = adds + 1
	end)
end)
sig3:fire()
eq(adds, 1, "a handler connected during fire does not run in that fire")
sig3:destroy()
eq(sig3:connectionCount(), 0, "destroy clears every connection")

-- ================================================================ Codec
end
section("Codec")
do

local w = Codec.writer()
w:u8(0):u8(255):i8(-128):i8(127)
local b = w:build()
eq(#b, 4, "writer length")
eq(b[1], 0, "u8 min")
eq(b[2], 255, "u8 max")
eq(b[3], 128, "i8 -128 is two's complement 0x80")
eq(b[4], 127, "i8 127")

local rd = Codec.reader(b)
eq(rd:u8(), 0, "read u8 min")
eq(rd:u8(), 255, "read u8 max")
eq(rd:i8(), -128, "read i8 min")
eq(rd:i8(), 127, "read i8 max")
eq(rd:remaining(), 0, "reader consumed everything")

errors(function()
	Codec.writer():u8(256)
end, "u8 rejects 256")
errors(function()
	Codec.writer():u8(-1)
end, "u8 rejects -1")
errors(function()
	Codec.writer():u8(1.5)
end, "u8 rejects a fraction")
errors(function()
	Codec.writer():i8(128)
end, "i8 rejects 128")
errors(function()
	Codec.writer():u16(65536)
end, "u16 rejects 65536")
errors(function()
	Codec.writer():i16(-32769)
end, "i16 rejects -32769")
errors(function()
	Codec.writer():u32(4294967296)
end, "u32 rejects 2^32")
errors(function()
	Codec.writer():i32(2147483648)
end, "i32 rejects 2^31")
errors(function()
	Codec.writer():u48(281474976710656)
end, "u48 rejects 2^48")
errors(function()
	Codec.writer():u64(9007199254740994)
end, "u64 rejects values above 2^53")
errors(function()
	Codec.reader({ 1 }):u16()
end, "reader errors past the end")

local widths = {
	{ "u16", 0 }, { "u16", 1 }, { "u16", 65535 },
	{ "i16", -32768 }, { "i16", -1 }, { "i16", 0 }, { "i16", 32767 },
	{ "u32", 0 }, { "u32", 4294967295 }, { "u32", 16777216 },
	{ "i32", -2147483648 }, { "i32", -1 }, { "i32", 2147483647 },
	{ "u48", 0 }, { "u48", 281474976710655 },
	{ "u64", 0 }, { "u64", 9007199254740992 }, { "u64", 1234567890123 },
	{ "varint", 0 }, { "varint", 127 }, { "varint", 128 }, { "varint", 300 }, { "varint", 123456789 },
}
for i = 1, #widths do
	local kind = widths[i][1]
	local value = widths[i][2]
	local writer = Codec.writer()
	writer[kind](writer, value)
	local bytes = writer:build()
	local reader = Codec.reader(bytes)
	eq(reader[kind](reader), value, kind .. " round trips " .. tostring(value))
end

local lw = Codec.writer()
lw:u16(1):u16(258)
local lb = lw:build()
eq(lb[1], 1, "u16 is little-endian (low byte first)")
eq(lb[2], 0, "u16 high byte")
eq(lb[3], 2, "u16 258 low byte")
eq(lb[4], 1, "u16 258 high byte")

local pw = Codec.writer()
pw:u32(0):u8(9)
pw:patchU32(1, 4294967295)
local pb = pw:build()
eq(pb[1], 255, "patchU32 wrote byte 1")
eq(pb[4], 255, "patchU32 wrote byte 4")
eq(pb[5], 9, "patchU32 left the following byte alone")

local zw = Codec.writer():zeros(3)
eq(#zw:build(), 3, "zeros writes the right count")

eq(Codec.base64Encode({ 77, 97, 110 }), "TWFu", "base64 of 'Man'")
eq(Codec.base64Encode({ 77, 97 }), "TWE=", "base64 with one pad")
eq(Codec.base64Encode({ 77 }), "TQ==", "base64 with two pads")
eq(Codec.base64Encode({}), "", "base64 of nothing")
local rt = { 0, 1, 2, 253, 254, 255, 128, 64 }
ok(Codec.equal(Codec.base64Decode(Codec.base64Encode(rt)), rt), "base64 round trips arbitrary bytes")
for len = 1, 24 do
	local blob = {}
	for i = 1, len do
		blob[i] = (i * 37 + len) % 256
	end
	ok(Codec.equal(Codec.base64Decode(Codec.base64Encode(blob)), blob), "base64 round trips " .. len .. " bytes")
end
errors(function()
	Codec.base64Decode("ab$c")
end, "base64Decode rejects an invalid character")
eq(Codec.toHex({ 0, 15, 255 }), "000fff", "toHex")
ok(Codec.equal({ 1, 2 }, { 1, 2 }), "equal on identical arrays")
notOk(Codec.equal({ 1, 2 }, { 1, 3 }), "equal on differing arrays")
notOk(Codec.equal({ 1 }, { 1, 2 }), "equal on different lengths")

-- ================================================================ Schema
end
section("Schema")
do

local intSpec = { kind = "int", min = 0, max = 10 }
ok(Schema.check(5, intSpec), "int in range")
notOk(Schema.check(11, intSpec), "int above max")
notOk(Schema.check(-1, intSpec), "int below min")
notOk(Schema.check(5.5, intSpec), "int rejects a fraction")
notOk(Schema.check("5", intSpec), "int rejects a string")
notOk(Schema.check(nil, intSpec), "a required field must be present")
ok(Schema.check(nil, { kind = "int", optional = true }), "an optional field may be absent")
ok(Schema.check(1.5, { kind = "number", min = 0, max = 2 }), "number in range")
notOk(Schema.check(0 / 0, { kind = "number" }), "number rejects NaN")
ok(Schema.check("abc", { kind = "string", maxLen = 3 }), "string at the length limit")
notOk(Schema.check("abcd", { kind = "string", maxLen = 3 }), "string over the length limit")
ok(Schema.check(true, { kind = "boolean" }), "boolean")
notOk(Schema.check(1, { kind = "boolean" }), "boolean rejects a number")
ok(Schema.check("HIGH", { kind = "enum", values = { "LOW", "HIGH" } }), "enum accepts a member")
notOk(Schema.check("MID", { kind = "enum", values = { "LOW", "HIGH" } }), "enum rejects a non-member")
ok(Schema.check({ 1, 2 }, Schema.array(intSpec, 1, 3)), "array within bounds")
notOk(Schema.check({ 1, 2, 3, 4 }, Schema.array(intSpec, 1, 3)), "array over maxLen")
notOk(Schema.check({ 11 }, Schema.array(intSpec, 1, 3)), "array element validation")
local mapSpec = Schema.map({ a = intSpec, b = { kind = "string", optional = true } }, true)
ok(Schema.check({ a = 1 }, mapSpec), "map with an optional field absent")
notOk(Schema.check({ a = 1, z = 9 }, mapSpec), "a strict map rejects an unexpected field")
local okv, message = Schema.validate({ a = 99 }, mapSpec)
notOk(okv, "validate reports failure")
ok(string.find(message, "a:") == 1, "validate reports the failing path")
local compiled = Schema.compile(intSpec)
ok(compiled(3), "compiled validator accepts")
notOk(compiled(30), "compiled validator rejects")
errors(function()
	Schema.check(1, { kind = "nonsense" })
end, "an unknown kind is a programming error and throws")

-- ================================================================ Tide
end
section("Tide")
do

local E = Tide.EPOCH
eq(E, 1767225600, "EPOCH is 2026-01-01T00:00:00Z")
eq(Tide.EPOCH_SECONDS, 22357, "one tide epoch is 22357 s")

-- Doc 02 section 8, vector by vector. Three of the twelve were wrong in the
-- document; the corrected expectations are asserted here and the corrections
-- are recorded in HANDOFF.md.
near(Tide.height(E), 15.5, 1e-9, "V1  height(EPOCH) == 15.5")
near(Tide.velocity(E), 0.0, 1e-9, "V2  velocity(EPOCH) == 0")
eq(Tide.epoch(E), 0, "V3  epoch(EPOCH) == 0")
eq(Tide.epoch(E + 22356), 0, "V4  epoch(EPOCH + 22356) == 0")
eq(Tide.epoch(E + 22357), 1, "V5  epoch(EPOCH + 22357) == 1")
near(Tide.height(E + 44714), 11.232754472632912, 1e-9, "V6  height(EPOCH + T_M2) (doc said within 0.9 of 15.5; it is 4.267 away)")

local vmin, vmax = math.huge, -math.huge
local meanSum, meanCount = 0, 0
local lowEntries = 0
local wasLow = false
local dailyMin, dailyMax = math.huge, -math.huge
local dayLo, dayHi = math.huge, -math.huge
local dayIndex = 0
local nilStateChange = 0
for step = 0, 86399 do
	local t = E + step * 60
	local h = Tide.height(t)
	if h < vmin then vmin = h end
	if h > vmax then vmax = h end
	if step < 43200 then
		meanSum = meanSum + h
		meanCount = meanCount + 1
		local isLow = Tide.state(t) == "LOW"
		if isLow and not wasLow then
			lowEntries = lowEntries + 1
		end
		wasLow = isLow
	end
	if h < dayLo then dayLo = h end
	if h > dayHi then dayHi = h end
	if (step + 1) % 1440 == 0 then
		local range = dayHi - dayLo
		if range < dailyMin then dailyMin = range end
		if range > dailyMax then dailyMax = range end
		dayLo, dayHi = math.huge, -math.huge
		dayIndex = dayIndex + 1
	end
end
eq(dayIndex, 60, "the sweep covered 60 days")
ok(vmax <= Tide.MAX_HEIGHT + 1e-9, "V7a height never exceeds the amplitude sum")
ok(vmin >= -Tide.MAX_HEIGHT - 1e-9, "V7b height never falls below minus the amplitude sum")
near(meanSum / meanCount, 0.0, 0.05, "V8  30-day mean is zero")
between(lowEntries, 50, 54, "V9  LOW entries over 30 days (doc said 55..65; the constants give 52)")
between(dailyMax, 29.5, 30.0, "V12a spring peak daily range (doc said 26.8; K1 lifts it to 29.73)")
between(dailyMin, 15.8, 16.2, "V12b neap trough daily range (doc said 13.2; K1 lifts it to 15.97)")

for i = 0, 19 do
	local t = E + i * 3617
	local change = Tide.nextStateChange(t)
	if change == nil then
		nilStateChange = nilStateChange + 1
	end
end
eq(nilStateChange, 0, "V10 nextStateChange never returns nil inside a 7-day horizon")

local h0 = Tide.height(E + 12345.5)
local drift = 0
for _ = 1, 10000 do
	if Tide.height(E + 12345.5) ~= h0 then
		drift = drift + 1
	end
end
eq(drift, 0, "V11 height is bit-identical across 10 000 repeated calls")

-- State machine.
eq(Tide.state(E), "HIGH", "at the epoch the tide is HIGH")
local states = {}
for step = 0, 2000 do
	states[Tide.state(E + step * 137)] = true
end
ok(states.LOW == true, "LOW occurs")
ok(states.HIGH == true, "HIGH occurs")
ok(states.SLACK == true, "SLACK occurs")
ok(states.EBB == true, "EBB occurs")
ok(states.FLOOD == true, "FLOOD occurs")
local badState = 0
for step = 0, 5000 do
	local s = Tide.state(E + step * 53)
	if s ~= "LOW" and s ~= "HIGH" and s ~= "SLACK" and s ~= "EBB" and s ~= "FLOOD" then
		badState = badState + 1
	end
end
eq(badState, 0, "state is always one of the five names")

-- EBB/FLOOD must follow the analytic derivative, not a finite difference.
local mismatched = 0
for step = 0, 3000 do
	local t = E + step * 71
	local s = Tide.state(t)
	if s == "EBB" and Tide.velocity(t) >= 0 then mismatched = mismatched + 1 end
	if s == "FLOOD" and Tide.velocity(t) < 0 then mismatched = mismatched + 1 end
end
eq(mismatched, 0, "EBB and FLOOD agree with the sign of the derivative")

eq(Tide.epochStart(0), E, "epochStart(0) is the epoch")
eq(Tide.epochStart(Tide.epoch(E + 100000)), E + 4 * 22357, "epochStart inverts epoch")
eq(Tide.epoch(E - 1), -1, "epoch is negative before the game epoch")
eq(Tide.epoch(E - 22357), -1, "epoch floors toward negative infinity")
eq(Tide.epoch(E - 22358), -2, "epoch stays monotonic across the boundary")
near(Tide.epochProgress(E), 0, 1e-12, "epochProgress at an epoch start")
near(Tide.epochProgress(E + 11178.5), 0.5, 1e-6, "epochProgress at the midpoint")

local changeAt, newState = Tide.nextStateChange(E)
ok(changeAt > E, "nextStateChange is strictly in the future")
eq(changeAt, math.floor(changeAt), "nextStateChange returns an integer second")
neq(newState, Tide.state(E), "nextStateChange reports a different state")
eq(Tide.state(changeAt), newState, "the reported state matches the returned second")
eq(Tide.state(changeAt - 1), Tide.state(E), "the second before the change still has the old state")
eq(Tide.nextStateChange(E, 1), nil, "a one-second horizon finds nothing")

local low = Tide.nextLowWater(E)
ok(low ~= nil, "nextLowWater finds a turning point")
ok(Tide.velocity(low - 30) < 0, "the tide is falling before low water")
ok(Tide.velocity(low + 30) > 0, "the tide is rising after low water")
local high = Tide.nextHighWater(E + 3600)
ok(high ~= nil, "nextHighWater finds a turning point")
ok(Tide.velocity(high - 30) > 0, "the tide is rising before high water")
ok(Tide.velocity(high + 30) < 0, "the tide is falling after high water")

local rlo, rhi, dayStart = Tide.rangeForDay(E + 50000)
ok(rhi > rlo, "rangeForDay returns an ordered pair")
eq(dayStart % 86400, 0, "rangeForDay snaps to a UTC day")
ok(rhi <= Tide.MAX_HEIGHT + 1e-9, "rangeForDay respects the amplitude bound")
local epochState = Tide.stateForEpoch(3)
ok(epochState == Tide.state(Tide.epochStart(3) + 22357 * 0.5), "stateForEpoch samples the midpoint")

-- 27 epochs is the clamp, and it must really be about a week.
near(27 * 22357 / 86400, 6.9865625, 1e-6, "27 tide epochs is 6.99 days, not exactly 7")

-- ================================================================ Version
end
section("Version")
do

eq(Version.CURRENT, GameConfig.SCHEMA_VERSION, "Version.CURRENT tracks GameConfig")
eq(Version.classify(Version.CURRENT), Version.OK, "the current version is OK")
eq(Version.classify(Version.CURRENT + 1), Version.TOO_NEW, "a newer blob is refused")
eq(Version.classify(0), Version.TOO_OLD, "a blob below the oldest supported is refused")
eq(Version.classify("1"), Version.NO_PATH, "a non-integer version is refused")
local migrated, reason = Version.migrate({ n = 1 }, Version.CURRENT + 1)
eq(migrated, nil, "migrate refuses a future blob")
eq(reason, Version.TOO_NEW, "migrate reports TOO_NEW")

-- Exercise the chain walker without shipping a fake migration.
Version._reset()
local realCurrent = Version.CURRENT
Version.CURRENT = 3
Version.OLDEST_SUPPORTED = 1
eq(Version.classify(1), Version.NO_PATH, "no migration means no path")
Version.register(1, 2, function(d)
	d.steps = (d.steps or 0) + 1
	return d
end)
eq(Version.classify(1), Version.NO_PATH, "a partial chain is still no path")
Version.register(2, 3, function(d)
	d.steps = (d.steps or 0) + 1
	return d
end)
eq(Version.classify(1), Version.OK, "a complete chain classifies OK")
eq(Version.registeredCount(), 2, "two migrations are registered")
ok(Version.hasMigration(1), "hasMigration finds a step")
notOk(Version.hasMigration(9), "hasMigration misses an absent step")
local walked = Version.migrate({ steps = 0 }, 1)
eq(walked.steps, 2, "migrate walks every step in the chain")
errors(function()
	Version.register(1, 2, function(d)
		return d
	end)
end, "a duplicate migration is refused")
errors(function()
	Version.register(1, 3, function(d)
		return d
	end)
end, "a migration may not skip a version")
Version.register(3, 4, function()
	error("deliberate failure")
end)
Version.CURRENT = 4
local failed, failReason = Version.migrate({}, 3)
eq(failed, nil, "a throwing migration fails cleanly")
eq(failReason, Version.NO_PATH, "a throwing migration reports NO_PATH")
Version._reset()
Version.CURRENT = realCurrent
Version.OLDEST_SUPPORTED = 1
-- Restore the real migration chain that PostCodec registered at load time.
-- _reset() above wiped it, and every PostCodec test after this point needs
-- the v1 -> v2 step to exist (OD16).
PostCodec.registerMigrations()
eq(Version.registeredCount(), 1, "the real v1 -> v2 migration is restored after the reset")
ok(Version.hasMigration(1), "PostCodec registered a migration from v1")

-- ================================================================ DrifterCodec
end
section("DrifterCodec")
do

eq(DrifterCodec.SIZE, 68, "a drifter record is 68 bytes")
local owner = 4455667788
local idA = DrifterCodec.makeId(owner, 100)
eq(DrifterCodec.ownerFromId(idA), owner, "the owner survives the id packing")
eq(DrifterCodec.epochLowFromId(idA), 100, "the epoch survives the id packing")
ok(idA < 9007199254740992, "the id stays below 2^53 and is therefore exact")
neq(DrifterCodec.makeId(owner, 100), DrifterCodec.makeId(owner, 101), "ids differ by epoch")
neq(DrifterCodec.makeId(owner, 100), DrifterCodec.makeId(owner + 1, 100), "ids differ by owner")
eq(DrifterCodec.makeId(owner, 8192), DrifterCodec.makeId(owner, 0), "the epoch field wraps at 8192 as documented")
errors(function()
	DrifterCodec.makeId(GameConfig.OWNER_ID_MAX + 1, 0)
end, "makeId refuses an owner beyond the representable range")

local dref = mkDrifter(owner, 100, Drifter.LUGGER, 2, 3, 1500, { -100, 0, 50, 127 - 128, 7, -7, 100, 1 }, { 3, 9 }, { 12 })
dref.standing = 4321
dref.renown = 777
dref.letterId = 40
dref.beacons = 5
local blob = DrifterCodec.encode(dref)
eq(#blob, 68, "encode produces exactly 68 bytes")
eq(blob[68], 0, "the reserved byte is zero")
local back, err = DrifterCodec.decode(blob)
eq(err, nil, "decode succeeds")
eq(back.id, dref.id, "id round trips")
eq(back.owner, dref.owner, "owner round trips")
eq(back.epoch, dref.epoch, "epoch round trips")
eq(back.current, dref.current, "current round trips")
eq(back.class, dref.class, "class round trips")
eq(back.tier, dref.tier, "tier round trips")
eq(back.standing, dref.standing, "standing round trips")
eq(back.renown, dref.renown, "renown round trips")
eq(back.budget, dref.budget, "budget round trips")
eq(back.letterId, dref.letterId, "letterId round trips")
eq(back.beacons, dref.beacons, "beacons round trips")
eq(back.look, dref.look, "look round trips")
local tasteOk = true
for i = 1, 8 do
	if back.taste[i] ~= dref.taste[i] then tasteOk = false end
end
ok(tasteOk, "the whole taste vector round trips, including negatives")
eq(#back.wants, 2, "wants keeps its length")
eq(back.wants[1], 3, "wants[1] round trips")
eq(back.wants[2], 9, "wants[2] round trips")
eq(#back.cargo, 1, "cargo keeps its length")
eq(back.cargo[1], 12, "cargo[1] round trips")

local corrupt = {}
for i = 1, 68 do
	corrupt[i] = blob[i]
end
corrupt[30] = (corrupt[30] + 1) % 256
local bad, badErr = DrifterCodec.decode(corrupt)
eq(bad, nil, "a corrupted record is rejected")
ok(string.find(badErr, "checksum") ~= nil, "the rejection names the checksum")
eq(DrifterCodec.decode({ 1, 2, 3 }), nil, "a truncated record is rejected")

local shardList = {}
for i = 1, 200 do
	shardList[i] = mkDrifter(1000000 + i, 50 + i, Drifter.SKIFF, i % 5, 1, 50 + i, nil, {}, {})
end
local shard = DrifterCodec.encodeShard(shardList, 200)
eq(#shard, 3 + 200 * 68 + 4, "a 200-record shard is 13607 bytes on the wire")
between(#shard / 1024, 13.2, 13.4, "a 200-record shard is about 13.3 KB (doc 03 section 6)")
local shardBack, shardErr = DrifterCodec.decodeShard(shard)
eq(shardErr, nil, "the shard decodes")
eq(#shardBack, 200, "every record came back")
eq(shardBack[137].owner, 1000137, "a record in the middle of the shard is intact")
eq(shardBack[200].epoch, 250, "the last record is intact")
local shardCorrupt = {}
for i = 1, #shard do
	shardCorrupt[i] = shard[i]
end
shardCorrupt[500] = (shardCorrupt[500] + 1) % 256
eq(DrifterCodec.decodeShard(shardCorrupt), nil, "a corrupted shard is rejected")
eq(DrifterCodec.decodeShard({ 9, 0, 0, 0, 0, 0, 0 }), nil, "an unknown shard version is rejected")

-- ================================================================ Standing
end
section("Standing")
do

eq(Standing.MAX, 65535, "Standing is a u16")
eq(Standing.bandOf(0), 0, "below the first band")
eq(Standing.bandOf(249), 0, "just below the first band")
eq(Standing.bandOf(250), 1, "at the first band")
eq(Standing.bandOf(999), 1, "between bands")
eq(Standing.bandOf(30000), 5, "at the top band")
eq(Standing.bandOf(65535), 5, "above the top band")
eq(Standing.floorOf(0), 0, "floor below the first band")
eq(Standing.floorOf(11000), 4000, "floor of 11000 is 4000")
eq(Standing.nextBandAt(11000), 12000, "next band above 11000")
eq(Standing.nextBandAt(40000), nil, "no band above the top")
near(Standing.bandProgress(4000), 0, 1e-12, "progress at a band floor")
near(Standing.bandProgress(8000), 0.5, 1e-12, "progress halfway to the next band")
eq(Standing.bandProgress(40000), 1, "progress is 1 in the top band")

eq(Standing.decay(0), 0, "zero does not decay")
eq(Standing.decay(250), 250, "a value sitting on its floor does not decay")
eq(Standing.decay(11000), 11000 - math.floor(7000 * 25 / 1000), "decay is 2.5% of the excess")
eq(Standing.decay(4001), 4000, "a value one above the floor decays to the floor, not below")
eq(Standing.decay(4040), 4039, "a small excess still loses at least one point")
local sustained = 11000
for _ = 1, 54 do
	sustained = Standing.decay(sustained)
end
eq(sustained, 5798, "a fortnight (54 epochs) of decay from 11000 lands at 5798 -- doc 06 section 2 guessed ~4700, which assumed decay toward zero rather than toward the band floor")
ok(Standing.decayN(11000, 54) == sustained, "decayN agrees with repeated decay")
local floorHeld = 30000
for _ = 1, 500 do
	floorHeld = Standing.decay(floorHeld)
end
eq(floorHeld, 30000, "500 epochs of decay never breach a crossed band")
local everyBand = { 0, 250, 1000, 4000, 12000, 30000 }
for i = 1, #everyBand do
	local v = everyBand[i]
	for _ = 1, 200 do
		v = Standing.decay(v)
	end
	eq(v, everyBand[i], "band floor " .. everyBand[i] .. " is permanent")
end

eq(Standing.grant(100, 50), 150, "grant adds")
eq(Standing.grant(65535, 100), 65535, "grant clamps at the maximum")
eq(Standing.grant(10, -100), 0, "grant clamps at zero")
eq(Standing.grant(4100, -500), 4000, "a penalty cannot push below a crossed band")
eq(Standing.grant(200, -100), 100, "below the first band a penalty applies in full")
local vector = { 11000, 250, 0, 4001, 30000 }
Standing.decayAll(vector)
eq(vector[1], 10825, "decayAll decays index 1")
eq(vector[2], 250, "decayAll leaves a floored value alone")
eq(vector[3], 0, "decayAll leaves zero alone")
eq(vector[4], 4000, "decayAll floors index 4")
eq(vector[5], 30000, "decayAll leaves the top band alone")

-- ================================================================ Almanac
end
section("Almanac")
do

local alm = Almanac.new()
eq(Almanac.BYTES, 32, "the Almanac is 32 bytes")
eq(Almanac.count(alm), 0, "a new Almanac is empty")
notOk(Almanac.has(alm, 1), "a new Almanac has nothing")
ok(Almanac.record(alm, 1), "recording a new find reports true")
notOk(Almanac.record(alm, 1), "recording a known find reports false")
ok(Almanac.has(alm, 1), "the find is now known")
notOk(Almanac.has(alm, 2), "a neighbouring bit was not set")
eq(Almanac.count(alm), 1, "count is 1")
Almanac.record(alm, 8)
Almanac.record(alm, 9)
Almanac.record(alm, 256)
eq(Almanac.count(alm), 4, "count tracks across byte boundaries")
ok(Almanac.has(alm, 8), "bit 8 is the last bit of byte 1")
ok(Almanac.has(alm, 9), "bit 9 is the first bit of byte 2")
ok(Almanac.has(alm, 256), "bit 256 is the last bit of byte 32")
notOk(Almanac.record(alm, 257), "an id beyond 256 is refused")
notOk(Almanac.record(alm, 0), "id 0 is refused")
notOk(Almanac.has(alm, 999), "has() is total for an out-of-range id")
local list = Almanac.toList(alm)
eq(#list, 4, "toList returns every recorded id")
eq(list[1], 1, "toList is ascending")
eq(list[4], 256, "toList includes the last id")
ok(Almanac.isValid(Almanac.fromList({ 5, 6, 7 })), "fromList produces a valid bitset")
eq(Almanac.count(Almanac.fromList({ 5, 5, 5 })), 1, "fromList deduplicates")
notOk(Almanac.isValid({ 1, 2 }), "a short array is not a valid bitset")
local fullAlm = Almanac.new()
for i = 1, #FindsConfig.FINDS do
	Almanac.record(fullAlm, FindsConfig.FINDS[i][1])
end
near(Almanac.completion(fullAlm), 1.0, 1e-12, "completion is 1 when every shipped find is known")
near(Almanac.completion(Almanac.new()), 0.0, 1e-12, "completion is 0 for an empty Almanac")

-- ================================================================ Post
end
section("Post")
do

local P = mkPost(3)
ok(Post.checkInvariants(P), "the fixture post satisfies its invariants")
eq(Post.stockOf(P, 1), 40, "stockOf finds an entry")
eq(Post.stockOf(P, 999), 0, "stockOf is 0 for an unknown find")
eq(Post.distinctStock(P), 7, "seven distinct finds in stock")
eq(Post.totalStock(P), 124, "total stock is the sum of the stacks")
local ascending = true
for i = 2, #P.store do
	if P.store[i].id <= P.store[i - 1].id then ascending = false end
end
ok(ascending, "the store is strictly ascending by find id")
Post.addStock(P, 2, 5)
eq(Post.stockOf(P, 2), 5, "addStock inserts a new entry")
eq(P.store[2].id, 2, "the new entry landed in sorted position")
Post.addStock(P, 2, 5)
eq(Post.stockOf(P, 2), 10, "addStock stacks")
eq(Post.removeStock(P, 2, 3), 3, "removeStock reports what it took")
eq(Post.stockOf(P, 2), 7, "removeStock decremented")
eq(Post.removeStock(P, 2, 100), 7, "removeStock never takes more than is present")
eq(Post.stockOf(P, 2), 0, "the entry is gone")
eq(Post.removeStock(P, 999, 1), 0, "removing an absent find is a no-op")
eq(Post.addStock(P, 1, 0), 0, "addStock refuses a non-positive quantity")
ok(Almanac.has(P.almanac, 1), "holding a find records it in the Almanac")
notOk(Almanac.has(P.almanac, 21), "a find never held is not in the Almanac")

eq(Post.baseValue(1), 3, "baseValue reads FindsConfig")
eq(Post.baseValue(999), 0, "baseValue of an unknown find is 0")
ok(Post.isPerishable(10), "gull_bone is perishable")
notOk(Post.isPerishable(1), "cockle_shell is not perishable")
eq(Post.groupOf(3), 2, "sea_glass_green is in the Glass group")
eq(#Post.tasteOf(1), 8, "a find's taste vector has eight axes")
eq(Post.tasteOf(999), nil, "an unknown find has no taste vector")
eq(Post.knownFindCount(), 200, "the v1 content set ships 200 finds")

-- The calibrated tier costs. economy-sim.lua is too slow (~2 min) to run on
-- every build, so this is the cheap guard that the curve it calibrated has
-- not been edited away: the costs must stay strictly increasing and must
-- match the values doc 06 quotes. Change them and you must re-run the sim.
eq(#EconomyConfig.TIER_COST, GameConfig.MAX_TIER, "there is a price for every tier")
eq(EconomyConfig.TIER_COST[1], 0, "tier 1 is free -- every post starts there")
local risingCost = true
for t = 2, GameConfig.MAX_TIER do
	if EconomyConfig.TIER_COST[t] <= EconomyConfig.TIER_COST[t - 1] then
		risingCost = false
	end
end
ok(risingCost, "each tier costs strictly more than the one below it")
eq(EconomyConfig.TIER_COST[2], 320, "the measured tier 2 price (doc 06: ~day 3)")
eq(EconomyConfig.TIER_COST[3], 3400, "the measured tier 3 price (doc 06: ~day 16)")
eq(EconomyConfig.TIER_COST[4], 15500, "the measured tier 4 price (doc 06: ~day 52)")

-- ------------------------------------------------------------- promotion
-- Nothing in the game promoted a post until iteration 7, so every tier-gated
-- system was dead. These pin the arithmetic.
local promo = mkPost(1)
promo.tier = 1
promo.coin = 0
eq(Post.promotionCost(promo), EconomyConfig.TIER_COST[2], "tier 1 quotes the tier 2 price")
notOk(Post.promote(promo), "a post that cannot afford the next tier is refused")
eq(promo.tier, 1, "a refused promotion does not change the tier")

promo.coin = EconomyConfig.TIER_COST[2]
ok(Post.promote(promo), "a post that can afford it is promoted")
eq(promo.tier, 2, "the tier went up by exactly one")
eq(promo.coin, 0, "the coin was actually spent")
ok(Post.maxShelves(promo.tier) > Post.maxShelves(1), "a promoted post really does get more shelves")

-- Walk it to the cap and check the cap holds.
promo.coin = EconomyConfig.TIER_COST[3]
ok(Post.promote(promo), "tier 3 is reachable")
promo.coin = EconomyConfig.TIER_COST[4]
ok(Post.promote(promo), "tier 4 is reachable")
eq(promo.tier, GameConfig.MAX_TIER, "the walk ends at MAX_TIER")
eq(Post.promotionCost(promo), nil, "there is no price above the cap")
promo.coin = 999999
notOk(Post.promote(promo), "a maxed post cannot be promoted again however rich it is")
eq(promo.coin, 999999, "...and refusing it does not take the coin")
ok(Post.checkInvariants(promo), "a promoted post is structurally valid")

eq(Post.maxShelves(1), 6, "tier 1 has six shelves")
eq(Post.maxShelves(4), 24, "tier 4 has twenty-four shelves")
eq(Post.shelfCount(P), 6, "the fixture uses six shelves")
notOk(Post.setShelf(P, 99, 1, 5), "setShelf refuses a slot beyond the tier limit")
notOk(Post.setShelf(P, 1, 999, 5), "setShelf refuses an unknown find")
notOk(Post.setShelf(P, 1, 1, 0), "setShelf refuses a price below the minimum")
notOk(Post.setShelf(P, 1, 1, 1.5), "setShelf refuses a fractional price")
ok(Post.setShelf(P, 1, 1, 5), "setShelf accepts a valid placement")
-- A gap makes the post unsaveable: PostCodec writes `#shelves` and then
-- indexes 1..n, so a nil in the middle throws during encode. `PostHandler`
-- hands a client-supplied slot straight to setShelf, so this is the check
-- that stops a client breaking its own save.
local gapPost = mkPost(4)
gapPost.shelves = {}
notOk(Post.setShelf(gapPost, 3, 1, 5), "setShelf refuses a slot that would leave a gap")
ok(Post.setShelf(gapPost, 1, 1, 5), "setShelf accepts the first slot")
ok(Post.setShelf(gapPost, 2, 2, 5), "setShelf accepts the next slot in sequence")
ok(Post.setShelf(gapPost, 2, 3, 7), "setShelf accepts overwriting an occupied slot")
eq(#gapPost.shelves, 2, "a dense shelf array stays dense")
local encoded = PostCodec.encode(gapPost)
ok(encoded ~= nil and #encoded > 0, "a post arranged through setShelf always encodes")
ok(Post.clearShelf(P, 1), "clearShelf removes a shelf")
eq(Post.shelfCount(P), 5, "the shelves compacted")
notOk(Post.clearShelf(P, 99), "clearing an empty slot is a no-op")
ok(Post.shelvedValue(P) > 0, "shelvedValue counts displayed stock")

eq(Post.maxOrderRules(1), 6, "tier 1 allows six rules")
eq(Post.maxOrderRules(4), 24, "tier 4 allows twenty-four rules")
eq(Post.maxOrderRules(99), 6, "an unknown tier falls back to the tier-1 cap")
eq(Post.passiveCap(1), 40, "tier 1 passive cap")
eq(Post.passiveCap(4), 1200, "tier 4 passive cap")

Post.recordVisit(P, 5001, 10)
Post.recordVisit(P, 5002, 10)
Post.recordVisit(P, 5001, 11)
eq(Post.visitCount(P, 5001), 2, "visitCount counts a returning face")
eq(Post.visitCount(P, 9999), 0, "visitCount of a stranger is 0")
eq(P.ring[1].epoch, 11, "the ring is most-recent-first")
for i = 1, 100 do
	Post.recordVisit(P, 6000 + i, 12)
end
eq(#P.ring, GameConfig.VISITOR_RING_SIZE, "the visitor ring is bounded")
ok(Post.checkInvariants(P), "the post is still valid after the ring overflowed")

local broken = mkPost(3)
broken.coin = -1
notOk(Post.checkInvariants(broken), "a negative coin balance fails the invariants")
broken = mkPost(3)
broken.store[1].qty = 0
notOk(Post.checkInvariants(broken), "a zero-quantity store entry fails the invariants")
broken = mkPost(3)
broken.store[1].id = 99
notOk(Post.checkInvariants(broken), "an unsorted store fails the invariants")
broken = mkPost(4)
Post.setShelf(broken, 7, 10, 6)
broken.tier = 1
notOk(Post.checkInvariants(broken), "seven shelves is too many once the post is demoted to tier 1")
broken = mkPost(3)
broken.standing[1] = -1
notOk(Post.checkInvariants(broken), "negative Standing fails the invariants")
broken = mkPost(3)
broken.almanac = { 1, 2 }
notOk(Post.checkInvariants(broken), "a malformed Almanac fails the invariants")

-- ================================================================ Orders
end
section("Orders")
do

local emptyProgram = Orders.empty()
ok(Orders.validate(emptyProgram, 1), "an empty program is valid")
local action, ruleIndex = Orders.evaluate(emptyProgram, {})
eq(action.op, Orders.SERVE, "an empty program serves")
eq(ruleIndex, 0, "an empty program reports rule 0")
eq(Orders.evaluate(nil, {}), Orders.DEFAULT_ACTION, "a nil program falls back to the default")
eq(Orders.evaluate({ version = 1 }, {}), Orders.DEFAULT_ACTION, "a program with no rules array falls back")
eq(Orders.evaluate({ version = 1, rules = { "junk" } }, {}), Orders.DEFAULT_ACTION, "a malformed rule is skipped, not fatal")

eq(Orders.conditionName(Orders.ALWAYS), "ALWAYS", "conditionName")
eq(Orders.conditionName(200), "UNKNOWN", "conditionName of an unknown opcode")
eq(Orders.actionName(Orders.GIFT), "GIFT", "actionName")
eq(Orders.actionName(200), "UNKNOWN", "actionName of an unknown opcode")

local facts = {
	class = Drifter.LUGGER,
	current = 2,
	standing = 5000,
	tide = "SLACK",
	wantsSomething = true,
	budget = 900,
	beacons = 4,
	taste = { 0, 60, 70, 0, 0, 0, 0, 0 },
	visits = 3,
}
ok(Orders.evalCondition(Orders.cond(Orders.ALWAYS), facts), "ALWAYS matches")
ok(Orders.evalCondition(Orders.cond(Orders.CLASS_IS, Drifter.LUGGER), facts), "CLASS_IS matches")
notOk(Orders.evalCondition(Orders.cond(Orders.CLASS_IS, Drifter.SKIFF), facts), "CLASS_IS rejects")
ok(Orders.evalCondition(Orders.cond(Orders.CURRENT_IS, 2), facts), "CURRENT_IS matches")
notOk(Orders.evalCondition(Orders.cond(Orders.CURRENT_IS, 0), facts), "CURRENT_IS rejects")
ok(Orders.evalCondition(Orders.cond(Orders.STANDING_GTE, 4000), facts), "STANDING_GTE matches")
ok(Orders.evalCondition(Orders.cond(Orders.STANDING_GTE, 5000), facts), "STANDING_GTE is inclusive")
notOk(Orders.evalCondition(Orders.cond(Orders.STANDING_GTE, 5001), facts), "STANDING_GTE rejects")
ok(Orders.evalCondition(Orders.cond(Orders.TIDE_IS, 4), facts), "TIDE_IS matches SLACK")
notOk(Orders.evalCondition(Orders.cond(Orders.TIDE_IS, 1), facts), "TIDE_IS rejects LOW")
ok(Orders.evalCondition(Orders.cond(Orders.WANTS_SOMETHING), facts), "WANTS_SOMETHING matches")
ok(Orders.evalCondition(Orders.cond(Orders.BUDGET_GTE, 900), facts), "BUDGET_GTE is inclusive")
notOk(Orders.evalCondition(Orders.cond(Orders.BUDGET_GTE, 901), facts), "BUDGET_GTE rejects")
ok(Orders.evalCondition(Orders.cond(Orders.BEACONS_GTE, 4), facts), "BEACONS_GTE matches")
notOk(Orders.evalCondition(Orders.cond(Orders.BEACONS_GTE, 5), facts), "BEACONS_GTE rejects")
ok(Orders.evalCondition(Orders.cond(Orders.TASTE_GT, 3, 60), facts), "TASTE_GT matches on axis 3")
notOk(Orders.evalCondition(Orders.cond(Orders.TASTE_GT, 3, 70), facts), "TASTE_GT is strict")
notOk(Orders.evalCondition(Orders.cond(Orders.TASTE_GT, 99, 0), facts), "TASTE_GT is total for a bad axis")
ok(Orders.evalCondition(Orders.cond(Orders.VISITS_GTE, 3), facts), "VISITS_GTE matches")
notOk(Orders.evalCondition(Orders.cond(Orders.VISITS_GTE, 4), facts), "VISITS_GTE rejects")
ok(Orders.evalCondition(Orders.compound(Orders.AND, Orders.cond(Orders.ALWAYS), Orders.cond(Orders.CURRENT_IS, 2)), facts), "AND with both true")
notOk(Orders.evalCondition(Orders.compound(Orders.AND, Orders.cond(Orders.ALWAYS), Orders.cond(Orders.CURRENT_IS, 0)), facts), "AND with one false")
ok(Orders.evalCondition(Orders.compound(Orders.OR, Orders.cond(Orders.CURRENT_IS, 0), Orders.cond(Orders.ALWAYS)), facts), "OR with one true")
notOk(Orders.evalCondition(Orders.compound(Orders.OR, Orders.cond(Orders.CURRENT_IS, 0), Orders.cond(Orders.CLASS_IS, 0)), facts), "OR with both false")
notOk(Orders.evalCondition(Orders.compound(Orders.AND, nil, nil), facts), "AND with missing terms is total")
notOk(Orders.evalCondition({ op = 200 }, facts), "an unknown opcode evaluates false")
notOk(Orders.evalCondition("junk", facts), "a non-table condition evaluates false")

-- First match wins.
local ladder = Orders.empty()
ladder.rules[1] = Orders.rule(Orders.cond(Orders.CLASS_IS, Drifter.SKIFF), Orders.act(Orders.REFUSE))
ladder.rules[2] = Orders.rule(Orders.cond(Orders.CLASS_IS, Drifter.LUGGER), Orders.act(Orders.SERVE_ADJ, 25))
ladder.rules[3] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.REFUSE))
local chosen, chosenIndex = Orders.evaluate(ladder, facts)
eq(chosen.op, Orders.SERVE_ADJ, "the first matching rule wins")
eq(chosen.a, 25, "the action argument comes through")
eq(chosenIndex, 2, "the rule index is reported")
facts.class = Drifter.DEEPWATER
chosen, chosenIndex = Orders.evaluate(ladder, facts)
eq(chosen.op, Orders.REFUSE, "falling through to the catch-all")
eq(chosenIndex, 3, "the catch-all index is reported")
facts.class = Drifter.LUGGER

-- Tier gating.
local tierProgram = Orders.empty()
tierProgram.rules[1] = Orders.rule(Orders.cond(Orders.STANDING_GTE, 100), Orders.act(Orders.SERVE))
notOk(Orders.validate(tierProgram, 1), "STANDING_GTE is not available at tier 1")
ok(Orders.validate(tierProgram, 2), "STANDING_GTE is available at tier 2")
tierProgram.rules[1] = Orders.rule(Orders.cond(Orders.VISITS_GTE, 2), Orders.act(Orders.SERVE))
notOk(Orders.validate(tierProgram, 3), "VISITS_GTE is not available at tier 3")
ok(Orders.validate(tierProgram, 4), "VISITS_GTE is available at tier 4")
tierProgram.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.GIFT, 1))
notOk(Orders.validate(tierProgram, 3), "GIFT is not available at tier 3")
ok(Orders.validate(tierProgram, 4), "GIFT is available at tier 4")
tierProgram.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, 10))
notOk(Orders.validate(tierProgram, 1), "SERVE_ADJ is not available at tier 1")
ok(Orders.validate(tierProgram, 2), "SERVE_ADJ is available at tier 2")
tierProgram.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, 41))
notOk(Orders.validate(tierProgram, 4), "SERVE_ADJ rejects more than +40%")
tierProgram.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, -41))
notOk(Orders.validate(tierProgram, 4), "SERVE_ADJ rejects less than -40%")
tierProgram.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, -40))
ok(Orders.validate(tierProgram, 4), "SERVE_ADJ accepts exactly -40%")

local overCap = Orders.empty()
for i = 1, 7 do
	overCap.rules[i] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE))
end
notOk(Orders.validate(overCap, 1), "seven rules exceed the tier-1 cap of six")
ok(Orders.validate(overCap, 2), "seven rules fit the tier-2 cap of ten")
notOk(Orders.validate({ version = 99, rules = {} }, 4), "an unknown program version is refused")
notOk(Orders.validate("junk", 4), "a non-table program is refused")
notOk(Orders.validate(Orders.empty(), 99), "an unknown tier is refused")
local badArg = Orders.empty()
badArg.rules[1] = Orders.rule(Orders.cond(Orders.STANDING_GTE, 70000), Orders.act(Orders.SERVE))
notOk(Orders.validate(badArg, 4), "an out-of-range u16 argument is refused")
badArg.rules[1] = Orders.rule(Orders.cond(Orders.TASTE_GT, 9, 0), Orders.act(Orders.SERVE))
notOk(Orders.validate(badArg, 4), "a TASTE_GT axis above 8 is refused")
badArg.rules[1] = Orders.rule(Orders.cond(200), Orders.act(Orders.SERVE))
notOk(Orders.validate(badArg, 4), "an unknown condition opcode is refused")
badArg.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), { op = 200 })
notOk(Orders.validate(badArg, 4), "an unknown action opcode is refused")
local deepNest = Orders.empty()
deepNest.rules[1] = Orders.rule(
	Orders.compound(Orders.AND, Orders.compound(Orders.AND, Orders.cond(Orders.ALWAYS), Orders.cond(Orders.ALWAYS)), Orders.cond(Orders.ALWAYS)),
	Orders.act(Orders.SERVE)
)
notOk(Orders.validate(deepNest, 4), "nesting beyond two terms is refused")
local shortTerms = Orders.empty()
shortTerms.rules[1] = Orders.rule({ op = Orders.AND, terms = { Orders.cond(Orders.ALWAYS) } }, Orders.act(Orders.SERVE))
notOk(Orders.validate(shortTerms, 4), "AND with one term is refused")

-- Bytecode.
local worked = Orders.empty()
worked.rules[1] = Orders.rule(Orders.cond(Orders.CLASS_IS, Drifter.DEEPWATER), Orders.act(Orders.HOLD_BERTH))
worked.rules[2] = Orders.rule(
	Orders.compound(Orders.AND, Orders.cond(Orders.CURRENT_IS, 2), Orders.cond(Orders.TASTE_GT, 2, 40)),
	Orders.act(Orders.SERVE_ADJ, 25)
)
worked.rules[3] = Orders.rule(Orders.cond(Orders.WANTS_SOMETHING), Orders.act(Orders.SERVE))
worked.rules[4] = Orders.rule(Orders.cond(Orders.BUDGET_GTE, 800), Orders.act(Orders.SERVE_ADJ, 10))
worked.rules[5] = Orders.rule(Orders.cond(Orders.STANDING_GTE, 4000), Orders.act(Orders.SERVE))
worked.rules[6] = Orders.rule(Orders.cond(Orders.CLASS_IS, Drifter.SKIFF), Orders.act(Orders.SERVE_ADJ, -10))
worked.rules[7] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.REFUSE))
ok(Orders.validate(worked, 4), "the doc 06 section 5.4 worked example validates at tier 4")
notOk(Orders.validate(worked, 2), "the worked example does not validate at tier 2")
local code = Orders.encode(worked)
ok(#code <= GameConfig.MAX_ORDERS_BYTES, "the worked example fits the 1024 byte budget")
between(#code, 20, 60, "the worked example is a couple of dozen bytes")
local decoded, decodeErr = Orders.decode(code, 1, #code)
eq(decodeErr, nil, "the worked example decodes")
eq(#decoded.rules, 7, "every rule came back")
ok(Tables.deepEqual(decoded, worked), "encode/decode is an exact round trip")
ok(Codec.equal(Orders.encode(decoded), code), "re-encoding a decoded program is byte-identical")
eq(Orders.byteLength(worked), #code, "byteLength agrees with encode")
eq(Orders.decode({ 99, 0 }), nil, "an unknown bytecode version is refused")
eq(Orders.decode({ 1, 1, 200 }), nil, "an unknown opcode in bytecode is refused")
eq(Orders.decode({ 1, 1 }), nil, "truncated bytecode is refused")
local withTrailing = {}
for i = 1, #code do
	withTrailing[i] = code[i]
end
withTrailing[#withTrailing + 1] = 0
eq(Orders.decode(withTrailing, 1, #withTrailing), nil, "trailing bytes are refused")
local tooManyRules = Orders.empty()
for i = 1, 24 do
	tooManyRules.rules[i] = Orders.rule(Orders.cond(Orders.BUDGET_GTE, 4294967295), Orders.act(Orders.GIFT, 65535))
end
ok(#Orders.encode(tooManyRules) <= GameConfig.MAX_ORDERS_BYTES, "a maximal tier-4 program still fits the budget")
errors(function()
	Orders.encode({ version = 1, rules = { Orders.rule(Orders.cond(Orders.ALWAYS), { op = 200 }) } })
end, "encoding an unknown action opcode throws")

-- Every opcode round trips.
local allConds = {
	Orders.cond(Orders.ALWAYS),
	Orders.cond(Orders.CLASS_IS, 3),
	Orders.cond(Orders.CURRENT_IS, 4),
	Orders.cond(Orders.STANDING_GTE, 65535),
	Orders.cond(Orders.TIDE_IS, 5),
	Orders.cond(Orders.WANTS_SOMETHING),
	Orders.cond(Orders.BUDGET_GTE, 4294967295),
	Orders.cond(Orders.BEACONS_GTE, 255),
	Orders.cond(Orders.TASTE_GT, 8, -128),
	Orders.compound(Orders.AND, Orders.cond(Orders.ALWAYS), Orders.cond(Orders.ALWAYS)),
	Orders.cond(Orders.VISITS_GTE, 40),
	Orders.compound(Orders.OR, Orders.cond(Orders.ALWAYS), Orders.cond(Orders.ALWAYS)),
}
for i = 1, #allConds do
	local single = Orders.empty()
	single.rules[1] = Orders.rule(allConds[i], Orders.act(Orders.SERVE))
	local bytes = Orders.encode(single)
	local round = Orders.decode(bytes, 1, #bytes)
	ok(round ~= nil and Tables.deepEqual(round, single), "condition opcode " .. i .. " round trips")
end
local allActions = {
	Orders.act(Orders.SERVE),
	Orders.act(Orders.REFUSE),
	Orders.act(Orders.SERVE_ADJ, -40),
	Orders.act(Orders.ACCEPT_BARTER),
	Orders.act(Orders.HOLD_BERTH),
	Orders.act(Orders.OFFER_ONLY, 6),
	Orders.act(Orders.GIFT, 24),
}
for i = 1, #allActions do
	local single = Orders.empty()
	single.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), allActions[i])
	local bytes = Orders.encode(single)
	local round = Orders.decode(bytes, 1, #bytes)
	ok(round ~= nil and Tables.deepEqual(round, single), "action opcode " .. i .. " round trips")
end
eq(#OrdersConfig.CONDITIONS, 12, "twelve conditions are specified")
eq(#OrdersConfig.ACTIONS, 7, "seven actions are specified")

-- ================================================================ Ledger
end
section("Ledger")
do

eq(Ledger.outcomeName(Ledger.SERVED), "SERVED", "outcomeName")
eq(Ledger.outcomeName(99), "UNKNOWN", "outcomeName of an unknown code")
local tctx = { class = 0, gatedByStanding = false, gifted = false, firstFind = false, sourPrice = false, warmth = 0, metWant = false }
eq(Ledger.selectTemplate(Ledger.MISSED_TIDE, tctx), Ledger.T_MISSED_TIDE, "MISSED_TIDE template")
tctx.class = 3
eq(Ledger.selectTemplate(Ledger.MISSED_TIDE, tctx), Ledger.T_MISSED_TIDE_DEEPWATER, "DEEPWATER gets its own missed-tide line")
eq(Ledger.selectTemplate(Ledger.NO_BERTH, tctx), Ledger.T_NO_BERTH, "NO_BERTH template")
eq(Ledger.selectTemplate(Ledger.REFUSED, tctx), Ledger.T_REFUSED_COLD, "REFUSED without a Standing gate")
tctx.gatedByStanding = true
eq(Ledger.selectTemplate(Ledger.REFUSED, tctx), Ledger.T_REFUSED_GATE, "REFUSED at a Standing gate")
eq(Ledger.selectTemplate(Ledger.PARTIAL, tctx), Ledger.T_PARTIAL_BUDGET, "PARTIAL template")
eq(Ledger.selectTemplate(Ledger.SERVED, tctx), Ledger.T_SERVED_PLAIN, "SERVED plain")
tctx.warmth = 80
eq(Ledger.selectTemplate(Ledger.SERVED, tctx), Ledger.T_SERVED_WARM, "SERVED warm")
tctx.metWant = true
eq(Ledger.selectTemplate(Ledger.SERVED, tctx), Ledger.T_SERVED_WANT, "SERVED warm and met a want")
tctx.sourPrice = true
eq(Ledger.selectTemplate(Ledger.SERVED, tctx), Ledger.T_SERVED_SOUR_PRICE, "a sour price beats warmth")
tctx.firstFind = true
eq(Ledger.selectTemplate(Ledger.SERVED, tctx), Ledger.T_SERVED_FIRST_FIND, "a first find beats a sour price")
tctx.gifted = true
eq(Ledger.selectTemplate(Ledger.SERVED, tctx), Ledger.T_GIFT, "a gift beats everything")

local entry, entryErr = Ledger.entry(Ledger.T_SERVED_PLAIN, 5, 99, { 1, 2, 3 })
eq(entryErr, nil, "a well-formed entry is built")
eq(entry.templateId, Ledger.T_SERVED_PLAIN, "entry keeps its template")
eq(#entry.slots, 3, "entry keeps its slots")
eq(Ledger.entry(Ledger.T_SERVED_PLAIN, 5, 99, { 1, 2 }), nil, "the wrong slot count is refused")
eq(Ledger.entry(Ledger.T_NO_BERTH, 5, 99, { 1, 2, 3, 4, 5, 6, 7 }), nil, "too many slots are refused")
ok(Ledger.isValid(entry), "a built entry validates")
notOk(Ledger.isValid({ templateId = 0 }), "an entry with template 0 is invalid")
notOk(Ledger.isValid("junk"), "a non-table entry is invalid")

local bounded = {}
for i = 1, 250 do
	Ledger.append(bounded, { templateId = 1, epoch = i, actorId = 0, slots = { 1, 2, 3 } }, 200)
end
eq(#bounded, 200, "append keeps the list bounded")
eq(bounded[1].epoch, 51, "append drops the oldest entries")
eq(bounded[200].epoch, 250, "append keeps the newest entry last")
local grouped = Ledger.groupByEpoch({
	{ templateId = 1, epoch = 1, slots = {} },
	{ templateId = 1, epoch = 1, slots = {} },
	{ templateId = 1, epoch = 2, slots = {} },
})
eq(#grouped, 2, "groupByEpoch makes one page per epoch")
eq(#grouped[1].entries, 2, "the first page has two entries")
eq(grouped[2].epoch, 2, "the second page carries its epoch")

-- ================================================================ Visit
end
section("Visit")
do

-- pricePressure
near(Visit.pricePressure(100, 100, 0), 1.0, 1e-12, "pricing at base value is the ideal for a neutral taste")
near(Visit.pricePressure(160, 100, 0), 1.6 - 2.2 * 0.6, 1e-12, "pricing at 1.6x for a neutral taste")
near(Visit.pricePressure(300, 100, 0), -1, 1e-12, "a wild markup clamps at -1")
near(Visit.pricePressure(100, 100, 100), 1.6 - 2.2 * 0.6, 1e-12, "a dear taste shifts the ideal to 1.6x")
near(Visit.pricePressure(160, 100, 100), 1.0, 1e-12, "a dear-tasting drifter is happiest at 1.6x")
eq(Visit.pricePressure(10, 0, 0), -1, "pricePressure is total for a zero base value")
ok(Visit.pricePressure(100, 100, -100) < Visit.pricePressure(40, 100, -100), "a cheap taste prefers a discount")
eq(Visit.adjustedPrice(100, 0), 100, "no adjustment")
eq(Visit.adjustedPrice(100, 25), 125, "a +25% adjustment")
eq(Visit.adjustedPrice(100, -40), 60, "a -40% adjustment")
eq(Visit.adjustedPrice(1, -40), 1, "an adjustment never prices below the minimum")

-- Berth rules, every class against every tide.
local expectedAdmit = {
	[0] = { true, true, true, true, true },
	[1] = { false, true, true, true, true },
	[2] = { false, false, false, true, true },
	[3] = { false, false, false, false, true },
}
for class = 0, 3 do
	for t = 1, 5 do
		eq(
			Drifter.admitsTide(class, tideNames[t]),
			expectedAdmit[class][t],
			Drifter.className(class) .. " at " .. tideNames[t]
		)
	end
end
notOk(Drifter.admitsTide(99, "HIGH"), "an unknown class admits nothing")

local S1 = mkPost(4)
local ctx1 = mkContext(10, "LOW")
local rngV = RNG.new(555)
local lugger = mkDrifter(7001, 10, Drifter.LUGGER, 0, 3, 2000, { 0, 0, 0, 0, 0, 0, 0, 0 }, {}, {})
local dlt = Visit.resolve(S1, lugger, ctx1, rngV)
eq(dlt.outcome, Ledger.MISSED_TIDE, "a LUGGER at LOW water misses the tide")
eq(dlt.coin, 0, "a missed tide earns nothing")
eq(dlt.itemCount, 0, "a missed tide buys nothing")
eq(dlt.standing, 0, "a missed tide costs no Standing")
ok(dlt.warmth < 0, "a missed tide is mildly negative")

ctx1.tide = "HIGH"
ctx1.berthsUsed = 3
dlt = Visit.resolve(S1, lugger, ctx1, rngV)
eq(dlt.outcome, Ledger.NO_BERTH, "a full quay turns a visitor away")
eq(dlt.coin, 0, "no berth earns nothing")
ctx1.berthsUsed = 0

-- Refusal.
S1.orders = Orders.empty()
S1.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.REFUSE))
dlt = Visit.resolve(S1, lugger, ctx1, rngV)
eq(dlt.outcome, Ledger.REFUSED, "an always-refuse program refuses")
eq(dlt.standing, EconomyConfig.STANDING_ON_REFUSED, "refusing costs Standing")
ok(dlt.warmth < -40, "refusing is cold")
eq(dlt.ruleIndex, 1, "the refusing rule is named")

-- Standing gate.
S1.orders.rules[1] = Orders.rule(Orders.cond(Orders.STANDING_GTE, 60000), Orders.act(Orders.REFUSE))
S1.orders.rules[2] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE))
lugger.standing = 65000
dlt = Visit.resolve(S1, lugger, ctx1, rngV)
eq(dlt.outcome, Ledger.REFUSED, "the Standing gate fires")
ok(dlt.gatedByStanding, "the refusal is attributed to a Standing gate")
lugger.standing = 0

-- Hold berth.
S1.orders = Orders.empty()
S1.orders.rules[1] = Orders.rule(Orders.cond(Orders.CLASS_IS, Drifter.LUGGER), Orders.act(Orders.HOLD_BERTH))
dlt = Visit.resolve(S1, lugger, ctx1, rngV)
eq(dlt.outcome, Ledger.NO_BERTH, "hold berth turns the visitor away")
ok(dlt.holdBerth, "the delta marks the berth as held")
eq(dlt.standing, 0, "holding a berth costs no Standing")

-- A plain serve.
S1.orders = Orders.empty()
local rich = mkDrifter(7002, 10, Drifter.DEEPWATER, 0, 4, 100000, { 20, 40, 30, 10, 10, 40, 0, 10 }, {}, {})
dlt = Visit.resolve(S1, rich, ctx1, rngV)
ok(dlt.outcome == Ledger.SERVED or dlt.outcome == Ledger.PARTIAL, "a well-funded visitor trades")
ok(dlt.itemCount >= 1, "a well-funded visitor buys something")
eq(dlt.spent, dlt.coin, "spend equals the host's coin gain")
local sumPrices = 0
for i = 1, dlt.itemCount do
	sumPrices = sumPrices + dlt.itemPrice[i]
end
eq(sumPrices, dlt.spent, "the item prices sum to the spend")
ok(dlt.itemCount <= Drifter.classMaxItems(Drifter.DEEPWATER), "a class never exceeds its item limit")
eq(dlt.spent, math.floor(dlt.spent), "spend is an integer")

-- A broke visitor.
local broke = mkDrifter(7003, 10, Drifter.SKIFF, 0, 1, 0, { 20, 40, 30, 10, 10, 40, 0, 10 }, {}, {})
dlt = Visit.resolve(S1, broke, ctx1, rngV)
eq(dlt.itemCount, 0, "a visitor with no budget buys nothing")
eq(dlt.outcome, Ledger.PARTIAL, "an empty-handed visit is PARTIAL")
eq(dlt.coin, 0, "an empty-handed visit earns nothing")

-- Effective budget rises with Standing.
local plain = mkDrifter(7004, 10, Drifter.SKIFF, 0, 1, 100, nil, {}, {})
eq(Drifter.effectiveBudget(plain), 100, "no Standing means no bonus")
plain.standing = 25600
eq(Drifter.effectiveBudget(plain), 200, "a regular spends more")
plain.standing = 65535
eq(Drifter.effectiveBudget(plain), 200, "the Standing budget bonus is capped at +100%")
plain.standing = 0

-- Wants raise the score and the warmth.
local wantsPost = mkPost(4)
wantsPost.orders = Orders.empty()
local wanter = mkDrifter(7005, 10, Drifter.DEEPWATER, 0, 4, 100000, { 0, 0, 0, 0, 0, 0, 0, 0 }, { 12 }, {})
local wctx = mkContext(10, "HIGH")
local wdelta = Visit.resolve(wantsPost, wanter, wctx, RNG.new(11))
local boughtWanted = false
for i = 1, wdelta.itemCount do
	if wdelta.itemId[i] == 12 then boughtWanted = true end
end
ok(boughtWanted, "a wanted find gets bought")
ok(wdelta.metWant >= 1, "the delta records the met want")
local indifferent = mkDrifter(7005, 10, Drifter.DEEPWATER, 0, 4, 100000, { 0, 0, 0, 0, 0, 0, 0, 0 }, {}, {})
local idelta = Visit.resolve(mkPost(4), indifferent, mkContext(10, "HIGH"), RNG.new(11))
ok(wdelta.warmth > idelta.warmth, "meeting a want is warmer than the same visit without one")

-- serve at -40% sells more than serve at +40%.
local cheapPost = mkPost(4)
cheapPost.orders = Orders.empty()
cheapPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, -40))
local dearPost = mkPost(4)
dearPost.orders = Orders.empty()
dearPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, 40))
local shopper = mkDrifter(7006, 10, Drifter.LUGGER, 0, 3, 200, { 0, 0, -80, 0, 0, 0, 0, 0 }, {}, {})
local cheapDelta = Visit.resolve(cheapPost, shopper, mkContext(10, "HIGH"), RNG.new(3))
local dearDelta = Visit.resolve(dearPost, shopper, mkContext(10, "HIGH"), RNG.new(3))
ok(cheapDelta.itemCount >= dearDelta.itemCount, "a cheap-tasting visitor buys at least as much at a discount")

-- offer only a group.
local groupPost = mkPost(4)
groupPost.orders = Orders.empty()
groupPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.OFFER_ONLY, 2))
local groupDelta = Visit.resolve(groupPost, rich, mkContext(10, "HIGH"), RNG.new(4))
local outOfGroup = 0
for i = 1, groupDelta.itemCount do
	if Post.groupOf(groupDelta.itemId[i]) ~= 2 then outOfGroup = outOfGroup + 1 end
end
eq(outOfGroup, 0, "offer only restricts the shelf set to one group")

-- Gifting.
local giftPost = mkPost(4)
giftPost.orders = Orders.empty()
giftPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.GIFT, 9))
local giftDelta = Visit.resolve(giftPost, rich, mkContext(10, "HIGH"), RNG.new(5))
eq(giftDelta.outcome, Ledger.SERVED, "a gift is a serve")
eq(giftDelta.spent, 0, "a gift costs the visitor nothing")
eq(giftDelta.coin, 0, "a gift earns the host nothing")
eq(giftDelta.itemCount, 1, "a gift moves exactly one item")
eq(giftDelta.itemId[1], 9, "the gifted find is the one named")
ok(giftDelta.gifted, "the delta is marked as a gift")
eq(giftDelta.renown, EconomyConfig.RENOWN_ON_GIFT, "a gift pays Renown")
ok(giftDelta.warmth > 80, "a gift is very warm")
giftPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.GIFT, 24))
local noStockGift = Visit.resolve(giftPost, rich, mkContext(10, "HIGH"), RNG.new(5))
notOk(noStockGift.gifted, "gifting something out of stock falls through to normal trade")

-- Barter forms a claim, not a transfer.
local barterPost = mkPost(4)
barterPost.orders = Orders.empty()
barterPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.ACCEPT_BARTER))
local trader = mkDrifter(7007, 10, Drifter.LUGGER, 0, 3, 500, nil, {}, { 4, 11 })
local barterDelta = Visit.resolve(barterPost, trader, mkContext(10, "HIGH"), RNG.new(6))
eq(barterDelta.claimCount, 2, "both cargo items become claims")
eq(barterDelta.claimId[1], 4, "the first claim names the cargo")
local stockBefore = Post.stockOf(barterPost, 4)
Visit.apply(barterPost, barterDelta)
eq(Post.stockOf(barterPost, 4), stockBefore, "a claim does not create stock")
eq(#barterPost.claims, 2, "the claims were queued on the post")
eq(barterPost.claims[1].fromOwner, 7007, "a claim remembers who owes it")

-- apply()
local applyPost = mkPost(4)
applyPost.orders = Orders.empty()
local applyCtx = mkContext(10, "HIGH")
local coinBefore = applyPost.coin
local stockTotalBefore = Post.totalStock(applyPost)
local applyDelta = Visit.resolve(applyPost, rich, applyCtx, RNG.new(7))
ok(Visit.apply(applyPost, applyDelta), "apply succeeds")
eq(applyPost.coin, coinBefore + applyDelta.coin, "apply credits the coin")
eq(Post.totalStock(applyPost), stockTotalBefore - applyDelta.itemCount, "apply removes exactly the sold stock")
eq(applyPost.standing[rich.current + 1], applyDelta.standing, "apply grants the delta's Standing to the right Current")
ok(applyDelta.standing > 0, "a completed visit earns Standing")
eq(applyPost.standing[(rich.current + 1) % 5 + 1], 0, "no other Current was touched")
ok(Post.checkInvariants(applyPost), "the post is still valid after apply")
local statTotal = applyPost.stats.served + applyPost.stats.partial + applyPost.stats.refused + applyPost.stats.missed + applyPost.stats.noBerth
eq(statTotal, 1, "apply recorded exactly one outcome")

-- Ledger entry and receipt.
local narratePost = mkPost(4)
narratePost.orders = Orders.empty()
local nctx = mkContext(42, "HIGH")
local ndelta, nentry, nreceipt = Visit.resolve(narratePost, rich, nctx, RNG.new(8))
eq(nentry.epoch, 42, "the entry carries the epoch")
eq(nentry.actorId, rich.id, "the entry names the actor")
ok(nentry.templateId > 0, "the entry has a template")
eq(nentry.slotCount, Ledger.SLOT_COUNT[nentry.templateId], "the slot count matches the template's arity")
eq(nreceipt.drifterId, rich.id, "the receipt names the drifter")
eq(nreceipt.hostId, narratePost.owner, "the receipt names the host")
eq(nreceipt.epoch, 42, "the receipt carries the epoch")
eq(nreceipt.outcome, ndelta.outcome, "the receipt agrees with the delta")
eq(nreceipt.spent, ndelta.spent, "the receipt agrees on the spend")
eq(nreceipt.flags, 0, "no letter means no flag")
rich.letterId = 17
local _, _, letterReceipt = Visit.resolve(narratePost, rich, nctx, RNG.new(8))
eq(letterReceipt.flags, 1, "a letter sets bit 0 of the flags")
eq(letterReceipt.noteId, 17, "a letter carries its id")
rich.letterId = 0
between(nreceipt.warmth, -128, 127, "warmth fits in an i8")
local cloned = Visit.cloneEntry(nctx)
ok(Ledger.isValid(cloned), "the cloned entry validates")
ok(cloned ~= nctx.entry, "cloneEntry really copies")

-- Warmth bounds across a wide sweep, and every outcome reachable.
local sweepSeen = {}
local warmthOutOfRange = 0
local negativeCoin = 0
local overSpend = 0
for i = 1, 400 do
	local sweepPost = mkPost(4)
	sweepPost.orders = Orders.empty()
	if i % 7 == 0 then
		sweepPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.REFUSE))
	end
	local sweepRng = RNG.new(i * 31)
	local d = Drifter.synthesize(sweepRng, 800000 + i, 10, i % 5, 4)
	local sctx = mkContext(10, tideNames[(i % 5) + 1])
	if i % 11 == 0 then
		sctx.berthsUsed = 3
	end
	local sd = Visit.resolve(sweepPost, d, sctx, sweepRng)
	sweepSeen[sd.outcome] = true
	if sd.warmth < -128 or sd.warmth > 127 then warmthOutOfRange = warmthOutOfRange + 1 end
	if sd.coin < 0 then negativeCoin = negativeCoin + 1 end
	if sd.spent > Drifter.effectiveBudget(d) then overSpend = overSpend + 1 end
end
eq(warmthOutOfRange, 0, "warmth never leaves the i8 range over 400 visits")
eq(negativeCoin, 0, "a visit never produces negative coin")
eq(overSpend, 0, "a visitor never spends more than its effective budget")
ok(sweepSeen[Ledger.SERVED], "SERVED occurs in the sweep")
ok(sweepSeen[Ledger.REFUSED], "REFUSED occurs in the sweep")
ok(sweepSeen[Ledger.MISSED_TIDE], "MISSED_TIDE occurs in the sweep")
ok(sweepSeen[Ledger.NO_BERTH], "NO_BERTH occurs in the sweep")
ok(sweepSeen[Ledger.PARTIAL], "PARTIAL occurs in the sweep")

-- Determinism of a single visit.
local detPost = mkPost(4)
detPost.orders = Orders.empty()
local dA = Visit.resolve(detPost, rich, mkContext(10, "HIGH"), RNG.new(99))
local snapA = { dA.outcome, dA.coin, dA.itemCount, dA.warmth, dA.standing, dA.itemId[1], dA.itemPrice[1] }
local dB = Visit.resolve(detPost, rich, mkContext(10, "HIGH"), RNG.new(99))
local snapB = { dB.outcome, dB.coin, dB.itemCount, dB.warmth, dB.standing, dB.itemId[1], dB.itemPrice[1] }
ok(Tables.deepEqual(snapA, snapB), "the same visit resolves identically twice")
local dC = Visit.resolve(detPost, rich, mkContext(10, "HIGH"), RNG.new(100))
local snapC = { dC.outcome, dC.coin, dC.itemCount, dC.warmth, dC.standing, dC.itemId[1], dC.itemPrice[1] }
notOk(Tables.deepEqual(snapA, snapC), "a different seed gives a different visit")

-- Context reuse: nothing in the context is ever replaced.
local reusePost = mkPost(4)
reusePost.orders = Orders.empty()
local reuseCtx = mkContext(10, "HIGH")
local identity = {
	delta = reuseCtx.delta,
	itemId = reuseCtx.delta.itemId,
	itemPrice = reuseCtx.delta.itemPrice,
	claimId = reuseCtx.delta.claimId,
	entry = reuseCtx.entry,
	slots = reuseCtx.entry.slots,
	receipt = reuseCtx.receipt,
	facts = reuseCtx.facts,
	candShelf = reuseCtx.candShelf,
	candScore = reuseCtx.candScore,
	sortKey = reuseCtx.sortKey,
	sortSlot = reuseCtx.sortSlot,
	tmpl = reuseCtx.tmpl,
}
local reuseRng = RNG.new(1)
for i = 1, 3000 do
	reuseCtx.tide = tideNames[(i % 5) + 1]
	reuseCtx.berthsUsed = i % 4
	Visit.resolve(reusePost, rich, reuseCtx, reuseRng)
end
local churned = 0
for key, value in pairs(identity) do
	local now
	if key == "itemId" or key == "itemPrice" or key == "claimId" then
		now = reuseCtx.delta[key]
	elseif key == "slots" then
		now = reuseCtx.entry.slots
	else
		now = reuseCtx[key]
	end
	if now ~= value then
		churned = churned + 1
		print("context churn on " .. key)
	end
end
eq(churned, 0, "3000 visits replaced no buffer in the context (zero-allocation proof, dynamic half)")

-- ================================================================ PostCodec
end
section("PostCodec")
do

local blobPost = mkPost(4)
blobPost.coin = 123456
blobPost.renown = 4321
blobPost.season = 3
blobPost.standing = { 11000, 250, 0, 4001, 30000 }
blobPost.comb = { 0, 12, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0 }
Post.recordVisit(blobPost, 987654321, 77)
Post.recordVisit(blobPost, 123456789, 78)
blobPost.claims = { { id = 4, qty = 1, fromOwner = 4455667788, epoch = 70 } }
blobPost.orders = Orders.empty()
blobPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, -10))
blobPost.ordersBytecode = Orders.encode(blobPost.orders)

local postBlob = PostCodec.encode(blobPost)
ok(#postBlob <= GameConfig.MAX_POST_BLOB_BYTES, "the post blob fits its 6 KB budget")
print("post blob size: " .. tostring(#postBlob) .. " bytes (" .. tostring(math.floor(#postBlob / 1024 * 100) / 100) .. " KB), budget " .. tostring(GameConfig.MAX_POST_BLOB_BYTES))
local restored, restoreReason = PostCodec.decode(postBlob)
eq(restoreReason, nil, "the blob decodes")
eq(restored.postId, blobPost.postId, "postId round trips")
eq(restored.owner, blobPost.owner, "owner round trips")
eq(restored.salt, blobPost.salt, "salt round trips")
eq(restored.tier, blobPost.tier, "tier round trips")
eq(restored.season, blobPost.season, "season round trips")
eq(restored.resolvedAt, blobPost.resolvedAt, "resolvedAt round trips")
eq(restored.coin, blobPost.coin, "coin round trips")
eq(restored.renown, blobPost.renown, "renown round trips")
ok(Tables.deepEqual(restored.standing, blobPost.standing), "the Standing vector round trips")
ok(Tables.deepEqual(restored.almanac, blobPost.almanac), "the Almanac round trips")
ok(Tables.deepEqual(restored.sold, blobPost.sold), "the sold bitset round trips")
ok(Tables.deepEqual(restored.store, blobPost.store), "the store round trips")
ok(Tables.deepEqual(restored.shelves, blobPost.shelves), "the shelves round trip")
ok(Tables.deepEqual(restored.comb, blobPost.comb), "the comb nodes round trip")
ok(Codec.equal(restored.ordersBytecode, blobPost.ordersBytecode), "the orders bytecode round trips verbatim")
ok(Tables.deepEqual(Orders.decode(restored.ordersBytecode, 1, #restored.ordersBytecode), blobPost.orders), "the orders rehydrate")
eq(#restored.ring, #blobPost.ring, "the visitor ring keeps its length")
eq(restored.ring[1].owner, 123456789, "a ring owner round trips")
eq(#restored.claims, 1, "the claim queue round trips")
eq(restored.claims[1].fromOwner, 4455667788, "a claim's owner round trips")

-- ------------------------------------------------- schema v2 and the v1 blob
-- OD16. Two separate things are checked here and they are not the same thing:
--   1. a v2 blob round-trips `publishedAt`  -- trivially true by construction;
--   2. a REAL v1 blob, captured before the field existed, still loads.
-- Only the second one can fail in a way that matters to a live player.

eq(Version.CURRENT, 2, "the current post schema is version 2")
blobPost.publishedAt = 4242
local v2Blob = PostCodec.encode(blobPost)
local v2Back, v2Reason = PostCodec.decode(v2Blob)
eq(v2Reason, nil, "a v2 blob decodes")
eq(v2Back.publishedAt, 4242, "publishedAt round trips at v2")
-- Epoch 0 is a real epoch and must survive as one, not decay into "never".
blobPost.publishedAt = 0
local zeroBack = PostCodec.decode(PostCodec.encode(blobPost))
eq(zeroBack.publishedAt, 0, "epoch 0 round trips as epoch 0, not as never")
blobPost.publishedAt = nil
local neverBack = PostCodec.decode(PostCodec.encode(blobPost))
eq(neverBack.publishedAt, nil, "never-published round trips as never")
blobPost.publishedAt = 4242
eq(v2Back.v, 2, "a v2 blob reports schema version 2")
eq(#v2Blob, #postBlob, "publishedAt costs exactly the 4 bytes the layout says")

local v1Bytes = Codec.base64Decode(FIXTURE_POST_V1)
eq(v1Bytes[1], 1, "the fixture really is a version 1 blob")
eq(#v1Bytes, 249, "the v1 fixture is the size it was captured at")
local migrated, migReason, migWhy = PostCodec.decode(v1Bytes)
eq(migReason, nil, "the captured v1 blob still decodes: " .. tostring(migWhy))
ok(migrated ~= nil, "the v1 blob produced a state")
eq(migrated.v, 2, "the v1 blob was migrated up to v2")
eq(migrated.publishedAt, nil, "a migrated v1 post has never published")
-- Everything the v1 blob DID carry must survive the migration untouched.
eq(migrated.postId, 1001, "postId survives the migration")
eq(migrated.owner, 4455667788, "owner survives the migration")
eq(migrated.coin, 123456, "coin survives the migration")
eq(migrated.renown, 4321, "renown survives the migration")
eq(migrated.tier, 4, "tier survives the migration")
eq(migrated.season, 3, "season survives the migration")
ok(Tables.deepEqual(migrated.standing, { 11000, 250, 0, 4001, 30000 }), "standing survives the migration")
eq(#migrated.claims, 1, "the claim queue survives the migration")
eq(migrated.claims[1].fromOwner, 4455667788, "a claim's owner survives the migration")
eq(#migrated.ring, 2, "the visitor ring survives the migration")

-- A migrated post must be re-encodable at the new version, or the player is
-- stuck reading a save they can never write back.
local reBlob = PostCodec.encode(migrated)
eq(reBlob[1], 2, "re-encoding a migrated post writes version 2")
local reBack, reReason = PostCodec.decode(reBlob)
eq(reReason, nil, "the re-encoded blob decodes")
eq(reBack.coin, 123456, "coin survives the full v1 -> v2 -> bytes -> state trip")

-- A blob from the FUTURE is refused, never guessed at.
local futureBytes = Codec.base64Decode(FIXTURE_POST_V1)
futureBytes[1] = 99
local fut, futReason = PostCodec.decode(futureBytes)
eq(fut, nil, "a blob newer than this server is refused")
ok(futReason == Version.TOO_NEW or futReason == "CORRUPT", "refusing a future blob reports why")

-- Put `blobPost` back the way the rest of this section found it. The later
-- base64 tests compare against `postBlob`, which was encoded when this post
-- had never published -- so the restore is `nil`, not 0. Those are different
-- states and the codec is careful to keep them different.
blobPost.publishedAt = nil
ok(Tables.deepEqual(restored.stats, blobPost.stats), "the stats round trip")
ok(Codec.equal(PostCodec.encode(restored), postBlob), "re-encoding a decoded post is byte-identical")

-- The number that actually matters against the 6 KB budget is not the
-- fixture's, it is a MAXED post: every store slot, every shelf, a full visitor
-- ring, a full claim queue and a 1024-byte orders program.
local maxPost = Post.new(4294967295, 4455667788, 987654321, Tide.EPOCH)
maxPost.tier = 4
maxPost.coin = 4294967295
maxPost.renown = 4294967295
maxPost.season = 65535
for i = 1, GameConfig.MAX_STORE_ENTRIES do
	maxPost.store[i] = { id = i, qty = GameConfig.MAX_STOCK_PER_ENTRY }
end
for i = 1, GameConfig.MAX_SHELF_SLOTS do
	maxPost.shelves[i] = { id = i, price = EconomyConfig.MAX_PRICE }
end
for i = 1, GameConfig.MAX_COMB_NODES do
	maxPost.comb[i] = 2147483647
end
for i = 1, GameConfig.VISITOR_RING_SIZE do
	maxPost.ring[i] = { owner = 4455667788, epoch = 8191 }
end
for i = 1, 64 do
	maxPost.claims[i] = { id = 65535, qty = 65535, fromOwner = 4455667788, epoch = 2147483647 }
end
for i = 1, 32 do
	maxPost.standing[i] = nil
end
for i = 1, EconomyConfig.CURRENT_COUNT do
	maxPost.standing[i] = 65535
end
for i = 1, 32 do
	maxPost.almanac[i] = 255
	maxPost.sold[i] = 255
end
maxPost.ordersBytecode = {}
for i = 1, GameConfig.MAX_ORDERS_BYTES do
	maxPost.ordersBytecode[i] = 0
end
maxPost.stats = { served = 4294967295, refused = 4294967295, partial = 4294967295, missed = 4294967295, noBerth = 4294967295, coinEarned = 4294967295 }
local maxBlob = PostCodec.encode(maxPost)
print("MAXIMAL post blob: " .. tostring(#maxBlob) .. " bytes, budget " .. tostring(GameConfig.MAX_POST_BLOB_BYTES) .. " (base64: " .. tostring(#PostCodec.encodeToString(maxPost)) .. " bytes)")
ok(#maxBlob <= GameConfig.MAX_POST_BLOB_BYTES, "a maximal post blob still fits the 6 KB budget")
ok(#PostCodec.encodeToString(maxPost) <= 32768, "the base64 form fits a 32 KB MemoryStore value")
local maxBack = PostCodec.decode(maxBlob)
ok(maxBack ~= nil and Codec.equal(PostCodec.encode(maxBack), maxBlob), "a maximal post round trips")

local text = PostCodec.encodeToString(blobPost)
ok(#text > 0, "the base64 form is non-empty")
local fromText = PostCodec.decodeFromString(text)
ok(Codec.equal(PostCodec.encode(fromText), postBlob), "the base64 form round trips")
eq(PostCodec.decodeFromString("not base64 !!"), nil, "a malformed base64 blob is refused")

local badBlob = {}
for i = 1, #postBlob do
	badBlob[i] = postBlob[i]
end
badBlob[20] = (badBlob[20] + 1) % 256
local corruptPost, corruptReason = PostCodec.decode(badBlob)
eq(corruptPost, nil, "a corrupted post blob is refused")
eq(corruptReason, "CORRUPT", "the refusal is reported as CORRUPT")
local futureBlob = {}
for i = 1, #postBlob do
	futureBlob[i] = postBlob[i]
end
futureBlob[1] = 99
local futurePost, futureReason = PostCodec.decode(futureBlob)
eq(futurePost, nil, "a blob from a newer server is refused")
eq(futureReason, Version.TOO_NEW, "the refusal is reported as TOO_NEW")
eq(PostCodec.decode({ 1, 2 }), nil, "a truncated post blob is refused")
eq(PostCodec.packRing(5, 8192), PostCodec.packRing(5, 0), "the ring epoch wraps like a drifter id")

-- ================================================================ Resolve
end
section("Resolve")
do

local RS, RIn = baseScenario(4)
startAt = Tide.epochStart(100)
RS.resolvedAt = startAt
local stockBeforeRun = Post.totalStock(RS)
local S2, rEntries, rReceipts, rInfo = Resolve.run(RS, startAt + 3 * 22357, RIn)
eq(RS.resolvedAt, startAt, "run does not mutate the input state")
eq(Post.totalStock(RS), stockBeforeRun, "run does not mutate the input stock")
eq(rInfo.epochsSimulated, 3, "three epochs were simulated")
eq(rInfo.firstEpoch, 101, "the first simulated epoch")
eq(rInfo.lastEpoch, 103, "the last simulated epoch")
notOk(rInfo.clamped, "three epochs is not a long absence")
eq(S2.resolvedAt, startAt + 3 * 22357, "resolvedAt advanced to now")
eq(rInfo.arrivalsPlaced + rInfo.arrivalsDropped, 9, "every inbound drifter was accounted for")
eq(rInfo.visitsResolved, rInfo.arrivalsPlaced, "every placed arrival became a visit")
eq(#rReceipts, rInfo.visitsResolved, "one receipt per visit")
ok(#rEntries >= rInfo.visitsResolved + 3, "there is an epoch summary per epoch on top of the visits")
ok(Resolve.checkInvariants(RS, S2, rInfo, rEntries, rReceipts), "the seven invariants hold")

local epochsSeen = {}
local ascendingEpochs = true
local lastEpochSeen = nil
for i = 1, #rEntries do
	epochsSeen[rEntries[i].epoch] = true
	if lastEpochSeen ~= nil and rEntries[i].epoch < lastEpochSeen then ascendingEpochs = false end
	lastEpochSeen = rEntries[i].epoch
end
ok(ascendingEpochs, "ledger entries are in ascending epoch order")
ok(epochsSeen[101] and epochsSeen[102] and epochsSeen[103], "every epoch produced at least one entry")

-- No-op cases.
local noopState, noopEntries, noopReceipts, noopInfo = Resolve.run(RS, startAt, RIn)
eq(noopInfo.epochsSimulated, 0, "resolving at the same instant simulates nothing")
eq(#noopEntries, 0, "a no-op produces no entries")
eq(#noopReceipts, 0, "a no-op produces no receipts")
eq(noopState.resolvedAt, startAt, "a no-op does not move the clock")
ok(Resolve.isNoOp(RS, startAt), "isNoOp agrees")
local backState, _, _, backInfo = Resolve.run(RS, startAt - 100000, RIn)
eq(backInfo.epochsSimulated, 0, "a backwards clock simulates nothing")
eq(backState.resolvedAt, startAt, "a backwards clock does not move resolvedAt")
ok(Resolve.isNoOp(RS, startAt - 1), "isNoOp catches a backwards clock")
local subEpoch, _, _, subInfo = Resolve.run(RS, startAt + 100, RIn)
eq(subInfo.epochsSimulated, 0, "less than one epoch simulates nothing")
eq(subEpoch.resolvedAt, startAt + 100, "a sub-epoch advance still records the time")

-- Idempotence: resolving twice to the same instant is the same as resolving once.
local onceState = Resolve.run(RS, startAt + 3 * 22357, RIn)
local twiceState = Resolve.run(onceState, startAt + 3 * 22357, RIn)
ok(Codec.equal(PostCodec.encode(onceState), PostCodec.encode(twiceState)), "re-resolving to the same instant is idempotent")

-- The clamp.
local CS, CIn = baseScenario(4)
CS.resolvedAt = startAt
CS.standing = { 11000, 5000, 900, 40000, 100 }
local clampedState, clampedEntries, _, clampedInfo = Resolve.run(CS, startAt + 60 * 22357, CIn)
ok(clampedInfo.clamped, "a 60-epoch gap is clamped")
eq(clampedInfo.epochsSimulated, GameConfig.MAX_CATCHUP_EPOCHS, "the clamp caps the simulation at 27 epochs")
eq(clampedInfo.skippedEpochs, 60 - GameConfig.MAX_CATCHUP_EPOCHS, "the skipped epochs are counted")
eq(clampedEntries[1].templateId, Ledger.T_LONG_ABSENCE, "a LONG_ABSENCE entry leads the ledger")
eq(clampedEntries[1].slots[1], clampedInfo.skippedEpochs, "the entry states the real gap")
-- The 27 simulated epochs that follow the clamp can earn a little Standing
-- back, so the assertion is "collapsed to the floor", not "exactly the floor".
between(clampedState.standing[1], 4000, 4400, "a long absence drops Standing from 11000 to its 4000 band floor")
ok(clampedState.standing[4] >= 30000, "a long absence never breaches a crossed band")
between(clampedState.standing[4], 30000, 30400, "and does not inflate it either")
ok(clampedState.coin >= EconomyConfig.LONG_ABSENCE_CACHE_COIN, "a returning player finds a cache, not a bill")
eq(Post.stockOf(clampedState, 10), 0, "perishables are gone after a long absence")
ok(clampedState.resolvedAt == startAt + 60 * 22357, "resolvedAt still jumps to now after a clamp")
local clampedRun2 = Resolve.run(CS, startAt + 400 * 22357, CIn)
ok(Post.checkInvariants(clampedRun2), "a 400-epoch absence still produces a valid post")

-- Arrival capping.
local MS, _ = baseScenario(4)
MS.resolvedAt = startAt
local crowd = {}
for i = 1, 40 do
	crowd[i] = Drifter.synthesize(RNG.new(5000 + i), 950000 + i, 5, 0, 4)
end
local _, _, crowdReceipts, crowdInfo = Resolve.run(MS, startAt + 22357, crowd)
eq(crowdInfo.epochsSimulated, 1, "one epoch")
eq(crowdInfo.arrivalsPlaced, GameConfig.MAX_ARRIVALS_PER_EPOCH, "arrivals are capped per epoch")
eq(crowdInfo.arrivalsDropped, 40 - GameConfig.MAX_ARRIVALS_PER_EPOCH, "the overflow is counted, not silently lost")
eq(#crowdReceipts, GameConfig.MAX_ARRIVALS_PER_EPOCH, "one receipt per admitted arrival")
local _, _, _, spreadInfo = Resolve.run(MS, startAt + 10 * 22357, crowd)
eq(spreadInfo.arrivalsPlaced, 40, "ten epochs have room for all forty arrivals")
eq(spreadInfo.arrivalsDropped, 0, "nothing is dropped when there is room")

-- Passive income.
local PS = mkPost(1)
PS.orders = Orders.empty()
PS.ordersBytecode = Orders.encode(PS.orders)
PS.resolvedAt = startAt
local _, _, _, passiveInfo = Resolve.run(PS, startAt + 5 * 22357, {})
ok(passiveInfo.passiveTotal <= Post.passiveCap(1) * 5, "passive income respects the tier-1 cap")
ok(passiveInfo.passiveTotal > 0, "a stocked post earns something while away")
local emptyPost = Post.new(2, 3, 4, startAt)
emptyPost.ordersBytecode = Orders.encode(emptyPost.orders)
local _, _, _, emptyInfo = Resolve.run(emptyPost, startAt + 5 * 22357, {})
eq(emptyInfo.passiveTotal, 0, "an empty post earns nothing while away")
local richPost = mkPost(4)
richPost.ordersBytecode = Orders.encode(richPost.orders)
richPost.resolvedAt = startAt
for i = 1, 20 do
	Post.addStock(richPost, 24, 1000)
end
Post.setShelf(richPost, 7, 24, 760)
local _, _, _, cappedInfo = Resolve.run(richPost, startAt + 4 * 22357, {})
eq(cappedInfo.passiveTotal, Post.passiveCap(4) * 4, "a very rich post is capped exactly at the tier maximum")

-- Spoilage.
local SP = mkPost(4)
SP.orders = Orders.empty()
SP.ordersBytecode = Orders.encode(SP.orders)
SP.resolvedAt = startAt
local perishableBefore = Post.stockOf(SP, 10)
local spoiled = Resolve.run(SP, startAt + 4 * 22357, {})
ok(Post.stockOf(spoiled, 10) < perishableBefore, "perishables spoil")
eq(Post.stockOf(spoiled, 1), Post.stockOf(SP, 1), "non-perishables do not spoil")

-- Standing decay happens once per epoch.
local DS = mkPost(4)
DS.orders = Orders.empty()
DS.ordersBytecode = Orders.encode(DS.orders)
DS.resolvedAt = startAt
DS.standing = { 11000, 0, 0, 0, 0 }
local decayed = Resolve.run(DS, startAt + 3 * 22357, {})
eq(decayed.standing[1], Standing.decayN(11000, 3), "three epochs of decay were applied exactly once each")

-- Comb nodes mature.
local KS = mkPost(4)
KS.orders = Orders.empty()
KS.ordersBytecode = Orders.encode(KS.orders)
KS.resolvedAt = startAt
KS.comb = { 102, 999, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local combed = Resolve.run(KS, startAt + 3 * 22357, {})
eq(combed.comb[1], 0, "a node whose epoch has arrived is ready again")
eq(combed.comb[2], 999, "a node still maturing is untouched")

-- Ordering is by Hash.mix(drifterId, epoch), not by input order.
local OS, OIn = baseScenario(4)
OS.resolvedAt = startAt
local _, orderedEntries = Resolve.run(OS, startAt + 22357, OIn)
local reversed = {}
for i = 1, #OIn do
	reversed[i] = OIn[#OIn - i + 1]
end
local OS2, OIn2 = baseScenario(4)
OS2.resolvedAt = startAt
local _, reversedEntries = Resolve.run(OS2, startAt + 22357, reversed)
local sameOrder = true
for i = 1, #orderedEntries do
	if reversedEntries[i] == nil or orderedEntries[i].actorId ~= reversedEntries[i].actorId then
		sameOrder = false
	end
end
ok(sameOrder, "reversing the inbound list does not change the resolution order")

-- Invariant failures are detectable.
local badInfo = { grantedUnits = 0, soldUnits = 0, spoiledUnits = 0, perishedUnits = 0, epochsSimulated = 1, passiveTotal = 0, visitsResolved = 0 }
local tampered = Tables.deepCopy(S2)
tampered.coin = -5
notOk(Resolve.checkInvariants(RS, tampered, badInfo, {}, {}), "checkInvariants catches a structural break")
local backwards = Tables.deepCopy(S2)
backwards.resolvedAt = RS.resolvedAt - 1
notOk(Resolve.checkInvariants(RS, backwards, badInfo, {}, {}), "checkInvariants catches time going backwards")
notOk(
	Resolve.checkInvariants(RS, S2, { grantedUnits = 0, soldUnits = 0, spoiledUnits = 0, perishedUnits = 0, epochsSimulated = 1, passiveTotal = 999999, visitsResolved = 0 }, {}, {}),
	"checkInvariants catches unbounded passive income"
)
notOk(
	Resolve.checkInvariants(RS, S2, { grantedUnits = 0, soldUnits = 0, spoiledUnits = 0, perishedUnits = 0, epochsSimulated = 99, passiveTotal = 0, visitsResolved = 0 }, {}, {}),
	"checkInvariants catches a clamp violation"
)
notOk(
	Resolve.checkInvariants(RS, S2, badInfo, {}, { { v = 1 } }),
	"checkInvariants catches a receipt with no visit"
)

-- Conservation across a long, busy run.
local BS, BIn = baseScenario(4)
BS.resolvedAt = startAt
local bigCrowd = {}
for i = 1, 60 do
	bigCrowd[i] = Drifter.synthesize(RNG.new(20000 + i), 960000 + i, 5, (i - 1) % 5, 4)
end
local bigState, bigEntries, bigReceipts, bigInfo = Resolve.run(BS, startAt + 27 * 22357, bigCrowd)
eq(bigInfo.epochsSimulated, 27, "a full 27-epoch catch-up")
ok(Resolve.checkInvariants(BS, bigState, bigInfo, bigEntries, bigReceipts), "the invariants hold across a full catch-up")
ok(bigInfo.visitsResolved > 20, "a full catch-up resolves a lot of visits")
ok(Post.checkInvariants(bigState), "the post is structurally valid afterwards")
ok(bigState.coin >= BS.coin, "coin never goes down across a resolve")
local blobAfter = PostCodec.encode(bigState)
ok(#blobAfter <= GameConfig.MAX_POST_BLOB_BYTES, "the post still serialises inside its budget after a busy week")
print("post blob after a busy 27-epoch week: " .. tostring(#blobAfter) .. " bytes")

-- ================================================================ determinism
end
section("determinism")
do

-- doc 04 section 5.1, proof one: 1000 identical runs.
local DPost, DIn = baseScenario(4)
DPost.resolvedAt = startAt
local reference = canonical(Resolve.run(DPost, startAt + 3 * 22357, DIn))
local divergences = 0
local sharedWorkspace = Resolve.newWorkspace()
for run = 1, 1000 do
	local s, e, r = Resolve.run(DPost, startAt + 3 * 22357, DIn, sharedWorkspace)
	if canonical(s, e, r) ~= reference then
		divergences = divergences + 1
	end
end
eq(divergences, 0, "PROOF 1: 1000 identical Resolve runs are byte-identical")
ok(#reference > 100, "the canonical form is substantial enough for the proof to mean something")

-- Proof two: the server path and the client replay path agree. Same module,
-- separate workspaces, separate RNG objects, separate context -- which is
-- exactly the difference between a server resolve and a client-side replay.
local serverWork = Resolve.newWorkspace()
local clientWork = Resolve.newWorkspace()
local serverOut = canonical(Resolve.run(DPost, startAt + 5 * 22357, DIn, serverWork))
local clientOut = canonical(Resolve.run(DPost, startAt + 5 * 22357, DIn, clientWork))
eq(serverOut, clientOut, "PROOF 2: the server path and the client replay path agree exactly")
local reusedWork = canonical(Resolve.run(DPost, startAt + 5 * 22357, DIn, serverWork))
eq(reusedWork, serverOut, "a reused workspace does not carry state between runs")

-- A single changed input must change the output: otherwise the proof above is
-- vacuous.
local nudged = Tables.deepCopy(DPost)
nudged.salt = nudged.salt + 1
neq(canonical(Resolve.run(nudged, startAt + 3 * 22357, DIn)), reference, "changing the salt changes the outcome")
local nudged2 = Tables.deepCopy(DPost)
nudged2.postId = nudged2.postId + 1
neq(canonical(Resolve.run(nudged2, startAt + 3 * 22357, DIn)), reference, "changing the postId changes the outcome")
neq(canonical(Resolve.run(DPost, startAt + 4 * 22357, DIn)), reference, "changing the time changes the outcome")
local fewer = {}
for i = 1, #DIn - 1 do
	fewer[i] = DIn[i]
end
neq(canonical(Resolve.run(DPost, startAt + 3 * 22357, fewer)), reference, "changing the inbound list changes the outcome")

-- No dependence on hash-table iteration order: the same logical post built in a
-- different insertion order must resolve identically.
local shuffledPost = Post.new(1001, 4455667788, 987654321, Tide.EPOCH)
shuffledPost.tier = 4
shuffledPost.current = 0
local addOrder = { 19, 1, 12, 3, 10, 9, 7 }
local qty = { [1] = 40, [3] = 25, [7] = 12, [9] = 6, [10] = 30, [12] = 3, [19] = 8 }
for i = 1, #addOrder do
	Post.addStock(shuffledPost, addOrder[i], qty[addOrder[i]])
end
Post.setShelf(shuffledPost, 1, 1, 4)
Post.setShelf(shuffledPost, 2, 3, 12)
Post.setShelf(shuffledPost, 3, 7, 18)
Post.setShelf(shuffledPost, 4, 9, 110)
Post.setShelf(shuffledPost, 5, 12, 240)
Post.setShelf(shuffledPost, 6, 19, 80)
shuffledPost.orders = Orders.empty()
shuffledPost.ordersBytecode = Orders.encode(shuffledPost.orders)
shuffledPost.resolvedAt = startAt
eq(canonical(Resolve.run(shuffledPost, startAt + 3 * 22357, DIn)), reference, "insertion order does not affect the result")

-- PATH INDEPENDENCE, and its one documented exception.
--
-- With no inbound drifters, resolving in two hops must equal resolving in one:
-- decay, spoilage, comb maturation and passive income are all per-epoch pure
-- functions, so a player who opens the game at hour 3 and again at hour 6 must
-- land on exactly the state of a player who only opened it at hour 6.
local quiet = Tables.deepCopy(DPost)
local hopped = Resolve.run(quiet, startAt + 1 * 22357, {})
local hoppedTwice = Resolve.run(hopped, startAt + 3 * 22357, {})
local straight = Resolve.run(quiet, startAt + 3 * 22357, {})
ok(
	Codec.equal(PostCodec.encode(hoppedTwice), PostCodec.encode(straight)),
	"with no visitors, resolving 1 epoch then 2 more equals resolving 3 at once"
)

-- The exception, asserted so it can never become an accident: ARRIVAL
-- SCHEDULING depends on the width of the window being resolved, because a
-- drifter's epoch is its hash reduced modulo the epoch count. Feeding the same
-- inbound list to two different windows therefore does NOT commute. That is
-- correct -- in the live game the exchange hands each drifter to exactly one
-- resolve -- but iteration 3's ExchangeService must guarantee it, so the
-- property is pinned here rather than assumed.
local hopA = Resolve.run(DPost, startAt + 1 * 22357, DIn)
local hopB = Resolve.run(hopA, startAt + 3 * 22357, DIn)
notOk(
	Codec.equal(PostCodec.encode(hopB), PostCodec.encode(Resolve.run(DPost, startAt + 3 * 22357, DIn))),
	"re-feeding the same inbound list across two windows is NOT the same run (iteration 3 must deliver each drifter once)"
)

-- The same proof, but on the CLAMPED path, which has its own RNG use.
local CPost, CIns = baseScenario(4)
CPost.resolvedAt = startAt
local clampRef = canonical(Resolve.run(CPost, startAt + 200 * 22357, CIns))
local clampDivergences = 0
for _ = 1, 200 do
	if canonical(Resolve.run(CPost, startAt + 200 * 22357, CIns)) ~= clampRef then
		clampDivergences = clampDivergences + 1
	end
end
eq(clampDivergences, 0, "PROOF 3: 200 long-absence resolves are byte-identical")

-- A drifter list in a different order with the same members is the same run.
local rotated = {}
for i = 1, #DIn do
	rotated[i] = DIn[(i % #DIn) + 1]
end
eq(canonical(Resolve.run(DPost, startAt + 3 * 22357, rotated)), reference, "rotating the inbound list changes nothing")

-- ================================================================ economy
end
section("economy")
do

eq(#EconomyConfig.CURRENT_NAMES, 5, "five Currents")
eq(#EconomyConfig.CURRENT_TASTE_BIAS, 5, "one taste bias per Current")
for i = 1, 5 do
	eq(#EconomyConfig.CURRENT_TASTE_BIAS[i], 8, "Current " .. i .. " biases all eight axes")
	eq(EconomyConfig.CURRENT_MIN_TIER[i] >= 1, true, "Current " .. i .. " has a sane unlock tier")
end
eq(EconomyConfig.CURRENT_TASTE_BIAS[3][2], 70, "the Glass Road is ornate")
eq(EconomyConfig.CURRENT_TASTE_BIAS[5][5], 70, "the Lantern Line is social")
eq(#EconomyConfig.PASSIVE_CAP_BY_TIER, 4, "a passive cap per tier")
ok(
	EconomyConfig.PASSIVE_CAP_BY_TIER[1] < EconomyConfig.PASSIVE_CAP_BY_TIER[2]
		and EconomyConfig.PASSIVE_CAP_BY_TIER[2] < EconomyConfig.PASSIVE_CAP_BY_TIER[3]
		and EconomyConfig.PASSIVE_CAP_BY_TIER[3] < EconomyConfig.PASSIVE_CAP_BY_TIER[4],
	"passive caps increase with tier"
)
near(EconomyConfig.PASSIVE_CAP_BY_TIER[1] * 86400 / 22357, 154.6, 1.0, "tier 1 earns about 155 coin a day idle (doc 06 section 4)")
near(EconomyConfig.PASSIVE_CAP_BY_TIER[4] * 86400 / 22357, 4637.0, 10.0, "tier 4 earns about 4644 coin a day idle (doc 06 section 4)")

eq(#DrifterConfig.CLASSES, 4, "four Drifter classes")
eq(#DrifterConfig.CLASS_TIDES, 4, "one tide set per class")
eq(#DrifterConfig.BUDGET_BANDS, 4, "one budget band per class")
eq(#DrifterConfig.AXIS_NAMES, 8, "eight taste axes")
eq(DrifterConfig.AXIS_NAMES[DrifterConfig.AXIS_DEAR], "cheap_dear", "AXIS_DEAR points at the cheap/dear axis")
eq(Drifter.classValuePerMille(Drifter.SKIFF), 1000, "a SKIFF is worth 1x")
eq(Drifter.classValuePerMille(Drifter.LAUNCH), 2200, "a LAUNCH is worth 2.2x")
eq(Drifter.classValuePerMille(Drifter.LUGGER), 5000, "a LUGGER is worth 5x")
eq(Drifter.classValuePerMille(Drifter.DEEPWATER), 14000, "a DEEPWATER is worth 14x")
local weightTotal = 0
for class = 0, 3 do
	weightTotal = weightTotal + Drifter.classWeight(class)
end
eq(weightTotal, 1000, "the class arrival weights sum to 1000 per mille")
eq(Drifter.classMinTier(Drifter.DEEPWATER), 4, "DEEPWATER needs tier 4")
eq(Drifter.classMaxItems(Drifter.SKIFF), 1, "a SKIFF buys one thing")
eq(Drifter.classMaxItems(Drifter.DEEPWATER), 4, "a DEEPWATER buys up to four")
eq(Drifter.className(99), "UNKNOWN", "className is total")
eq(Drifter.classFromName("LUGGER"), Drifter.LUGGER, "classFromName")
eq(Drifter.classFromName("NOPE"), nil, "classFromName of an unknown name")

local synth = Drifter.synthesize(RNG.new(4242), 123456, 77, 2, 4)
ok(Drifter.validate(synth), "a synthesized drifter validates")
eq(#synth.taste, 8, "a synthesized drifter has eight taste axes")
local outOfBand = 0
local tierViolations = 0
for i = 1, 500 do
	local sd = Drifter.synthesize(RNG.new(i), 700000 + i, 20, i % 5, (i % 4) + 1)
	local valid, why = Drifter.validate(sd)
	if not valid then
		outOfBand = outOfBand + 1
		if i < 3 then print("synth invalid: " .. tostring(why)) end
	end
	if sd.tier < Drifter.classMinTier(sd.class) then tierViolations = tierViolations + 1 end
end
eq(outOfBand, 0, "500 synthesized drifters all validate")
eq(tierViolations, 0, "synthesis never produces a class above the post's tier")
local tier1Classes = {}
for i = 1, 200 do
	tier1Classes[Drifter.synthesize(RNG.new(i * 7), 710000 + i, 20, 0, 1).class] = true
end
eq(Tables.count(tier1Classes), 1, "a tier-1 post only ever sees SKIFFs")

local invalid = Tables.deepCopy(synth)
invalid.taste[1] = 500
notOk(Drifter.validate(invalid), "an out-of-range taste axis is caught")
invalid = Tables.deepCopy(synth)
invalid.id = invalid.id + 1
notOk(Drifter.validate(invalid), "a mismatched id is caught")
invalid = Tables.deepCopy(synth)
invalid.tier = 1
invalid.class = Drifter.DEEPWATER
notOk(Drifter.validate(invalid), "a class above the drifter's tier is caught")
invalid = Tables.deepCopy(synth)
invalid.extra = 1
notOk(Drifter.validate(invalid), "an unexpected field is caught")

eq(#FindsConfig.FINDS, 200, "doc 07 section 5 wants 200 finds for v1")
local idsSeen = {}
local badFind = 0
for i = 1, #FindsConfig.FINDS do
	local row = FindsConfig.FINDS[i]
	if idsSeen[row[1]] then badFind = badFind + 1 end
	idsSeen[row[1]] = true
	if row[1] < 1 or row[1] > FindsConfig.MAX_FIND_ID then badFind = badFind + 1 end
	if row[3] < 1 then badFind = badFind + 1 end
	if #row[8] ~= 8 then badFind = badFind + 1 end
	if row[5] < 1 or row[5] > #FindsConfig.GROUP_NAMES then badFind = badFind + 1 end
	if row[6] < 1 or row[6] > FindsConfig.ZONE_COUNT then badFind = badFind + 1 end
	-- Added with the 176 iteration-6 rows. The loop above never looked
	-- inside the taste vector or at the perishable flag, so a typo'd axis
	-- (-700 instead of -70) or a perishable value of 2 would have been
	-- waved through into the economy.
	if row[4] ~= 0 and row[4] ~= 1 then badFind = badFind + 1 end
	if row[7] < 1 then badFind = badFind + 1 end
	for axis = 1, #row[8] do
		local v = row[8][axis]
		if v ~= math.floor(v) or v < DrifterConfig.TASTE_MIN or v > DrifterConfig.TASTE_MAX then
			badFind = badFind + 1
		end
	end
end
eq(badFind, 0, "every find row is well formed")
eq(Tables.count(idsSeen), #FindsConfig.FINDS, "every find id is unique")

-- --------------------------------------------------------------- letters
-- The letter list is the other half of the dispatch feature that iteration 7
-- found inert: the ids were validated against a hard-coded ceiling of 96 and
-- there was no phrase list at all. Pin the count to the doc 07 target so the
-- content cannot be deleted without turning this red.
local LettersConfig = TidekeeperRequire("LettersConfig")
eq(#LettersConfig.LETTERS, 120, "doc 07 section 5 wants 120 letters for v1")
eq(LettersConfig.MAX_LETTER_ID, #LettersConfig.LETTERS, "the validation ceiling matches the content")

local letterIds = {}
local badLetter = 0
for i = 1, #LettersConfig.LETTERS do
	local row = LettersConfig.LETTERS[i]
	if row[1] ~= i then badLetter = badLetter + 1 end
	if letterIds[row[1]] then badLetter = badLetter + 1 end
	letterIds[row[1]] = true
	if row[2] < 1 or row[2] > #LettersConfig.CATEGORY_NAMES then badLetter = badLetter + 1 end
end
eq(badLetter, 0, "every letter row is well formed and densely numbered")
eq(Tables.count(letterIds), #LettersConfig.LETTERS, "every letter id is unique")


-- =============================================================== benchmark
end
section("benchmark")
do

if BENCH_ENABLED then
	local benchPost = mkPost(4)
	benchPost.orders = Orders.empty()
	benchPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.CLASS_IS, Drifter.SKIFF), Orders.act(Orders.SERVE_ADJ, -10))
	benchPost.orders.rules[2] = Orders.rule(Orders.cond(Orders.WANTS_SOMETHING), Orders.act(Orders.SERVE))
	benchPost.orders.rules[3] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, 10))
	local benchCtx = mkContext(500, "HIGH")
	local benchRng = RNG.new(31415)
	local benchDrifter = Drifter.synthesize(RNG.new(2718), 880000, 500, 0, 4)
	benchDrifter.budget = 5000

	-- Warm up, so the first-call cost of the VM is not in the sample.
	for _ = 1, 500 do
		Visit.resolve(benchPost, benchDrifter, benchCtx, benchRng)
	end

	local BATCH = 10
	local SAMPLES = 500
	local samples = {}
	local total = 0
	for s = 1, SAMPLES do
		local t0 = os.clock()
		for _ = 1, BATCH do
			Visit.resolve(benchPost, benchDrifter, benchCtx, benchRng)
		end
		local dt = (os.clock() - t0) / BATCH
		samples[s] = dt
		total = total + dt
	end
	table.sort(samples)
	local median = samples[math.floor(SAMPLES / 2)]
	local p99 = samples[math.floor(SAMPLES * 0.99)]
	local mean = total / SAMPLES

	print("")
	print("=== Visit.resolve benchmark (fengari, NOT Luau) ===")
	print(string.format("  samples        %d batches of %d calls", SAMPLES, BATCH))
	print(string.format("  mean           %.2f us", mean * 1e6))
	print(string.format("  median         %.2f us", median * 1e6))
	print(string.format("  p99            %.2f us", p99 * 1e6))
	print(string.format("  budget (Luau)  %s", "18 us median / 50 us p99 (doc 04 section 6)"))
	print("  VERDICT: NOT VERIFIED. fengari is a Lua interpreter written in")
	print("  JavaScript and runs roughly 30-100x slower than Luau. These")
	print("  figures are an upper bound and a regression tripwire only. The")
	print("  18 us budget must be measured in Studio (iteration 3).")

	-- A calibration loop, so the number above can at least be read relative to
	-- something with a known cost.
	local c0 = os.clock()
	local acc = 0
	for i = 1, 1000000 do
		acc = acc + i
	end
	local calibration = os.clock() - c0
	print(string.format("  calibration    1e6 integer adds took %.1f ms on this VM", calibration * 1000))
	print(string.format("  ratio          one visit costs about %.0f integer adds", median / (calibration / 1000000)))
	ok(median > 0, "the benchmark produced a positive median")
	ok(p99 >= median, "p99 is at least the median")
	BENCH_RESULT = { mean = mean, median = median, p99 = p99, calibration = calibration }
else
	ok(true, "benchmark skipped by request")
end

end
-- ---------------------------------------------------------------- summary

print("")
print("=== assertions by section ===")
for i = 1, #SECTION_ORDER do
	local name = SECTION_ORDER[i]
	print(string.format("  %-14s %4d", name, SECTION_COUNTS[name]))
end
if #TESTS.failures > 0 then
	print("")
	print("=== failures ===")
	for i = 1, #TESTS.failures do
		print("  " .. TESTS.failures[i])
	end
end
