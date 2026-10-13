--!strict
-- LightingDriver.luau
-- Location: StarterPlayer > StarterPlayerScripts > Vitriol > Controllers (ModuleScript)
-- Purpose: Client-only presentation of TimeService's authored clock. No UI,
--          Lighting Instances, skyboxes or post-processing objects are created.
--          TimeService alone owns phase/time; this controller only paints it.

local LightingDriver = {}
LightingDriver.__index = LightingDriver

local function blend(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function color(a: any, b: any, t: number): any
	return Color3.fromRGB(blend(a[1], b[1], t), blend(a[2], b[2], t), blend(a[3], b[3], t))
end

local function writeNumber(object: any, key: string, value: number, epsilon: number): ()
	if math.abs(object[key] - value) > epsilon then object[key] = value end
end

local function writeColor(object: any, key: string, value: any): ()
	local old = object[key]
	if old == nil or math.abs(old.R - value.R) > 1 / 255 or math.abs(old.G - value.G) > 1 / 255
		or math.abs(old.B - value.B) > 1 / 255 then object[key] = value end
end

function LightingDriver.new(options: any): any
	local self = setmetatable({}, LightingDriver)
	self.Workspace = options.Workspace
	self.Lighting = options.Lighting
	self.RunService = options.RunService
	self.Config = options.Config
	self.Hour = nil
	self.RemoteClock = nil
	self.Anchor = nil
	self.Connection = nil
	return self
end

function LightingDriver:_sample(hour: number): (any, any, number)
	local frames = self.Config.Keyframes
	local a, b = frames[#frames], frames[1]
	local h = hour
	for i = 1, #frames - 1 do
		if hour >= frames[i].Hour and hour < frames[i + 1].Hour then
			a, b = frames[i], frames[i + 1]
			break
		end
	end
	if b.Hour <= a.Hour then
		if h < a.Hour then
			h += 24
		end
	end
	local span = (b.Hour <= a.Hour and b.Hour + 24 or b.Hour) - a.Hour
	local t = math.clamp((h - a.Hour) / math.max(span, 0.001), 0, 1)
	return a, b, t * t * (3 - 2 * t)
end

function LightingDriver:paint(hour: number): ()
	local a, b, t = self:_sample(hour % 24)
	local lighting = self.Lighting
	writeNumber(lighting, "ClockTime", hour % 24, 0.001)
	writeNumber(lighting, "Brightness", blend(a.Brightness, b.Brightness, t), 0.002)
	writeNumber(lighting, "ExposureCompensation", blend(a.ExposureCompensation, b.ExposureCompensation, t), 0.002)
	writeNumber(lighting, "ShadowSoftness", blend(a.ShadowSoftness, b.ShadowSoftness, t), 0.002)
	writeNumber(lighting, "EnvironmentDiffuseScale", blend(a.EnvironmentDiffuseScale, b.EnvironmentDiffuseScale, t), 0.002)
	writeNumber(lighting, "EnvironmentSpecularScale", blend(a.EnvironmentSpecularScale, b.EnvironmentSpecularScale, t), 0.002)
	writeNumber(lighting, "FogStart", blend(a.Fog.Start, b.Fog.Start, t), 0.5)
	writeNumber(lighting, "FogEnd", blend(a.Fog.End, b.Fog.End, t), 0.5)
	writeColor(lighting, "Ambient", color(a.Ambient, b.Ambient, t))
	writeColor(lighting, "OutdoorAmbient", color(a.OutdoorAmbient, b.OutdoorAmbient, t))
	writeColor(lighting, "FogColor", color(a.Fog.Color, b.Fog.Color, t))
end

-- RE_TimeSync is a server-to-client clock snapshot. Consume it (do not leave
-- Roblox's invocation queue unbound); the authored anchor remains the fallback.
function LightingDriver:receive(clockMinutes: any): ()
	if type(clockMinutes) == "number" and clockMinutes >= 0 and clockMinutes < 1440 then
		self.RemoteClock = clockMinutes
	end
end

function LightingDriver:step(dt: number): ()
	if self.Anchor == nil then
		local vitriol = self.Workspace:FindFirstChild("Vitriol")
		local world = vitriol and vitriol:FindFirstChild("World")
		self.Anchor = world and world:FindFirstChild("TimeAnchor")
	end
	local published = self.RemoteClock or (self.Anchor and self.Anchor:GetAttribute("ClockMinutes"))
	if type(published) ~= "number" then return end
	local target = (published / 60) % 24
	if self.Hour == nil then
		self.Hour = target -- joining mid-night should never flash the old daytime sky
	else
		local delta = (target - self.Hour + 12) % 24 - 12
		self.Hour = (self.Hour + delta * (1 - math.exp(-math.max(dt, 0) * 5))) % 24
	end
	self:paint(self.Hour)
end

function LightingDriver:start(): ()
	if self.Connection then return end
	self.Connection = self.RunService.RenderStepped:Connect(function(dt: number)
		self:step(dt)
	end)
end

function LightingDriver:stop(): ()
	if not self.Connection then return end
	self.Connection:Disconnect()
	self.Connection = nil
end

return LightingDriver
