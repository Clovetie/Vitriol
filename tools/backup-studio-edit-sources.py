#!/usr/bin/env python3
"""Read-only Vitriol/Edit backup of all Studio Script Sources, not the place.

Requires BRIDGE_URL and BRIDGE_TOKEN in the environment. Never writes to
Studio, saves credentials, or pretends the resulting ZIP is a full .rbxl.
"""
import hashlib
import json
import os
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True
from studio_bridge import request

ROOT = Path(__file__).resolve().parent.parent
PLACE_ID = 92448193604950
OUTPUT = ROOT / "backups" / "vitriol-studio-edit-sources-2026-10-13.zip"


def job(kind, payload, note):
    result = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if result.get("status") != "done" or result.get("ok") is not True:
        raise RuntimeError(note + " failed; no partial backup will be presented")
    return result.get("result") or {}


def guard():
    if job("ping", {}, "Vitriol source backup place guard").get("placeId") != PLACE_ID:
        raise RuntimeError("wrong place; refusing backup")
    state = job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"},
                "Vitriol source backup Edit guard")
    if state.get("returned") != "false":
        raise RuntimeError("Play/Run is active; no Edit source snapshot")


def run():
    guard()
    survey = job("survey", {"maxScriptBytes": 0, "includeSource": False},
                 "Vitriol source backup read-only survey")
    rows = survey.get("scripts") or []
    by_path = {}
    for row in rows:
        name = row.get("path")
        if not isinstance(name, str) or not name or name in by_path or row.get("className") not in (
            "Script", "LocalScript", "ModuleScript"
        ):
            raise RuntimeError("duplicate/invalid script path or class in survey")
        by_path[name] = row["className"]
    if len(by_path) < 61:
        raise RuntimeError("incomplete script survey; refusing partial backup")
    sources = {}
    paths = sorted(by_path)
    for start in range(0, len(paths), 5):
        batch = paths[start:start + 5]
        result = job("read_scripts", {"paths": batch, "maxBytes": 450000},
                     "Vitriol source backup exact readback")
        entries = result.get("scripts") or []
        if len(entries) != len(batch):
            raise RuntimeError("partial Source readback; refusing partial backup")
        found = {item.get("path"): item.get("source") for item in entries}
        if any(not isinstance(found.get(name), str) for name in batch):
            raise RuntimeError("missing Source; refusing partial backup")
        sources.update(found)
    # Read-only final mode/place guard. The ZIP backs up source snapshots only;
    # no promise about unrelated property/geometry changes during the read.
    guard()
    secret = os.environ.get("BRIDGE_TOKEN", "")
    if secret and any(secret in value for value in sources.values()):
        raise RuntimeError("a Studio Source contains the bridge token; refusing to archive it")
    manifest = {"placeId": PLACE_ID, "mode": "Edit", "savedAtUtc": datetime.now(timezone.utc).isoformat(),
                "scope": "script Sources/classes only; NOT a saved Roblox place or player data",
                "scripts": []}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temp = OUTPUT.with_suffix(".tmp")
    try:
        with zipfile.ZipFile(temp, "w", zipfile.ZIP_DEFLATED) as archive:
            for index, path in enumerate(paths):
                content = sources[path].encode("utf-8")
                # Indexed filenames avoid ambiguity when authored names contain
                # spaces/dots; manifest carries the complete original path.
                safe_name = re.sub(r"[^A-Za-z0-9_-]", "_", path.split(".")[-1])[:60]
                entry = f"StudioScripts/{index:03d}_{safe_name}.luau"
                archive.writestr(entry, content)
                manifest["scripts"].append({"path": path, "className": by_path[path],
                    "file": entry, "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()})
            archive.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        temp.replace(OUTPUT)
    finally:
        temp.unlink(missing_ok=True)
    print("Read-only Edit backup:", OUTPUT.relative_to(ROOT), "scripts", len(paths),
          "source bytes", sum(item["bytes"] for item in manifest["scripts"]))
    print("NOT a place save, publish, or DataStore backup")


if __name__ == "__main__":
    try:
        run()
    except Exception as error:
        # request() suppresses token-bearing URLs; do not print raw job payloads.
        print("Source backup refused:", error, file=sys.stderr)
        sys.exit(1)
