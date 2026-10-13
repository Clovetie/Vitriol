--!strict
-- Bounded, server-side waypoint routing around the authored Map v1 garage.
-- Only Lua coordinates are generated: no PathfindingService Path or runtime Instance.
-- The approved Locomotion/TendrilRig still own every actual step and foothold.
local GarageNavigation = {}
GarageNavigation.__index = GarageNavigation

local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

function GarageNavigation.new(map: any, workspace: any): any
	local structures = map and map:FindFirstChild("Structures")
	local garage = structures and structures:FindFirstChild("Millers_Garage")
	local floor = garage and garage:FindFirstChild("Floor")
	local rear = garage and garage:FindFirstChild("RearWall")
	if not (floor and rear and floor.Position and floor.Size and workspace and workspace.Raycast) then
		return nil -- older headless worlds have no authored map; no fabricated geometry
	end
	local cx, cz = floor.Position.X, floor.Position.Z
	local east = cx + floor.Size.X * 0.5 + 7
	local west = cx - floor.Size.X * 0.5 - 7
	local north = cz - floor.Size.Z * 0.5 - 7
	local south = cz + floor.Size.Z * 0.5 + 7
	local self = setmetatable({ Workspace = workspace, Garage = garage,
		Interiors = map:FindFirstChild("Interiors"), Cache = nil }, GarageNavigation)
	-- Open east/front entrance, two north/south turns, and the west/rear wall.
	-- Routes run OUTSIDE the solid footprint, not through its roof/walls.
	self.Nodes = {
		{east, cz}, {east, north}, {west, north},
		{west, cz}, {west, south}, {east, south},
	}
	self.Cost, self.Next = {}, {}
	for i = 1, 6 do
		self.Cost[i], self.Next[i] = {}, {}
		for j = 1, 6 do self.Cost[i][j] = i == j and 0 or math.huge end
	end
	for i = 1, 6 do
		local j = i % 6 + 1
		local cost = distance(self.Nodes[i][1], self.Nodes[i][2], self.Nodes[j][1], self.Nodes[j][2])
		self.Cost[i][j], self.Cost[j][i] = cost, cost
		self.Next[i][j], self.Next[j][i] = j, i
	end
	for k = 1, 6 do
		for i = 1, 6 do
			for j = 1, 6 do
				local through = self.Cost[i][k] + self.Cost[k][j]
				if through < self.Cost[i][j] then
					self.Cost[i][j], self.Next[i][j] = through, self.Next[i][k]
				end
			end
		end
	end
	return self
end

function GarageNavigation:hit(ax: number, az: number, bx: number, bz: number, params: any): any
	if Vector3 == nil then return nil end
	local dx, dz = bx - ax, bz - az
	if dx * dx + dz * dz < 0.25 then return nil end
	-- Ground-level horizontal visibility: do not raycast from the elevated
	-- core above the wall or mistake a roof for an impassable passage.
	return self.Workspace:Raycast(Vector3.new(ax, 4, az), Vector3.new(dx, 0, dz), params)
end

function GarageNavigation:clear(ax: number, az: number, bx: number, bz: number, params: any): boolean
	return self:hit(ax, az, bx, bz, params) == nil
end

function GarageNavigation:routeClear(ax: number, az: number, bx: number, bz: number, params: any, endpoint: any?): boolean
	local hit = self:hit(ax, az, bx, bz, params)
	if hit == nil then return true end
	local part = hit.Instance
	-- For a targeted generator sabotage ray, striking the TARGET itself is a
	-- successful final approach, not a blocked route. Never grant this for an
	-- intervening garage wall or unrelated cover/player chase.
	if endpoint and part == endpoint then return true end
	-- Defenses are not static walls: let CreatureCore's existing crossing /
	-- press / breach authority handle them rather than routing the Braid away.
	return part ~= nil and (part.Name == "Garage_BoardedGate"
		or (part.Parent ~= nil and part.Parent.Name == "PlacedBarricades"))
end

-- A caller that JUST measured this exact start→goal ray may pass its
-- obstructing RaycastResult. Never accept a boolean or a guessed blocker:
-- absent evidence takes the original physical ray here.
function GarageNavigation:route(cx: number, cz: number, tx: number, tz: number, params: any, now: number, endpoint: any?, knownHit: any?): (number?, number?)
	local obstacle = knownHit and knownHit.Instance and knownHit or self:hit(cx, cz, tx, tz, params)
	if obstacle == nil then self.Cache = nil; return tx, tz end
	-- Garage furnishings can be the FIRST hit before the structural wall:
	-- the authored barrel in the bay lies exactly on the center chase ray.
	-- Keep this scoped to named garage props, not arbitrary town cover.
	local part = obstacle.Instance
	local garageProp = part and self.Interiors and part.Parent == self.Interiors
		and string.sub(part.Name, 1, 7) == "Garage_"
	if not (part and (part:IsDescendantOf(self.Garage) or garageProp)) then
		self.Cache = nil
		return tx, tz
	end
	local cache = self.Cache
	if cache and (now or 0) < cache.untilTime and distance(tx, tz, cache.tx, cache.tz) < 10
		and distance(cx, cz, cache.x, cache.z) > 4 then
		return cache.x, cache.z
	end
	local nodes = self.Nodes
	local fromDistance, toDistance, to = {}, {}, {}
	for i = 1, 6 do
		fromDistance[i] = distance(cx, cz, nodes[i][1], nodes[i][2])
		toDistance[i] = distance(nodes[i][1], nodes[i][2], tx, tz)
	end
	local best, chosen = math.huge, nil
	-- Enumerate pairs in the SAME order and retain the original strict < tie
	-- rule. Once a safe pair exists, reject a start node only if even its
	-- cheapest EXACT graph pair cannot improve it; reject losing end nodes
	-- BEFORE paying a Workspace ray. Never infer an untested node is clear.
	for i = 1, 6 do
		local canImprove = false
		for j = 1, 6 do
			if fromDistance[i] + self.Cost[i][j] + toDistance[j] < best then
				canImprove = true
				break
			end
		end
		if canImprove and self:routeClear(cx, cz, nodes[i][1], nodes[i][2], params) then
			for j = 1, 6 do
				local cost = fromDistance[i] + self.Cost[i][j] + toDistance[j]
				if cost < best then
					if to[j] == nil then
						to[j] = self:routeClear(nodes[j][1], nodes[j][2], tx, tz, params, endpoint)
					end
					if to[j] then
						best = cost
						chosen = fromDistance[i] <= 4 and (self.Next[i][j] or j) or i
					end
				end
			end
		end
	end
	if chosen then
		local x, z = nodes[chosen][1], nodes[chosen][2]
		self.Cache = {x = x, z = z, tx = tx, tz = tz, untilTime = (now or 0) + 0.5}
		return x, z
	end
	self.Cache = nil
	return nil, nil -- no visible safe waypoint: do not run blindly into the wall
end

return GarageNavigation
