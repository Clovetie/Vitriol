--!strict
-- QLearning.luau
-- Location: ReplicatedStorage > Vitriol > Lib > QLearning  (ModuleScript)
-- Purpose:  Linear-function-approximation Q-learning with REPLACING eligibility
--           traces and Boltzmann action selection. The creature's learned policy.
--           Specification and rationale: docs/02-MONSTER-DESIGN.md §8.
--
--           Why linear and not a network: Luau has no autodiff and no GPU, and the
--           decision budget is a fraction of a millisecond at 4-8 Hz. A sparse
--           binary feature vector dotted into per-action weights is a few hundred
--           multiply-adds, and - critically - it is INSPECTABLE, which the
--           legibility pillar (docs/00-VISION.md P4) and AIDebugDump both require.
--
--           States are encoded SPARSELY: `feats` is an array of active feature
--           indices, so Q(s,a) = bias[a] + sum over f in feats of w[a][f].
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Creature/Brain/Policy

local QLearning = {}
QLearning.__index = QLearning

local TRACE_CUTOFF = 1e-4 -- traces smaller than this are dropped, bounding memory

local DEFAULTS = {
	Alpha = 0.09,
	AlphaDecayN0 = 400,
	Gamma = 0.94,
	Lambda = 0.80,
	TemperatureStart = 1.4,
	TemperatureEnd = 0.35,
	EpsilonFloor = 0.05,
	RewardClamp = 30,
	WeightNormCap = 24,
}

-- new(cfg) -> QLearning
-- cfg.actions is a required array of action names. Any other key falls back to
-- DEFAULTS (which mirror Config/MonsterConfig.Learning).
function QLearning.new(cfg: any): any
	local self = setmetatable({}, QLearning)
	local c = cfg or {}
	self.actions = c.actions or {}
	self.nActions = #self.actions
	self.actionIndex = {}
	for i = 1, self.nActions do
		self.actionIndex[self.actions[i]] = i
	end

	self.alpha = c.Alpha or DEFAULTS.Alpha
	self.alphaDecayN0 = c.AlphaDecayN0 or DEFAULTS.AlphaDecayN0
	self.gamma = c.Gamma or DEFAULTS.Gamma
	self.lambda = c.Lambda or DEFAULTS.Lambda
	self.epsilonFloor = c.EpsilonFloor or DEFAULTS.EpsilonFloor
	self.rewardClamp = c.RewardClamp or DEFAULTS.RewardClamp
	self.weightNormCap = c.WeightNormCap or DEFAULTS.WeightNormCap

	self.weights = {} -- weights[a] = { [feature] = w }
	self.bias = {}
	self.traces = {} -- traces[a] = { [feature] = e }
	self.biasTrace = {}
	for i = 1, self.nActions do
		self.weights[i] = {}
		self.bias[i] = 0
		self.traces[i] = {}
		self.biasTrace[i] = 0
	end

	self.updates = 0
	self.cumulativeDelta = 0
	self.lastDelta = 0
	return self
end

-- actionCount(ql) -> number
function QLearning:actionCount(): number
	return self.nActions
end

-- currentAlpha(ql) -> number
function QLearning:currentAlpha(): number
	return self.alpha / (1 + self.updates / self.alphaDecayN0)
end

-- _q(ql, actionIndex, feats) -> number
function QLearning:_q(ai: number, feats: any): number
	local q = self.bias[ai]
	local wa = self.weights[ai]
	if next(wa) ~= nil then
		for i = 1, #feats do
			local v = wa[feats[i]]
			if v then
				q += v
			end
		end
	end
	return q
end

-- q(ql, feats, action) -> number
function QLearning:q(feats: any, action: any): number
	local ai = self.actionIndex[action]
	if ai == nil then
		return 0
	end
	return self:_q(ai, feats)
end

-- _maxQ(ql, feats) -> number, actionIndex
function QLearning:_maxQ(feats: any): number, number
	local best = -math.huge
	local bestAi = 1
	for ai = 1, self.nActions do
		local v = self:_q(ai, feats)
		if v > best then
			best = v
			bestAi = ai
		end
	end
	if best == -math.huge then
		return 0, 1
	end
	return best, bestAi
end

-- scores(ql, feats, logPrior?, kappa?) -> { [action] = score }
-- Q plus the genome's instinct prior (docs/02 §6.2). Used by Policy and by the
-- debug dump. Allocates; call on the Think cadence only.
function QLearning:scores(feats: any, logPrior: any?, kappa: number?): any
	local k = kappa or 0
	local out = {}
	for ai = 1, self.nActions do
		local name = self.actions[ai]
		local s = self:_q(ai, feats)
		if k ~= 0 and logPrior and logPrior[name] then
			s += k * logPrior[name]
		end
		out[name] = s
	end
	return out
