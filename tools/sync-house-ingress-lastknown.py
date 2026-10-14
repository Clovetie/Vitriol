#!/usr/bin/env python3
"""Guarded ONE-Module Vitriol/Edit plan for genuinely remembered House ingress.

--offline checks a READ-ONLY snapshot of the exact CURRENT saved Studio Source.
--check reads place/Edit/class/full Source and does NOT write.
--apply --saved-checkpoint-verified needs the owner's already-confirmed
post-previous-sync Save to Roblox with Notes in Version History. The bridge
cannot verify this UI action. This flag is a human operator attestation,
NOT proof of a cloud save. A successful Edit write also needs a NEW Save to
Roblox with Notes and Version History check to protect this new change.
Only existing CreatureService may be written. No geometry or other Source.
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
BASELINE = ROOT / "backups/vitriol-studio-edit-creature-pre-ingress-2026-10-13.zip"
LOCAL = ROOT / "code/ServerStorage/Vitriol/Services/CreatureService.luau"


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def plan():
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if branch != "main":
        raise RuntimeError("refusing a Vitriol sync outside main")
    with zipfile.ZipFile(BASELINE) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        if (manifest.get("placeId") != PLACE_ID or manifest.get("mode") != "Edit"
            or manifest.get("path") != PATH or manifest.get("className") != "ModuleScript"
            or manifest.get("file") != "CreatureService.luau"):
            raise RuntimeError("wrong-scope Studio Source baseline")
        raw = archive.read(manifest["file"])
        if len(raw) != manifest.get("bytes") or hashlib.sha256(raw).hexdigest() != manifest.get("sha256"):
            raise RuntimeError("baseline Source hash/length mismatch")
    previous = raw.decode("utf-8")
    if not digest(previous).startswith("f6968a3f7027dac0"):
        raise RuntimeError("not the saved post-House/Church Source; refuse sync")
    desired = LOCAL.read_text(encoding="utf-8")
    if previous == desired:
        raise RuntimeError("no pending local Source; avoid repeat write")
    return previous, desired


def job(kind, payload, note):
    result = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if result.get("status") != "done" or result.get("ok") is not True:
        raise RuntimeError(note + " failed; no Studio write")
    return result.get("result") or {}


def guard():
    if job("ping", {}, "Vitriol ingress sync place guard").get("placeId") != PLACE_ID:
        raise RuntimeError("wrong Studio place")
    if job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"},
           "Vitriol ingress sync Edit guard").get("returned") != "false":
        raise RuntimeError("Play/Run active; Edit-only sync refused")


def read_exact():
    inspected = job("inspect", {"path": PATH, "depth": 0}, "Vitriol ingress sync class guard")
    if inspected.get("className") != "ModuleScript":
        raise RuntimeError("existing CreatureService ModuleScript required")
    result = job("read_scripts", {"paths": [PATH], "maxBytes": 160000},
                 "Vitriol ingress sync full Source readback")
    rows = result.get("scripts") or []
    if len(rows) != 1 or rows[0].get("path") != PATH or not isinstance(rows[0].get("source"), str):
        raise RuntimeError("missing/partial Studio Source")
    return rows[0]["source"]


def run(mode, attested):
    previous, desired = plan()
    if mode == "offline":
        print("CreatureService prior saved", digest(previous)[:16], "local candidate", digest(desired)[:16])
        print("Offline ONLY; no bridge read/write, cloud save or live Play verdict")
        return
    if mode == "apply" and not attested:
        raise RuntimeError("verify owner-approved saved place checkpoint in Version History before --apply")
    guard()
    actual = read_exact()
    if actual not in (previous, desired):
        raise RuntimeError("Studio Source differs from BOTH baseline and intended local Source; no write")
    if mode == "check":
        print("Read-only Vitriol/Edit:", "already exact" if actual == desired else "guarded and pending")
        return
    if actual == desired:
        print("already exact; no repeat write")
        return
    guard()
    if LOCAL.read_text(encoding="utf-8") != desired or read_exact() != previous:
        raise RuntimeError("local or Studio Source changed before guarded write")
    job("write_script", {"parent": "ServerStorage.Vitriol.Services", "name": "CreatureService",
                         "className": "ModuleScript", "source": desired},
        "Guarded Vitriol genuine-last-clue ingress Source")
    guard()
    if read_exact() != desired:
        raise RuntimeError("post-write full Source/class mismatch")
    print("CreatureService exact Studio Source/class", digest(desired)[:16])
    print("NOT saved to Roblox or Play-verified; NEW Save to Roblox with Notes/Version History needed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    for flag in ("offline", "check", "apply"):
        mode.add_argument("--" + flag, action="store_const", const=flag, dest="mode")
    parser.add_argument("--saved-checkpoint-verified", action="store_true")
    args = parser.parse_args()
    try:
        run(args.mode or "offline", args.saved_checkpoint_verified)
        return 0
    except (RuntimeError, ValueError, UnicodeError, OSError, KeyError, zipfile.BadZipFile) as error:
        print("Vitriol ingress sync refused:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
