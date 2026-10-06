--!nonstrict
-- StarterPlayer/StarterPlayerScripts/Tidekeeper/Main.client (LocalScript)
--
-- THE ONLY CLIENT SCRIPT IN THE GAME, and the only place on the client that
-- touches `game`. Everything below it is a pure module that receives what it
-- needs as an argument (see Client/ClientBootstrap).
--
-- It mirrors `ServerScriptService/Tidekeeper/Main.server.luau` exactly:
-- resolve the platform, build the composition root, make ONE connection.
--
-- ONE CONNECTION. Doc 01 section 5 allows the server exactly one RunService
-- connection, owned by CadenceService. The client gets exactly one too, for
-- the same reason: a second connection is frame time that no budget accounts
-- for and no profiler attributes to anything. Every screen redraws from this
-- tick, and only when the model is dirty.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")
local ClientBootstrap = require(Tidekeeper.Client.ClientBootstrap)
local NetContract = require(Tidekeeper.Shared.NetContract)
local Remotes = require(Tidekeeper.Shared.Remotes)

local player = Players.LocalPlayer

-- Remotes come from `Remotes.await`, which is the client half of the single
-- sanctioned remote factory (doc 01 section 4). It is not a convenience.
--
-- An earlier version of this file hand-rolled the lookup as
-- `Tidekeeper:FindFirstChild(name)`, and it was wrong in two independent
-- ways, either of which alone makes the game unplayable for every player:
--
--   1. WRONG PARENT. `Remotes.build` puts them in a SIBLING folder,
--      ReplicatedStorage/TidekeeperRemotes, not inside the module tree
--      ReplicatedStorage/Tidekeeper. All seven lookups returned nil, the
--      client warned seven times and started with no remotes at all, and
--      every session request answered "offline" forever.
--   2. NO WAIT. Even at the right path, `FindFirstChild` is a race against
--      replication on join. `await` uses WaitForChild with a timeout.
--
-- Nothing caught this for two iterations because no test constructs an
-- Instance. The lesson is in the shape of the bug, not the typo: the client
-- re-derived a path that the server owns, instead of calling the function
-- whose entire job is to know it.
local remotes, remotesWhy = Remotes.await(30)
if remotes == nil then
	warn("[Tidekeeper] remotes unavailable: " .. tostring(remotesWhy))
	remotes = {}
end

local app = ClientBootstrap.start({
	remotes = remotes,
	clock = os.time,
	userId = player.UserId,
	logger = function(scope, message)
		warn("[Tidekeeper/" .. tostring(scope) .. "] " .. tostring(message))
	end,
})

-- Server -> client pushes.
local snapshotRemote = remotes[NetContract.RE_POST_SNAPSHOT]
if snapshotRemote ~= nil then
	snapshotRemote.OnClientEvent:Connect(function(snapshot)
		app:applySnapshot(snapshot)
	end)
end

local ledgerRemote = remotes[NetContract.RE_LEDGER_BATCH]
if ledgerRemote ~= nil then
	ledgerRemote.OnClientEvent:Connect(function(entries)
		app:applyLedgerBatch(entries or {})
	end)
end

-- Ask for the session once. The reply carries the post and the Ledger, and
-- the Ledger takes the screen on arrival (doc 08 section 2: it slides up on
-- its own, at 0:02, and it is not empty).
task.spawn(function()
	-- KEEP ASKING. The first real Studio run asked once, half a second after
	-- the server came up, got "your post is still coming out of the water"
	-- -- which is E_NO_POST, meaning the join is still in flight -- and gave
	-- up permanently. The Ledger is the game's opening and it never arrived.
	local reply, why = app:awaitSession()
	if reply == nil then
		warn("[Tidekeeper] session unavailable: " .. tostring(why))
		return
	end
	app:setScreen(ClientBootstrap.SCREEN_LEDGER)
end)

-- THE single connection.
RunService.Heartbeat:Connect(function()
	app:step(os.time())
end)
