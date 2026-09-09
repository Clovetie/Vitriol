--!strict
-- RegionIntegrity.luau
-- Location: ReplicatedStorage > Vitriol > Shared > RegionIntegrity  (ModuleScript)
-- Purpose:  Per-body-region damage model that makes the kill procedural.
--           Damage accrues as frictional shear; when a region fails it severs,
--           and severing cascades downstream. This is why no two kills are the
--           same (docs/04-KILL-CHOREOGRAPHY.md §2).
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Creature/Body/KillChoreography, Services/HealthService, tests

local RegionIntegrity = {}
RegionIntegrity.__index = RegionIntegrity

-- Default region table. Runtime values come from
-- ReplicatedStorage/Vitriol/Config/GoreConfig.Regions; this default exists so the
-- module is testable on its own.
RegionIntegrity.DEFAULT_REGIONS = {
	{ name = "Head", integrity = 60, vulnerability = 1.4, severable = true, downstream = {} },
	{ name = "Torso", integrity = 180, vulnerability = 0.7, severable = false, downstream = {} },
	{ name = "LeftArm", integrity = 70, vulnerability = 1.1, severable = true, downstream = { "LeftHand" } },
	{ name = "RightArm", integrity = 70, vulnerability = 1.1, severable = true, downstream = { "RightHand" } },
	{ name = "LeftLeg", integrity = 90, vulnerability = 1.0, severable = true, downstream = {} },
	{ name = "RightLeg", integrity = 90, vulnerability = 1.0, severable = true, downstream = {} },
	{ name = "LeftHand", integrity = 35, vulnerability = 1.3, severable = true, downstream = {} },
	{ name = "RightHand", integrity = 35, vulnerability = 1.3, severable = true, downstream = {} },
}

-- new(regions?) -> body
function RegionIntegrity.new(regions: any)
	local self = setmetatable({}, RegionIntegrity)
	self.defs = regions or RegionIntegrity.DEFAULT_REGIONS
	self.regions = {}
	self.order = {}
	for i = 1, #self.defs do
		local d = self.defs[i]
		self.regions[d.name] = {
			name = d.name,
			integrity = d.integrity,
			maxIntegrity = d.integrity,
			vulnerability = d.vulnerability,
			severable = d.severable,
			downstream = d.downstream or {},
			severed = false,
		}
		table.insert(self.order, d.name)
	end
	self.severLog = {}
	self.elapsed = 0
	return self
end

-- reset(body) -> ()
function RegionIntegrity:reset(): ()
	for i = 1, #self.order do
		local r = self.regions[self.order[i]]
		r.integrity = r.maxIntegrity
		r.severed = false
	end
	table.clear(self.severLog)
	self.elapsed = 0
end

-- integrityOf(body, name) -> number
function RegionIntegrity:get(name: string): number
	local r = self.regions[name]
	if not r or r.severed then
		return 0
	end
	return r.integrity
end

-- meanIntegrity(body) -> number  (0..1)
-- Used by the escape threshold: a mangled victim is harder to wriggle free of.
function RegionIntegrity:meanIntegrity(): number
	local total = 0
	local count = 0
	for i = 1, #self.order do
		local r = self.regions[self.order[i]]
		if not r.severed then
			total += r.integrity / r.maxIntegrity
			count += 1
		end
	end
	if count == 0 then
		return 0
	end
	return total / count
end

-- sever(body, name) -> {string}  (list of regions severed by this call)
-- Cascades downstream: severing an arm takes the hand with it. Enforced in one
-- place so the rule cannot drift between systems.
function RegionIntegrity:sever(name: string): {string}
	local out = {}
	local queue = { name }
	local guard = 0
	while #queue > 0 and guard < 32 do
		guard += 1
		local current = table.remove(queue, 1)
		local r = self.regions[current]
		if r and not r.severed then
			r.severed = true
			r.integrity = 0
			table.insert(out, current)
			table.insert(self.severLog, { name = current, time = self.elapsed })
			for i = 1, #r.downstream do
				table.insert(queue, r.downstream[i])
			end
		end
	end
	return out
end

-- applyShear(body, dt, params) -> {string}  (regions severed this tick)
--
-- params:
--   omega     number  angular rate of the coil (rad/s) - from the ShearRate gene
--   grip      number  0..1 grip pressure - rises as the escape mash fails
--   radiusOf  fn(name) -> number   distance of that region from the coil axis
--   shearMul  number  global multiplier (config), default 1
--   ramp      number  seconds over which the creature "settles in", default 1.5
--
-- Physics rationale (docs/04 §2.2): surface speed at a region is omega * radius,
-- so distal limbs further from the axis shear faster and fail first. The torso,
-- compressed near the axis, takes longer - which is why the creature can hold a
-- victim for several seconds before anything comes loose.
function RegionIntegrity:applyShear(dt: number, params: any): {string}
	if dt <= 0 then
		return {}
	end
	self.elapsed += dt

	local omega = params.omega or 8
	local grip = params.grip or 0.5
	local shearMul = params.shearMul or 1
	local rampTime = params.ramp or 1.5

	-- Tenderize curve: 0 at contact, 1 once the creature has settled in.
	local ramp = self.elapsed / rampTime
	if ramp > 1 then
		ramp = 1
	end
	ramp = ramp * ramp

	local severed = {}
	for i = 1, #self.order do
		local r = self.regions[self.order[i]]
		if not r.severed then
			local radius = 0.5
			if params.radiusOf then
				radius = params.radiusOf(r.name) or 0.5
			end
			local surfaceSpeed = omega * radius
			local stress = surfaceSpeed * grip * r.vulnerability
			r.integrity -= stress * dt * shearMul * ramp
			if r.integrity <= 0 and r.severable then
				local list = self:sever(r.name)
				for j = 1, #list do
					table.insert(severed, list[j])
				end
			elseif r.integrity <= 0 then
				r.integrity = 0
			end
		end
	end
	return severed
end

-- severLog(body) -> { {name, time} }
-- Ordered record of what came off and when. Drives the "discard" behaviour and
-- is what makes two kills demonstrably different in tests.
function RegionIntegrity:log(): {any}
	return self.severLog
end

return RegionIntegrity
