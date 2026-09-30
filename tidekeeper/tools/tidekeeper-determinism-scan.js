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
 *   Config/ Lib/ Shared/ Domain/   os.time, os.clock, os.date, tick(),
 *   ("the pure core")              DateTime, GetServerTimeNow, game:GetService,
 *                                  Instance.new, workspace, task.*, wait(),
 *                                  coroutine.*, spawn(), delay()
 *   Domain/                        bare pairs() / next() iteration — iteration
 *                                  order over a hash part is unspecified, and
 *                                  the simulation iterates stock and rules
 *   everywhere in code/            math.random (one unseedable global stream)
 *   everywhere in code/            TextBox / TextService / FilterStringAsync —
 *                                  TIDEKEEPER has no free text ANYWHERE
 *                                  (docs/13 §2), and the cheapest way to keep
 *                                  that true is to make it unrepresentable
 *   outside Adapters/              DataStoreService, MemoryStoreService,
 *                                  HttpService, MessagingService — every
 *                                  platform call goes through one adapter so
 *                                  the session harness can substitute a fake
 *   outside CadenceService         RunService — there is exactly one Heartbeat
 *                                  connection in this game (docs/01 §5)
 *   outside Adapters/ +            task.*, wait(), delay(), spawn() — yields
 *   CadenceService                 belong to I/O and to the scheduler, nowhere
 *                                  else
 *   everywhere in code/            a require that points at a HIGHER layer
 *                                  (Config < Lib < Shared < Domain < Adapters
 *                                  < Services < Client)
 *
 * The pure-core rules were global in iteration 2, when Config/Lib/Shared/Domain
 * were the only directories that existed. Scoping them to those four is not a
 * weakening: the behaviour on every file that existed then is byte-identical,
 * and the surface they used to cover is now covered by the three narrower,
 * STRICTER rules above (platform, runservice, scheduler-scope), which name the
 * one file each thing is allowed in rather than the layer.
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

// The pure core. These four directories are the simulation; nothing in them
// may read a clock, touch the engine, or yield.
const PURE = ["Config", "Lib", "Shared", "Domain"];

