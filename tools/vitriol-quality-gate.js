#!/usr/bin/env node
"use strict";

/**
 * Vitriol quality gate — one deterministic pre-commit/CI command for future
 * iterations.
 *
 * This deliberately orchestrates the repository's existing tests and analysis
 * tools rather than replacing them. The official luau-compile parser is REQUIRED:
 * historical luaparse/Fengari transforms erased invalid type annotations and
 * let a broken Studio module pass green. Install via bash tools/install-luau.sh.
 *
 * Usage:
 *   node tools/vitriol-quality-gate.js
 *   node tools/vitriol-quality-gate.js --src code --report tools/reports/quality-gate.json
 *
 * The report contains bounded stdout/stderr for every command so a later agent
 * can inspect the exact evidence without rerunning a long suite. Generated
 * reports belong under tools/reports/ and are ignored by Git.
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { defaultSourceRoot } = require("./lib/paths");

const ROOT = path.resolve(__dirname, "..");
const NODE = process.execPath;
const MAX_CAPTURE = 400000;
// No syntax exceptions are allowed. The official Luau compiler is mandatory.

function die(message) {
	console.error(`vitriol-quality-gate: ${message}`);
	process.exit(2);
}

function parseArgs(argv) {
	const out = {
		src: path.relative(ROOT, defaultSourceRoot()).replace(/\\/g, "/") || ".",
		report: null,
		quiet: false,
	};
	for (let i = 2; i < argv.length; i += 1) {
		const arg = argv[i];
		if (arg === "--src") {
			const absolute = path.resolve(process.cwd(), argv[++i]);
			out.src = path.relative(ROOT, absolute).replace(/\\/g, "/") || ".";
		}
		else if (arg === "--report") out.report = argv[++i];
		else if (arg === "--quiet") out.quiet = true;
		else if (arg === "--help") {
			console.log("Usage: node tools/vitriol-quality-gate.js [--src code] [--report path] [--quiet]");
			process.exit(0);
		} else {
			die(`unknown argument ${arg}`);
		}
	}
	return out;
}

function relativePath(value) {
	return path.relative(ROOT, value).replace(/\\/g, "/");
}

function commandString(args) {
	return ["node", ...args].join(" ");
}

function runNode(args) {
	const result = spawnSync(NODE, args, {
		cwd: ROOT,
		encoding: "utf8",
		maxBuffer: 32 * 1024 * 1024,
	});
	const stdout = result.stdout || "";
	const stderr = result.stderr || "";
	const combined = `${stdout}${stderr}`;
	return {
		command: commandString(args),
		args,
		exitCode: typeof result.status === "number" ? result.status : 1,
		signal: result.signal || null,
		stdout,
		stderr,
		combined,
		spawnError: result.error ? String(result.error.message || result.error) : null,
	};
}

function runShell(args) {
	const result = spawnSync(args[0], args.slice(1), {
		cwd: ROOT,
		encoding: "utf8",
		maxBuffer: 32 * 1024 * 1024,
	});
	const stdout = result.stdout || "";
	const stderr = result.stderr || "";
	return {
		command: args.join(" "),
		args,
		exitCode: typeof result.status === "number" ? result.status : 1,
		signal: result.signal || null,
		stdout,
		stderr,
		combined: `${stdout}${stderr}`,
		spawnError: result.error ? String(result.error.message || result.error) : null,
	};
}

function bounded(text) {
	if (text.length <= MAX_CAPTURE) return { text, truncated: false };
	return { text: `${text.slice(0, MAX_CAPTURE)}\n[output truncated]`, truncated: true };
}

function summaryLine(output, regex) {
	const match = output.combined.match(regex);
	return match ? match[0].trim() : null;
}

function syntaxAssessment(output) {
	const failures = [...output.combined.matchAll(/^FAIL\s+(.+)$/gm)].map((match) => match[1].trim());
	const normalised = failures.map((file) => file.replace(/^.*?(?=code\/)/, ""));
	const okCount = (output.combined.match(/^OK\s+/gm) || []).length;
	return {
		passed: output.exitCode === 0 && normalised.length === 0,
		okCount,
		failures: normalised,
		unexpected: normalised,
		known: [],
		note: "all Luau files parsed (secondary Lua 5.1 approximation)",
	};
}

function evaluateCheck(id, output) {
	const combined = output.combined;
	if (id === "smoke") {
		const match = combined.match(/VITRIOL smoke test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[2]) === 0, summary: match ? match[0] : null };
	}
	if (id === "survival-model") {
		const match = combined.match(/VITRIOL smoke test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 54 && Number(match[2]) === 0,
			summary: match ? `Pure survival model ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "survival-consume-action") {
		const match = combined.match(/VITRIOL smoke test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 25 && Number(match[2]) === 0,
			summary: match ? `Pure consumption action ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "survival-collapse") {
		const match = combined.match(/VITRIOL smoke test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 24 && Number(match[2]) === 0,
			summary: match ? `Pure collapse timeline ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "survival-service") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 57 && Number(match[2]) === 0,
			summary: match ? `Offline survival ownership ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "survival-consume-service") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 25 && Number(match[2]) === 0,
			summary: match ? `Offline consumption authority ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "session") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[2]) === 0, summary: match ? match[0] : null };
	}
	if (id === "bell") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 19 && Number(match[2]) === 0, summary: match ? `Church bell ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "senses") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 23 && Number(match[2]) === 0, summary: match ? `Sight/thermal/noise ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "instinct-search") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 19 && Number(match[2]) === 0, summary: match ? `Night search ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "region-patrol") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 12 && Number(match[2]) === 0, summary: match ? `Region patrol ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (["garage-habit", "shadow-predictor", "cadence-warning-context"].includes(id)) {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		const minimum = id === "garage-habit" ? 69 : id === "shadow-predictor" ? 21 : 10;
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= minimum && Number(match[2]) === 0, summary: match ? `${id} ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "time-publish-profile") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 10 && Number(match[2]) === 0, summary: match ? `Time publish profile ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "church-route") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 10 && Number(match[2]) === 0, summary: match ? `Church route ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "navigation") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 25 && Number(match[2]) === 0, summary: match ? `Garage navigation ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "placement") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 17 && Number(match[2]) === 0, summary: match ? `Placement ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "barricade") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 23 && Number(match[2]) === 0, summary: match ? `Barricade ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "prep-publish-count") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 7 && Number(match[2]) === 0, summary: match ? `DayPrep publication path ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "house-cover") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 69 && Number(match[2]) === 0, summary: match ? `House cover ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "cover-clue-full") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 11 && Number(match[2]) === 0, summary: match ? `Recent-clue full breach ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "cover-clue-footed") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 7 && Number(match[2]) === 0, summary: match ? `Footed House contact ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "house-access") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 74 && Number(match[2]) === 0, summary: match ? `House access ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "run-lights") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 27 && Number(match[2]) === 0, summary: match ? `Persistent lights ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (id === "day-prep") {
		const match = combined.match(/VITRIOL session test:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= 14 && Number(match[2]) === 0, summary: match ? `Day-prep ${match[1]} passed, ${match[2]} failed` : null };
	}
	if (["studio-audit-unit", "priority-sync-unit", "house-church-sync-unit", "house-ingress-sync-unit", "cover-clue-sync-unit", "studio-properties-unit"].includes(id)) {
		const match = combined.match(/Ran (\d+) tests/);
		const minimum = id === "studio-audit-unit" ? 9 : (id === "house-church-sync-unit" || id === "cover-clue-sync-unit") ? 6 : 5;
		const label = id === "studio-audit-unit" ? "Studio audit"
			: id === "studio-properties-unit" ? "Property inventory"
			: id === "house-ingress-sync-unit" ? "House ingress sync"
			: id === "cover-clue-sync-unit" ? "Cover clue two-Module sync"
			: id === "house-church-sync-unit" ? "Two-Module sync" : "One-Module sync";
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) >= minimum
			&& /\bOK\b/.test(combined), summary: match ? `${label} ${match[1]} fail-closed cases` : null };
	}
	if (id === "client-boot") {
		const match = combined.match(/Client delayed-replication regression:\s+(\d+) passed,\s+(\d+) failed/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) > 0 && Number(match[2]) === 0, summary: match ? match[0] : null };
	}
	if (id === "syntax") return syntaxAssessment(output);
	if (id === "metrics") {
		const match = combined.match(/=== BRINE metrics \((\d+) files\) ===[\s\S]*?LOC (\d+) \| code (\d+) \| comments (\d+) \| exports (\d+) \| requires (\d+)/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) > 0, summary: match ? match[0].replace(/\s+/g, " ") : null };
	}
	if (id === "hot-loop") {
		const match = combined.match(/Priced calls:\s+(\d+) \| inside-a-loop:\s+(\d+) \| in a RunService file:\s+(\d+)/);
		return { passed: output.exitCode === 0 && !!match && Number(match[3]) === 0, summary: match ? match[0] : null, framePathCalls: match ? Number(match[3]) : null };
	}
	if (id === "call-graph") {
		const match = combined.match(/Modules:\s+(\d+)[\s\S]*?Require edges:\s+(\d+)/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) > 0, summary: match ? match[0].replace(/\s+/g, " ") : null };
	}
	if (id === "dead-config") {
		return { passed: output.exitCode === 0, summary: summaryLine(output, /(?:^! .*: not found$|^=== .*config keys ===$)/m) };
	}
	if (id === "evaluation") {
		const admit = /fixture-known-good:\s+ADMIT\s+100\.0%/.test(combined);
		const reject = /candidate-local:\s+REJECT\s+0\.0%/.test(combined);
		return { passed: output.exitCode === 0 && admit && reject, summary: `${admit ? "ADMIT 100.0%" : "missing ADMIT"} / ${reject ? "REJECT 0.0%" : "missing REJECT"}` };
	}
	if (id === "static-content") {
		return { passed: output.exitCode === 0 && /Authored-content gate:/.test(combined), summary: summaryLine(output, /^Authored-content gate:.*$/m) };
	}
	if (id === "luau-compiler") {
		const match = combined.match(/Official Luau compiler: (\d+) game scripts compiled/);
		return { passed: output.exitCode === 0 && !!match && Number(match[1]) > 0, summary: match ? match[0] : null };
	}
	if (id === "diff-check") {
		return { passed: output.exitCode === 0, summary: output.exitCode === 0 ? "no whitespace errors" : null };
	}
	return { passed: output.exitCode === 0, summary: null };
}

function main() {
	const cli = parseArgs(process.argv);
	const src = cli.src;
	const checks = [
		["smoke", ["tools/vitriol-smoke-test.js"]],
		["survival-model", ["tools/vitriol-smoke-test.js", "--tests", "tools/vitriol/survival-model.luau"]],
		["survival-consume-action", ["tools/vitriol-smoke-test.js", "--tests", "tools/vitriol/survival-consume-action.luau"]],
		["survival-collapse", ["tools/vitriol-smoke-test.js", "--tests", "tools/vitriol/survival-collapse.luau"]],
		["survival-service", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/survival-service.luau"]],
		["survival-consume-service", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/survival-consume-service.luau"]],
		["session", ["tools/vitriol-session-test.js"]],
		["day-prep", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/dayprep.luau"]],
		["bell", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/bell.luau"]],
		["bell-hoist", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/bell-hoist.luau"]],
		["prep-clock", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/prep-clock.luau"]],
		["time-publish-profile", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/time-publish-profile.luau"]],
		["prep-publish-count", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/prep-publish-count.luau"]],
		["cadence-warning-context", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/cadence-warning-context.luau"]],
		["prep-coordinator", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/prep-coordinator.luau"]],
		["prep-integration", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/prep-integration.luau"]],
		["run-lights", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/run-lights.luau"]],
		["house-cover", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/house-cover.luau"]],
		["cover-clue-full", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/house-cover-recent-clue.luau"]],
		["cover-clue-footed", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/house-cover-footed-ingress.luau"]],
		["house-access", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/house-access.luau"]],
		["prep-fast-day", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/prep-fast-day.luau"]],
		["barricade", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/barricade.luau"]],
		["placement", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/placement.luau"]],
		["navigation", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/navigation.luau"]],
		["church-route", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/church-navigation.luau"]],
		["senses", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/senses.luau"]],
		["instinct-search", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/instinct-search.luau"]],
		["region-patrol", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/region-patrol.luau"]],
		["garage-habit", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/garage-habit.luau"]],
		["shadow-predictor", ["tools/vitriol-session-test.js", "--tests", "tools/vitriol/shadow-predictor.luau"]],
		["client-boot", ["tools/vitriol-client-boot-test.js"]],
		["watch", ["tools/vitriol-watch-test.js"]],
		["prep-fade", ["tools/vitriol-prep-fade-test.js"]],
		["studio-audit-unit", ["tools/test-studio-audit.py"]],
		["priority-sync-unit", ["tools/test-sync-house-garage-priority.py"]],
		["house-church-sync-unit", ["tools/test-sync-pending-house-church.py"]],
		["house-ingress-sync-unit", ["tools/test-sync-house-ingress-lastknown.py"]],
		["cover-clue-sync-unit", ["tools/test-sync-house-cover-recent-clue.py"]],
		["studio-properties-unit", ["tools/test-studio-property-backup.py"]],
		["static-content", ["tools/static-content-check.js"]],
		["luau-compiler", ["tools/compile-luau.js"]],
		["syntax", ["tools/check-syntax.js", src]],
		["metrics", ["tools/metrics.js", "--src", src]],
		["hot-loop", ["tools/hot-loop-scan.js", "--src", src]],
		["call-graph", ["tools/call-graph.js", "--src", src]],
		["dead-config", ["tools/find-dead-config.js", "--src", src]],
		["evaluation", ["tools/evaluate-models.js", "--models", "tools/models.example.json", "--suite", "tools/evaluation-suite.example.json"]],
		["diff-check", null],
	];
	const results = [];
	for (const [id, args] of checks) {
		const raw = ["studio-audit-unit", "priority-sync-unit", "house-church-sync-unit", "house-ingress-sync-unit", "cover-clue-sync-unit", "studio-properties-unit"].includes(id)
			? runShell(["python", ...args])
			: args ? runNode(args) : runShell(["git", "diff", "--check", "HEAD"]);
		const assessment = evaluateCheck(id, raw);
		const record = {
			id,
			command: raw.command,
			exitCode: raw.exitCode,
			signal: raw.signal,
			spawnError: raw.spawnError,
			passed: assessment.passed,
			summary: assessment.summary || null,
			notes: assessment.note || null,
			stdout: bounded(raw.stdout),
			stderr: bounded(raw.stderr),
		};
		if (id === "syntax") {
			record.okCount = assessment.okCount;
			record.failures = assessment.failures;
			record.knownFailures = assessment.known;
			record.unexpectedFailures = assessment.unexpected;
		}
		results.push(record);
		if (!cli.quiet) {
			console.log(`[${record.passed ? "PASS" : "FAIL"}] ${id}${record.summary ? ` — ${record.summary}` : ""}`);
			if (id === "syntax" && assessment.known && assessment.known.length) {
				console.log(`       allowlisted syntax exceptions: ${assessment.known.join(", ")}`);
			}
			if (!record.passed && raw.stderr) console.error(raw.stderr.trim().split("\n").slice(-4).join("\n"));
		}
	}

	const failed = results.filter((result) => !result.passed);
	const report = {
		schema: 1,
		generated_at: new Date().toISOString(),
		sourceRoot: src,
		checks: results,
		passed: failed.length === 0,
		summary: { total: results.length, passed: results.length - failed.length, failed: failed.length },
	};
	if (cli.report) {
		const reportPath = path.resolve(ROOT, cli.report);
		fs.mkdirSync(path.dirname(reportPath), { recursive: true });
		fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n");
		if (!cli.quiet) console.log(`Report: ${relativePath(reportPath)}`);
	}
	console.log(`Vitriol quality gate: ${report.summary.passed}/${report.summary.total} checks passed`);
	if (failed.length) {
		console.error(`Failed checks: ${failed.map((result) => result.id).join(", ")}`);
		process.exitCode = 1;
	}
}

main();
