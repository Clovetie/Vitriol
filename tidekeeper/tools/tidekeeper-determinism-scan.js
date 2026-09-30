#!/usr/bin/env node
"use strict";

/**
 * tidekeeper-determinism-scan.js
 *
 * Static enforcement of the determinism rules in docs/04-SIMULATION-MODEL.md §5
 * and the layering rules in docs/01-ARCHITECTURE.md §7.
 *
 * The smoke test proves that TODAY's code is deterministic. This proves that
 * tomorrow's code cannot stop being deterministic by accident — the failure it
 * prevents is the worst kind this game can have: a player's offline replay
 * disagreeing with the server, silently, weeks after the commit that caused it.
 *
 * What it forbids, and where:
 *
 *   Lib/ Domain/ Shared/ Config/   math.random, os.time, os.clock, os.date,
 *                                  tick(), DateTime, GetServerTimeNow,
 *                                  game:GetService, Instance.new, workspace,
 *                                  task.*, wait(), coroutine.*, spawn(), delay()
 *   Domain/                        bare pairs() / next() iteration — iteration
 *                                  order over a hash part is unspecified, and
 *                                  the simulation iterates stock and rules
 *   everywhere in code/            a require that points at a HIGHER layer
 *                                  (Config < Lib < Shared < Domain < Services)
 *
 * Every rule has a `-- determinism-scan: allow <rule> <reason>` escape hatch on
 * the preceding line, because a rule with no escape hatch gets deleted the
 * first time it is inconvenient. Allowances are printed in the report so they
 * stay visible.
 *
 * Usage:
 *   node tidekeeper/tools/tidekeeper-determinism-scan.js
 *   node tidekeeper/tools/tidekeeper-determinism-scan.js --src tidekeeper/code
 *   node tidekeeper/tools/tidekeeper-determinism-scan.js --json out.json
 *
 * Exit 0 = clean, 1 = violations, 2 = bad invocation.
 */

const fs = require("fs");
const path = require("path");

const TOOLS = __dirname;
const GAME = path.resolve(TOOLS, "..");
const REPO = path.resolve(GAME, "..");

function die(message) {
	console.error(`tidekeeper-determinism-scan: ${message}`);
	process.exit(2);
}

function parseArgs(argv) {
	const out = { src: path.join(GAME, "code"), json: null, quiet: false };
	for (let i = 2; i < argv.length; i += 1) {
		const arg = argv[i];
		if (arg === "--src") out.src = path.resolve(process.cwd(), argv[++i]);
		else if (arg === "--json") out.json = path.resolve(process.cwd(), argv[++i]);
		else if (arg === "--quiet") out.quiet = true;
		else if (arg === "--help") {
			console.log("Usage: node tidekeeper/tools/tidekeeper-determinism-scan.js [--src tidekeeper/code] [--json path] [--quiet]");
			process.exit(0);
		} else die(`unknown argument ${arg}`);
	}
	return out;
}

const args = parseArgs(process.argv);
const rel = (p) => path.relative(REPO, p).replace(/\\/g, "/");

// --------------------------------------------------------------------- rules

