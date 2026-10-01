#!/usr/bin/env node
"use strict";
//
// tidekeeper-dead-content-scan.js -- player-facing content that no code path
// can ever put in front of a player.
//
// WHY THIS EXISTS
// ---------------
// This is level six of the ladder in docs/10-RESEARCH-NOTES.md section 12.
// Every iteration since the sixth has found a feature that was fully built,
// fully tested, and dead -- dead in the SEAM between two modules that were
// each correct alone. The scans have climbed one level each time:
//
//   member-scan        a field READ that is never written
//   dead-write-scan    a field WRITTEN that is never read
//   orphan-scan        a FUNCTION defined that is never called
//   orphan-scan (D44)  an ALLOWLIST ENTRY that has gone stale
//   remote-scan        a REMOTE declared that one side never speaks
//   dead-content-scan  a STRING a player can never see              <- this
//
// Every one of those is about code. This one is about the thing the player
// actually experiences. TIDEKEEPER is a content-heavy game -- 200 finds, 180
// Ledger sentences, 120 letters, 51 UI labels -- and a label that nothing
// renders is invisible in exactly the way the previous five defects were: it
// parses, it is well-formed, it is ready to be localised, and it will never
// reach a human being.
//
// On its first run this found 18 of 51 UI labels dead, including an entire
// screen's worth of furniture (TAB_WORLD, TAB_POST, TAB_CHART, TAB_ALMANAC --
// the whole navigation bar), two labels iteration 9 had added that same day
// and never wired up (UPGRADE_SHORT, UPGRADE_DONE), and one left over from a
// design that was deliberately abandoned (DISPATCH_PHRASE, from before free
// text was banned from the wire).
//
// WHAT IT CHECKS
// --------------
//   1. Every key in Strings.UI is displayed by something -- a literal
//      Format.label("KEY") or a Strings.UI.KEY access, outside Strings.luau.
//   2. Every Format.label("KEY") names a key that EXISTS. Format.label
//      returns "" for a missing key and counts a silent miss, so a typo is a
//      blank label in the player's hands and no error anywhere.
//   3. Every Ledger template constant has a prose row to render it with.
//   4. Every Ledger prose row has a template constant that can select it.
//
// Checks 3 and 4 are the same question asked of the Ledger, which is the
// screen carrying this game's whole emotional argument. Both directions,
// because a template with no prose renders blank and a prose row with no
// template is 9 sentences nobody will read.
//
// THE PARSING TRAP, AND WHY THIS FILE DOES NOT USE strip()
// --------------------------------------------------------
// Iteration 9's remote scan learned that a scan reusing the shared strip()
// cannot parse string-literal DATA from stripped text, because strip() blanks
// string literals -- and the remote names ARE string literals. Its fix was to
// parse from raw text and detect in stripped text, so that a comment
// mentioning a remote could not be mistaken for a call.
//
// That fix cannot be reused here, because the thing being DETECTED is itself
// a string literal: Format.label("LEDGER_TITLE"). Stripping would erase every
// call site. Scanning raw text instead would count this very comment block,
// which mentions LEDGER_TITLE, as a use -- and would therefore hide the exact
// defect the scan exists to find.
//
// So this file carries stripComments(): it tracks string literals in order to
// skip OVER them intact, and blanks only comments. Comments cannot lie to it,
// and string literals survive to be read. That is the correct tool for
// detecting content references, and it is the generalisation of the iteration
// 9 lesson rather than a contradiction of it.

const fs = require("fs");
const path = require("path");

const GAME = path.resolve(__dirname, "..");
const SRC = path.join(GAME, "code");
const REPO = path.resolve(GAME, "..");

const STRINGS = path.join(SRC, "ReplicatedStorage", "Tidekeeper", "Client", "Strings.luau");
const LEDGER = path.join(SRC, "ReplicatedStorage", "Tidekeeper", "Domain", "Ledger.luau");

// --- allowlist -------------------------------------------------------------
//
// Verified in BOTH directions, like every other allowlist in this project
// (D44): an entry that stops being dead fails the scan too, so the list
// cannot rot into a collection of excuses.
//
// Keep this list short and keep the reasons real. A label parked here is a
// sentence a player cannot read.
const ALLOWED_DEAD = [
	// (empty -- iteration 10 wired or deleted all 18 it found)
];

function stripComments(code) {
	// Blanks comments, preserves string literals. Newlines are kept so that
	// line numbers survive. See the header for why this is not strip().
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
			// Copy the literal through verbatim, so that a "--" inside it
			// cannot be mistaken for a comment.
			const quote = ch;
			out += ch;
			i++;
			while (i < code.length && code[i] !== quote) {
				if (code[i] === "\\") {
					out += code[i];
					i++;
					if (i < code.length) out += code[i];
					i++;
					continue;
				}
				out += code[i];
				i++;
			}
			if (i < code.length) out += code[i];
			continue;
		}
		const long = /^\[(=*)\[/.exec(code.slice(i));
		if (long) {
			const close = "]" + long[1] + "]";
			const end = code.indexOf(close, i);
			const stop = end === -1 ? code.length : end + close.length;
			out += code.slice(i, stop);
			i = stop - 1;
			continue;
		}
		out += ch;
	}
	return out;
}

function walk(dir, out) {
	if (!fs.existsSync(dir)) return out;
	for (const name of fs.readdirSync(dir)) {
		const p = path.join(dir, name);
		const st = fs.statSync(p);
		if (st.isDirectory()) walk(p, out);
		else if (name.endsWith(".luau")) out.push(p);
	}
	return out;
}

