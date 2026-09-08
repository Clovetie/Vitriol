--!strict
-- DebugHandler.luau
-- Location: ServerScriptService > Vitriol > RemoteHandlers > DebugHandler  (Script)
-- Purpose:  RF_DebugQuery: read-only introspection plus the four tuning commands
--            docs/06 §8 lists, all of them going through the SAME NetContract gate as
--            gameplay traffic. A debug channel that skips validation is how a
--            "dev-only" remote becomes a server-side command interpreter in a live
--            place, so the gate is not optional and the whole handler is not bound
--            unless the config says debug is wanted.
-- Requires: Shared/Remotes, Shared/NetContract, ServerStorage.Vitriol.Bootstrap
-- Used by:  Clients/DebugConsole (WP9), a Studio command line

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local runtime = require(ServerStorage.Vitriol.Bootstrap).ensure()
local Remotes = require(ReplicatedStorage.Vitriol.Shared.Remotes)
local NetContract = require(ReplicatedStorage.Vitriol.Shared.NetContract)

local SCHEMA = "DebugQuery"
local SECONDS_PER_MILLISECOND = 1000

local function now(): number
	return DateTime.now():ToUnixTimeMillis() / SECONDS_PER_MILLISECOND
end

local gate = NetContract.newGate()

-- answers: command -> handler(player, payload) -> reply
-- Exactly the set NetContract.DebugCommands declares, and read-only: docs/06 §8's
-- four *tuning* commands (setclock, speedtime, phasetest, dumpkeyframes) belong to
-- Diagnostics/AIDebugDump, which runs in Studio and calls the setters on the services
-- (TimeService:seekTo, :setTimeScale, :seekToPhase). Keeping them off this remote is
-- the difference between an introspection channel and a remote command interpreter
-- shipped to players.
local answers = {}

function answers.help(): any
	local names = {}
	for name in pairs(answers) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function answers.clock(): any
	return runtime.Time:snapshot()
end

function answers.phases(): any
	local out = {}
	local phases = runtime.DayNight.PHASES
	for i = 1, #phases do
		local startHour = runtime.Time.Model.phaseSpan(phases[i])
		out[#out + 1] = {
			name = phases[i],
			seconds = runtime.Time.Model.phaseSeconds(phases[i], runtime.Time.threat),
			startHour = startHour,
		}
	end
	return out
end

function answers.cadence(): any
	return runtime.Cadence:summary()
end

function answers.budget(): any
	local out = {}
	local names = runtime.Cadence:slotNames()
	for i = 1, #names do
		local stats = runtime.Cadence:stats(names[i])
		if stats then
			out[names[i]] = stats
		end
	end
	out.LodTier = runtime.LodTier
	return out
end

local function onQuery(player: any, payload: any): any
	local ok, code = NetContract.admit(gate, player.UserId, SCHEMA, payload, now())
	if not ok then
		-- A reply, never a throw: a client that floods the debug remote should get a
		-- string it can print, not a disconnected instance.
		return { ok = false, code = code }
	end
	local answer = answers[payload.Command]
	if answer == nil then
		return { ok = false, code = "unknown-command", command = payload.Command }
	end
	local sent, reply = pcall(answer, player, payload)
	if not sent then
		return { ok = false, code = "handler-error", error = tostring(reply) }
	end
	return { ok = true, reply = reply }
end

if runtime.Config.Diagnostics.DebugRemoteEnabled then
	local debug = Remotes.get("RF_DebugQuery")
	if debug ~= nil then
		debug.OnServerInvoke = onQuery
	else
		Remotes.reportBindFailure("RF_DebugQuery")
	end
end
