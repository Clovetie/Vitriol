#!/usr/bin/env node
"use strict";

/**
 * TIDEKEEPER quality gate — one deterministic pre-commit/CI command.
 *
 * It orchestrates this folder's tools rather than replacing them, and it degrades
 * honestly across iterations:
 *
 *   iteration 1  code/ is empty  -> runs the doc gate; source checks report "skipped
 *                                   (no source)"; the gate passes.
 *   iteration 2+ code/ has Luau  -> syntax, metrics, hot-loop, call-graph,
 *                                   dead-config and the determinism scan run, and
 *                                   the smoke test is REQUIRED to exist and pass.
 *   iteration 3+ session harness -> also required once it exists.
 *
 * It never invents a pass. A tool that is missing when it is required is a failure,
 * not a skip.
 *
 * Usage:
 *   node tidekeeper/tools/tidekeeper-quality-gate.js
 *   node tidekeeper/tools/tidekeeper-quality-gate.js --src tidekeeper/code \
 *        --report tidekeeper/tools/reports/gate.json
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const TOOLS = __dirname;
const GAME = path.resolve(TOOLS, "..");
const REPO = path.resolve(GAME, "..");
const NODE = process.execPath;
const MAX_CAPTURE = 200000;

/**
 * The ratchet. Each iteration bumps this by one, which is what turns that
 * iteration's harness from "pending" into "required". It is a hand-edited
 * constant on purpose: a gate that infers how far along the project is will
 * eventually infer wrongly and let a missing harness through.
 */
const CURRENT_ITERATION = 4;

function die(message) {
	console.error(`tidekeeper-quality-gate: ${message}`);
	process.exit(2);
}

function parseArgs(argv) {
	const out = { src: path.join(GAME, "code"), report: null, quiet: false, iteration: CURRENT_ITERATION };
	for (let i = 2; i < argv.length; i += 1) {
		const arg = argv[i];
		if (arg === "--src") out.src = path.resolve(process.cwd(), argv[++i]);
		else if (arg === "--report") out.report = path.resolve(process.cwd(), argv[++i]);
		else if (arg === "--quiet") out.quiet = true;
		else if (arg === "--iteration") out.iteration = Number(argv[++i]);
		else if (arg === "--help") {
			console.log(
				"Usage: node tidekeeper/tools/tidekeeper-quality-gate.js [--src tidekeeper/code] [--report path] [--iteration N] [--quiet]"
			);
			process.exit(0);
		} else die(`unknown argument ${arg}`);
	}
	return out;
}

const args = parseArgs(process.argv);
const rel = (p) => path.relative(REPO, p).replace(/\\/g, "/");

/** Count .luau/.lua files under the source root. */
function countSource(root) {
	if (!fs.existsSync(root)) return 0;
	let n = 0;
	const walk = (dir) => {
		for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
			const full = path.join(dir, e.name);
			if (e.isDirectory()) walk(full);
			else if (/\.luau?$/.test(e.name)) n += 1;
		}
	};
	walk(root);
	return n;
}

const sourceCount = countSource(args.src);
const hasSource = sourceCount > 0;

function clip(s) {
	if (s.length <= MAX_CAPTURE) return s;
	return `${s.slice(0, MAX_CAPTURE)}\n...[truncated ${s.length - MAX_CAPTURE} bytes]`;
}

const results = [];