// `scope`  — directory names under the Tidekeeper tree the rule applies to;
//            null means every file.
// `except` — module basenames (no extension) the rule does not apply to; this
//            is how "exactly one file may do X" is expressed.
// `exceptDirs` — directory names the rule does not apply to.
const RULES = [
	{
		id: "math.random",
		scope: null,
		pattern: /\bmath\.random(?:seed)?\s*\(/,
		why: "math.random shares one unseedable global stream with every other script in the place. Use Lib/RNG.",
	},
	{
		id: "clock",
		scope: PURE,
		pattern: /\b(?:os\.time|os\.clock|os\.date|tick)\s*\(/,
		why: "a pure module may not read the clock. Time enters the simulation only as the `now` argument to Resolve.run; services and adapters take a clock by injection so the harness can virtualise it.",
	},
	{
		id: "datetime",
		scope: PURE,
		pattern: /\bDateTime\b|\bGetServerTimeNow\b/,
		why: "a pure module may not read the clock. Time enters the simulation only as the `now` argument to Resolve.run.",
	},
	{
		id: "services",
		scope: PURE,
		pattern: /\bgame\s*[:.]\s*GetService\b|\bInstance\.new\b|\bworkspace\b|\bgame\.Workspace\b/,
		why: "layers L0-L2 are pure. Roblox surface belongs in the adapter layer (L1) and the services layer (L3).",
	},
	{
		id: "scheduler",
		scope: PURE,
		pattern: /\btask\.(?:wait|spawn|delay|defer|synchronize|desynchronize)\s*\(|(?:^|[^.\w])wait\s*\(|(?:^|[^.\w])delay\s*\(|(?:^|[^.\w])spawn\s*\(/,
		why: "a pure module may not yield or schedule. Yields make the simulation depend on frame timing.",
	},
	{
		id: "coroutine",
		scope: PURE,
		pattern: /\bcoroutine\.(?:create|resume|wrap|yield)\b/,
		why: "a pure module may not yield.",
	},
	{
		id: "unordered-iteration",
		scope: ["Domain"],
		pattern: /\bin\s+(?:pairs|next)\s*\(|\bfor\s+\w+(?:\s*,\s*\w+)?\s+in\s+next\b/,
		why: "hash-part iteration order is unspecified. Use a numeric for, ipairs, or Tables.sortedPairs.",
	},
	{
		id: "platform",
		scope: null,
		strings: true,
		exceptDirs: ["Adapters"],
		pattern: /\bDataStoreService\b|\bMemoryStoreService\b|\bHttpService\b|\bMessagingService\b/,
		why: "every platform request goes through an adapter under Adapters/. That is what lets tools/tests/fake-platform.lua substitute a fake DataModel and measure requests per session against the real service code.",
	},
	{
		id: "runservice",
		scope: null,
		strings: true,
		except: ["CadenceService"],
		pattern: /\bRunService\b/,
		why: "there is exactly ONE RunService connection in this game and CadenceService owns it (docs/01 §5). A second connection means server time no longer belongs to a named slot with a declared budget.",
	},
	{
		id: "scheduler-scope",
		scope: null,
		exceptDirs: ["Adapters"],
		except: ["CadenceService"],
		pattern: /\btask\.(?:wait|spawn|delay|defer)\s*\(|(?:^|[^.\w])wait\s*\(|(?:^|[^.\w])delay\s*\(|(?:^|[^.\w])spawn\s*\(/,
		why: "yielding belongs to I/O (Adapters/) and to the scheduler (CadenceService). A task.spawn anywhere else is work that no slot budgets for and no profiler attributes.",
	},
	{
		id: "no-free-text",
		scope: null,
		strings: true,
		pattern: /\bTextBox\b|\bTextService\b|\bFilterStringAsync\b|\bTextChatService\b|\bFilterForBroadcast\b/,
		why: "TIDEKEEPER has no free text anywhere (docs/13 §2). Players exchange authored phrase ids, so there is no text to filter, nothing to moderate, and no hot path that calls a filtering API.",
	},
];

// Layer ordering. A module may require from its own layer or any layer to the
// left of it, never to the right.
const LAYER_ORDER = ["Config", "Lib", "Shared", "Domain", "Adapters", "Services", "Client"];

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

// Strip ONLY the trailing comment, keeping string literals intact. Rules that
// name a Roblox service have to see inside strings, because the way you ask
// for a service is `game:GetService("DataStoreService")` — blanking the string
// would make the single most important rule in this file unenforceable.
function blankCommentsOnly(line) {
	let i = 0;
	while (i < line.length) {
		const c = line[i];
		if (c === "-" && line[i + 1] === "-") return line.slice(0, i) + " ".repeat(line.length - i);
		if (c === '"' || c === "'") {
			const quote = c;
			i += 1;
			while (i < line.length) {
				if (line[i] === "\\") {
					i += 2;
					continue;
				}
				if (line[i] === quote) {
					i += 1;
					break;
				}
				i += 1;
			}
			continue;
		}
		i += 1;
	}
	return line;
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
	const segments = relPath.split("/");
	const baseName = path.basename(file).replace(/\.(server|client)?\.?luau?$/, "").replace(/\.luau?$/, "");
	const raw = fs.readFileSync(file, "utf8");
	const lines = raw.split("\n");
	scanned += 1;
	linesScanned += lines.length;

	for (let i = 0; i < lines.length; i += 1) {
		const code = blankNonCode(lines[i]);
		const codeWithStrings = blankCommentsOnly(lines[i]);
		if (!code.trim()) continue;
		const previous = i > 0 ? lines[i - 1] : "";
		const allowMatch = /--\s*determinism-scan:\s*allow\s+(\S+)\s*(.*)$/.exec(previous);

		for (const rule of RULES) {
			if (rule.scope && (!layer || !rule.scope.includes(layer))) continue;
			if (rule.except && rule.except.includes(baseName)) continue;
			if (rule.exceptDirs && rule.exceptDirs.some((d) => segments.includes(d))) continue;
			if (!rule.pattern.test(rule.strings ? codeWithStrings : code)) continue;
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
		const req = /require\s*\(\s*[A-Za-z_][\w.]*?\.(\w+)\.(\w+)\s*\)/.exec(code);
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
					why: `${layer} may not require ${targetLayer}: the dependency arrow points the wrong way (Config < Lib < Shared < Domain < Adapters < Services < Client).`,
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
