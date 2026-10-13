#!/usr/bin/env python3
"""Fail-closed two-Module Edit plan for user-approved recent indoor-clue cover contact.

Offline by default. --check NEVER writes. --apply needs the owner's prior
Save-to-Roblox-with-Notes checkpoint, TWO successful place/Edit guards, exact
full previous Sources/classes from the read-only ZIP, then writes ONLY the two
existing Modules and reads each back. A bridge error stops immediately; a
partial write is NOT auto-retried or silently rolled back. Edit is not Play,
and a Source ZIP is NOT a full-place cloud save. After apply the owner must
make and verify a NEW Save to Roblox with Notes/Version History entry.
Credentials are provided ONLY via environment to studio_bridge.request.
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
BASELINE = ROOT / "backups/vitriol-studio-edit-cover-pre-2026-10-14.zip"
# Pin BOTH sides. Local unrelated edits or current Studio drift refuse the write.
PINS = {
    "ServerStorage.Vitriol.Creature.CreatureCore": (
        "7743b80715e0228f93c72669f31528dcd44aa61a26d18a66aa94d42b6493a365",
        "abe4caa277e9147c6c2a2343cee1223fe7b820c9d78e77a21327ad73df4a4e0c"),
    "ServerStorage.Vitriol.Services.CreatureService": (
        "7621678c1f4ade794f1bf3cca390fa88cafaaea751713be53b671935c028acdc",
        "eada018a1a33f5c47270e13eb8631e6d7c1989c0d4367d83ba4c79051f1e3c7a"),
}


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def plan():
    if subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip() != "main":
        raise RuntimeError("Vitriol main is the only authorized branch")
    with zipfile.ZipFile(BASELINE) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        if manifest.get("placeId") != PLACE_ID or manifest.get("mode") != "Edit":
            raise RuntimeError("wrong place/Edit read-only backup")
        rows = manifest.get("scripts", [])
        if len(rows) != 2 or {row.get("path") for row in rows} != set(PINS):
            raise RuntimeError("wrong two-Source scope")
        prior = {}
        for row in rows:
            path = row["path"]
            if row.get("className") != "ModuleScript" or row.get("file") != path.split(".")[-1] + ".luau":
                raise RuntimeError("wrong class/file in read-only backup")
            raw = archive.read(row["file"])
            if len(raw) != row.get("bytes") or hashlib.sha256(raw).hexdigest() != row.get("sha256"):
                raise RuntimeError("backup Source hash/length mismatch")
            previous = raw.decode("utf-8")
            if digest(previous) != PINS[path][0]:
                raise RuntimeError("unknown previous saved Studio Source")
            prior[path] = previous
    desired = {}
    for path in PINS:
        local = ROOT / "code" / Path(*path.split("."))
        text = local.with_suffix(".luau").read_text(encoding="utf-8")
        if digest(text) != PINS[path][1] or text == prior[path]:
            raise RuntimeError("unverified local candidate for " + path)
        desired[path] = text
    return prior, desired


def job(kind, payload, note):
    response = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if response.get("status") != "done" or response.get("ok") is not True:
        raise RuntimeError(note + " failed: bridge state uncertain; no further writes")
    return response.get("result") or {}


def guard():
    if job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"},
           "Vitriol cover sync Edit guard").get("returned") != "false":
        raise RuntimeError("cannot establish Edit mode; Play/Run unsafe")
    if job("ping", {}, "Vitriol cover sync place guard").get("placeId") != PLACE_ID:
        raise RuntimeError("wrong Vitriol place ID")


def read_exact():
    # inspect/read_scripts are existing legacy bridge operations; never create.
    for path in PINS:
        if job("inspect", {"path": path, "depth": 0},
               "Vitriol cover sync class guard").get("className") != "ModuleScript":
            raise RuntimeError("missing/wrong-class existing ModuleScript " + path)
    result = job("read_scripts", {"paths": list(PINS), "maxBytes": 240000},
                 "Vitriol cover sync exact full Sources")
    rows = result.get("scripts") or []
    if len(rows) != 2 or {row.get("path") for row in rows} != set(PINS):
        raise RuntimeError("missing or partial Studio Sources")
    if any(not isinstance(row.get("source"), str) for row in rows):
        raise RuntimeError("missing Source text")
    return {row["path"]: row["source"] for row in rows}


def run(mode, attested=False):
    prior, desired = plan()
    if mode == "offline":
        print("TWO exact pinned Source changes, offline only:")
        for path in PINS:
            print(path, digest(prior[path])[:16], "->", digest(desired[path])[:16])
        return
    if mode == "apply" and not attested:
        raise RuntimeError("owner's prior cloud checkpoint must be verified before write")
    guard()
    actual = read_exact()
    if all(actual[path] == desired[path] for path in PINS):
        print("two Sources already exact; NO repeat write")
        return
    if any(actual[path] != prior[path] for path in PINS):
        raise RuntimeError("unexpected or partially updated Studio Source; no automatic write/rollback")
    if mode == "check":
        print("read-only two-Source plan: guarded and pending; NO Studio write")
        return
    # Intermittent bridge `loadstring() is not available` has occurred even
    # after owner-confirmed Edit. Revalidate twice and re-read exact Sources;
    # NEVER bypass a failed guard to make progress.
    guard()
    guard()
    if plan() != (prior, desired) or read_exact() != prior:
        raise RuntimeError("local or Studio Sources changed during preflight")
    for path in PINS:
        guard()
        if read_exact()[path] != prior[path]:
            raise RuntimeError("Studio Source changed immediately before write")
        parts = path.split(".")
        job("write_script", {"parent": ".".join(parts[:-1]), "name": parts[-1],
                             "className": "ModuleScript", "source": desired[path]},
            "Guarded Vitriol recent-clue cover existing Source only")
        # If the bridge is unreliable now, STOP. Never send the second write
        # until the first exact Source/class and Edit/place can be verified.
        guard()
        if read_exact()[path] != desired[path]:
            raise RuntimeError("post-write Source/class mismatch; stop before next Module")
        print("exact Edit Source/class", path, digest(desired[path])[:16])
    guard()
    if read_exact() != desired:
        raise RuntimeError("final two-Source mismatch; do NOT Play or save as complete")
    print("Edit sync only. Owner must NEW Save to Roblox with Notes/Version History. NOT Play-verified.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    for mode in ("offline", "check", "apply"):
        group.add_argument("--" + mode, action="store_const", const=mode, dest="mode")
    parser.add_argument("--saved-checkpoint-verified", action="store_true")
    args = parser.parse_args()
    try:
        run(args.mode or "offline", args.saved_checkpoint_verified)
        return 0
    except (RuntimeError, OSError, ValueError, UnicodeError, KeyError, zipfile.BadZipFile) as error:
        print("Vitriol cover sync refused:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
