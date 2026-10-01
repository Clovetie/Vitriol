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
const { transformLuau, read, ROOT } = require("./lib/luau-transform");
const { floatifyNumbers, transformModules, buildBundle, runBundle, printLog } = require("./lib/harness");

// The fengari harness -- number semantics, bit32, the module loader -- lives
// in lib/harness.js, shared with tidekeeper-session-test.js. Read the header
// there before changing anything about how numbers behave in this VM.
// Logical name -> path relative to tidekeeper/. The logical name must equal the
// last segment of the module's `require` path, because that is how the
// transform rewrites requires.
//
// This list USED TO BE DUPLICATED HERE, which is precisely what decision D32
// forbids. It drifted the moment iteration 7 added LettersConfig to the shared
// map: the Luau runner picked it up and this one crashed with "unknown module
// LettersConfig", on a file that had not changed. Two lists of the same thing
// is one list and one liability, so this now reads the real one.
const MODULES = require("./lib/module-map.js").PURE_REL;

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
const transformed = transformModules(MODULES);

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


const bundle = buildBundle({
	modules: transformed,
	globals: {
		BENCH_ENABLED: noBench ? "false" : "true",
		// Real captured v1 save (tools/fixture-blobs/). Passed in rather than
		// read from Lua because the harness has no filesystem.
		FIXTURE_POST_V1: JSON.stringify(
			fs.readFileSync(path.join(__dirname, "fixture-blobs", "post-v1.b64"), "utf8").trim()
		),
	},
	tests: testSource,
});

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------
const run = runBundle(bundle);
printLog(run.log);

if (!run.ok) {
	console.error("\nHARNESS CRASHED:\n" + run.error);
	process.exit(1);
}

console.log("\n--- static proofs (source inspection, not the VM) ---");
let staticFailures = 0;
for (const check of staticChecks) {
	if (!check.ok) staticFailures += 1;
	console.log(`${check.ok ? "  ok " : "FAIL "} ${check.name}  [${check.detail}]`);
}

if (run.tests === null) {
	console.error("pure-tests.lua did not define a TESTS table");
	process.exit(1);
}
const passed = run.tests.passed;
const failed = run.tests.failed;

console.log("");
console.log(`harness wall time: ${run.elapsedMs.toFixed(0)} ms`);
console.log(
	`TIDEKEEPER smoke test: ${passed} passed, ${failed} failed, ${staticFailures} static proof(s) failed`
);
process.exit(failed > 0 || staticFailures > 0 ? 1 : 0);
