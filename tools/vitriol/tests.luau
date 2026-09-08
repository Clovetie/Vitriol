-- tests.luau
-- Location: tools/vitriol/tests.luau  (executed by tools/vitriol-smoke-test.js)
-- Purpose:  Runtime assertions for the pure Vitriol modules. These tests execute
--           the REAL modules (loaded from code/) inside fengari - they are not a
--           reimplementation, so a regression in Lib/ fails here.

local MathExt = VitriolRequire("MathExt")
local RNG = VitriolRequire("RNG")
local Fabrik = VitriolRequire("Fabrik")
local Genetics = VitriolRequire("Genetics")
local Tables = VitriolRequire("Tables")
local Signal = VitriolRequire("Signal")
local Noise = VitriolRequire("Noise")
local SpatialHash = VitriolRequire("SpatialHash")
local UtilityAI = VitriolRequire("UtilityAI")
local QLearning = VitriolRequire("QLearning")
local MarkovPredictor = VitriolRequire("MarkovPredictor")
local RegionIntegrity = VitriolRequire("RegionIntegrity")
local Skeleton = VitriolRequire("Skeleton")
local SkeletonCodec = VitriolRequire("SkeletonCodec")
local NoiseField = VitriolRequire("NoiseField")

TESTS = { passed = 0, failed = 0 }

local function check(cond, msg)
	if cond then
		TESTS.passed = TESTS.passed + 1
		print("PASS  " .. msg)
	else
		TESTS.failed = TESTS.failed + 1
		warn("FAIL  " .. msg)
	end
end

local function approx(a, b, tol)
	return math.abs(a - b) <= (tol or 1e-6)
end

local function argmax(t)
	local bestK, bestV = nil, -math.huge
	for k, v in pairs(t) do
		if v > bestV then
			bestK, bestV = k, v
		end
	end
	return bestK, bestV
end

do
print("=== MathExt ===")

-- damp must be frame-rate independent: one step of dt equals two steps of dt/2.
local oneStep = MathExt.damp(0, 1, 5, 1 / 30)
local halfA = MathExt.damp(0, 1, 5, 1 / 60)
local twoStep = MathExt.damp(halfA, 1, 5, 1 / 60)
check(approx(oneStep, twoStep, 1e-9), "MathExt.damp is frame-rate independent")
check(oneStep > 0 and oneStep < 1, "MathExt.damp stays inside (0,1) for one step")
check(approx(MathExt.damp(0, 1, 0, 1), 0), "MathExt.damp with lambda 0 does not move")

check(approx(MathExt.smoothstepRange(-5, 0, 10), 0), "smoothstepRange clamps below edge0")
check(approx(MathExt.smoothstepRange(15, 0, 10), 1), "smoothstepRange clamps above edge1")
check(approx(MathExt.smoothstepRange(5, 0, 10), 0.5), "smoothstepRange midpoint is 0.5")
check(approx(MathExt.approach(0, 10, 3), 3), "approach moves by maxDelta")
check(approx(MathExt.approach(9, 10, 3), 10), "approach never overshoots")
check(approx(MathExt.angleBetweenDeg(1, 0, 0, 0, 1, 0), 90, 1e-9), "angleBetweenDeg right angle")
check(approx(MathExt.angleBetweenDeg(0, 0, 0, 1, 0, 0), 0), "angleBetweenDeg degrades to 0 on zero input")

local cx, cy, cz = MathExt.clampMagnitude(3, 4, 0, 5)
check(approx(math.sqrt(cx * cx + cy * cy + cz * cz), 5, 1e-9), "clampMagnitude scales to the cap")
local sx, sy, sz = MathExt.clampMagnitude(0.1, 0, 0, 5)
check(approx(sx, 0.1), "clampMagnitude leaves short vectors alone")

end
do
print("=== RNG ===")

local a1 = RNG.new(1234)
local a2 = RNG.new(1234)
local deterministic = true
for _ = 1, 200 do
	if a1:next() ~= a2:next() then
		deterministic = false
		break
	end
end
check(deterministic, "RNG is deterministic for a given seed")

local b1 = RNG.new(1234)
local b2 = RNG.new(9999)
local differs = false
for _ = 1, 20 do
	if b1:next() ~= b2:next() then
		differs = true
		break
	end
end
check(differs, "RNG differs across seeds")

local boundsOk = true
local intOk = true
local r = RNG.new(4242)
for _ = 1, 5000 do
	local f = r:range(2, 5)
	if f < 2 or f >= 5 then
		boundsOk = false
	end
	local i = r:int(3, 7)
	if i < 3 or i > 7 or i ~= math.floor(i) then
		intOk = false
	end
end
check(boundsOk, "RNG:range stays within [a,b)")
check(intOk, "RNG:int stays within [a,b] and is integral")

-- The xorshift32 absorbing state must never be reached.
local zeroRng = RNG.new(0)
local nonZero = true
for _ = 1, 100 do
	if zeroRng:nextInt32() == 0 then
		nonZero = false
	end
end
check(nonZero, "RNG never collapses to the zero absorbing state from seed 0")

local mean = 0
local gr = RNG.new(77)
local samples = 6000
for _ = 1, samples do
	mean = mean + gr:gaussian()
end
mean = mean / samples
check(math.abs(mean) < 0.05, "RNG:gaussian mean is near 0 (got " .. string.format("%.4f", mean) .. ")")

local weightedList = { { weight = 0, name = "never" }, { weight = 1, name = "always" } }
local weightOk = true
local wr = RNG.new(5)
for _ = 1, 200 do
	if wr:weighted(weightedList).name ~= "always" then
		weightOk = false
	end
end
check(weightOk, "RNG:weighted respects zero weights")
check(RNG.new(1):weighted({}) == nil, "RNG:weighted returns nil for an empty list")

local forked = RNG.new(11):fork()
check(type(forked.next) == "function", "RNG:fork returns a usable RNG")

local snap = RNG.new(31337)
for _ = 1, 50 do
	snap:next()
end
local restored = RNG.deserialize(snap:serialize())
check(approx(snap:next(), restored:next(), 0), "RNG serialize/deserialize reproduces the stream")

end
do
print("=== Fabrik ===")

