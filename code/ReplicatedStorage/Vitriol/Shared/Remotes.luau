--!strict
-- Remotes.luau
-- Location: ReplicatedStorage > Vitriol > Shared > Remotes  (ModuleScript)
-- Purpose:  THE ONLY PLACE REMOTES ARE CREATED, and the only place their names are
--           written down. Exactly the set in docs/01-ARCHITECTURE.md §2 - no
--           remote is ever invented ad hoc by a feature.
--
--           Rules this module encodes:
--           * SERVER creates (init), CLIENT binds (WaitForChild + timeout). A client
--             never creates an Instance, and a bind that times out is reported once
--             rather than retried every frame.
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

-- ensureFolder() -> Instance
-- Creates ReplicatedStorage.Vitriol.Comms if it is not there yet. In a real place
-- the folder ships authored; in a test/studio-play place this lets the whole
-- project boot from code alone.
local function ensureFolder(): any
	local root = storage()
	local container = root:FindFirstChild("Vitriol")
	if container == nil then
		container = Instance.new("Folder")
		container.Name = "Vitriol"
		container.Parent = root
	end
	local comms = container:FindFirstChild(FOLDER_NAME)
	if comms == nil then
		comms = Instance.new("Folder")
		comms.Name = FOLDER_NAME
		comms.Parent = container
	end
	return comms
end

-- init() -> createdCount
-- Server only, idempotent. Creates every remote in the definition list; re-running
-- it after an external script deleted one repairs the set. One GetChildren pass
-- builds the present-set rather than N FindFirstChild calls, and the same pass is
-- what lets this module POLICE its own folder: a remote authored in Studio outside
-- the contract is exactly the "ad hoc remote" rule this file exists to prevent.
function Remotes.init(): number
	if not isServer() then
		warn("[Vitriol.Remotes] init() called on a client - remotes are server-created")
		return 0
	end
	local comms = ensureFolder()
	local present = {}
	for _, child in ipairs(comms:GetChildren()) do
		present[child.Name] = child
	end
	local created = 0
	for i = 1, #Remotes.Definition do
		local def = Remotes.Definition[i]
		local existing = present[def.Name]
		if existing == nil then
			local remote = Instance.new(def.Class)
			remote.Name = def.Name
			remote.Parent = comms
			cache[def.Name] = remote
			created = created + 1
		else
			present[def.Name] = nil
			if existing.Class ~= def.Class then
				-- A class mismatch means somebody authored a remote in Studio with a
				-- different class than the contract. That cannot be repaired at
				-- runtime without destroying their instance, so it is a loud error.
				error(("[Vitriol.Remotes] %s exists as %s, contract says %s"):format(def.Name, existing.Class, def.Class), 0)
			end
			cache[def.Name] = existing
		end
	end
	for name in pairs(present) do
		warn(("[Vitriol.Remotes] stray remote %s in Comms: it is not in the contract. Delete it, or add it to Remotes.Definition and a NetContract schema."):format(name))
	end
	initialised = true
	return created
end

-- get(name) -> Instance?
-- Never creates on a client. On the server it will initialise itself if nothing did
-- yet, because services are started in an order that this must not depend on.
function Remotes.get(name: string): any
	local cached = cache[name]
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end
	if BY_NAME[name] == nil then
		error(("[Vitriol.Remotes] %s is not in the contract; add it to Remotes.Definition (and a NetContract schema if a client sends it)"):format(name), 0)
	end
	if not isServer() then
		return Remotes.await(name)
	end
	if not initialised then
		Remotes.init()
		return cache[name]
	end
	local comms = ensureFolder()
	local def = BY_NAME[name]
	local remote = Instance.new(def.Class)
	remote.Name = name
	remote.Parent = comms
	cache[name] = remote
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
	local comms = storage():FindFirstChild("Vitriol")
	if comms == nil then
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
	warn(("[Vitriol.Remotes] WaitForChild timed out for %s after %ss - the server never created it"):format(what, tostring(BIND_TIMEOUT_SECONDS)))
end

-- bindAll(timeoutSeconds?) -> ok, missingNames
-- Client boot path: bind the whole contract once, and report what is absent so the
-- caller can decide whether a feature is worth disabling. Called from ClientMain.
function Remotes.bindAll(timeoutSeconds: number?): boolean, any
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
