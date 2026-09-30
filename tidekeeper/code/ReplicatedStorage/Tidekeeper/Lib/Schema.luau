--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/Schema (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- Declarative table validation. Used by the domain layer to check its own
-- invariants in tests and Studio, and (from iteration 3) by `Shared/NetContract`
-- to validate every remote payload before it reaches a service.
--
-- A spec is a table:
--   { kind = "int",    min = 0, max = 255 }
--   { kind = "number", min = -1, max = 1 }
--   { kind = "string", maxLen = 64 }
--   { kind = "boolean" }
--   { kind = "enum",   values = { "LOW", "HIGH" } }
--   { kind = "array",  of = <spec>, minLen = 0, maxLen = 24 }
--   { kind = "map",    fields = { name = <spec>, ... }, strict = true }
-- Any spec may set `optional = true`.
--
-- `Schema.check(value, spec)` returns `(true)` or `(false, path, message)`.
-- It NEVER throws on bad data -- only on a malformed spec, which is a
-- programming error rather than a runtime input.

local MathExt = require(script.Parent.MathExt)
local Tables = require(script.Parent.Tables)

local Schema = {}

local function join(path, key)
	if path == "" then
		return tostring(key)
	end
	return path .. "." .. tostring(key)
end

local check

local function checkInt(value, spec, path)
	if not MathExt.isInteger(value) then
		return false, path, "expected an integer, got " .. type(value) .. " " .. tostring(value)
	end
	if spec.min ~= nil and value < spec.min then
		return false, path, string.format("%d is below the minimum %d", value, spec.min)
	end
	if spec.max ~= nil and value > spec.max then
		return false, path, string.format("%d is above the maximum %d", value, spec.max)
	end
	return true
end

local function checkNumber(value, spec, path)
	if type(value) ~= "number" then
		return false, path, "expected a number, got " .. type(value)
	end
	if value ~= value then
		return false, path, "expected a number, got NaN"
	end
	if spec.min ~= nil and value < spec.min then
		return false, path, string.format("%s is below the minimum %s", tostring(value), tostring(spec.min))
	end
	if spec.max ~= nil and value > spec.max then
		return false, path, string.format("%s is above the maximum %s", tostring(value), tostring(spec.max))
	end
	return true
end

local function checkString(value, spec, path)
	if type(value) ~= "string" then
		return false, path, "expected a string, got " .. type(value)
	end
	if spec.maxLen ~= nil and #value > spec.maxLen then
		return false, path, string.format("string of length %d exceeds %d", #value, spec.maxLen)
	end
	if spec.minLen ~= nil and #value < spec.minLen then
		return false, path, string.format("string of length %d is below %d", #value, spec.minLen)
	end
	return true
end

local function checkEnum(value, spec, path)
	for i = 1, #spec.values do
		if spec.values[i] == value then
			return true
		end
	end
	return false, path, "value " .. tostring(value) .. " is not one of the permitted values"
end

local function checkArray(value, spec, path)
	if type(value) ~= "table" then
		return false, path, "expected an array, got " .. type(value)
	end
	local n = #value
	if spec.minLen ~= nil and n < spec.minLen then
		return false, path, string.format("array of length %d is below %d", n, spec.minLen)
	end
	if spec.maxLen ~= nil and n > spec.maxLen then
		return false, path, string.format("array of length %d exceeds %d", n, spec.maxLen)
	end
	if not Tables.isArray(value) then
		return false, path, "array has holes or non-integer keys"
	end
	for i = 1, n do
		local ok, p, m = check(value[i], spec.of, join(path, i))
		if not ok then
			return false, p, m
		end
	end
	return true
end

local function checkMap(value, spec, path)
	if type(value) ~= "table" then
		return false, path, "expected a table, got " .. type(value)
	end
	local keys = Tables.sortedKeys(spec.fields)
	for i = 1, #keys do
		local key = keys[i]
		local ok, p, m = check(value[key], spec.fields[key], join(path, key))
		if not ok then
			return false, p, m
		end
	end
	if spec.strict then
		local present = Tables.sortedKeys(value)
		for i = 1, #present do
			local key = present[i]
			if spec.fields[key] == nil then
				return false, join(path, key), "unexpected field"
			end
		end
	end
	return true
end

function check(value, spec, path)
	if type(spec) ~= "table" or spec.kind == nil then
		error("Schema: malformed spec at " .. tostring(path), 0)
	end
	if value == nil then
		if spec.optional then
			return true
		end
		return false, path, "required field is missing"
	end
	local kind = spec.kind
	if kind == "int" then
		return checkInt(value, spec, path)
	elseif kind == "number" then
		return checkNumber(value, spec, path)
	elseif kind == "string" then
		return checkString(value, spec, path)
	elseif kind == "boolean" then
		if type(value) ~= "boolean" then
			return false, path, "expected a boolean, got " .. type(value)
		end
		return true
	elseif kind == "enum" then
		return checkEnum(value, spec, path)
	elseif kind == "array" then
		return checkArray(value, spec, path)
	elseif kind == "map" then
		return checkMap(value, spec, path)
	elseif kind == "any" then
		return true
	end
	error("Schema: unknown kind " .. tostring(kind), 0)
end

-- Returns (true) or (false, path, message).
function Schema.check(value, spec)
	return check(value, spec, "")
end

-- Returns (true) or (false, "path: message") -- convenient for assertions.
function Schema.validate(value, spec)
	local ok, path, message = check(value, spec, "")
	if ok then
		return true
	end
	if path == "" then
		return false, tostring(message)
	end
	return false, tostring(path) .. ": " .. tostring(message)
end

-- Bake a spec into a reusable validator function.
function Schema.compile(spec)
	return function(value)
		return Schema.validate(value, spec)
	end
end

-- Shorthands that keep the domain specs readable.
function Schema.int(min, max, optional)
	return { kind = "int", min = min, max = max, optional = optional }
end

function Schema.array(of, minLen, maxLen, optional)
	return { kind = "array", of = of, minLen = minLen, maxLen = maxLen, optional = optional }
end

function Schema.map(fields, strict, optional)
	return { kind = "map", fields = fields, strict = strict, optional = optional }
end

return Schema
