#!/usr/bin/env python3
"""Guarded two-Module Vitriol/Edit sync PLAN; no writes by default.

--offline: validate exact historical Studio Source ZIP and local desired files.
--check: read both existing Studio Modules, class, place, Edit mode, full Source.
--apply --saved-checkpoint-verified: ONLY after a human verifies the
CURRENT full-place checkpoint in Version History (Save to Roblox with Notes,
or a published place version if the owner explicitly authorizes its use).
The flag is an operator attestation, not bridge proof of the UI/cloud version.
After exact Source readback, Save to Roblox with Notes and verify the
new post-sync checkpoint; Edit readback alone does not persist the fixes.
Both Modules are checked BEFORE any write, rechecked immediately per write,
then read back exactly. Never use to sync other files or modify geometry.
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
BASELINE = ROOT / "backups/vitriol-studio-edit-sources-2026-10-13.zip"
TARGETS = (
    "ServerStorage.Vitriol.Services.CreatureService",
    "ServerStorage.Vitriol.Creature.ChurchNavigation",
)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def plan():
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if branch != "main":
        raise RuntimeError("refusing a Studio sync outside Vitriol main")
    with zipfile.ZipFile(BASELINE) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        if manifest.get("placeId") != PLACE_ID or manifest.get("mode") != "Edit":
            raise RuntimeError("historical Studio ZIP has wrong place or mode")
        rows = manifest.get("scripts") or []
        result = {}
        for path in TARGETS:
            match = [row for row in rows if row.get("path") == path]
            if len(match) != 1 or match[0].get("className") != "ModuleScript":
                raise RuntimeError("missing/ambiguous prior Studio ModuleScript: " + path)
            raw = archive.read(match[0]["file"])
            if hashlib.sha256(raw).hexdigest() != match[0]["sha256"]:
                raise RuntimeError("historical Studio Source hash mismatch: " + path)
            local = ROOT / "code" / Path(*path.split(".")).with_suffix(".luau")
            result[path] = (raw.decode("utf-8"), local.read_text(encoding="utf-8"), local)
    if not any(old != new for old, new, _ in result.values()):
        raise RuntimeError("no pending local Source; avoid repeating a Studio sync")
    return result


def job(kind, payload, note):
    outcome = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if outcome.get("status") != "done" or outcome.get("ok") is not True:
        raise RuntimeError(note + " failed; no further Studio writes")
    return outcome.get("result") or {}


def guard():
    if job("ping", {}, "Vitriol House/Church sync place guard").get("placeId") != PLACE_ID:
        raise RuntimeError("wrong Studio place")
    if job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"},
           "Vitriol House/Church sync Edit guard").get("returned") != "false":
        raise RuntimeError("Play/Run active; Edit-only sync refused")


def read(paths):
    for path in paths:
        result = job("inspect", {"path": path, "depth": 0}, "Vitriol House/Church class guard")
        if result.get("className") != "ModuleScript":
            raise RuntimeError("existing ModuleScript class required: " + path)
    result = job("read_scripts", {"paths": list(paths), "maxBytes": 160000},
                 "Vitriol House/Church full Studio Sources")
    rows = result.get("scripts") or []
    if len(rows) != len(paths) or len({row.get("path") for row in rows}) != len(paths):
        raise RuntimeError("partial or duplicate Studio Source readback")
    sources = {row.get("path"): row.get("source") for row in rows}
    if any(not isinstance(sources.get(path), str) for path in paths):
        raise RuntimeError("missing/truncated Studio Source")
    return sources


def run(mode, attested):
    pending = plan()
    if mode == "offline":
        for path, (old, new, _) in pending.items():
            print(path, "baseline", digest(old)[:16], "local", digest(new)[:16],
                  "pending" if old != new else "unchanged")
        print("Offline ONLY; no bridge read/write, cloud save or Play verdict")
        return
    if mode == "apply" and not attested:
        raise RuntimeError("first verify the owner-approved full-place checkpoint in Version History; no write")
    guard()
    actual = read(TARGETS)
    if any(actual[path] not in pending[path][:2] for path in TARGETS):
        raise RuntimeError("Studio Source differs from BOTH baseline and intended local Source; no write")
    if mode == "check":
        for path in TARGETS:
            print(path, "already exact" if actual[path] == pending[path][1] else "guarded and pending")
        print("Read-only Vitriol/Edit; no Studio write or Play verdict")
        return
    for path in TARGETS:
        previous, desired, local = pending[path]
        if actual[path] == desired:
            continue
        guard()
        if local.read_text(encoding="utf-8") != desired or read([path])[path] != previous:
            raise RuntimeError("local or Studio Source changed before single guarded write: " + path)
        parts = path.split(".")
        job("write_script", {"parent": ".".join(parts[:-1]), "name": parts[-1],
                             "className": "ModuleScript", "source": desired},
            "Guarded Vitriol House/Church ModuleScript write")
        guard()
        if read([path])[path] != desired:
            raise RuntimeError("post-write full Source/class mismatch: " + path)
        print(path, "exact full Studio Source/class", digest(desired)[:16])
    guard()
    final = read(TARGETS)
    if any(final[path] != pending[path][1] for path in TARGETS):
        raise RuntimeError("final two-Module Studio Source readback mismatch")
    print("Two Vitriol/Edit ModuleScripts exact; NOT a post-sync cloud save, publish or live Play verdict")
    print("NEXT: Save to Roblox with Notes and verify the new Version History checkpoint")


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
        print("Vitriol House/Church sync refused:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
