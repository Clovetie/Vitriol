#!/usr/bin/env node
/**
 * tidekeeper-luau-test.js — run the correctness suite in a REAL Luau VM.
 *
 * This is OD17, and it is the whole point of iteration 5's tooling work.
 *
 * `tidekeeper-smoke-test.js` runs the same `tests/pure-tests.lua` under
 * fengari, which is a Lua 5.3 VM. Lua 5.3 is not Luau, so that harness has to
 * reshape both the game and the tests before either will run
 * (`tools/README.md` §5b):
 *
 *   - every numeric literal is rewritten to a float, because fengari's lexer
 *     turns anything above 2^31-1 into a float anyway and the integer subtype
 *     then wraps at 32 bits;
 *   - `bit32` is rebuilt from a 64 KB byte-wise XOR table, because Lua's
 *     native `&` and `~` raise "number has no integer representation" on
 *     exactly the uint32 constants this game is full of;
 *   - `math.floor`/`ceil`/`abs`/`max`/`min` are wrapped to return floats;
 *   - `string.format("%d", …)` is rewritten to `%.0f`.
 *
 * Every one of those is a place where **the thing under test is not the thing
 * that ships**. One of them once produced 841 meaningless passes.
 *
 * Here there are no shims at all. The only transform is the Roblox `require`
 * rewrite, which is unavoidable — `require(script.Parent.Foo)` has no meaning
 * outside a DataModel. Numbers, `bit32`, `buffer`, string formatting and the
 * optimiser are the real ones.
 *
 * The two runners share `tests/pure-tests.lua` byte for byte. That is
 * deliberate: if they ever disagree on the pass count, one of the two VMs is
 * lying about the game, and finding out which is worth more than either
 * number on its own. `--compare` asserts they agree.
 *
 *   node tidekeeper/tools/tidekeeper-luau-test.js
 *   node tidekeeper/tools/tidekeeper-luau-test.js --compare
 *   node tidekeeper/tools/tidekeeper-luau-test.js --json report.json
 *
 * Needs a `luau` binary (tools/bin/README.md, four minutes from source).
 * Without one it prints SKIPPED and exits 0, same contract as the bench.
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { findLuau, buildBundle, runBundle } = require("./lib/luau-native");
const { MODULES } = require("./lib/module-map");

const ROOT = path.resolve(__dirname, "..");
const REPO = path.resolve(ROOT, "..");

const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const valueOf = (f) => {
	const i = argv.indexOf(f);
	return i >= 0 ? argv[i + 1] : null;
};

// --------------------------------------------------------------------- luau
const luau = findLuau();
if (!luau) {
	console.log("TIDEKEEPER Luau test: SKIPPED — no `luau` binary found.");
	console.log("");
	console.log("  git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau");
	console.log("  make -C /tmp/luau config=release luau -j$(nproc)");
	console.log("  cp /tmp/luau/luau tidekeeper/tools/bin/luau");
	console.log("");
	console.log("Or point TIDEKEEPER_LUAU at an existing binary.");
	process.exit(0);
}

// ------------------------------------------------------------------ the run
//
// The epilogue is the only Luau this file adds. pure-tests.lua already keeps
// its own tally in the global TESTS, so all that is needed is to print it in
// a shape this process can parse. It must run even if the suite threw, which
// is why the suite is called through pcall rather than concatenated.
const testsPath = valueOf("--tests") || path.join(ROOT, "tools", "tests", "pure-tests.lua");
const testSource = fs.readFileSync(testsPath, "utf8");

// Globals the fengari runner injects from JS. They have to be injected here
// too, and with the same names, because the suite is shared verbatim: the
// Lua side has no filesystem in either VM, so a captured fixture can only
// arrive as a string literal.
const FIXTURE_POST_V1 = fs
	.readFileSync(path.join(ROOT, "tools", "fixture-blobs", "post-v1.b64"), "utf8")
	.trim();

const FIXTURE_POST_V2 = fs
	.readFileSync(path.join(ROOT, "tools", "fixture-blobs", "post-v2.b64"), "utf8")
	.trim();

const PRELUDE = `
-- emitted by tidekeeper-luau-test.js
BENCH_ENABLED = false
FIXTURE_POST_V1 = ${JSON.stringify(FIXTURE_POST_V1)}
FIXTURE_POST_V2 = ${JSON.stringify(FIXTURE_POST_V2)}
`;

const EPILOGUE = `
-- emitted by tidekeeper-luau-test.js
print("__TK_RESULT__ passed=" .. tostring(TESTS.passed) .. " failed=" .. tostring(TESTS.failed))
for i = 1, #TESTS.failures do
	print("__TK_FAIL__ " .. TESTS.failures[i])
end
`;

const bundlePath = path.join(ROOT, "tools", "reports", "luau-test-bundle.luau");
fs.mkdirSync(path.dirname(bundlePath), { recursive: true });

const started = Date.now();
const run = runBundle(MODULES, PRELUDE + testSource + EPILOGUE, bundlePath, {});
const elapsedMs = Date.now() - started;

const out = (run.stdout || "") + (run.stderr || "");
const result = out.match(/__TK_RESULT__ passed=(\d+) failed=(\d+)/);

if (!result) {
	console.error("TIDEKEEPER Luau test: the suite did not reach its epilogue.");
	console.error("");
	console.error(out.trim().split("\n").slice(-40).join("\n"));
	console.error("");
	console.error(`bundle kept at ${path.relative(REPO, bundlePath)} for inspection`);
	process.exit(1);
}

const passed = Number(result[1]);
const failed = Number(result[2]);
const failures = [...out.matchAll(/__TK_FAIL__ (.*)/g)].map((m) => m[1].trim());

for (const f of failures) console.log(`FAIL  ${f}`);

// ------------------------------------------------------------- cross-check
//
// Agreement between the two VMs is the actual deliverable. A Luau-only number
// would be better than a fengari-only number, but a number both VMs agree on
// rules out "the harness is wrong" AND "the port is wrong" at once.
let compare = null;
if (has("--compare")) {
	const r = spawnSync(process.execPath, [path.join(ROOT, "tools", "tidekeeper-smoke-test.js"), "--no-bench"], {
		cwd: REPO,
		encoding: "utf8",
		maxBuffer: 32 * 1024 * 1024,
	});
	const m = ((r.stdout || "") + (r.stderr || "")).match(/TIDEKEEPER smoke test: (\d+) passed, (\d+) failed/);
	if (!m) {
		console.error("TIDEKEEPER Luau test: --compare could not read the fengari suite's total.");
		process.exit(1);
	}
	compare = { passed: Number(m[1]), failed: Number(m[2]) };
}

// ------------------------------------------------------------------ report
console.log("");
console.log(`=== pure-tests.lua in REAL Luau (${path.relative(REPO, luau) || luau}) ===`);
console.log(`  passed         ${passed}`);
console.log(`  failed         ${failed}`);
console.log(`  wall time      ${elapsedMs} ms`);
console.log("  shims applied  none (the fengari harness needs four)");

let mismatch = false;
if (compare) {
	console.log("");
	console.log("=== cross-check against the fengari suite ===");
	console.log(`  fengari        ${compare.passed} passed, ${compare.failed} failed`);
	console.log(`  real Luau      ${passed} passed, ${failed} failed`);
	mismatch = compare.passed !== passed || compare.failed !== failed;
	console.log(`  agreement      ${mismatch ? "MISMATCH" : "identical"}`);
	if (mismatch) {
		console.log("");
		console.log("  The two VMs disagree about the same source file. That means one of");
		console.log("  them is not running the game you think it is. Do not pick the");
		console.log("  convenient number -- find out which.");
	}
}

const jsonPath = valueOf("--json");
if (jsonPath) {
	const p = path.resolve(REPO, jsonPath);
	fs.mkdirSync(path.dirname(p), { recursive: true });
	fs.writeFileSync(
		p,
		JSON.stringify({ generatedAt: new Date().toISOString(), luau, passed, failed, failures, elapsedMs, compare }, null, 2)
	);
}

console.log("");
console.log(`TIDEKEEPER Luau test: ${passed} passed, ${failed} failed${compare ? (mismatch ? ", MISMATCH vs fengari" : ", agrees with fengari") : ""}`);
process.exit(failed > 0 || mismatch ? 1 : 0);
