--!nonstrict
-- ReplicatedStorage/Tidekeeper/Domain/Almanac (ModuleScript)
--
-- Layer L2: pure. No services, no Instances, no yields, no time reads.
--
-- "Which finds have I ever held?" -- 256 bits, stored as a 32-byte array so it
-- drops straight into the post blob with no framing (doc 05 section 3).
--
-- A set of 256 booleans as a Luau table would be ~4 KB of hash part and would
-- iterate in an unspecified order. A bitset is 32 bytes, iterates in find-id
-- order by construction, and is the difference between the post blob fitting
-- in its budget and not.

local FindsConfig = require(script.Parent.Parent.Config.FindsConfig)

local Almanac = {}

local floor = math.floor
local band = bit32.band
local bor = bit32.bor
local lshift = bit32.lshift

local MAX_ID = FindsConfig.MAX_FIND_ID
local BYTES = MAX_ID / 8

Almanac.BYTES = BYTES
Almanac.MAX_ID = MAX_ID

function Almanac.new()
	local a = {}
	for i = 1, BYTES do
		a[i] = 0
	end
	return a
end

local function locate(id)
	local zero = id - 1
	return floor(zero / 8) + 1, lshift(1, zero % 8)
end

function Almanac.has(a, id)
	if id < 1 or id > MAX_ID then
		return false
	end
	local index, mask = locate(id)
	return band(a[index], mask) ~= 0
end

-- Returns true when this was a NEW find (the caller uses that to fire the
-- "first time you have held one of these" moment, which is the Almanac's whole
-- reason to exist).
function Almanac.record(a, id)
	if id < 1 or id > MAX_ID then
		return false
	end
	local index, mask = locate(id)
	local current = a[index]
	if band(current, mask) ~= 0 then
		return false
	end
	a[index] = bor(current, mask)
	return true
end

function Almanac.count(a)
	local n = 0
	for i = 1, BYTES do
		local v = a[i]
		while v > 0 do
			n = n + (v % 2)
			v = floor(v / 2)
		end
	end
	return n
end

-- Completion against the finds that actually exist, not against 256.
function Almanac.completion(a)
	local known = #FindsConfig.FINDS
	if known == 0 then
		return 0
	end
	local held = 0
	for i = 1, known do
		if Almanac.has(a, FindsConfig.FINDS[i][1]) then
			held = held + 1
		end
	end
	return held / known
end

-- Ids present, ascending. Allocates; for UI and tests, never for the resolver.
function Almanac.toList(a)
	local out = {}
	local n = 0
	for id = 1, MAX_ID do
		if Almanac.has(a, id) then
			n = n + 1
			out[n] = id
		end
	end
	return out
end

function Almanac.fromList(ids)
	local a = Almanac.new()
	for i = 1, #ids do
		Almanac.record(a, ids[i])
	end
	return a
end

function Almanac.isValid(a)
	if type(a) ~= "table" then
		return false
	end
	for i = 1, BYTES do
		local v = a[i]
		if type(v) ~= "number" or v ~= floor(v) or v < 0 or v > 255 then
			return false
		end
	end
	return true
end

return Almanac