// Extract the body of `Strings.UI = { ... }` by brace matching, so that a
// later table in the same file cannot leak keys into the set.
function tableBody(text, marker) {
	const at = text.indexOf(marker);
	if (at === -1) return null;
	let i = text.indexOf("{", at);
	if (i === -1) return null;
	let depth = 0;
	const start = i;
	for (; i < text.length; i++) {
		if (text[i] === "{") depth++;
		else if (text[i] === "}") {
			depth--;
			if (depth === 0) return text.slice(start + 1, i);
		}
	}
	return null;
}

function main() {
	const stringsRaw = fs.readFileSync(STRINGS, "utf8");
	const stringsCode = stripComments(stringsRaw);

	const uiBody = tableBody(stringsCode, "Strings.UI");
	if (uiBody === null) {
		console.log("FAIL could not locate Strings.UI");
		return 1;
	}
	// Only top-level keys of the UI table: `\tKEY = "..."`.
	const uiKeys = [];
	for (const m of uiBody.matchAll(/^\t(\w+)\s*=\s*"/gm)) uiKeys.push(m[1]);

	// Ledger prose rows live in Strings.LEDGER, keyed by template id.
	const ledgerBody = tableBody(stringsCode, "Strings.LEDGER");
	const proseIds = new Set();
	if (ledgerBody !== null) {
		for (const m of ledgerBody.matchAll(/^\t\[(\d+)\]\s*=\s*\{/gm)) proseIds.add(Number(m[1]));
	}

	// Ledger template constants.
	const ledgerCode = stripComments(fs.readFileSync(LEDGER, "utf8"));
	const templates = new Map();
	for (const m of ledgerCode.matchAll(/Ledger\.(T_\w+)\s*=\s*(\d+)/g)) {
		templates.set(m[1], Number(m[2]));
	}

	// Every .luau file except Strings.luau itself is a potential display site.
	const files = walk(SRC, []).filter((p) => p !== STRINGS);
	const used = new Set();
	const labelled = new Map(); // key -> first file that names it
	for (const p of files) {
		const code = stripComments(fs.readFileSync(p, "utf8"));
		for (const m of code.matchAll(/Format\.label\(\s*"(\w+)"/g)) {
			used.add(m[1]);
			if (!labelled.has(m[1])) labelled.set(m[1], p);
		}
		for (const m of code.matchAll(/Strings\.UI\.(\w+)/g)) {
			used.add(m[1]);
			if (!labelled.has(m[1])) labelled.set(m[1], p);
		}
		for (const m of code.matchAll(/Strings\.UI\[\s*"(\w+)"\s*\]/g)) {
			used.add(m[1]);
			if (!labelled.has(m[1])) labelled.set(m[1], p);
		}
		// A label can also be named INDIRECTLY, and legitimately so:
		// ClientBootstrap maps status codes to label names through a table,
		//   [NetContract.E_REJECTED] = "ERR_REJECTED",
		// which is better code than a chain of ifs around Format.label.
		// Counting only the direct Format.label("...") form reported four
		// such labels as dead the moment that table was introduced.
		//
		// So: any string literal equal to a key counts as naming it. The
		// keys are SHOUTY_SNAKE_CASE and unique, so a literal that happens
		// to equal one and is not meant as a reference is not a realistic
		// accident -- and comments are already blanked, which is where the
		// realistic false positives would otherwise come from.
		for (const m of code.matchAll(/"([A-Z][A-Z0-9_]{2,})"/g)) used.add(m[1]);
	}

	const allowed = new Map(ALLOWED_DEAD.map((r) => [r[0], r[1]]));
	const failures = [];
	const keySet = new Set(uiKeys);

	// 1. a label nothing displays
	let allowedHit = 0;
	for (const k of uiKeys) {
		if (used.has(k)) {
			if (allowed.has(k)) {
				failures.push(
					`Strings.UI.${k}  — on the allowlist but IS displayed now; remove the entry`
				);
			}
			continue;
		}
		if (allowed.has(k)) {
			allowedHit++;
			continue;
		}
		failures.push(`Strings.UI.${k}  — defined, never displayed; no player can ever read it`);
	}

	// 2. a label that does not exist (Format.label returns "" silently)
	for (const [k, where] of labelled) {
		if (!keySet.has(k)) {
			failures.push(
				`Format.label("${k}")  — no such key in Strings.UI; renders as an EMPTY label (${path.relative(REPO, where)})`
			);
		}
	}

	// 3/4. Ledger templates and their prose, both directions
	for (const [name, id] of templates) {
		if (!proseIds.has(id)) {
			failures.push(`Ledger.${name} (${id})  — no prose row in Strings.LEDGER; renders blank`);
		}
	}
	const templateIds = new Set(templates.values());
	for (const id of proseIds) {
		if (!templateIds.has(id)) {
			failures.push(`Strings.LEDGER[${id}]  — prose with no template constant; unreachable`);
		}
	}

	console.log(
		`TIDEKEEPER dead content scan — ${uiKeys.length} UI label(s), ` +
			`${templates.size} Ledger template(s), ${proseIds.size} prose row(s), ` +
			`${files.length} source file(s)`
	);
	console.log("");

	if (failures.length === 0) {
		const tail = allowedHit > 0 ? `, ${allowedHit} allowlisted` : "";
		console.log(
			`clean — every piece of player-facing content is reachable ` +
				`(${uiKeys.length + templates.size + proseIds.size} checked${tail})`
		);
		return 0;
	}
	for (const f of failures) console.log(`FAIL ${f}`);
	console.log("");
	console.log(
		`${failures.length} unreachable piece(s) of content. Content a player cannot ` +
			`see is not content.`
	);
	return 1;
}

process.exit(main());
