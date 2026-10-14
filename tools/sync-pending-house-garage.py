#!/usr/bin/env python3
"""Fail-closed, narrowly scoped Vitriol Edit sync for pending House/Garage work.

--offline (default) validates the previously captured full Studio Sources and
prints SHA256s without contacting the bridge. --check reads Studio without
writing. --apply requires an explicit flag and writes ONLY the four named
ModuleScripts after full-source/class/place/Edit guards. No Play introspection.
Do not use a generic repository-wide sync for this task.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from studio_bridge import request

ROOT = Path(__file__).resolve().parent.parent
PLACE_ID = 92448193604950
# Full-source snapshots from the LAST verified guarded Edit sync of each path.
# Every one must match the CURRENT Studio Source byte-for-byte (or the new
# desired source byte-for-byte for an already completed partial deployment).
TARGETS = (
    ("ServerStorage.Vitriol.Creature.HouseAccess",
     "house-exit-sweep-final-sources.json"),
    ("ServerStorage.Vitriol.Creature.CreatureCore",
     "house-break-output-sources.json"),
    ("ServerStorage.Vitriol.Services.CreatureService",
     "house-exit-sweep-final-sources.json"),
    ("ServerStorage.Vitriol.Bootstrap",
     "dayprep-warning-context-sources.json"),
)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def load_plan():
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if branch != "main":
        raise RuntimeError("refusing a sync outside Vitriol main")
    plan = []
    for path, report_name in TARGETS:
        report = json.loads((ROOT / "tools/reports" / report_name).read_text(encoding="utf-8"))
        if report.get("status") != "done" or report.get("ok") is not True:
            raise RuntimeError("prior verified readback is missing or failed: " + report_name)
        matches = [item for item in report["result"]["scripts"] if item.get("path") == path]
        if len(matches) != 1 or not isinstance(matches[0].get("source"), str):
            raise RuntimeError("prior full Source missing or ambiguous: " + path)
        relative = Path(*path.split(".")).with_suffix(".luau")
        file = ROOT / "code" / relative
        plan.append((path, matches[0]["source"], file.read_text(encoding="utf-8")))
    return plan


def job(kind, payload, note):
    result = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if result.get("status") != "done" or result.get("ok") is not True:
        raise RuntimeError(note + " failed; do not continue or overwrite user changes")
    return result.get("result") or {}


def guard_edit():
    if job("ping", {}, "Pending Vitriol sync place guard").get("placeId") != PLACE_ID:
        raise RuntimeError("wrong place; no writes permitted")
    running = job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"},
                  "Pending Vitriol sync Edit guard")
    if running.get("returned") != "false":
        raise RuntimeError("Play/Run is active; Edit-only sync refused")


def verify_classes(paths):
    for path in paths:
        result = job("inspect", {"path": path, "depth": 0}, "Inspect pending ModuleScript class")
        if result.get("className") != "ModuleScript":
            raise RuntimeError(path + ": expected existing ModuleScript; no writes permitted")


def read_sources(paths):
    result = job("read_scripts", {"paths": list(paths), "maxBytes": 160000},
                 "Read full pending Vitriol Sources")
    sources = result.get("scripts") or []
    if len(sources) != len(paths):
        raise RuntimeError("partial Source readback; no writes permitted")
    indexed = {item.get("path"): item.get("source") for item in sources}
    if any(not isinstance(indexed.get(path), str) for path in paths):
        raise RuntimeError("missing or truncated Source; no writes permitted")
    return indexed


def run(mode):
    plan = load_plan()
    if mode == "offline":
        for path, previous, desired in plan:
            print(path, "previous", digest(previous), "workspace", digest(desired),
                  "unchanged" if previous == desired else "pending")
        print("Offline plan only; no Studio read, no Studio write, no Play verdict")
        return
    guard_edit()
    paths = [path for path, _, _ in plan]
    verify_classes(paths)
    actual = read_sources(paths)
    for path, previous, desired in plan:
        if actual[path] != previous and actual[path] != desired:
            raise RuntimeError(path + ": Studio Source differs from BOTH guarded old and intended new; no writes")
    if mode == "check":
        for path, _, desired in plan:
            print(path, "already exact" if actual[path] == desired else "guarded and pending")
        print("Read-only Edit preflight; no Studio write and no Play verdict")
        return
    for path, previous, desired in plan:
        if actual[path] == desired:
            continue
        # A user may change the local file or Studio mode during the multi-job
        # operation. Recheck both before each individual write. No rollback of
        # any earlier successful write is attempted if a later guard fails.
        guard_edit()
        local_file = ROOT / "code" / Path(*path.split(".")).with_suffix(".luau")
        if local_file.read_text(encoding="utf-8") != desired:
            raise RuntimeError(path + ": local Source changed mid-sync; stopped")
        current = read_sources([path])[path]
        if current != previous:
            raise RuntimeError(path + ": Studio Source changed mid-sync; stopped")
        parts = path.split(".")
        job("write_script", {"parent": ".".join(parts[:-1]), "name": parts[-1],
                             "className": "ModuleScript", "source": desired},
            "Guarded pending Vitriol ModuleScript write")
        verify_classes([path])
        if read_sources([path])[path] != desired:
            raise RuntimeError(path + ": exact post-write readback failed; stopped")
        print(path, "exact Source/class readback", digest(desired))
    guard_edit()
    verify_classes(paths)
    final = read_sources(paths)
    if any(final[path] != desired for path, _, desired in plan):
        raise RuntimeError("final exact four-source parity failed")
    print("Four pending ModuleScripts exact in Vitriol/Edit; NOT live Play acceptance")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--offline", action="store_const", const="offline", dest="mode")
    group.add_argument("--check", action="store_const", const="check", dest="mode")
    group.add_argument("--apply", action="store_const", const="apply", dest="mode")
    arguments = parser.parse_args()
    try:
        run(arguments.mode or "offline")
    except Exception as exc:
        # studio_bridge intentionally hides credential-bearing URLs. These
        # failures are narrowed to local guard errors; no Source is printed.
        print("Pending Vitriol sync refused:", exc, file=sys.stderr)
        sys.exit(1)
