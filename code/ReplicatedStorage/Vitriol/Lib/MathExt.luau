--!strict
-- MathExt.luau
-- Location: ReplicatedStorage > Vitriol > Lib > MathExt  (ModuleScript)
-- Purpose:  Frame-rate-independent interpolation and small vector helpers.
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Lib/Fabrik, Lib/Genetics, Creature/Body/TendrilRig, Client/SkeletonInterpolator

local TAU = math.pi * 2

local MathExt = {}

MathExt.TAU = TAU

-- Plain linear interpolation.
function MathExt.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Frame-rate independent exponential approach. Use this instead of lerp(a,b,0.1)
-- anywhere a value chases a target every frame, or the motion will change speed
-- with the frame rate.
function MathExt.damp(a: number, b: number, lambda: number, dt: number): number
	if lambda <= 0 then
		return a
	end
	if dt <= 0 then
		return a
	end
	return a + (b - a) * (1 - math.exp(-lambda * dt))
end

-- 0 at edge0, 1 at edge1, smooth in between. Clamped outside the range.
function MathExt.smoothstepRange(x: number, edge0: number, edge1: number): number
	if edge1 == edge0 then
		return x < edge0 and 0 or 1
	end
	local t = (x - edge0) / (edge1 - edge0)
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	return t * t * (3 - 2 * t)
end

-- smoothstep over 0..1.
function MathExt.smoothstep(t: number): number
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	return t * t * (3 - 2 * t)
end

-- Move `a` toward `b` by at most maxDelta. No overshoot, no oscillation.
function MathExt.approach(a: number, b: number, maxDelta: number): number
	if a < b then
		local v = a + maxDelta
		if v > b then
			return b
		end
		return v
	else
		local v = a - maxDelta
		if v < b then
			return b
		end
		return v
	end
end

-- Angle in degrees between two 3D directions given as components.
-- Returns 0 for degenerate (zero-length) inputs rather than NaN.
function MathExt.angleBetweenDeg(
	ax: number, ay: number, az: number,
	bx: number, by: number, bz: number
): number
	local la = math.sqrt(ax * ax + ay * ay + az * az)
	local lb = math.sqrt(bx * bx + by * by + bz * bz)
	if la < 1e-9 or lb < 1e-9 then
		return 0
	end
	local dot = (ax * bx + ay * by + az * bz) / (la * lb)
	if dot > 1 then
		dot = 1
	elseif dot < -1 then
		dot = -1
	end
	return math.deg(math.acos(dot))
end

-- Scale a vector down to at most `maxLen`. Returns the 3 components.
-- Avoids a sqrt when the vector is already short enough (common case).
function MathExt.clampMagnitude(
	x: number, y: number, z: number, maxLen: number
): (number, number, number)
	local sq = x * x + y * y + z * z
	local maxSq = maxLen * maxLen
	if sq <= maxSq or sq < 1e-12 then
		return x, y, z
	end
	local s = maxLen / math.sqrt(sq)
	return x * s, y * s, z * s
end

-- Squared distance between two points. Prefer over distance inside loops.
function MathExt.distSq(
	ax: number, ay: number, az: number,
	bx: number, by: number, bz: number
): number
	local dx = ax - bx
	local dy = ay - by
	local dz = az - bz
	return dx * dx + dy * dy + dz * dz
end

-- Remap a value from one range to another, clamped.
function MathExt.remap(v: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	if inMax == inMin then
		return outMin
	end
	local t = (v - inMin) / (inMax - inMin)
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	return outMin + (outMax - outMin) * t
end

return MathExt
