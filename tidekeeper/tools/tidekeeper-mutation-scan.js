#!/usr/bin/env node
"use strict";
//
// tidekeeper-mutation-scan.js -- a test that runs but cannot fail.
//
// WHY THIS EXISTS
// ---------------
// Level seven of the ladder in docs/10-RESEARCH-NOTES.md section 12. The six
// scans before it ask structural questions:
//
//   member-scan        a field READ that is never written
//   dead-write-scan    a field WRITTEN that is never read
//   orphan-scan        a FUNCTION defined that is never called
//   orphan-scan (D44)  an ALLOWLIST ENTRY gone stale
//   remote-scan        a REMOTE one side never speaks
//   dead-content-scan  a STRING a player can never see
//   mutation-scan      a VALUE no test constrains                  <- this
//
// Every one of those can be answered by reading the source. This one cannot.
// "Does the suite actually check this?" is only answerable by breaking the
// code on purpose and seeing whether anything notices.
//
// Iteration 11 first tried the two cheaper versions of the question and both
// came back clean, which is worth recording because clean is a result:
//
//   * ASSERTIONS THAT NEVER RUN. Instrumenting the assert helpers to record
//     debug.getinfo line numbers and diffing against the static call sites
//     found 3 of 1130 call sites unexecuted, and all three were legitimate
//     (`ok(false, ...)` inside failure branches that must not be reached).
//   * TESTS ASSERTING ON FIELDS THAT DO NOT EXIST. member-scan only walks
//     code/, so the 4600 lines of test files -- the project's entire
//     evidence base -- had never been member-checked. Extending it found
//     1615 references and 0 problems.
//
// Mutation found what those could not. On its first full run, **every single
// number in the economy table was unconstrained**: STANDING_ON_SERVED,
// RENOWN_ON_GIFT, WARMTH_BASE_SERVED, SPOIL_PER_MILLE, PASSIVE_RATE_PER_MILLE
// and twenty more could each be changed and all 1755 assertions still passed.
// Doc 06 is the longest design document in the project and nothing verified
// its numbers.
//
// WHAT IT DOES
// ------------
// For each scalar constant in Config/*.luau, change it by one and run the
// suite. If the suite still passes, nothing in the project depends on that
// value being what the design says it is.
//
// TWO MODES, because the honest version is slow:
//
//   default   Re-check only the constants recorded below as GUARDED, using
//             the real-Luau pure suite (~0.8 s per run). This is the gate
//             check: it detects TEST ROT -- an assertion weakened or deleted
//             so that a value that used to be pinned no longer is.
//   --full    Every constant, against the pure suite and then (for anything
//             that survives) the session and smoke suites. ~90 minutes.
//             This is the discovery run; use it when adding config.
//
// THE MANIFEST IS EXHAUSTIVE ON PURPOSE. A constant that appears in config
// and is in neither list fails the scan. New config arrives classified or it
// does not arrive -- which is the same rule the orphan allowlist follows, and
// for the same reason: a list nobody is forced to maintain rots into a list
// nobody believes.
//
// Verified in both directions (D44): an UNGUARDED entry that starts being
// caught fails too, and must be promoted.

const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const GAME = path.resolve(__dirname, "..");
const CFG = path.join(GAME, "code", "ReplicatedStorage", "Tidekeeper", "Config");

