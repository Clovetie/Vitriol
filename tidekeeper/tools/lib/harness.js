#!/usr/bin/env node
"use strict";

/**
 * lib/harness.js
 *
 * The shared fengari harness: everything the smoke test and the session test
 * both need to run REAL TIDEKEEPER .luau SOURCE on Node.
 *
 * This file was extracted from tidekeeper-smoke-test.js in iteration 3, when a
 * second harness (tidekeeper-session-test.js) appeared. It is a straight
 * extraction, not a rewrite: the smoke test still reports the same 858
 * assertions afterwards, which is the only acceptable evidence that a
 * refactor of test infrastructure did not quietly change what is being
 * tested.
 *
 * WHY ANY OF THIS EXISTS
 * ----------------------
 * Roblox Luau cannot be run outside Roblox. fengari is a Lua 5.3 VM in
 * JavaScript, and Lua 5.3 is NOT Luau. Two differences are fatal and both are
 * handled here:
 *
 *   1. Lua 5.3 has an integer subtype. fengari's is 32 BITS WIDE with silent
 *      wraparound, so `255 * 16777216` evaluates to -16777216. Every hash
 *      constant, drifter id and codec word in this game is wider than that.
 *      `floatifyNumbers` rewrites every numeric literal to a float and the
 *      preamble forces `math.floor` and friends to return floats, after which
 *      fengari arithmetic IS Luau arithmetic (both are doubles).
 *
 *      This was found the hard way: before the fix, the suite reported 841
 *      passing assertions that were meaningless.
 *
 *   2. `bit32` does not exist, and cannot be shimmed with Lua's bitwise
 *      operators, because a literal above 2^31-1 lexes as a float and `&`
 *      then raises "number has no integer representation". The preamble
 *      builds bit32 from a byte-wise XOR table plus the identities
 *      `a AND b = (a + b - (a XOR b)) / 2` and `a OR b = a + b - (a AND b)`.
 *
 * Known limits, recorded so nobody rediscovers them:
 *   * `collectgarbage("count")` raises "lua_gc not implemented" — there is NO
 *     allocation counter. Zero-allocation claims are proved statically
 *     (source inspection) and by identity, never by measurement.
 *   * `require()` is resolved by the LAST path segment, so module base names
 *     must be globally unique.
 *   * Lua's 200-local limit applies to the test chunk's main function; wrap
 *     sections in `do ... end`.
 *   * The transform throws on `continue` and on backtick strings.
 */

const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const { transformLuau, luaLongString, read } = require("./luau-transform");

