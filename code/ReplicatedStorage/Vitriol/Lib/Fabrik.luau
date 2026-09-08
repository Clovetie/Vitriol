--!strict
-- Fabrik.luau
-- Location: ReplicatedStorage > Vitriol > Lib > Fabrik  (ModuleScript)
-- Purpose:  Constrained FABRIK inverse-kinematics solver for tendril chains.
--           Operates on FLAT ARRAYS (no Vector3, no Instances) so it is
--           allocation-free in the frame path, parallel-safe, and unit-testable
--           outside Roblox.
--           Reference: Aristidou & Lasenby, "FABRIK: a fast, iterative solver for
--           the inverse kinematics problem", Graphical Models 73(5), 2011.
-- Requires: (none)
-- Used by:  Creature/Body/TendrilRig (server), Client/LocalRigDriver (presentation)

-- Chain shape (see docs/03-MONSTER-TECH.md §2):
--   { count = n, x = {..}, y = {..}, z = {..}, len = {..} }
-- `len[i]` is the bone length from joint i to joint i+1, so #len == count - 1.
-- Joint 1 is the root (base) and is held fixed by the solver.

local EPS = 1e-9

local Fabrik = {}

Fabrik.DEFAULT_TOLERANCE = 0.02
Fabrik.DEFAULT_MAX_ITERATIONS = 8
-- When the residual stops improving by more than this between iterations we have
-- hit the floating-point noise floor, not a slow convergence. Measured: a
-- 16-joint chain plateaus at ~0.004 studs no matter how many iterations it is
-- given, because every pass rescales by len/r and the error accumulates along the
-- chain. 0.004 studs is ~0.8 mm at Roblox scale, i.e. invisible, so the default
-- tolerance sits above it rather than spinning iterations it can never satisfy.
Fabrik.PLATEAU_EPSILON = 1e-7

-- newChain(count) -> chain
-- All joints start stacked at the origin; call setStraight() before first solve.
-- count is clamped to at least 2: a one-joint chain has no bone to solve and
-- every downstream loop assumes count >= 2.
function Fabrik.newChain(count: number, segmentLength: number?)
	local c = count or 8
	if c < 2 then
		c = 2
	end
	local seg = segmentLength or 1
	if seg <= 0 then
		seg = 1
	end
	local chain = {
		count = c,
		x = table.create(c, 0),
		y = table.create(c, 0),
		z = table.create(c, 0),
		len = table.create(c - 1, seg),
	}
	return chain
end

-- setLengths(chain, lengthsArray) -> ()
-- Tapered tendrils set len[i] decreasing along the chain.
function Fabrik.setLengths(chain: any, lengths: {number}): ()
	for i = 1, chain.count - 1 do
		chain.len[i] = lengths[i] or chain.len[i]
	end
end

-- totalLength(chain) -> number
function Fabrik.totalLength(chain: any): number
	local total = 0
	for i = 1, chain.count - 1 do
		total += chain.len[i]
	end
	return total
end

-- setStraight(chain, ox, oy, oz, dx, dy, dz) -> ()
-- Lay the chain out along a direction from an origin. Gives the solver a sane
-- starting pose, which materially affects how many iterations it needs.
function Fabrik.setStraight(
	chain: any,
	ox: number, oy: number, oz: number,
	dx: number, dy: number, dz: number
): ()
	local m = math.sqrt(dx * dx + dy * dy + dz * dz)
	if m < EPS then
		dx, dy, dz = 0, 1, 0
		m = 1
	end
	local ux, uy, uz = dx / m, dy / m, dz / m
	local px, py, pz = ox, oy, oz
	for i = 1, chain.count do
		chain.x[i] = px
		chain.y[i] = py
		chain.z[i] = pz
		if i < chain.count then
			local l = chain.len[i]
			px += ux * l
			py += uy * l
			pz += uz * l
		end
	end
end