end

-- act(ql, feats, rng, opts?) -> action, actionIndex
-- opts: { logPrior = table, kappa = number, temperature = number, epsilon = number }
--
-- Boltzmann over Q + kappa*logPrior, with an exploration floor. The floor matters
-- more than it looks: a creature that stops exploring stops being surprising, and
-- "surprising" is the product (docs/02 §8.6).
function QLearning:act(feats: any, rng: any, opts: any?): any, number
	if self.nActions == 0 then
		return nil, 0
	end
	local o = opts or {}
	local epsilon = o.epsilon
	if epsilon == nil then
		epsilon = self.epsilonFloor
	end
	if rng and rng:next() < epsilon then
		local ai = rng:int(1, self.nActions)
		return self.actions[ai], ai
	end

	local kappa = o.kappa or 0
	local logPrior = o.logPrior
	local temp = o.temperature
	if temp == nil then
		temp = DEFAULTS.TemperatureStart
	end

	-- Collect scores, subtracting the max for numerical stability.
	local maxScore = -math.huge
	local scores = {}
	for ai = 1, self.nActions do
		local s = self:_q(ai, feats)
		if kappa ~= 0 and logPrior then
			local lp = logPrior[self.actions[ai]]
			if lp then
				s += kappa * lp
			end
		end
		scores[ai] = s
		if s > maxScore then
			maxScore = s
		end
	end

	if temp <= 0 then
		local bestAi = 1
		for ai = 2, self.nActions do
			if scores[ai] > scores[bestAi] then
				bestAi = ai
			end
		end
		return self.actions[bestAi], bestAi
	end

	local total = 0
	for ai = 1, self.nActions do
		scores[ai] = math.exp((scores[ai] - maxScore) / temp)
		total += scores[ai]
	end
	if total <= 0 or rng == nil then
		local bestAi = 1
		for ai = 2, self.nActions do
			if scores[ai] > scores[bestAi] then
				bestAi = ai
			end
		end
		return self.actions[bestAi], bestAi
	end

	local roll = rng:next() * total
	local acc = 0
	for ai = 1, self.nActions do
		acc += scores[ai]
		if roll <= acc then
			return self.actions[ai], ai
		end
	end
	return self.actions[self.nActions], self.nActions
end

-- greedy(ql, feats) -> action, actionIndex
function QLearning:greedy(feats: any): any, number
	local _, bestAi = self:_maxQ(feats)
	return self.actions[bestAi], bestAi
end

-- _decayAllTraces(ql) -> ()
-- Decays EVERY (feature, action) eligibility by gamma*lambda.
--
-- This must include the action that is about to be taken: canonical replacing
-- traces decay all pairs first and THEN set e(s,a) = 1 for the current pair.
-- Skipping the taken action here would leave its stale eligibilities pinned at
-- 1.0 and credit would flow back through a hunt at full strength forever.
-- Entries that fall below TRACE_CUTOFF are dropped so the trace tables cannot
-- grow without bound over a long night.
function QLearning:_decayAllTraces(): ()
	local factor = self.gamma * self.lambda
	if factor <= 0 then
		for ai = 1, self.nActions do
			self.traces[ai] = {}
			self.biasTrace[ai] = 0
		end
		return
	end
	for ai = 1, self.nActions do
		local tr = self.traces[ai]
		for f, e in pairs(tr) do
			local e2 = e * factor
			if e2 < TRACE_CUTOFF and e2 > -TRACE_CUTOFF then
				tr[f] = nil
			else
				tr[f] = e2
			end
		end
		local bt = self.biasTrace[ai] * factor
		if bt < TRACE_CUTOFF and bt > -TRACE_CUTOFF then
			bt = 0
		end
		self.biasTrace[ai] = bt
	end
end

