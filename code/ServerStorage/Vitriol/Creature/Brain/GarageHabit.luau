--!strict
-- M3 instinct-only habit: remember REAL witnessed Garage entries, then
-- investigate its authored front approach before a clue-less local patrol.
-- No unseen player's position, Q weights, global search, runtime Instance or
-- extra cadence. Only the existing service may feed already-SENSED prey.
local GarageHabit = {}
GarageHabit.__index = GarageHabit
local function square(dx: number, dz: number): number
	return dx*dx+dz*dz
end
function GarageHabit.new(config: any, navigation: any, searchConfig: any?): any
	local garage = navigation and navigation.Garage
	local floor = garage and garage:FindFirstChild("Floor")
	local roof = garage and garage:FindFirstChild("Roof")
	local entrance = navigation and navigation.Nodes and navigation.Nodes[1]
	local present = floor and floor:IsA("BasePart") and entrance ~= nil
	local ceilingY = present and floor.Position.Y+14 or nil
	if present and roof and roof:IsA("BasePart") then
		ceilingY=roof.Position.Y-roof.Size.Y*0.5-2
	end
	local o = setmetatable({Config=config or {},SearchConfig=searchConfig or {},Floor=present and floor or nil,
		Entrance=present and entrance or nil,
		Interior=present and {floor.Position.X,floor.Position.Z} or nil,
		CoreCeilingY=ceilingY,
		Visits=0,PredictionMisses=0,Evidence=0,ObservedInside={}},GarageHabit)
	return o
end
function GarageHabit:inside(x: number, y: number, z: number): boolean
	local floor=self.Floor
	if not floor then return false end
	local p,s=floor.Position,floor.Size
	-- A roof-level player is not a Garage floor visit. The inset excludes
	-- footprints at the outside threshold; never count a nearby road crossing.
	return math.abs(x-p.X) <= s.X*0.5-2 and math.abs(z-p.Z) <= s.Z*0.5-2
		and y >= p.Y-1 and y <= p.Y+8
end
function GarageHabit:observe(userId: number, x: number, y: number, z: number): boolean
	if not self.Floor or userId == nil then return false end
	local floorY=self.Floor.Position.Y
	if y < floorY-1 or y > floorY+8 then
		-- A roof-level sighting is not an OUTSIDE ground-level witness.
		-- Nor can it bridge an earlier ground sighting to a later entry.
		self.ObservedInside[userId]=nil
		return false
	end
	local inside=self:inside(x,y,z)
	local previous=self.ObservedInside[userId]
	self.ObservedInside[userId]=inside
	if inside and previous == false then
		local cap=self.Config.WorkingCapacity or 12
		self.Visits=math.min(self.Visits+1,cap)
		self.Evidence=math.min(self.Evidence+1,self.Config.GarageVisitsForPrediction or 3)
		return true
	end
	return false
end
-- The service calls this after EACH Think. If sight/thermal lost a player,
-- their old exterior sample cannot turn a later reacquisition inside into a
-- witnessed visit. This also handles a nearer player taking sensory priority.
function GarageHabit:markUnseenExcept(userId: number?): ()
	for id in pairs(self.ObservedInside) do
		if id ~= userId then self.ObservedInside[id]=nil end
	end
end
function GarageHabit:forget(userId: number): ()
	self.ObservedInside[userId]=nil
end
-- A real prey/lure/last-known/noise/roof-recovery goal can move the Braid
-- away while lead() is not called. Never reuse a cached flank/front/interior
-- clearance ray after higher-priority movement; revalidate on return.
function GarageHabit:interrupt(creature: any): ()
	local state=creature.HabitState
	if state=="front" or state=="inside" or state=="flankWest" or state=="flankEast" then
		creature.HabitState="pending"
	end
