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
const MODULES = {
	// L0 Config
	GameConfig: `${REPLICATED}/Config/GameConfig.luau`,
	TideConfig: `${REPLICATED}/Config/TideConfig.luau`,
	EconomyConfig: `${REPLICATED}/Config/EconomyConfig.luau`,
	DrifterConfig: `${REPLICATED}/Config/DrifterConfig.luau`,
	OrdersConfig: `${REPLICATED}/Config/OrdersConfig.luau`,
	FindsConfig: `${REPLICATED}/Config/FindsConfig.luau`,
	NotifyConfig: `${REPLICATED}/Config/NotifyConfig.luau`,
	// L0 Lib
	MathExt: `${REPLICATED}/Lib/MathExt.luau`,
	Hash: `${REPLICATED}/Lib/Hash.luau`,
	RNG: `${REPLICATED}/Lib/RNG.luau`,
	Tables: `${REPLICATED}/Lib/Tables.luau`,
	Signal: `${REPLICATED}/Lib/Signal.luau`,
	Codec: `${REPLICATED}/Lib/Codec.luau`,
	Schema: `${REPLICATED}/Lib/Schema.luau`,
	Tide: `${REPLICATED}/Lib/Tide.luau`,
	// L2 Shared
	Version: `${REPLICATED}/Shared/Version.luau`,
	DrifterCodec: `${REPLICATED}/Shared/DrifterCodec.luau`,
	PostCodec: `${REPLICATED}/Shared/PostCodec.luau`,
	ReceiptCodec: `${REPLICATED}/Shared/ReceiptCodec.luau`,
	NetContract: `${REPLICATED}/Shared/NetContract.luau`,
	Remotes: `${REPLICATED}/Shared/Remotes.luau`,
	// L2 Domain
	Standing: `${REPLICATED}/Domain/Standing.luau`,
	Almanac: `${REPLICATED}/Domain/Almanac.luau`,
	Drifter: `${REPLICATED}/Domain/Drifter.luau`,
	Post: `${REPLICATED}/Domain/Post.luau`,
	Orders: `${REPLICATED}/Domain/Orders.luau`,
	Ledger: `${REPLICATED}/Domain/Ledger.luau`,
	Visit: `${REPLICATED}/Domain/Visit.luau`,
	Resolve: `${REPLICATED}/Domain/Resolve.luau`,
	// L1 Adapters
	DataStoreAdapter: `${SERVER}/Adapters/DataStoreAdapter.luau`,
	MemoryAdapter: `${SERVER}/Adapters/MemoryAdapter.luau`,
	NotifyAdapter: `${SERVER}/Adapters/NotifyAdapter.luau`,
	PolicyAdapter: `${SERVER}/Adapters/PolicyAdapter.luau`,
	// L3 Services
	CadenceService: `${SERVER}/Services/CadenceService.luau`,
	ExchangeService: `${SERVER}/Services/ExchangeService.luau`,
	LedgerService: `${SERVER}/Services/LedgerService.luau`,
	NotifyService: `${SERVER}/Services/NotifyService.luau`,
	ShowcaseService: `${SERVER}/Services/ShowcaseService.luau`,
	PostService: `${SERVER}/Services/PostService.luau`,
	PlayerService: `${SERVER}/Services/PlayerService.luau`,
	Bootstrap: `${SERVER}/Services/Bootstrap.luau`,
	// L4 Remote handlers (loaded so that a syntax or layering error in them
	// fails this suite rather than waiting for Studio)
	SessionHandler: `${SCRIPTS}/RemoteHandlers/SessionHandler.luau`,
	PostHandler: `${SCRIPTS}/RemoteHandlers/PostHandler.luau`,
	DispatchHandler: `${SCRIPTS}/RemoteHandlers/DispatchHandler.luau`,
	DebugHandler: `${SCRIPTS}/RemoteHandlers/DebugHandler.luau`,
	Profiler: `${SCRIPTS}/Diagnostics/Profiler.luau`,
	BudgetMeter: `${SCRIPTS}/Diagnostics/BudgetMeter.luau`,
	// L5 Client (iteration 4). Loaded so the localisation table and the
	// presenters are exercised by the same suite that drives the server --
	// the whole point of scenario 15 is that the ids the DOMAIN emits and the
	// prose the CLIENT holds are checked against each other, and they can
	// only be checked together.
	Strings: `${REPLICATED}/Client/Strings.luau`,
	Format: `${REPLICATED}/Client/Format.luau`,
	LedgerView: `${REPLICATED}/Client/LedgerView.luau`,
	TideView: `${REPLICATED}/Client/TideView.luau`,
	PostView: `${REPLICATED}/Client/PostView.luau`,
	OrdersView: `${REPLICATED}/Client/OrdersView.luau`,
	DispatchView: `${REPLICATED}/Client/DispatchView.luau`,
	ClientBootstrap: `${REPLICATED}/Client/ClientBootstrap.luau`,
	// The fake platform is required like any other module.
	FakePlatform: "tools/tests/fake-platform.lua",
};

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