// `scope` is a list of directory names under the Tidekeeper tree; null = all.
const RULES = [
	{
		id: "math.random",
		scope: null,
		pattern: /\bmath\.random(?:seed)?\s*\(/,
		why: "math.random shares one unseedable global stream with every other script in the place. Use Lib/RNG.",
	},
	{
		id: "clock",
		scope: null,
		pattern: /\b(?:os\.time|os\.clock|os\.date|tick)\s*\(/,
		why: "a pure module may not read the clock. Time enters the simulation only as the `now` argument to Resolve.run.",
	},
	{
		id: "datetime",
		scope: null,
		pattern: /\bDateTime\b|\bGetServerTimeNow\b/,
		why: "a pure module may not read the clock. Time enters the simulation only as the `now` argument to Resolve.run.",
	},
	{
		id: "services",
		scope: null,
		pattern: /\bgame\s*[:.]\s*GetService\b|\bInstance\.new\b|\bworkspace\b|\bgame\.Workspace\b/,
		why: "layers L0-L2 are pure. Roblox surface belongs in the adapter layer (L1) and the services layer (L3).",
	},
	{
		id: "scheduler",
		scope: null,
		pattern: /\btask\.(?:wait|spawn|delay|defer|synchronize|desynchronize)\s*\(|(?:^|[^.\w])wait\s*\(|(?:^|[^.\w])delay\s*\(|(?:^|[^.\w])spawn\s*\(/,
		why: "a pure module may not yield or schedule. Yields make the simulation depend on frame timing.",
	},
	{
		id: "coroutine",
		scope: null,
		pattern: /\bcoroutine\.(?:create|resume|wrap|yield)\b/,
		why: "a pure module may not yield.",
	},
	{
		id: "unordered-iteration",
		scope: ["Domain"],
		pattern: /\bin\s+(?:pairs|next)\s*\(|\bfor\s+\w+(?:\s*,\s*\w+)?\s+in\s+next\b/,
		why: "hash-part iteration order is unspecified. Use a numeric for, ipairs, or Tables.sortedPairs.",
	},
];

// Layer ordering. A module may require from its own layer or any layer to the
// left of it, never to the right.
const LAYER_ORDER = ["Config", "Lib", "Shared", "Domain", "Services", "Client"];

// ---------------------------------------------------------------- collection

function collect(root) {
	const files = [];
	if (!fs.existsSync(root)) return files;
	const walk = (dir) => {
		for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
			const full = path.join(dir, entry.name);
			if (entry.isDirectory()) walk(full);
			else if (/\.luau?$/.test(entry.name)) files.push(full);
		}
	};
	walk(root);
	return files;
}

function layerOf(file) {
	const parts = rel(file).split("/");
	for (let i = parts.length - 1; i >= 0; i -= 1) {
		if (LAYER_ORDER.includes(parts[i])) return parts[i];
	}
	return null;
}

// Strip string literals and comments so a rule name inside a doc comment or an
// error message is never a violation. Keeps line structure intact.
function blankNonCode(line) {
	let out = "";
	let i = 0;
	while (i < line.length) {
		const c = line[i];
		if (c === "-" && line[i + 1] === "-") {
			out += " ".repeat(line.length - i);
			break;
		}
		if (c === '"' || c === "'") {
			const quote = c;
			out += " ";
			i += 1;
			while (i < line.length) {
				if (line[i] === "\\") {
					out += "  ";
					i += 2;
					continue;
				}
				if (line[i] === quote) {
					out += " ";
					i += 1;
					break;
				}
				out += " ";
				i += 1;
			}
			continue;
		}
		out += c;
		i += 1;
	}
	return out;
}

// ------------------------------------------------------------------- the scan

const files = collect(args.src);
const violations = [];
const allowances = [];
let scanned = 0;
let linesScanned = 0;

for (const file of files) {
	const layer = layerOf(file);
	const relPath = rel(file);
	const raw = fs.readFileSync(file, "utf8");
	const lines = raw.split("\n");
	scanned += 1;
	linesScanned += lines.length;

	for (let i = 0; i < lines.length; i += 1) {
		const code = blankNonCode(lines[i]);
		if (!code.trim()) continue;
		const previous = i > 0 ? lines[i - 1] : "";
		const allowMatch = /--\s*determinism-scan:\s*allow\s+(\S+)\s*(.*)$/.exec(previous);

		for (const rule of RULES) {
			if (rule.scope && (!layer || !rule.scope.includes(layer))) continue;
			if (!rule.pattern.test(code)) continue;
			if (allowMatch && allowMatch[1] === rule.id) {
				allowances.push({ file: relPath, line: i + 1, rule: rule.id, reason: allowMatch[2].trim() || "(no reason given)" });
				continue;
			}
			violations.push({
				file: relPath,
				line: i + 1,
				rule: rule.id,
				text: lines[i].trim().slice(0, 120),
				why: rule.why,
			});
		}

		// Layering. `require(script.Parent.Parent.Lib.Codec)` -> the layer is the
		// second-to-last path segment.
		const req = /require\s*\(\s*script[.\w]*?\.(\w+)\.(\w+)\s*\)/.exec(code);
		if (req && layer) {
			const targetLayer = req[1];
			const here = LAYER_ORDER.indexOf(layer);
			const there = LAYER_ORDER.indexOf(targetLayer);
			if (here >= 0 && there >= 0 && there > here) {
				violations.push({
					file: relPath,
					line: i + 1,
					rule: "layering",
					text: lines[i].trim().slice(0, 120),
					why: `${layer} may not require ${targetLayer}: the dependency arrow points the wrong way (Config < Lib < Shared < Domain < Services < Client).`,
				});
			}
		}
	}
}

// ---------------------------------------------------------------- the report

const byRule = {};
for (const v of violations) byRule[v.rule] = (byRule[v.rule] || 0) + 1;

if (!args.quiet) {
	console.log(`TIDEKEEPER determinism scan — ${scanned} file(s), ${linesScanned} line(s) under ${rel(args.src)}\n`);
	if (files.length === 0) {
		console.log("  no Luau sources yet — nothing to scan");
	}
	for (const rule of RULES) {
		const n = byRule[rule.id] || 0;
		console.log(`${n === 0 ? "  ok " : "FAIL "} ${rule.id.padEnd(22)} ${n} violation(s)`);
	}
	const layeringCount = byRule.layering || 0;
	console.log(`${layeringCount === 0 ? "  ok " : "FAIL "} ${"layering".padEnd(22)} ${layeringCount} violation(s)`);

	if (allowances.length) {
		console.log("\nexplicit allowances:");
		for (const a of allowances) {
			console.log(`  ${a.file}:${a.line}  ${a.rule}  — ${a.reason}`);
		}
	}
	if (violations.length) {
		console.log("");
		for (const v of violations) {
			console.log(`${v.file}:${v.line}  [${v.rule}]  ${v.text}`);
			console.log(`    ${v.why}`);
		}
	}
	console.log(`\n${violations.length === 0 ? "clean" : `${violations.length} violation(s)`}`);
}

if (args.json) {
	fs.mkdirSync(path.dirname(args.json), { recursive: true });
	fs.writeFileSync(
		args.json,
		JSON.stringify({ generatedAt: new Date().toISOString(), src: rel(args.src), scanned, linesScanned, violations, allowances }, null, 2)
	);
}

process.exit(violations.length === 0 ? 0 : 1);
