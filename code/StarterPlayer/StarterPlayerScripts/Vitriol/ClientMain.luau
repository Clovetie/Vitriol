--!strict
-- ClientMain.luau
-- Location: StarterPlayer > StarterPlayerScripts > Vitriol > ClientMain (LocalScript)
-- Purpose:  Client entry point. Remotes are server-created; this script binds the
--           victim presentation controller once and never creates a client remote.
-- Requires: Controllers/VictimCamera, Controllers/QTEStruggle,
--           ReplicatedStorage/Vitriol/Shared/Remotes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VictimCamera = require(script.Parent.Controllers.VictimCamera)
local QTEStruggle = require(script.Parent.Controllers.QTEStruggle)
local Remotes = require(ReplicatedStorage.Vitriol.Shared.Remotes)

local camera = VictimCamera.new({
	Players = Players,
	RunService = RunService,
	Workspace = Workspace,
	Player = Players.LocalPlayer,
})

local struggle = QTEStruggle.new({
	Players = Players,
	RunService = RunService,
	Workspace = Workspace,
	Player = Players.LocalPlayer,
})

local creatureEvent = Remotes.await("RE_CreatureEvent")
camera:bind(creatureEvent)
-- The server starts struggle QTEs over the same creature event the camera watches
-- (docs/11 §8); the client reports the outcome back through an intent, and the
-- server decides what it means.
struggle:bind(creatureEvent)
