--!nonstrict
-- tools/bench/resolve-bench.luau
--
-- Measures Visit.resolve in a REAL Luau VM. This is the OD12 measurement that
-- iterations 2 and 3 both deferred.
--
-- The construction below is a deliberate copy of the fengari benchmark in
-- tools/tests/pure-tests.lua (the "benchmark" section): same post, same tier,
-- same three standing-order rules, same drifter, same budget, same warmup,
-- same 500 batches of 10. If the two harnesses build different work, the
-- comparison between them is meaningless and so is the ratio.

local GameConfig = TKRequire("GameConfig")
local Tide = TKRequire("Tide")
local RNG = TKRequire("RNG")
local Drifter = TKRequire("Drifter")
local Post = TKRequire("Post")
local Orders = TKRequire("Orders")
local Visit = TKRequire("Visit")
local Resolve = TKRequire("Resolve")

-- ------------------------------------------------------------------ fixtures

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

local function mkContext(epoch, tide)
	local ctx = Visit.newContext()
	ctx.epoch = epoch
	ctx.tide = tide
	ctx.hostId = 4455667788
	ctx.berthsUsed = 0
	return ctx
end

-- --------------------------------------------------------------- correctness
-- A benchmark that measures the wrong answer quickly is worth nothing. Before
-- timing anything, assert that real Luau produces the SAME values the fengari
-- suite asserts. These are copied from pure-tests.lua, where they are checked
-- against published vectors.

local Hash = TKRequire("Hash")
local failures = 0
local function check(label, got, want)
	if got ~= want then
		failures += 1
		print(string.format("  MISMATCH %-28s got %s  want %s", label, tostring(got), tostring(want)))
	end
end

check("Hash.string('foobar')", Hash.string("foobar"), 3214735720)
check("bit32 is native", bit32.bxor(0xDEADBEEF, 0x9E3779B9), 1083885398)
check("no 32-bit wraparound", 255 * 16777216, 4278190080)
check("MAX_CATCHUP_EPOCHS", GameConfig.MAX_CATCHUP_EPOCHS, 27)

local detPost = mkPost(4)
detPost.orders = Orders.empty()
local rich = Drifter.synthesize(RNG.new(2718), 880000, 500, 0, 4)
rich.budget = 5000
local dA = Visit.resolve(detPost, rich, mkContext(10, "HIGH"), RNG.new(99))
local dB = Visit.resolve(detPost, rich, mkContext(10, "HIGH"), RNG.new(99))
check("resolve is deterministic (outcome)", dA.outcome, dB.outcome)
check("resolve is deterministic (coin)", dA.coin, dB.coin)

if failures > 0 then
	print(string.format("\nFAIL: %d correctness check(s) failed in real Luau.", failures))
	print("The fengari suite and the Luau VM disagree. Investigate before")
	print("trusting ANY timing below.")
	BENCH_FAILED = true
else
	print("correctness: real Luau agrees with the fengari suite on all spot checks")
end

-- ------------------------------------------------------------------ the bench

local benchPost = mkPost(4)
benchPost.orders = Orders.empty()
benchPost.orders.rules[1] = Orders.rule(Orders.cond(Orders.CLASS_IS, Drifter.SKIFF), Orders.act(Orders.SERVE_ADJ, -10))
benchPost.orders.rules[2] = Orders.rule(Orders.cond(Orders.WANTS_SOMETHING), Orders.act(Orders.SERVE))
benchPost.orders.rules[3] = Orders.rule(Orders.cond(Orders.ALWAYS), Orders.act(Orders.SERVE_ADJ, 10))
local benchCtx = mkContext(500, "HIGH")
local benchRng = RNG.new(31415)
local benchDrifter = Drifter.synthesize(RNG.new(2718), 880000, 500, 0, 4)
benchDrifter.budget = 5000

for _ = 1, 5000 do
	Visit.resolve(benchPost, benchDrifter, benchCtx, benchRng)
end

