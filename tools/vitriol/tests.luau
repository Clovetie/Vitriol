-- tests.luau
-- Location: tools/vitriol/tests.luau  (executed by tools/vitriol-smoke-test.js)
-- Purpose:  Runtime assertions for the pure Vitriol modules. These tests execute
--           the REAL modules (loaded from code/) inside fengari - they are not a
--           reimplementation, so a regression in Lib/ fails here.

local MathExt = VitriolRequire("MathExt")
local RNG = VitriolRequire("RNG")
local Fabrik = VitriolRequire("Fabrik")
local Genetics = VitriolRequire("Genetics")
local RegionIntegrity = VitriolRequire("RegionIntegrity")

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

return TESTS
