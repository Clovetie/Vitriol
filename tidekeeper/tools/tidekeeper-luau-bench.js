#!/usr/bin/env node
/**
 * tools/tidekeeper-luau-bench.js
 *
 * Runs the pure TIDEKEEPER modules in a REAL Luau VM and measures
 * Visit.resolve and Resolve.run against the budgets in doc 04 section 6 and
 * doc 01 section 5.
 *
 * This is the tool that settles OD12, which iterations 2 and 3 both deferred
 * for want of Roblox Studio. It does not need Studio: `luau` is the same
 * language runtime Roblox embeds, published as a standalone binary by the
 * Luau team at Roblox (doc 10 section 7.1).
 *
 *   node tidekeeper/tools/tidekeeper-luau-bench.js
 *   node tidekeeper/tools/tidekeeper-luau-bench.js --json reports/bench.json
 *   TIDEKEEPER_LUAU=/path/to/luau node tidekeeper/tools/tidekeeper-luau-bench.js
 *
 * EXIT CODES
 *   0  measured, and within budget  — or skipped because no `luau` was found
 *   1  measured, and OVER budget, or a correctness check disagreed
 *
 * Exit 0 on "no binary" is deliberate: the gate must stay green on a machine
 * that has not built Luau, and a skipped check reports itself loudly as
 * skipped. A check that silently becomes a no-op is worse than no check, so
 * the word SKIPPED is printed, not swallowed.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { runBundle, findLuau } = require("./lib/luau-native.js");

const ROOT = path.resolve(__dirname, "..", "..");
const CODE = path.join(ROOT, "tidekeeper", "code", "ReplicatedStorage", "Tidekeeper");
const OUT = path.join(__dirname, "reports");

const MODULES = {
	GameConfig: `${CODE}/Config/GameConfig.luau`,
	TideConfig: `${CODE}/Config/TideConfig.luau`,
	EconomyConfig: `${CODE}/Config/EconomyConfig.luau`,
	DrifterConfig: `${CODE}/Config/DrifterConfig.luau`,
	OrdersConfig: `${CODE}/Config/OrdersConfig.luau`,
	FindsConfig: `${CODE}/Config/FindsConfig.luau`,
	NotifyConfig: `${CODE}/Config/NotifyConfig.luau`,
	MathExt: `${CODE}/Lib/MathExt.luau`,
	Hash: `${CODE}/Lib/Hash.luau`,
	RNG: `${CODE}/Lib/RNG.luau`,
	Tables: `${CODE}/Lib/Tables.luau`,
	Signal: `${CODE}/Lib/Signal.luau`,
	Codec: `${CODE}/Lib/Codec.luau`,
	Schema: `${CODE}/Lib/Schema.luau`,
	Tide: `${CODE}/Lib/Tide.luau`,
	Version: `${CODE}/Shared/Version.luau`,
	DrifterCodec: `${CODE}/Shared/DrifterCodec.luau`,
	PostCodec: `${CODE}/Shared/PostCodec.luau`,
	ReceiptCodec: `${CODE}/Shared/ReceiptCodec.luau`,
	Standing: `${CODE}/Domain/Standing.luau`,
	Almanac: `${CODE}/Domain/Almanac.luau`,
	Drifter: `${CODE}/Domain/Drifter.luau`,
	Post: `${CODE}/Domain/Post.luau`,
	Orders: `${CODE}/Domain/Orders.luau`,
	Ledger: `${CODE}/Domain/Ledger.luau`,
	Visit: `${CODE}/Domain/Visit.luau`,
	Resolve: `${CODE}/Domain/Resolve.luau`,
};

function main() {
	const argv = process.argv.slice(2);
	const jsonAt = argv.indexOf("--json");
	const jsonPath = jsonAt >= 0 ? argv[jsonAt + 1] : null;
	const codegen = argv.includes("--codegen");

	const luau = findLuau();
	if (!luau) {
		console.log("TIDEKEEPER Luau bench: SKIPPED — no `luau` binary found.");
		console.log("");
		console.log("  This check measures Visit.resolve in a real Luau VM (OD12). It is");
		console.log("  skipped, not failed, so the gate stays green without it — but the");
		console.log("  18 us budget is then UNVERIFIED and must be reported as such.");
		console.log("");
		console.log("  To build it (about 4 minutes, needs g++ and make):");
		console.log("    git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau");
		console.log("    make -C /tmp/luau config=release luau -j$(nproc)");
		console.log("    cp /tmp/luau/luau tidekeeper/tools/bin/luau");
		console.log("");
		console.log("  Or point TIDEKEEPER_LUAU at an existing binary.");
		process.exit(0);
	}

	const body = fs.readFileSync(path.join(__dirname, "bench", "resolve-bench.luau"), "utf8");
	const bundlePath = path.join(OUT, "bench-bundle.luau");

	console.log(`TIDEKEEPER Luau bench — real Luau VM at ${luau}`);
	console.log(`  ${Object.keys(MODULES).length} module(s), -O2${codegen ? " --codegen" : ""}`);
	console.log("");

	const res = runBundle(MODULES, body, bundlePath, { codegen });
	process.stdout.write(res.stdout);
	if (res.stderr) process.stderr.write(res.stderr);
	if (!res.ok) {
		console.error("\nTIDEKEEPER Luau bench: FAILED to execute the bundle.");
		process.exit(1);
	}

	const line = (res.stdout.match(/^RESULT .*$/m) || [])[0] || "";
	const verdict = /verdict=(\w+)/.exec(line);
	const median = parseFloat((/median=([\d.]+)us/.exec(line) || [])[1]);
	const p99 = parseFloat((/p99=([\d.]+)us/.exec(line) || [])[1]);
	const catchup = parseFloat((/catchup=([\d.]+)us/.exec(line) || [])[1]);

	if (jsonPath) {
		fs.mkdirSync(path.dirname(path.resolve(jsonPath)), { recursive: true });
		fs.writeFileSync(
			path.resolve(jsonPath),
			JSON.stringify({ luau, median, p99, catchup, verdict: verdict && verdict[1] }, null, 2)
		);
	}

	if (/MISMATCH/.test(res.stdout)) {
		console.error("\nTIDEKEEPER Luau bench: FAILED — real Luau disagrees with the fengari suite.");
		process.exit(1);
	}
	if (!verdict) {
		console.error("\nTIDEKEEPER Luau bench: FAILED — no RESULT line.");
		process.exit(1);
	}
	if (verdict[1] !== "WITHIN_BUDGET") {
		console.error(`\nTIDEKEEPER Luau bench: OVER BUDGET (median ${median} us, p99 ${p99} us).`);
		process.exit(1);
	}
	console.log(`\nTIDEKEEPER Luau bench: within budget (median ${median} us, p99 ${p99} us, catch-up ${catchup} us).`);
	process.exit(0);
}

main();
