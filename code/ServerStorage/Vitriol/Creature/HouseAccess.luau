--!strict
-- Doorway/roof clearance from the TWO existing house Parts. Geometry is read
-- once; no world objects, paths, rays or per-frame allocations are created.
-- Route a grounded survivor through the actual east doorway; if the Braid
-- already climbed onto either roof, exit to CLEAR sky before descending.
local HouseAccess = {}
HouseAccess.__index = HouseAccess
local function within(x: number, z: number, part: any, pad: number): boolean
	return math.abs(x-part.Position.X) <= part.Size.X*0.5+pad
		and math.abs(z-part.Position.Z) <= part.Size.Z*0.5+pad
end
local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi,v))
end
function HouseAccess.new(map: any): any
	local structures = map and map:FindFirstChild("Structures")
	if not structures then return nil end
	local self = setmetatable({Houses={}},HouseAccess)
	for _, name in ipairs({"House_01","House_02"}) do
		local house=structures:FindFirstChild(name)
		if not house then return nil end
		local floor=house:FindFirstChild("Floor")
		local pier=house:FindFirstChild("EastPier_-13")
		local lintel=house:FindFirstChild("EastLintel")
		local roof=house:FindFirstChild("Roof")
		local porch=house:FindFirstChild("PorchRoof")
		if not (floor and pier and lintel and roof and porch and floor:IsA("BasePart")
			and pier:IsA("BasePart") and lintel:IsA("BasePart")
			and roof:IsA("BasePart") and porch:IsA("BasePart")) then
			return nil -- older test maps: do not invent an entrance or ceiling
		end
		local otherPier=house:FindFirstChild("EastPier_13")
		local lowEdge=pier.Size and pier.Position.Z+pier.Size.Z*0.5
			or floor.Position.Z-8 -- older headless fixtures omit wall Size
		local highEdge=otherPier and otherPier.Size and otherPier.Position.Z-otherPier.Size.Z*0.5
			or floor.Position.Z+8
		-- An angled center ray can pass the doorway plane while the full core
		-- clips a pier CORNER on its way through the one-stud-deep wall.
		-- Keep the authored X extent of BOTH piers for an analytic body band.
		local halfX=pier.Size and pier.Size.X*0.5 or 0.5
		local otherHalfX=otherPier and otherPier.Size and otherPier.Size.X*0.5 or halfX
		local otherX=otherPier and otherPier.Position.X or pier.Position.X
		self.Houses[#self.Houses+1]={Name=name,Floor=floor,Roof=roof,Porch=porch,
			DoorX=pier.Position.X,DoorZ=floor.Position.Z,
			DoorMinZ=lowEdge,DoorMaxZ=highEdge,
			PierWestX=math.min(pier.Position.X-halfX,otherX-otherHalfX),
			PierEastX=math.max(pier.Position.X+halfX,otherX+otherHalfX),
			FloorTop=floor.Position.Y+floor.Size.Y*0.5,
			LintelBottom=lintel.Position.Y-lintel.Size.Y*0.5,
			RoofBottom=roof.Position.Y-roof.Size.Y*0.5,
			PorchBottom=porch.Position.Y-porch.Size.Y*0.5}
	end
	return self
end
function HouseAccess:houseForPrey(x: number, y: number, z: number): any?
	for _, h in ipairs(self.Houses) do
		local p=h.Floor.Position
		if x >= p.X-h.Floor.Size.X*0.5+2 and x <= h.DoorX-0.75
			and math.abs(z-h.DoorZ) <= h.Floor.Size.Z*0.5-2
			and y >= h.FloorTop-1 and y < h.RoofBottom-2 then return h end
	end
	return nil
end
-- The existing horizontal sight ray is intentionally at ground level for
-- wall routing. A rooftop Braid must not use it to acquire the EXACT live
-- coordinates of someone physically below a solid roof. This analytic
-- segment/slab intersection costs no additional raycast or allocation.
local function slabBlocks(slab: any, cx: number, cy: number, cz: number, tx: number, ty: number, tz: number): boolean
	local top=slab.Position.Y+slab.Size.Y*0.5
	local bottom=slab.Position.Y-slab.Size.Y*0.5
	if cy <= top+0.1 or ty >= bottom-0.1 then return false end
	local t=(top-cy)/(ty-cy)
	return t>0 and t<1 and within(cx+(tx-cx)*t,cz+(tz-cz)*t,slab,-0.05)
