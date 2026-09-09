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
local GameConfig = VitriolRequire("GameConfig")
local DayNightConfig = VitriolRequire("DayNightConfig")
local MonsterConfig = VitriolRequire("MonsterConfig")
local Remotes = VitriolRequire("Remotes")
local NetContract = VitriolRequire("NetContract")
local Replicator = VitriolRequire("Replicator")
local KillChoreography = VitriolRequire("KillChoreography")
local TimeModel = VitriolRequire("TimeModel")

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
do
print("=== Skeleton: rest pose and reset() (WP3) ===")

local restSkel = Skeleton.new(6, {
	segmentLength = 2,
	restOrigin = { X = 4, Y = 1, Z = -2 },
	restDirection = { X = 0, Y = -1, Z = 0 },
})
check(approx(restSkel.x[1], 4, 1e-9) and approx(restSkel.y[1], 1, 1e-9), "restOrigin anchors the constructed pose")
check(approx(restSkel.y[6], -9, 1e-9), "restDirection lays a hanging tendril straight down from its root")
check(approx(restSkel.z[6], -2, 1e-9), "the hanging pose stays in its own plane")
Fabrik.solve(restSkel, 0, 0, 0)
local knotted = restSkel.z[6] ~= -2
restSkel:reset()
check(knotted, "a solve really did move the chain (otherwise this test proves nothing)")
check(approx(restSkel.x[1], 4, 1e-9) and approx(restSkel.y[6], -9, 1e-9), "reset returns the chain to its rest pose")
check(restSkel:isDirty() == true, "reset marks the pose dirty so the renderer picks it up")
check(Fabrik.maxBoneError(restSkel) < 1e-9, "reset keeps every bone length exact")
local restClone = Skeleton.new(2)
restClone:copyFrom(restSkel)
local clonedRestX = restClone:restPose()
check(approx(clonedRestX, 4, 1e-9), "copyFrom carries the rest pose, so a pooled chain resets to the right shoulder")

local defaultSkel = Skeleton.new(5)
check(defaultSkel.z[5] == 8 and defaultSkel.x[1] == 0, "a default Skeleton is built STRAIGHT, not collapsed to a knot")
check(approx(defaultSkel:totalLength(), 8, 1e-9), "the straight construction agrees with totalLength")

end
do
print("=== SkeletonCodec: 200 random chains (docs/03 §7.1 round trip) ===")
-- WP3 asks for max positional error < 0.02 studs over 200 RANDOM chains. One hand
-- -picked pose is how the collapsed-noise bug in iteration 2 nearly shipped: a
-- single input passes for the wrong reason every time.

local rng = RNG.new(20260908)
local WIRE_BUDGET = 0.02
local encBytes = {}
local cmpBytes = {}
local worstJoint = 0
local worstTip = 0
local worstCore = 0
local worstAngle = 0
local worstParentRelative = 0
local sizeMismatch = 0
local nonIdempotent = 0
local worstQuatDrift = 0
local seqMismatch = 0
local idMismatch = 0
local jointsSeen = 0
local refX, refY, refZ = 0, 0, 0

for chain = 1, 200 do
	local tendrils = rng:int(1, 8)
	local jointsPer = rng:int(2, 16)
	local seg = rng:range(1.2, 3.5)
	local coreX = rng:range(-240, 240)
	local coreY = rng:range(-20, 160)
	local coreZ = rng:range(-240, 240)

	local skels = {}
	local decoded = {}
	local jointsTotal = 0
	for t = 1, tendrils do
		local skel = Skeleton.new(jointsPer, { segmentLength = seg })
		-- A random walk that preserves every bone length: the distribution a solved
		-- tendril actually has, so the offsets the codec quantises are realistic.
		skel:setJoint(1, coreX + rng:range(-6, 6), coreY + rng:range(-6, 6), coreZ + rng:range(-6, 6))
		for i = 2, jointsPer do
			local dx = rng:range(-1, 1)
			local dy = rng:range(-1, 1)
			local dz = rng:range(-1, 1)
			local m = math.sqrt(dx * dx + dy * dy + dz * dz)
			if m < 1e-6 then
				dx = 1
				dy = 0
				dz = 0
				m = 1
			end
			local bone = skel.len[i - 1]
			skel:setJoint(i, skel.x[i - 1] + dx / m * bone, skel.y[i - 1] + dy / m * bone, skel.z[i - 1] + dz / m * bone)
		end
		skels[t] = skel
		decoded[t] = Skeleton.new(jointsPer, { segmentLength = seg })
		jointsTotal = jointsTotal + jointsPer
	end

	-- Random unit orientation for the core.
	local qx = rng:range(-1, 1)
	local qy = rng:range(-1, 1)
	local qz = rng:range(-1, 1)
	local qw = rng:range(-1, 1)
	local qm = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if qm < 1e-6 then
		qx, qy, qz, qw = 0, 0, 0, 1
	else
		qx = qx / qm
		qy = qy / qm
		qz = qz / qm
		qw = qw / qm
	end

	local prevRefX, prevRefY, prevRefZ = refX, refY, refZ
	local count, reconX, reconY, reconZ = SkeletonCodec.encode(
		encBytes, skels, coreX, coreY, coreZ, refX, refY, refZ, chain, chain % 251, qx, qy, qz, qw
	)
	if count ~= SkeletonCodec.byteCount(tendrils, jointsPer) then
		sizeMismatch = sizeMismatch + 1
	end

	local dX, dY, dZ, dSeq, dQX, dQY, dQZ, dQW = SkeletonCodec.decode(encBytes, decoded, refX, refY, refZ)
	if dSeq ~= (chain % 65536) then
		seqMismatch = seqMismatch + 1
	end
	if SkeletonCodec.creatureId(encBytes) ~= chain % 251 then
		idMismatch = idMismatch + 1
	end

	-- Core: bounded, never accumulating, even though the reference here is the
	-- PREVIOUS chain's reconstruction rather than a fresh anchor.
	local coreErr = math.sqrt((dX - coreX) ^ 2 + (dY - coreY) ^ 2 + (dZ - coreZ) ^ 2)
	if coreErr > worstCore then
		worstCore = coreErr
	end
	refX = reconX
	refY = reconY
	refZ = reconZ

	for t = 1, tendrils do
		local skel = skels[t]
		local dec = decoded[t]
		for i = 1, jointsPer do
			local e = math.sqrt((dec.x[i] - skel.x[i]) ^ 2 + (dec.y[i] - skel.y[i]) ^ 2 + (dec.z[i] - skel.z[i]) ^ 2)
			if e > worstJoint then
				worstJoint = e
			end
			if i == jointsPer then
				-- The tip is where a parent-relative scheme loses the most, so it is
				-- tracked on its own: this is the number the doc quotes.
				if e > worstTip then
					worstTip = e
				end
			end
			jointsSeen = jointsSeen + 1
		end
		-- Same sweep through the naive scheme (quantise against the TRUE parent,
		-- decode by accumulation) to show the budget would have been blown.
		local accX = skel.x[1]
		local accY = skel.y[1]
		local accZ = skel.z[1]
		local step = SkeletonCodec.JOINT_STEP
		for i = 2, jointsPer do
			accX = accX + math.floor((skel.x[i] - skel.x[i - 1]) / step + 0.5) * step
			accY = accY + math.floor((skel.y[i] - skel.y[i - 1]) / step + 0.5) * step
			accZ = accZ + math.floor((skel.z[i] - skel.z[i - 1]) / step + 0.5) * step
			local e = math.sqrt((accX - skel.x[i]) ^ 2 + (accY - skel.y[i]) ^ 2 + (accZ - skel.z[i]) ^ 2)
			if e > worstParentRelative then
				worstParentRelative = e
			end
		end
	end

	-- Orientation: geodesic angle between the true and decoded unit quaternions.
	local dot = math.abs(dQX * qx + dQY * qy + dQZ * qz + dQW * qw)
	if dot > 1 then
		dot = 1
	end
	local angle = 2 * math.acos(dot)
	if angle > worstAngle then
		worstAngle = angle
	end

	-- Idempotence: encoding the DECODED pose against the same reference must
	-- reproduce the same bytes, or the client's next frame would disagree with the
	-- server about what the server just sent.
	-- Idempotence, and the precise scope of it: POSITIONS must reproduce byte for
	-- byte, because the core is a DPCM channel (a one-unit difference there would
	-- walk). The quaternion is absolute - the server encodes its own true
	-- orientation every snapshot and never feeds a reconstruction back - so a 1 LSB
	-- difference when re-quantising a decoded, renormalised quaternion is harmless.
	-- It is bounded below instead, which is the property that actually matters.
	local reCount = SkeletonCodec.encode(cmpBytes, decoded, dX, dY, dZ, prevRefX, prevRefY, prevRefZ, chain, chain % 251, dQX, dQY, dQZ, dQW)
	if reCount ~= count then
		nonIdempotent = nonIdempotent + 1
	else
		for b = 1, count do
			local isQuatByte = b >= 10 and b <= SkeletonCodec.HEADER_BYTES
			if not isQuatByte and cmpBytes[b] ~= encBytes[b] then
				nonIdempotent = nonIdempotent + 1
				break
			end
		end
	end
	local quatDrift = 0
	for b = 10, SkeletonCodec.HEADER_BYTES do
		local d = cmpBytes[b] - encBytes[b]
		if d < 0 then
			d = -d
		end
		if d > quatDrift then
			quatDrift = d
		end
	end
	if quatDrift > worstQuatDrift then
		worstQuatDrift = quatDrift
	end
