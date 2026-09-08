--!strict
-- MarkovPredictor.luau
-- Location: ReplicatedStorage > Vitriol > Lib > MarkovPredictor  (ModuleScript)
-- Purpose:  First-order Markov model of a player's behaviour transitions. This is
--           what lets the creature intercept instead of chase, and the
--           "predictability" score that rewards players for varying their routine
--           (docs/02-MONSTER-DESIGN.md §4).
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Creature/Brain/Predictor

local MarkovPredictor = {}
MarkovPredictor.__index = MarkovPredictor

-- new(nStates) -> MarkovPredictor
-- States are 1..nStates integers. For Vitriol a state is
-- LocationClass x PostureClass (8 x 6 = 48), so the full matrix is 2304 counts.
function MarkovPredictor.new(nStates: number)
	local self = setmetatable({}, MarkovPredictor)
	self.nStates = nStates or 1
	self.rows = {} -- rows[from] = { [to] = count }
	self.totals = {} -- totals[from] = sum of counts
	self.observations = 0
	return self
end

-- observe(predictor, from, to) -> ()
function MarkovPredictor:observe(from: number, to: number): ()
	if from < 1 or from > self.nStates or to < 1 or to > self.nStates then
		return
	end
	local row = self.rows[from]
	if row == nil then
		row = {}
		self.rows[from] = row
		self.totals[from] = 0
	end
	row[to] = (row[to] or 0) + 1
	self.totals[from] += 1
	self.observations += 1
end

-- count(predictor, from, to) -> number
function MarkovPredictor:count(from: number, to: number): number
	local row = self.rows[from]
	if row == nil then
		return 0
	end
	return row[to] or 0
end

-- probability(predictor, from, to) -> number
function MarkovPredictor:probability(from: number, to: number): number
	local total = self.totals[from]
	if not total or total == 0 then
		return 0
	end
	return self:count(from, to) / total
end

-- observationsFrom(predictor, from) -> number
function MarkovPredictor:observationsFrom(from: number): number
	return self.totals[from] or 0
end

-- predict(predictor, from, k) -> { {state=, p=}, ... } sorted by p descending
-- Ties break toward the LOWER state index so the result is deterministic and a
-- decision dump can be replayed exactly.
--
-- Allocates the result table. Callers run this on the Think cadence (4-8 Hz),
-- never per frame.
function MarkovPredictor:predict(from: number, k: number?): any
	local out = {}
	local total = self.totals[from]
	if not total or total == 0 then
		return out
	end
	local row = self.rows[from]
	local want = k or 3
	if want > self.nStates then
		want = self.nStates
	end

	-- Copy the row so we can consume it without mutating the model.
	local pending = {}
	local n = 0
	for to, c in pairs(row) do
		n += 1
		pending[n] = { state = to, p = c / total }
	end

	for _ = 1, want do
		local bestIdx = 0
		local bestP = -1
		local bestState = math.huge
		for i = 1, n do
			local cand = pending[i]
			if cand then
				if cand.p > bestP or (cand.p == bestP and cand.state < bestState) then
					bestIdx, bestP, bestState = i, cand.p, cand.state
				end
			end
		end
		if bestIdx == 0 then
			break
		end
		out[#out + 1] = pending[bestIdx]
		pending[bestIdx] = nil
	end
	return out
end

-- entropy(predictor, from) -> number (nats)
-- Shannon entropy of the transition row. 0 = perfectly predictable.
function MarkovPredictor:entropy(from: number): number
	local total = self.totals[from]
	if not total or total == 0 then
		return 0
	end
	local row = self.rows[from]
	local h = 0
	for _, c in pairs(row) do
		local p = c / total
		if p > 0 then
			h -= p * math.log(p)
		end
	end
	return h
end

-- predictability(predictor, from) -> number in [0, 1]
-- 1 - H / H_max. A player who always does the same thing scores near 1 and gets
-- ambushed; one who varies scores low and forces the creature to search.
-- Returns 0 when there is not enough data to say anything.
function MarkovPredictor:predictability(from: number): number
	local total = self.totals[from]
	if not total or total < 2 then
		return 0
	end
	local row = self.rows[from]
	local distinct = 0
	for _, c in pairs(row) do
		if c > 0 then
			distinct += 1
		end
	end
	if distinct <= 1 then
		return 1
	end
	local hMax = math.log(distinct)
	if hMax <= 0 then
		return 0
	end
	local p = 1 - (self:entropy(from) / hMax)
	if p < 0 then
		return 0
	elseif p > 1 then
		return 1
	end
	return p
end

-- serialize(predictor) -> table
function MarkovPredictor:serialize(): any
	local rows = {}
	for from, row in pairs(self.rows) do
		local copy = {}
		for to, c in pairs(row) do
			copy[to] = c
		end
		rows[from] = copy
	end
	return {
		nStates = self.nStates,
		rows = rows,
		totals = self.totals,
		observations = self.observations,
	}
end

-- deserialize(data) -> MarkovPredictor
function MarkovPredictor.deserialize(data: any): any
	local self = MarkovPredictor.new(data.nStates or 1)
	if data.rows then
		for from, row in pairs(data.rows) do
			local copy = {}
			for to, c in pairs(row) do
				copy[to] = c
			end
			self.rows[from] = copy
		end
	end
	if data.totals then
		for from, t in pairs(data.totals) do
			self.totals[from] = t
		end
	end
	self.observations = data.observations or 0
	return self
end

-- reset(predictor) -> ()
function MarkovPredictor:reset(): ()
	self.rows = {}
	self.totals = {}
	self.observations = 0
end

return MarkovPredictor