// Constants whose value IS pinned by the fast pure suite. Mutating any of
// these must break it. Measured 2026-10-02.
const GUARDED = [
	"DrifterConfig.TASTE_AXES",
	"DrifterConfig.AXIS_DEAR",
	"DrifterConfig.MAX_WANTS",
	"DrifterConfig.MAX_CARGO",
	"EconomyConfig.STANDING_MAX",
	"EconomyConfig.STANDING_DECAY_PER_MILLE",
	"EconomyConfig.STANDING_ON_MISSED_TIDE",
	"EconomyConfig.CURRENT_COUNT",
	"EconomyConfig.MIN_PRICE",
	"FindsConfig.MAX_FIND_ID",
	"GameConfig.SCHEMA_VERSION",
	"GameConfig.MAX_BERTHS",
	"GameConfig.MAX_STOCK_PER_ENTRY",
	"GameConfig.MAX_TIER",
	"GameConfig.DRIFTER_BLOB_BYTES",
	"GameConfig.DRIFTER_ID_EPOCH_SPAN",
	"LettersConfig.MAX_LETTER_ID",
	"OrdersConfig.ARG_NONE",
	"OrdersConfig.ARG_U8",
	"OrdersConfig.ARG_U16",
	"OrdersConfig.ARG_U32",
	"OrdersConfig.ARG_I8",
	"OrdersConfig.PRICE_ADJUST_MAX",
	"OrdersConfig.MAX_NEST_DEPTH",
	"SeedsConfig.SEED_COUNT",
	"TideConfig.EPOCH",
	"TideConfig.EPOCH_SECONDS",
	"TideConfig.DAY_SECONDS",
	// Promoted by iteration 11, which wrote the economy pinning tests.
	"EconomyConfig.STANDING_ON_SERVED",
	"EconomyConfig.STANDING_ON_PARTIAL",
	"EconomyConfig.STANDING_ON_GIFT",
	"EconomyConfig.RENOWN_ON_SERVED",
	"EconomyConfig.RENOWN_ON_GIFT",
	"EconomyConfig.WARMTH_BASE_SERVED",
	"EconomyConfig.WARMTH_BASE_PARTIAL",
	"EconomyConfig.WARMTH_BASE_GIFT",
	"EconomyConfig.WARMTH_PER_WANT_MET",
	"EconomyConfig.WARMTH_MAX",
	"EconomyConfig.PASSIVE_RATE_PER_MILLE",
	"EconomyConfig.SPOIL_PER_MILLE",
	"EconomyConfig.MAX_ITEMS_PER_VISIT",
	"EconomyConfig.LONG_ABSENCE_CACHE_COIN",
	"EconomyConfig.LONG_ABSENCE_CACHE_ITEMS",
	"EconomyConfig.COMB_RESPAWN_EPOCHS",
	"EconomyConfig.MAX_PRICE",
	"DrifterConfig.TASTE_MAX",
	// Pinned by the OD15 blob-budget section, iteration 11.
	"GameConfig.MAX_POST_BLOB_BYTES",
];

// Pinned, but only by a suite too slow for the gate (session ~20 s, smoke
// ~75 s). Recorded so the --full run can tell "nothing checks this" apart
// from "the fast suite does not check this", and so the gate does not report
// them as rot when it cannot see them.
const GUARDED_SLOW = [
	["GameConfig.RECEIPT_BLOB_BYTES", "session: receipt blobs are round-tripped through the real exchange"],
	["NotifyConfig.MAX_PER_USER_PER_DAY", "session: the daily throttle is asserted against the real NotifyService"],
];

