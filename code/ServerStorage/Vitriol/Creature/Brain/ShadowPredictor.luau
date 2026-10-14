--!strict
-- M3 observation-only location model. Tagged, AUTHORED ZoneClass Parts are
-- classified only after the existing sensory check succeeds. No hidden-player
-- GPS, posture guess, path target, Q-learning, added cadence or Instance.
local ShadowPredictor = {}
ShadowPredictor.__index = ShadowPredictor
function ShadowPredictor.new(config: any, map: any, markov: any, tagService: any?): any
	local cfg=config or {}
	local tags=tagService or game:GetService("CollectionService")
	local classes=cfg.LocationClasses or {}
	local indices={}
	for i=1,#classes do indices[classes[i]]=i end
	local zones={}
	local folder=map and map:FindFirstChild("Zones")
	if folder then
		for _,part in ipairs(folder:GetChildren()) do
			if part:IsA("BasePart") and tags:HasTag(part,"Vitriol_Zone") then
				local class=part:GetAttribute("ZoneClass")
				local o=part.Orientation
				if indices[class] and o and math.abs(o.X)<0.01
					and math.abs(o.Y)<0.01 and math.abs(o.Z)<0.01 then
					local p,s=part.Position,part.Size
					zones[#zones+1]={id=indices[class],name=part.Name,
						x=p.X,y=p.Y,z=p.Z,hx=s.X*0.5,hy=s.Y*0.5,hz=s.Z*0.5,
						volume=s.X*s.Y*s.Z}
				end
			end
		end
	end
	return setmetatable({Config=cfg,Classes=classes,Zones=zones,Markov=markov,
		Observed={},Models={},Transitions=0},ShadowPredictor)
end
function ShadowPredictor:classAt(x: number, y: number, z: number): number?
	local best,size=nil,math.huge
	for i=1,#self.Zones do
		local v=self.Zones[i]
		if math.abs(x-v.x)<=v.hx and math.abs(y-v.y)<=v.hy
			and math.abs(z-v.z)<=v.hz and v.volume<size then
			best,size=v.id,v.volume -- smaller specific zones win overlaps
		end
	end
	return best
end
-- Called ONLY with the already-sensed nearest living prey. Sampling once per
-- real second avoids per-Think region scans and repeated same-zone training.
-- A long unseen gap NEVER fabricates a transition across hidden positions.
function ShadowPredictor:observe(userId: number, x: number, y: number, z: number, now: number): boolean
	if userId == nil or #self.Zones == 0 then return false end
	local previous=self.Observed[userId]
	if previous then previous.sensed=true end -- a throttled sample is still a real sighting
	if previous and now-previous.at < 1 then return false end
	local class=self:classAt(x,y,z)
	local transitioned=false
	if previous and previous.connected and class and previous.class and class~=previous.class
		and now-previous.at <= 3 then
		local model=self.Models[userId]
		if not model then
			model=self.Markov.new(#self.Classes)
			self.Models[userId]=model
		end
		model:observe(previous.class,class)
		self.Transitions+=1
		transitioned=true
	end
	if previous then
		previous.class,previous.at,previous.connected=class,now,true
	else
		self.Observed[userId]={class=class,at=now,connected=true,sensed=true}
	end
	return transitioned
end
function ShadowPredictor:markUnseenExcept(userId: number?): ()
	for id,observation in pairs(self.Observed) do
		if id ~= userId then observation.connected=false;observation.sensed=false end
	end
end
function ShadowPredictor:forget(userId: number): ()
	self.Observed[userId]=nil
	self.Models[userId]=nil -- no unbounded churn of disconnected players
end
-- Read-only, deliberately on-demand; Markov prediction allocates ONLY here.
-- This cannot authorize steering or interception: 8 location classes are not
-- the authored 48 location×posture states and are not positions.
function ShadowPredictor:dump(): any
	local out={mode="observation-only",steers=false,postureObserved=false,
		authoredZoneCount=#self.Zones,transitions=self.Transitions,players={}}
	for userId,observation in pairs(self.Observed) do
		local model=self.Models[userId]
		local row=model and observation.class and model:observationsFrom(observation.class) or 0
		-- A learned row is historical evidence, NOT a current location while
		-- the player is hidden. Withhold even well-trained guesses until sensed.
		local trusted=observation.sensed and row >= (self.Config.MinObservations or 12)
		local top=nil
		if trusted then
			local guesses=model:predict(observation.class,2)
			top={}
			for i=1,#guesses do
				local guess=guesses[i]
				top[i]={class=self.Classes[guess.state],probability=guess.p}
			end
		end
		out.players[#out.players+1]={userId=userId,currentlySensed=observation.sensed,
				lastClass=observation.class and self.Classes[observation.class] or nil,
				lastSampleAt=observation.at, -- historical, not a hidden live position
				observationsFromLastClass=row,trusted=trusted,
				predictability=trusted and model:predictability(observation.class) or nil,
				possibleNextClasses=top}
	end
	return out
end
return ShadowPredictor
