#!/usr/bin/env python3
"""Read-only Vitriol Studio audit: place, Edit mode, authored verifiers, script classes and source parity.

Usage (credentials in environment, never in files):
  BRIDGE_URL=... BRIDGE_TOKEN=... python tools/vitriol-studio-audit.py
  python tools/vitriol-studio-audit.py --report tools/reports/studio-audit.json

No Studio changes are made. Missing objects, wrong classes, verifier defects,
missing scripts, unexpected Source drift, bridge errors or Play/Run fail closed.
Exactly two user-preserved Source differences are allowed only by pinned hashes
for BOTH Studio and checkout. One missing terminal LF in Studio is recorded
separately; interior whitespace and arbitrary drift still fail closed.
All completed Edit verifiers and Source checks are recorded even on an authored
defect; place/mode/bridge failures stop without claiming a complete report.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from studio_bridge import request

ROOT = Path(__file__).resolve().parent.parent
CODE = ROOT / "code"
PLACE_ID = 92448193604950
VERIFIERS = (
    "verify_static_vitriol.lua",
    "verify_map_vitriol.lua",
    "verify_client_boot_vitriol.lua",
    "verify_dayprep_vitriol.lua",
    "verify_church_bell_vitriol.lua",
    "verify_station_floodlight_vitriol.lua",
    "verify_prep_helpers_vitriol.lua",
    "verify_wristwatch_vitriol.lua",
    "verify_barricade_vitriol.lua",
    "verify_barricade_tool_vitriol.lua",
)
# Exact hashes from the original 2026-10-13 Source ZIP (VictimCamera) and
# the later user-confirmed 70-second Night Source ZIP (DayNightConfig). These
# USER-preserved differences are permitted ONLY when both sides still match
# their pinned bytes; an edited config, blank line, or additional difference
# fails closed. This list cannot authorize a write or prove a cloud place save.
PRESERVED_SOURCES = {
    "ReplicatedStorage.Vitriol.Config.DayNightConfig": (
        "9a735defc13ffe83dd726a3d26cf5fce9e50432903e8c991803ceaee629d0c71",
        "bb8948eabb4d0272593e97efce66fcb8aa4fd8b355dc0cf0c36d5bb587650c77",
        "user-confirmed Studio test phases 15/41/10/70/15; preserve NightBaseSeconds 70"),
    "StarterPlayer.StarterPlayerScripts.Vitriol.Controllers.VictimCamera": (
        "e1436bf76fdd92df7c8d1d9f1c3f81830d94be9968d4b354ef93e20099e022a3",
        "0f6a4c4680556cff3004ea1782a050c9752ea1afcf612ac9eaf2036e0d0a1bfe",
        "three extra blank lines before Studio's return statement"),
}


class AuditFailure(RuntimeError):
    def __init__(self, report, reason):
        self.report = report
        super().__init__(reason)


def source_verdict(name, studio, local):
    """Exact bytes only: known Studio edits require both pinned source hashes."""
    if not isinstance(studio, str):
        return "missing"
    if studio == local:
        return "exact"
    # Studio previously stored these older files without ONE final LF. This
    # is recorded separately, not silently stripped along with interior edits.
    if local.endswith("\n") and studio == local[:-1]:
        return "terminal-lf"
    pinned = PRESERVED_SOURCES.get(name)
    if pinned and (hashlib.sha256(local.encode()).hexdigest(),
                   hashlib.sha256(studio.encode()).hexdigest()) == pinned[:2]:
        return "preserved"
    return "unexpected"


def job(kind, payload, note):
    result = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if result.get("status") != "done" or result.get("ok") is not True:
        raise RuntimeError(f"{note}: bridge job did not complete successfully")
    return result.get("result") or {}


def scripts():
    paths = {}
    for file in sorted(CODE.rglob("*.luau")):
        parts = file.relative_to(CODE).with_suffix("").parts
        instance = ".".join(parts)
        if parts[0] == "ServerScriptService":
            class_name = "Script"
        elif parts[0] == "StarterPlayer" and parts[-1] == "ClientMain":
            class_name = "LocalScript"
        else:
            class_name = "ModuleScript"
        paths[instance] = (file, class_name)
    return paths


def run():
    ping = job("ping", {}, "Vitriol audit place check")
    if ping.get("placeId") != PLACE_ID:
        raise RuntimeError(f"wrong Studio place ID {ping.get('placeId')}; expected {PLACE_ID}")
    running = job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"}, "Vitriol audit Edit-mode check")
    if running.get("returned") != "false":
        raise RuntimeError("stop Play/Run before auditing authored Edit-mode state")

    report = {"placeId": PLACE_ID, "mode": "Edit", "verifiers": {}, "scripts": {}, "passed": False}
    defects = []
    # Verifiers are read-only; collect ALL verdicts rather than stopping at
    # the first authored mismatch and obscuring unrelated script drift.
    for filename in VERIFIERS:
        source = (ROOT / "jobs" / filename).read_text(encoding="utf-8")
        outcome = job("run_luau", {"code": source}, "Vitriol audit " + filename)
        try:
            verdict = json.loads(outcome["returned"])
        except (KeyError, TypeError, json.JSONDecodeError) as error:
            raise RuntimeError(f"{filename}: no JSON verdict") from error
        if not isinstance(verdict, dict):
            raise RuntimeError(f"{filename}: verdict is not an object")
        report["verifiers"][filename] = verdict
        if verdict.get("ok") is not True:
            defects.append(f"{filename}: verifier reported defects: {verdict.get('defects', verdict.get('failures'))}")

    expected = scripts()
    surveyed = job("survey", {"maxScriptBytes": 0, "includeSource": False}, "Vitriol audit script-class survey")
    by_path = {}
    for row in surveyed.get("scripts", []):
        path = row.get("path")
        if path in expected:
            if path in by_path:
                raise RuntimeError(f"duplicate Studio script path: {path}")
            by_path[path] = row.get("className")
    missing = sorted(set(expected) - set(by_path))
    wrong = {name: {"expected": expected[name][1], "actual": by_path[name]}
             for name in sorted(by_path) if by_path[name] != expected[name][1]}
    report["scripts"]["classesChecked"] = len(by_path)
    report["scripts"]["missing"] = missing
    report["scripts"]["wrongClass"] = wrong
    if missing or wrong:
        raise AuditFailure(report, f"Studio script class audit failed: {len(missing)} missing, {len(wrong)} wrong-class")

    entries = list(expected.items())
    drift, preserved, terminal_lf = [], [], []
    for start in range(0, len(entries), 5):
        batch = entries[start:start + 5]
        paths = [name for name, _ in batch]
        response = job("read_scripts", {"paths": paths, "maxBytes": 450000}, "Vitriol audit source readback")
        rows = response.get("scripts") or []
        if len(rows) != len(paths) or len({row.get("path") for row in rows}) != len(paths):
            raise RuntimeError("Studio source readback partial or duplicated")
        actual = {row.get("path"): row.get("source") for row in rows}
        for name, (file, _) in batch:
            verdict = source_verdict(name, actual.get(name), file.read_text(encoding="utf-8"))
            if verdict == "preserved":
                preserved.append({"path": name, "reason": PRESERVED_SOURCES[name][2]})
            elif verdict == "terminal-lf":
                terminal_lf.append(name)
            elif verdict != "exact":
                drift.append(name)
    report["scripts"]["sourceChecked"] = len(entries)
    report["scripts"]["exact"] = len(entries)-len(preserved)-len(terminal_lf)-len(drift)
    report["scripts"]["terminalNewlineOnly"] = terminal_lf
    report["scripts"]["preservedStudioDifferences"] = preserved
    report["scripts"]["drift"] = drift
    if drift:
        defects.append(f"Studio source drift in {len(drift)} script(s): {', '.join(drift)}")
    if defects:
        report["defects"] = defects
        raise AuditFailure(report, "; ".join(defects))
    report["passed"] = True
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", default="tools/reports/studio-audit.json")
    options = parser.parse_args()
    report_file = (ROOT / options.report).resolve()
    if not report_file.is_relative_to(ROOT):
        parser.error("report path must be within the workspace checkout")
    try:
        report = run()
        report_file.parent.mkdir(parents=True, exist_ok=True)
        report_file.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Vitriol Studio audit: PASS — {len(report['verifiers'])} verifiers, "
              f"{report['scripts']['classesChecked']} script classes, "
              f"{report['scripts']['sourceChecked']} sources "
              f"({report['scripts']['exact']} exact, "
              f"{len(report['scripts']['terminalNewlineOnly'])} one-terminal-LF, "
              f"{len(report['scripts']['preservedStudioDifferences'])} pinned user differences), "
              "zero unexpected drift")
        print("Report:", report_file.relative_to(ROOT))
        return 0
    except AuditFailure as error:
        report_file.parent.mkdir(parents=True, exist_ok=True)
        report_file.write_text(json.dumps(error.report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("Vitriol Studio audit: FAIL —", error, file=sys.stderr)
        print("Failed read-only report:", report_file.relative_to(ROOT), file=sys.stderr)
        return 1
    except (RuntimeError, ValueError) as error:
        # The bridge helper never includes its credential-bearing URL in errors.
        print("Vitriol Studio audit: FAIL —", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