-- Reachable target: must converge, must preserve bone lengths exactly.
local chain = Fabrik.newChain(10, 1)
Fabrik.setStraight(chain, 0, 0, 0, 0, 1, 0)
check(approx(Fabrik.totalLength(chain), 9), "totalLength sums the declared bones")
local reached = Fabrik.solve(chain, 2, 0, 0)
check(reached, "solve reaches an in-range target")
check(Fabrik.endEffectorError(chain, 2, 0, 0) < 0.005, "tip lands within tolerance of the target")
check(Fabrik.maxBoneError(chain) < 1e-6, "solve preserves bone lengths (reachable case)")

-- Root must stay pinned - the rig positions the base, the solver must not move it.
check(approx(chain.x[1], 0, 1e-9) and approx(chain.y[1], 0, 1e-9) and approx(chain.z[1], 0, 1e-9), "solve pins the root joint")

-- Unreachable target: must return false, fully extend, and still preserve lengths.
local far = Fabrik.newChain(5, 1)
Fabrik.setStraight(far, 0, 0, 0, 0, 1, 0)
local farReached = Fabrik.solve(far, 100, 0, 0)
check(farReached == false, "solve reports false for an out-of-reach target")
check(Fabrik.maxBoneError(far) < 1e-6, "solve preserves bone lengths (unreachable case)")
check(approx(far.x[far.count], 4, 1e-6), "unreachable chain extends fully toward the target")
check(approx(far.y[far.count], 0, 1e-6), "unreachable chain has no lateral offset")

-- Cone limits: no interior joint may bend past the limit.
local limited = Fabrik.newChain(8, 1)
Fabrik.setStraight(limited, 0, 0, 0, 0, 1, 0)
local LIMIT = 30
Fabrik.solve(limited, 0.5, 0, 0, { maxAngle = LIMIT, tolerance = 0.005, maxIterations = 12 })
local worstAngle = 0
for i = 2, limited.count - 1 do
	local ang = MathExt.angleBetweenDeg(
		limited.x[i] - limited.x[i - 1], limited.y[i] - limited.y[i - 1], limited.z[i] - limited.z[i - 1],
		limited.x[i + 1] - limited.x[i], limited.y[i + 1] - limited.y[i], limited.z[i + 1] - limited.z[i]
	)
	if ang > worstAngle then
		worstAngle = ang
	end
end
check(worstAngle <= LIMIT + 1e-6, "cone limit is respected (worst joint " .. string.format("%.2f", worstAngle) .. " deg)")
check(Fabrik.maxBoneError(limited) < 1e-6, "constraint pass preserves bone lengths")

-- planeBias must not break lengths or the solve.
local biased = Fabrik.newChain(9, 1)
Fabrik.setStraight(biased, 0, 0, 0, 0, 1, 0)
local biasedReached = Fabrik.solve(biased, 1.5, 0.5, 0, { maxAngle = 45, planeBias = 0.6, upX = 0, upY = 0, upZ = 1 })
check(Fabrik.maxBoneError(biased) < 1e-6, "planeBias preserves bone lengths")
check(biasedReached == true or biasedReached == false, "planeBias solve returns a boolean")

-- Statistical: many random chains must all converge and keep their lengths.
local rr = RNG.new(20260908)
local converged, lengthSafe, tested = 0, 0, 0
for _ = 1, 200 do
	local c = Fabrik.newChain(rr:int(4, 16), rr:range(0.4, 1.6))
	local bx, by, bz = rr:range(-10, 10), rr:range(-10, 10), rr:range(-10, 10)
	Fabrik.setStraight(c, bx, by, bz, rr:range(-1, 1), rr:range(-1, 1), rr:range(-1, 1))
	local total = Fabrik.totalLength(c)
	-- Aim at a random DIRECTION at 80% of reach. Offsetting each axis
	-- independently would routinely place the target outside the sphere of reach
	-- and test the unreachable branch instead of the solver.
	local ux, uy, uz = rr:range(-1, 1), rr:range(-1, 1), rr:range(-1, 1)
	local um = math.sqrt(ux * ux + uy * uy + uz * uz)
	if um < 1e-6 then
		ux, uy, uz, um = 0, 1, 0, 1
	end
	local reach = total * 0.8
	local tx = bx + (ux / um) * reach
	local ty = by + (uy / um) * reach
	local tz = bz + (uz / um) * reach
	tested = tested + 1
	if Fabrik.solve(c, tx, ty, tz, { maxIterations = 16 }) then
		converged = converged + 1
	end
	if Fabrik.maxBoneError(c) < 1e-5 then
		lengthSafe = lengthSafe + 1
	end
end
check(lengthSafe == tested, "bone lengths preserved across " .. tested .. " random chains")
check(converged >= tested * 0.98, "converged on " .. converged .. "/" .. tested .. " random chains")

-- The residual floor grows with chain length and the solver must PLATEAU rather
-- than spin: with an impossible tolerance it still has to return promptly.
local longChain = Fabrik.newChain(16, 1)
Fabrik.setStraight(longChain, 0, 0, 0, 0, 1, 0)
Fabrik.solve(longChain, 0.4, 0.4, 0, { maxIterations = 64, tolerance = 1e-9 })
local longErr = Fabrik.endEffectorError(longChain, 0.4, 0.4, 0)
check(longErr < 0.02, "a 16-joint chain lands inside the visible-noise floor (" .. string.format("%.5f", longErr) .. " studs)")
check(Fabrik.maxBoneError(longChain) < 1e-6, "long chain preserves bone lengths despite the residual floor")

-- dampChain must not allocate or corrupt; the tip should lag the base.
-- Move the WHOLE source chain so both ends have somewhere to go - moving only
-- the tip would leave the base with nothing to follow and the comparison is
-- meaningless.
local src = Fabrik.newChain(6, 1)
Fabrik.setStraight(src, 0, 0, 0, 0, 1, 0)
local dst = Fabrik.newChain(6, 1)
Fabrik.setStraight(dst, 0, 0, 0, 0, 1, 0)
for i = 1, 6 do
	src.y[i] = src.y[i] + 5
end
Fabrik.dampChain(dst, src, 30, 6, 1 / 60)
local baseMoved = dst.y[1] - 0
local tipMoved = dst.y[6] - 5
check(baseMoved > 0, "dampChain moves the base toward its target")
check(tipMoved > 0 and tipMoved < baseMoved, "dampChain makes the tip lag the base")
check(Fabrik.maxBoneError(dst) > 0, "dampChain intentionally breaks bone lengths (it is presentation only)")

