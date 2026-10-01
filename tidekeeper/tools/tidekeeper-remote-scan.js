#!/usr/bin/env node
"use strict";
//
// tidekeeper-remote-scan.js -- every remote must have a caller on the side
// that originates it, and a listener on the side that receives it.
//
// WHY THIS EXISTS
// ---------------
// Iteration 9 found that THE CLIENT COULD NOT PERFORM A SINGLE ACTION.
//
// Six client -> server remotes were declared in NetContract.REMOTES. All six
// were bound on the server, rate limited, schema checked, and covered by
// session tests. The client invoked exactly ONE of them -- RF_Session -- and
// then listened. Arranging a shelf, combing the beach, setting standing
// orders, dispatching a drifter and buying a tier: every verb in the game had
// a complete, correct, tested server half and no way for a player to reach it.
//
// Sixteen checks were green. They were green because each half is valid on
// its own: the handler is bound (fine), the payload builder returns a table
// (fine), the schema validates (fine, nothing ever submits to it). The defect
// is the absence of a call, and absence is exactly what the other scans are
// not looking for:
//
//   member-scan      a field READ that is never written
//   dead-write-scan  a field WRITTEN that is never read
//   orphan-scan      a FUNCTION defined that is never called
//   remote-scan      a REMOTE declared that one side never speaks   <- this
//
// The orphan scan could not catch it either: ClientBootstrap:requestSession
// is called, PostView.arrangePayload was allowlisted as "client UI not built",
// and `invoke` is called once, which is enough to look alive. Only counting
// calls PER REMOTE NAME shows that five of the six were never spoken.
//
// WHAT IT CHECKS
// --------------
// For each row of NetContract.REMOTES, with direction 1 = client -> server
// (RemoteFunction) and 2 = server -> client (RemoteEvent):
//
//   dir 1   the SERVER must bind a handler for it,
//           and the CLIENT must invoke it by name.
//   dir 2   the SERVER must fire it,
//           and the CLIENT must connect to it.
//
// A remote is "spoken" by a tree if that tree mentions its NetContract
// constant (NetContract.RF_ARRANGE) or its wire name ("RF_Arrange"). Matching
// on the constant rather than on call syntax keeps this honest about helper
// indirection -- ClientBootstrap routes every call through :invoke(name, ...)
// and :act(name, ...), so there is no literal InvokeServer at the call site
// to look for.
//
// ALLOWLIST
// ---------
// Deliberately absent. A remote that one side never speaks is either an
// unreachable feature or a row that should be deleted, and both of those
// should cost somebody a decision rather than a line in a list.

const fs = require("fs");
const path = require("path");

const GAME = path.resolve(__dirname, "..");
const SRC = path.join(GAME, "code");
const REPO = path.resolve(GAME, "..");

const CLIENT_DIRS = [
	path.join(SRC, "ReplicatedStorage", "Tidekeeper", "Client"),
	path.join(SRC, "StarterPlayer"),
];
const SERVER_DIRS = [
	path.join(SRC, "ServerScriptService"),
	path.join(SRC, "ServerStorage"),
];

const DIR_TO_SERVER = 1;
const DIR_TO_CLIENT = 2;

function walk(dir, out) {
	if (!fs.existsSync(dir)) return out;
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) walk(p, out);
		else if (e.name.endsWith(".luau")) out.push(p);
	}
	return out;
}

function readAll(dirs) {
	let text = "";
	const files = [];
	for (const d of dirs) walk(d, files);
	for (const f of files) text += "\n" + strip(fs.readFileSync(f, "utf8"));
	return { text, count: files.length };
}

// Remote name -> the NetContract constant that names it. RF_SetOrders becomes
// RF_SET_ORDERS: the wire name is camel, the constant is screaming snake, and
// deriving one from the other is what keeps this scan from needing its own
// copy of the list.
function constantFor(wireName) {
	const m = /^(RF|RE)_(.+)$/.exec(wireName);
	if (!m) return null;
	const tail = m[2].replace(/([a-z0-9])([A-Z])/g, "$1_$2").toUpperCase();
	return `${m[1]}_${tail}`;
}

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
	const contractPath = path.join(SRC, "ReplicatedStorage", "Tidekeeper", "Shared", "NetContract.luau");
	if (!fs.existsSync(contractPath)) {
		console.log("TIDEKEEPER remote scan — no NetContract yet, nothing to check");
		return 0;
	}
	// Parsed from the RAW file: strip() erases string literals, and the
	// remote names ARE string literals. Detection below uses the stripped
	// corpora instead, so a comment that merely mentions RF_Arrange -- and
	// PostView has exactly such a comment -- can never be mistaken for a
	// call.
	const contract = fs.readFileSync(contractPath, "utf8");

	// Parse the REMOTES table: { "RF_Session", 1, 2, 1 }, ...
	const block = /NetContract\.REMOTES\s*=\s*\{([\s\S]*?)\n\}/.exec(contract);
	if (!block) {
		console.log("FAIL could not find NetContract.REMOTES");
		return 1;
	}
	const rows = [...block[1].matchAll(/\{\s*"([A-Za-z_]+)"\s*,\s*(\d+)/g)].map((m) => ({
		name: m[1],
		dir: Number(m[2]),
	}));
	if (rows.length === 0) {
		console.log("FAIL NetContract.REMOTES parsed as empty");
		return 1;
	}

	const client = readAll(CLIENT_DIRS);
	const server = readAll(SERVER_DIRS);

	// Only real code counts: both corpora have had comments and strings
	// removed, so this matches the NetContract constant and nothing else.
	const spoken = (corpus, row) => {
		const konst = constantFor(row.name);
		return konst !== null && new RegExp(`NetContract\\.${konst}\\b`).test(corpus);
	};

	const failures = [];
	for (const row of rows) {
		const onClient = spoken(client.text, row);
		const onServer = spoken(server.text, row);
		if (row.dir === DIR_TO_SERVER) {
			if (!onServer) failures.push(`${row.name}  — client -> server, but NO SERVER HANDLER binds it`);
			if (!onClient) failures.push(`${row.name}  — client -> server, but NO CLIENT CODE ever calls it`);
		} else if (row.dir === DIR_TO_CLIENT) {
			if (!onServer) failures.push(`${row.name}  — server -> client, but NO SERVER CODE ever fires it`);
			if (!onClient) failures.push(`${row.name}  — server -> client, but NO CLIENT CODE ever listens`);
		} else {
			failures.push(`${row.name}  — unknown direction ${row.dir}`);
		}
	}

	console.log(
		`TIDEKEEPER remote scan — ${rows.length} remote(s), ` +
			`${client.count} client file(s), ${server.count} server file(s)`
	);
	console.log("");

	if (failures.length === 0) {
		console.log(`clean — every remote is spoken by both sides (${rows.length} checked)`);
		return 0;
	}
	for (const f of failures) console.log(`FAIL ${f}`);
	console.log("");
	console.log(
		`${failures.length} unreachable remote path(s). A remote only one side ever ` +
			`speaks is a feature no player can use.`
	);
	return 1;
}

process.exit(main());