end
function HouseAccess:roofOccludes(cx: number, cy: number, cz: number, tx: number, ty: number, tz: number): boolean
	for _, h in ipairs(self.Houses) do
		if ty < h.RoofBottom-1 and (slabBlocks(h.Roof,cx,cy,cz,tx,ty,tz)
			or slabBlocks(h.Porch,cx,cy,cz,tx,ty,tz)) then return true end
	end
	return false
end
local function entryTop(h: any, radius: number): number
	return math.min(h.LintelBottom,h.PorchBottom)-radius-0.5
end
local function safeX(h: any, radius: number): number
	return h.Porch.Position.X+h.Porch.Size.X*0.5+radius+1
end
local function exitX(h: any, radius: number): number
	return safeX(h,radius)+6
end
local function aboveRoof(h: any, x: number, y: number, z: number, radius: number): boolean
	return (within(x,z,h.Roof,radius) and y >= h.Roof.Position.Y+h.Roof.Size.Y*0.5+radius*0.35)
		or (within(x,z,h.Porch,radius) and y >= h.Porch.Position.Y+h.Porch.Size.Y*0.5+radius*0.35)
end
function HouseAccess:escape(x: number, y: number, z: number, radius: number): (any?,number?,number?,number?,boolean?)
	for _, h in ipairs(self.Houses) do
		local outside=safeX(h,radius)
		local high=aboveRoof(h,x,y,z,radius)
		-- Continue the same escape after crossing the eaves. Without this
		-- short exterior recovery strip the planted feet can pull it back up.
		if high or (x >= outside and x <= exitX(h,radius)+6
			and math.abs(z-h.DoorZ) <= h.Porch.Size.Z*0.5+radius+2
			and y > entryTop(h,radius)+0.3) then
			if x < outside then return h,exitX(h,radius),y,h.DoorZ,false end
			return h,exitX(h,radius),h.FloorTop+radius+5,h.DoorZ,true
		end
	end
	return nil,nil,nil,nil,nil
end
-- Returns a waypoint, its target Y and a height ceiling. No prey GPS is
-- acquired here: CreatureService passes ONLY its already-sensed player.
function HouseAccess:route(x: number, y: number, z: number, tx: number, ty: number, tz: number, radius: number): (number?,number?,number?,number?)
	local h=self:houseForPrey(tx,ty,tz)
	if not h then return nil,nil,nil,nil end
	local _,ex,ey,ez=self:escape(x,y,z,radius)
	if ex then return ex,ey,ez,nil end
	local maxY=entryTop(h,radius)
	local lane=clamp(tz,h.DoorZ-6,h.DoorZ+6)
	local west=h.Floor.Position.X-h.Floor.Size.X*0.5-6
	local sideZ=h.DoorZ+(z<h.DoorZ and -1 or 1)*(h.Roof.Size.Z*0.5+5)
	-- If on the OTHER side at ground level, skirt the actual solid walls and
	-- roof overhang. Never pull straight through the user's house geometry.
	if x <= h.DoorX-6 and not within(x,z,h.Floor,-1) then
		if x < h.Floor.Position.X-h.Floor.Size.X*0.5+1 and math.abs(z-sideZ)>3 then
			return west,y,sideZ,nil
		end
		if math.abs(z-h.DoorZ)>h.Floor.Size.Z*0.5+2 then return exitX(h,radius),y,sideZ,nil end
	end
	-- A high body must descend in the clear beyond the porch eave BEFORE it
	-- enters; otherwise lowering here would tunnel through the solid roof.
	if x >= safeX(h,radius) and y > maxY+0.3 then
		return exitX(h,radius),h.FloorTop+radius+5,h.DoorZ,nil
	end
	if x < safeX(h,radius) and x > h.DoorX-6 and y > maxY+0.3 then
		return exitX(h,radius),y,h.DoorZ,nil
	end
	if x > exitX(h,radius)-2 and math.abs(z-lane)>2 then
		return exitX(h,radius),math.max(ty,maxY-1),lane,nil
	end
	-- The creature follows low footfall waypoints at a reachable body
	-- height; commanding Y=the player's ankles made foot intent disappear.
	local waypointY=math.max(ty,maxY-1)
	if x > h.DoorX+7 then return h.DoorX+6,waypointY,lane,maxY end
	if x > h.DoorX-6 then return h.DoorX-8,waypointY,lane,maxY end
	return tx,ty,tz,self:heightCap(x,y,z,radius)