-- Defensive: a degenerate chain request must not produce a broken chain.
local tiny = Fabrik.newChain(0, 1)
check(tiny.count >= 2 and #tiny.len == tiny.count - 1, "newChain clamps a degenerate count to a solvable chain")
check(Fabrik.solve(tiny, 1, 0, 0) == true or Fabrik.solve(tiny, 1, 0, 0) == false, "solve tolerates a minimal chain")

end
do
print("=== Genetics ===")

local gen = Genetics.new()
local grng = RNG.new(90210)

local genome = gen:roll(grng)
check(gen:cost(genome) <= gen.budget + 1e-9, "rolled genome fits the metabolic budget")
check(genome.TendrilCount >= 6 and genome.TendrilCount <= 14, "TendrilCount inside its range")

-- A genome pushed to the maximum must be projected back under budget.
local greedy = { TendrilCount = 14, scars = {} }
for i = 1, #gen.genes do
	local g = gen.genes[i]
	if g.kind ~= "int" then
		greedy[g.name] = 1
	end
end
check(gen:cost(greedy) > gen.budget, "a maxed genome would exceed the budget before projection")
local projected = gen:project(greedy)
check(gen:cost(projected) <= gen.budget + 1e-9, "projection brings a maxed genome back under budget")

-- Mutation must never produce an illegal genome, and must not mutate its parent.
local parent = gen:roll(grng)
local parentSpeed = parent.Speed
local mutateOk = true
for _ = 1, 200 do
	local child = gen:mutate(parent, grng)
	if gen:cost(child) > gen.budget + 1e-9 then
		mutateOk = false
	end
	for k, v in pairs(child) do
		if type(v) == "number" and (v ~= v) then
			mutateOk = false
		end
	end
end
check(mutateOk, "mutate always yields a legal, non-NaN genome")
check(approx(parent.Speed, parentSpeed, 0), "mutate does not modify the parent genome")

local cross = gen:crossover(gen:roll(grng), gen:roll(grng), grng, 2.0, 0.5)
check(gen:cost(cross) <= gen.budget + 1e-9, "crossover yields a legal genome")
check(type(cross.TendrilCount) == "number", "crossover carries integer genes")

-- Express maps genes onto gameplay numbers.
local fast = { Speed = 1, Strength = 1, Aggression = 1, TendrilCount = 10, scars = {} }
local stats = gen:express(fast)
check(stats.TendrilCount == 10, "express preserves TendrilCount")
check(stats.HaulSpeed > 10, "a Speed-1 creature hauls fast (" .. string.format("%.1f", stats.HaulSpeed) .. ")")
check(stats.JointsPerTendril >= 8, "express always yields a solvable joint count")
check(stats.SenseRange.VIBRATION > 40, "express produces sense ranges")

-- THE headline behaviour from docs/02 §6: a fast+strong creature's instinct says CHARGE.
local chargeAction = argmax(stats.Temperament)
check(chargeAction == "CHARGE", "fast+strong+aggressive instinct prefers CHARGE (got " .. tostring(chargeAction) .. ")")

-- ...and a patient, cunning creature's instinct says STALK.
local patient = {
	Speed = 0.2, Strength = 0.2, Mass = 0, Patience = 1, Cunning = 0.8,
	Aggression = 0, Adhesion = 0.1, Softness = 0.1, Armour = 0, Endurance = 0.5,
	TendrilCount = 8, scars = {},
}
local patientStats = gen:express(patient)
local patientAction = argmax(patientStats.Temperament)
check(patientAction == "STALK", "patient+cunning instinct prefers STALK (got " .. tostring(patientAction) .. ")")

-- logPrior must be monotonic in the instinct score, and finite.
local lp = Genetics.logPrior({ CHARGE = 1.0, STALK = 0.1, NONE = 0 })
check(lp.CHARGE > lp.STALK, "logPrior is monotonic in the instinct score")
check(lp.NONE == lp.NONE and lp.NONE < lp.STALK, "logPrior floors a zero instinct instead of going -inf")

-- Scars must slow the creature down (the persistent-injury tell).
local healthy = gen:express({ Speed = 0.8, Mass = 0.3, TendrilCount = 8, scars = {} })
local wounded = gen:express({ Speed = 0.8, Mass = 0.3, TendrilCount = 8, scars = { "trap_collapse" } })
check(wounded.HaulSpeed < healthy.HaulSpeed, "scars reduce haul speed")

-- Fitness must reward kills and punish damage taken.
local fit = gen:fitness({}, { kills = 2, grabSeconds = 60, damageDealt = 100, damageTaken = 0, survived = true })
local badFit = gen:fitness({}, { kills = 0, damageTaken = 400, died = true })
check(fit > badFit, "fitness ranks a successful night above a failed one")

end
do
print("=== RegionIntegrity ===")

-- Two different wrap geometries must produce different sever orders. This is the
-- assertion that makes the kill procedural rather than canned (docs/04 §7.2).
local function runKill(radiusOf)
	local body = RegionIntegrity.new()
	for t = 0.1, 60, 0.1 do
		body:applyShear(0.1, { omega = 8, grip = 0.6, radiusOf = radiusOf, shearMul = 1, ramp = 1.5 })
	end
	return body
end

local handsOut = runKill(function(name)
	if name == "LeftHand" or name == "RightHand" then
		return 1.2
	elseif name == "LeftArm" or name == "RightArm" then
		return 0.9
	elseif name == "LeftLeg" or name == "RightLeg" then
		return 0.6
	elseif name == "Head" then
		return 0.4
	end
	return 0.2
end)
local firstHandsOut = handsOut:log()[1]
check(firstHandsOut ~= nil, "a coil with the hands outside severs something")
check(firstHandsOut and (firstHandsOut.name == "LeftHand" or firstHandsOut.name == "RightHand"),
	"hands-first geometry severs a hand first (got " .. tostring(firstHandsOut and firstHandsOut.name) .. ")")

local legsOut = runKill(function(name)
	if name == "LeftLeg" or name == "RightLeg" then
		return 1.6
	elseif name == "LeftArm" or name == "RightArm" then
		return 0.5
	elseif name == "LeftHand" or name == "RightHand" then
		return 0.3
	elseif name == "Head" then
		return 0.4
	end
	return 0.2
end)
local firstLegsOut = legsOut:log()[1]
check(firstLegsOut ~= nil, "a coil with the legs outside severs something")
check(firstLegsOut and (firstLegsOut.name == "LeftLeg" or firstLegsOut.name == "RightLeg"),
	"legs-first geometry severs a leg first (got " .. tostring(firstLegsOut and firstLegsOut.name) .. ")")
check(firstHandsOut.name ~= firstLegsOut.name, "the two geometries produce different first severs")

-- Downstream cascade: an arm takes its hand with it, in one call.
local body = RegionIntegrity.new()
local cascaded = body:sever("RightArm")
check(#cascaded == 2, "severing an arm cascades to its hand (got " .. #cascaded .. ")")
check(body:get("RightHand") == 0, "the cascaded hand reports zero integrity")
check(body:get("LeftHand") > 0, "the other hand is untouched")

-- Severing is idempotent: a second call must not double-report.
check(#body:sever("RightArm") == 0, "re-severing an already-severed region is a no-op")

-- The torso is not severable; it only reaches zero integrity.
local torsoBody = RegionIntegrity.new()
for _ = 1, 4000 do
	torsoBody:applyShear(0.1, { omega = 20, grip = 1, radiusOf = function() return 2 end, ramp = 0.01 })
end
check(torsoBody:get("Torso") == 0, "the torso integrity bottoms out at zero")
local torsoSevered = false
for _, entry in ipairs(torsoBody:log()) do
	if entry.name == "Torso" then
		torsoSevered = true
	end
end
check(torsoSevered == false, "the torso is never severed, only consumed")

-- meanIntegrity must fall as damage accrues, driving the escape threshold.
local fresh = RegionIntegrity.new()
check(approx(fresh:meanIntegrity(), 1, 1e-9), "a fresh body has full mean integrity")
fresh:applyShear(5, { omega = 8, grip = 0.6, radiusOf = function() return 1 end, ramp = 0.1 })
check(fresh:meanIntegrity() < 1, "mean integrity falls under shear")

end
do
print("=== cross-module: the whole creature pipeline ===")

-- Genome -> stats -> a rig built from those stats -> a solve. This is the actual
-- data path the server takes each frame, exercised end to end.
local pipeRng = RNG.new(1)
local pipeGen = Genetics.new()
local pipeGenome = pipeGen:roll(pipeRng)
local pipeStats = pipeGen:express(pipeGenome)
local tendril = Fabrik.newChain(pipeStats.JointsPerTendril, pipeStats.TendrilReach / pipeStats.JointsPerTendril)
Fabrik.setStraight(tendril, 0, 0, 0, 0, 1, 0)
local targetReach = pipeStats.TendrilReach * 0.7
local pipeReached = Fabrik.solve(tendril, targetReach, 0, 0, { maxAngle = 55, planeBias = 0.5 })
check(pipeReached, "a genome-derived tendril solves to 70% of its own reach")
check(Fabrik.maxBoneError(tendril) < 1e-6, "genome-derived tendril preserves bone lengths")
-- Temperament is a hash keyed by action name, so # is meaningless on it.
local temperamentCount = 0
for _ in pairs(pipeStats.Temperament) do
	temperamentCount = temperamentCount + 1
end
check(temperamentCount >= 10, "express yields a full temperament prior for Policy (" .. temperamentCount .. " actions)")

end
do
print("=== Tables ===")
local pool = Tables.newPool(function()
	return { v = 0 }
end, 2)
check(pool:stats().created == 2, "newPool preallocates")
local pooledA = pool:get()
local pooledB = pool:get()
local pooledC = pool:get()
check(pool:stats().created == 3, "pool grows on demand when empty")
pool:release(pooledA)
local pooledD = pool:get()
check(rawequal(pooledA, pooledD), "pool reuses a released object instead of allocating")
check(pool:stats().free == 0, "pool reports no free objects once everything is borrowed")
check(Tables.count({ x = 1, y = 2, z = 3 }) == 3, "Tables.count counts hash keys")
check(#Tables.copyArray({ 1, 2, 3 }) == 3, "copyArray copies arrays")

end
do
print("=== Signal ===")
local sig = Signal.new()
local hits = 0
local conn1 = sig:connect(function(v)
	hits += v
end)
sig:fire(2)
check(hits == 2, "signal delivers its argument to a connected handler")
conn1:disconnect()
sig:fire(5)
check(hits == 2, "a disconnected handler is no longer called")
check(sig:handlerCount() == 0, "disconnect removes the handler from the list")

local sig2 = Signal.new()
local order = {}
local selfKiller = nil
selfKiller = sig2:connect(function()
	table.insert(order, "a")
	selfKiller:disconnect()
end)
sig2:connect(function()
	table.insert(order, "b")
end)
sig2:fire()
check(order[1] == "a" and order[2] == "b", "disconnecting during a fire still calls the later handler")
check(sig2:handlerCount() == 1, "deferred compaction removed the handler that died mid-fire")

local onceSig = Signal.new()
local onceCount = 0
onceSig:once(function()
	onceCount += 1
end)
onceSig:fire()
onceSig:fire()
check(onceCount == 1, "once fires exactly one time")
onceSig:disconnectAll()
check(onceSig:handlerCount() == 0, "disconnectAll empties the signal")

end
do
print("=== Noise ===")
local noiseA = Noise.new(99)
local noiseB = Noise.new(99)
local noiseDeterministic = true
for i = 1, 100 do
	local x = i * 0.137
	if noiseA:value1(x) ~= noiseB:value1(x) then
		noiseDeterministic = false
	end
	if noiseA:value3(x, x * 0.5, -x) ~= noiseB:value3(x, x * 0.5, -x) then
		noiseDeterministic = false
	end
end
check(noiseDeterministic, "Noise is deterministic for a given seed")

-- Regression guard for the collapsed-hash bug: xorshift32 used directly as a
-- lattice hash produced value1(i) in 0.0742..0.0816 for i = 0..63 - a "noise"
-- field with a dynamic range of 0.007. Sampling at integers isolates the hash
-- itself, since the interpolant is exactly 0 there.
local latticeMin, latticeMax, latticeSum = 9, -9, 0
for i = 0, 63 do
	local v = Noise.new(1234):value1(i + 0.0)
	if v < latticeMin then
		latticeMin = v
	end
	if v > latticeMax then
		latticeMax = v
	end
	latticeSum += v
end
check(latticeMax - latticeMin > 0.6, "lattice values span the range (min=" .. string.format("%.4f", latticeMin) .. " max=" .. string.format("%.4f", latticeMax) .. ")")
check(math.abs(latticeSum / 64 - 0.5) < 0.12, "lattice values average near 0.5 (got " .. string.format("%.4f", latticeSum / 64) .. ")")

local sameNoise = Noise.new(1234)
local stepSum = 0
for i = 0, 62 do
	stepSum += math.abs(sameNoise:value1(i + 0.0) - sameNoise:value1(i + 1.0))
end
-- E[|U - V|] for independent uniforms is exactly 1/3. A collapsed hash drives this
-- toward 0; a lattice that merely repeats every few cells also drives it down.
-- (Asserting "no adjacent pair is ever close" would be wrong: with 63 pairs of
-- independent samples that is expected to be violated ~92% of the time.)
local meanStep = stepSum / 63
check(meanStep > 0.2, "consecutive lattice points are decorrelated (mean |step| = " .. string.format("%.4f", meanStep) .. ", expected ~0.333)")

local noiseC = Noise.new(1234)
local valueInUnitRange = true
local noiseSum = 0
for i = 1, 2000 do
	local v = noiseC:value1(i * 0.031)
	if v < 0 or v >= 1 then
		valueInUnitRange = false
	end
	noiseSum += v
end
check(valueInUnitRange, "value1 stays inside [0,1)")
check(math.abs(noiseSum / 2000 - 0.5) < 0.08, "value1 is centred near 0.5 (got " .. string.format("%.4f", noiseSum / 2000) .. ")")

local v3InSignedRange = true
for i = 1, 500 do
	local ox, oy, oz = noiseC:v3(17, i * 0.05)
	if math.abs(ox) > 1 or math.abs(oy) > 1 or math.abs(oz) > 1 then
		v3InSignedRange = false
	end
end
check(v3InSignedRange, "v3 stays inside [-1,1] on every axis")

-- v3 must be smooth in t. Sampling a raw hash here (an easy mistake) gives a step
-- function, which on a tendril reads as a twitch instead of as drift.
local v3Continuous = true
for i = 1, 400 do
	local t = i * 0.001
	local ax = noiseC:v3(3, t)
	local bx = noiseC:v3(3, t + 0.001)
	if math.abs(ax - bx) > 0.1 then
		v3Continuous = false
	end
end
check(v3Continuous, "v3 is continuous in t (a tendril drifts, it does not step)")

local noiseContinuous = true
for i = 1, 500 do
	local x = i * 0.001
	if math.abs(noiseC:value1(x) - noiseC:value1(x + 0.001)) > 0.05 then
		noiseContinuous = false
	end
end
check(noiseContinuous, "value1 is continuous between neighbouring samples (not hash soup)")

local fbmValue = noiseC:fbm1(0.5, 4)
check(fbmValue >= 0 and fbmValue <= 1, "fbm1 is normalised into [0,1]")
check(Noise.new(1):value1(0.5) ~= Noise.new(2):value1(0.5), "different seeds give different noise")

end
do
print("=== SpatialHash ===")
local hash = SpatialHash.new(8)
hash:insert("a", 0, 0, 0, { intensity = 1 })
hash:insert("b", 5, 0, 0, { intensity = 1 })
hash:insert("c", 100, 0, 0, { intensity = 1 })
local foundIds = {}
local foundCount = hash:query(0, 0, 0, 10, function(id)
	foundIds[id] = true
end)
check(foundCount == 2, "query returns exactly the entries inside the radius (got " .. foundCount .. ")")
check(foundIds.a and foundIds.b and not foundIds.c, "query returns the correct ids and excludes the distant one")
check(hash:count() == 3, "count tracks insertions")

hash:move("c", 1, 1, 1)
local afterMove = {}
hash:query(0, 0, 0, 10, function(id)
	afterMove[id] = true
end)
check(afterMove.c == true, "move re-indexes the entry into its new cell")
local replacement = { intensity = 0.5 }
local stored = hash:insert("a", 2, 0, 0, replacement)
check(rawequal(stored, replacement), "insert returns the entry it stores")
check(rawequal(hash:get("a"), replacement), "re-inserting with a fresh entry table replaces the stored one")
check(approx(hash:get("a").x, 2, 1e-9), "the stored entry carries the new coordinates, not the stale ones")
check(hash:count() == 3, "re-inserting an existing id moves it instead of duplicating")

-- At this point a=(2,0,0) dSq=4, b=(5,0,0) dSq=25, c=(1,1,1) dSq=3. Before the
-- stale-coordinate fix this returned "a", because the re-insert had left a pinned
-- at the origin - the test was asserting the bug.
local nearestId, _, nearestSq = hash:queryNearest(0, 0, 0, 50)
check(nearestId == "c", "queryNearest returns the closest entry (got " .. tostring(nearestId) .. ")")
check(approx(nearestSq, 3, 1e-9), "queryNearest returns the squared distance")
check(hash:queryNearest(1000, 1000, 1000, 10) == nil, "queryNearest returns nil when nothing is in range")

check(hash:remove("c") == true, "remove reports success for a known id")
check(hash:remove("c") == false, "remove reports failure for an unknown id")
check(hash:count() == 2, "count tracks removals")

local decayingHash = SpatialHash.new(8)
decayingHash:insert(1, 0, 0, 0, { intensity = 1.0, time = 0, halflife = 10 })
check(approx(decayingHash:sampleDecay(0, 0, 0, 20, 0), 1.0, 1e-9), "sampleDecay returns full intensity at t=0")
check(approx(decayingHash:sampleDecay(0, 0, 0, 20, 10), 0.5, 1e-9), "sampleDecay halves after one half-life")
check(decayingHash:prune(1000, 100) == 1, "prune removes entries that have decayed past the threshold")
check(decayingHash:count() == 0, "the hash is empty after pruning its only entry")

end
do
print("=== UtilityAI ===")
local utility = UtilityAI.new()
utility:consider("CHARGE", 0.9)
utility:consider("STALK", 0.4)
local bestName, bestScore = utility:best()
check(bestName == "CHARGE", "best returns the highest-scoring option")
check(approx(bestScore, 0.9), "best returns that option's score")
utility:consider("CHARGE", 0.2)
check(approx(utility:score("CHARGE"), 0.9), "considering an option twice keeps the maximum")
check(utility:select(RNG.new(5), 0) == "CHARGE", "temperature 0 collapses select onto the argmax")

local softRng = RNG.new(7)
local softUtility = UtilityAI.new()
softUtility:consider("A", 1)
softUtility:consider("B", 0)
local softPicks = {}
for _ = 1, 2000 do
	local picked = softUtility:select(softRng, 1.0)
	softPicks[picked] = (softPicks[picked] or 0) + 1
end
check(softPicks.A and softPicks.B and softPicks.A > softPicks.B, "the softmax prefers the higher score but still explores the other option")
check(utility:selectWithBonus(RNG.new(3), 0, function(name)
	if name == "STALK" then
		return 10
	end
	return 0
end) == "STALK", "selectWithBonus folds an additive bonus into the decision")
utility:clear()
check(utility:best() == nil, "clear empties the option set")

end
do
print("=== QLearning ===")
local ACTIONS = { "A", "B", "C" }
local ql = QLearning.new({
	actions = ACTIONS,
	Alpha = 0.3,
	AlphaDecayN0 = 1e9,
	Gamma = 0,
	Lambda = 0,
	EpsilonFloor = 0,
})
local banditFeatures = { 1 }
local banditReward = { A = 1, B = 5, C = 2 }
for _ = 1, 200 do
	for _, actionName in ipairs(ACTIONS) do
		ql:learn(banditFeatures, actionName, banditReward[actionName])
	end
end
check(ql:q(banditFeatures, "B") > ql:q(banditFeatures, "A"), "Q-learning ranks the best arm above a worse one")
check(ql:q(banditFeatures, "B") > ql:q(banditFeatures, "C"), "Q-learning ranks the best arm above the third")
check(ql:greedy(banditFeatures) == "B", "greedy picks the best arm")
check(approx(ql:q(banditFeatures, "B"), 5, 0.05), "Q converges on the arm's true value (got " .. string.format("%.3f", ql:q(banditFeatures, "B")) .. ")")
check(ql:act(banditFeatures, RNG.new(11), { temperature = 0, epsilon = 0 }) == "B", "act with temperature 0 and no exploration is greedy")

-- The payoff of eligibility traces: the reward arrives ONE STEP LATE, so plain
-- Q-learning could never credit the first action.
local seq = QLearning.new({ actions = { "go", "stay" }, Alpha = 0.5, AlphaDecayN0 = 1e9, Gamma = 0.9, Lambda = 0.8, EpsilonFloor = 0 })
local firstFeatures, secondFeatures = { 1 }, { 2 }
for _ = 1, 300 do
	seq:resetTraces()
	seq:learn(firstFeatures, "go", 0, secondFeatures)
	seq:learn(secondFeatures, "go", 10, nil)
end
check(seq:q(firstFeatures, "go") > 1.0, "traces propagate credit back one step (Q=" .. string.format("%.3f", seq:q(firstFeatures, "go")) .. ")")
check(seq:q(firstFeatures, "go") > seq:q(firstFeatures, "stay"), "the branch that was never rewarded stays lower")

-- Guardrails. Both bias and the feature weight receive the clamped delta, so the
-- ceiling on |Q| is 2 * RewardClamp, not 1.
local clampedQ = QLearning.new({ actions = { "x" }, Alpha = 1.0, AlphaDecayN0 = 1e12, Gamma = 0, Lambda = 0, RewardClamp = 5, EpsilonFloor = 0 })
clampedQ:learn({ 1 }, "x", 1e9)
check(clampedQ:q({ 1 }, "x") <= 10 + 1e-9, "an absurd reward is clamped before it reaches the weights (got " .. string.format("%.1f", clampedQ:q({ 1 }, "x")) .. ")")

local cappedQ = QLearning.new({ actions = { "p", "q" }, Alpha = 0.9, AlphaDecayN0 = 1e12, Gamma = 0, Lambda = 0, RewardClamp = 1e6, WeightNormCap = 3, EpsilonFloor = 0 })
for i = 1, 400 do
	cappedQ:learn({ i }, "p", 1000)
end
check(cappedQ:weightNorm() <= 3 + 1e-6, "the weight-norm cap holds (" .. string.format("%.3f", cappedQ:weightNorm()) .. ")")

local qlRestored = QLearning.deserialize(ql:serialize())
check(qlRestored:actionCount() == #ACTIONS, "deserialize restores the action set")
check(approx(qlRestored:q(banditFeatures, "B"), ql:q(banditFeatures, "B"), 1e-12), "serialize/deserialize preserves Q values exactly")

end
do
print("=== MarkovPredictor ===")
local predictor = MarkovPredictor.new(4)
for _ = 1, 80 do
	predictor:observe(1, 2)
end
for _ = 1, 20 do
	predictor:observe(1, 3)
end
local distribution = predictor:predict(1, 3)
local distributionSum = 0
for i = 1, #distribution do
	distributionSum += distribution[i].p
end
check(approx(distributionSum, 1.0, 1e-9), "predict returns a normalised distribution (sum=" .. string.format("%.6f", distributionSum) .. ")")
check(#distribution == 2, "predict returns only the states that were actually observed")
check(distribution[1].state == 2, "predict ranks the most likely next state first")
check(approx(predictor:probability(1, 2), 0.8, 1e-9), "probability matches the observed frequency")
check(approx(predictor:predictability(1), 1 - (-(0.8 * math.log(0.8) + 0.2 * math.log(0.2)) / math.log(2)), 1e-9), "predictability equals 1 - H/Hmax")
local restoredPredictor = MarkovPredictor.deserialize(predictor:serialize())
check(approx(restoredPredictor:probability(1, 2), predictor:probability(1, 2), 1e-12), "the predictor survives serialize/deserialize")
check(#predictor:predict(9, 3) == 0, "predict on an unobserved state returns an empty list")

local deterministicPlayer = MarkovPredictor.new(4)
for _ = 1, 10 do
	deterministicPlayer:observe(1, 2)
end
check(approx(deterministicPlayer:predictability(1), 1, 1e-9), "a player who never varies scores predictability 1")

end
do
print("=== Skeleton ===")
local skel = Skeleton.new(12, { segmentLength = 2 })
check(skel.count == 12, "Skeleton.new keeps the requested joint count")
check(approx(skel:totalLength(), 22, 1e-9), "totalLength sums the bone lengths")
check(Skeleton.new(1).count == 2, "a 1-joint chain is clamped to 2 (no zero-length bone arrays)")
check(approx(skel:radiusAt(1), 0.55, 1e-9), "the taper starts at the root radius")
check(approx(skel:radiusAt(12), 0.05, 1e-6), "the taper ends at the tip radius")
check(skel:radiusAt(0) == skel:radiusAt(1) and skel:radiusAt(99) == skel:radiusAt(12), "radiusAt clamps out-of-range indices")
check(skel:setUp(0, 0, 0) == false, "setUp rejects a degenerate vector instead of storing NaN")
check(skel.upY == 1, "a rejected setUp leaves the previous value intact")

skel:straighten(10, 5, -3, 0.3, -0.7, 0.65)
check(approx(skel.x[1], 10, 1e-9) and approx(skel.y[1], 5, 1e-9) and approx(skel.z[1], -3, 1e-9), "straighten anchors joint 1 at the origin point")
local straightLengthsOk = true
for i = 1, 11 do
	local d = math.sqrt((skel.x[i + 1] - skel.x[i]) ^ 2 + (skel.y[i + 1] - skel.y[i]) ^ 2 + (skel.z[i + 1] - skel.z[i]) ^ 2)
	if math.abs(d - 2) > 1e-9 then
		straightLengthsOk = false
	end
end
check(straightLengthsOk, "straighten preserves every bone length exactly")
check(approx(skel:jointDistance(12, 10, 5, -3), 22, 1e-9), "a straightened chain is fully extended")

local clone = Skeleton.new(12)
clone:copyFrom(skel)
local copyOk = true
for i = 1, 12 do
	if clone.x[i] ~= skel.x[i] or clone.radius[i] ~= skel.radius[i] then
		copyOk = false
	end
end
check(copyOk, "copyFrom duplicates joints and taper")

-- The claim in Skeleton's header: Fabrik operates on a Skeleton with no adapter.
local rig = Skeleton.new(6, { segmentLength = 2 })
rig:straighten(0, 0, 0, 0, 0, 1)
local reached = Fabrik.solve(rig, 4, 3, 0)
check(reached == true, "Lib/Fabrik solves a Skeleton directly (no adapter)")
check(Fabrik.endEffectorError(rig, 4, 3, 0) < 0.02, "the solved Skeleton's tip is on target (err=" .. string.format("%.5f", Fabrik.endEffectorError(rig, 4, 3, 0)) .. ")")
check(Fabrik.maxBoneError(rig) < 1e-6, "solving a Skeleton preserves its bone lengths")

end
do
print("=== SkeletonCodec ===")
local pose = Skeleton.new(12, { segmentLength = 2 })
pose:straighten(10, 5, -3, 0.3, -0.7, 0.65)
local coreX, coreY, coreZ = 10, 5, -3

local bytes = {}
local byteCount, reconX, reconY, reconZ = SkeletonCodec.encode(bytes, { pose }, coreX, coreY, coreZ, coreX, coreY, coreZ, 42, 7)
check(byteCount == SkeletonCodec.byteCount(1, 12), "encode writes exactly the documented byte count (" .. byteCount .. " B for 12 joints)")
check(#bytes == byteCount, "the byte array is exactly as long as encode reports")
check(reconX == coreX and reconY == coreY and reconZ == coreZ, "a zero core delta reconstructs the core exactly")
check(SkeletonCodec.creatureId(bytes) == 7, "the creature id survives the round trip")

local decoded = Skeleton.new(12)
local decX, decY, decZ, decSeq = SkeletonCodec.decode(bytes, { decoded }, coreX, coreY, coreZ)
check(decSeq == 42, "the sequence number survives the round trip")
local worstJointError = 0
for i = 1, 12 do
	local e = math.sqrt((decoded.x[i] - pose.x[i]) ^ 2 + (decoded.y[i] - pose.y[i]) ^ 2 + (decoded.z[i] - pose.z[i]) ^ 2)
	if e > worstJointError then
		worstJointError = e
	end
end
-- The whole point of core-relative quantisation: this bound does NOT grow with
-- joint index. Parent-relative offsets would give joint 12 an error of ~0.06.
check(worstJointError <= SkeletonCodec.MAX_JOINT_ERROR + 1e-9, "joint error stays inside the budget (worst=" .. string.format("%.5f", worstJointError) .. " <= " .. string.format("%.5f", SkeletonCodec.MAX_JOINT_ERROR) .. ")")

-- Quantify the design decision rather than assert it rhetorically: replay the
-- SAME pose through the naive parent-relative scheme - each joint encoded as an
-- offset from its TRUE parent and decoded by accumulating those offsets - and
-- compare. Rounding error then feeds forward down the chain.
--
-- (Note what this does NOT claim: a parent-relative encoder that quantises
-- against the previously DECODED joint, i.e. DPCM with feedback, would also stay
-- bounded. It would just have to mirror the decoder's whole chain state on the
-- server to do so. Core-relative gets the same bound with one anchor.)
local step = SkeletonCodec.JOINT_STEP
local accX, accY, accZ = pose.x[1], pose.y[1], pose.z[1]
local worstParentRelative = 0
for i = 2, 12 do
	local qx = math.floor((pose.x[i] - pose.x[i - 1]) / step + 0.5) * step
	local qy = math.floor((pose.y[i] - pose.y[i - 1]) / step + 0.5) * step
	local qz = math.floor((pose.z[i] - pose.z[i - 1]) / step + 0.5) * step
	accX, accY, accZ = accX + qx, accY + qy, accZ + qz
	local e = math.sqrt((accX - pose.x[i]) ^ 2 + (accY - pose.y[i]) ^ 2 + (accZ - pose.z[i]) ^ 2)
	if e > worstParentRelative then
		worstParentRelative = e
	end
end
check(worstParentRelative > SkeletonCodec.MAX_JOINT_ERROR, "the naive parent-relative scheme exceeds the budget (worst=" .. string.format("%.5f", worstParentRelative) .. " vs budget " .. string.format("%.5f", SkeletonCodec.MAX_JOINT_ERROR) .. ")")
check(worstJointError < worstParentRelative, "core-relative quantisation is strictly better on the same pose (" .. string.format("%.5f", worstJointError) .. " < " .. string.format("%.5f", worstParentRelative) .. ")")

-- DPCM feedback: the encoder must be fed the RECONSTRUCTED core, or rounding
-- error random-walks the client's creature away from the server's.
local tinySkel = Skeleton.new(2, { segmentLength = 1 })
local feedbackBuffer = {}
local rx, ry, rz = 0, 0, 0
local tx, ty, tz = 0, 0, 0
local worstCoreError = 0
for step = 1, 1000 do
	tx += 0.137
	ty -= 0.091
	tz += 0.033
	local _, nx, ny, nz = SkeletonCodec.encode(feedbackBuffer, { tinySkel }, tx, ty, tz, rx, ry, rz, step, 1)
	rx, ry, rz = nx, ny, nz
	local err = math.sqrt((rx - tx) ^ 2 + (ry - ty) ^ 2 + (rz - tz) ^ 2)
	if err > worstCoreError then
		worstCoreError = err
	end
end
check(math.abs(tx) > 100, "the simulated creature really did travel a long way (" .. string.format("%.1f", tx) .. " studs)")
check(worstCoreError <= SkeletonCodec.MAX_CORE_ERROR + 1e-9, "core error stays bounded over 1000 snapshots (worst=" .. string.format("%.5f", worstCoreError) .. ")")

-- Out-of-range and non-finite inputs must clamp, never corrupt the stream.
local nan = 0 / 0
local wildSkel = Skeleton.new(3, { segmentLength = 1 })
wildSkel:setJoint(1, 0, 0, 0)
wildSkel:setJoint(2, 5000, 0, 0)
wildSkel:setJoint(3, nan, nan, nan)
local wildBytes = {}
SkeletonCodec.encode(wildBytes, { wildSkel }, 0, 0, 0, 0, 0, 0, 1, 1)
local wildDecoded = Skeleton.new(3)
SkeletonCodec.decode(wildBytes, { wildDecoded }, 0, 0, 0)
check(wildDecoded.x[2] < 400 and wildDecoded.x[2] > 300, "an out-of-range joint clamps to the int16 limit instead of wrapping (got " .. string.format("%.2f", wildDecoded.x[2]) .. ")")
check(wildDecoded.x[3] == wildDecoded.x[3], "a NaN joint encodes to a finite value instead of poisoning the stream")

end
do
print("=== NoiseField ===")
local field = NoiseField.new()
check(#NoiseField.CHANNELS == 6, "six sensory channels")
check(field:hasChannel("VIBRATION") and field:hasChannel("SCENT") and field:hasChannel("PRESSURE"), "every documented channel exists")
check(field:hasChannel("SIGHT") == false, "there is no sight channel (the creature is eyeless)")

local footstepId = field:emit("VIBRATION", 0, 0, 0, 1.0, 0)
check(footstepId ~= nil, "emit returns an impulse id")
check(field:sample("VIBRATION", 0, 0, 0, 20, 0) == 1.0, "a fresh impulse samples at full intensity")
check(field:sample("SCENT", 0, 0, 0, 20, 0) == 0, "an impulse is not heard on a different channel")
check(approx(field:sample("VIBRATION", 0, 0, 0, 20, 0.9), 0.5, 1e-9), "an impulse halves after one channel half-life")
check(field:sample("VIBRATION", 50, 0, 0, 1, 0) == 0, "an impulse outside the sample radius is not heard")
check(field:emit("VIBRATION", 0, 0, 0, -5, 0) == nil, "a non-positive intensity is not emitted")
check(field:emit("SIGHT", 0, 0, 0, 1, 0) == nil, "emitting on an unknown channel is a no-op")
check(field:sample("SIGHT", 0, 0, 0, 20, 0) == 0, "sampling an unknown channel returns 0")

local allChannels = field:sampleAll(0, 0, 0, 20, 0.9)
check(allChannels.VIBRATION ~= nil and allChannels.SCENT ~= nil and allChannels.PRESSURE ~= nil and allChannels.EM ~= nil, "sampleAll reports every channel")
check(allChannels.SCENT == 0, "sampleAll reports silence on channels with no impulses")
check(field:sampleAll(0, 0, 0, 20, 0.9) == allChannels, "sampleAll reuses one output table (no allocation per sweep)")

local bloodId = field:emit("SCENT", 5, 0, 0, 4.0, 0)
local loudest = field:loudestChannel(0, 0, 0, 20, 0)
check(loudest == "SCENT", "loudestChannel picks the strongest channel (a blood trail beats a decaying footstep)")
check(field:remove("SCENT", bloodId) == true, "remove drops an emitter immediately")
check(field:sample("SCENT", 5, 0, 0, 20, 0) == 0, "a removed emitter is silent at once")
check(field:remove("SCENT", bloodId) == false, "removing an unknown impulse reports failure")

-- Prune cut-offs are derived from each channel's half-life, so one rule serves all.
local pruneField = NoiseField.new()
pruneField:emit("PRESSURE", 0, 0, 0, 1, 0) -- half-life 0.25 s -> swept after ~1.9 s
pruneField:emit("SCENT", 0, 0, 0, 1, 0) -- half-life 26 s   -> survives ~199 s
check(pruneField:count() == 2, "count sums every channel")
check(pruneField:count("SCENT") == 1, "count accepts a single channel")
local pruned = pruneField:prune(10)
check(pruned == 1, "prune drops the impulse that has decayed away and keeps the lingering one")
check(pruneField:count() == 1, "count reflects the prune")
check(pruneField:sample("SCENT", 0, 0, 0, 20, 10) > 0, "a scent trail survives a prune that cleared a pressure pulse")

local poolCreatedBefore = pruneField.pools.PRESSURE:stats().created
pruneField:emit("PRESSURE", 0, 0, 0, 1, 20)
check(pruneField.pools.PRESSURE:stats().created == poolCreatedBefore, "pruned entries return to the pool, so impulses do not allocate")

pruneField:clear()
check(pruneField:count() == 0, "clear empties every channel")

end
return TESTS
