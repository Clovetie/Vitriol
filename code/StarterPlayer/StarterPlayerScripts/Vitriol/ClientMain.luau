--!strict
-- ClientMain.luau
-- Location: StarterPlayer > StarterPlayerScripts > Vitriol > ClientMain (LocalScript)
-- Purpose:  Client entry point. Remotes are server-created; this script binds the
--           victim presentation controller once and never creates a client remote.
-- Requires: Controllers/VictimCamera, ReplicatedStorage/Vitriol/Shared/Remotes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

print("[vitriol.client] ClientMain started")
-- Wait BEFORE requiring modules from the replicated root; otherwise a delayed
-- ReplicatedStorage.Vitriol raises an indexing error before we can bind anything.
local shared = ReplicatedStorage:WaitForChild("Vitriol")
local config = shared:WaitForChild("Config")
local sharedModules = shared:WaitForChild("Shared")
local controllers = script.Parent:WaitForChild("Controllers")
local VictimCamera = require(controllers:WaitForChild("VictimCamera"))
local LightingDriver = require(controllers:WaitForChild("LightingDriver"))
local WatchController = require(controllers:WaitForChild("WatchController"))
local PrepFadeController = require(controllers:WaitForChild("PrepFadeController"))
local DayNightConfig = require(config:WaitForChild("DayNightConfig"))
local Remotes = require(sharedModules:WaitForChild("Remotes"))

local camera = VictimCamera.new({
	Players = Players,
	RunService = RunService,
	Workspace = Workspace,
	Player = Players.LocalPlayer,
})

local sky = LightingDriver.new({
	Workspace = Workspace,
	Lighting = Lighting,
	RunService = RunService,
	Config = DayNightConfig,
})
-- RE_TimeSync is an essential authored remote. Do not silently give up after a
-- startup timeout: PlayerScripts can start before ReplicatedStorage has arrived.
local comms = shared:WaitForChild(Remotes.FolderName)
local timeSync = comms:WaitForChild("RE_TimeSync")
local watch: any = nil
local fade: any = nil
local latestPhase: any = nil
local latestProgress: any = nil
local latestBudget: any = nil
local latestFade: any = nil
timeSync.OnClientEvent:Connect(function(clockMinutes: number, phase: any, progress: any, _threat: any, _night: any, _weather: any, _cycle: any, dayBudget: any, fadeState: any)
	sky:receive(clockMinutes)
	latestPhase, latestProgress, latestBudget, latestFade = phase, progress, dayBudget, fadeState
	if watch then watch:receive(phase, progress, dayBudget) end
	if fade and fadeState then fade:receive(fadeState) end
end)
print("[vitriol.client] RE_TimeSync listener bound")
sky:start()

local creatureEvent = Remotes.await("RE_CreatureEvent")
camera:bind(creatureEvent)

-- Optional watch is bound after essential clock/creature listeners. The
-- authored per-player GUI is copied with this LocalScript, not StarterGui.
watch = WatchController.new({
	Player = Players.LocalPlayer,
	Workspace = Workspace,
	Input = UserInputService,
	DayNight = DayNightConfig,
	Overlay = script:FindFirstChild("VitriolWatchOverlay"), -- engine-copied with ClientMain
	Template = script, -- contains the user's preauthored per-player Arms model
	RunService = RunService,
})
if watch then
	watch:start()
	if latestPhase then watch:receive(latestPhase, latestProgress, latestBudget) end
end
-- Draw only on the same preauthored ScreenGui's SharedFade Frame. A missing
-- optional watch must not block essential clock/creature boot or mint a GUI.
fade = PrepFadeController.new({
	Frame = watch and watch.Fade,
	RunService = RunService,
	Clock = function() return Workspace:GetServerTimeNow() end,
})
if fade and latestFade then fade:receive(latestFade) end
