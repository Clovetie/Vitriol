--!nonstrict
-- ReplicatedStorage/Tidekeeper/Shared/Version (ModuleScript)
--
-- Schema versions and the migration registry (doc 05 section 6).
--
-- Three rules, and they are not negotiable once the game is live:
--   1. Every persisted blob starts with a version byte.
--   2. A migration is NEVER deleted. The chain from OLDEST_SUPPORTED to
--      CURRENT must stay walkable forever, because a player who has not logged
--      in for two years still owns a v1 blob.
--   3. A blob NEWER than the running server is REFUSED, never guessed at. A
--      server that half-understands a future save destroys it.
--
-- Pure: this module knows nothing about DataStores. It transforms tables.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Version = {}

Version.CURRENT = GameConfig.SCHEMA_VERSION
Version.OLDEST_SUPPORTED = GameConfig.OLDEST_SUPPORTED_VERSION

Version.OK = "OK"
Version.TOO_OLD = "TOO_OLD"
Version.TOO_NEW = "TOO_NEW"
Version.NO_PATH = "NO_PATH"

-- [from] = { to = <number>, apply = function(data) -> data }
local migrations = {}

-- Register a single-step migration. Steps must be strictly increasing by one
-- so the chain is unambiguous; a fork in the graph is a bug, not a feature.
function Version.register(from, to, apply)
	assert(type(from) == "number" and type(to) == "number", "Version.register: versions must be numbers")
	assert(to == from + 1, "Version.register: migrations must advance exactly one version at a time")
	assert(type(apply) == "function", "Version.register: apply must be a function")
	assert(migrations[from] == nil, "Version.register: a migration from version " .. from .. " already exists")
	migrations[from] = { to = to, apply = apply }
	return true
end

function Version.hasMigration(from)
	return migrations[from] ~= nil
end

function Version.registeredCount()
	local n = 0
	for _ in pairs(migrations) do
		n = n + 1
	end
	return n
end

-- Test-only: used by the harness to prove the chain walker without shipping a
-- fake migration. Never called by game code.
function Version._reset()
	migrations = {}
	return true
end

-- Classify a version byte before doing anything with the payload.
function Version.classify(version)
	if type(version) ~= "number" or version ~= math.floor(version) then
		return Version.NO_PATH, "version is not an integer"
	end
	if version > Version.CURRENT then
		return Version.TOO_NEW,
			string.format("blob version %d is newer than this server's %d; refusing to touch it", version, Version.CURRENT)
	end
	if version < Version.OLDEST_SUPPORTED then
		return Version.TOO_OLD, string.format("blob version %d is older than the oldest supported %d", version, Version.OLDEST_SUPPORTED)
	end
	if version == Version.CURRENT then
		return Version.OK, nil
	end
	local at = version
	while at < Version.CURRENT do
		local step = migrations[at]
		if step == nil then
			return Version.NO_PATH, string.format("no migration registered from version %d", at)
		end
		at = step.to
	end
	return Version.OK, nil
end

-- Walk `data` from `version` up to CURRENT. Returns `(data, nil)` on success or
-- `(nil, reason, message)` on failure. Never mutates the input on a failure
-- path: each step's output replaces the previous value only once it succeeded.
function Version.migrate(data, version)
	local status, message = Version.classify(version)
	if status ~= Version.OK then
		return nil, status, message
	end
	local at = version
	local current = data
	while at < Version.CURRENT do
		local step = migrations[at]
		local ok, result = pcall(step.apply, current)
		if not ok then
			return nil, Version.NO_PATH, string.format("migration %d -> %d failed: %s", at, step.to, tostring(result))
		end
		current = result
		at = step.to
	end
	return current, nil
end

return Version
