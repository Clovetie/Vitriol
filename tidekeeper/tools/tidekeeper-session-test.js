#!/usr/bin/env node
"use strict";

/**
 * tidekeeper-session-test.js
 *
 * Runs the REAL server -- adapters, services, scheduler, remote handlers --
 * against a fake Roblox DataModel, and measures what it costs.
 *
 * WHAT THIS IS FOR, THAT THE SMOKE TEST IS NOT
 * --------------------------------------------
 * `tidekeeper-smoke-test.js` proves the simulation is right: given a state
 * and a window of time, does `Resolve.run` produce the correct next state.
 * It never touches DataStore, MemoryStore, the scheduler or a player joining,
 * because those layers did not exist when it was written.
 *
 * This runs the layers where the OPERATIONAL failures live:
 *
 *   * a failed read being mistaken for a new player (the single most
 *     expensive persistence bug there is);
 *   * a DataUpdateConflict retry loop that classifies by error string;
 *   * quota errors, which must fail fast rather than sleep through a
 *     backoff schedule that cannot help;
 *   * MemoryStore going away, which must degrade rather than block play;
 *   * two servers holding the same post;
 *   * at-most-once Drifter delivery, which is the property the entire
 *     asynchronous design rests on.
 *
 * And it produces the number quoted in docs/03 section 6.3 -- mean platform
 * requests per session across a simulated month -- by counting every request
 * the real adapter makes. A documented performance claim that no test
 * measures is a claim that is already wrong and nobody has noticed.
 *
 * Usage:
 *   node tidekeeper/tools/tidekeeper-session-test.js
 *   node tidekeeper/tools/tidekeeper-session-test.js --verbose
 *   node tidekeeper/tools/tidekeeper-session-test.js --json out.json
 *
 * Exit 0 = all assertions passed.
 */

const fs = require("fs");
const path = require("path");
const { lua, to_luastring } = require("fengari");

const { transformLuau, read, ROOT } = require("./lib/luau-transform");
const { floatifyNumbers, transformModules, buildBundle, runBundle, printLog } = require("./lib/harness");

const REPLICATED = "code/ReplicatedStorage/Tidekeeper";
const SERVER = "code/ServerStorage/Tidekeeper";
const SCRIPTS = "code/ServerScriptService/Tidekeeper";

// Logical name -> path. The name MUST equal the last segment of the module's
// require path; the transform resolves requires by base name, which is also
// why every module in this game has a globally unique file name.
const { SESSION_REL: MODULES } = require("./lib/module-map");

const argv = process.argv.slice(2);
const verbose = argv.includes("--verbose");
const jsonIdx = argv.indexOf("--json");
const jsonPath = jsonIdx >= 0 ? path.resolve(process.cwd(), argv[jsonIdx + 1]) : null;
const testsIdx = argv.indexOf("--tests");
const testsPath = testsIdx >= 0 ? argv[testsIdx + 1] : "tools/tests/session-tests.lua";

const transformed = transformModules(MODULES);
const testSource = floatifyNumbers(transformLuau(read(testsPath), "session-tests"));

const bundle = buildBundle({ modules: transformed, tests: testSource });

const run = runBundle(bundle);
printLog(run.log);

if (!run.ok) {
	console.error("\nSESSION HARNESS CRASHED:\n" + run.error);
	process.exit(1);
}

// Pull the REPORT table out of the VM: the measured numbers the docs quote.
const L = run.state;
function readReport() {
	const out = {};
	lua.lua_getglobal(L, to_luastring("REPORT"));
	if (lua.lua_type(L, -1) !== lua.LUA_TTABLE) {
		lua.lua_pop(L, 1);
		return out;
	}
	lua.lua_pushnil(L);
	while (lua.lua_next(L, -2) !== 0) {
		const key = lua.lua_tojsstring(L, -2);
		const value = lua.lua_tonumber(L, -1);
		if (key) out[key] = value;
		lua.lua_pop(L, 1);
	}
	lua.lua_pop(L, 1);
	return out;
}
const report = readReport();

if (run.tests === null) {
	console.error("session-tests.lua did not define a TESTS table");
	process.exit(1);
}

const passed = run.tests.passed;
const failed = run.tests.failed;

console.log("\n--- measured platform cost ---");
const rows = [
	["sessions simulated", report.sessions],
	["distinct posts", report.posts],
	["days of virtual time", report.days],
	["DataStore requests, total", report.dataStoreRequests],
	["DataStore requests per session", report.dataPerSession, 2],
	["MemoryStore requests, total", report.memoryRequests],
	["MemoryStore requests per session", report.memoryPerSession, 2],
	["adapter retries", report.retries],
	["post saves", report.saves],
	["drifters published", report.published],
	["drifters claimed: live", report.claimedLive],
	["drifters claimed: echo", report.claimedEcho],
	["drifters claimed: seed", report.claimedSeed],
	["duplicate deliveries refused", report.duplicatesRefused],
	["cold-start session requests", report.coldStartRequests],
];
for (const [label, value, dp] of rows) {
	if (value === undefined || value === null) continue;
	const text = dp ? Number(value).toFixed(dp) : String(Math.round(value));
	console.log(`  ${label.padEnd(36)} ${text}`);
}

if (jsonPath) {
	fs.mkdirSync(path.dirname(jsonPath), { recursive: true });
	fs.writeFileSync(
		jsonPath,
		JSON.stringify({ generatedAt: new Date().toISOString(), passed, failed, report }, null, 2)
	);
}

console.log("");
console.log(`harness wall time: ${run.elapsedMs.toFixed(0)} ms`);
console.log(`TIDEKEEPER session test: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
