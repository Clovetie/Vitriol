#!/usr/bin/env node
"use strict";

/**
 * TIDEKEEPER design-document gate.
 *
 * Iteration 1's deliverable is documentation, so it gets a real, failing-capable
 * check rather than a claim. This verifies:
 *
 *   1. every required document exists and is non-trivial;
 *   2. every relative Markdown link inside tidekeeper/ resolves to a real file;
 *   3. the tide constants in 02-TIDE-AND-TIME.md are internally consistent with the
 *      derived values the rest of the design depends on (epoch length, spring/neap
 *      range and period, the EPOCH test vector);
 *   4. the storage budget arithmetic in 03/05 holds;
 *   5. every iteration prompt in 12-ITERATION-PROMPTS.md is present and carries the
 *      separation rule and the branch rule;
 *   6. no document references the sibling VITRIOL tree as a dependency.
 *
 * It is a consistency checker, not a proof that the design is good.
 *
 * Usage:  node tidekeeper/tools/tidekeeper-doc-gate.js [--json path]
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const DOCS = path.join(ROOT, "docs");

const REQUIRED_DOCS = [
	["00-VISION.md", 4000],
	["01-ARCHITECTURE.md", 4000],
	["02-TIDE-AND-TIME.md", 4000],
	["03-ASYNC-SOCIAL.md", 5000],
	["04-SIMULATION-MODEL.md", 5000],
	["05-PERSISTENCE.md", 4000],
	["06-ECONOMY-PROGRESSION.md", 4000],
	["07-WORLD-AND-CONTENT.md", 3000],
	["08-CLIENT-UX-MOBILE.md", 3000],
	["09-AI-BUILD-PIPELINE.md", 4000],
	["10-RESEARCH-NOTES.md", 5000],
	["11-HUMAN-AUTHORED.md", 2500],
	["12-ITERATION-PROMPTS.md", 5000],
	["13-RISKS-AND-COMPLIANCE.md", 4000],
];

const REQUIRED_ROOT_FILES = ["README.md", "ROADMAP.md", "HANDOFF.md"];

const failures = [];
const notes = [];
let checks = 0;

function check(name, ok, detail) {
	checks += 1;
	if (!ok) failures.push(`${name}: ${detail}`);
}

function read(file) {
	return fs.readFileSync(file, "utf8");
}

// ---------------------------------------------------------------- 1. presence
for (const [name, minBytes] of REQUIRED_DOCS) {
	const p = path.join(DOCS, name);
	const exists = fs.existsSync(p);
	check(`doc/${name}`, exists, "missing");
	if (!exists) continue;
	const size = fs.statSync(p).size;
	check(`doc/${name} size`, size >= minBytes, `${size} bytes < ${minBytes} required`);
	const first = read(p).split("\n")[0] || "";
	check(`doc/${name} title`, /^#\s+\S/.test(first), `first line is not an H1: ${JSON.stringify(first.slice(0, 60))}`);
}

for (const name of REQUIRED_ROOT_FILES) {
	check(`root/${name}`, fs.existsSync(path.join(ROOT, name)), "missing");
}

// ------------------------------------------------------------------ 2. links
function collectMarkdown(dir, out = []) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		if (entry.name === "node_modules" || entry.name === "reports") continue;
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) collectMarkdown(full, out);
		else if (entry.name.endsWith(".md")) out.push(full);
	}
	return out;
}

const LINK_RE = /\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
let linkCount = 0;
for (const file of collectMarkdown(ROOT)) {
	const text = read(file);
	let m;
	while ((m = LINK_RE.exec(text)) !== null) {
		const target = m[1];
		if (/^(https?:|mailto:|#)/.test(target)) continue;
		linkCount += 1;
		const [rel] = target.split("#");
		if (!rel) continue;
		const resolved = path.resolve(path.dirname(file), rel);
		check(
			`link ${path.relative(ROOT, file)} -> ${target}`,
			fs.existsSync(resolved),
			"target does not exist"
		);
	}
}
notes.push(`checked ${linkCount} relative Markdown links`);

// --------------------------------------------------------- 3. tide arithmetic
const tidePath = path.join(DOCS, "02-TIDE-AND-TIME.md");
if (fs.existsSync(tidePath)) {
	const tide = read(tidePath);

	function constant(symbol) {
		// matches a markdown table row:  | `T_M2` | `44714` s | ...
		const re = new RegExp("\\|\\s*`" + symbol.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "`\\s*\\|\\s*`([-0-9.]+)`");
		const m = tide.match(re);
		return m ? Number(m[1]) : null;
	}

	const T_M2 = constant("T_M2");
	const T_S2 = constant("T_S2");
	const T_K1 = constant("T_K1");
	const A_M2 = constant("A_M2");
	const A_S2 = constant("A_S2");
	const A_K1 = constant("A_K1");
	const Z0 = constant("Z0");
	const EPOCH = constant("EPOCH");

	for (const [sym, val] of Object.entries({ T_M2, T_S2, T_K1, A_M2, A_S2, A_K1, Z0, EPOCH })) {
		check(`tide constant ${sym}`, typeof val === "number" && Number.isFinite(val), "not parseable from the constants table");
	}

	if ([T_M2, T_S2, A_M2, A_S2, A_K1, Z0, EPOCH].every((v) => typeof v === "number")) {
		// epoch length must be exactly half an M2 period, and must be quoted as such
		const epochSeconds = Math.floor(T_M2 / 2);
		check(
			"tide epoch length",
			tide.includes(String(epochSeconds)),
			`T_M2/2 = ${epochSeconds} is never stated in the document`
		);

		// spring / neap ranges
		const spring = 2 * (A_M2 + A_S2);
		const neap = 2 * (A_M2 - A_S2);
		check("spring range stated", tide.includes(spring.toFixed(1)), `expected ${spring.toFixed(1)} studs`);
		check("neap range stated", tide.includes(neap.toFixed(1)), `expected ${neap.toFixed(1)} studs`);

		// spring/neap beat period
		const beat = 1 / Math.abs(1 / T_M2 - 1 / T_S2);
		const beatDays = beat / 86400;
		check(
			"spring/neap period",
			Math.abs(beatDays - 14.765) < 0.02,
			`computed ${beatDays.toFixed(3)} d from the stated periods, document claims 14.765 d`
		);

		// the headline test vector
		const atEpoch = A_M2 + A_S2 + A_K1 + Z0;
		check(
			"TideHeight(EPOCH) test vector",
			tide.includes(atEpoch.toFixed(1)),
			`constants give ${atEpoch.toFixed(1)}, which is not stated as the EPOCH test vector`
		);

		// EPOCH must be a plausible 2026-01-01 UTC timestamp
		const iso = new Date(EPOCH * 1000).toISOString();
		check("EPOCH timestamp", iso.startsWith("2026-01-01T00:00:00"), `EPOCH resolves to ${iso}`);

		// 27 epochs must be >= 7 days (the documented catch-up cap)
		const capDays = (27 * epochSeconds) / 86400;
		check("27-epoch cap covers 7 days", capDays >= 6.9, `27 epochs = ${capDays.toFixed(2)} days`);
		notes.push(`tide: epoch=${epochSeconds}s, spring=${spring.toFixed(1)}, neap=${neap.toFixed(1)}, beat=${beatDays.toFixed(3)}d, cap=${capDays.toFixed(2)}d`);

		// ------------------------------------------------- 3b. measured vectors
		//
		// Added in iteration 2, after three of §8's twelve test vectors turned out
		// to be reasoned-about rather than computed. This block RE-DERIVES them in
		// JavaScript straight from the §2.2 constants and asserts the document
		// states the answer. A doc gate that only checks internal consistency
		// would have passed all three wrong rows; this one would not have.
		const TWO_PI = Math.PI * 2;
		const heightAt = (t) => {
			const s = t - EPOCH;
			return (
				Z0 +
				A_M2 * Math.cos((TWO_PI * s) / T_M2) +
				A_S2 * Math.cos((TWO_PI * s) / T_S2) +
				A_K1 * Math.cos((TWO_PI * s) / T_K1)
			);
		};
		const velocityAt = (t) => {
			const s = t - EPOCH;
			return (
				(-A_M2 * TWO_PI * Math.sin((TWO_PI * s) / T_M2)) / T_M2 +
				(-A_S2 * TWO_PI * Math.sin((TWO_PI * s) / T_S2)) / T_S2 +
				(-A_K1 * TWO_PI * Math.sin((TWO_PI * s) / T_K1)) / T_K1
			);
		};
		const stateAt = (t) => {
			const h = heightAt(t);
			if (h < -6) return "LOW";
			if (h > 8) return "HIGH";
			if (h >= 2) return "SLACK";
			return velocityAt(t) < 0 ? "EBB" : "FLOOD";
		};

		const afterOneM2 = heightAt(EPOCH + T_M2);
		check(
			"TideHeight(EPOCH + T_M2) vector matches the constants",
			tide.includes(afterOneM2.toPrecision(17).replace(/0+$/, "")) || tide.includes(String(afterOneM2)),
			`constants give ${afterOneM2}, which the document does not state`
		);

		let lowEntries = 0;
		let wasLow = false;
		let dayLo = Infinity;
		let dayHi = -Infinity;
		let rangeMax = -Infinity;
		let rangeMin = Infinity;
		for (let step = 0; step < 86400; step += 1) {
			const t = EPOCH + step * 60;
			const h = heightAt(t);
			if (step < 43200) {
				const isLow = stateAt(t) === "LOW";
				if (isLow && !wasLow) lowEntries += 1;
				wasLow = isLow;
			}
			if (h < dayLo) dayLo = h;
			if (h > dayHi) dayHi = h;
			if ((step + 1) % 1440 === 0) {
				const range = dayHi - dayLo;
				if (range > rangeMax) rangeMax = range;
				if (range < rangeMin) rangeMin = range;
				dayLo = Infinity;
				dayHi = -Infinity;
			}
		}
		check(
			"LOW-entry count vector matches the constants",
			tide.includes(`**${lowEntries}**`),
			`constants give ${lowEntries} LOW entries over 30 days, which the document does not state`
		);
		check(
			"spring daily-range vector matches the constants",
			tide.includes(rangeMax.toFixed(2)),
			`constants give a ${rangeMax.toFixed(2)} stud spring range, which the document does not state`
		);
		check(
			"neap daily-range vector matches the constants",
			tide.includes(rangeMin.toFixed(2)),
			`constants give a ${rangeMin.toFixed(2)} stud neap range, which the document does not state`
		);
		notes.push(
			`tide measured: +T_M2 height=${afterOneM2.toFixed(6)}, LOW entries/30d=${lowEntries}, daily range ${rangeMin.toFixed(2)}..${rangeMax.toFixed(2)}`
		);
	}
}

// ------------------------------------------------------- 4. storage arithmetic
const asyncPath = path.join(DOCS, "03-ASYNC-SOCIAL.md");
const persistPath = path.join(DOCS, "05-PERSISTENCE.md");
if (fs.existsSync(asyncPath) && fs.existsSync(persistPath)) {
	const a = read(asyncPath);
	const p = read(persistPath);

	// The Drifter byte budget must agree across the two documents.
	check("drifter size stated in 03", /68\s*bytes/i.test(a), "03 does not state the 68-byte Drifter size");
	const layout = p.match(/offset size field[\s\S]*?reserved\s+must be 0/);
	check("drifter layout present in 05", Boolean(layout), "05 §4 byte layout table is missing");
	if (layout) {
		// last declared field must end at byte 68
		const rows = layout[0].split("\n").map((l) => l.trim().match(/^(\d+)\s+(\d+)\s+(\S+)/)).filter(Boolean);
		check("drifter layout non-empty", rows.length >= 10, `only ${rows.length} fields parsed`);
		if (rows.length) {
			const last = rows[rows.length - 1];
			const end = Number(last[1]) + Number(last[2]);
			check("drifter layout totals 68 bytes", end === 68, `fields end at byte ${end}`);
			// offsets must be contiguous
			let cursor = 0;
			let contiguous = true;
			for (const r of rows) {
				if (Number(r[1]) !== cursor) { contiguous = false; break; }
				cursor += Number(r[2]);
			}
			check("drifter layout contiguous", contiguous, "offsets are not contiguous from 0");
		}
	}

	// 200 drifters * 68 B must match the stated warm shard size
	const shard = (200 * 68) / 1024;
	check(
		"warm shard size",
		p.includes(shard.toFixed(1)),
		`200 x 68 B = ${shard.toFixed(1)} KB, which is not the stated shard budget`
	);

	// MemoryStore quota formula must be quoted verbatim in both places it is used
	check("MemoryStore formula in 03", /64\s*KB\s*\+\s*1\.2\s*KB/.test(a), "03 does not quote the MemoryStore quota formula");
	check("MemoryStore formula in 05", /64\s*KB\s*\+\s*1\.2\s*KB/.test(p), "05 does not quote the MemoryStore quota formula");
}

// ------------------------------------------------------------- 5. the prompts
const promptPath = path.join(DOCS, "12-ITERATION-PROMPTS.md");
if (fs.existsSync(promptPath)) {
	const text = read(promptPath);
	for (const n of [2, 3, 4, 5]) {
		check(`prompt for iteration ${n}`, text.includes(`Iteration ${n}:`), "not present");
	}
	check("prompt for iteration 6+", /Iteration 6\+/.test(text), "not present");
	check("handoff template", text.includes("Handoff — TIDEKEEPER, iteration N"), "not present");

	const blocks = text.split("```").filter((_, i) => i % 2 === 1);
	const prompts = blocks.filter((b) => /You are iteration/.test(b));
	check("prompt blocks fenced", prompts.length >= 5, `found ${prompts.length} fenced prompt blocks, expected >= 5`);
	for (const [i, b] of prompts.entries()) {
		check(`prompt ${i} states branch rule`, /branch/i.test(b), "no branch instruction");
		check(`prompt ${i} states separation`, /VITRIOL|tidekeeper\//.test(b), "no separation instruction");
	}
	notes.push(`checked ${prompts.length} iteration prompts`);
}

// --------------------------------------------- 6. no dependency on the sibling
for (const file of collectMarkdown(DOCS)) {
	const text = read(file);
	const bad = text.match(/\]\(\.\.\/\.\.\/(code|tools|docs)\//g);
	check(
		`no sibling dependency in ${path.basename(file)}`,
		!bad,
		`links into the VITRIOL tree: ${bad ? bad.join(", ") : ""}`
	);
}

// -------------------------------------------------------------------- report
const argv = process.argv.slice(2);
const jsonIdx = argv.indexOf("--json");
const result = {
	checks,
	failures,
	notes,
	passed: failures.length === 0,
	generatedAt: new Date().toISOString(),
};
if (jsonIdx !== -1 && argv[jsonIdx + 1]) {
	const out = path.resolve(process.cwd(), argv[jsonIdx + 1]);
	fs.mkdirSync(path.dirname(out), { recursive: true });
	fs.writeFileSync(out, JSON.stringify(result, null, 2));
}

for (const n of notes) console.log(`note: ${n}`);
for (const f of failures) console.error(`FAIL ${f}`);
console.log(
	`TIDEKEEPER doc gate: ${checks - failures.length}/${checks} checks passed` +
		(failures.length ? ` (${failures.length} failed)` : "")
);
process.exit(failures.length ? 1 : 0);
