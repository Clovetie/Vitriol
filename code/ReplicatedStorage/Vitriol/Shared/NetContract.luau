--!strict
-- NetContract.luau
-- Location: ReplicatedStorage > Vitriol > Shared > NetContract  (ModuleScript)
-- Purpose:  Declarative payload schemas for every message a client may send, plus
--           the server-side validator and admission gate that use them. The rule
--           this exists to enforce: NEVER TRUST A CLIENT. A remote handler may not
--           index a payload it has not run through 'NetContract.admit'.
--
--           Shape of the defence, in the order it is applied:
--           1. admission (token bucket per player per message kind) - a spammer is
--              refused before any of their data is read, so flooding costs the
--              server nothing;
--           2. type validation of every field, including rejecting fields that are
--              NOT in the schema (a forgeable extra key is the classic hole);
--           3. domain validation: finite numbers, ranges, enum membership against
--              GameConfig.Intents, list lengths.
--           Anything that fails returns a reject code, never a sanitised guess - a
--           silent fix-up means a cheat works half the time and an exploit stays
--           invisible in the logs.
--
--           PURE: no Instances, no services, no yields. 'now' is always passed IN
--           by the caller, so the whole module runs in the headless harness and the
--           rate limiter can be tested at arbitrary speed. Vectors are read as
--           {X,Y,Z} (a Roblox Vector3 satisfies that; a table of numbers does too).
-- Requires: Config/GameConfig
-- Used by:  ServerScriptService > Vitriol > RemoteHandlers/ClientIntentHandler,
--           RemoteHandlers/DebugHandler, Shared/Remotes (schema registry)

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local NetContract = {}

local NET = GameConfig.Net

NetContract.MaxStringBytes = NET.MaxStringBytes
NetContract.MaxListLength = NET.MaxListLength
NetContract.MaxPositionMagnitude = NET.MaxPositionMagnitude

NetContract.Reject = {
	RateLimited = "rate-limited",
	UnknownSchema = "unknown-schema",
	Malformed = "payload-not-a-table",
	MissingField = "missing-field",
	UnknownField = "unknown-field",
	BadType = "bad-type",
	NotFinite = "non-finite-number",
	OutOfRange = "out-of-range",
	NotAllowed = "value-not-allowed",
	TooLong = "list-too-long",
}