-- learn(ql, feats, action, reward, nextFeats?) -> delta
-- nextFeats == nil marks a TERMINAL state (no bootstrap).
function QLearning:learn(feats: any, action: any, reward: number, nextFeats: any?): number
	local ai = self.actionIndex[action]
	if ai == nil or self.nActions == 0 then
		return 0
	end

	local r = reward
	if r > self.rewardClamp then
		r = self.rewardClamp
	elseif r < -self.rewardClamp then
		r = -self.rewardClamp
	end

	local qNow = self:_q(ai, feats)
	local target = r
	if nextFeats ~= nil then
		local maxNext = self:_maxQ(nextFeats)
		target = r + self.gamma * maxNext
	end
	local delta = target - qNow
	self.lastDelta = delta
	self.cumulativeDelta += math.abs(delta)

	local alpha = self:currentAlpha()

	-- Replacing traces: decay every pair by gamma*lambda, THEN set the taken
	-- action's current features to exactly 1. That replacement is what stops a
	-- feature that recurs in a loop from accumulating eligibility indefinitely.
	self:_decayAllTraces()
	local tr = self.traces[ai]
	for i = 1, #feats do
		tr[feats[i]] = 1
	end
	self.biasTrace[ai] = 1

	-- Update every action's weights by its own trace. Actions that were not taken
	-- still carry decayed eligibility, which is exactly what lets credit flow back
	-- through a multi-step hunt ("stalk -> wait -> charge" gets rewarded together).
	local wa = self.weights[ai]
	for f, e in pairs(tr) do
		wa[f] = (wa[f] or 0) + alpha * delta * e
	end
	self.bias[ai] += alpha * delta * self.biasTrace[ai]

	self.updates += 1
	-- The norm cap is checked on EVERY update. At the Think cadence (4-8 Hz) the
	-- cost is one pass over the non-zero weights, which is negligible, and a cap
	-- that is only enforced every N updates is not a bound at all.
	self:_enforceNormCap()
	return delta
end

-- weightNorm(ql) -> number
function QLearning:weightNorm(): number
	local sumSq = 0
	for ai = 1, self.nActions do
		local b = self.bias[ai]
		sumSq += b * b
		for _, v in pairs(self.weights[ai]) do
			sumSq += v * v
		end
	end
	return math.sqrt(sumSq)
end

-- _enforceNormCap(ql) -> ()
-- Guardrail (docs/02 §8.6): without this, a long night with correlated rewards
-- can inflate the weights until every Q saturates and the softmax goes degenerate.
function QLearning:_enforceNormCap(): ()
	local norm = self:weightNorm()
	if norm <= self.weightNormCap or norm <= 0 then
		return
	end
	local scale = self.weightNormCap / norm
	for ai = 1, self.nActions do
		self.bias[ai] *= scale
		local wa = self.weights[ai]
		for f, v in pairs(wa) do
			wa[f] = v * scale
		end
	end
end

-- resetTraces(ql) -> ()
-- Called at the start of each episode (one night).
function QLearning:resetTraces(): ()
	for ai = 1, self.nActions do
		self.traces[ai] = {}
		self.biasTrace[ai] = 0
	end
end

-- reset(ql) -> ()
-- Wipes learned values but keeps the action set. Used for A/B tests.
function QLearning:reset(): ()
	for ai = 1, self.nActions do
		self.weights[ai] = {}
		self.bias[ai] = 0
		self.traces[ai] = {}
		self.biasTrace[ai] = 0
	end
	self.updates = 0
	self.cumulativeDelta = 0
	self.lastDelta = 0
end

-- serialize(ql) -> table
function QLearning:serialize(): any
	local weights = {}
	for ai = 1, self.nActions do
		local copy = {}
		for f, v in pairs(self.weights[ai]) do
			copy[f] = v
		end
		weights[ai] = copy
	end
	local bias = {}
	for ai = 1, self.nActions do
		bias[ai] = self.bias[ai]
	end
	return {
		actions = self.actions,
		weights = weights,
		bias = bias,
		updates = self.updates,
	}
end

-- deserialize(data, cfg?) -> QLearning
function QLearning.deserialize(data: any, cfg: any?): any
	-- cfg wins over the serialized copy, except that the action set falls back to
	-- the one that was saved: a policy restored without its action names would
	-- silently learn a different action space.
	local merged = {}
	if cfg then
		for k, v in pairs(cfg) do
			merged[k] = v
		end
	end
	if merged.actions == nil and data.actions then
		merged.actions = data.actions
	end
	local self = QLearning.new(merged)
	if data.weights then
		for ai = 1, self.nActions do
			local src = data.weights[ai]
			if src then
				for f, v in pairs(src) do
					self.weights[ai][f] = v
				end
			end
		end
	end
	if data.bias then
		for ai = 1, self.nActions do
			self.bias[ai] = data.bias[ai] or 0
		end
	end
	self.updates = data.updates or 0
	return self
end

return QLearning
