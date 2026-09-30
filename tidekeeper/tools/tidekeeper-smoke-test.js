#!/usr/bin/env node
// tidekeeper-smoke-test.js
// Headless runtime smoke test for the TIDEKEEPER pure layers (L0 Lib, L2 Domain,
// Shared codecs, Config).
//
// Roblox is not available here, so this harness:
//   1. Reads the REAL shipping .luau files out of tidekeeper/code -- never a
//      copy, never a reimplementation. If a module changes, this changes.
//   2. Transforms them to plain Lua 5.3 with tools/lib/luau-transform.js
//      (strips type syntax, rewrites compound assignment, rewrites
//      `require(script.Parent.X)` to a flat lookup). The transform THROWS on
//      constructs it cannot handle rather than silently mangling them.
//   3. Runs them in fengari (a Lua 5.3 VM in JS) with a small shim for the
//      Luau-only stdlib the modules use: `bit32`, `table.create/clone/clear/
//      find/freeze/isfrozen`, `math.clamp/round/sign`.
//   4. Executes tools/tests/pure-tests.lua and reports PASS/FAIL per assertion.
//   5. Benchmarks Visit.resolve and runs two structural proofs about its
//      allocation behaviour.
//
// HONESTY NOTE ABOUT THE BENCHMARK
// --------------------------------
// fengari is an interpreter written in JavaScript. It is roughly one to two
// orders of magnitude slower than Luau. The microsecond figures printed below
// are therefore an UPPER BOUND and a regression tripwire, NOT a measurement
// against doc 04 section 6's 18 us budget. That budget can only be verified in
// Studio, and this harness says so instead of pretending otherwise.
//
// Run with:  npm --prefix tidekeeper/tools install   (once)
//            node tidekeeper/tools/tidekeeper-smoke-test.js
//            node tidekeeper/tools/tidekeeper-smoke-test.js --debug-transform
//            node tidekeeper/tools/tidekeeper-smoke-test.js --no-bench

const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const { transformLuau, luaLongString, read, ROOT } = require("./lib/luau-transform");

// ---------------------------------------------------------------------------
// Luau number semantics inside fengari
// ---------------------------------------------------------------------------
//
// THIS IS NOT A COSMETIC HACK. It is the difference between the harness testing
// the game and the harness testing a lie.
//
// Luau has ONE number type: an IEEE-754 double. Lua 5.3 has two, and fengari's
// integer subtype is 32 BITS WIDE (`luaconf.LUA_MAXINTEGER === 2147483647`) with
// SILENT wraparound -- `255 * 16777216` evaluates to -16777216 inside it. Every
// uint32 hash constant, every u32/u48/u64 codec value and every drifter id in
// TIDEKEEPER is wider than that, so running the real modules on fengari's
// integers produces confidently wrong answers rather than errors.
//
// The fix is to make every numeral a float, which is exactly what Luau does.
// `floatifyNumbers` rewrites `1` to `1.0` outside strings and comments, and the
// preamble forces `math.floor` and friends to return floats too (Lua's
// `math.floor` narrows back to the integer subtype when it can). After that,
// fengari arithmetic is JavaScript double arithmetic, which is Luau arithmetic.
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

const CODE = "code/ReplicatedStorage/Tidekeeper";

// Logical name -> path relative to tidekeeper/. The logical name must equal the
// last segment of the module's `require` path, because that is how the
// transform rewrites requires.
const MODULES = {
	// Config (pure data, no requires)
	GameConfig: `${CODE}/Config/GameConfig.luau`,
	TideConfig: `${CODE}/Config/TideConfig.luau`,
	EconomyConfig: `${CODE}/Config/EconomyConfig.luau`,
	DrifterConfig: `${CODE}/Config/DrifterConfig.luau`,
	OrdersConfig: `${CODE}/Config/OrdersConfig.luau`,
	FindsConfig: `${CODE}/Config/FindsConfig.luau`,
	// L0 Lib
	MathExt: `${CODE}/Lib/MathExt.luau`,
	Hash: `${CODE}/Lib/Hash.luau`,
	RNG: `${CODE}/Lib/RNG.luau`,
	Tables: `${CODE}/Lib/Tables.luau`,
	Signal: `${CODE}/Lib/Signal.luau`,
	Codec: `${CODE}/Lib/Codec.luau`,
	Schema: `${CODE}/Lib/Schema.luau`,
	Tide: `${CODE}/Lib/Tide.luau`,
	// Shared
	Version: `${CODE}/Shared/Version.luau`,
	DrifterCodec: `${CODE}/Shared/DrifterCodec.luau`,
	PostCodec: `${CODE}/Shared/PostCodec.luau`,
	// L2 Domain
	Standing: `${CODE}/Domain/Standing.luau`,
	Almanac: `${CODE}/Domain/Almanac.luau`,
	Drifter: `${CODE}/Domain/Drifter.luau`,
	Post: `${CODE}/Domain/Post.luau`,
	Orders: `${CODE}/Domain/Orders.luau`,
	Ledger: `${CODE}/Domain/Ledger.luau`,
	Visit: `${CODE}/Domain/Visit.luau`,
	Resolve: `${CODE}/Domain/Resolve.luau`,
};

const argv = process.argv.slice(2);
const noBench = argv.includes("--no-bench");

