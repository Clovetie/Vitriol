#!/usr/bin/env python3
"""Read-only selected Studio Instance-property inventory, NOT a Roblox place.

Run with BRIDGE_URL/BRIDGE_TOKEN in the environment; never persist them. This
captures a useful geometry/asset/UI manifest to complement the Source ZIP.
It cannot preserve terrain voxels, binary mesh/texture/audio content, every
property, relationships not represented in these records, unpublished place
state, a .rbxl, or a cloud Save to Roblox. No restoration is attempted.
"""
import hashlib
import json
import os
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True
from studio_bridge import request

ROOT = Path(__file__).resolve().parent.parent
JOB = ROOT / "jobs/snapshot_edit_properties_vitriol.lua"
OUTPUT = ROOT / "backups/vitriol-studio-edit-selected-properties-2026-10-13.zip"
PLACE_ID = 92448193604950
SERVICES = ("Workspace", "ServerStorage", "ReplicatedStorage", "ServerScriptService",
            "StarterPlayer", "StarterGui", "Lighting", "SoundService",
            "TextChatService", "MaterialService", "StarterPack", "ReplicatedFirst", "Teams")


def job(kind, payload, note):
    result = request("/api/jobs", {"type": kind, "payload": payload, "note": note, "wait": 100})
    if result.get("status") != "done" or result.get("ok") is not True:
        raise RuntimeError(note + " failed; no partial property backup will be saved")
    return result.get("result") or {}


def guard():
    if job("ping", {}, "Vitriol property inventory place guard").get("placeId") != PLACE_ID:
        raise RuntimeError("wrong Studio place; read-only inventory refused")
    state = job("run_luau", {"code": "return tostring(game:GetService('RunService'):IsRunning())"},
                "Vitriol property inventory Edit guard")
    if state.get("returned") != "false":
        raise RuntimeError("Play/Run active; refusing to call it authored Edit data")


def validate(name, result):
    if (result.get("ok") is not True or result.get("mode") != "Edit"
        or result.get("placeId") != PLACE_ID or result.get("root") != name
        or result.get("studioWritten") is not False or result.get("sourceIncluded") is not False
        or result.get("playCaptured") is not False):
        raise RuntimeError(name + ": incomplete/wrong-scope Studio property inventory")
    entries = result.get("entries")
    if not isinstance(entries, list) or result.get("count") != len(entries) or not entries:
        raise RuntimeError(name + ": missing/truncated Instance entries")
    if entries[0].get("index") != 1 or entries[0].get("name") != name:
        raise RuntimeError(name + ": wrong root Instance")
    for idx, entry in enumerate(entries, 1):
        # Roblox HttpService encodes an empty Lua table as [] even when it is
        # used as an attributes/properties map. Normalize ONLY that case.
        for field in ("attributes", "properties"):
            if entry.get(field) == []:
                entry[field] = {}
        if (entry.get("index") != idx or not isinstance(entry.get("fullName"), str)
            or not isinstance(entry.get("className"), str)
            or not isinstance(entry.get("name"), str)
            or not isinstance(entry.get("properties"), dict)
            or not isinstance(entry.get("attributes"), dict)
            or not isinstance(entry.get("tags"), list)):
            raise RuntimeError(name + ": malformed Instance record")
        if idx > 1 and (not isinstance(entry.get("parentIndex"), int)
                        or entry["parentIndex"] < 1 or entry["parentIndex"] >= idx):
            raise RuntimeError(name + ": hierarchy missing an earlier parent")
        if entry["className"] in ("Part", "MeshPart", "UnionOperation", "SpawnLocation"):
            if "CFrame" not in entry["properties"] or "Size" not in entry["properties"]:
                raise RuntimeError(name + ": incomplete BasePart geometry")
    return entries


def run():
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if branch != "main":
        raise RuntimeError("refusing a Vitriol backup outside main")
    source = JOB.read_text(encoding="utf-8")
    if source.count("__ROOT_SERVICE__") != 1:
        raise RuntimeError("property job has ambiguous service placeholder")
    guard()
    captured = {}
    token = os.environ.get("BRIDGE_TOKEN", "")
    for name in SERVICES:
        result = job("run_luau", {"code": source.replace("__ROOT_SERVICE__", name)},
                     "Read-only Vitriol authored properties: " + name)
        try:
            raw = result["returned"]
            decoded = json.loads(raw)
        except (KeyError, TypeError, json.JSONDecodeError) as error:
            raise RuntimeError(name + ": bridge returned no complete JSON inventory") from error
        validate(name, decoded)
        if token and token in raw:
            raise RuntimeError(name + ": bridge credential appeared in attributes; refusing ZIP")
        captured[name] = json.dumps(decoded, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    guard()  # scope guard again; sequential reads are NOT an atomic place snapshot
    manifest = {"placeId": PLACE_ID, "mode": "Edit", "savedAtUtc": datetime.now(timezone.utc).isoformat(),
        "scope": "SELECTED readable Instance properties + hierarchy/tags/attributes only; NOT .rbxl, cloud save, all assets, voxels, complete place or Play",
        "scripts": "classes/paths but no Sources; consult separate 75-script ZIP", "atomic": False, "roots": []}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temp = OUTPUT.with_suffix(".tmp")
    try:
        with zipfile.ZipFile(temp, "w", zipfile.ZIP_DEFLATED) as archive:
            for name in SERVICES:
                data = captured[name]
                file = "StudioProperties/" + name + ".json"
                archive.writestr(file, data)
                rows = json.loads(data)["entries"]
                manifest["roots"].append({"service": name, "file": file,
                    "instances": len(rows), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
            archive.writestr("manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        temp.replace(OUTPUT)
    finally:
        temp.unlink(missing_ok=True)
    print("Read-only selected Studio/Edit property backup:", OUTPUT.relative_to(ROOT),
          "roots", len(SERVICES), "Instance records", sum(row["instances"] for row in manifest["roots"]))
    print("NOT a full place/cloud save, publish, runtime Play capture, asset binary or terrain backup")


if __name__ == "__main__":
    try:
        run()
    except (RuntimeError, ValueError, UnicodeError, OSError, KeyError, zipfile.BadZipFile) as error:
        print("Property inventory refused:", error, file=sys.stderr)
        sys.exit(1)
