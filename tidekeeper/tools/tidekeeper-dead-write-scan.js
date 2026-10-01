#!/usr/bin/env node
"use strict";
//
// tidekeeper-dead-write-scan.js -- find fields written onto shared state that
// nothing ever reads.
//
// WHY THIS EXISTS
// ---------------
// Iteration 7 found that the entire RF_Dispatch feature was inert. The handler
// did this:
//
//     S.dispatchedAt   = epoch
//     S.dispatchLetter = payload.letterId
//     S.dispatchCargo  = cargo
//
// ...and `dispatchLetter` and `dispatchCargo` were read by NOTHING. The
// outbound drifter was built by ExchangeService, which recomputed cargo from
// the shelves and hard-coded `d.letterId = 0`. So a player could choose cargo
// and attach a letter, and both choices were silently discarded. The Ledger
// template for "your drifter brought a note back" was unreachable prose.
//
// Every existing check was green while this was true, because each half is
// individually valid code: the handler writes a field (fine), the service
// reads a different one (fine). The defect only exists in the GAP between two
// modules, which is exactly where this project keeps losing features --
// the iteration-6 remote-folder bug was the same shape.
//
// `tidekeeper-member-scan.js` catches the mirror image: a field READ that was
// never written. This catches a field WRITTEN that is never read. Between
// them they close both directions of the cross-module field contract.
//
// SCOPE, AND WHY IT IS NARROW
// ---------------------------
// Only fields written onto the shared post/session state object are checked --
// the receivers in STATE_RECEIVERS below. That object is the one piece of
// mutable state every module touches, so it is where a dropped write is both
// most likely and most expensive. Widening this to every table in the project
// would produce a flood of false positives on local scratch tables, and a
// scan that cries wolf gets switched off and then protects nothing.
//
// Usage: node tidekeeper/tools/tidekeeper-dead-write-scan.js [--quiet]

const fs = require("fs");
const path = require("path");

const GAME = path.resolve(__dirname, "..");
const SRC = path.join(GAME, "code");
const REPO = path.resolve(GAME, "..");

// Identifiers that, by convention in this codebase, hold the post/session
// state table. `S` is overwhelmingly the common one; the others appear in
// Resolve and the services.
const STATE_RECEIVERS = new Set(["S", "S2", "state", "post"]);

// Fields that are legitimately write-only from the game's point of view.
// Each needs a reason, and the reason is checked by a human, not by the tool.
const ALLOWED_WRITE_ONLY = new Map([
	// (none yet -- add with a justification, never to silence a real finding)
]);

function walk(dir, out) {
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) walk(p, out);
		else if (e.name.endsWith(".luau")) out.push(p);
	}
	return out;
}

// Remove comments and string literals so that prose and template text can
// never be mistaken for code. Same approach as the member scan.
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
	const quiet = process.argv.includes("--quiet");
	const files = walk(SRC, []).sort();

	// field -> [{file, line}]
	const writes = new Map();
	// field -> true if read anywhere, on any receiver
	const reads = new Set();

	const recv = [...STATE_RECEIVERS].join("|");
	// `S.field =` but not `S.field ==`, and not `S.field` inside a longer path.
	const WRITE_RE = new RegExp(`\\b(?:${recv})\\.([A-Za-z_]\\w*)\\s*=(?!=)`, "g");
	// Any `.field` that is NOT an assignment target: a read.
	const READ_RE = /\.([A-Za-z_]\w*)\s*(?!=(?!=))/g;

	for (const f of files) {
		const code = strip(fs.readFileSync(f, "utf8"));
		const rel = path.relative(REPO, f);
		const lines = code.split("\n");

		lines.forEach((text, idx) => {
			let m;
			WRITE_RE.lastIndex = 0;
			while ((m = WRITE_RE.exec(text)) !== null) {
				const field = m[1];
				if (!writes.has(field)) writes.set(field, []);
				writes.get(field).push({ file: rel, line: idx + 1 });
			}
		});

		// Reads are collected across the whole project, on ANY receiver -- a
		// field written as `S.x` and read as `self.post.x` is still live.
		let m;
		READ_RE.lastIndex = 0;
		const noAssign = code.replace(new RegExp(`\\b(?:${recv})\\.([A-Za-z_]\\w*)\\s*=(?!=)`, "g"), " ");
		while ((m = READ_RE.exec(noAssign)) !== null) reads.add(m[1]);
	}

	const dead = [];
	for (const [field, sites] of writes) {
		if (reads.has(field)) continue;
		if (ALLOWED_WRITE_ONLY.has(field)) continue;
		dead.push({ field, sites });
	}
	dead.sort((a, b) => a.field.localeCompare(b.field));

	const checked = [...writes.keys()].length;
	console.log(
		`TIDEKEEPER dead-write scan — ${files.length} file(s), ${checked} field(s) written to shared state`
	);
	console.log("");

	if (dead.length === 0) {
		console.log(`clean — every field written to shared state is read somewhere (${checked} checked)`);
		return 0;
	}

	for (const d of dead) {
		for (const s of d.sites) {
			console.log(`FAIL ${s.file}:${s.line}  S.${d.field}  — written here, read by nothing`);
		}
	}
	console.log("");
	console.log(`${dead.length} dead write(s). A field nothing reads is a feature that does not work.`);
	return 1;
}

process.exit(main());
