--!strict
-- CreatureMemory.luau
-- Location: ReplicatedStorage > Vitriol > Shared > CreatureMemory  (ModuleScript)
-- Purpose:  Bounded, allocation-conscious evidence records for one creature.
--           Working memory, last-known position, source channel, age and
--           confidence decay live here. Spatial interest cells and a first-order
--           Markov predictor (location x posture) live here too.
--
--           WHY SHARED, NOT Brain/Memory. docs/01 parks Memory under
--           Creature/Brain, but this module is pure math/data: no Instances, no
--           yields, no Players. Putting it in Shared lets the smoke harness
--           execute it the same way it executes NoiseField, and keeps DataModel
--           access in server services (the stimulus bridge and the kill authority).
-- Requires: Lib/{SpatialHash,MarkovPredictor,Tables}
-- Used by:  Creature/Brain/{Senses,Steering}, Services/CreatureService
--
--           There is no SIGHT channel. observe() refuses it.

local SpatialHash = require(script.Parent.Parent.Lib.SpatialHash)
local MarkovPredictor = require(script.Parent.Parent.Lib.MarkovPredictor)
local Tables = require(script.Parent.Parent.Lib.Tables)

local CreatureMemory = {}
CreatureMemory.__index = CreatureMemory

CreatureMemory.FORBIDDEN = { SIGHT = true, Sight = true, vision = true, VISION = true }

local function clamp01(value: number): number
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

local function defaultMemory(cfg: any): any
	return cfg or {
		WorkingCapacity = 12,
		CellSize = 8,
		Interest = { Kill = 1.0, Grab = 0.6, PreyPerceived = 0.25, LoudNoise = 0.15 },
		InterestDecayHalfLife = 90,
		TimeHeatmapBuckets = 6,
		EvidenceHalfLife = 4.5,
		LastKnownMaxAgeSeconds = 14,
		SearchWanderRadius = 16,
		PatrolRadius = 22,
		ConfidenceFloor = 0.08,
	}
end

-- new(monsterOrMemory, prediction?) -> CreatureMemory
-- Accepts either MonsterConfig (with .Memory / .Prediction) or a Memory table.
function CreatureMemory.new(monster: any, prediction: any?)
	local self = setmetatable({}, CreatureMemory)
	local mem = defaultMemory(monster and monster.Memory or monster)
	local pred = prediction or (monster and monster.Prediction) or {
		LocationClasses = { "Open", "Road", "House", "Garage", "Basement", "Roof", "Woods", "Water" },
		PostureClasses = { "Idle", "Scavenging", "Fleeing", "Hiding", "Driving", "Fighting" },
		MinObservations = 12,
		PredictabilityHigh = 0.60,
		PredictabilityLow = 0.30,
		MinProbabilityToIntercept = 0.50,
	}
	self.Memory = mem
	self.Prediction = pred
	self.capacity = mem.WorkingCapacity or 12
	self.halfLife = mem.EvidenceHalfLife or 4.5
	self.floor = mem.ConfidenceFloor or 0.08
	self.lastKnownMaxAge = mem.LastKnownMaxAgeSeconds or 14
	self.searchWander = mem.SearchWanderRadius or 16
	self.patrolRadius = mem.PatrolRadius or 22
	self.interestWeights = mem.Interest or {}
	self.interestHalfLife = mem.InterestDecayHalfLife or 90

	self.working = {}
	self.count = 0
	self.next = 1
	for i = 1, self.capacity do
		self.working[i] = {
			channel = nil,
			x = 0,
			y = 0,
			z = 0,
			confidence = 0,
			confidence0 = 0,
			time = 0,
			intensity = 0,
			age = 0,
		}
	end

	self.lastKnown = {
		channel = nil,
		x = 0,
		y = 0,
		z = 0,
		confidence = 0,
		time = -1e9,
		exact = false,
	}

	self.interest = SpatialHash.new(mem.CellSize or 8)
	self.interestNext = 0
	self.interestPool = Tables.newPool(function()
		return { score = 0, time = 0 }
	end, 8)

	self.locations = pred.LocationClasses
	self.postures = pred.PostureClasses
	self.nLoc = #self.locations
	self.nPos = #self.postures
	self.nStates = self.nLoc * self.nPos
	self.locIndex = {}
	self.posIndex = {}
	for i = 1, self.nLoc do
		self.locIndex[self.locations[i]] = i
	end
	for i = 1, self.nPos do
		self.posIndex[self.postures[i]] = i
	end
	self.predictor = MarkovPredictor.new(self.nStates)
	self.minObservations = pred.MinObservations or 12
	self.predictabilityHigh = pred.PredictabilityHigh or 0.60
	self.predictabilityLow = pred.PredictabilityLow or 0.30
	self.minProbabilityToIntercept = pred.MinProbabilityToIntercept or 0.50
	self.lastFrom = nil
	return self
end

function CreatureMemory.hasSight(): boolean
	return false
end

function CreatureMemory:hasChannel(channel: any): boolean
	if channel == nil or CreatureMemory.FORBIDDEN[channel] then
		return false
	end
	return true
end