// ---------------------------------------------------------------------------
// Luau number semantics inside fengari
// ---------------------------------------------------------------------------
//
// THIS IS NOT A COSMETIC HACK. It is the difference between the harness testing
// the game and the harness testing a lie. See the file header.
function floatifyNumbers(src) {
	let out = "";
	let i = 0;
	const n = src.length;
	const isWordChar = (c) => c !== undefined && /[A-Za-z0-9_.]/.test(c);
	while (i < n) {
		const c = src[i];
		// Comments, short and long.
		if (c === "-" && src[i + 1] === "-") {
			const long = /^--\[(=*)\[/.exec(src.slice(i, i + 16));
			if (long) {
				const close = "]" + long[1] + "]";
				const end = src.indexOf(close, i);
				const stop = end === -1 ? n : end + close.length;
				out += src.slice(i, stop);
				i = stop;
				continue;
			}
			let end = src.indexOf("\n", i);
			if (end === -1) end = n;
			out += src.slice(i, end);
			i = end;
			continue;
		}
		// Long strings.
		const long = /^\[(=*)\[/.exec(src.slice(i, i + 16));
		if (long) {
			const close = "]" + long[1] + "]";
			const end = src.indexOf(close, i);
			const stop = end === -1 ? n : end + close.length;
			out += src.slice(i, stop);
			i = stop;
			continue;
		}
		// Quoted strings.
		if (c === '"' || c === "'") {
			let j = i + 1;
			while (j < n) {
				if (src[j] === "\\") {
					j += 2;
					continue;
				}
				if (src[j] === c) {
					j += 1;
					break;
				}
				if (src[j] === "\n") break;
				j += 1;
			}
			out += src.slice(i, j);
			i = j;
			continue;
		}
		if (c >= "0" && c <= "9") {
			const prev = i > 0 ? src[i - 1] : undefined;
			// Digits inside an identifier (u32, TWO32) or after a decimal point.
			if (isWordChar(prev)) {
				out += c;
				i += 1;
				continue;
			}
			// The exponent of a float literal: 1e-9.
			if ((prev === "-" || prev === "+") && /[eE]/.test(src[i - 2] || "")) {
				out += c;
				i += 1;
				continue;
			}
			let j = i;
			if (src[j] === "0" && /[xX]/.test(src[j + 1] || "")) {
				j += 2;
				while (j < n && /[0-9a-fA-F]/.test(src[j])) j += 1;
				// `0xFF.0` is not valid Lua; widen with an addition instead.
				out += "(" + src.slice(i, j) + " + 0.0)";
				i = j;
				continue;
			}
			while (j < n && /[0-9]/.test(src[j])) j += 1;
			let isFloat = false;
			if (src[j] === ".") {
				isFloat = true;
				j += 1;
				while (j < n && /[0-9]/.test(src[j])) j += 1;
			}
			if (/[eE]/.test(src[j] || "")) {
				isFloat = true;
				j += 1;
				if (/[+-]/.test(src[j] || "")) j += 1;
				while (j < n && /[0-9]/.test(src[j])) j += 1;
			}
			const text = src.slice(i, j);
			out += isFloat ? text : text + ".0";
			i = j;
			continue;
		}
		out += c;
		i += 1;
	}
	return out;
}

// ---------------------------------------------------------------------------
// The preamble: Luau stdlib shims, prepended to every bundle.
// ---------------------------------------------------------------------------
const PREAMBLE = `
-- ---------------------------------------------------------------------------
-- Luau stdlib shims. fengari is Lua 5.3; these make the REAL modules runnable
-- without editing them. Every shim below matches the documented Luau semantics
-- for the subset TIDEKEEPER actually uses.
-- ---------------------------------------------------------------------------

-- bit32: exact uint32 semantics.
--
-- This shim deliberately uses NO Lua bitwise operators. fengari's lexer turns
-- any numeric literal above 2^31-1 into a float, \`math.tointeger\` then returns
-- nil for it, and \`&\` / \`~\` raise "number has no integer representation".
-- Every uint32 constant in TIDEKEEPER (the FNV basis, the SplitMix mixers, the
-- murmur finalizer) is above that threshold, so the operator route is simply
-- not available here.
--
-- Instead: a 64 KB byte-wise XOR table, with AND and OR derived from XOR by
-- the exact identities
--     a AND b = (a + b - (a XOR b)) / 2
--     a OR  b = a + b - (a AND b)
-- and the shifts done as multiplication and division, pre-masked so no
-- intermediate ever exceeds 2^32. All of it is exact in a double.
local TWO32 = 4294967296
local function u32(x)
	return math.floor(x) % TWO32
end

local NIBBLE = {}
for a = 0, 15 do
	for b = 0, 15 do
		local x, y, res, place = a, b, 0, 1
		for _ = 1, 4 do
			local xb = x % 2
			local yb = y % 2
			if xb ~= yb then res = res + place end
			x = (x - xb) / 2
			y = (y - yb) / 2
			place = place * 2
		end
		NIBBLE[a * 16 + b] = res
	end
end
local BXOR = {}
for a = 0, 255 do
	local al = a % 16
	local ah = (a - al) / 16
	local base = a * 256
	for b = 0, 255 do
		local bl = b % 16
		local bh = (b - bl) / 16
		BXOR[base + b] = NIBBLE[ah * 16 + bh] * 16 + NIBBLE[al * 16 + bl]
	end
end

local function bxor32(a, b)
	a = u32(a)
	b = u32(b)
	local a0 = a % 256
	local ar = (a - a0) / 256
	local a1 = ar % 256
	ar = (ar - a1) / 256
	local a2 = ar % 256
	local a3 = (ar - a2) / 256
	local b0 = b % 256
	local br = (b - b0) / 256
	local b1 = br % 256
	br = (br - b1) / 256
	local b2 = br % 256
	local b3 = (br - b2) / 256
	return BXOR[a0 * 256 + b0]
		+ BXOR[a1 * 256 + b1] * 256
		+ BXOR[a2 * 256 + b2] * 65536
		+ BXOR[a3 * 256 + b3] * 16777216
end

local POW2 = {}
for i = 0, 32 do
	POW2[i] = 2 ^ i
end

bit32 = {
	bxor = bxor32,
	band = function(a, b)
		a = u32(a)
		b = u32(b)
		return (a + b - bxor32(a, b)) / 2
	end,
	bor = function(a, b)
		a = u32(a)
		b = u32(b)
		return a + b - (a + b - bxor32(a, b)) / 2
	end,
	bnot = function(a) return 4294967295 - u32(a) end,
	lshift = function(a, n)
		if n >= 32 or n < 0 then return 0 end
		return (u32(a) % POW2[32 - n]) * POW2[n]
	end,
	rshift = function(a, n)
		if n >= 32 or n < 0 then return 0 end
		return math.floor(u32(a) / POW2[n])
	end,
}

table.create = function(n, v)
	local t = {}
	for i = 1, n do t[i] = v end
	return t
end
table.clone = function(t)
	local u = {}
	for k, v in pairs(t) do u[k] = v end
	return u
end
table.clear = function(t)
	for k in pairs(t) do t[k] = nil end
end
table.find = function(t, value)
	for i = 1, #t do
		if t[i] == value then return i end
	end
	return nil
end

-- table.freeze / table.isfrozen, faithful enough to be worth testing against:
-- a frozen table errors on write and reports itself as frozen.
local FROZEN = setmetatable({}, { __mode = "k" })
table.isfrozen = function(t) return FROZEN[t] == true end
table.freeze = function(t)
	if FROZEN[t] then return t end
	FROZEN[t] = true
	local shadow = {}
	for k, v in pairs(t) do shadow[k] = v; rawset(t, k, nil) end
	setmetatable(t, {
		__index = shadow,
		__newindex = function() error("attempt to modify a readonly table", 2) end,
		__len = function() return #shadow end,
		__pairs = function() return next, shadow, nil end,
	})
	return t
end

-- Luau has no integer subtype; neither, effectively, may this VM. Lua's
-- math.floor narrows an integral float back to the 32-bit integer subtype,
-- which would silently wrap the moment it is multiplied. Widen it back.
local rawfloor = math.floor
local rawceil = math.ceil
local rawabs = math.abs
local rawmax = math.max
local rawmin = math.min
math.floor = function(x) return rawfloor(x) + 0.0 end
math.ceil = function(x) return rawceil(x) + 0.0 end
math.abs = function(x) return rawabs(x) + 0.0 end
math.max = function(a, b) return rawmax(a, b) + 0.0 end
math.min = function(a, b) return rawmin(a, b) + 0.0 end

-- string.format("%d", x) refuses a float wider than 2^31 in this VM. Route
-- integer conversions through %.0f, which is exact for every value below 2^53.
local rawformat = string.format
local function intToString(v)
	if type(v) ~= "number" then return tostring(v) end
	if v == rawfloor(v) then return rawformat("%.0f", v) end
	return tostring(v)
end
string.format = function(fmt, ...)
	local args = { ... }
	local count = select("#", ...)
	local index = 0
	local rewritten = string.gsub(fmt, "%%([-+ #0-9.]*)([diouxXeEfgGqscaA%%])", function(flags, conv)
		if conv == "%" then return "%%" end
		index = index + 1
		if conv == "d" or conv == "i" then
			args[index] = intToString(args[index])
			return "%" .. flags .. "s"
		end
		return "%" .. flags .. conv
	end)
	return rawformat(rewritten, table.unpack(args, 1, count))
end

math.clamp = function(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end
math.round = function(x)
	if x >= 0 then return math.floor(x + 0.5) end
	return -math.floor(-x + 0.5)
end
math.sign = function(x)
	if x > 0 then return 1 elseif x < 0 then return -1 end
	return 0
end

LOGSTRING = ""
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	LOGSTRING = LOGSTRING .. "print|" .. table.concat(parts, "\\t") .. "\\n"
end
warn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	LOGSTRING = LOGSTRING .. "warn|" .. table.concat(parts, "\\t") .. "\\n"
end

-- Flat module resolution. The transform rewrote every
-- \`require(script.Parent....X)\` to \`TidekeeperRequire("X")\`, so a cycle here
-- is a real layering cycle in the game and is reported as one.
local loaded = {}
local loading = {}
function TidekeeperRequire(name)
	if loaded[name] ~= nil then return loaded[name] end
	if loading[name] then error("TidekeeperRequire: require cycle at " .. tostring(name)) end
	local src = SOURCES[name]
	if not src then error("TidekeeperRequire: unknown module " .. tostring(name)) end
	loading[name] = true
	local fn, err = load(src, "@" .. name)
	if not fn then error("TidekeeperRequire: failed to load " .. name .. ": " .. tostring(err)) end
	local ok, result = pcall(fn)
	loading[name] = nil
	if not ok then error("TidekeeperRequire: module " .. name .. " errored: " .. tostring(result)) end
	loaded[name] = result
	return result
end
`;

// ---------------------------------------------------------------------------
// Bundling and running
// ---------------------------------------------------------------------------

/**
 * Transform a { logicalName -> path } map into { logicalName -> source }.
 * The logical name MUST equal the last segment of the module's require path,
 * because that is how `transformLuau` rewrites requires.
 */
function transformModules(modules) {
	const out = {};
	for (const [name, rel] of Object.entries(modules)) {
		out[name] = floatifyNumbers(transformLuau(read(rel), name));
	}
	return out;
}

/**
 * Build the single Lua chunk that gets executed.
 *
 *   options.modules   { name -> transformed source }, exposed via SOURCES
 *   options.globals   { name -> literal Lua expression } emitted before tests
 *   options.prelude   raw Lua emitted after SOURCES, before the tests (the
 *                     session test uses this for the fake DataModel)
 *   options.tests     the test chunk, last
 */
function buildBundle(options) {
	const parts = [floatifyNumbers(PREAMBLE), "SOURCES = {"];
	for (const [name, src] of Object.entries(options.modules || {})) {
		parts.push(`  ${name} = ${luaLongString(4, src)},`);
	}
	parts.push("}");
	for (const [name, value] of Object.entries(options.globals || {})) {
		parts.push(`${name} = ${value}`);
	}
	if (options.prelude) parts.push(options.prelude);
	if (options.tests) parts.push(options.tests);
	return parts.join("\n");
}

/**
 * Execute a bundle. Returns { ok, error, log, elapsedMs, tests, state }.
 * `tests` is the TESTS global ({ passed, failed }) if the chunk defined one.
 */
function runBundle(bundle) {
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);
	const started = process.hrtime.bigint();
	const status = lauxlib.luaL_dostring(L, to_luastring(bundle));
	const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;

	const readGlobalString = (name) => {
		lua.lua_getglobal(L, to_luastring(name));
		const v = lua.lua_tostring(L, -1);
		lua.lua_pop(L, 1);
		return v === null || v === undefined ? "" : to_jsstring(v);
	};

	const result = {
		ok: status === lua.LUA_OK,
		elapsedMs,
		log: readGlobalString("LOGSTRING"),
		error: null,
		tests: null,
		state: L,
	};
	if (!result.ok) {
		const raw = lua.lua_tostring(L, -1);
		result.error = raw ? to_jsstring(raw) : "<no error object>";
		return result;
	}
	lua.lua_getglobal(L, to_luastring("TESTS"));
	if (lua.lua_type(L, -1) === lua.LUA_TTABLE) {
		const field = (name) => {
			lua.lua_getfield(L, -1, to_luastring(name));
			const v = lua.lua_tonumber(L, -1);
			lua.lua_pop(L, 1);
			return v;
		};
		result.tests = { passed: field("passed"), failed: field("failed") };
	}
	lua.lua_pop(L, 1);
	return result;
}

/** Print a captured LOGSTRING the way both harnesses print it. */
function printLog(log) {
	for (const entry of log.split("\n")) {
		if (!entry) continue;
		if (entry.startsWith("warn|")) console.log("[warn] " + entry.slice(5));
		else if (entry.startsWith("print|")) console.log(entry.slice(6));
	}
	return log;
}

module.exports = { floatifyNumbers, PREAMBLE, transformModules, buildBundle, runBundle, printLog };
