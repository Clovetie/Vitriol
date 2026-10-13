--!strict
-- WP6's first Night-only search policy, NOT Q learning or prey prediction.
-- A real clue gets a short local sweep; otherwise the Braid patrols a bounded
-- area around its current region. No player position is queried here.
-- Only numeric waypoints; existing locomotion, ray filter and authored cover
-- retain control of actual travel. No Instance, Path, loop or yield is made.
local InstinctSearch = {}
InstinctSearch.__index = InstinctSearch
local OFFSETS = { {1,0}, {0,1}, {-1,0}, {0,-1} }
local function square(dx: number, dz: number): number
	return dx*dx+dz*dz
end
function InstinctSearch.new(config: any, map: any): any
	local ground = map and map:FindFirstChild("Ground")
	local floor = ground and ground:FindFirstChild("Ground_QuarryFoundation")
	local bounds = nil
	if floor and floor:IsA("BasePart") then
		local p,s=floor.Position,floor.Size
		bounds={minX=p.X-s.X*0.5+8,maxX=p.X+s.X*0.5-8,
			minZ=p.Z-s.Z*0.5+8,maxZ=p.Z+s.Z*0.5-8}
	end
	-- Long-range PATROL objectives follow the user's authored road spine.
	-- Derive from the current Part, never assume its old 560-stud length or
	-- snap the user-extended Road_Main back to a historical coordinate.
	local roads=map and map:FindFirstChild("Roads")
	local road=roads and roads:FindFirstChild("Road_Main")
	local stops=nil
	if road and road:IsA("BasePart") and road.Size.Z >= 120 then
		stops={}
		for _,fraction in ipairs({-0.33,-0.12,0.12,0.33}) do
			stops[#stops+1]={road.Position.X,road.Position.Z+road.Size.Z*fraction}
		end
	end
	return setmetatable({Config=config or {},Bounds=bounds,RoadStops=stops},InstinctSearch)
end
function InstinctSearch:note(creature: any, x: number, y: number, z: number, now: number): ()
	-- Called ONLY with a freshly sensed prey root or an actual emitted sound.
	creature.SearchClueX,creature.SearchClueY,creature.SearchClueZ=x,y,z
	creature.SearchClueAt=now
	creature.SearchMode,creature.SearchGoalX=nil,nil
end
function InstinctSearch:reset(creature: any): ()
	creature.SearchClueAt,creature.SearchMode,creature.SearchGoalX=nil,nil,nil
	creature.SearchGoalZ,creature.SearchIndex,creature.SearchProgressAt=nil,nil,nil
	creature.SearchRegionNextIndex,creature.SearchRegionTries=nil,nil
end
-- One road objective after a completed local circuit, not a player location.
-- Find a nearby road stop by arithmetic, then try at most TWO actual rays per
-- Think. Blocked/intercepted points are skipped; the map is never phased.
function InstinctSearch:_transit(creature: any, now: number, navigation: any?, cover: any?): (number?,number?,number?)
	local nodes=self.RoadStops
	local index=creature.SearchRegionNextIndex
	if not index then
		local nearest,distance=1,math.huge
		for i=1,#nodes do
			local p=nodes[i]
			local d=square(p[1]-creature.X,p[2]-creature.Z)
			if d<distance then nearest,distance=i,d end
		end
		index=nearest
		if distance <= (self.Config.RegionArriveStuds or 12)^2 then
			index=index%#nodes+1
		end
	end
	local tried=creature.SearchRegionTries or 0
	for _=1,2 do
		if tried >= #nodes then break end
		local i=index
		index=index%#nodes+1
		tried+=1
		local p=nodes[i]
		local tx,tz=p[1],p[2]
		if square(tx-creature.X,tz-creature.Z) > (self.Config.RegionArriveStuds or 12)^2
			and (not navigation or navigation:clear(creature.X,creature.Z,tx,tz,creature.RaycastParams))
			and (not cover or cover.activeCount == 0
				or not cover:intercept(creature.X,creature.Z,tx,tz)) then
			creature.SearchRegionNextIndex=index
			creature.SearchRegionTries=0
			creature.SearchGoalX,creature.SearchGoalZ=tx,tz
			creature.SearchProgressX,creature.SearchProgressZ,creature.SearchProgressAt=creature.X,creature.Z,now
			return tx,creature.Y,tz
		end
	end
	creature.SearchRegionNextIndex=index
	creature.SearchRegionTries=tried
	if tried >= #nodes then
		-- None of the four real destinations has a direct safe route. Stay
		-- locally mobile; try an outward route only after another full circuit.
		creature.SearchMode,creature.SearchIndex="patrol",1
		creature.SearchAnchorX,creature.SearchAnchorY,creature.SearchAnchorZ=creature.X,creature.Y,creature.Z
		creature.SearchRegionTries=0
	end
	return nil,nil,nil
end
function InstinctSearch:next(creature: any, now: number, navigation: any?, cover: any?): (number?,number?,number?)
	local cfg=self.Config
	local clueAge=creature.SearchClueAt and now-creature.SearchClueAt or math.huge
	local dx=(creature.SearchClueX or creature.X)-creature.X
	local dz=(creature.SearchClueZ or creature.Z)-creature.Z
	local recent=clueAge >= 0 and clueAge <= (cfg.ClueSeconds or 25)
		and square(dx,dz) <= (cfg.ClueReachStuds or 32)^2
	if creature.SearchMode == nil then
		creature.SearchMode=recent and "sweep" or "patrol"
		creature.SearchAnchorX=recent and creature.SearchClueX or creature.X
		creature.SearchAnchorY=recent and creature.SearchClueY or creature.Y
		creature.SearchAnchorZ=recent and creature.SearchClueZ or creature.Z
		creature.SearchIndex=1
	end
	if creature.SearchMode == "sweep" and not recent then
		creature.SearchMode,creature.SearchIndex,creature.SearchGoalX="patrol",1,nil
		creature.SearchAnchorX,creature.SearchAnchorY,creature.SearchAnchorZ=creature.X,creature.Y,creature.Z
	end
	local arriveSq=(cfg.ArriveStuds or 5)^2
	if creature.SearchGoalX ~= nil then
		local gx,gz=creature.SearchGoalX,creature.SearchGoalZ
		local reached=square(gx-creature.X,gz-creature.Z) <= arriveSq
		local px,pz=creature.SearchProgressX or creature.X,creature.SearchProgressZ or creature.Z
		if square(creature.X-px,creature.Z-pz) >= 1 then
			creature.SearchProgressX,creature.SearchProgressZ,creature.SearchProgressAt=creature.X,creature.Z,now
		end
		local stalled=now-(creature.SearchProgressAt or now) >= (cfg.StallSeconds or 3)
		if not reached and not stalled then return gx,creature.SearchAnchorY,gz end
		creature.SearchGoalX=nil
		if creature.SearchMode == "transit" then
			if reached then
				creature.SearchMode,creature.SearchIndex="patrol",1
				creature.SearchAnchorX,creature.SearchAnchorY,creature.SearchAnchorZ=creature.X,creature.Y,creature.Z
			end -- a stalled transit tries the NEXT road stop on this Think
		else
			creature.SearchIndex=(creature.SearchIndex or 1)+1
		end
	end
	if creature.SearchMode == "patrol" and creature.SearchIndex > #OFFSETS and self.RoadStops then
		creature.SearchMode,creature.SearchGoalX="transit",nil
		creature.SearchRegionTries=0
	end
	if creature.SearchMode == "transit" then
		return self:_transit(creature,now,navigation,cover)
	end
	-- At most two new candidate visibility checks per Think; never sweep a
	-- dozen map rays in a single measured perception slot.
	for _=1,2 do
		if creature.SearchIndex > #OFFSETS then
			if creature.SearchMode == "sweep" then
				creature.SearchMode="patrol"
				creature.SearchAnchorX,creature.SearchAnchorY,creature.SearchAnchorZ=creature.X,creature.Y,creature.Z
			end
			creature.SearchIndex=1
		end
		local offset=OFFSETS[creature.SearchIndex]
		local radius=creature.SearchMode == "sweep" and (cfg.SweepRadiusStuds or 10)
			or (cfg.PatrolRadiusStuds or 24)
		local tx=creature.SearchAnchorX+offset[1]*radius
		local tz=creature.SearchAnchorZ+offset[2]*radius
		local bounds=self.Bounds
		if bounds then
			tx=math.clamp(tx,bounds.minX,bounds.maxX)
			tz=math.clamp(tz,bounds.minZ,bounds.maxZ)
		end
		creature.SearchIndex+=1
		if square(tx-creature.X,tz-creature.Z) > arriveSq
			and (not navigation or navigation:clear(creature.X,creature.Z,tx,tz,creature.RaycastParams))
			and (not cover or cover.activeCount == 0
				or not cover:intercept(creature.X,creature.Z,tx,tz)) then
			-- Current goal advances ONLY on arrival/stall.
			creature.SearchIndex = creature.SearchIndex - 1
			creature.SearchGoalX,creature.SearchGoalZ=tx,tz
			creature.SearchProgressX,creature.SearchProgressZ,creature.SearchProgressAt=creature.X,creature.Z,now
			return tx,creature.SearchAnchorY,tz
		end
	end
	return nil,nil,nil -- physically inaccessible: never phase through cover/walls
end
return InstinctSearch