end
-- The main door has the lowest lintel/porch underside. Indoors the higher
-- main roof permits the normal elevated gait again; outside no cap applies.
function HouseAccess:heightCap(x: number, y: number, z: number, radius: number): (number?,number?)
	for _, h in ipairs(self.Houses) do
		local cap=nil
		local indoors=within(x,z,h.Roof,-radius)
		local porch=within(x,z,h.Porch,radius)
		local doorLane=math.abs(z-h.DoorZ)<=8+radius and math.abs(x-h.DoorX)<=3+radius
		if indoors then cap=h.RoofBottom-radius-0.5 end
		if porch or doorLane then cap=math.min(cap or math.huge,entryTop(h,radius)) end
		-- The same Part's TOP may be support for a roof-bound Braid. Never
		-- clamp through it; the separate clear-sky escape handles that case.
		if cap and y <= cap+radius+0.5 then return cap,h.FloorTop+radius+0.1 end
	end
	return nil,nil
end
function HouseAccess:constrain(x: number, y: number, z: number, dx: number, dy: number, dz: number, radius: number, dt: number, recovering: boolean?): (number,number,number)
	local h,_,targetY,_,descending=self:escape(x,y,z,radius)
	if recovering and h and descending then
		local boundary=safeX(h,radius)
		if x+dx < boundary then dx=boundary-x end
		dy=math.min(dy,-math.min(math.max(0,y-targetY),10*math.max(dt,0)))
	end
	local cap,minY=self:heightCap(x+dx,y+dy,z+dz,radius)
	if cap then
		-- Entry staging ensures Y is already BELOW the eave. A per-frame
		-- clamp here only rejects the ordinary raised support-haul impulse.
		if y+dy > cap then dy=cap-y end
		if y+dy < minY then dy=minY-y end
	end
	-- BulkMoveTo bypasses solid roof collision. A lost rooftop foothold
	-- must NOT let the core glide down through either authored roof slab;
	-- descent is available only beyond the porch edge, as above.
	for _,house in ipairs(self.Houses) do
		local roof=house.Roof
		local top=roof.Position.Y+roof.Size.Y*0.5
		if within(x+dx,z+dz,roof,radius) and y>=top+radius*0.5
			and y+dy<top+radius+0.1 then dy=top+radius+0.1-y end
		local porch=house.Porch
		top=porch.Position.Y+porch.Size.Y*0.5
		if within(x+dx,z+dz,porch,radius) and y>=top+radius*0.5
			and y+dy<top+radius+0.1 then dy=top+radius+0.1-y end
	end
	return dx,dy,dz
end
-- A clue-less Braid that has COMPLETED one local patrol circuit can be
-- inside a house with no direct road target. Sweep real ground-level rays
-- around it, over successive Thinks, then follow only a body-width-safe ray
-- through the EXISTING east door. This never reads a hidden player's position.
function HouseAccess:groundHouse(x: number, y: number, z: number): any?
	for _, h in ipairs(self.Houses) do
		local p,s=h.Floor.Position,h.Floor.Size
		if x >= p.X-s.X*0.5+2 and x <= h.DoorX-0.75
			and math.abs(z-h.DoorZ) <= s.Z*0.5-2
			and y >= h.FloorTop-1 and y < h.RoofBottom-0.5 then return h end
	end
	return nil
end

function HouseAccess:resetExitSweep(c: any): ()
	c.ExitSweepHouse,c.ExitSweepIndex,c.ExitSweepGoalX,c.ExitSweepGoalZ=nil,nil,nil,nil
	c.ExitSweepKind,c.ExitSweepProgressX,c.ExitSweepProgressZ,c.ExitSweepProgressAt=nil,nil,nil,nil
	c.ExitSweepStageIndex,c.ExitSweepLowerY,c.ExitSweepLowerAt,c.ExitSweepCrouch=nil,nil,nil,nil
end

