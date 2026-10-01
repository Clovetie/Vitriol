#!/usr/bin/env node
"use strict";
//
// tidekeeper-orphan-scan.js -- find exported functions that nothing ever
// calls.
//
// WHY THIS EXISTS
// ---------------
// Iteration 8 went looking for a fifth dead feature and found three, all of
// the same shape and all invisible to the fourteen checks that were passing:
//
//   1. `DataStoreAdapter:savePost` pushes an abandoned write onto a
//      MemoryStore recovery queue. `popRecovery` and `ackRecovery` existed to
//      drain it. NOTHING CALLED THEM. The last-resort net against data loss
//      caught the blob and dropped it on the floor.
//   2. `LedgerService:flushPending` archives older Ledger entries into pages.
//      `DataStoreAdapter:loadLedgerPage` exists to read them back. NOTHING
//      CALLED IT, and no remote asks for history -- so every entry that
//      scrolled past MAX_LEDGER_RESIDENT became permanently unreadable.
//   3. `DataStoreAdapter:reapPoolShard` is the reaper for the drifter pool.
//      NOTHING CALLED IT, so the pool only ever grows.
//
// The member scan and the dead-write scan both check FIELDS. A function that
// is defined, correct, tested in isolation and never called is invisible to
// both: every individual module parses, type-checks and passes its unit
// tests. The feature is missing from the SEAM, which is where this project
// keeps losing things -- the same lesson as iterations 6 and 7, one level up.
//
// WHAT COUNTS AS A CALL
// ---------------------
// A reference to `.name` or `:name` anywhere in the game source OR in the
// test suites. Tests count deliberately: a function exercised only by tests
// is not dead, it is staged -- but it must then be on the allowlist with a
// reason saying what will call it, so "staged" cannot quietly become
// "forgotten".
//
// Matching is by bare member name across the whole corpus, so it is
// deliberately GENEROUS: two modules with a same-named method shield each
// other. That is the right bias. A scan that cries wolf gets switched off and
// then protects nothing; this one should only ever fire on something genuinely dead.
//
// THE ALLOWLIST IS CHECKED IN BOTH DIRECTIONS
// -------------------------------------------
// An orphan not on the list fails the scan. An allowlist entry that is NO
// LONGER an orphan also fails it, so the list cannot rot into a pile of
// stale excuses -- the same two-direction discipline as decision D39.

const fs = require("fs");
const path = require("path");

const GAME = path.resolve(__dirname, "..");
const SRC = path.join(GAME, "code");
const TESTS = path.join(GAME, "tools", "tests");

// Every entry needs a reason, and the reason is checked by a human, not by
// the tool. "It is not called yet" is not a reason; "X will call it, and
// until then the feature is documented as absent" is.
const ALLOWED_ORPHANS = new Map([
	// --- deliberate library surface -------------------------------------
	// Lib/* is a small toolkit written to be complete rather than to be
	// exactly as large as today's callers. These are the unused corners.
	["RNG.chance", "toolkit completeness; chancePerMille is the one in use"],
	["RNG.float", "toolkit completeness; the game is integer-only by D14"],
	["Reader.seek", "codec toolkit; no format needs random access yet"],
	["Writer.len", "codec toolkit; used by future variable-length sections"],
	["Drifter.affinity", "pure helper kept beside carries(); ExchangeService inlines the same maths"],
	["Drifter.carries", "pure helper; cargo matching currently happens in Resolve"],

	// --- diagnostics, called by a human at a console --------------------
	["DebugHandler.print", "developer console entry point; never called by game code by design"],
	["Profiler.worstOffender", "read in Studio while profiling"],
	["BudgetMeter.memoryRequestFloor", "read in Studio when tuning quota"],
	["MemoryAdapter.requestUnitsPerMinute", "quota arithmetic surfaced for diagnostics"],
	["MemoryAdapter.lockHolder", "answers 'who holds this lock' during an incident"],
	["LedgerView.templatesUsed", "coverage reporting for the prose templates"],
	["NetContract.isClientBound", "contract introspection used when adding a remote"],

	// --- teardown paths, exercised only when a server dies --------------
	["PlayerService.unbindAll", "BindToClose teardown; see doc 05 section 10"],
	["NetContract.resetPlayer", "per-player rate-guard reset on leave"],
	["MemoryAdapter.clearIndex", "index teardown for a shard that is being retired"],

	// --- blocked on a client that does not exist yet --------------------
	// These are the payload builders for UI nobody has built. They are real
	// unfinished work, tracked in doc 07, NOT library surface.
	//
	// Iteration 9 wired the ACTIONS up, so arrangePayload and
	// setOrdersPayload left this list -- and the scan made them leave by
	// failing on the stale entries rather than letting them sit here
	// looking like excuses. What remains is presentation: the preview and
	// layout helpers that need a real screen.
	["OrdersView.preview", "client UI not built; doc 07 row Orders"],
	["OrdersView.domainValues", "client UI not built; doc 07 row Orders"],
	["TideView.dayCurve", "client UI not built; doc 07 row Tide dial"],

	// --- blocked on a platform capability that does not exist -----------
	["NotifyService.shouldPromptOptIn", "OD7: the send half of the API is removed; NotifyAdapter is capability-flagged"],
	["NotifyService.launchDataFor", "OD7: ditto -- kept so the feature is one wiring change away"],

	// --- compliance surface, dormant until the game sells anything ------
	// Nothing in TIDEKEEPER takes money today. If that ever changes these
	// two MUST gate it; leaving them uncalled is correct only while there is
	// no paid content at all.
	["PolicyAdapter.mayOfferPaidRandomItems", "no paid content exists; must gate any future paid random item"],
	["PolicyAdapter.mayTradePaidItems", "no paid content exists; must gate any future paid trade"],

	// --- genuinely unfinished, scheduled -------------------------------
	["DataStoreAdapter.reapPoolShard", "pool reaper not yet scheduled; see OD21 and doc 05 section 9"],
	["DataStoreAdapter.loadLedgerPage", "Ledger history read path not built; see OD22 and doc 07"],
]);

