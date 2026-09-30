--!nonstrict
-- ReplicatedStorage/Tidekeeper/Shared/NetContract (ModuleScript)
--
-- Layer: Shared. PURE -- it validates payloads, it does not touch remotes.
-- `Shared/Remotes` creates the Instances; this decides what is allowed
-- through them. Splitting the two is what lets the whole remote surface be
-- tested headlessly.
--
-- Three defences, in the order they are cheapest:
--
--   1. RATE      a token bucket per (player, remote). Refills from the `now`
--                argument, so it is testable and cannot be defeated by a
--                clock read inside the module.
--   2. SEQUENCE  a monotonic counter per (player, remote). A replayed or
--                reordered packet is dropped, which closes the "fire the
--                same purchase twice" shape.
--   3. SHAPE     a declarative Lib/Schema spec per remote.
--
-- The order matters: shape validation walks a table, rate limiting does not,
-- and the flood case is the one that has to stay cheap.
--
-- NO REMOTE ACCEPTS FREE TEXT (doc 13 section 2). Not one spec below contains
-- a string field, and `NetContract.hasNoStringFields` proves it by walking the
-- compiled specs. That assertion runs in the harness, so the rule cannot be
-- broken by a future edit that merely looks reasonable.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local FindsConfig = require(script.Parent.Parent.Config.FindsConfig)
local Schema = require(script.Parent.Parent.Lib.Schema)

local NetContract = {}

-- Remote names. These are the Instance names under ReplicatedStorage, and
-- they are the keys of every table in this module.
NetContract.RF_SESSION = "RF_Session"
NetContract.RF_SET_ORDERS = "RF_SetOrders"
NetContract.RF_ARRANGE = "RF_Arrange"
NetContract.RF_COMB = "RF_Comb"
NetContract.RF_DISPATCH = "RF_Dispatch"
NetContract.RE_POST_SNAPSHOT = "RE_PostSnapshot"
NetContract.RE_LEDGER_BATCH = "RE_LedgerBatch"

-- doc 01 section 4. { name, direction, burst, perMinute }
-- direction 1 = client -> server function, 2 = server -> client event.
NetContract.REMOTES = {
	{ "RF_Session", 1, 2, 1 },
	{ "RF_SetOrders", 1, 3, 6 },
	{ "RF_Arrange", 1, 8, 30 },
	{ "RF_Comb", 1, 10, 40 },
	{ "RF_Dispatch", 1, 2, 4 },
	{ "RE_PostSnapshot", 2, 0, 0 },
	{ "RE_LedgerBatch", 2, 0, 0 },
}

local COL_NAME = 1
local COL_DIR = 2
local COL_BURST = 3
local COL_PER_MINUTE = 4

NetContract.DIR_C2S = 1
NetContract.DIR_S2C = 2

-- ------------------------------------------------------------------ specs

-- An orders program arrives as the encoded byte array of Domain/Orders, not
-- as a table of rules: the interpreter's own encoder is the only thing
-- allowed to produce one, and a byte array has no shape to attack.
local SPEC_SET_ORDERS = Schema.map({
	seq = Schema.int(1, 4294967295),
	bytes = Schema.array(Schema.int(0, 255), 1, GameConfig.MAX_ORDERS_BYTES),
}, true)

local SPEC_ARRANGE = Schema.map({
	seq = Schema.int(1, 4294967295),
	slot = Schema.int(1, GameConfig.MAX_SHELF_SLOTS),
	-- findId 0 means "clear this shelf".
	findId = Schema.int(0, FindsConfig.MAX_FIND_ID),
	price = Schema.int(0, EconomyConfig.MAX_PRICE),
}, true)

local SPEC_COMB = Schema.map({
	seq = Schema.int(1, 4294967295),
	zoneId = Schema.int(1, FindsConfig.ZONE_COUNT),
	nodeId = Schema.int(1, GameConfig.MAX_COMB_NODES),
}, true)

local SPEC_DISPATCH = Schema.map({
	seq = Schema.int(1, 4294967295),
	-- Targets are exchange-chosen slot indices, never user ids: the client
	-- may say "the second of the three you offered me", never "this account".
	targets = Schema.array(Schema.int(1, 3), 1, 3),
	letterId = Schema.int(0, 65535),
	cargo = Schema.array(Schema.int(1, FindsConfig.MAX_FIND_ID), 0, 4),
}, true)

local SPEC_SESSION = Schema.map({
	seq = Schema.int(1, 4294967295),
}, true)

NetContract.SPECS = {
	RF_Session = SPEC_SESSION,
	RF_SetOrders = SPEC_SET_ORDERS,
	RF_Arrange = SPEC_ARRANGE,
	RF_Comb = SPEC_COMB,
	RF_Dispatch = SPEC_DISPATCH,
}