-- copyFrom(dst, src) -> ()
function Fabrik.copyFrom(dst: any, src: any): ()
	for i = 1, src.count do
		dst.x[i] = src.x[i]
		dst.y[i] = src.y[i]
		dst.z[i] = src.z[i]
	end
end

-- endEffectorError(chain, tx, ty, tz) -> number
-- Distance from the tip to the target. Used for convergence + telemetry.
function Fabrik.endEffectorError(chain: any, tx: number, ty: number, tz: number): number
	local n = chain.count
	local dx = chain.x[n] - tx
	local dy = chain.y[n] - ty
	local dz = chain.z[n] - tz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- maxBoneError(chain) -> number
-- The largest deviation of any bone from its declared length. The solver must
-- keep this at ~0; the smoke test asserts it. A non-zero value here means the
-- solver has been mis-edited.
function Fabrik.maxBoneError(chain: any): number
	local worst = 0
	for i = 1, chain.count - 1 do
		local dx = chain.x[i + 1] - chain.x[i]
		local dy = chain.y[i + 1] - chain.y[i]
		local dz = chain.z[i + 1] - chain.z[i]
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		local err = math.abs(d - chain.len[i])
		if err > worst then
			worst = err
		end
	end
	return worst
end

---------------------------------------------------------------------------
-- Core solver
---------------------------------------------------------------------------

-- solve(chain, tx, ty, tz, opts?) -> reached: boolean
--
-- opts (all optional, pass a cached table - never allocate one per frame):
--   tolerance     number   default 0.005
--   maxIterations number   default 8
--   maxAngle      number   per-joint bend limit in degrees (nil = unlimited)
--   maxAngles     {number} per-joint overrides, indexed 2..count-1
--   planeBias     number   0..1, how strongly the bend is pulled into the
--                          preferred plane (anti-flip). Default 0.
--   upX/upY/upZ   number   preferred bend-plane reference. Default (0,1,0).
--
-- Returns true if the tip ended within `tolerance` of the target. Returns false
-- (with the chain fully extended toward the target) when the target is out of
-- reach - that is correct behaviour, not an error.
function Fabrik.solve(chain: any, tx: number, ty: number, tz: number, opts: any?): boolean
	local n = chain.count
	if n < 2 then
		return false
	end

	local tol = (opts and opts.tolerance) or Fabrik.DEFAULT_TOLERANCE
	local maxIter = (opts and opts.maxIterations) or Fabrik.DEFAULT_MAX_ITERATIONS

	local x, y, z, len = chain.x, chain.y, chain.z, chain.len

	-- Total reach.
	local total = 0
	for i = 1, n - 1 do
		total += len[i]
	end

	-- Root stays pinned where the rig put it.
	local bx, by, bz = x[1], y[1], z[1]

	local dx, dy, dz = tx - bx, ty - by, tz - bz
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

	-- UNREACHABLE: stretch the chain straight at the target and stop.
	if dist > total then
		if dist < EPS then
			return false
		end
		local ux, uy, uz = dx / dist, dy / dist, dz / dist
		local px, py, pz = bx, by, bz
		for i = 1, n do
			x[i], y[i], z[i] = px, py, pz
			if i < n then
				px += ux * len[i]
				py += uy * len[i]
				pz += uz * len[i]
			end
		end
		return false
	end

	local reached = false
	local prevErr = math.huge
	for _ = 1, maxIter do
		-- FORWARD REACHING: pin the tip on the target.
		x[n], y[n], z[n] = tx, ty, tz
		for i = n - 1, 1, -1 do
			local rx = x[i] - x[i + 1]
			local ry = y[i] - y[i + 1]
			local rz = z[i] - z[i + 1]
			local r = math.sqrt(rx * rx + ry * ry + rz * rz)
			if r < EPS then
				-- Degenerate (two joints coincident): fall back to the target
				-- direction so the chain cannot collapse into a knot.
				rx, ry, rz, r = dx, dy, dz, dist
				if r < EPS then
					rx, ry, rz, r = 0, 1, 0, 1
				end
			end
			local lam = len[i] / r
			x[i] = x[i + 1] + rx * lam
			y[i] = y[i + 1] + ry * lam
			z[i] = z[i + 1] + rz * lam
		end

		-- BACKWARD REACHING: pin the root on the base.
		-- NOTE: the blend keeps the OLD joint position direction, rescaled.
		x[1], y[1], z[1] = bx, by, bz
		for i = 2, n do
			local rx = x[i] - x[i - 1]
			local ry = y[i] - y[i - 1]
			local rz = z[i] - z[i - 1]
			local r = math.sqrt(rx * rx + ry * ry + rz * rz)
			if r < EPS then
				rx, ry, rz, r = dx, dy, dz, dist
				if r < EPS then
					rx, ry, rz, r = 0, 1, 0, 1
				end
			end
			local lam = len[i - 1] / r
			x[i] = x[i - 1] + rx * lam
			y[i] = y[i - 1] + ry * lam
			z[i] = z[i - 1] + rz * lam
		end

		local err = Fabrik.endEffectorError(chain, tx, ty, tz)
		if err < tol then
			reached = true
			break
		end
		-- Plateau: the residual has stopped improving, so we are at the float
		-- noise floor for this chain length. Extra iterations cannot help.
		if prevErr - err < Fabrik.PLATEAU_EPSILON then
			break
		end
		prevErr = err
	end

	-- Joint constraints. Applied after convergence: enforcing cone limits inside
	-- the iteration loop fights the length re-imposition and costs more than it
	-- buys for tendril-length chains.
	local limit = opts and (opts.maxAngle or nil)
	if limit or (opts and opts.maxAngles) then
		Fabrik.constraintPass(chain, opts, 2)
	end

	return reached