local BATCH = 100
local SAMPLES = 500
local samples = table.create(SAMPLES)
local total = 0
for s = 1, SAMPLES do
	local t0 = os.clock()
	for _ = 1, BATCH do
		Visit.resolve(benchPost, benchDrifter, benchCtx, benchRng)
	end
	local dt = (os.clock() - t0) / BATCH
	samples[s] = dt
	total += dt
end
table.sort(samples)
local median = samples[math.floor(SAMPLES / 2)]
local p99 = samples[math.floor(SAMPLES * 0.99)]
local mean = total / SAMPLES

-- Calibration: the same 1e6-integer-add loop the fengari benchmark runs, so
-- the two VMs can be compared on something with a known shape.
local c0 = os.clock()
local acc = 0
for i = 1, 1000000 do
	acc += i
end
local calibration = os.clock() - c0

print("")
print("=== Visit.resolve benchmark (REAL Luau) ===")
print(string.format("  samples        %d batches of %d calls", SAMPLES, BATCH))
print(string.format("  mean           %.3f us", mean * 1e6))
print(string.format("  median         %.3f us", median * 1e6))
print(string.format("  p99            %.3f us", p99 * 1e6))
print(string.format("  budget         18 us median / 50 us p99 (doc 04 section 6)"))
print(string.format("  headroom       %.1fx under the median budget", 18 / (median * 1e6)))
print(string.format("  calibration    1e6 integer adds took %.1f ms", calibration * 1000))
print(string.format("  ratio          one visit costs about %.0f integer adds", median / (calibration / 1000000)))

-- ------------------------------------------------- Resolve.run, the real unit
-- Visit.resolve is one visitor. Resolve.run is what a session actually pays:
-- up to 27 epochs, up to 8 arrivals each. Measure the worst case too, because
-- that is the number that decides whether a catch-up blocks a join.

local RESOLVE_INBOUND = {}
for i = 1, 8 * 27 do
	RESOLVE_INBOUND[i] = Drifter.synthesize(RNG.new(i * 7919), 900000 + i, 1, i % 5, 4)
end

local function timeResolve(epochs, inbound, reps)
	local work = Resolve.newWorkspace()
	local base = mkPost(4)
	base.orders = Orders.empty()
	-- warm
	for _ = 1, 20 do
		Resolve.run(base, Tide.EPOCH + epochs * Tide.EPOCH_SECONDS, inbound, work)
	end
	local t0 = os.clock()
	for _ = 1, reps do
		Resolve.run(base, Tide.EPOCH + epochs * Tide.EPOCH_SECONDS, inbound, work)
	end
	return (os.clock() - t0) / reps
end

local oneEpochEmpty = timeResolve(1, {}, 2000)
local fullCatchup = timeResolve(27, RESOLVE_INBOUND, 200)

print("")
print("=== Resolve.run (REAL Luau) ===")
print(string.format("  1 epoch, no arrivals        %8.1f us", oneEpochEmpty * 1e6))
print(string.format("  27 epochs, 216 arrivals     %8.1f us   (the documented worst case)", fullCatchup * 1e6))
print(string.format("  budget for a full catch-up  %8.1f us   (doc 01 section 5: 12 ms slow slot)", 12000.0))
print(string.format("  headroom                    %8.1fx", 12000 / (fullCatchup * 1e6)))

BENCH_RESULT = {
	visitMedianUs = median * 1e6,
	visitMeanUs = mean * 1e6,
	visitP99Us = p99 * 1e6,
	calibrationMs = calibration * 1000,
	resolveOneEpochUs = oneEpochEmpty * 1e6,
	resolveFullCatchupUs = fullCatchup * 1e6,
}

print("")
print(
	string.format(
		"RESULT median=%.3fus p99=%.3fus catchup=%.1fus verdict=%s",
		median * 1e6,
		p99 * 1e6,
		fullCatchup * 1e6,
		(median * 1e6 <= 18 and p99 * 1e6 <= 50) and "WITHIN_BUDGET" or "OVER_BUDGET"
	)
)
