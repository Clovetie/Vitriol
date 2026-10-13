--!strict
-- Server-only transaction engine for shared daylight preparation. NOT YET wired
-- into live prompts. No yielding, task scheduler, Instances or client clock writes.
-- The caller injects authored action specs and a fade transport after authoring
-- its remote; a failed or stale transaction never pays or commits.
local PrepCoordinator = {}
PrepCoordinator.__index = PrepCoordinator

local FADE_IN = 0.35 -- real seconds from vote close to full blackout
local FADE_OUT = 0.4 -- real seconds after the one server-owned time skip
local HELPER_RADIUS_SQUARED = 12 * 12

function PrepCoordinator.new(s: any): any
	local self: any = setmetatable({}, PrepCoordinator)
	self.Time, self.Health, self.Players = s.Time, s.Health, s.Players
	self.Rules, self.Actions, self.Fade = s.Rules, s.Actions, s.Fade
	self.OnClear = s.OnClear -- post-fade world presentation, never the paid commit
	self.Now = s.Now -- inject Workspace:GetServerTimeNow for live wall-clock deadlines
	self.Logger = s.Logger
	self.current, self.serial, self.running = nil, 0, true
	self.connections, self.started = {}, false
	return self
end
function PrepCoordinator:_showHelpers(active: string?): ()
	for action, spec in pairs(self.Actions) do
		if spec.Helper then spec.Helper.Enabled = active == action end
	end
end
function PrepCoordinator:start(): ()
	if self.started then return end
	self.started = true
	self:_showHelpers(nil)
	for action, spec in pairs(self.Actions) do
		if spec.Helper then
			local key = action
			self.connections[#self.connections+1] = spec.Helper.Triggered:Connect(function(player: any)
				self:volunteer(key, player)
			end)
		end
	end
end

local function day(time: any): boolean
	return time.phase == "Day" or time.phase == "Dawn"
end
function PrepCoordinator:_eligible(player: any, part: any): boolean
	if not player or type(player.UserId) ~= "number" or not part or not part.Position then return false end
	-- A disconnected player may still have a character/state object for a moment.
	-- Players has no FindFirstPlayerByUserId API; with at most four survivors,
	-- checking identity in GetPlayers is cheap and cannot trust a stale UserId.
	local connected = false
	for _, present in ipairs(self.Players:GetPlayers()) do
		if present == player then connected = true; break end
	end
	if not connected then return false end
	local state = self.Health.states[player.UserId]
	if not state or state.dead or state.awaitingDawn or state.permadead then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root.Position then return false end
	local a, b = root.Position, part.Position
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return dx * dx + dy * dy + dz * dz <= HELPER_RADIUS_SQUARED
end
function PrepCoordinator:_ready(spec: any, player: any): boolean
	if not self:_eligible(player, spec.Part) or type(spec.Ready) ~= "function" then return false end
	local ok, ready = pcall(spec.Ready, player)
	if not ok and self.Logger then self.Logger("warn", "prep action validation failed: " .. tostring(ready)) end
	return ok and ready == true
end
function PrepCoordinator:_send(serial: number, stage: string, seconds: number): boolean
	-- This is a transport seam, not a runtime remote factory. The owner must
	-- supply a preauthored remote and replay this stage to late joiners.
	if type(self.Fade) ~= "function" then return false end
	local ok, result = pcall(self.Fade, serial, stage, seconds)
	if not ok and self.Logger then self.Logger("warn", "prep fade transport failed: " .. tostring(result)) end
	return ok and result ~= false
end
function PrepCoordinator:begin(action: string, player: any): boolean
	if not self.running or self.current or not day(self.Time) then return false end
	local spec = self.Actions[action]
	if not spec or not self.Rules.BaseSeconds[action] or not self:_ready(spec, player) then return false end
	local remaining = self.Time:dayRemaining()
	if not remaining or remaining <= 0 then return false end
	self.serial = self.serial + 1
	self.current = {Serial=self.serial, Action=action, Spec=spec, Initiator=player,
		Stage="vote", Remaining=self.Rules.VoteWindowSeconds, Helpers={}}
	if not self:_send(self.serial, "vote", self.Rules.VoteWindowSeconds) then
		self.current = nil -- no client fade transport, no preparation
		return false
	end
	if self.Now then self.current.Deadline = self.Now() + self.Rules.VoteWindowSeconds end
	self:_showHelpers(action)
	return true
end
function PrepCoordinator:_remaining(tx: any): number
	if self.Now and tx.Deadline then return math.max(0, tx.Deadline - self.Now()) end
	return tx.Remaining
