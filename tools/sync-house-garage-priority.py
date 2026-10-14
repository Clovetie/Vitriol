#!/usr/bin/env python3
"""Fail-closed ONE-Module Vitriol/Edit plan for indoor House egress vs Garage habit.

Default --offline: compare local Source with the exact prior Studio Source ZIP.
--check: read ONLY the guarded Studio Source/class/place/mode; never write.
--apply --saved-checkpoint-verified: operator must first verify a full-place
Save to Roblox with Notes checkpoint in Version History. The legacy bridge
cannot do or verify this UI action. The explicit flag is a human attestation,
NOT evidence that a cloud save happened. An apply writes only CreatureService
when full Studio Source EXACTLY matches the prior ZIP, then reads back class,
full Source and place/Edit again. Never store bridge credentials in files.
"""
import argparse
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True
from studio_bridge import request

ROOT = Path(__file__).resolve().parent.parent
PLACE_ID = 92448193604950
PATH = "ServerStorage.Vitriol.Services.CreatureService"
BASELINE = ROOT / "backups/vitriol-studio-edit-sources-2026-10-13.zip"
LOCAL = ROOT / "code/ServerStorage/Vitriol/Services/CreatureService.luau"


def digest(source):
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def plan():
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if branch != "main":
        raise RuntimeError("refusing a Studio sync outside Vitriol main")
    with zipfile.ZipFile(BASELINE) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        if manifest.get("placeId") != PLACE_ID or manifest.get("mode") != "Edit":
            raise RuntimeError("prior Studio Source ZIP has wrong place/mode")
        rows = [row for row in manifest.get("scripts", []) if row.get("path") == PATH]
        if len(rows) != 1 or rows[0].get("className") != "ModuleScript":
            raise RuntimeError("prior CreatureService Source/class missing or ambiguous")
        prior_bytes = archive.read(rows[0]["file"])
        if hashlib.sha256(prior_bytes).hexdigest() != rows[0]["sha256"]:
            raise RuntimeError("prior full Studio Source hash differs from ZIP manifest")
    previous = prior_bytes.decode("utf-8")
    desired = LOCAL.read_text(encoding="utf-8")
    if previous == desired:
        raise RuntimeError("no pending local Source change; do not repeat Studio sync")
    return previous, desired


def job(kind, payload, note):
    outcome = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if outcome.get("status") != "done" or outcome.get("ok") is not True:
        raise RuntimeError(note + " failed; no Studio write permitted")
    return outcome.get("result") or {}


def guard():
    if job("ping", {}, "Vitriol priority sync place guard").get("placeId") != PLACE_ID:
        raise RuntimeError("wrong Studio place")
    if job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"},
           "Vitriol priority sync Edit guard").get("returned") != "false":
        raise RuntimeError("Play/Run active; Edit-only operation refused")


def read_exact():
    inspected = job("inspect", {"path": PATH, "depth": 0}, "Vitriol priority sync class guard")
    if inspected.get("className") != "ModuleScript":
        raise RuntimeError("CreatureService must be an existing ModuleScript")
    result = job("read_scripts", {"paths": [PATH], "maxBytes": 160000},
                 "Vitriol priority sync full Source readback")
    rows = result.get("scripts") or []
    if len(rows) != 1 or rows[0].get("path") != PATH or not isinstance(rows[0].get("source"), str):
        raise RuntimeError("missing or truncated Studio CreatureService Source")
    return rows[0]["source"]


def run(mode, saved_checkpoint):
    previous, desired = plan()
    if mode == "offline":
        print("ONE pending CreatureService Source; ZIP baseline", digest(previous)[:16],
              "local desired", digest(desired)[:16])
        print("Offline plan only; no Studio read/write, Play or cloud save verdict")
        return
    guard()
    actual = read_exact()
    if actual not in (previous, desired):
        raise RuntimeError("Studio Source differs from BOTH exact baseline and intended code; no write")
    if mode == "check":
        print("Read-only Vitriol/Edit:", "already exact" if actual == desired else "guarded and pending")
        return
    if not saved_checkpoint:
        raise RuntimeError("verify Save to Roblox with Notes in Version History before --apply")
    if actual == desired:
        print("Studio Source already exact; no write")
        return
    # Recheck all guards immediately before the SINGLE conditional write.
    guard()
    if LOCAL.read_text(encoding="utf-8") != desired or read_exact() != previous:
        raise RuntimeError("local or Studio Source changed since preflight; refusing write")
    parts = PATH.split(".")
    job("write_script", {"parent": ".".join(parts[:-1]), "name": parts[-1],
                         "className": "ModuleScript", "source": desired},
        "Guarded Vitriol indoor House/Garage priority write")
    guard()
    if read_exact() != desired:
        raise RuntimeError("post-write full Studio Source/class mismatch")
    print("CreatureService full Source/class exact in Vitriol/Edit; NOT a second cloud save or Play verdict")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--offline", action="store_const", const="offline", dest="mode")
    modes.add_argument("--check", action="store_const", const="check", dest="mode")
    modes.add_argument("--apply", action="store_const", const="apply", dest="mode")
    parser.add_argument("--saved-checkpoint-verified", action="store_true")
    args = parser.parse_args()
    try:
        run(args.mode or "offline", args.saved_checkpoint_verified)
        return 0
    except (RuntimeError, ValueError, UnicodeError, OSError, KeyError, zipfile.BadZipFile) as error:
        print("Vitriol priority sync refused:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
