--!strict
-- M6 pure collapse onset/fall contract. Not a NoiseField, Humanoid or UI driver.
-- A future server service must verify eligibility, enforce movement/ragdoll,
-- and CONSUME the fall event using an authored player's current position.
-- Recovery after the eight-second crawl remains a separate design decision;
-- the sequence deliberately holds instead of secretly restoring controls.
local SurvivalCollapse={}
SurvivalCollapse.__index=SurvivalCollapse
local EPS=1e-9 -- avoid leaving an onset in float dust after a split tick

local function finite(v: any): boolean
	return type(v)=="number" and v==v and v>-math.huge and v<math.huge
end

function SurvivalCollapse.new(config: any): any
	assert(config and finite(config.OnsetDelaySeconds) and config.OnsetDelaySeconds>0
		and finite(config.CrawlDurationSeconds) and config.CrawlDurationSeconds>0
		and finite(config.FallVibrationIntensity)
		and config.FallVibrationIntensity>=0 and config.FallVibrationIntensity<=1,
		"[Vitriol.Survival] collapse timing and vibration must be authored")
	return setmetatable({config=config,phase="Idle",onsetLeft=0,crawlLeft=0,
		fallPending=false},SurvivalCollapse)
end

-- eligible is an authoritative SERVER verdict: the living player's Model
-- reports collapseCandidate using HealthService HP. Not a client command.
function SurvivalCollapse:begin(eligible: boolean): boolean
	if eligible~=true or self.phase~="Idle" then return false end
	self.phase="Onset"
	self.onsetLeft=self.config.OnsetDelaySeconds
	return true
end

-- No side effects. Keeps the event pending even if a caller advances straight
-- through onset and the entire crawl window in one long, valid step.
function SurvivalCollapse:advance(dt: number): (any?,string?)
	if not finite(dt) or dt<0 or dt>3600 then return nil,"invalid-dt" end
	local remaining=dt
	if self.phase=="Onset" then
		local used=math.min(remaining,self.onsetLeft)
		self.onsetLeft=self.onsetLeft-used
		remaining=remaining-used
		if self.onsetLeft<=EPS then
			self.onsetLeft=0
			self.phase="Crawl"
			self.crawlLeft=self.config.CrawlDurationSeconds
			self.fallPending=true
		end
	end
	if self.phase=="Crawl" and remaining>0 then
		self.crawlLeft=math.max(0,self.crawlLeft-remaining)
		if self.crawlLeft<=EPS then self.crawlLeft=0;self.phase="Hold" end
	end
	return {phase=self.phase,onsetLeft=self.onsetLeft,crawlLeft=self.crawlLeft,
		fallPending=self.fallPending},nil
end

-- A disconnected/despawned body must not emit a delayed noise from the NEXT
-- body after reconnect. This drops only the physical event; it does NOT reset
-- the collapse phase or decide the still-open recovery/life policy.
function SurvivalCollapse:cancelPendingFall(): boolean
	local pending=self.fallPending
	self.fallPending=false
	return pending
end

-- At-most-once retrieval of the authored noise request. No emission here.
-- A caller must NOT treat the returned data as a client-authorized event.
function SurvivalCollapse:takeFall(): any?
	if not self.fallPending then return nil end
	self.fallPending=false
	return {channel="VIBRATION",intensity=self.config.FallVibrationIntensity}
end

return SurvivalCollapse