// Constants no test pins, each with a reason that is honest about why not.
// Shrinking this list is real work for a future iteration; padding it is not.
const UNGUARDED = [
	["BadgesConfig.KIND_COUNTER", "a tag compared only against itself; no behaviour branches on the number"],
	["BadgesConfig.KIND_MILESTONE", "as above"],
	["BadgesConfig.KIND_COLLECTION", "as above"],
	["DrifterConfig.AXIS_SOCIAL", "an index into the taste array; any value in range names *a* valid axis, so the suite cannot tell one choice from another without pinning the authored content to axes by name"],
	["DrifterConfig.AXIS_KIND", "as above"],
	["DrifterConfig.MAX_BEACONS", "a ceiling nothing reaches in any test; needs a scenario that actually saturates beacons"],
	["FindsConfig.ZONE_COUNT", "comb zones are exercised by id, never counted"],
	["GameConfig.OLDEST_SUPPORTED_VERSION", "only two schema versions exist, so 1 and 2 behave identically here. Re-check at schema v4"],
	["GameConfig.MAX_CATCHUP_EPOCHS", "the clamp is asserted via Resolve's own reported epoch count rather than against this constant; a session scenario that returns after 30+ epochs would pin it"],
	["GameConfig.EPOCHS_PER_RESOLVE_TICK", "a scheduling granularity; changing it changes how work is split, not the result -- which is the determinism property, and that IS asserted"],
	["GameConfig.MAX_ARRIVALS_PER_EPOCH", "no scenario produces enough arrivals to hit the cap"],
	["GameConfig.MAX_RESIDENT_DRIFTERS", "as above"],
	["GameConfig.MAX_SHELF_SLOTS", "tier caps bind first; this ceiling is never the binding one in any test"],
	["GameConfig.MAX_STORE_ENTRIES", "as above"],
	["GameConfig.MAX_COIN", "the u32 ceiling; no test earns near it"],
	["GameConfig.MAX_COMB_NODES", "nodes are addressed by id, never counted"],
	["GameConfig.VISITOR_RING_SIZE", "the ring is asserted by behaviour (oldest evicted first), not by size"],
	["GameConfig.MAX_LEDGER_RESIDENT", "scenario 24 overflows it but asserts on pages written, not on the threshold"],
	["GameConfig.MAX_LEDGER_SLOTS", "Ledger.SLOT_COUNT pins arity per template; this global ceiling is slack"],
	["GameConfig.MAX_ORDERS_BYTES", "as above, for order programs"],
	["NotifyConfig.KIND_DEEPWATER", "notification kinds are inert: OD7 closed as 'no send API exists', so nothing branches on them"],
	["NotifyConfig.KIND_SPRING_TIDE", "as above"],
	["NotifyConfig.KIND_NAMED_RETURN", "as above"],
	["NotifyConfig.KIND_INBOX_FULL", "as above"],
	["NotifyConfig.DAY_SECONDS", "as above"],
	["NotifyConfig.MAX_LEAD_SECONDS", "as above"],
	["NotifyConfig.MIN_LEAD_SECONDS", "as above"],
	["NotifyConfig.INBOX_THRESHOLD", "as above"],
	["NotifyConfig.SEND_ATTEMPTS", "as above"],
	["NotifyConfig.MIN_VISITS_REQUIRED", "as above"],
	["OrdersConfig.BYTECODE_VERSION", "only one bytecode version exists; pin it when a second arrives"],
	["SeedsConfig.SEED_OWNER_BASE", "seed owners are identified by isSeed(), which derives from this constant, so moving it moves both sides together"],
	["TideConfig.SCAN_STEP", "a solver step size: changing it changes precision, not the answer the tests assert"],
	["TideConfig.BISECTIONS", "as above"],
	["TideConfig.RANGE_SAMPLE_STEP", "as above"],
	// These two were invisible to the scan until its line regex was fixed to
	// tolerate a trailing comment -- they had never been mutated at all.
	["GameConfig.OWNER_ID_MAX", "an id ceiling; no test uses an owner id anywhere near it"],
	["TideConfig.SCAN_HORIZON", "how far the tide solver looks ahead; changing it changes cost, not the answers the tests assert"],
];

function targets() {
	const out = [];
	for (const file of fs.readdirSync(CFG).sort()) {
		if (!file.endsWith(".luau")) continue;
		const p = path.join(CFG, file);
		const lines = fs.readFileSync(p, "utf8").split("\n");
		const mod = path.basename(file, ".luau");
		lines.forEach((line, i) => {
			// Tolerate spacing and a trailing comment. The first version of
			// this regex demanded `\tNAME = 123,` exactly, so merely adding
			// an explanatory comment to a config line made the scan announce
			// that the constant "no longer exists" -- the iteration-10
			// warning about scans encoding today's idioms, arriving on
			// schedule. Found by deliberately reformatting a line that was
			// not otherwise being changed.
			const m = /^\t([A-Z][A-Z0-9_]*)\s*=\s*(\d+)\s*,\s*(?:--.*)?$/.exec(line);
			if (m) out.push({ path: p, key: `${mod}.${m[1]}`, line: i, value: Number(m[2]), text: line });
		});
	}
	return out;
}

