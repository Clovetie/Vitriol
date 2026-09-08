#!/usr/bin/env node
// luau-transform.js
// Location: tools/lib/luau-transform.js
// Purpose:  The Luau -> Lua 5.3 source transform shared by both headless harnesses
//           (vitriol-smoke-test.js for the pure modules, vitriol-session-test.js for
//           the server services). It lives here rather than inlined twice because the
//           two harnesses MUST agree on what legal Luau is: a construct the smoke
//           test tolerates and the session test mangles would mean a green run that
//           tested a rewritten file.
//
//           Deliberately stricter than a general Luau parser: rather than silently
//           mangling constructs it does not understand, it THROWS. The rules it
//           enforces are documented in docs/01-ARCHITECTURE.md §13.

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "../..");

// ---------------------------------------------------------------------------
// Luau -> Lua 5.3 transform
// ---------------------------------------------------------------------------
//
// Deliberately stricter than a general Luau parser: rather than silently
// mangling constructs it does not understand, it THROWS. Pure modules are
// expected to avoid multi-line function heads, `continue`, interpolated strings
// and generics; if a future module uses one, this fails loudly instead of
// testing something other than what was written.
function transformLuau(src, label) {
	const lines = src.split("\n");
	const out = [];
	let inTypeBlock = false;
	let typeDepth = 0;
	let inBlockComment = false;
	let inFnHead = false;
	let parenDebt = 0;

	for (let raw of lines) {
		const trimmed = raw.trim();

		// Block comments: pass through untouched.
		if (inBlockComment) {
			if (/\]\]/.test(trimmed)) inBlockComment = false;
			out.push(raw);
			continue;
		}
		if (/^--\[\[/.test(trimmed)) {
			inBlockComment = !/\]\]/.test(trimmed.slice(4));
			out.push(raw);
			continue;
		}

		const isComment = trimmed.startsWith("--");

		// A compound assignment whose right-hand side spans several lines cannot
		// be closed on the same line, so the opening paren is left open here and
		// closed on the line where the expression actually ends.
		if (!isComment && parenDebt > 0) {
			parenDebt -= (raw.match(/\)/g) || []).length - (raw.match(/\(/g) || []).length;
			if (parenDebt <= 0) {
				// Exactly one wrapper paren is outstanding: each compound
				// assignment opens one, and a second cannot start before the
				// first expression ends.
				raw += ")";
				parenDebt = 0;
			}
		}

		if (!isComment) {
			// Strip `type X = ...` / `export type X = ...` (multi-line aware).
			if (inTypeBlock) {
				typeDepth += (raw.match(/[{(]/g) || []).length;
				typeDepth -= (raw.match(/[})]/g) || []).length;
				if (typeDepth <= 0) inTypeBlock = false;
				out.push("-- (type declaration stripped)");
				continue;
			}
			if (/^\s*(export\s+)?type\s+[A-Za-z_]\w*\s*=/.test(raw)) {
				typeDepth = (raw.match(/[{(]/g) || []).length - (raw.match(/[})]/g) || []).length;
				inTypeBlock = typeDepth > 0;
				out.push("-- (type declaration stripped)");
				continue;
			}

			if (/\bcontinue\b/.test(raw)) {
				throw new Error(`${label}: \`continue\` is not supported by the smoke harness: ${trimmed}`);
			}
			if (/`/.test(raw)) {
				throw new Error(`${label}: interpolated strings are not supported by the smoke harness: ${trimmed}`);
			}

			// Function declarations: drop the return annotation, then param
			// annotations. Heads may span several lines, so track whether the
			// parameter list is still open.
			if (inFnHead) {
				// Continuation lines of a multi-line parameter list can only
				// contain a `:` for a type annotation (the method `:` of a
				// `function Foo:bar()` head is on the opening line), so strip
				// them without needing a lookahead - the last param on a line
				// has no trailing comma to anchor on.
				const closes = /\)/.test(raw);
				let l = raw;
				if (closes) l = l.replace(/^(.*\))\s*:\s*.*$/, "$1");
				l = l.replace(/:\s*[A-Za-z_{][^,()=]*/g, "");
				raw = l;
				if (closes) inFnHead = false;
			} else if (/^\s*(local\s+)?function\b/.test(raw)) {
				const noReturn = raw.replace(/^(.*\))\s*:\s*.*$/, "$1");
				raw = noReturn.replace(/:\s*[A-Za-z_{][^,()=]*?(?=[,)])/g, "");
				const opens = (raw.match(/\(/g) || []).length;
				const closes = (raw.match(/\)/g) || []).length;
				if (opens > closes) inFnHead = true;
			}

			// An anonymous head inside an expression: `Run = function(dt)`,
			// `OnSample = function(name, ms)`. Typed callbacks in table constructors
			// are how this codebase configures its services, so they must be stripped
			// like a named head - but ONLY when the head closes on this line. A call
			// like `conn = self:connect(function(...)` is balanced-not-yet, and treating
			// its continuation lines as a parameter list would eat `conn:disconnect()`.
			if (/\bfunction\s*\(/.test(raw)) {
				// The return annotation can only exist once the head has closed, so that
				// strip is limited to balanced lines; the parameter strip is anchored on a
				// `,` or `)` lookahead and is safe on an unbalanced line too - which is the
				// common shape here, since `remote.OnServerEvent:Connect(function(dt: number)`
				// opens a head it does not close. Neither strip masks strings, so a colon
				// inside a literal on such a line would be eaten; that is why the Vitriol
				// style keeps heads short and literals out of them.
				const opens = (raw.match(/\(/g) || []).length;
				const closes = (raw.match(/\)/g) || []).length;
				if (opens === closes) {
					raw = raw.replace(/^(.*\))\s*:\s*.*$/, "$1");
				}
				raw = raw.replace(/:\s*[A-Za-z_{][^,()=]*?(?=[,)])/g, "");
			}

			// `local x: T = v` / `local x: T`
			raw = raw.replace(/^(\s*local\s+[A-Za-z_]\w*)\s*:\s*[A-Za-z_][\w?]*\s*=\s*/, "$1 = ");
			raw = raw.replace(/^(\s*local\s+[A-Za-z_]\w*)\s*:\s*[A-Za-z_][\w?]*\s*$/, "$1");

			// Type assertion casts: `expr :: T` -> `expr`
			raw = raw.replace(/\s*::\s*[A-Za-z_][\w?|{}]*/g, "");

			// require(script.Parent.Parent.Lib.Foo) -> VitriolRequire("Foo").
			// Shipping modules must use real `require()` with a real Instance path;
			// the harness resolves the LAST path segment against the flat MODULES
			// map. Without this, any module that has a dependency is untestable here.
			raw = raw.replace(/require\(\s*([A-Za-z_][\w.:]*)\s*\)/g, (_all, path) => {
				const parts = path.split(/[.:]/).filter(Boolean);
				return `VitriolRequire("${parts[parts.length - 1]}")`;
			});

			// Compound assignment.
			const m = raw.match(/^(\s*)([A-Za-z_][\w.[\]"']*)\s*(\+=|-=|\*=|\/=)(.+)$/);
			if (m) {
				const rhs = m[4].trim();
				const unbalanced = (rhs.match(/\(/g) || []).length - (rhs.match(/\)/g) || []).length;
				if (unbalanced > 0) {
					raw = `${m[1]}${m[2]} = ${m[2]} ${m[3][0]} (${rhs}`;
					parenDebt = unbalanced;
				} else {
					raw = `${m[1]}${m[2]} = ${m[2]} ${m[3][0]} (${rhs})`;
				}
			}

			// Generalized iteration.
			const fm = raw.match(/^(\s*for\s+[A-Za-z_][\w,\s]*?\s+)in\s+(.+?)\s+do$/);
			// Luau's sugar is `for x in table` (no call). An expression that is already a
			// call - pairs(t), string.gmatch(s, p), next(t, k) - must be left exactly as
			// written; wrapping it in pairs() is how an iterator becomes "table expected,
			// got function".
			if (fm && !/^(pairs|ipairs|next)\s*\(/.test(fm[2].trim()) && !/\)$/.test(fm[2].trim())) {
				raw = `${fm[1]}in pairs(${fm[2]}) do`;
			}
		}

		out.push(raw);
	}

	if (inTypeBlock) throw new Error(`${label}: unterminated type declaration`);
	return out.join("\n");
}

function luaLongString(level, s) {
	const eq = "=".repeat(level);
	return `[${eq}[${s}]${eq}]`;
}

function read(p) {
	return fs.readFileSync(path.join(ROOT, p), "utf8");
}


module.exports = { transformLuau, luaLongString, read, ROOT };
