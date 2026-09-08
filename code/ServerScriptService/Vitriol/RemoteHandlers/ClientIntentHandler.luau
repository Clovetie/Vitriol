--!strict
-- ClientIntentHandler.luau
-- Location: ServerScriptService > Vitriol > RemoteHandlers > ClientIntentHandler  (Script)
-- Purpose:  The I/O half of RE_ClientIntent. NetContract decides whether a payload is
--            admissible; this file is where that decision is applied to the world, and
--            where a rejected message is counted instead of throwing.
--
--            WHY VALIDATION IS NOT IN A SERVICE. The contract is pure data so it can be
--            executed by the headless harness (docs/01 §13); binding a RemoteEvent is
--            not pure, so the handler keeps the two apart: connect, admit, route.
--            Every route is looked up in a table that services fill at boot, which is
--            also the answer to "what happens before DestructionService exists":
--            nothing, and the reason is logged.
-- Requires: Shared/Remotes, Shared/NetContract, ServerStorage.Vitriol.Bootstrap
-- Used by:  Roblox (runs itself)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local runtime = require(ServerStorage.Vitriol.Bootstrap).ensure()
local Remotes = require(ReplicatedStorage.Vitriol.Shared.Remotes)
local NetContract = require(ReplicatedStorage.Vitriol.Shared.NetContract)

local SCHEMA = "ClientIntent"
local SECONDS_PER_MILLISECOND = 1000

-- now() -> seconds
-- DateTime rather than os.clock: os.clock is CPU time, and a rate limiter that counts
-- CPU time rewards a spammer for making the server busy.
local function now(): number
	return DateTime.now():ToUnixTimeMillis() / SECONDS_PER_MILLISECOND
end

local gate = NetContract.newGate()
local routes = {}

-- groupOf: the action -> owning-group map, built from GameConfig.Intents so this file
-- does not know any action by name. An action missing from the config would be
-- rejected by the schema long before it got here.
local groupOf = {}
do
	local groups = runtime.Config.Intents
	for g = 1, #groups do
		local list = groups[g].Actions
		for i = 1, #list do
			groupOf[list[i]] = groups[g].Group
		end
	end
end

-- route(svc, group, fn) -> ()
-- Services register the handler for their intent group. An intent whose group has no
-- service yet is admitted (so the rate limiter is the only cost a client can impose)
-- and then dropped with one log line, never applied by a guess.
function runtime.routeIntent(group: string, fn: any): ()
	routes[group] = fn
end

local function onIntent(player: any, payload: any): ()
	local ok, code, extra = NetContract.admit(gate, player.UserId, SCHEMA, payload, now())
	if not ok then
		-- The ONLY reaction a malformed payload gets. No error(), no kick, no state
		-- change: an exploiter wants the server to throw, and a false positive on a
		-- slow client is a player who gets kicked for lagging.
		runtime.rejectedIntents = (runtime.rejectedIntents or 0) + 1
		if runtime.Config.Diagnostics.LogNetRejections then
			print("[" .. runtime.Config.Diagnostics.Prefix .. "] rejected " .. tostring(code) .. " from " .. player.Name .. " (" .. tostring(extra) .. ")")
		end
		return
	end
	local route = routes[groupOf[payload.Action]]
	if route == nil then
		-- Admitted, validated, and then dropped: WP4 has no DestructionService or
		-- SurvivalService yet. A count rather than a log line per packet, because an
		-- exploiter's cheapest denial-of-service on a debug-less server is to send
		-- valid intents forever.
		runtime.unroutedIntents = (runtime.unroutedIntents or 0) + 1
		return
	end
	-- pcall because a route is other people's code, and a throw in a handler must not
	-- take the connection down with it: the gate would survive, the remote would not.
	local applied, err = pcall(route, player, payload)
	if not applied then
		runtime.log("error", "intent route " .. tostring(payload.Action) .. " errored: " .. tostring(err))
	end
end

local intent = Remotes.get("RE_ClientIntent")
if intent ~= nil then
	intent.OnServerEvent:Connect(onIntent)
	-- A player who leaves mid-stream would otherwise keep a token bucket and a
	-- sequence number alive for a UserId that never returns.
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		NetContract.forget(gate, player.UserId)
	end)
else
	Remotes.reportBindFailure("RE_ClientIntent")
end

-- The answer to "what did the network actually send us", for RF_DebugQuery.
function runtime.intentStats(): any
	local stats = NetContract.stats(gate)
	stats.rejected = runtime.rejectedIntents or 0
	stats.unrouted = runtime.unroutedIntents or 0
	return stats
end