function suitePasses(cmd) {
	try {
		cp.execSync(cmd, { cwd: GAME, stdio: "pipe", timeout: 600000 });
		return true;
	} catch (e) {
		return false;
	}
}

// Apply a mutation, run `fn`, and ALWAYS put the file back -- including if
// the runner throws or the process is interrupted mid-check. A scan that can
// leave a mutated constant behind is worse than no scan.
function withMutation(t, fn) {
	const original = fs.readFileSync(t.path, "utf8");
	try {
		const lines = original.split("\n");
		const next = t.value === 0 ? 1 : t.value + 1;
		lines[t.line] = t.text.replace(/=(\s*)\d+/, `=$1${next}`);
		fs.writeFileSync(t.path, lines.join("\n"));
		return fn();
	} finally {
		fs.writeFileSync(t.path, original);
	}
}

function main() {
	const full = process.argv.includes("--full");
	const all = targets();
	const guarded = new Set(GUARDED);
	const unguarded = new Map(UNGUARDED);
	const guardedSlow = new Map(GUARDED_SLOW);
	const failures = [];

	// Unclassified config is a failure in both directions.
	for (const t of all) {
		if (!guarded.has(t.key) && !unguarded.has(t.key) && !guardedSlow.has(t.key)) {
			failures.push(`${t.key}  — new config constant, not classified. Run --full and add it to GUARDED or UNGUARDED.`);
		}
	}
	const known = new Set(all.map((t) => t.key));
	for (const k of guarded) {
		if (!known.has(k)) failures.push(`${k}  — listed as GUARDED but no longer exists in config; remove the entry.`);
	}
	for (const [k] of unguarded) {
		if (!known.has(k)) failures.push(`${k}  — listed as UNGUARDED but no longer exists in config; remove the entry.`);
	}
	for (const [k] of guardedSlow) {
		if (!known.has(k)) failures.push(`${k}  — listed as GUARDED_SLOW but no longer exists in config; remove the entry.`);
	}

	const toCheck = full ? all : all.filter((t) => guarded.has(t.key));
	const PURE = "node tools/tidekeeper-luau-test.js";
	let caught = 0;
	const survived = [];

	for (const t of toCheck) {
		const pureCaught = withMutation(t, () => !suitePasses(PURE));
		let isCaught = pureCaught;
		if (!isCaught && full) {
			// Only the slow suites can speak for what the pure suite misses.
			isCaught = withMutation(t, () => !suitePasses("node tools/tidekeeper-session-test.js"))
				|| withMutation(t, () => !suitePasses("node tools/tidekeeper-smoke-test.js"));
		}
		if (isCaught) {
			caught += 1;
			if (unguarded.has(t.key)) {
				failures.push(`${t.key}  — listed as UNGUARDED but a test now catches it; promote it to GUARDED.`);
			}
		} else {
			survived.push(t.key);
			if (guarded.has(t.key)) {
				failures.push(`${t.key}  — GUARDED, but changing it from ${t.value} breaks NO test. The assertion that pinned it is gone or weakened.`);
			}
		}
	}

	console.log(
		`TIDEKEEPER mutation scan — ${toCheck.length} constant(s) mutated` +
			`${full ? " (full: pure, then session, then smoke)" : " (guarded set, pure suite)"}, ` +
			`${all.length} in config`
	);
	console.log("");

	if (full) {
		console.log(`  caught by a test: ${caught}`);
		console.log(`  survived:         ${survived.length}`);
		for (const k of survived) console.log(`     ${k}`);
		console.log("");
	}

	if (failures.length === 0) {
		console.log(
			`clean — every guarded constant is still pinned by a test ` +
				`(${toCheck.length} mutated, ${UNGUARDED.length} known-unguarded)`
		);
		return 0;
	}
	for (const f of failures) console.log(`FAIL ${f}`);
	console.log("");
	console.log(`${failures.length} problem(s). A value no test constrains is a test that cannot fail.`);
	return 1;
}

process.exit(main());
