--!strict
-- Draws a server-timestamped shared prep fade on the existing per-player
-- SharedFade Frame. No UI creation, cloning, Tween Instances or standing loop.
-- NOT YET wired: ClientMain will feed a ninth RE_TimeSync snapshot field once
-- the server transaction is connected. Works on late joins/repeated snapshots.
local PrepFadeController = {}
PrepFadeController.__index = PrepFadeController

local RANK = {vote=1, blackout=2, reveal=3, cancel=3, clear=4}
local function valid(data: any): boolean
	return type(data) == "table" and type(data.serial) == "number"
		and data.serial == math.floor(data.serial) and data.serial >= 1
		and type(data.stage) == "string" and RANK[data.stage] ~= nil
		and type(data.startedAt) == "number" and data.startedAt == data.startedAt
		and data.startedAt ~= math.huge and data.startedAt ~= -math.huge
		and type(data.seconds) == "number" and data.seconds == data.seconds
		and data.seconds >= 0 and data.seconds <= 15
end
function PrepFadeController.new(s: any): any?
	if not s.Frame or not s.Frame:IsA("Frame") then return nil end
	local self: any = setmetatable({}, PrepFadeController)
	self.Frame, self.RunService, self.Clock = s.Frame, s.RunService, s.Clock
	self.serial, self.rank, self.stage = 0, 0, nil
	self.startedAt, self.duration, self.from, self.to = 0, 0, 0, 0
	self.opacity, self.connection, self.stopped = 0, nil, false
	self.Frame.BackgroundTransparency = 1
	self.Frame.Visible = false
	return self
end
function PrepFadeController:_disconnect(): ()
	if self.connection then self.connection:Disconnect(); self.connection = nil end
end
function PrepFadeController:_render(): ()
	if not self.stage then return end
	local progress = self.duration == 0 and 1 or math.clamp((self.Clock() - self.startedAt) / self.duration, 0, 1)
	self.opacity = self.from + (self.to - self.from) * progress
	self.Frame.BackgroundTransparency = 1 - self.opacity
	self.Frame.Visible = self.stage == "blackout" or self.opacity > 0
	if progress >= 1 then
		self:_disconnect() -- black holds its last opacity without a standing loop
		if self.to == 0 then self.Frame.Visible = false end
	end
end
function PrepFadeController:_watch(): ()
	self:_render()
	if self.connection or self.duration == 0 or self.Clock() >= self.startedAt + self.duration then return end
	self.connection = self.RunService.RenderStepped:Connect(function() self:_render() end)
end
function PrepFadeController:receive(data: any): ()
	if self.stopped or not valid(data) or data.serial < self.serial then return end
	local rank = RANK[data.stage]
	if data.serial == self.serial and rank <= self.rank then return end
	if data.serial > self.serial then
		self:_disconnect()
		self.serial, self.rank, self.opacity, self.stage = data.serial, 0, 0, nil
	end
	self.rank, self.stage = rank, data.stage
	self:_disconnect()
	if data.stage == "vote" or data.stage == "clear" then
		self.opacity, self.Frame.BackgroundTransparency, self.Frame.Visible = 0, 1, false
		return
	end
	self.startedAt, self.duration = data.startedAt, data.seconds
	if data.stage == "blackout" then
		self.from, self.to = 0, 1
	elseif data.stage == "reveal" then
		-- An arriving client missed the blackout, but still sees the remaining
		-- reveal time instead of a suddenly visible black rectangle.
		self.from, self.to = 1, 0
	else -- cancel, potentially while still fading into blackout
		self.from, self.to = self.opacity, 0
	end
	self:_watch()
end
function PrepFadeController:stop(): ()
	self.stopped = true
	self:_disconnect()
	self.stage, self.opacity = nil, 0
	self.Frame.BackgroundTransparency = 1
	self.Frame.Visible = false
end
return PrepFadeController