-- Guard the core along the WHOLE near/far pier band, not just at X=DoorX.
-- The physical centerline ray remains the only Workspace query. Since Z is
-- linear in X, checking both clipped band endpoints covers every X between.
local function clearsPierBand(h: any, x: number, z: number, tx: number, tz: number, radius: number): boolean
	local first=math.max(x,h.PierWestX-radius)
	local last=math.min(tx,h.PierEastX+radius)
	if last<first then return false end
	local slope=(tz-z)/(tx-x)
	local firstZ=z+(first-x)*slope
	local lastZ=z+(last-x)*slope
	local low=h.DoorMinZ+radius+0.5
	local high=h.DoorMaxZ-radius-0.5
	return firstZ>=low and firstZ<=high and lastZ>=low and lastZ<=high
end

local function crossesCover(h: any, cover: any, x: number, z: number, tx: number, tz: number, radius: number): boolean
	if not cover or not cover.Pieces or (cover.activeCount or 0)==0 then return false end
	for _,piece in ipairs(cover.Pieces) do
		if piece.Placed and piece.House==h.Name and piece.Target and piece.Width then
			-- At the authored 90-degree marker the ORIGINAL Part.Size.Z is
			-- the furniture depth in X. A center-plane-only check misses an
			-- angled core grazing its near/far corner; do not alter the Part.
			local depth=piece.Part and piece.Part.Size and piece.Part.Size.Z
			if not depth or depth<=0 then return true end -- missing geometry fails closed
			local plane=piece.Target.Position.X
			local halfDepth=depth*0.5+radius
			local first=math.max(math.min(x,tx),plane-halfDepth)
			local last=math.min(math.max(x,tx),plane+halfDepth)
			if first<=last then
				local firstZ,lastZ=z,tz
				if math.abs(tx-x)>0.0001 then
					local slope=(tz-z)/(tx-x)
					firstZ=z+(first-x)*slope
					lastZ=z+(last-x)*slope
				end
				local low=piece.Target.Position.Z-piece.Width*0.5-radius
				local high=piece.Target.Position.Z+piece.Width*0.5+radius
				if math.max(firstZ,lastZ)>=low and math.min(firstZ,lastZ)<=high then
					return true
				end
			end
		end
	end
	return false
end

