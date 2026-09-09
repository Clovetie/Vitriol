--!strict
-- UtilityAI.luau
-- Location: ReplicatedStorage > Vitriol > Lib > UtilityAI  (ModuleScript)
-- Purpose:  Scored-action selection with Boltzmann (softmax) randomness.
--           This is the READABLE, tunable half of the creature's decision layer;
--           Lib/QLearning supplies the learned correction on top
--           (docs/02-MONSTER-DESIGN.md §9.1).
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Creature/Brain/Policy

local UtilityAI = {}
UtilityAI.__index = UtilityAI

function UtilityAI.new()
	local self = setmetatable({}, UtilityAI)
	self.options = {}
	self.byName = {}
	self.count = 0
	return self
end

-- consider(utility, name, score, weight?) -> ()
-- Scores are multiplied by weight and the highest per name wins, so several
-- subsystems can vote on the same action without double counting.
function UtilityAI:consider(name: any, score: number, weight: number?): ()
	local w = weight or 1
	local final = score * w
	local existing = self.byName[name]
	if existing then
		if final > existing.score then
			existing.score = final
		end
		return
	end
	self.count += 1
	local entry = { name = name, score = final }
	self.options[self.count] = entry
	self.byName[name] = entry
end

-- clear(utility) -> ()
function UtilityAI:clear(): ()
	for i = 1, self.count do
		self.options[i] = nil
	end
	self.byName = {}
	self.count = 0
end

-- score(utility, name) -> number?
function UtilityAI:score(name: any): number?
	local entry = self.byName[name]
	if entry == nil then
		return nil
	end
	return entry.score
end

-- best(utility) -> name?, score?
-- Deterministic argmax. Ties resolve to the lowest index, so identical inputs
-- always produce the same action (important for replaying a decision dump).
function UtilityAI:best(): (any, number?)
	local bestEntry = nil
	for i = 1, self.count do
		local entry = self.options[i]
		if entry and (bestEntry == nil or entry.score > bestEntry.score) then
			bestEntry = entry
		end
	end
	if bestEntry == nil then
		return nil, nil
	end
	return bestEntry.name, bestEntry.score
end

-- select(utility, rng, temperature?) -> name?
-- Boltzmann selection. temperature <= 0 collapses to argmax.
-- The max is subtracted before the exponential so large score magnitudes cannot
-- overflow to inf and silently make the distribution degenerate.
function UtilityAI:select(rng: any, temperature: number?): any
	if self.count == 0 then
		return nil
	end
	if self.count == 1 then
		return self.options[1].name
	end

	local temp = temperature or 1
	if temp <= 0 then
		return self:best()
	end

	local maxScore = -math.huge
	for i = 1, self.count do
		local s = self.options[i].score
		if s > maxScore then
			maxScore = s
		end
	end

	local total = 0
	for i = 1, self.count do
		local e = math.exp((self.options[i].score - maxScore) / temp)
		self.options[i]._p = e
		total += e
	end
	if total <= 0 then
		return self:best()
	end

	local roll = rng:next() * total
	local acc = 0
	for i = 1, self.count do
		acc += self.options[i]._p
		if roll <= acc then
			local name = self.options[i].name
			self.options[i]._p = nil
			return name
		end
	end
	return self.options[self.count].name
end

-- selectWithBonus(utility, rng, temperature, bonusFor) -> name?
-- Same as select but adds `bonusFor(name)` to each score before the softmax.
-- Policy uses this to fold in the genome's instinct prior and the learned Q
-- without mutating the utility scores themselves (docs/02 §6.2).
function UtilityAI:selectWithBonus(rng: any, temperature: number?, bonusFor: any?): any
	if self.count == 0 then
		return nil
	end
	local temp = temperature or 1
	if temp <= 0 or bonusFor == nil then
		if bonusFor == nil then
			return self:select(rng, temp)
		end
		local bestName, bestScore = nil, -math.huge
		for i = 1, self.count do
			local entry = self.options[i]
			local s = entry.score + (bonusFor(entry.name) or 0)
			if s > bestScore then
				bestName, bestScore = entry.name, s
			end
		end
		return bestName
	end

	local maxScore = -math.huge
	for i = 1, self.count do
		local entry = self.options[i]
		entry._p = entry.score + (bonusFor(entry.name) or 0)
		if entry._p > maxScore then
			maxScore = entry._p
		end
	end

	local total = 0
	for i = 1, self.count do
		local entry = self.options[i]
		entry._p = math.exp((entry._p - maxScore) / temp)
		total += entry._p
	end
	if total <= 0 then
		return self:best()
	end

	local roll = rng:next() * total
	local acc = 0
	for i = 1, self.count do
		local entry = self.options[i]
		acc += entry._p
		if roll <= acc then
			local name = entry.name
			entry._p = nil
			return name
		end
	end
	local last = self.options[self.count]
	local name = last.name
	last._p = nil
	return name
end

return UtilityAI
