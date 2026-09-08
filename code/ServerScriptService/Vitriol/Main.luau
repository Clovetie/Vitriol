--!strict
-- Main.luau
-- Location: ServerScriptService > Vitriol > Main  (Script)
-- Purpose:  The entry point. Five lines on purpose: everything a server does is a
--            service or a handler, and an entry point that also contains logic is how
--            a boot order ends up buried in a file nobody reads.
--
--            It is the ONLY thing in the Vitriol tree that both runs on its own and is
--            a Script: a Script only executes under Workspace or ServerScriptService
--            (docs/08 §10), which is why Bootstrap is a ModuleScript in
--            ServerStorage and calls nothing itself.
-- Requires: ServerStorage.Vitriol.Bootstrap
-- Used by:  Roblox, when the place starts

local ServerStorage = game:GetService("ServerStorage")

-- ensure() is idempotent, so it does not matter that Diagnostics/Profiler may get
-- there first: whoever arrives second gets the same runtime back.
require(ServerStorage.Vitriol.Bootstrap).ensure()
