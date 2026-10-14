--!strict
-- Remotes.luau
-- Location: ReplicatedStorage > Vitriol > Shared > Remotes  (ModuleScript)
-- Purpose:  The registry of EDIT-MODE-AUTHORED remotes; never creates Instances.
--           Exactly the set in docs/01-ARCHITECTURE.md §2 - no remote is
--           invented ad hoc by a feature.
--
--           Rules this module encodes:
--           * SERVER validates authored remotes (init), CLIENT binds with
--             WaitForChild + timeout. Neither side creates them at runtime.
--           * Every client->server entry names a NetContract schema, so no inbound
--             remote can exist without a validator. 'coverageProblems' is the test
--             that keeps that true as the set grows.
--           * A payload here is a Buffer or plain data - never an Instance. Sending
--             an Instance reference through a remote gives the client a handle to
--             something it does not own; the server looks things up by id instead.
--
--           Requires nothing but Config, and touches no service at load time (the
--           DataModel is looked up lazily inside the functions) so the headless
--           harness can assert the whole contract without Studio.
-- Requires: Config/GameConfig
-- Used by:  ServerScriptService > Vitriol > Bootstrap, every Service, every
--           Controller, ServerScriptService > Vitriol > RemoteHandlers/*

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Remotes = {}

-- The complete set. 'Direction' is documentary + the basis of the coverage test;
-- 'Schema' is the NetContract validator applied to anything coming IN from a
-- client. Server->client payloads are validated by the SENDER owning the state and
-- need no inbound validator, which is why they have no Schema field.
-- (docs/01-ARCHITECTURE.md §2 Comms folder, §3 ownership table.)
Remotes.Definition = {
	{
		Name = "RE_TimeSync",
		Class = "RemoteEvent",
		Direction = "ServerToClient",
		Owner = "TimeService",
		Notes = "clock/threat snapshot: low rate, plus a catch-up burst on join",
	},
	{
		Name = "RE_SkeletonStream",
		Class = "RemoteEvent",
		Direction = "ServerToClient",
		Owner = "Creature/Replicator",
		Notes = "one Buffer per creature per snapshot (docs/03 §7.1)",
	},
	{
		Name = "RE_CreatureEvent",
		Class = "RemoteEvent",
		Direction = "ServerToClient",
		Owner = "CreatureCore",
		Notes = "moments, not state: roar/impact/breach/grab/coil/sever/consume/flinch",
	},
	{
		Name = "RE_SurvivalSync",
		Class = "RemoteEvent",
		Direction = "ServerToClient",
		Owner = "SurvivalService",
		Notes = "meter/debuff deltas, to the owner only",
	},
	{
		Name = "RE_ClientIntent",
		Class = "RemoteEvent",
		Direction = "ClientToServer",
		Owner = "RemoteHandlers/ClientIntentHandler",
		Schema = "ClientIntent",
		Notes = "attune/consume/interact intents - the only routine client input",
	},
	{
		Name = "RE_Destruction",
		Class = "RemoteEvent",
		Direction = "ServerToClient",
		Owner = "DestructionService",
		Notes = "joint break + debris spawn",
	},
	{
		Name = "RF_DebugQuery",
		Class = "RemoteFunction",
		Direction = "ClientToServer",
		Owner = "RemoteHandlers/DebugHandler",
		Schema = "DebugQuery",
		Notes = "permission-gated introspection; returns a table",
	},
}

local BY_NAME = {}
for i = 1, #Remotes.Definition do
	local def = Remotes.Definition[i]
	BY_NAME[def.Name] = def
end

local NET = GameConfig.Net
local FOLDER_NAME = NET.CommsFolder
local BIND_TIMEOUT_SECONDS = NET.BindTimeoutSeconds

Remotes.FolderName = FOLDER_NAME
Remotes.BindTimeoutSeconds = BIND_TIMEOUT_SECONDS

local cache = {}
local missing = {}
local initialised = false
local services = nil

-- _storage() -> ReplicatedStorage   (lazily, so 'require' is safe anywhere)
local function storage(): any
	if services == nil then
		services = { storage = game:GetService("ReplicatedStorage"), run = game:GetService("RunService") }
	end
	return services.storage
end

local function isServer(): boolean
	storage() -- ensures 'services' exists
	return services.run:IsServer()
end

-- definition(name) -> table? - the metadata for one remote (class, direction, owner)
function Remotes.definition(name: string): any
	return BY_NAME[name]
end

-- names() -> {string} in declaration order
function Remotes.names(): any
	local out = {}
	for i = 1, #Remotes.Definition do
		out[i] = Remotes.Definition[i].Name
	end
	return out
end

-- clientToServer() -> {definition} - everything the server must validate
function Remotes.clientToServer(): any
	local out = {}
	local n = 0
	for i = 1, #Remotes.Definition do
		local def = Remotes.Definition[i]
		if def.Direction == "ClientToServer" then
			n = n + 1
			out[n] = def
		end
	end
	return out
end

-- init() -> 0; validate the authored tree before any gameplay starts.
-- A missing or wrong-class remote is a deployment error, never repaired in Play mode.
function Remotes.init(): number
	if not isServer() then
		error("[Vitriol.Remotes] init is server-only", 0)
	end
	local container = storage():FindFirstChild("Vitriol")
	local comms = container and container:FindFirstChild(FOLDER_NAME)
	if comms == nil or not comms:IsA("Folder") then
		error("[Vitriol.Remotes] missing authored ReplicatedStorage.Vitriol." .. FOLDER_NAME, 0)
	end
	local present = {}
	for _, child in ipairs(comms:GetChildren()) do
		if present[child.Name] then
			error("[Vitriol.Remotes] duplicate remote " .. child.Name, 0)
		end
		present[child.Name] = child
	end
	for i = 1, #Remotes.Definition do
		local def = Remotes.Definition[i]
		local remote = present[def.Name]
		if remote == nil or remote.ClassName ~= def.Class then
			error(("[Vitriol.Remotes] missing/wrong-class authored remote %s (expected %s)"):format(def.Name, def.Class), 0)
		end
		present[def.Name] = nil
		cache[def.Name] = remote
	end
	for name in pairs(present) do
		error("[Vitriol.Remotes] stray child in Comms: " .. name, 0)
	end
	initialised = true
	return 0
end

-- get(name) -> pre-authored Instance. No repair or creation in Play mode.
function Remotes.get(name: string): any
	if BY_NAME[name] == nil then
		error("[Vitriol.Remotes] unknown remote " .. tostring(name), 0)
	end
	if not isServer() then
		return Remotes.await(name)
	end
	if not initialised then
		Remotes.init()
	end
	local remote = cache[name]
	if remote == nil or remote.Parent == nil then
		error("[Vitriol.Remotes] authored remote removed during play: " .. name, 0)
	end
	return remote
end

-- await(name, timeoutSeconds?) -> Instance?
-- The client path: WaitForChild WITH a timeout, so a missing remote degrades to a
-- warning and a feature running without replication rather than a yielded client
-- that hangs forever. The result is cached either way; 'lastBindFailure' lets the
-- caller report it once.
function Remotes.await(name: string, timeoutSeconds: number?): any
	local cached = cache[name]
	if cached ~= nil then
		return cached
	end
	-- StarterPlayerScripts can run before ReplicatedStorage.Vitriol replicates.
	-- A non-yielding FindFirstChild could silently return nil here, causing
	-- optional client remote binds to be skipped during a replication race.
	local comms = storage():WaitForChild("Vitriol", timeoutSeconds or BIND_TIMEOUT_SECONDS)
	if comms == nil then
		Remotes.reportBindFailure("ReplicatedStorage.Vitriol")
		return nil
	end
	local folder = comms:WaitForChild(FOLDER_NAME, timeoutSeconds or BIND_TIMEOUT_SECONDS)
	if folder == nil then
		Remotes.reportBindFailure("folder " .. FOLDER_NAME)
		return nil
	end
	local remote = folder:WaitForChild(name, timeoutSeconds or BIND_TIMEOUT_SECONDS)
	if remote == nil then
		Remotes.reportBindFailure(name)
		return nil
	end
	cache[name] = remote
	return remote
end

function Remotes.reportBindFailure(what: string): ()
	if missing[what] then
		return
	end
	missing[what] = true
	warn(("[Vitriol.Remotes] WaitForChild timed out for %s after %ss - missing or not yet replicated"):format(what, tostring(BIND_TIMEOUT_SECONDS)))
end

-- bindAll(timeoutSeconds?) -> ok, missingNames
-- Client boot path: bind the whole contract once, and report what is absent so the
-- caller can decide whether a feature is worth disabling. Called from ClientMain.
function Remotes.bindAll(timeoutSeconds: number?): (boolean, any)
	local absent = {}
	local n = 0
	for i = 1, #Remotes.Definition do
		local def = Remotes.Definition[i]
		if Remotes.await(def.Name, timeoutSeconds) == nil then
			n = n + 1
			absent[n] = def.Name
		end
	end
	return n == 0, absent
end

-- coverageProblems(schemas) -> {problem strings}
-- Pure form of the contract test (the same one the smoke test runs) so it can also
-- be called from a boot-time check with the real NetContract table: every remote
-- exists once, with a legal class, and every client->server remote has a schema.
function Remotes.coverageProblems(schemas: any): any
	local problems = {}
	local n = 0
	local seen = {}
	for i = 1, #Remotes.Definition do
		local def = Remotes.Definition[i]
		if seen[def.Name] then
			n = n + 1
			problems[n] = def.Name .. ": declared twice"
		end
		seen[def.Name] = true
		if def.Class ~= "RemoteEvent" and def.Class ~= "RemoteFunction" then
			n = n + 1
			problems[n] = def.Name .. ": class must be RemoteEvent or RemoteFunction"
		end
		if def.Direction == "ClientToServer" and def.Schema == nil then
			n = n + 1
			problems[n] = def.Name .. ": client-to-server with no schema"
		end
		if def.Schema ~= nil and schemas[def.Schema] == nil then
			n = n + 1
			problems[n] = def.Name .. ": schema " .. tostring(def.Schema) .. " is not defined"
		end
	end
	return problems
end

return Remotes