function run(name, scriptRelative, extraArgs, options) {
	const opts = options || {};
	const script = path.join(TOOLS, scriptRelative);
	const entry = { name, command: null, status: null, exitCode: null, stdout: "", stderr: "" };

	if (!fs.existsSync(script)) {
		if (opts.requiredFrom && hasSource && args.iteration >= opts.requiredFrom) {
			entry.status = "FAIL";
			entry.stderr = `${scriptRelative} does not exist, and it is required from iteration ${opts.requiredFrom} onward (this is iteration ${args.iteration}).`;
		} else {
			entry.status = "PENDING";
			entry.stderr = `${scriptRelative} not present yet (expected in iteration ${opts.requiredFrom || "?"}; this is iteration ${args.iteration}).`;
		}
		results.push(entry);
		return entry;
	}

	if (opts.needsSource && !hasSource) {
		entry.status = "SKIP";
		entry.stderr = "no Luau source under the source root yet";
		results.push(entry);
		return entry;
	}

	const argv = [script, ...extraArgs];
	entry.command = ["node", rel(script), ...extraArgs].join(" ");
	const r = spawnSync(NODE, argv, { cwd: REPO, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
	entry.exitCode = r.status;
	entry.stdout = clip(r.stdout || "");
	entry.stderr = clip(r.stderr || "");
	entry.status = r.status === 0 ? "PASS" : "FAIL";

	// A tool may exit 0 and still not have DONE anything -- the Luau bench
	// does exactly that when no `luau` binary is present, which is the right
	// behaviour (the gate should not go red on a machine that has not built
	// one) but the wrong REPORT. Rendered as a plain `ok` with whatever its
	// last stdout line happened to be, a skip is indistinguishable from a
	// pass, and "the check that measures performance quietly stopped
	// measuring performance" is precisely the kind of thing a gate exists to
	// make visible.
	// (Matched anywhere on the line, not line-initial: the bench prints
	// "TIDEKEEPER Luau bench: SKIPPED - ...". A first version of this anchored
	// at ^ and silently never fired, which is the same bug this block exists
	// to catch, one level up.)
	if (entry.status === "PASS" && /\bSKIPPED\b/.test(entry.stdout)) {
		entry.status = "SKIP";
		const line = (entry.stdout.match(/^.*\bSKIPPED\b.*$/m) || [""])[0];
		entry.stderr = line.trim() || "the tool reported SKIPPED";
	}

	results.push(entry);
	return entry;
}

// ---------------------------------------------------------------- the checks

// 1. Documents. Always enforcing — they are the project's source of truth.
run("doc-gate", "tidekeeper-doc-gate.js", []);

// 2. Separation from the sibling game. Always enforcing.
(function separation() {
	const entry = { name: "separation", command: "internal", status: "PASS", exitCode: 0, stdout: "", stderr: "" };
	const offenders = [];
	const walk = (dir) => {
		if (!fs.existsSync(dir)) return;
		for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
			if (e.name === "node_modules" || e.name === "reports" || e.name === ".git") continue;
			const full = path.join(dir, e.name);
			if (e.isDirectory()) { walk(full); continue; }
			if (!/\.(luau?|js|md|json)$/.test(e.name)) continue;
			const text = fs.readFileSync(full, "utf8");
			// A dependency on the sibling tree: a require/import/path reaching out of
			// tidekeeper/ into the VITRIOL code or tools trees.
			const bad = text.match(/(?:require|from|src|path)\s*[=:(]?\s*["'`][^"'`]*\.\.\/\.\.\/(?:code|tools)\//g);
			if (bad) offenders.push(`${rel(full)}: ${bad.join(", ")}`);
			if (/\bVitriol\b/.test(text) && !/sibling|VITRIOL tree|reference implementation|different game|Separation|do not import/i.test(text)) {
				offenders.push(`${rel(full)}: references Vitriol outside an explicit separation note`);
			}
		}
	};
	walk(GAME);
	if (offenders.length) {
		entry.status = "FAIL";
		entry.exitCode = 1;
		entry.stderr = offenders.join("\n");
	} else {
		entry.stdout = "no dependency on the VITRIOL tree";
	}
	results.push(entry);
})();

// 3. Source checks. Skip cleanly while code/ is empty.
run("check-syntax", "check-syntax.js", [rel(args.src)], { needsSource: true });
run("metrics", "metrics.js", ["--src", rel(args.src)], { needsSource: true });
run("hot-loop-scan", "hot-loop-scan.js", ["--src", rel(args.src)], { needsSource: true });
run("call-graph", "call-graph.js", ["--src", rel(args.src)], { needsSource: true });
run("find-dead-config", "find-dead-config.js", ["--src", rel(args.src)], { needsSource: true });
// Unlike the four scans above (which report and exit 0), this one exits
// non-zero on a hit, so it genuinely gates. Determinism is the product.
run("determinism-scan", "tidekeeper-determinism-scan.js", ["--src", rel(args.src)], { needsSource: true });

// 4. Harnesses. Pending until their iteration; required once source exists.
run("smoke-test", "tidekeeper-smoke-test.js", [], { requiredFrom: 2 });
run("session-test", "tidekeeper-session-test.js", [], { requiredFrom: 3 });
// Real-Luau benchmark. Required from iteration 4, when OD12 was settled.
// It exits 0 and prints SKIPPED when no `luau` binary is present, so the gate
// stays green on a machine that has not built one -- but it says so loudly
// rather than vanishing.
run("luau-bench", "tidekeeper-luau-bench.js", [], { requiredFrom: 4 });

// 5. Whitespace hygiene in the working tree.
(function diffCheck() {
	const r = spawnSync("git", ["diff", "--check"], { cwd: REPO, encoding: "utf8" });
	results.push({
		name: "git-diff-check",
		command: "git diff --check",
		status: r.status === 0 ? "PASS" : "FAIL",
		exitCode: r.status,
		stdout: clip(r.stdout || ""),
		stderr: clip(r.stderr || ""),
	});
})();

// ---------------------------------------------------------------- the report

const passed = results.filter((r) => r.status === "PASS").length;
const failed = results.filter((r) => r.status === "FAIL");
const skipped = results.filter((r) => r.status === "SKIP" || r.status === "PENDING");

if (!args.quiet) {
	console.log(`TIDEKEEPER quality gate — iteration ${args.iteration}, source root ${rel(args.src)} (${sourceCount} Luau file(s))\n`);
	for (const r of results) {
		const mark = { PASS: "  ok ", FAIL: "FAIL ", SKIP: "skip ", PENDING: "wait " }[r.status];
		// For a skip, show WHY it skipped. Taking the last stdout line gave
		// "Or point TIDEKEEPER_LUAU at an existing binary." -- a help string,
		// stripped of the fact that the benchmark did not run.
		const summarySource =
			r.status === "SKIP" || r.status === "PENDING"
				? r.stderr || r.stdout || ""
				: r.stdout || r.stderr || "";
		const first = summarySource.trim().split("\n").filter(Boolean).pop() || "";
		console.log(`${mark} ${r.name.padEnd(18)} ${first.slice(0, 96)}`);
	}
	if (failed.length) {
		console.log("");
		for (const r of failed) {
			console.log(`--- ${r.name} (${r.command || "internal"})`);
			if (r.stdout) console.log(r.stdout);
			if (r.stderr) console.error(r.stderr);
		}
	}
}

if (args.report) {
	fs.mkdirSync(path.dirname(args.report), { recursive: true });
	fs.writeFileSync(
		args.report,
		JSON.stringify(
			{ generatedAt: new Date().toISOString(), sourceRoot: rel(args.src), sourceCount, results },
			null,
			2
		)
	);
}

const total = results.length;
console.log(
	`\nTIDEKEEPER quality gate: ${passed}/${total} checks passed` +
		(skipped.length ? `, ${skipped.length} not applicable yet` : "") +
		(failed.length ? `, ${failed.length} FAILED` : "")
);
process.exit(failed.length ? 1 : 0);