-- The interaction vocabulary, derived from config rather than repeated here:
-- GameConfig.Intents is the single list that says what a client may ask for, and
-- DestructionConfig.Interactions is the single list that says what each one costs.
local ALLOWED_ACTIONS = {}
local ACTION_LIST = {}
do
	local groups = GameConfig.Intents
	for g = 1, #groups do
		local list = groups[g].Actions
		for i = 1, #list do
			local action = list[i]
			if ALLOWED_ACTIONS[action] == nil then
				ALLOWED_ACTIONS[action] = true
				ACTION_LIST[#ACTION_LIST + 1] = action
			end
		end
	end
end

NetContract.Actions = ALLOWED_ACTIONS
NetContract.ActionNames = ACTION_LIST

-- The debug surface (docs/06 §8) is closed by default and gated by permission in
-- the handler; the schema still bounds it, so a mis-keyed command never reaches a
-- service. Declared before the schemas because a schema references it.
NetContract.DebugCommands = {
	phases = true,
	clock = true,
	cadence = true,
	budget = true,
	help = true,
}

---------------------------------------------------------------------------
-- Schemas
---------------------------------------------------------------------------
-- Field spec: { Kind, Required, Min, Max, Enum, Element }
--   Kind: "number" | "integer" | "string" | "boolean" | "vector" | "list"
-- Every field NOT listed here is a rejection, so adding a client field is a
-- deliberate act that shows up in this file's diff.
NetContract.Schemas = {
	ClientIntent = {
		Remote = "RE_ClientIntent",
		Fields = {
			-- Which interaction, from the config-declared vocabulary.
			Action = { Kind = "string", Required = true, Enum = ALLOWED_ACTIONS },
			-- A logical id assigned by the owning service (a joint id, a container
			-- id). Never an Instance: the client must not name objects.
			TargetId = { Kind = "integer", Required = true, Min = 0 },
			-- Where, for the interactions that are spatial. Validated as finite and
			-- inside the world bounds; the SERVER still re-checks reach.
			Position = { Kind = "vector", Required = false },
			-- How long the input was held, as CLAIMED by the client and re-checked
			-- against the server's own timer: a claim longer than the interaction is
			-- possible is a lie, and 'Max' is where that is caught.
			HeldSeconds = { Kind = "number", Required = false, Min = 0, Max = NET.MaxHeldSeconds },
			-- Client-side prediction counter, monotonic per player: the handler drops
			-- anything at or below the last accepted sequence, which is what stops a
			-- replayed packet from opening a door twice.
			Sequence = { Kind = "integer", Required = true, Min = 0 },
		},
	},
	DebugQuery = {
		Remote = "RF_DebugQuery",
		Fields = {
			Command = { Kind = "string", Required = true, Enum = NetContract.DebugCommands },
			Argument = { Kind = "number", Required = false, Min = NET.DebugArgumentMin, Max = NET.DebugArgumentMax },
		},
	},
}

---------------------------------------------------------------------------
-- Field validation
---------------------------------------------------------------------------
local function isFiniteNumber(v: any): boolean
	-- NaN never equals itself; +/-inf are excluded without calling math.huge
	-- through a comparison chain that a future edit could break.
	if type(v) ~= "number" then
		return false
	end
	if v ~= v then
		return false
	end
	return v < math.huge and v > -math.huge
end

local function validateNumber(spec: any, v: any): any
	if not isFiniteNumber(v) then
		return NetContract.Reject.NotFinite
	end
	local min = spec.Min
	if min ~= nil and v < min then
		return NetContract.Reject.OutOfRange
	end
	local max = spec.Max
	if max ~= nil and v > max then
		return NetContract.Reject.OutOfRange
	end
	return nil
end

local function validateField(spec: any, v: any, depth: number): any
	local kind = spec.Kind
	if kind == "number" then
		return validateNumber(spec, v)
	elseif kind == "integer" then
		local err = validateNumber(spec, v)
		if err ~= nil then
			return err
		end
		if math.floor(v) ~= v then
			return NetContract.Reject.BadType
		end
		return nil
	elseif kind == "boolean" then
		if type(v) ~= "boolean" then
			return NetContract.Reject.BadType
		end
		return nil
	elseif kind == "string" then
		if type(v) ~= "string" then
			return NetContract.Reject.BadType
		end
		if #v > NetContract.MaxStringBytes then
			return NetContract.Reject.TooLong
		end
		local enum = spec.Enum
		if enum ~= nil and enum[v] == nil then
			return NetContract.Reject.NotAllowed
		end
		return nil
	elseif kind == "vector" then
		if type(v) ~= "table" and type(v) ~= "userdata" then
			return NetContract.Reject.BadType
		end
		local limit = NetContract.MaxPositionMagnitude
		local x = v.X
		local y = v.Y
		local z = v.Z
		if isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z) then
			if x < -limit or x > limit or y < -limit or y > limit or z < -limit or z > limit then
				return NetContract.Reject.OutOfRange
			end
			return nil
		end
		return NetContract.Reject.NotFinite
	elseif kind == "list" then
		if type(v) ~= "table" then
			return NetContract.Reject.BadType
		end
		-- '#' on a sparse table is undefined-ish; length is checked and each index
		-- probed, so a hole or an overflow both fail closed.
		local count = #v
		if count > NetContract.MaxListLength then
			return NetContract.Reject.TooLong
		end
		if depth >= 1 then
			return NetContract.Reject.Malformed
		end
		local element = spec.Element
		for i = 1, count do
			local err = validateField(element, v[i], depth + 1)
			if err ~= nil then
				return err
			end
		end
		return nil
	end
	return NetContract.Reject.BadType
end

-- validate(schemaName, payload) -> ok, rejectCode?, fieldName?
function NetContract.validate(schemaName: string, payload: any): (boolean, any, any)
	local schema = NetContract.Schemas[schemaName]
	if schema == nil then
		return false, NetContract.Reject.UnknownSchema, nil
	end
	if type(payload) ~= "table" then
		-- Instances, strings and numbers are all rejected here. 'type(Instance)' is
		-- "userdata", so an Instance smuggled in as a payload never gets read.
		return false, NetContract.Reject.Malformed, nil
	end

	local fields = schema.Fields
	-- Unknown keys first: a client that sends an extra field is either a version
	-- mismatch or probing, and both deserve the same answer.
	for key in pairs(payload) do
		if fields[key] == nil then
			return false, NetContract.Reject.UnknownField, key
		end
	end

	for key in pairs(fields) do
		local spec = fields[key]
		local value = payload[key]
		if value == nil then
			if spec.Required then
				return false, NetContract.Reject.MissingField, key
			end
		else
			local err = validateField(spec, value, 0)
			if err ~= nil then
				return false, err, key
			end
		end
	end
	return true, nil, nil