end

check(sizeMismatch == 0, "byteCount agrees with encode for every chain size (2..16 joints x 1..8 tendrils)")
check(jointsSeen > 6000, "the sweep really did cover thousands of joints (" .. jointsSeen .. " joints)")
check(worstJoint < WIRE_BUDGET, "max positional error over 200 random chains is inside the 0.02 stud wire budget (worst=" .. string.format("%.5f", worstJoint) .. ")")
check(worstJoint <= SkeletonCodec.MAX_JOINT_ERROR + 1e-12, "and inside the analytic per-joint bound (worst=" .. string.format("%.5f", worstJoint) .. " <= " .. string.format("%.5f", SkeletonCodec.MAX_JOINT_ERROR) .. ")")
check(worstTip <= SkeletonCodec.MAX_JOINT_ERROR + 1e-12, "the TIP of a 16-joint chain is no worse than its root (worst=" .. string.format("%.5f", worstTip) .. ")")
check(worstParentRelative > WIRE_BUDGET, "the naive parent-relative scheme blows the budget on these chains (worst=" .. string.format("%.5f", worstParentRelative) .. ")")
check(worstCore <= SkeletonCodec.MAX_CORE_ERROR + 1e-12, "core delta stays inside its own bound across 200 chained snapshots (worst=" .. string.format("%.5f", worstCore) .. ")")
check(worstAngle <= SkeletonCodec.MAX_ANGLE_ERROR + 1e-12, "core orientation error is inside the int8 quaternion bound (worst=" .. string.format("%.5f", math.deg(worstAngle)) .. " deg <= " .. string.format("%.5f", math.deg(SkeletonCodec.MAX_ANGLE_ERROR)) .. ")")
check(nonIdempotent == 0, "positions re-encode byte for byte from the decoded pose (no DPCM drift, client and server agree)")
check(worstQuatDrift <= 1, "re-quantising a decoded quaternion moves it at most one LSB, and it is absolute so even that cannot accumulate (" .. worstQuatDrift .. " LSB)")
check(seqMismatch == 0, "every sequence number survives 200 snapshots")
check(idMismatch == 0, "every creature id survives 200 snapshots")
check(SkeletonCodec.coreDisplacement(8) < 0.15, "the orientation cost on an 8-stud core is under 0.15 studs (" .. string.format("%.4f", SkeletonCodec.coreDisplacement(8)) .. ")")

-- The header, as data, so the doc and the codec cannot drift apart silently.
check(SkeletonCodec.HEADER_BYTES == 1 + 2 + 6 + 4, "the header is creatureId+seq+core delta+quat (13 B)")
check(SkeletonCodec.byteCount(8, 12) == 589, "a Braid snapshot is 589 B, the number docs/03 §7.1 quotes")

-- A caller with no orientation yet must still produce a decodable frame.
local noQuat = {}
local skel1 = Skeleton.new(3, { segmentLength = 1 })
skel1:straighten(0, 0, 0, 1, 0, 0)
SkeletonCodec.encode(noQuat, { skel1 }, 0, 0, 0, 0, 0, 0, 1, 1)
local dec1 = Skeleton.new(3)
local _, _, _, _, nqX, nqY, nqZ, nqW = SkeletonCodec.decode(noQuat, { dec1 }, 0, 0, 0)
check(nqW == 1 and nqX == 0 and nqY == 0 and nqZ == 0, "a missing quaternion decodes as identity, not as garbage")

end
do
print("=== NoiseField: wind advection, weather masking, surface coupling (docs/02 §2) ===")
local Monster = MonsterConfig.Senses

local advected = NoiseField.new({
	Halflife = { SCENT = 1000, VIBRATION = 1000 },
	Coupling = Monster.VibrationCoupling,
	AdvectedMaxAge = Monster.AdvectionMaxAgeSeconds,
})
check(advected:advectionWindow("SCENT") == Monster.AdvectionMaxAgeSeconds, "advection is searched over a bounded age window, not the whole half-life")
check(advected:advectionWindow("VIBRATION") == 0, "and only for advected channels")
-- 1 stud/s along +X. A scent emitted at the origin is 5 studs downwind after 5 s.
advected:setWind(1, 0, 0)
local wx, wy, wz = advected:wind()
check(wx == 1 and wy == 0 and wz == 0, "setWind stores the vector for the debug overlay")
advected:emit("SCENT", 0, 0, 0, 1, 0)
advected:emit("VIBRATION", 0, 0, 0, 1, 0)
check(advected:sample("SCENT", 5, 0, 0, 1, 5) > 0.9, "scent has drifted downwind: 5 studs away, 5 s later, it is heard where the plume actually is")
check(advected:sample("SCENT", 0, 0, 0, 1, 5) < 0.05, "and NOT at the source, which is now upwind of the plume")
check(advected:sample("VIBRATION", 0, 0, 0, 1, 5) > 0.9, "vibration is ground-borne: the wind does not move it")
check(advected:sample("VIBRATION", 5, 0, 0, 1, 5) < 0.05, "so nothing appears at the drifted position on a non-advected channel")

