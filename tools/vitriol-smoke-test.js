#!/usr/bin/env node
// vitriol-smoke-test.js
// Headless runtime smoke test for the VITRIOL pure-Luau modules.
//
// Roblox is not available here, so this harness:
//   1. Transforms the Vitriol Luau sources (and the test file) into plain
//      Lua 5.3: strips `type` aliases and type annotations, rewrites compound
//      assignment, and generalises `for x in t`.
//   2. Runs them inside fengari (a Lua 5.3 VM in JS) with a tiny shim for the
//      Luau-only stdlib functions the modules use (table.create/clone/find/clear,
//      math.clamp).
//   3. Executes tools/vitriol/tests.luau and prints PASS/FAIL per assertion.
//
// The modules under test are deliberately PURE (no game:GetService, no Instances,
// no task.*), which is what makes this possible and is a hard rule in
// docs/01-ARCHITECTURE.md §7.
//
// Run with:  npm --prefix tools install   (once)
//            node tools/vitriol-smoke-test.js
//            node tools/vitriol-smoke-test.js --debug-transform

const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const ROOT = path.resolve(__dirname, "..");

// Modules under test: logical name -> repo-relative path.
const MODULES = {
	MathExt: "code/ReplicatedStorage/Vitriol/Lib/MathExt.luau",
	RNG: "code/ReplicatedStorage/Vitriol/Lib/RNG.luau",
	Fabrik: "code/ReplicatedStorage/Vitriol/Lib/Fabrik.luau",
	Genetics: "code/ReplicatedStorage/Vitriol/Lib/Genetics.luau",
	Tables: "code/ReplicatedStorage/Vitriol/Lib/Tables.luau",
	Signal: "code/ReplicatedStorage/Vitriol/Lib/Signal.luau",
	Noise: "code/ReplicatedStorage/Vitriol/Lib/Noise.luau",
	SpatialHash: "code/ReplicatedStorage/Vitriol/Lib/SpatialHash.luau",
	UtilityAI: "code/ReplicatedStorage/Vitriol/Lib/UtilityAI.luau",
	QLearning: "code/ReplicatedStorage/Vitriol/Lib/QLearning.luau",
	MarkovPredictor: "code/ReplicatedStorage/Vitriol/Lib/MarkovPredictor.luau",
	RegionIntegrity: "code/ReplicatedStorage/Vitriol/Shared/RegionIntegrity.luau",
	Skeleton: "code/ReplicatedStorage/Vitriol/Shared/Skeleton.luau",
	SkeletonCodec: "code/ReplicatedStorage/Vitriol/Shared/SkeletonCodec.luau",
	NoiseField: "code/ReplicatedStorage/Vitriol/Shared/NoiseField.luau",
};