-- ------------------------------------------------------------- the checker

function NetContract.rowOf(name)
	for i = 1, #NetContract.REMOTES do
		if NetContract.REMOTES[i][COL_NAME] == name then
			return NetContract.REMOTES[i]
		end
	end
	return nil
end

function NetContract.isClientBound(name)
	local row = NetContract.rowOf(name)
	return row ~= nil and row[COL_DIR] == NetContract.DIR_S2C
end

-- A guard holds one bucket and one sequence per (player, remote). It is a
-- plain table so a test can inspect it and a service can throw it away when
-- the player leaves.
function NetContract.newGuard()
	return { buckets = {}, seqs = {}, rejected = 0, accepted = 0 }
end

local function bucketKey(userId, name)
	return tostring(userId) .. "|" .. name
end

function NetContract.resetPlayer(guard, userId)
	for i = 1, #NetContract.REMOTES do
		local key = bucketKey(userId, NetContract.REMOTES[i][COL_NAME])
		guard.buckets[key] = nil
		guard.seqs[key] = nil
	end
end

-- Returns (true) or (false, reason). `now` is seconds; it is an argument so
-- this module never reads a clock.
function NetContract.checkRate(guard, userId, name, now)
	local row = NetContract.rowOf(name)
	if row == nil then
		return false, "unknown remote"
	end
	if row[COL_DIR] ~= NetContract.DIR_C2S then
		return false, "not a client-to-server remote"
	end
	local key = bucketKey(userId, name)
	local b = guard.buckets[key]
	if b == nil then
		b = { tokens = row[COL_BURST], at = now }
		guard.buckets[key] = b
	end
	local elapsed = now - b.at
	if elapsed > 0 then
		b.tokens = b.tokens + elapsed * (row[COL_PER_MINUTE] / 60)
		if b.tokens > row[COL_BURST] then
			b.tokens = row[COL_BURST]
		end
		b.at = now
	end
	if b.tokens < 1 then
		return false, "rate limited"
	end
	b.tokens = b.tokens - 1
	return true
end

function NetContract.checkSequence(guard, userId, name, seq)
	local key = bucketKey(userId, name)
	local last = guard.seqs[key] or 0
	if seq <= last then
		return false, "replayed or out-of-order sequence"
	end
	guard.seqs[key] = seq
	return true
end

-- The single entry point every handler calls. Returns (true) or (false, why).
function NetContract.accept(guard, userId, name, payload, now)
	if type(payload) ~= "table" then
		guard.rejected = guard.rejected + 1
		return false, "payload is not a table"
	end
	local ok, why = NetContract.checkRate(guard, userId, name, now)
	if not ok then
		guard.rejected = guard.rejected + 1
		return false, why
	end
	if type(payload.seq) ~= "number" then
		guard.rejected = guard.rejected + 1
		return false, "payload has no sequence"
	end
	ok, why = NetContract.checkSequence(guard, userId, name, payload.seq)
	if not ok then
		guard.rejected = guard.rejected + 1
		return false, why
	end
	local spec = NetContract.SPECS[name]
	if spec == nil then
		guard.rejected = guard.rejected + 1
		return false, "no schema for " .. tostring(name)
	end
	ok, why = Schema.validate(payload, spec)
	if not ok then
		guard.rejected = guard.rejected + 1
		return false, why
	end
	guard.accepted = guard.accepted + 1
	return true
end

-- ------------------------------------------------------- the no-text proof

local function specHasString(spec, depth)
	if depth > 8 then
		return false
	end
	if type(spec) ~= "table" then
		return false
	end
	if spec.kind == "string" or spec.kind == "enum" then
		return true
	end
	if spec.of ~= nil and specHasString(spec.of, depth + 1) then
		return true
	end
	if spec.fields ~= nil then
		local names = {}
		local count = 0
		for key in pairs(spec.fields) do
			count = count + 1
			names[count] = key
		end
		table.sort(names)
		for i = 1, count do
			if specHasString(spec.fields[names[i]], depth + 1) then
				return true
			end
		end
	end
	return false
end

-- Returns (true) or (false, remoteName). doc 13 section 2 as an assertion.
function NetContract.hasNoStringFields()
	local names = {}
	local count = 0
	for key in pairs(NetContract.SPECS) do
		count = count + 1
		names[count] = key
	end
	table.sort(names)
	for i = 1, count do
		if specHasString(NetContract.SPECS[names[i]], 0) then
			return false, names[i]
		end
	end
	return true
end

return NetContract