-- A scent older than the window is not modelled here (it belongs to memory).
advected:emit("SCENT", 200, 0, 0, 1, 1000)
check(advected:sample("SCENT", 2020, 0, 0, 1, 1010) == 0, "an impulse older than the advection window is skipped, not clamped to the window edge")

-- Exact parity with the plain decay path when there is no wind: advection must not
-- change a single number, or the Attune UI and the creature would disagree.
local calm = NoiseField.new({ Halflife = { SCENT = 1000, VIBRATION = 1000 } })
calm:emit("SCENT", 3, 1, -2, 0.75, 0)
local calmHash = calm.hashes.SCENT
local plainValue = calmHash:sampleDecay(3, 1, -2, 8, 4)
check(approx(calm:sample("SCENT", 3, 1, -2, 8, 4), plainValue, 1e-12), "with zero wind an advected sample equals SpatialHash:sampleDecay exactly")
calm:setWind(0, 0, 0)
check(approx(calm:sample("SCENT", 3, 1, -2, 8, 4), plainValue, 1e-12), "setWind(0,0,0) restores that parity (no sqrt of zero, no drift term)")

-- A second consumer of the same field sees the same plume: this is the Attune rule.
local observer = NoiseField.new({ Halflife = { SCENT = 1000, VIBRATION = 1000 }, AdvectedMaxAge = Monster.AdvectionMaxAgeSeconds })
observer:setWind(1, 0, 0)
observer:emit("SCENT", 0, 0, 0, 1, 0)
check(approx(observer:sample("SCENT", 5, 0, 0, 1, 5), advected:sample("SCENT", 5, 0, 0, 1, 5), 1e-12), "two fields with the same wind and impulse agree to the last bit")

-- Weather: rain halves vibration propagation (docs/00 §5.1.3).
local wet = NoiseField.new()
wet:emit("VIBRATION", 0, 0, 0, 1, 0)
wet:emit("AIR", 0, 0, 0, 1, 0)
wet:emit("SCENT", 0, 0, 0, 1, 0)
local dryVibration = wet:sample("VIBRATION", 0, 0, 0, 20, 0)
wet:setWeather(DayNightConfig.Weather.Rain)
check(approx(wet:sample("VIBRATION", 0, 0, 0, 20, 0), dryVibration * DayNightConfig.Weather.Rain.VibrationMask, 1e-12), "rain masks VIBRATION by the config multiplier")
check(approx(wet:sample("AIR", 0, 0, 0, 20, 0), DayNightConfig.Weather.Rain.AirMask, 1e-12), "rain masks AIR by its own multiplier (rain noise drowns voices, not the reverse)")
check(wet:sample("SCENT", 0, 0, 0, 20, 0) == 1, "a channel with no mask key is untouched by weather")
check(wet:channelMask("SCENT") == 1, "channelMask reports the neutral gain for an unmasked channel")
local storm = NoiseField.new()
storm:emit("VIBRATION", 0, 0, 0, 1, 0)
storm:setWeather(DayNightConfig.Weather.Storm)
check(storm:sample("VIBRATION", 0, 0, 0, 20, 0) < wet:sample("VIBRATION", 0, 0, 0, 20, 0), "a storm hides you better than rain does")
storm:setWeather(nil)
check(storm:sample("VIBRATION", 0, 0, 0, 20, 0) == 1, "setWeather(nil) clears the mask")
check(storm:setChannelMask("NOPE", 0.5) == false, "an unknown channel cannot be masked")

-- Surface coupling (docs/02 §2: hard surfaces amplify, water decouples).
local coupled = NoiseField.new({ Coupling = Monster.VibrationCoupling })
coupled:emitAt("VIBRATION", 0, 0, 0, 1, 0, nil, "Concrete")
coupled:emitAt("VIBRATION", 40, 0, 0, 1, 0, nil, "Water")
coupled:emitAt("VIBRATION", -40, 0, 0, 1, 0, nil, "Unobtainium")
check(approx(coupled:sample("VIBRATION", 0, 0, 0, 20, 0), Monster.VibrationCoupling.Concrete, 1e-12), "concrete couples a footstep at its config multiplier")
check(approx(coupled:sample("VIBRATION", 40, 0, 0, 20, 0), Monster.VibrationCoupling.Water, 1e-12), "water decouples it (0.1) - the reason the creek is a hiding place")
check(coupled:sample("VIBRATION", -40, 0, 0, 20, 0) == 1, "an unknown material is neutral, never silent and never amplified")
check(coupled:couple("AIR", "Concrete") == 1, "coupling applies to the coupling channel only (air sound does not care what you stepped on)")
coupled:emit("AIR", 0, 0, 0, 1, 0, { Material = "Concrete" })
check(coupled:sample("AIR", 0, 0, 0, 20, 0) == 1, "so passing a Material on AIR changes nothing")
check(coupled:emit("VIBRATION", 0, 0, 0, 1, 0, { Material = "Water", Halflife = 5 }) ~= nil, "opts also carries the per-event half-life")

-- Sampling must not mutate the field (no drift writes, no allocations).
local before = coupled:count()
local createdBefore = coupled.pools.VIBRATION:stats().created
for i = 1, 500 do
	coupled:sampleAll(0, 0, 0, 30, i * 0.01)
end
check(coupled:count() == before, "500 sweeps changed nothing in the index")
check(coupled.pools.VIBRATION:stats().created == createdBefore, "500 sweeps allocated no entries")
local allOut = coupled:sampleAll(0, 0, 0, 20, 0)
check(allOut.VIBRATION == coupled:sample("VIBRATION", 0, 0, 0, 20, 0), "sampleAll and sample agree on the same channel")
check(coupled:loudestChannel(0, 0, 0, 20, 0) == "VIBRATION", "the loudest-channel probe respects coupling")

end
do
print("=== Remotes: the contract is the set in docs/01 §2 ===")

