--!strict
-- Inert route data for the USER'S solid church UnionOperation. The main
-- doorway is on its front/south face; no doors, meshes or Paths are created.
local ChurchNavigation = {}
ChurchNavigation.__index = ChurchNavigation

function ChurchNavigation.new(map: any, world: any): any?
	local structures = map and map:FindFirstChild("Structures")
	local church = structures and structures:FindFirstChild("Church_BellTower")
	local body = church and church:FindFirstChild("Body")
	if not (body and body:IsA("BasePart") and world and world.Raycast) then return nil end
	local interactions = map and map:FindFirstChild("Interactions")
	local lever = interactions and interactions:FindFirstChild("Church_BellLever")
	if not (lever and lever:IsA("BasePart")) then lever=nil end
	local cx, cz = body.Position.X, body.Position.Z
	local left, right = cx-body.Size.X*.5-8, cx+body.Size.X*.5+8
	local front = cz+body.Size.Z*.5+11
	return setmetatable({World=world, Church=church, Body=body, Lever=lever,
		Windows=world.FindFirstChild and world:FindFirstChild("ChurchWindows") or nil,
		Left=left, Right=right, Front=front, Middle=cx}, ChurchNavigation)
end
function ChurchNavigation:hit(ax: number, az: number, bx: number, bz: number, params: any): any
	if Vector3 == nil then return nil end
	local dx,dz=bx-ax,bz-az
	if dx*dx+dz*dz<.25 then return nil end
	return self.World:Raycast(Vector3.new(ax,4,az),Vector3.new(dx,0,dz),params)
end
local function near(ax: number, az: number, bx: number, bz: number): boolean
	local dx,dz=ax-bx,az-bz
	-- The elevated body can trail planted feet by several studs; a waypoint
	-- switches when those feet can reach it, not at four-stud core contact.
	return dx*dx+dz*dz<=12*12
end
function ChurchNavigation:route(cx: number, cz: number, tx: number, tz: number, params: any, bellModel: any?): (number?, number?)
	local sideX = cx<self.Middle and self.Left or self.Right
	-- Once beside the church, take the known CLEAR doorway leg even if the
	-- straight ray to the bell now hits a separate Workspace.ChurchWindows
	-- decoration. It is not an obstacle on this waypoint leg.
	if (cx<self.Middle-13 or cx>self.Middle+13) and near(cx,cz,sideX,self.Front) then
		if not self:hit(cx,cz,self.Middle,self.Front,params) then return self.Middle,self.Front end
		return nil,nil
	end
	local hit=self:hit(cx,cz,tx,tz,params)
	-- Studio's ground-height ray may finish on the queryable, noncolliding
	-- ORIGINAL target lever itself. Accept ONLY that exact authored Part
	-- when the requested endpoint is its CURRENT coordinate; a moved lever
	-- along the ray to a different goal must still block it. No wall/window
	-- or unrelated prop gains endpoint authority.
	local lever=self.Lever
	local targetLever=lever and hit and hit.Instance==lever
		and math.abs(tx-lever.Position.X)<0.01 and math.abs(tz-lever.Position.Z)<0.01
	if not hit or targetLever
		or (bellModel and hit.Instance and hit.Instance:IsDescendantOf(bellModel)) then
		return tx,tz -- physically clear or the exact preauthored target itself
	end
	local churchWall = hit.Instance and hit.Instance:IsDescendantOf(self.Church)
	local churchWindow = hit.Instance and self.Windows and hit.Instance:IsDescendantOf(self.Windows)
	if not (churchWall or churchWindow) then
		return nil,nil -- unknown obstacle: don't blindly tunnel through it
	end
	-- Real Studio rays: from the reported western core (83.8,-207.5),
	-- side approach (86.25,-130.25) -> door (119,-130.25) -> bell.
	if (cx<self.Middle-13 or cx>self.Middle+13) and cz<self.Front+4 then
		if not self:hit(cx,cz,sideX,self.Front,params) then return sideX,self.Front end
		return nil,nil
	end
	if not self:hit(cx,cz,self.Middle,self.Front,params) then return self.Middle,self.Front end
	return nil,nil
end
return ChurchNavigation