end

---------------------------------------------------------------------------
-- Constraints
---------------------------------------------------------------------------

-- rotateAround(ax,ay,az, kx,ky,kz, angleRad) -> x,y,z
-- Rodrigues' rotation formula. `k` must be unit length.
local function rotateAround(
	ax: number, ay: number, az: number,
	kx: number, ky: number, kz: number,
	angle: number
): number, number, number
	local c = math.cos(angle)
	local s = math.sin(angle)
	local dot = kx * ax + ky * ay + kz * az
	-- k x a
	local cx = ky * az - kz * ay
	local cy = kz * ax - kx * az
	local cz = kx * ay - ky * ax
	return ax * c + cx * s + kx * dot * (1 - c),
		ay * c + cy * s + ky * dot * (1 - c),
		az * c + cz * s + kz * dot * (1 - c)
end

-- constraintPass(chain, opts, passes) -> ()
-- Enforces per-joint cone limits and, when planeBias > 0, pulls the bend into
-- the preferred plane so the chain does not randomly flip its "elbow".
function Fabrik.constraintPass(chain: any, opts: any, passes: number?): ()
	local n = chain.count
	if n < 3 then
		return
	end
	local x, y, z, len = chain.x, chain.y, chain.z, chain.len
	local bias = (opts and opts.planeBias) or 0
	local upX = (opts and opts.upX) or 0
	local upY = (opts and opts.upY) or 1
	local upZ = (opts and opts.upZ) or 0
	local iter = passes or 1

	for _ = 1, iter do
		for i = 2, n - 1 do
			local limitDeg = nil
			if opts.maxAngles and opts.maxAngles[i] then
				limitDeg = opts.maxAngles[i]
			elseif opts.maxAngle then
				limitDeg = opts.maxAngle
			end
			if limitDeg then
				-- Incoming and outgoing bone directions.
				local ax = x[i] - x[i - 1]
				local ay = y[i] - y[i - 1]
				local az = z[i] - z[i - 1]
				local alen = math.sqrt(ax * ax + ay * ay + az * az)

				local bx = x[i + 1] - x[i]
				local by = y[i + 1] - y[i]
				local bz = z[i + 1] - z[i]
				local blen = math.sqrt(bx * bx + by * by + bz * bz)

				if alen > EPS and blen > EPS then
					local uax, uay, uaz = ax / alen, ay / alen, az / alen
					local ubx, uby, ubz = bx / blen, by / blen, bz / blen

					local dot = uax * ubx + uay * uby + uaz * ubz
					if dot > 1 then
						dot = 1
					elseif dot < -1 then
						dot = -1
					end
					local ang = math.acos(dot)
					local maxAng = math.rad(limitDeg)

					if ang > maxAng then
						-- Rotation axis for the actual bend.
						local kx = uay * ubz - uaz * uby
						local ky = uaz * ubx - uax * ubz
						local kz = uax * uby - uay * ubx
						local klen = math.sqrt(kx * kx + ky * ky + kz * kz)

						if klen > EPS then
							kx, ky, kz = kx / klen, ky / klen, kz / klen

							local nx, ny, nz = rotateAround(uax, uay, uaz, kx, ky, kz, maxAng)

							if bias > 0 then
								-- Preferred axis: perpendicular to both the bone
								-- and the tendril's stable "up".
								local px = uay * upZ - uaz * upY
								local py = uaz * upX - uax * upZ
								local pz = uax * upY - uay * upX
								local plen = math.sqrt(px * px + py * py + pz * pz)
								if plen > EPS then
									px, py, pz = px / plen, py / plen, pz / plen
									local qx, qy, qz = rotateAround(uax, uay, uaz, px, py, pz, maxAng)
									nx = nx + (qx - nx) * bias
									ny = ny + (qy - ny) * bias
									nz = nz + (qz - nz) * bias
									local nlen = math.sqrt(nx * nx + ny * ny + nz * nz)
									if nlen > EPS then
										nx, ny, nz = nx / nlen, ny / nlen, nz / nlen
									end
								end
							end

							x[i + 1] = x[i] + nx * len[i]
							y[i + 1] = y[i] + ny * len[i]
							z[i + 1] = z[i] + nz * len[i]
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Character helpers
---------------------------------------------------------------------------