end

---------------------------------------------------------------------------
-- Admission: one token bucket per (player, message kind)
---------------------------------------------------------------------------
-- newGate() -> gate
function NetContract.newGate()
	local gate = {}
	gate.buckets = {}
	gate.sequences = {}
	gate.accepted = 0
	gate.rejected = 0
	gate.rejectedBy = {}
	return gate
end

-- Limits for one kind, from config. Missing entry = closed: an undocumented
-- message kind must not get an accidental default.
function NetContract.limits(schemaName: string): any
	local rate = NET.Rate
	if rate == nil then
		return nil
	end
	return rate[schemaName]
end

-- gate:allow(key, schemaName, now) -> ok, retryAfterSeconds
function NetContract.allow(gate: any, key: any, schemaName: string, now: number): (boolean, number)
	local limits = NetContract.limits(schemaName)
	if limits == nil then
		return false, 0
	end
	local byKey = gate.buckets[schemaName]
	if byKey == nil then
		byKey = {}
		gate.buckets[schemaName] = byKey
	end
	local bucket = byKey[key]
	if bucket == nil then
		bucket = { tokens = limits.Burst, last = now }
		byKey[key] = bucket
	end
	local refill = (now - bucket.last) * limits.SustainedPerSecond
	if refill < 0 then
		refill = 0
	end
	local tokens = bucket.tokens + refill
	local burst = limits.Burst
	if tokens > burst then
		tokens = burst
	end
	bucket.last = now
	if tokens < 1 then
		local gap = limits.MinGapSeconds or 0
		local deficit = 1 - tokens
		local retry = deficit / limits.SustainedPerSecond
		if retry < gap then
			retry = gap
		end
		bucket.tokens = tokens
		return false, retry
	end
	bucket.tokens = tokens - 1
	return true, 0
end

-- gate:checkSequence(key, schemaName, seq) -> ok
-- Monotonic per (player, kind): replayed or reordered predictions are dropped
-- rather than applied twice.
function NetContract.checkSequence(gate: any, key: any, schemaName: string, seq: any): boolean
	if type(seq) ~= "number" then
		return true
	end
	local byKey = gate.sequences[schemaName]
	if byKey == nil then
		byKey = {}
		gate.sequences[schemaName] = byKey
	end
	local last = byKey[key]
	if last ~= nil and seq <= last then
		return false
	end
	byKey[key] = seq
	return true
end

-- gate:forget(key) -> ()  (player left: drop their buckets so the gate does not
-- grow with the server's lifetime)
function NetContract.forget(gate: any, key: any): ()
	for schemaName in pairs(gate.buckets) do
		gate.buckets[schemaName][key] = nil
	end
	for schemaName in pairs(gate.sequences) do
		gate.sequences[schemaName][key] = nil
	end
end

-- admit(gate, key, schemaName, payload, now) -> ok, rejectCode?, fieldName?
-- THE entry point every client-facing handler calls. Order is deliberate: the
-- cheapest test that can refuse a spammer runs first.
function NetContract.admit(gate: any, key: any, schemaName: string, payload: any, now: number): (boolean, any, any)
	local ok, retry = NetContract.allow(gate, key, schemaName, now)
	if not ok then
		gate.rejected = gate.rejected + 1
		local by = gate.rejectedBy
		by[NetContract.Reject.RateLimited] = (by[NetContract.Reject.RateLimited] or 0) + 1
		return false, NetContract.Reject.RateLimited, retry
	end
	local valid, code, field = NetContract.validate(schemaName, payload)
	if not valid then
		gate.rejected = gate.rejected + 1
		local by = gate.rejectedBy
		by[code] = (by[code] or 0) + 1
		return false, code, field
	end
	if not NetContract.checkSequence(gate, key, schemaName, payload.Sequence) then
		gate.rejected = gate.rejected + 1
		local by = gate.rejectedBy
		by["stale-sequence"] = (by["stale-sequence"] or 0) + 1
		return false, "stale-sequence", "Sequence"
	end
	gate.accepted = gate.accepted + 1
	return true, nil, nil
end

-- stats(gate) -> { accepted, rejected, rejectedBy }
function NetContract.stats(gate: any): any
	return { accepted = gate.accepted, rejected = gate.rejected, rejectedBy = gate.rejectedBy }
end

return NetContract