function HouseAccess:sweepExit(c: any, now: number, nav: any, cover: any): (number?,number?,number?,string?)
	local h=self:groundHouse(c.X,c.Y,c.Z)
	if not h or not nav or not nav.clear then self:resetExitSweep(c); return nil,nil,nil,"unavailable" end
	if c.ExitSweepHouse ~= h.Name or (c.ExitSweepGoalX and
		(c.TargetX ~= c.ExitSweepGoalX or c.TargetZ ~= c.ExitSweepGoalZ)) then
		self:resetExitSweep(c) -- a higher-priority goal interrupted a held ray
	end
	c.ExitSweepHouse=h.Name
	local radius=(c.Stats and c.Stats.CoreRadius) or 1.5
	-- A low Y on a distant exit goal does NOT guarantee the horizontal foot-led
	-- haul waits for the body to descend. Command stationary X/Z and a
	-- supported crouch indoors; spend no candidate ray until the core fits.
	local lowerY=entryTop(h,radius)-1
	if c.ExitSweepCrouch==nil then
		-- An elevated planted-foot core supports its NORMAL standing height
		-- even when TargetY is lower. Use only the existing supported crouch
		-- during this idle doorway sweep; never change the approved gait or
		-- chomp crouch elsewhere. Derive it from this genome and real floor.
		local stats=c.Stats or {}
		local monster=c.Monster or {}
		local movement=monster.Locomotion or {}
		local kill=monster.Kill or {}
		local standing=math.max(radius+0.12,(stats.TendrilReach or 14)*(movement.SupportHeightFraction or 0.34))
		local crouched=radius+(kill.ChompClearance or 0.55)
		local desired=lowerY-h.FloorTop-0.25
		c.ExitSweepCrouch=math.clamp((standing-desired)/math.max(standing-crouched,0.01),0,1)
	end
	if c.Y > lowerY+0.35 then
		if c.ExitSweepLowerY==nil or c.Y < c.ExitSweepLowerY-0.5 then
			c.ExitSweepLowerY,c.ExitSweepLowerAt=c.Y,now
		elseif now-(c.ExitSweepLowerAt or now)>=3 then
			self:resetExitSweep(c) -- no downward progress: resume local hunt
			return nil,nil,nil,"blocked"
		end
		return c.X,lowerY,c.Z,"physical-house-exit-lowering"
	end
	c.ExitSweepLowerY,c.ExitSweepLowerAt=nil,nil
	local goalY=math.min(c.Y,lowerY)
	local arriveSq=5*5
	if c.ExitSweepGoalX then
		local dx,dz=c.ExitSweepGoalX-c.X,c.ExitSweepGoalZ-c.Z
		if dx*dx+dz*dz <= arriveSq then
			local kind=c.ExitSweepKind
			c.ExitSweepGoalX,c.ExitSweepGoalZ,c.ExitSweepKind=nil,nil,nil
			if kind=="stage" then c.ExitSweepIndex=1 end -- scan AGAIN from the real new spot
		elseif (c.X-(c.ExitSweepProgressX or c.X))^2
			+(c.Z-(c.ExitSweepProgressZ or c.Z))^2 >= 1 then
			c.ExitSweepProgressX,c.ExitSweepProgressZ,c.ExitSweepProgressAt=c.X,c.Z,now
			return c.ExitSweepGoalX,goalY,c.ExitSweepGoalZ,"physical-house-exit"
		elseif now-(c.ExitSweepProgressAt or now)>=3 then
			c.ExitSweepGoalX,c.ExitSweepGoalZ,c.ExitSweepKind=nil,nil,nil
			c.ExitSweepIndex=(c.ExitSweepIndex or 1)+1 -- stalled: try the next real ray
		else
			return c.ExitSweepGoalX,goalY,c.ExitSweepGoalZ,"physical-house-exit"
		end
	end
	local index=c.ExitSweepIndex or 1
	if index<=16 then
		local k=math.floor(index/2)
		local angle=(index%2==0 and 1 or -1)*k*math.pi/8
		local range=math.max(24,h.DoorX+12-c.X)
		local tx,tz=c.X+math.cos(angle)*range,c.Z+math.sin(angle)*range
		c.ExitSweepIndex=index+1 -- ONE physical candidate ray per Think
		local doorT=(h.DoorX-c.X)/(tx-c.X)
		if tx>=h.DoorX+6 and doorT>0 and doorT<1 then
			if clearsPierBand(h,c.X,c.Z,tx,tz,radius)
				and not crossesCover(h,cover,c.X,c.Z,tx,tz,radius)
				and nav:clear(c.X,c.Z,tx,tz,c.RaycastParams) then
				c.ExitSweepGoalX,c.ExitSweepGoalZ,c.ExitSweepKind=tx,tz,"exit"
				c.ExitSweepProgressX,c.ExitSweepProgressZ,c.ExitSweepProgressAt=c.X,c.Z,now
				return tx,goalY,tz,"physical-house-exit"
			end
		end
		return nil,nil,nil,"scanning"
	end
	-- If a direct spoke is occluded from a corner, step to one of the two
	-- actual furniture lanes INSIDE the door, then restart the circular scan.
	-- Never tunnel through installed cover, solid walls, or a roof to get there.
	local lanes={h.DoorZ+5,h.DoorZ-3.5}
	local stageIndex=c.ExitSweepStageIndex or 1
	if stageIndex<=#lanes then
		c.ExitSweepStageIndex=stageIndex+1
		local tx,tz=h.DoorX-8,lanes[stageIndex]
		local dx,dz=tx-c.X,tz-c.Z
		if dx*dx+dz*dz>arriveSq
			and not crossesCover(h,cover,tx,tz,h.DoorX+12,tz,radius)
			and not crossesCover(h,cover,c.X,c.Z,tx,tz,radius)
			and nav:clear(c.X,c.Z,tx,tz,c.RaycastParams) then
			c.ExitSweepGoalX,c.ExitSweepGoalZ,c.ExitSweepKind=tx,tz,"stage"
			c.ExitSweepProgressX,c.ExitSweepProgressZ,c.ExitSweepProgressAt=c.X,c.Z,now
			return tx,goalY,tz,"physical-house-exit-stage"
		end
		return nil,nil,nil,"scanning"
	end
	self:resetExitSweep(c)
	return nil,nil,nil,"blocked"
end

return HouseAccess