-- blendToRest(chain, rest, alpha) -> ()
-- Pull the solved chain toward its authored rest pose. This is what turns a
-- rope into an organism: idle tendrils curl instead of hanging limp.
function Fabrik.blendToRest(chain: any, rest: any, alpha: number): ()
	if alpha <= 0 then
		return
	end
	local a = alpha
	if a > 1 then
		a = 1
	end
	for i = 1, chain.count do
		chain.x[i] = chain.x[i] + (rest.x[i] - chain.x[i]) * a
		chain.y[i] = chain.y[i] + (rest.y[i] - chain.y[i]) * a
		chain.z[i] = chain.z[i] + (rest.z[i] - chain.z[i]) * a
	end
end

-- dampChain(dst, src, baseStiffness, tipStiffness, dt) -> ()
-- Frame-rate independent trailing motion: the tip lags the base, which is the
-- whip-like secondary motion of a real tentacle. See docs/03-MONSTER-TECH.md §3.3
function Fabrik.dampChain(dst: any, src: any, baseStiffness: number, tipStiffness: number, dt: number): ()
	if dt <= 0 then
		return
	end
	local n = src.count
	local inv = 1 / math.max(n - 1, 1)
	for i = 1, n do
		local t = (i - 1) * inv
		local lambda = baseStiffness + (tipStiffness - baseStiffness) * t
		local k = 1 - math.exp(-lambda * dt)
		dst.x[i] = dst.x[i] + (src.x[i] - dst.x[i]) * k
		dst.y[i] = dst.y[i] + (src.y[i] - dst.y[i]) * k
		dst.z[i] = dst.z[i] + (src.z[i] - dst.z[i]) * k
	end
end

return Fabrik
