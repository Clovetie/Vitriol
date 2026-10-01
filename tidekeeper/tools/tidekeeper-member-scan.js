#!/usr/bin/env node
/**
 * tidekeeper-member-scan.js — does every cross-module field actually exist?
 *
 * WHY THIS EXISTS
 *
 * `check-syntax` parses. The determinism scan checks shape. Neither executes
 * anything, and Luau has no compile-time member checking on a plain table. So
 * a module can reference `Other.FIELD` where `Other` has never had a `FIELD`,
 * and the whole toolchain stays green until something runs that line:
 *
 *   - `OrdersView` ended with `#Drifter.CLASS_NAMES`, a table that has never
 *     existed in any version of this project. It threw AT LOAD TIME, which in
 *     Studio takes the entire Orders screen with it. Found only in iteration
 *     5, by finally executing the module.
 *   - `GameConfig.MAX_SHELF_PRICE` was assumed while writing `PostView` and
 *     does not exist either.
 *
 * Both are the same bug: a name that reads plausibly, resolves to nil, and is
 * invisible to every static tool in the build. This closes that gap.
 *
 * WHAT IT DOES
 *
 * For each file, find the modules it requires and the local alias each was
 * bound to. Then for every `alias.Member` reference, check that `Member` is
 * assigned somewhere in that module. Assignment means any of:
 *
 *   function Mod.foo(...)      Mod.foo = ...      Mod.CONST = ...
 *   Mod = { foo = ..., ... }   (a returned table literal)
 *   Mod[k] = v                 (dynamic -- disables checking for that module)
 *
 * DELIBERATELY CONSERVATIVE. A module that writes any computed key, or that
 * is built by a loop, is skipped entirely rather than guessed at: a member
 * scan that cries wolf gets switched off, and then it protects nothing. It
 * is a tripwire for the obvious case, which is the case that keeps happening.
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const REPO = path.resolve(ROOT, "..");
const SRC = path.join(ROOT, "code");

// ---------------------------------------------------------------- utilities
function walk(dir, out) {
	out = out || [];
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, entry.name);
		if (entry.isDirectory()) walk(p, out);
		else if (entry.name.endsWith(".luau")) out.push(p);
	}
	return out;
}

// Blank out comments and string literals so neither can create a false
// reference ("see Foo.Bar" in prose) or hide a real one.
function strip(src) {
	let out = "";
	let i = 0;
	while (i < src.length) {
		const two = src.slice(i, i + 2);
		if (two === "--") {
			const longOpen = /^--\[(=*)\[/.exec(src.slice(i));
			if (longOpen) {
				const close = `]${longOpen[1]}]`;
				const end = src.indexOf(close, i);
				const stop = end === -1 ? src.length : end + close.length;
				for (let k = i; k < stop; k++) out += src[k] === "\n" ? "\n" : " ";
				i = stop;
				continue;
			}
			while (i < src.length && src[i] !== "\n") {
				out += " ";
				i += 1;
			}
			continue;
		}
		const longStr = /^\[(=*)\[/.exec(src.slice(i));
		if (longStr) {
			const close = `]${longStr[1]}]`;
			const end = src.indexOf(close, i);
			const stop = end === -1 ? src.length : end + close.length;
			for (let k = i; k < stop; k++) out += src[k] === "\n" ? "\n" : " ";
			i = stop;
			continue;
		}
		const c = src[i];
		if (c === '"' || c === "'") {
			const quote = c;
			out += " ";
			i += 1;
			while (i < src.length && src[i] !== quote) {
				if (src[i] === "\\") {
					out += "  ";
					i += 2;
					continue;
				}
				out += src[i] === "\n" ? "\n" : " ";
				i += 1;
			}
			out += " ";
			i += 1;
			continue;
		}
		out += c;
		i += 1;
	}
	return out;
}

// ------------------------------------------------------- what a module owns
//
// `name` is the module's own table identifier, which by convention in this
// codebase is the file's base name.
function membersOf(code, name) {
	const members = new Set();
	let dynamic = false;

	const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

	// function Mod.foo(  /  function Mod:foo(
	for (const m of code.matchAll(new RegExp(`\\bfunction\\s+${esc}\\s*[.:]\\s*([A-Za-z_]\\w*)`, "g"))) {
		members.add(m[1]);
	}
	// Mod.foo = ...
	for (const m of code.matchAll(new RegExp(`\\b${esc}\\s*\\.\\s*([A-Za-z_]\\w*)\\s*=`, "g"))) {
		members.add(m[1]);
	}
	// Mod[expr] = ...  -> computed keys; stop trusting this module's surface
	if (new RegExp(`\\b${esc}\\s*\\[`).test(code)) dynamic = true;

	// Two table-literal shapes, and the second one matters more than it
	// looks: every Config module in this project is an ANONYMOUS
	// `return { ... }`, with no identifier to match on at all. A first
	// version of this scan only handled `local Mod = {` and therefore
	// reported all 7 Config modules as having zero members -- 70-odd
	// confident failures, every one of them wrong. A scan that is wrong at
	// that volume gets switched off within a day, so this case is not
	// optional.
	//
	//   local Mod = { a = 1 }  ...  return Mod
	//   return { a = 1 }
	const lit =
		new RegExp(`\\b(?:local\\s+)?${esc}\\s*=\\s*\\{`).exec(code) ||
		/\breturn\s*\{/.exec(code);
	if (lit) {
		let i = lit.index + lit[0].length - 1;
		let depth = 0;
		let end = i;
		for (; end < code.length; end++) {
			if (code[end] === "{") depth += 1;
			else if (code[end] === "}") {
				depth -= 1;
				if (depth === 0) break;
			}
		}
		const body = code.slice(i + 1, end);
		// top-level keys only: split on commas at depth 0
		let d = 0;
		let cur = "";
		const parts = [];
		for (const ch of body) {
			if (ch === "{" || ch === "(" || ch === "[") d += 1;
			if (ch === "}" || ch === ")" || ch === "]") d -= 1;
			if (ch === "," && d === 0) {
				parts.push(cur);
				cur = "";
			} else cur += ch;
		}
		parts.push(cur);
		for (const part of parts) {
			const kv = /^\s*([A-Za-z_]\w*)\s*=/.exec(part);
			if (kv) members.add(kv[1]);
			else if (/^\s*\[/.test(part)) dynamic = true;
		}
	}

	return { members, dynamic };
}

// ------------------------------------------------------------------ the scan
const files = walk(SRC).sort();

// name -> {members, dynamic}, keyed by module base name (globally unique by
// convention -- the same assumption the two Lua harnesses already rely on).
const surfaces = new Map();
const sources = new Map();
for (const file of files) {
	const base = path.basename(file, ".luau");
	const code = strip(fs.readFileSync(file, "utf8"));
	sources.set(base, { file, code });
	surfaces.set(base, membersOf(code, base));
}

const problems = [];
let checkedRefs = 0;
let skippedDynamic = 0;

for (const [base, { file, code }] of sources) {
	// alias -> module base name, from `local X = require(... .Foo)`
	const aliases = new Map();
	for (const m of code.matchAll(/\blocal\s+([A-Za-z_]\w*)\s*=\s*require\s*\(([^)]*)\)/g)) {
		const target = m[2].trim().split(".").pop().trim();
		if (surfaces.has(target)) aliases.set(m[1], target);
	}

	for (const [alias, target] of aliases) {
		const surface = surfaces.get(target);
		if (surface.dynamic) {
			skippedDynamic += 1;
			continue;
		}
		const esc = alias.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
		for (const m of code.matchAll(new RegExp(`\\b${esc}\\s*[.:]\\s*([A-Za-z_]\\w*)`, "g"))) {
			const member = m[1];
			checkedRefs += 1;
			if (!surface.members.has(member)) {
				const line = code.slice(0, m.index).split("\n").length;
				problems.push({
					file: path.relative(REPO, file),
					line,
					ref: `${alias}.${member}`,
					module: target,
					detail: `${target} never assigns ${member}`,
				});
			}
		}
	}
}

// ------------------------------------------------------------------- report
const quiet = process.argv.includes("--quiet");
if (!quiet) {
	console.log(`TIDEKEEPER member scan — ${files.length} file(s), ${checkedRefs} cross-module reference(s)`);
	if (skippedDynamic > 0) {
		console.log(`  ${skippedDynamic} alias(es) skipped: the target module writes computed keys`);
	}
	console.log("");
}

for (const p of problems) {
	console.log(`FAIL ${p.file}:${p.line}  ${p.ref}  — ${p.detail}`);
}

if (problems.length === 0) {
	console.log(`clean — every cross-module member resolves (${checkedRefs} checked)`);
}
process.exit(problems.length > 0 ? 1 : 0);