local names = Remotes.names()
check(#names == 7, "exactly seven remotes exist (" .. #names .. ")")
local wanted = {
	RE_TimeSync = "RemoteEvent",
	RE_SkeletonStream = "RemoteEvent",
	RE_CreatureEvent = "RemoteEvent",
	RE_SurvivalSync = "RemoteEvent",
	RE_ClientIntent = "RemoteEvent",
	RE_Destruction = "RemoteEvent",
	RF_DebugQuery = "RemoteFunction",
}
local allWanted = true
for i = 1, #names do
	if wanted[names[i]] == nil then
		allWanted = false
	end
end
check(allWanted, "every declared remote is one from the architecture tree (no ad hoc remotes)")
local missingFromDoc = 0
for name in pairs(wanted) do
	local found = false
	for i = 1, #names do
		if names[i] == name then
			found = true
		end
	end
	if not found then
		missingFromDoc = missingFromDoc + 1
	end
end
check(missingFromDoc == 0, "and every remote in the tree is declared here")
local classesOk = true
for name, class in pairs(wanted) do
	local def = Remotes.definition(name)
	if def == nil or def.Class ~= class then
		classesOk = false
	end
end
check(classesOk, "each one has the class the tree says (RF_ is a RemoteFunction)")
check(Remotes.FolderName == "Comms", "the folder name comes from GameConfig.Net.CommsFolder")
check(Remotes.BindTimeoutSeconds == GameConfig.Net.BindTimeoutSeconds, "the client bind timeout comes from config, not a literal")
local c2s = Remotes.clientToServer()
check(#c2s == 2, "two remotes carry client->server traffic (RE_ClientIntent, RF_DebugQuery)")
check(Remotes.coverageProblems(NetContract.Schemas)[1] == nil, "the contract is covered: every client->server remote has a schema that exists")

end
do
print("=== NetContract: the server never trusts a client ===")
local gate = NetContract.newGate()
local now = 100
local function okFor(payload, t)
	return NetContract.admit(gate, t or "player:1", "ClientIntent", payload, now)
end

local good = { Action = "OpenDoor", TargetId = 17, Sequence = 1, Position = { X = 4, Y = 0, Z = -2 }, HeldSeconds = 0.8 }
local accepted, code = okFor(good)
check(accepted == true, "a well-formed intent is accepted (" .. tostring(code) .. ")")
check(NetContract.Actions.OpenDoor == true, "the intent enum is derived from GameConfig.Intents")
check(#NetContract.ActionNames >= 12, "and covers the whole interaction table (" .. #NetContract.ActionNames .. " actions)")

check(okFor({ Action = "OpenDoor", TargetId = 17 }) == false, "a missing required field is rejected")
local ok1, code1, field1 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 17, Sequence = 1, Loot = "everything" })
check(ok1 == false and code1 == NetContract.Reject.UnknownField, "an unknown field is rejected outright (" .. tostring(code1) .. " on " .. tostring(field1) .. ")")
check(NetContract.validate("ClientIntent", nil) == false, "a nil payload is rejected")
check(NetContract.validate("ClientIntent", "OpenDoor") == false, "a bare string is rejected")
check(NetContract.validate("ClientIntent", 42) == false, "a number is rejected")
check(NetContract.validate("Nada", {}) == false, "an unknown schema is rejected rather than passed through")
local ok2, code2 = NetContract.validate("ClientIntent", { Action = "GiveMeAllTheLoot", TargetId = 1, Sequence = 1 })
check(ok2 == false and code2 == NetContract.Reject.NotAllowed, "an action outside the vocabulary is refused")
local ok3, code3 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 1.5, Sequence = 1 })
check(ok3 == false and code3 == NetContract.Reject.BadType, "a fractional 'integer' id is refused")
local ok4, code4 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = -1, Sequence = 1 })
check(ok4 == false and code4 == NetContract.Reject.OutOfRange, "a negative id is refused")
local ok5, code5 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 1, Sequence = 1, Position = { X = 0 / 0, Y = 0, Z = 0 } })
check(ok5 == false and code5 == NetContract.Reject.NotFinite, "a NaN position is refused")
local ok6, code6 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 1, Sequence = 1, Position = { X = math.huge, Y = 0, Z = 0 } })
check(ok6 == false and code6 == NetContract.Reject.NotFinite, "an infinite position is refused")
local ok7, code7 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 1, Sequence = 1, Position = { X = 1e9, Y = 0, Z = 0 } })
check(ok7 == false and code7 == NetContract.Reject.OutOfRange, "a position outside the world bound is refused")
local ok8, code8 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 1, Sequence = 1, HeldSeconds = 100000 })
check(ok8 == false and code8 == NetContract.Reject.OutOfRange, "a 27-hour 'hold' is refused (MaxHeldSeconds = " .. GameConfig.Net.MaxHeldSeconds .. ")")
local ok9 = NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 1, Sequence = 1, TargetId2 = "x" })
check(ok9 == false, "a near-miss field name is refused, not coerced")
local longString = "a"
while #longString < GameConfig.Net.MaxStringBytes + 1 do
	longString = longString .. "a"
end
check(NetContract.validate("ClientIntent", { Action = longString, TargetId = 1, Sequence = 1 }) == false, "an oversized string is refused before it is compared to the enum")
check(NetContract.validate("ClientIntent", { Action = "OpenDoor", TargetId = 1, Sequence = 0 }) == true, "Sequence 0 is legal (the first packet)")

-- Rate limiting: a burst then refusal, then refill. Two players are independent.
local spamGate = NetContract.newGate()
local limits = NetContract.limits("ClientIntent")
local burst = limits.Burst
local spammed = 0
local t = 0
for i = 1, burst + 40 do
	if NetContract.allow(spamGate, "bot", "ClientIntent", t) then
		spammed = spammed + 1
	end
end
check(spammed == burst, "exactly the configured burst is admitted in one instant (" .. burst .. ")")
check(NetContract.allow(spamGate, "bot", "ClientIntent", t) == false, "the next message in that instant is refused")
local afterRefill = 0
for i = 1, 100 do
	t = t + 1 / 60
	if NetContract.allow(spamGate, "bot", "ClientIntent", t) then
		afterRefill = afterRefill + 1
	end
end
local window = 100 / 60
local expected = window * limits.SustainedPerSecond
check(afterRefill >= math.floor(expected) - 1 and afterRefill <= math.ceil(expected) + 1, "the bucket refills at SustainedPerSecond (" .. afterRefill .. " admitted over " .. string.format("%.2f", window) .. " s, expected " .. string.format("%.1f", expected) .. ")")
check(NetContract.allow(spamGate, "someoneElse", "ClientIntent", t) == true, "a neighbour player is unaffected by the bot's flood")
check(NetContract.limits("Nope") == nil, "an undocumented message kind gets NO default limit (closed by default)")
check(NetContract.allow(spamGate, "bot", "Nope", t) == false, "and refuses that kind outright")

-- Replay protection.
local seqGate = NetContract.newGate()
local first = NetContract.admit(seqGate, "p1", "ClientIntent", { Action = "KickDoor", TargetId = 3, Sequence = 5 }, 0)
local replay = NetContract.admit(seqGate, "p1", "ClientIntent", { Action = "KickDoor", TargetId = 3, Sequence = 5 }, 0.5)
local stale = NetContract.admit(seqGate, "p1", "ClientIntent", { Action = "KickDoor", TargetId = 3, Sequence = 2 }, 0.6)
local later = NetContract.admit(seqGate, "p1", "ClientIntent", { Action = "KickDoor", TargetId = 3, Sequence = 6 }, 0.7)
check(first == true and later == true, "monotonic sequences are accepted")
check(replay == false and stale == false, "a replayed or reordered packet is dropped (a door cannot be kicked twice by one click)")
NetContract.forget(seqGate, "p1")
check(NetContract.admit(seqGate, "p1", "ClientIntent", { Action = "KickDoor", TargetId = 3, Sequence = 1 }, 0.8) == true, "after forget(), a rejoining player starts clean")

