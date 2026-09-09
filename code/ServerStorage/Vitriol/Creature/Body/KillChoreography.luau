--!strict
-- KillChoreography.luau
-- Location: ServerStorage > Vitriol > Creature > Body > KillChoreography (ModuleScript)
-- Purpose:  Small interruptible, cadence-stepped victim scene. It owns no Roblox
--           Instances and never applies damage itself; HealthService remains the
--           single writer of Humanoid health. The optional sever callback is the only
--           limb-presentation seam, and LOW BloodConfig can leave it disabled.
-- Requires: timing/config tables injected by HealthService
-- Used by:  Services/HealthService

local KillChoreography = {}
KillChoreography.__index = KillChoreography

local ORDER = { "GRAB", "LIFT", "COIL", "TENDERIZE", "CONSUME", "DISCARD" }
local TIMING_KEY = {
	GRAB = "Grab",
	LIFT = "Lift",
	COIL = "Coil",
	TENDERIZE = "Tenderize",
	CONSUME = "Consume",
	DISCARD = "Discard",
}

local function durationFor(timings: any, phase: string, fallback: number): number
	local value = timings and (timings[TIMING_KEY[phase] or phase] or timings[phase])
	if type(value) == "table" then
		return value.max or value.min or fallback
	elseif type(value) == "number" then
		return value
	end
	return fallback
end

function KillChoreography.new(options: any?): any
	local o = options or {}
	local self = setmetatable({}, KillChoreography)
	self.VictimUserId = o.VictimUserId
	self.CreatureId = o.CreatureId
	self.Timings = o.Timings or {}
	self.Duration = o.Duration or 5.8
	self.Dismemberment = o.Dismemberment == true
	self.OnPhase = o.OnPhase
	self.OnSever = o.OnSever
	self.OnComplete = o.OnComplete
	self.OnInterrupt = o.OnInterrupt
	self.PhaseIndex = 1
	self.Phase = ORDER[1]
	self.PhaseElapsed = 0
	self.Elapsed = 0
	self.Done = false
	self.Interrupted = false
	self.DidSever = false
	self:emitPhase(self.Phase)
	return self
end

function KillChoreography:emitPhase(phase: string): ()
	self.Phase = phase
	self.PhaseElapsed = 0
	if self.OnPhase then
		self.OnPhase(phase, self)
	end
end

function KillChoreography:nextPhase(): ()
	self.PhaseIndex = self.PhaseIndex + 1
	if self.PhaseIndex > #ORDER then
		self.Done = true
		if self.OnComplete then
			self.OnComplete(self)
		end
		return
	end
	self:emitPhase(ORDER[self.PhaseIndex])
end

function KillChoreography:step(dt: number): ()
	if self.Done or self.Interrupted then
		return
	end
	local remaining = math.max(dt, 0)
	self.Elapsed = self.Elapsed + remaining
	while remaining > 0 and not self.Done and not self.Interrupted do
		local phaseDuration = durationFor(self.Timings, self.Phase, self.Duration / #ORDER)
		-- The configured scene duration is an upper bound. If the supplied Gore
		-- timing table is longer, proportionally scale the scene at construction
		-- time through the final phase instead of allowing an unbounded hold.
		if self.Elapsed >= self.Duration then
			phaseDuration = math.min(phaseDuration, math.max(self.Duration - (self.Elapsed - remaining), 0))
		end
		local untilPhase = phaseDuration - self.PhaseElapsed
		if untilPhase <= 0 then
			self:nextPhase()
		else
			local consumed = math.min(remaining, untilPhase)
			self.PhaseElapsed = self.PhaseElapsed + consumed
			remaining = remaining - consumed
		end
		if self.Phase == "TENDERIZE" and self.Dismemberment and not self.DidSever and self.PhaseElapsed >= phaseDuration * 0.5 then
			self.DidSever = true
			if self.OnSever then
				self.OnSever("LeftArm", self)
			end
		end
		if self.Elapsed >= self.Duration and not self.Done then
			-- Complete at the next cadence boundary; this keeps the whole scene
			-- deterministic and gives the camera a final frame.
			self.PhaseIndex = #ORDER
			self.Phase = ORDER[#ORDER]
			self.PhaseElapsed = durationFor(self.Timings, self.Phase, 0)
			self:nextPhase()
		end
	end
end

function KillChoreography:interrupt(reason: string?): ()
	if self.Done or self.Interrupted then
		return
	end
	self.Interrupted = true
	if self.OnInterrupt then
		self.OnInterrupt(reason or "interrupted", self)
	end
end

function KillChoreography:isDone(): boolean
	return self.Done or self.Interrupted
end

function KillChoreography:snapshot(): any
	return {
		victimUserId = self.VictimUserId,
		creatureId = self.CreatureId,
		phase = self.Phase,
		elapsed = self.Elapsed,
		done = self.Done,
		interrupted = self.Interrupted,
	}
end

return KillChoreography