-- observe(memory, channel, x, y, z, confidence, now, intensity?) -> boolean
-- False for a forbidden (sight) channel or non-positive confidence.
function CreatureMemory:observe(channel: any, x: number, y: number, z: number, confidence: number, now: number, intensity: number?): boolean
	if not self:hasChannel(channel) then
		return false
	end
	local conf = clamp01(confidence or 0)
	if conf <= 0 then
		return false
	end
	local slot = self.working[self.next]
	slot.channel = channel
	slot.x = x
	slot.y = y
	slot.z = z
	slot.confidence = conf
	slot.confidence0 = conf
	slot.time = now or 0
	slot.intensity = intensity or conf
	slot.age = 0
	self.next = self.next + 1
	if self.next > self.capacity then
		self.next = 1
	end
	if self.count < self.capacity then
		self.count = self.count + 1
	end
	if self.lastKnown.channel == nil or conf >= self.lastKnown.confidence then
		self.lastKnown.channel = channel
		self.lastKnown.x = x
		self.lastKnown.y = y
		self.lastKnown.z = z
		self.lastKnown.confidence = conf
		self.lastKnown.time = now or 0
		self.lastKnown.exact = true
	end
	self:addInterest(x, y, z, "PreyPerceived", now or 0)
	return true
end

-- decay(memory, now) -> ()
-- Exponential confidence decay on working records. Does NOT reimplement field
-- advection; last-known stays put until LastKnownMaxAgeSeconds, then is cleared.
function CreatureMemory:decay(now: number): ()
	local t = now or 0
	local bestConf = -1
	local best = nil
	for i = 1, self.count do
		local slot = self.working[i]
		if slot.channel ~= nil then
			local age = t - slot.time
			if age < 0 then
				age = 0
			end
			slot.age = age
			local factor = 1
			if self.halfLife > 0 then
				factor = 0.5 ^ (age / self.halfLife)
			end
			slot.confidence = slot.confidence0 * factor
			if slot.confidence < self.floor then
				slot.channel = nil
				slot.confidence = 0
			elseif slot.confidence > bestConf then
				bestConf = slot.confidence
				best = slot
			end
		end
	end
	if best == nil then
		self.lastKnown.exact = false
		if t - self.lastKnown.time > self.lastKnownMaxAge then
			self.lastKnown.channel = nil
			self.lastKnown.confidence = 0
			self.lastKnown.exact = false
		end
	else
		self.lastKnown.channel = best.channel
		self.lastKnown.x = best.x
		self.lastKnown.y = best.y
		self.lastKnown.z = best.z
		self.lastKnown.confidence = best.confidence
		self.lastKnown.time = best.time
		self.lastKnown.exact = true
	end
end

-- best(memory, now?) -> record?
function CreatureMemory:best(_now: number?): any
	local bestConf = self.floor
	local best = nil
	for i = 1, self.count do
		local slot = self.working[i]
		if slot.channel ~= nil and slot.confidence > bestConf then
			bestConf = slot.confidence
			best = slot
		end
	end
	return best
end

-- lastKnownRecord(memory) -> record
function CreatureMemory:lastKnownRecord(): any
	return self.lastKnown
end

function CreatureMemory:hasLastKnown(now: number): boolean
	if self.lastKnown.channel == nil then
		return false
	end
	return (now - self.lastKnown.time) <= self.lastKnownMaxAge
end

function CreatureMemory:lastKnownAge(now: number): number
	if self.lastKnown.channel == nil then
		return math.huge
	end
	local age = now - self.lastKnown.time
	if age < 0 then
		return 0
	end
	return age
end

function CreatureMemory:addInterest(x: number, y: number, z: number, kind: any, now: number): ()
	local weight = self.interestWeights[kind] or self.interestWeights.LoudNoise or 0.15
	self.interestNext = self.interestNext + 1
	local entry = self.interestPool:get()
	entry.score = weight
	entry.time = now
	entry.halflife = self.interestHalfLife
	entry.intensity = weight
	self.interest:insert(self.interestNext, x, y, z, entry)
end

function CreatureMemory:interestAt(x: number, y: number, z: number, now: number): number
	return self.interest:sampleDecay(x, y, z, (self.Memory.CellSize or 8) * 1.5, now)
end

-- stateIndex(memory, locationClass, postureClass) -> number
function CreatureMemory:stateIndex(locationClass: any, postureClass: any): number
	local loc = self.locIndex[locationClass] or 1
	local pos = self.posIndex[postureClass] or 1
	return (loc - 1) * self.nPos + pos
end

function CreatureMemory:observeTransition(fromState: number, toState: number): ()
	self.predictor:observe(fromState, toState)
	self.lastFrom = toState
end

function CreatureMemory:observeTagged(locationClass: any, postureClass: any): ()
	local toState = self:stateIndex(locationClass, postureClass)
	if self.lastFrom ~= nil then
		self.predictor:observe(self.lastFrom, toState)
	end
	self.lastFrom = toState
end

function CreatureMemory:predict(fromState: number, k: number?): any
	if self.predictor.observations < self.minObservations then
		return {}
	end
	return self.predictor:predict(fromState, k or 3)
end

function CreatureMemory:predictability(fromState: number): number
	return self.predictor:predictability(fromState)
end

function CreatureMemory:canIntercept(fromState: number): boolean
	if self.predictor.observations < self.minObservations then
		return false
	end
	if self:predictability(fromState) < self.predictabilityHigh then
		return false
	end
	local ranked = self.predictor:predict(fromState, 1)
	if ranked[1] == nil then
		return false
	end
	return ranked[1].p >= self.minProbabilityToIntercept
end

function CreatureMemory:snapshot(): any
	local best = self:best()
	return {
		count = self.count,
		bestChannel = best and best.channel or nil,
		bestConfidence = best and best.confidence or 0,
		lastKnownExact = self.lastKnown.exact,
		lastKnownChannel = self.lastKnown.channel,
		observations = self.predictor.observations,
		hasSight = false,
	}
end

return CreatureMemory