end
function PrepCoordinator:_prune(tx: any): number
	local count = 0
	for id, helper in pairs(tx.Helpers) do
		if not self:_eligible(helper, tx.Spec.Part) then
			tx.Helpers[id] = nil
		else
			count = count + 1
		end
	end
	return count
end
function PrepCoordinator:volunteer(action: string, player: any): boolean
	local tx = self.current
	if not tx or tx.Stage ~= "vote" or self:_remaining(tx) <= 0
		or action ~= tx.Action or not day(self.Time)
		or not self:_ready(tx.Spec, tx.Initiator) or not self:_eligible(player, tx.Spec.Part)
		or player.UserId == tx.Initiator.UserId or tx.Helpers[player.UserId] then return false end
	if self:_prune(tx) >= self.Rules.MaximumHelperDiscountSeconds then return false end
	tx.Helpers[player.UserId] = player -- distinct living OTHER players only
	return true
end
function PrepCoordinator:cancel(): ()
	local tx = self.current
	if not tx then return end
	self.current = nil
	self:_showHelpers(nil)
	-- If any client has already started fading, let it un-black without a jump.
	self:_send(tx.Serial, "cancel", FADE_OUT)
end
function PrepCoordinator:_commit(tx: any): ()
	if not day(self.Time) or not self:_ready(tx.Spec, tx.Initiator) then self:cancel(); return end
	local remaining = self.Time:dayRemaining()
	if not remaining or remaining <= 0 then self:cancel(); return end
	local count = self:_prune(tx)
	local dayLength = self.Time.Model.phaseSeconds("Day", self.Time.threat)
	local cost = self.Rules.cost(tx.Action, count, dayLength, remaining)
	if not cost or cost <= 0 then self:cancel(); return end
	-- Spec.Commit is an existing synchronous, server-validated effect method.
	-- It may fail from inventory/action contention; never pay for a failed effect.
	local ok, committed = pcall(tx.Spec.Commit, tx.Initiator)
	if not ok and self.Logger then self.Logger("warn", "prep commit failed: " .. tostring(committed)) end
	if not ok or committed ~= true then self:cancel(); return end
	local paid = self.Time:spendPrepDay(cost)
	-- No yield occurs between revalidation, commit and payment; TimeService is
	-- the only phase writer. An unexpected mismatch is an invariant breach:
	-- report it loudly, since a committed effect cannot safely be rolled back.
	if paid ~= cost and self.Logger then self.Logger("error", "prep clock did not charge full reserved cost") end
	tx.Stage, tx.Remaining = "reveal", FADE_OUT
	self:_send(tx.Serial, "reveal", FADE_OUT)
	if self.Now then tx.Deadline = self.Now() + FADE_OUT end
end
function PrepCoordinator:tick(dt: number): ()
	local tx = self.current
	if not tx or not self.running or type(dt) ~= "number" or dt <= 0 then return end
	-- Do not cross a forbidden phase even while fading. Existing services own
	-- their phase callbacks; this engine only cancels its private transaction.
	if tx.Stage ~= "reveal" and not day(self.Time) then self:cancel(); return end
	-- Advance at most ONE stage per cadence tick. A frame spike cannot broadcast
	-- blackout, jump and reveal in the same frame before any client can render.
	if self.Now then
		tx.Remaining = self:_remaining(tx)
	else -- virtual-time test adapter; live service supplies an absolute server Now
		tx.Remaining = tx.Remaining - math.min(dt, tx.Remaining)
	end
	if tx.Remaining > 1e-7 then return end
	if tx.Stage == "vote" then
		if not self:_ready(tx.Spec, tx.Initiator) then self:cancel(); return end
		tx.Stage, tx.Remaining = "blackout", FADE_IN
		self:_showHelpers(nil)
		if not self:_send(tx.Serial, "blackout", FADE_IN) then self:cancel(); return end
		if self.Now then tx.Deadline = self.Now() + FADE_IN end
	elseif tx.Stage == "blackout" then
		self:_commit(tx)
	elseif tx.Stage == "reveal" then
		self.current = nil
		self:_send(tx.Serial, "clear", 0)
		if self.OnClear then self.OnClear(tx.Action) end -- after fade, not at blackout
	end
end
function PrepCoordinator:stop(): ()
	self:cancel()
	self.running = false
	self:_showHelpers(nil)
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.connections, self.started = {}, false
end
function PrepCoordinator:snapshot(): any?
	local tx = self.current
	if not tx then return nil end
	return {serial=tx.Serial, action=tx.Action, stage=tx.Stage, remaining=self:_remaining(tx)}
end
return PrepCoordinator