// ---------------------------------------------------------------------------
// Luau -> Lua 5.3 transform
// ---------------------------------------------------------------------------
//
// Deliberately stricter than a general Luau parser: rather than silently
// mangling constructs it does not understand, it THROWS. Pure modules are
// expected to avoid multi-line function heads, `continue`, interpolated strings
// and generics; if a future module uses one, this fails loudly instead of
// testing something other than what was written.
function transformLuau(src, label) {
	const lines = src.split("\n");
	const out = [];
	let inTypeBlock = false;
	let typeDepth = 0;
	let inBlockComment = false;
	let inFnHead = false;
	let parenDebt = 0;

	for (let raw of lines) {
		const trimmed = raw.trim();

		// Block comments: pass through untouched.
		if (inBlockComment) {
			if (/\]\]/.test(trimmed)) inBlockComment = false;
			out.push(raw);
			continue;
		}
		if (/^--\[\[/.test(trimmed)) {
			inBlockComment = !/\]\]/.test(trimmed.slice(4));
			out.push(raw);
			continue;
		}

		const isComment = trimmed.startsWith("--");

		// A compound assignment whose right-hand side spans several lines cannot
		// be closed on the same line, so the opening paren is left open here and
		// closed on the line where the expression actually ends.
		if (!isComment && parenDebt > 0) {
			parenDebt -= (raw.match(/\)/g) || []).length - (raw.match(/\(/g) || []).length;
			if (parenDebt <= 0) {
				// Exactly one wrapper paren is outstanding: each compound
				// assignment opens one, and a second cannot start before the
				// first expression ends.
				raw += ")";
				parenDebt = 0;
			}
		}

		if (!isComment) {
			// Strip `type X = ...` / `export type X = ...` (multi-line aware).
			if (inTypeBlock) {
				typeDepth += (raw.match(/[{(]/g) || []).length;
				typeDepth -= (raw.match(/[})]/g) || []).length;
				if (typeDepth <= 0) inTypeBlock = false;
				out.push("-- (type declaration stripped)");
				continue;
			}
			if (/^\s*(export\s+)?type\s+[A-Za-z_]\w*\s*=/.test(raw)) {
				typeDepth = (raw.match(/[{(]/g) || []).length - (raw.match(/[})]/g) || []).length;
				inTypeBlock = typeDepth > 0;
				out.push("-- (type declaration stripped)");
				continue;
			}

			if (/\bcontinue\b/.test(raw)) {
				throw new Error(`${label}: \`continue\` is not supported by the smoke harness: ${trimmed}`);
			}
			if (/`/.test(raw)) {
				throw new Error(`${label}: interpolated strings are not supported by the smoke harness: ${trimmed}`);
			}

			// Function declarations: drop the return annotation, then param
			// annotations. Heads may span several lines, so track whether the
			// parameter list is still open.
			if (inFnHead) {
				// Continuation lines of a multi-line parameter list can only
				// contain a `:` for a type annotation (the method `:` of a
				// `function Foo:bar()` head is on the opening line), so strip
				// them without needing a lookahead - the last param on a line
				// has no trailing comma to anchor on.
				const closes = /\)/.test(raw);
				let l = raw;
				if (closes) l = l.replace(/^(.*\))\s*:\s*.*$/, "$1");
				l = l.replace(/:\s*[A-Za-z_{][^,()=]*/g, "");
				raw = l;
				if (closes) inFnHead = false;
			} else if (/^\s*(local\s+)?function\b/.test(raw)) {
				const noReturn = raw.replace(/^(.*\))\s*:\s*.*$/, "$1");
				raw = noReturn.replace(/:\s*[A-Za-z_{][^,()=]*?(?=[,)])/g, "");
				const opens = (raw.match(/\(/g) || []).length;
				const closes = (raw.match(/\)/g) || []).length;
				if (opens > closes) inFnHead = true;
			}

			// `local x: T = v` / `local x: T`
			raw = raw.replace(/^(\s*local\s+[A-Za-z_]\w*)\s*:\s*[A-Za-z_][\w?]*\s*=\s*/, "$1 = ");
			raw = raw.replace(/^(\s*local\s+[A-Za-z_]\w*)\s*:\s*[A-Za-z_][\w?]*\s*$/, "$1");

			// Type assertion casts: `expr :: T` -> `expr`
			raw = raw.replace(/\s*::\s*[A-Za-z_][\w?|{}]*/g, "");

			// require(script.Parent.Parent.Lib.Foo) -> VitriolRequire("Foo").
			// Shipping modules must use real `require()` with a real Instance path;
			// the harness resolves the LAST path segment against the flat MODULES
			// map. Without this, any module that has a dependency is untestable here.
			raw = raw.replace(/require\(\s*([A-Za-z_][\w.:]*)\s*\)/g, (_all, path) => {
				const parts = path.split(/[.:]/).filter(Boolean);
				return `VitriolRequire("${parts[parts.length - 1]}")`;
			});

			// Compound assignment.
			const m = raw.match(/^(\s*)([A-Za-z_][\w.[\]"']*)\s*(\+=|-=|\*=|\/=)(.+)$/);
			if (m) {
				const rhs = m[4].trim();
				const unbalanced = (rhs.match(/\(/g) || []).length - (rhs.match(/\)/g) || []).length;
				if (unbalanced > 0) {
					raw = `${m[1]}${m[2]} = ${m[2]} ${m[3][0]} (${rhs}`;
					parenDebt = unbalanced;
				} else {
					raw = `${m[1]}${m[2]} = ${m[2]} ${m[3][0]} (${rhs})`;
				}
			}

			// Generalized iteration.
			const fm = raw.match(/^(\s*for\s+[A-Za-z_][\w,\s]*?\s+)in\s+(.+?)\s+do$/);
			if (fm && !/^(pairs|ipairs|next)\s*\(/.test(fm[2].trim())) {
				raw = `${fm[1]}in pairs(${fm[2]}) do`;
			}
		}

		out.push(raw);
	}

	if (inTypeBlock) throw new Error(`${label}: unterminated type declaration`);
	return out.join("\n");
}

function luaLongString(level, s) {
	const eq = "=".repeat(level);
	return `[${eq}[${s}]${eq}]`;
}

function read(p) {
	return fs.readFileSync(path.join(ROOT, p), "utf8");
}

// ---------------------------------------------------------------------------
// Bundle
// ---------------------------------------------------------------------------
const transformed = {};
for (const [name, rel] of Object.entries(MODULES)) {
	transformed[name] = transformLuau(read(rel), name);
}
// --tests <path> lets you point the harness at a scratch file while debugging.
const testsArgIdx = process.argv.indexOf("--tests");
const testsPath = testsArgIdx >= 0 ? process.argv[testsArgIdx + 1] : "tools/vitriol/tests.luau";
const tTests = transformLuau(read(testsPath), "tests");

if (process.argv.includes("--debug-transform")) {
	for (const [name, src] of Object.entries(transformed)) {
		fs.writeFileSync(`/tmp/vitriol-${name}.lua`, src);
	}
	fs.writeFileSync("/tmp/vitriol-tests.lua", tTests);
	console.log("transformed sources written to /tmp/vitriol-*.lua");
	process.exit(0);
}

const PREAMBLE = `
-- Luau stdlib shims (fengari is Lua 5.3).
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
math.clamp = function(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

LOGSTRING = ""
local origPrint = print
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

local loaded = {}
function VitriolRequire(name)
	if loaded[name] ~= nil then return loaded[name] end
	local src = SOURCES[name]
	if not src then error("VitriolRequire: unknown module " .. tostring(name)) end
	local fn, err = load(src, "@" .. name)
	if not fn then error("VitriolRequire: failed to load " .. name .. ": " .. tostring(err)) end
	local ok, result = pcall(fn)
	if not ok then error("VitriolRequire: module " .. name .. " errored: " .. tostring(result)) end
	loaded[name] = result
	return result
end
`;

const parts = [PREAMBLE, "SOURCES = {"];
for (const [name, src] of Object.entries(transformed)) {
	parts.push(`  ${name} = ${luaLongString(4, src)},`);
}
parts.push("}", tTests);
const bundle = parts.join("\n");

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const status = lauxlib.luaL_dostring(L, to_luastring(bundle));

function globalString(name) {
	lua.lua_getglobal(L, to_luastring(name));
	const v = lua.lua_tostring(L, -1);
	lua.lua_pop(L, 1);
	return v === null ? "" : to_jsstring(v);
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
	const err = to_jsstring(lua.lua_tostring(L, -1) || to_luastring("<no error object>"));
	dumpLog();
	console.error("\nHARNESS CRASHED:\n" + err);
	process.exit(1);
}

dumpLog();

lua.lua_getglobal(L, to_luastring("TESTS"));
if (lua.lua_type(L, -1) !== lua.LUA_TTABLE) {
	console.error("tests.luau did not define a TESTS table");
	process.exit(1);
}
lua.lua_getfield(L, -1, to_luastring("passed"));
const passed = lua.lua_tonumber(L, -1);
lua.lua_pop(L, 1);
lua.lua_getfield(L, -1, to_luastring("failed"));
const failed = lua.lua_tonumber(L, -1);
lua.lua_pop(L, 2);

console.log("");
console.log(`VITRIOL smoke test: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