// ---------------------------------------------------------------------------
// Static proof: Visit.resolve must contain no table constructor.
// ---------------------------------------------------------------------------
//
// fengari does not implement `lua_gc`, so `collectgarbage("count")` is not
// available and an allocation counter cannot be read from inside the VM. Rather
// than skip the zero-allocation claim or fake it, the harness proves it two
// other ways:
//
//   (a) STATICALLY, here: the body of `Visit.resolve` is extracted from the
//       real source and asserted to contain no `{` table constructor and no
//       call to a known allocating helper. A table constructor is the only way
//       a Luau function of this shape allocates.
//   (b) DYNAMICALLY, in Lua: the test file records the identity of every
//       scratch array in the context, runs thousands of visits, and asserts
//       every identity is unchanged -- i.e. nothing was replaced by a fresh
//       table.
//
// Neither is a heap profiler. Together they are a much stronger statement than
// "the number looked small".
function extractFunctionBody(source, header) {
	const lines = source.split("\n");
	const start = lines.findIndex((l) => l.startsWith(header));
	if (start === -1) return null;
	// Module-level functions in this codebase close with an unindented `end`.
	for (let i = start + 1; i < lines.length; i += 1) {
		if (lines[i] === "end") return lines.slice(start + 1, i).join("\n");
	}
	return null;
}

const visitSource = read(MODULES.Visit);
const visitBody = extractFunctionBody(visitSource, "function Visit.resolve(S, D, ctx, rng)");

const staticChecks = [];
if (visitBody === null) {
	staticChecks.push({ name: "Visit.resolve body located", ok: false, detail: "header or terminating end not found" });
} else {
	const stripped = visitBody
		.split("\n")
		.map((l) => l.replace(/--.*$/, ""))
		.join("\n");
	staticChecks.push({
		name: "Visit.resolve body located",
		ok: true,
		detail: `${visitBody.split("\n").length} lines`,
	});
	const constructors = (stripped.match(/\{/g) || []).length;
	staticChecks.push({
		name: "Visit.resolve contains no table constructor",
		ok: constructors === 0,
		detail: `${constructors} occurrence(s) of '{'`,
	});
	const allocatingCalls = [];
	for (const pattern of ["table.create", "table.clone", "Tables.deepCopy", "Tables.copy", "string.format", "string.rep", "tostring("]) {
		if (stripped.includes(pattern)) allocatingCalls.push(pattern);
	}
	if (/[^.]\.\.[^.]/.test(stripped)) allocatingCalls.push("string concatenation");
	staticChecks.push({
		name: "Visit.resolve calls no allocating helper",
		ok: allocatingCalls.length === 0,
		detail: allocatingCalls.length ? `found ${allocatingCalls.join(", ")}` : "none",
	});
}

// ---------------------------------------------------------------------------
// Bundle
// ---------------------------------------------------------------------------
const transformed = {};
for (const [name, rel] of Object.entries(MODULES)) {
	transformed[name] = floatifyNumbers(transformLuau(read(rel), name));
}

const testsIdx = argv.indexOf("--tests");
const testsPath = testsIdx >= 0 ? argv[testsIdx + 1] : "tools/tests/pure-tests.lua";
const testSource = floatifyNumbers(transformLuau(read(testsPath), "pure-tests"));

if (argv.includes("--debug-transform")) {
	const out = "/tmp/tidekeeper-transformed";
	fs.mkdirSync(out, { recursive: true });
	for (const [name, src] of Object.entries(transformed)) {
		fs.writeFileSync(path.join(out, `${name}.lua`), src);
	}
	fs.writeFileSync(path.join(out, "pure-tests.lua"), testSource);
	console.log(`transformed sources written to ${out}/`);
	process.exit(0);
}

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

const parts = [floatifyNumbers(PREAMBLE), "SOURCES = {"];
for (const [name, src] of Object.entries(transformed)) {
	parts.push(`  ${name} = ${luaLongString(4, src)},`);
}
parts.push("}");
parts.push(`BENCH_ENABLED = ${noBench ? "false" : "true"}`);
parts.push(testSource);
const bundle = parts.join("\n");

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const started = process.hrtime.bigint();
const status = lauxlib.luaL_dostring(L, to_luastring(bundle));
const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;

function globalString(name) {
	lua.lua_getglobal(L, to_luastring(name));
	const v = lua.lua_tostring(L, -1);
	lua.lua_pop(L, 1);
	return v === null || v === undefined ? "" : to_jsstring(v);
}

function dumpLog() {
	const log = globalString("LOGSTRING");
	for (const entry of log.split("\n")) {
		if (!entry) continue;
		if (entry.startsWith("warn|")) console.log("[warn] " + entry.slice(5));
		else if (entry.startsWith("print|")) console.log(entry.slice(6));
	}
	return log;
}

if (status !== lua.LUA_OK) {
	const raw = lua.lua_tostring(L, -1);
	dumpLog();
	console.error("\nHARNESS CRASHED:\n" + (raw ? to_jsstring(raw) : "<no error object>"));
	process.exit(1);
}

dumpLog();

console.log("\n--- static proofs (source inspection, not the VM) ---");
let staticFailures = 0;
for (const check of staticChecks) {
	if (!check.ok) staticFailures += 1;
	console.log(`${check.ok ? "  ok " : "FAIL "} ${check.name}  [${check.detail}]`);
}

lua.lua_getglobal(L, to_luastring("TESTS"));
if (lua.lua_type(L, -1) !== lua.LUA_TTABLE) {
	console.error("pure-tests.lua did not define a TESTS table");
	process.exit(1);
}
function field(name) {
	lua.lua_getfield(L, -1, to_luastring(name));
	const v = lua.lua_tonumber(L, -1);
	lua.lua_pop(L, 1);
	return v;
}
const passed = field("passed");
const failed = field("failed");
lua.lua_pop(L, 1);

console.log("");
console.log(`harness wall time: ${elapsedMs.toFixed(0)} ms`);
console.log(
	`TIDEKEEPER smoke test: ${passed} passed, ${failed} failed, ${staticFailures} static proof(s) failed`
);
process.exit(failed > 0 || staticFailures > 0 ? 1 : 0);
