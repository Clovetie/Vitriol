--!strict
-- QTEStruggleClient.luau
-- Location: StarterPlayer > StarterPlayerScripts > QTEStruggleClient (LocalScript)
-- Purpose:  The package's own boot script. One per place, and only needed if the
--           place does not already have a client bootstrap of its own.
--
--           It does three things: find the package, build the controller, and
--           optionally bind it to a server remote. Everything else (input, the
--           overlay, the frame loop, the freeze) the controller does itself.
--
-- INSTALL
--   1. ReplicatedStorage > QTE                      <- the package folder (this repo's qte/)
--   2. StarterPlayer > StarterPlayerScripts > QTEStruggleClient (LocalScript, this file)
--   3. (optional) ReplicatedStorage > QTE > Network > RE_QTE (RemoteEvent)
--      Server -> client: { qte = "start", id = "Spam" } / { qte = "beat" } /
--                        { qte = "cancel", reason = "..." }
--   4. (optional) StarterGui > QTEOverlay (ScreenGui, QTEOverlay.rbxmx)
--      Skip step 4 and the overlay is built at runtime instead.
--
-- Requires: ReplicatedStorage.QTE.Client.QTEStruggle
-- Used by:  nothing (this is the entry point)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local package = ReplicatedStorage:WaitForChild("QTE")
local QTEStruggle = require(package.Client.QTEStruggle)

-- What the controller needs is injected, so a test or a different place can build
-- it with its own services. These are the defaults for a normal player client.
local struggle = QTEStruggle.new({
	Players = Players,
	RunService = game:GetService("RunService"),
	Workspace = game:GetService("Workspace"),
	Player = Players.LocalPlayer,

	-- A fresh seed per session: which QTEs you get should not repeat every join.
	seed = os.time() % 100000,

	-- "Freeze the character while a QTE runs" is a design choice, not a rule: off,
	-- the player keeps walking during the struggle; on, the struggle is a commitment.
	freeze = false,
	preset = "Normal",
})

-- Optional server hook. Absent the remote this script still works: the controller
-- is a normal client object and the game can call struggle:start(id) whenever it
-- wants (see Client/QTEPlayground for the smallest example).
local network = package:FindFirstChild("Network")
local remote = nil
if network ~= nil then
	remote = network:FindFirstChild("RE_QTE")
end
if remote ~= nil then
	struggle:bind(remote)
end