function walk(dir, ext, out) {
	if (!fs.existsSync(dir)) return out;
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) walk(p, ext, out);
		else if (e.name.endsWith(ext)) out.push(p);
	}
	return out;
}

// Remove comments and string literals so that prose and template text can
// never be mistaken for code. Same approach as the member and dead-write
// scans, so all three agree on what is code.
function strip(code) {
	let out = "";
	for (let i = 0; i < code.length; i++) {
		const two = code.slice(i, i + 2);
		if (two === "--") {
			const longOpen = /^--\[(=*)\[/.exec(code.slice(i));
			if (longOpen) {
				const close = "]" + longOpen[1] + "]";
				const end = code.indexOf(close, i);
				const stop = end === -1 ? code.length : end + close.length;
				for (let k = i; k < stop; k++) out += code[k] === "\n" ? "\n" : " ";
				i = stop - 1;
				continue;
			}
			const nl = code.indexOf("\n", i);
			const stop = nl === -1 ? code.length : nl;
			for (let k = i; k < stop; k++) out += " ";
			i = stop - 1;
			continue;
		}
		const ch = code[i];
		if (ch === '"' || ch === "'") {
			const quote = ch;
			out += " ";
			i++;
			while (i < code.length && code[i] !== quote) {
				if (code[i] === "\\") {
					out += " ";
					i++;
				}
				out += code[i] === "\n" ? "\n" : " ";
				i++;
			}
			out += " ";
			continue;
		}
		const long = /^\[(=*)\[/.exec(code.slice(i));
		if (long) {
			const close = "]" + long[1] + "]";
			const end = code.indexOf(close, i);
			const stop = end === -1 ? code.length : end + close.length;
			for (let k = i; k < stop; k++) out += code[k] === "\n" ? "\n" : " ";
			i = stop - 1;
			continue;
		}
		out += ch;
	}
	return out;
}

function main() {
	const srcFiles = walk(SRC, ".luau", []);
	const testFiles = walk(TESTS, ".lua", []);

	const defs = new Map(); // "Mod.name" -> {file, line}
	let corpus = "";

	for (const f of srcFiles) {
		const code = strip(fs.readFileSync(f, "utf8"));
		corpus += "\n" + code;
		const lines = code.split("\n");
		for (let i = 0; i < lines.length; i++) {
			const m = /^function\s+(\w+)[.:](\w+)\s*\(/.exec(lines[i]);
			if (!m) continue;
			const key = m[1] + "." + m[2];
			if (!defs.has(key)) {
				defs.set(key, { file: path.relative(path.resolve(GAME, ".."), f), line: i + 1, member: m[2] });
			}
		}
	}
	for (const f of testFiles) corpus += "\n" + strip(fs.readFileSync(f, "utf8"));

	// Count references per bare member name, once, rather than re-scanning
	// the corpus for every definition.
	const refs = new Map();
	for (const m of corpus.matchAll(/[.:](\w+)/g)) {
		refs.set(m[1], (refs.get(m[1]) || 0) + 1);
	}

	const orphans = [];
	for (const [key, d] of defs) {
		// The definition itself contributes one `.name`/`:name` occurrence.
		if ((refs.get(d.member) || 0) > 1) continue;
		orphans.push({ key, ...d });
	}
	orphans.sort((a, b) => a.key.localeCompare(b.key));

	const unexplained = orphans.filter((o) => !ALLOWED_ORPHANS.has(o.key));
	const live = new Set(orphans.map((o) => o.key));
	const stale = [...ALLOWED_ORPHANS.keys()].filter((k) => !live.has(k)).sort();

	console.log(
		`TIDEKEEPER orphan scan — ${srcFiles.length} source file(s), ${defs.size} exported function(s), ` +
			`${testFiles.length} test file(s) counted as callers`
	);
	console.log("");

	if (unexplained.length === 0 && stale.length === 0) {
		console.log(
			`clean — every exported function is called, or allowlisted with a reason ` +
				`(${defs.size} checked, ${ALLOWED_ORPHANS.size} allowlisted)`
		);
		return 0;
	}

	for (const o of unexplained) {
		console.log(`FAIL ${o.file}:${o.line}  ${o.key}  — defined here, called by nothing`);
	}
	for (const k of stale) {
		const d = defs.get(k);
		const where = d ? `${d.file}:${d.line}` : "(definition gone)";
		console.log(`FAIL ${where}  ${k}  — on the allowlist but no longer an orphan; remove the entry`);
	}
	console.log("");
	if (unexplained.length > 0) {
		console.log(
			`${unexplained.length} uncalled function(s). A function nothing calls is either a ` +
				`feature that does not work or code that should not exist — fix it, delete it, ` +
				`or allowlist it with a reason.`
		);
	}
	if (stale.length > 0) {
		console.log(`${stale.length} stale allowlist entr(ies). The list must not rot.`);
	}
	return 1;
}

process.exit(main());
