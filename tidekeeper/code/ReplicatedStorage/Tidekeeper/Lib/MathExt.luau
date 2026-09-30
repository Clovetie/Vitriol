--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/MathExt (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- Small numeric helpers used by the domain layer. Everything here is total
-- (defined for every input) and allocation-free.

local MathExt = {}

local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt

-- Clamp. Present in Luau as math.clamp, re-exported so headless harnesses and
-- Studio agree even if the shim differs.
function MathExt.clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

function MathExt.sign(v)
	if v > 0 then
		return 1
	elseif v < 0 then
		return -1
	end
	return 0
end

-- Round half away from zero, so that -0.5 -> -1 and 0.5 -> 1. Deterministic
-- across platforms; do NOT swap this for math.round, whose tie behaviour is
-- half-away-from-zero too but is not contractually pinned here.
function MathExt.round(v)
	if v >= 0 then
		return floor(v + 0.5)
	end
	return -floor(-v + 0.5)
end

-- Integer division that floors toward negative infinity (Lua's // semantics,
-- written out so Lua 5.1-based tooling can still parse the file).
function MathExt.idiv(a, b)
	return floor(a / b)
end

function MathExt.lerp(a, b, t)
	return a + (b - a) * t
end

function MathExt.approx(a, b, eps)
	return abs(a - b) <= (eps or 1e-9)
end

-- Integer percentage helpers. Money never leaves the integers, so every
-- scaling in the economy goes through one of these.
function MathExt.scalePerMille(value, perMille)
	return floor(value * perMille / 1000)
end

function MathExt.applyPercent(value, percent)
	return floor(value * (100 + percent) / 100)
end

-- Cosine similarity of two equal-length integer vectors, in [-1, 1].
-- Returns 0 when either vector is the zero vector (the honest neutral answer:
-- "no information", not "perfect mismatch").
function MathExt.cosine(a, b, n)
	local dot = 0
	local na = 0
	local nb = 0
	for i = 1, n do
		local x = a[i]
		local y = b[i]
		dot = dot + x * y
		na = na + x * x
		nb = nb + y * y
	end
	if na == 0 or nb == 0 then
		return 0
	end
	return dot / (sqrt(na) * sqrt(nb))
end

-- Linear congruential-free, allocation-free integer clamp used all over the
-- codecs: clamp v into [lo, hi] AND force it to an integer.
function MathExt.clampInt(v, lo, hi)
	local x = floor(v)
	if x < lo then
		return lo
	end
	if x > hi then
		return hi
	end
	return x
end

function MathExt.isInteger(v)
	return type(v) == "number" and v == floor(v) and v == v and v ~= math.huge and v ~= -math.huge
end

return MathExt