end
-- Two short, PHYSICALLY TESTED legs: front approach, then inside floor.
-- Never conclude an unseen room is empty merely from reaching its exterior.
-- At most one NEW ray per call; held targets cost none. All obstruction paths
-- return to the already-approved Night search instead of wall phasing.
function GarageHabit:lead(creature: any, now: number, night: number, navigation: any?, cover: any?): (number?,number?,string?)
	local entrance,interior=self.Entrance,self.Interior
	-- Bounded confidence still learns when visit/miss counters saturate.
	if not entrance or not interior or self.Evidence < (self.Config.GarageVisitsForPrediction or 3) then
		return nil,nil,nil
	end
	if creature.HabitNight ~= night then
		creature.HabitNight,creature.HabitState=night,nil
	end
	-- A planar Garage ray never proves a ROOF-level core entered the room.
	-- Without the navigation sensor, the prediction has no physical authority.
	if creature.Y >= self.CoreCeilingY or not navigation or not navigation.clear then
		creature.HabitState="blocked"
		return nil,nil,"blocked"
	end
	local state=creature.HabitState
	if state == "arrived" or state == "blocked" then return nil,nil,nil end
	local age=creature.SearchClueAt and now-creature.SearchClueAt or math.huge
	if age >= 0 and age <= (self.SearchConfig.ClueSeconds or 25) then
		if state == "front" or state == "inside" or state == "flankWest" or state == "flankEast" then
			creature.HabitState="pending"
		end
		return nil,nil,nil
	end
	local arriveSq=(self.Config.GarageLeadArriveStuds or 10)^2
	if state == "front" and square(entrance[1]-creature.X,entrance[2]-creature.Z)<=arriveSq then
		state="pendingInside"
		creature.HabitState=state
	end
	if state == "flankWest" or state == "flankEast" then
		local gx,gz=creature.HabitGoalX,creature.HabitGoalZ
		if not gx or not gz then
			creature.HabitState="blocked"
			return nil,nil,"blocked"
		end
		if square(gx-creature.X,gz-creature.Z)<=arriveSq then
			state=state == "flankWest" and "pendingFlankEast" or "pendingFront"
			creature.HabitState=state
		end
	end
	if state == "inside" and square(interior[1]-creature.X,interior[2]-creature.Z)<=arriveSq then
		-- A soft failed prediction ONLY after entering the actual Garage.
		-- This is not proof no hidden survivor exists; local search continues.
		self.PredictionMisses=math.min(self.PredictionMisses+1,self.Config.WorkingCapacity or 12)
		self.Evidence=math.max(0,self.Evidence-1)
		creature.HabitState="arrived"
		return nil,nil,"arrived"
	end
	if state == "front" or state == "inside" or state == "flankWest" or state == "flankEast" then
		local px,pz=creature.HabitProgressX or creature.X,creature.HabitProgressZ or creature.Z
		if square(creature.X-px,creature.Z-pz)>=1 then
			creature.HabitProgressX,creature.HabitProgressZ,creature.HabitProgressAt=creature.X,creature.Z,now
		elseif now-(creature.HabitProgressAt or now) >= (self.SearchConfig.StallSeconds or 3) then
			creature.HabitState="blocked"
			return nil,nil,"blocked"
		end
		if state == "front" then return entrance[1],entrance[2],"witnessed-three-garage-entries" end
		if state == "inside" then return interior[1],interior[2],"physical-garage-investigation" end
		return creature.HabitGoalX,creature.HabitGoalZ,"witnessed-garage-flank"
	end
	local floor=self.Floor
	local p,s=floor.Position,floor.Size
	local insideFootprint=math.abs(creature.X-p.X)<=s.X*0.5-2
		and math.abs(creature.Z-p.Z)<=s.Z*0.5-2
	local goInside=state == "pendingInside" or insideFootprint
		or square(entrance[1]-creature.X,entrance[2]-creature.Z)<=arriveSq
	-- The direct front ray can strike the user's solid garage from its west
	-- or north/south sides. Follow EXISTING external nav corners instead of
	-- calling the whole remembered visit unusable. Only ONE leg is ray-checked
	-- per Think; a blocked corner defers patrol fallback until next Think.
	local nextState=goInside and "inside" or "front"
	local target=goInside and interior or entrance
	if not goInside then
		local nodes=navigation.Nodes
		local north=creature.Z<=p.Z
		local west=nodes and nodes[north and 3 or 5]
		local east=nodes and nodes[north and 2 or 6]
		if state=="pendingFlankEast" then
			target,nextState=east,"flankEast"
		elseif state=="pendingFront" then
			target,nextState=entrance,"front"
		elseif east and square(east[1]-creature.X,east[2]-creature.Z)<=arriveSq then
			target,nextState=entrance,"front"
		elseif west and square(west[1]-creature.X,west[2]-creature.Z)<=arriveSq then
			target,nextState=east,"flankEast"
		elseif creature.X < p.X-s.X*0.5+2 then
			target,nextState=west,"flankWest"
		elseif creature.X < entrance[1] and math.abs(creature.Z-p.Z)>=s.Z*0.5+2 then
			target,nextState=east,"flankEast"
		end
	end
	if not target then
		creature.HabitState="blocked"
		return nil,nil,"blocked"
	end
	local tx,tz=target[1],target[2]
	if goInside and square(tx-creature.X,tz-creature.Z)<=arriveSq then
		-- Already inside near the search center; only THIS physical presence
		-- provides (weak) negative evidence, never a view through the wall.
		self.PredictionMisses=math.min(self.PredictionMisses+1,self.Config.WorkingCapacity or 12)
		self.Evidence=math.max(0,self.Evidence-1)
		creature.HabitState="arrived"
		return nil,nil,"arrived"
	end
	if (navigation and not navigation:clear(creature.X,creature.Z,tx,tz,creature.RaycastParams))
		or (cover and cover.activeCount>0 and cover:intercept(creature.X,creature.Z,tx,tz)) then
		creature.HabitState="blocked"
		return nil,nil,"blocked"
	end
	creature.HabitState=nextState
	creature.HabitGoalX,creature.HabitGoalZ=tx,tz
	creature.HabitProgressX,creature.HabitProgressZ,creature.HabitProgressAt=creature.X,creature.Z,now
	return tx,tz,goInside and "physical-garage-investigation"
		or nextState=="front" and "witnessed-three-garage-entries" or "witnessed-garage-flank"
end
function GarageHabit:dump(): any
	return {visits=self.Visits,predictionMisses=self.PredictionMisses,
		effectiveEvidence=self.Evidence,
		threshold=self.Config.GarageVisitsForPrediction or 3,
		predictsGarage=self.Entrance~=nil and self.Evidence >= (self.Config.GarageVisitsForPrediction or 3),
		entranceX=self.Entrance and self.Entrance[1] or nil,
		entranceZ=self.Entrance and self.Entrance[2] or nil,
		interiorX=self.Interior and self.Interior[1] or nil,
		interiorZ=self.Interior and self.Interior[2] or nil,
		evidence="bounded witnessed entries; ONLY an unproductive physical Garage interior check lowers confidence"}
end
return GarageHabit