-- Fuzz: nothing may get through that is not a legal intent.
local fuzzGate = NetContract.newGate()
local frng = RNG.new(4242)
local acceptedBad = 0
local rejected = 0
local fieldPool = { "Action", "TargetId", "Sequence", "Position", "HeldSeconds", "Loot", "Admin", "Payload" }
local valuePool = { 0, -1, 1.5, 42, math.huge, 0 / 0, "OpenDoor", "", "a" .. "b", true, {}, { X = 1, Y = 2, Z = 3 }, { X = 0 / 0, Y = 0, Z = 0 }, 1e30 }
for trial = 1, 400 do
	local payload = {}
	local fields = frng:int(0, 5)
	for f = 1, fields do
		payload[fieldPool[frng:int(1, #fieldPool)]] = valuePool[frng:int(1, #valuePool)]
	end
	local ok = NetContract.admit(fuzzGate, "fuzz", "ClientIntent", payload, trial * 10)
	if ok then
		local valid = NetContract.validate("ClientIntent", payload)
		if not valid or payload.Action == nil or NetContract.Actions[payload.Action] == nil then
			acceptedBad = acceptedBad + 1
		end
	else
		rejected = rejected + 1
	end
end
check(acceptedBad == 0, "400 hostile payloads: nothing was accepted that validate() would reject")
check(rejected > 350, "and nearly all of them were refused (" .. rejected .. "/400)")

-- Debug query surface.
local dbgOk = NetContract.validate("DebugQuery", { Command = "phases" })
check(dbgOk == true, "a bare debug command is valid")
check(NetContract.validate("DebugQuery", { Command = "rm -rf" }) == false, "an unlisted command is refused")
check(NetContract.validate("DebugQuery", { Command = "clock", Argument = 18.5 }) == true, "setclock 18.5 is in range")
check(NetContract.validate("DebugQuery", { Command = "clock", Argument = 1e6 }) == false, "and 1e6 is not")

end
do
print("=== Replicator: the byte array and the Buffer agree (docs/03 §7.1) ===")

local rep = Replicator.new(9, { Codec = SkeletonCodec, Config = GameConfig })
check(approx(rep.secPerSnapshot, 1 / GameConfig.Ticks.SkeletonStreamHzNear, 1e-12), "the default stream rate is the NEAR tier from config (" .. string.format("%.1f", 1 / rep.secPerSnapshot) .. " Hz)")

local skels = {}
for t = 1, 8 do
	local skel = Skeleton.new(12, { segmentLength = 2 })
	skel:straighten(0, 0, 0, math.cos(t), math.sin(t * 0.5), math.sin(t))
	skels[t] = skel
end
local count = rep:encode(skels, 30, 4, -12, 0.1, 0.2, 0.3, 0.92)
check(count == SkeletonCodec.byteCount(8, 12), "encode sized the payload from the joint counts (" .. count .. " B)")
check(count == SkeletonCodec.HEADER_BYTES + 8 * 12 * SkeletonCodec.JOINT_BYTES, "and that matches Replicator's own capacity formula")

local buf, bufCount = rep:snapshot(skels, 30, 4, -12, 0.1, 0.2, 0.3, 0.92)
check(buffer.len(buf) == bufCount, "buffer.create was given exactly the codec's byte count")
local recovered, recCount = Replicator.toBytes(buf)
check(recCount == bufCount, "toBytes reports the same length")
local parity, mismatchAt = Replicator.checkParity(rep.bytes, recovered, bufCount)
check(parity == true, "every byte survives array -> buffer -> array (first mismatch at " .. tostring(mismatchAt) .. ")")

-- Decoding the recovered array must reproduce exactly what decoding the array did.
local decA = {}
local decB = {}
for t = 1, 8 do
	decA[t] = Skeleton.new(12)
	decB[t] = Skeleton.new(12)
end
local ax, ay, az, aseq, aqx, aqy, aqz, aqw = SkeletonCodec.decode(rep.bytes, decA, 30, 4, -12)
local bx, by, bz, bseq, bqx, bqy, bqz, bqw = SkeletonCodec.decode(recovered, decB, 30, 4, -12)
check(ax == bx and ay == by and az == bz and aseq == bseq, "core + sequence decode identically through both paths")
check(aqx == bqx and aqy == bqy and aqz == bqz and aqw == bqw, "and so does the core quaternion")
local jointsEqual = true
for t = 1, 8 do
	for i = 1, 12 do
		if decA[t].x[i] ~= decB[t].x[i] or decA[t].y[i] ~= decB[t].y[i] or decA[t].z[i] ~= decB[t].z[i] then
			jointsEqual = false
		end
	end
end
check(jointsEqual, "all 96 joints decode identically through both paths")

-- The reader half on the client: a Buffer arriving from the remote unpacks to the
-- same skeleton the server packed, with the DPCM reference the client holds.
local fromWire = {}
local wireSkels = {}
for t = 1, 8 do
	wireSkels[t] = Skeleton.new(12)
end
local wireBytes, wireCount = Replicator.toBytes(buf, fromWire)
check(wireCount == bufCount, "a caller-supplied buffer array is reused, not reallocated")
SkeletonCodec.decode(wireBytes, wireSkels, 30, 4, -12)
check(SkeletonCodec.creatureId(wireBytes) == 9, "the creature id rides in byte 1 on the wire too")

-- Out-of-range offsets must error, not silently truncate: that is the property the
-- adapter relies on when it trusts the codec's count.
local failed = false
local ok = pcall(function()
	buffer.readu8(buf, bufCount)
end)
if not ok then
	failed = true
end
check(failed, "reading past the end of a Buffer errors in both implementations (the adapter's off-by-one guard)")

-- Rate limiting + a fake remote, to prove the send path fires with the right shape.
local fired = 0
local firedBytes = 0
local lastPayload
local fakeRemote = {}
fakeRemote.FireAllClients = function(self, payload)
	if self ~= fakeRemote then
		error("FireAllClients was not called with the remote as self", 2)
	end
	fired = fired + 1
	lastPayload = payload
	firedBytes = firedBytes + buffer.len(payload)
end
fakeRemote.FireClient = function(self, player, payload)
	fired = fired + 1
	lastPayload = payload
	firedBytes = firedBytes + buffer.len(player)
end
rep:setRemote(fakeRemote)
local sends = 0
local sentImmediate = rep:publish(1 / 60, nil, skels, 30, 4, -12)
if sentImmediate then
	sends = sends + 1
end
check(sentImmediate == true, "the first frame publishes immediately (a creature must not wait a period to appear)")
check(fired == 1 and lastPayload ~= nil, "and it really did fire the remote once with a Buffer")
local payloadBytes = buffer.len(lastPayload)
check(payloadBytes == SkeletonCodec.byteCount(8, 12), "the Buffer on the wire is exactly the documented payload (" .. payloadBytes .. " B)")
local rejectedFrames = 0
for i = 1, 20 do
	local sent = rep:publish(1 / 60, nil, skels, 31, 4, -12)
	if sent then
		sends = sends + 1
	else
		rejectedFrames = rejectedFrames + 1
	end
end
-- 20 frames at 60 Hz is 1/3 s; the NEAR tier is 15 Hz, so 4-5 snapshots. The point
-- of the range is that it paces at all: an unthrottled stream would say 20.
check(sends >= 4 and sends <= 6, "and then it paces itself: 21 frames produced " .. sends .. " snapshots at the " .. GameConfig.Ticks.SkeletonStreamHzNear .. " Hz tier")
check(rejectedFrames > 14, "the surplus frames were dropped rather than queued (a backlog is how a stream jitters)")
local beforeFires = fired
local sentEmpty, emptyBytes = rep:publish(1 / 15, {}, skels, 32, 4, -12)
if sentEmpty then
	sends = sends + 1
end
check(sentEmpty == true and fired == beforeFires, "an empty recipient list encodes but sends nothing (nobody in range, no bandwidth)")
check(rep:publish(0.001, nil, skels, 33, 4, -12) == false, "a frame shorter than the period is skipped")
rep:setRate(GameConfig.Ticks.SkeletonStreamHzFar)
local farStart = sends
for i = 1, 40 do
	if rep:publish(1 / 60, nil, skels, 34, 4, -12) then
		sends = sends + 1
	end
end
check(sends - farStart == 2, "setRate to the FAR tier: 40 frames produced " .. (sends - farStart) .. " snapshots (" .. GameConfig.Ticks.SkeletonStreamHzFar .. " Hz)")
local stats = rep:stats()
check(stats.snapshots == sends, "stats counts every snapshot produced (" .. stats.snapshots .. ")")
check(stats.bytesSent == firedBytes + emptyBytes, "and the bytes it produced, including the ones nobody was close enough to receive")
check(stats.byteCount == SkeletonCodec.byteCount(8, 12), "stats reports the last payload size for the bandwidth budget")
check(rep.seq > 0, "the sequence number advanced with the stream")

-- Feedback continuity: two snapshots in a row must not re-anchor to the true core.
rep:reset()
local first = rep:encode(skels, 100, 0, 0)
check(rep.refX == 100, "after reset the first snapshot is absolute (no stale reference from the last life)")
local secondCount = rep:encode(skels, 100.001, 0, 0)
check(secondCount == first, "a same-length pose costs the same bytes regardless of movement")
check(rep.refX == 100, "the 1 mm nudge is absorbed by the 0.02 stud core grid, so a hovering creature does not jitter (" .. rep.refX .. ")")
local third = rep:encode(skels, 104.5, 0, 0)
check(math.abs(rep.refX - 104.5) <= SkeletonCodec.MAX_CORE_ERROR + 1e-9, "and a real 4.5 stud move still lands inside the core budget (" .. rep.refX .. ")")
check(third == first, "same pose shape, same byte count")

end
do
print("=== KillChoreography: cadence-owned victim scene ===")
local phases = {}
local severed = 0
local completed = false
local scene = KillChoreography.new({
	VictimUserId = 7,
	CreatureId = 1,
	Duration = 1.2,
	Timings = {
		GRAB = 0.1,
		LIFT = 0.2,
		COIL = 0.2,
		TENDERIZE = 0.3,
		CONSUME = 0.2,
		DISCARD = 0.2,
	},
	Dismemberment = true,
	OnPhase = function(phase) phases[#phases + 1] = phase end,
	OnSever = function() severed = severed + 1 end,
	OnComplete = function() completed = true end,
})
for _ = 1, 12 do
	scene:step(0.1)
end
check(phases[1] == "GRAB" and phases[2] == "LIFT", "victim scene starts at GRAB and advances in configured order")
check(severed == 1, "optional dismemberment callback fires once during TENDERIZE")
check(completed and scene:isDone(), "victim scene completes without a second scheduler")

end
do
print("=== TimeModel: one clock, so the sky can never disagree with the phase (docs/06 §2) ===")

check(TimeModel.minutesToClock(0) == 0, "midnight is hour 0")
check(TimeModel.minutesToClock(TimeModel.MINUTES_PER_DAY) == 0, "and 1440 minutes wraps to the same hour")
check(TimeModel.minutesToClock(750) == 12.5, "12:30 is hour 12.5")
check(TimeModel.clockToMinutes(6.25) == 375, "hours convert back to minutes")
check(TimeModel.phaseOf(6.5) == "Dawn", "06:30 is Dawn")
check(TimeModel.phaseOf(12) == "Day", "noon is Day")
check(TimeModel.phaseOf(18.5) == "Dusk", "18:30 is Dusk")
check(TimeModel.phaseOf(2.0) == "Night", "2 a.m. is Night")
check(TimeModel.phaseOf(TimeModel.PHASE_HOURS.NightStart - 0.001) == "Dusk", "the last instant of Dusk is still Dusk")
check(TimeModel.phaseOf(TimeModel.PHASE_HOURS.NightStart) == "Night", "the first instant of Night is Night")
check(TimeModel.nextPhase("Dusk") == "Night" and TimeModel.nextPhase("Night") == "Dawn", "the cycle order is Dawn->Day->Dusk->Night->Dawn")

check(approx(TimeModel.warp(0, -0.6), 0, 1e-12), "warp(0) is exactly 0 whatever the ease")
check(approx(TimeModel.warp(1, 0.9), 1, 1e-12), "warp(1) is exactly 1, and an over-range ease is clamped, not obeyed")
local mono = true
local prevWarp = -1
for i = 0, 20 do
	local w = TimeModel.warp(i / 20, -TimeModel.MAX_EASE)
	if w < prevWarp then
		mono = false
	end
	prevWarp = w
end
check(mono, "warp is monotone at the negative ease clamp, so the sun never runs backwards mid-phase")
-- Derivation, so the direction of the sign is not folklore: smoothstep(p) < p for
-- p < 0.5 and > p above it, so warp = p + ease*(smoothstep - p) runs AHEAD early
-- and BEHIND late when ease is negative - i.e. it spends the phase's second half
-- dawdling, which is where a Dusk wants to live (18.5-19.8, the money shot).
check(TimeModel.warp(0.25, -TimeModel.MAX_EASE) > 0.25, "a negative ease runs ahead through the first half")
check(TimeModel.warp(0.75, -TimeModel.MAX_EASE) < 0.75, "and dawdles through the second half")
check(TimeModel.warp(0.25, TimeModel.MAX_EASE) < 0.25, "a positive ease is the mirror image")
check(approx(TimeModel.warp(0.5, TimeModel.MAX_EASE), 0.5, 1e-12), "both are exact at the midpoint, where smoothstep crosses the line")
local duskPhase, duskWeight = TimeModel.phaseWeight(18.75)
check(duskPhase == "Dusk", "phaseWeight reports the phase alongside the blend")
check(approx(duskWeight, 0.5, 1e-9), "and dusk's midpoint is exactly its midpoint hour (18.75), the ease acting on either side of it")

-- THE property WP4's acceptance hangs on: the clock lands exactly on the next
-- phase's start hour, at Threat 0 and Threat 1, for all four phases.
local boundaryOk = true
local spanOk = true
for i = 1, #TimeModel.PHASES do
	local phase = TimeModel.PHASES[i]
	local startHour, length = TimeModel.phaseSpan(phase)
	local endHour = TimeModel.phaseClock(phase, 1)
	local nextStart = TimeModel.phaseSpan(TimeModel.nextPhase(phase))
	if math.abs(endHour - nextStart) > 1e-9 then
		boundaryOk = false
	end
	local covered = endHour - startHour
	if covered < 0 then
		covered = covered + TimeModel.HOURS_PER_DAY
	end
	if math.abs(covered - length) > 1e-9 then
		spanOk = false
	end
end
check(boundaryOk, "each phase ends EXACTLY on the next phase's boundary hour")
check(spanOk, "and traverses exactly its documented hour span")

local nightAt0 = TimeModel.phaseSeconds("Night", 0)
local nightAt1 = TimeModel.phaseSeconds("Night", 1)
local threatAdds = DayNightConfig.Pacing.NightPerThreatSeconds * DayNightConfig.Pacing.NightThreatMultiplier
check(nightAt1 - nightAt0 == threatAdds, "Night grows 45 s x 4 across the Threat range (" .. nightAt0 .. " -> " .. nightAt1 .. " s)")
check(TimeModel.phaseSeconds("Day", 1) == DayNightConfig.Pacing.DaySeconds, "Day does not care about Threat (docs/00 P5: the NIGHT is the dial)")
local expectCycle = DayNightConfig.Pacing.DawnSeconds + DayNightConfig.Pacing.DaySeconds + DayNightConfig.Pacing.DuskSeconds + DayNightConfig.Pacing.NightBaseSeconds
check(TimeModel.cycleSeconds(0) == expectCycle, "the cycle sums the four phases at Threat 0 (" .. expectCycle .. " s)")
check(TimeModel.cycleSeconds(1) == expectCycle + threatAdds, "and Threat only lengthens the Night")
check(TimeModel.cycleSeconds(0) / 60 >= 8 and TimeModel.cycleSeconds(1) / 60 <= 14, "the session stays inside the 8-14 minute target (" .. string.format("%.1f", TimeModel.cycleSeconds(0) / 60) .. "-" .. string.format("%.1f", TimeModel.cycleSeconds(1) / 60) .. " min)")
check(TimeModel.phaseSeconds("Night", 1) / TimeModel.cycleSeconds(1) > TimeModel.phaseSeconds("Night", 0) / TimeModel.cycleSeconds(0), "and Night is a bigger SHARE of the round at high Threat, not just longer")

check(TimeModel.skyKey(12) == "Sky_Day", "noon takes the day sky")
check(TimeModel.skyKey(19.0) == "Sky_Dusk", "19:00 is still the dusk sky")
check(TimeModel.skyKey(21.5) == "Sky_Night", "the switch happened at the fog-thick hour")
check(TimeModel.skyKey(2.0) == "Sky_Night", "and the small hours are night")
local skyOk = true
for i = 0, 1439 do
	local key = TimeModel.skyKey(TimeModel.minutesToClock(i))
	if key ~= "Sky_Day" and key ~= "Sky_Dusk" and key ~= "Sky_Night" then
		skyOk = false
	end
end
check(skyOk, "skyKey answers for all 1440 minutes of the day")

check(TimeModel.sunElevation(12) > 20, "the sun is well up at local noon at the configured latitude (" .. string.format("%.1f", TimeModel.sunElevation(12)) .. " deg)")
check(TimeModel.sunElevation(0) < -20, "and well down at midnight")
check(TimeModel.isDaylight(12) == true and TimeModel.isDaylight(0) == false, "isDaylight follows the horizon crossing")

local moon = DayNightConfig.Moon.StartPhase
for i = 1, 20 do
	moon = TimeModel.nextMoonPhase(moon)
end
check(moon >= 0 and moon < DayNightConfig.Moon.Phases, "moon phase stays inside 0..Phases-1 after 20 nights (" .. moon .. ")")
check(moon == (DayNightConfig.Moon.StartPhase + 20) % DayNightConfig.Moon.Phases, "and it really did walk forward 20 steps")
local fullMoon = TimeModel.moonBrightnessDelta(DayNightConfig.Moon.Phases / 2)
local newMoon = TimeModel.moonBrightnessDelta(0)
check(fullMoon > newMoon, "a full moon adds more light than a new one (" .. string.format("%.3f", fullMoon) .. " vs " .. string.format("%.3f", newMoon) .. ")")
check(approx(fullMoon, DayNightConfig.Moon.BrightnessDelta, 1e-9), "and the peak is exactly the configured delta")

end
do
print("=== WP6A CreatureMemory / Senses / Steering (blind instinct) ===")

local CreatureMemory = VitriolRequire("CreatureMemory")
local Senses = VitriolRequire("Senses")
local Steering = VitriolRequire("Steering")

check(CreatureMemory.hasSight() == false, "CreatureMemory has no sight channel")
check(Senses.hasSight() == false, "Senses has no sight channel")
check(GameConfig.Features.CreatureLearning == false, "CreatureLearning stays off for WP6A")
check(MonsterConfig.Senses.ObserverChannels[1] == "VIBRATION", "observer channels start at vibration, not sight")
local sightListed = false
for i = 1, #MonsterConfig.Senses.ObserverChannels do
	if MonsterConfig.Senses.ObserverChannels[i] == "SIGHT" then
		sightListed = true
	end
end
check(sightListed == false, "SIGHT is not an observer channel")

local memory = CreatureMemory.new(MonsterConfig)
check(memory:observe("SIGHT", 1, 2, 3, 1, 0) == false, "observe refuses a sight event")
check(memory:observe("VISION", 1, 2, 3, 1, 0) == false, "and refuses VISION as an alias")
check(memory:observe("VIBRATION", 40, 0, 0, 0.9, 0, 2.0) == true, "vibration evidence is stored")
check(memory:best().channel == "VIBRATION" and approx(memory:best().x, 40, 1e-9), "best evidence is the vibration position, not a player")
memory:decay(MonsterConfig.Memory.EvidenceHalfLife)
check(approx(memory:best().confidence, 0.45, 1e-6), "confidence halves after one evidence half-life (got " .. string.format("%.4f", memory:best().confidence) .. ")")
memory:decay(16)
check(memory:best() == nil, "stale evidence drops below the confidence floor")
check(memory:hasLastKnown(16) == true, "last-known survives after working memory expires")
check(memory.lastKnown.exact == false, "but it is no longer an exact chase point")
check(memory:hasLastKnown(MonsterConfig.Memory.LastKnownMaxAgeSeconds + 1) == false, "and it expires after LastKnownMaxAgeSeconds")

local field = NoiseField.new({
	Halflife = { VIBRATION = 1000, SCENT = 1000, AIR = 1000 },
	Coupling = MonsterConfig.Senses.VibrationCoupling,
})
-- Silent nearby scent vs a farther loud footstep. Positions are injected numbers.
field:emitAt("SCENT", 6, 0, 0, 0.20, 0)
field:emitAt("VIBRATION", 40, 0, 0, 2.0, 0)
local iNear = field:bestImpulse("SCENT", 0, 0, 0, 80, 0)
local iFar, fx = field:bestImpulse("VIBRATION", 0, 0, 0, 80, 0)
check(iFar > iNear, "the field's loudest vibration outranks nearby base scent")
check(approx(fx, 40, 1e-9), "bestImpulse returns the loud source position, not the nearest")

local senses = Senses.new({
	Field = field,
	Config = MonsterConfig,
	Stats = {
		SenseRange = { VIBRATION = 80, AIR = 70, SCENT = 50 },
		SenseAcuity = { VIBRATION = 0.9, AIR = 0.5, SCENT = 0.5 },
	},
})
check(senses:hasChannel("SIGHT") == false, "Senses:hasChannel refuses sight")
local observations, n = senses:sample(0, 0, 0, 0)
check(n >= 1, "the observer hears at least one channel")
local loudest = senses:loudest(0, 0, 0, 0)
check(loudest ~= nil and loudest.channel == "VIBRATION", "far loud vibration beats silent nearby scent (got " .. tostring(loudest and loudest.channel) .. ")")
check(loudest.x > 20, "and the estimated position is the far source, not the nearby silent one (x=" .. string.format("%.1f", loudest.x) .. ")")

local wetField = NoiseField.new({ Halflife = { VIBRATION = 1000 }, Coupling = MonsterConfig.Senses.VibrationCoupling })
wetField:emitAt("VIBRATION", 0, 0, 0, 1, 0, nil, "Concrete")
local dry = wetField:sample("VIBRATION", 0, 0, 0, 20, 0)
wetField:setWeather(DayNightConfig.Weather.Rain)
local rained = wetField:sample("VIBRATION", 0, 0, 0, 20, 0)
check(rained < dry, "rain masking stays on NoiseField, not reimplemented in Senses")
local waterField = NoiseField.new({ Halflife = { VIBRATION = 1000 }, Coupling = MonsterConfig.Senses.VibrationCoupling })
waterField:emitAt("VIBRATION", 0, 0, 0, 1, 0, nil, "Water")
waterField:emitAt("VIBRATION", 30, 0, 0, 1, 0, nil, "Concrete")
local wI, wx = waterField:bestImpulse("VIBRATION", 0, 0, 0, 80, 0)
check(wx == 30, "surface coupling makes concrete louder than water, so bestImpulse prefers it")
check(wI > 1, "and the coupled intensity is amplified")

local windField = NoiseField.new({
	Halflife = { SCENT = 1000 },
	AdvectedMaxAge = MonsterConfig.Senses.AdvectionMaxAgeSeconds,
})
windField:setWind(1, 0, 0)
windField:emit("SCENT", 0, 0, 0, 1, 0)
local plume, px = windField:bestImpulse("SCENT", 5, 0, 0, 2, 5)
check(plume > 0.9 and approx(px, 5, 1e-9), "bestImpulse follows the advected plume, not the emit origin")

local mem2 = CreatureMemory.new(MonsterConfig)
for _ = 1, 20 do
	mem2:observeTagged("Garage", "Idle")
	mem2:observeTagged("House", "Idle")
end
local garage = mem2:stateIndex("Garage", "Idle")
check(mem2.predictor.observations >= MonsterConfig.Prediction.MinObservations, "tagged location/posture sequences fill the Markov table")
check(mem2:predictability(garage) > MonsterConfig.Prediction.PredictabilityLow, "a repeating Garage habit is predictable without Q-learning")
local ranked = mem2:predict(garage, 1)
check(ranked[1] ~= nil and ranked[1].state == mem2:stateIndex("House", "Idle"), "the predictor's next state is House, still without Q")

local utility = UtilityAI.new()
local genome = { Cunning = 0.5, Speed = 0.5, Strength = 0.5, Softness = 0.2, Adhesion = 0.2 }
local stats = {
	Genome = genome,
	Temperament = { STALK = 0.7, CHARGE = 0.3, RETREAT = 0.1, SEARCH = 0.2 },
}
local steering = Steering.new({
	Config = MonsterConfig,
	Stats = stats,
	Utility = utility,
	Features = GameConfig.Features,
})
local chase = steering:decide({
	x = 0, y = 0, z = 0, now = 1,
	evidence = { channel = "VIBRATION", x = 70, y = 0, z = 0, confidence = 0.9, age = 0.2, time = 1 },
	threatening = true,
	wound = 0,
	spawnX = 0, spawnY = 0, spawnZ = 0,
})
check(chase.action == "STALK" or chase.action == "INVESTIGATE", "live evidence steers investigate/stalk, not a nearest-player query (got " .. tostring(chase.action) .. ")")
check(approx(chase.x, 70, 1e-9), "the target request is the evidence position")
check(chase.channel == "VIBRATION", "and names the channel, never a player")

local expired = steering:decide({
	x = 0, y = 0, z = 0, now = 12,
	evidence = nil,
	lastKnown = { channel = "VIBRATION", x = 70, y = 0, z = 0, confidence = 0.4, time = 1, exact = false },
	threatening = true,
	wound = 0,
	spawnX = 0, spawnY = 0, spawnZ = 0,
})
check(expired.action == "SEARCH", "expired evidence becomes a bounded search, not a stale chase")
local wander = math.sqrt((expired.x - 70) ^ 2 + (expired.z - 0) ^ 2)
check(wander > 0.01 and wander <= MonsterConfig.Memory.SearchWanderRadius + 1e-6, "search wanders the last-known area instead of the exact point (wander=" .. string.format("%.2f", wander) .. ")")

local wounded = steering:decide({
	x = 0, y = 0, z = 0, now = 20,
	evidence = { channel = "VIBRATION", x = 8, y = 0, z = 0, confidence = 1, age = 0, time = 20 },
	threatening = false,
	wound = 1,
	spawnX = 0, spawnY = 0, spawnZ = 0,
})
check(wounded.action == "RETREAT", "a wounded non-threatening creature retreats")
check(wounded.x == nil, "and emits no pursuit target")

local learningOff = Steering.new({
	Config = MonsterConfig,
	Stats = stats,
	Utility = UtilityAI.new(),
	Features = { CreatureLearning = true },
})
-- Even with the flag forced, WP6A's decide path must not call QLearning.
local qPick = learningOff:decide({
	x = 0, y = 0, z = 0, now = 30,
	evidence = { channel = "SCENT", x = 12, y = 0, z = 0, confidence = 0.6, age = 0, time = 30 },
	threatening = true,
	wound = 0,
	spawnX = 0, spawnY = 0, spawnZ = 0,
	rng = RNG.new(3),
})
check(qPick.action ~= nil and qPick.action ~= "SIGHT", "softmax-with-flag still returns an instinct action, never sight")

end
return TESTS
