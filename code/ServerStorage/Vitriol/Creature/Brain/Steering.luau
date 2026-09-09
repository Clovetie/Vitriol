--!strict
-- Steering.luau
-- Location: ServerStorage > Vitriol > Creature > Brain > Steering  (ModuleScript)
-- Purpose:  Instinct-only action pick for WP6A. Scores INVESTIGATE / STALK /
--           SEARCH / RETREAT / CHARGE from evidence and genome temperament,
--           gated by MonsterConfig.Actions.requires. Returns a target REQUEST
--           (action + numeric position + confidence), never a player or Instance.
--
--           Q-learning is not consulted: GameConfig.Features.CreatureLearning
--           stays false. UtilityAI is the readable policy (docs/02 §9.1).
-- Requires: injected Lib/UtilityAI, MonsterConfig, expressed stats
-- Used by:  Services/CreatureService

local Steering = {}
Steering.__index = Steering

local function clamp(value: number, low: number, high: number): number
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

local function dist3(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local dx = ax - bx
	local dy = ay - by
	local dz = az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Steering.new(options: any): any
	local o = options or {}
	local self = setmetatable({}, Steering)
	self.Config = o.Config or {}
	self.Actions = self.Config.Actions or {}
	self.MemoryCfg = self.Config.Memory or {}
	self.Commitment = self.Config.Commitment or {}
	self.Stats = o.Stats or {}
	self.Utility = o.Utility
	self.Features = o.Features or {}
	self.RNG = o.RNG
	self.lastAction = "SEARCH"
	self.lastChangeAt = -1e9
	self.scoresScratch = {}
	return self
end

function Steering:_gated(name: any): boolean
	local spec = self.Actions[name]
	if spec == nil then
		return false
	end
	local requires = spec.requires
	if requires == nil then
		return true
	end
	local genome = self.Stats.Genome or self.Stats
	for gene, minValue in pairs(requires) do
		local have = genome[gene]
		if have == nil then
			have = 0.5
		end
		if have < minValue then
			return false
		end
	end
	return true
end

function Steering:_instinct(name: any): number
	local temperament = self.Stats.Temperament
	if temperament and temperament[name] ~= nil then
		return temperament[name]
	end
	return 0.2
end

function Steering:_topScores(): any
	local utility = self.Utility
	local out = self.scoresScratch
	local n = 0
	if utility == nil then
		return out, 0
	end
	for i = 1, utility.count do
		local entry = utility.options[i]
		n = n + 1
		out[n] = entry
	end
	-- Tiny selection sort so the diagnostic line is stable without table.sort
	-- (hot-loop-scan prices table.sort).
	for i = 1, n do
		local best = i
		for j = i + 1, n do
			if out[j].score > out[best].score then
				best = j
			end
		end
		if best ~= i then
			local tmp = out[i]
			out[i] = out[best]
			out[best] = tmp
		end
	end
	return out, n
end

-- decide(steering, ctx) -> request
-- ctx: { x, y, z, now, evidence, lastKnown, threatening, wound, spawnX, spawnY,
--        spawnZ, rng }
-- request: { action, x, y, z, confidence, channel, evidenceAge, scores }
function Steering:decide(ctx: any): any
	local now = ctx.now or 0
	local utility = self.Utility
	if utility then
		utility:clear()
	end
	local floor = self.MemoryCfg.ConfidenceFloor or 0.08
	local wander = self.MemoryCfg.SearchWanderRadius or 16
	local patrol = self.MemoryCfg.PatrolRadius or 22
	local lastKnownMax = self.MemoryCfg.LastKnownMaxAgeSeconds or 14
	local commitRange = self.Commitment.CommitRange or 16
	local refractory = self.Commitment.RefractorySeconds or 0.4

	local evidence = ctx.evidence
	local lastKnown = ctx.lastKnown
	local threatening = ctx.threatening
	if threatening == nil then
		threatening = true
	end

	local request = {
		action = "SEARCH",
		x = nil,
		y = nil,
		z = nil,
		confidence = 0,
		channel = nil,
		evidenceAge = 0,
		scores = nil,
	}

	if not threatening or (ctx.wound or 0) >= 0.85 then
		if utility then
			utility:consider("RETREAT", 1.0)
		end
		request.action = "RETREAT"
		request.scores = { RETREAT = 1 }
		self.lastAction = "RETREAT"
		return request
	end

	local conf = 0
	local channel = nil
	local age = 0
	local ex, ey, ez = nil, nil, nil
	if evidence and evidence.channel and (evidence.confidence or 0) >= floor then
		conf = evidence.confidence
		channel = evidence.channel
		age = evidence.age or (now - (evidence.time or now))
		ex, ey, ez = evidence.x, evidence.y, evidence.z
	end

	local cx, cy, cz = ctx.x or 0, ctx.y or 0, ctx.z or 0
	local spawnX = ctx.spawnX or cx
	local spawnY = ctx.spawnY or cy
	local spawnZ = ctx.spawnZ or cz
	local rng = ctx.rng or self.RNG

	if utility then
		if self:_gated("RETREAT") then
			utility:consider("RETREAT", self:_instinct("RETREAT") * (ctx.wound or 0))
		end
		if conf >= floor and ex ~= nil then
			local d = dist3(cx, cy, cz, ex, ey, ez)
			if self:_gated("STALK") then
				utility:consider("STALK", self:_instinct("STALK") * (0.35 + 0.65 * conf))
			end
			if self:_gated("INVESTIGATE") then
				utility:consider("INVESTIGATE", 0.45 * conf + 0.2 * (1 - math.min(d / 80, 1)))
			end
			if self:_gated("CHARGE") and d <= commitRange then
				utility:consider("CHARGE", self:_instinct("CHARGE") * (0.5 + 0.5 * conf))
			end
		else
			if self:_gated("INVESTIGATE") and lastKnown and lastKnown.channel and (now - (lastKnown.time or 0)) <= lastKnownMax then
				utility:consider("INVESTIGATE", 0.40)
			end
			if self:_gated("SEARCH") then
				utility:consider("SEARCH", 0.55)
			end
		end
		if self:_gated("SEARCH") and utility:score("SEARCH") == nil and conf < floor then
			utility:consider("SEARCH", 0.50)
		end
	end

	local action = "SEARCH"
	if utility then
		if self.Features.CreatureLearning then
			action = utility:select(rng, 0.4) or "SEARCH"
		else
			action = utility:best() or "SEARCH"
		end
	elseif conf >= floor then
		action = "STALK"
	end

	if now - self.lastChangeAt < refractory and self.lastAction ~= action then
		local delta = self.Commitment.PreemptScoreDelta or 0.25
		local newScore = utility and utility:score(action) or 0
		local oldScore = utility and utility:score(self.lastAction) or 0
		if (newScore - (oldScore or 0)) < delta then
			action = self.lastAction
		end
	end
	if action ~= self.lastAction then
		self.lastChangeAt = now
		self.lastAction = action
	end

	request.action = action
	request.channel = channel or (lastKnown and lastKnown.channel) or nil
	request.evidenceAge = age
	if lastKnown and request.channel == lastKnown.channel then
		if age == 0 then
			request.evidenceAge = now - (lastKnown.time or now)
		end
	end
	request.confidence = conf

	if action == "RETREAT" then
		request.x, request.y, request.z = nil, nil, nil
	elseif (action == "STALK" or action == "CHARGE" or action == "INVESTIGATE") and ex ~= nil and conf >= floor then
		request.x, request.y, request.z = ex, ey, ez
		request.confidence = conf
	elseif lastKnown and lastKnown.channel and (now - (lastKnown.time or 0)) <= lastKnownMax then
		-- Search the last-known AREA, not the stale exact point forever.
		local ox, oz = 0, 0
		if rng and rng.range then
			ox = rng:range(-wander, wander)
			oz = rng:range(-wander, wander)
		else
			local phase = now * 0.37
			ox = math.cos(phase) * wander * 0.5
			oz = math.sin(phase) * wander * 0.5
		end
		request.action = "SEARCH"
		request.x = lastKnown.x + ox
		request.y = lastKnown.y
		request.z = lastKnown.z + oz
		request.confidence = clamp(lastKnown.confidence or 0.1, 0, 0.4)
		request.channel = lastKnown.channel
		request.evidenceAge = now - (lastKnown.time or now)
	else
		local ox, oz = 0, 0
		if rng and rng.range then
			ox = rng:range(-patrol, patrol)
			oz = rng:range(-patrol, patrol)
		else
			local phase = now * 0.19
			ox = math.cos(phase) * patrol * 0.6
			oz = math.sin(phase) * patrol * 0.6
		end
		request.action = "SEARCH"
		request.x = spawnX + ox
		request.y = spawnY
		request.z = spawnZ + oz
		request.confidence = 0.05
	end

	if utility then
		local ranked, n = self:_topScores()
		local packed = {}
		local limit = n
		if limit > 4 then
			limit = 4
		end
		for i = 1, limit do
			packed[ranked[i].name] = ranked[i].score
		end
		request.scores = packed
	end
	return request
end

return Steering
