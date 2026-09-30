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

local player = Players.LocalPlayer

-- Collect the remotes by name. If one is missing the client still starts and
-- says so; a nil-index crash on join is a worse failure than a degraded
-- screen, and the player has lost nothing either way.
local remotes = {}
for _, row in ipairs(NetContract.REMOTES) do
	local name = row[1]
	local instance = Tidekeeper:FindFirstChild(name)
	if instance == nil then
		warn("[Tidekeeper] remote missing: " .. name)
	else
		remotes[name] = instance
	end
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
	local reply, why = app:requestSession()
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
