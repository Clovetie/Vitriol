#!/usr/bin/env python3
"""Minimal client for the legacy Arena Studio jobs bridge. Credentials from env only.

Usage: BRIDGE_URL=... BRIDGE_TOKEN=... python tools/studio_bridge.py ping
       ... python tools/studio_bridge.py survey --out survey.json
       ... python tools/studio_bridge.py build tools/studio-build.json
No token is saved or echoed; never commit a survey containing private place data.
"""
import argparse
import json
import os
import sys
from pathlib import Path
import urllib.parse
import urllib.request


def request(path, body=None, timeout=130):
    base = os.environ.get("BRIDGE_URL", "").rstrip("/")
    token = os.environ.get("BRIDGE_TOKEN", "")
    if not base.startswith("https://") or not token:
        raise ValueError("Set BRIDGE_URL (https) and BRIDGE_TOKEN in the environment")
    url = base + path + "?" + urllib.parse.urlencode({"token": token})
    payload = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if payload is not None else {}
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=payload, headers=headers), timeout=timeout) as response:
            return json.load(response)
    except Exception:
        # urllib exception text can contain the token-bearing URL: never echo it.
        raise RuntimeError("Studio bridge request failed (check health/connection)") from None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("command", choices=["health", "state", "ping", "survey", "inspect", "read", "reads", "runfile", "build", "console", "parity", "sync"])
    p.add_argument("argument", nargs="?")
    p.add_argument("--out")
    p.add_argument("--depth", type=int, default=2)
    args = p.parse_args()
    if args.command in ("parity", "sync"):
        code = Path(__file__).resolve().parent.parent / "code"
        files = sorted(code.rglob("*.luau"))
        if args.command == "sync":
            # Fail closed if a different place is connected, or Play is active.
            probe = request("/api/jobs", {"type": "ping", "payload": {}, "note": "Vitriol sync target check", "wait": 25})
            if probe.get("status") != "done" or probe.get("result", {}).get("placeId") != 92448193604950:
                raise RuntimeError("Refusing sync: connected Studio placeId is not the verified Vitriol place")
            state = request("/api/jobs", {"type": "run_luau", "payload": {"code": "return tostring(game:GetService('RunService'):IsRunning())"}, "note": "Vitriol sync Edit-mode check", "wait": 25})
            if state.get("status") != "done" or state.get("result", {}).get("returned") != "false":
                raise RuntimeError("Refusing sync: stop Play/Run before modifying scripts")
            if not args.argument:
                p.error("sync requires comma-separated paths relative to code/, without .luau")
            selected = set(args.argument.split(","))
            files = [f for f in files if str(f.relative_to(code).with_suffix("")) in selected]
            if len(files) != len(selected):
                p.error("one or more sync paths are not in code/")
            for file in files:
                rel = file.relative_to(code).with_suffix("")
                parent, name = rel.parts[:-1], rel.parts[-1]
                # ClientMain is executable; its Controllers are required modules.
                # Classifying every StarterPlayer descendant as a LocalScript
                # caused LightingDriver to be authored with the wrong class and
                # made ClientMain's require() fail before binding RE_TimeSync.
                typ = ("Script" if rel.parts[0] == "ServerScriptService" else
                       "LocalScript" if rel.parts[0] == "StarterPlayer" and rel.name == "ClientMain" else
                       "ModuleScript")
                j = request("/api/jobs", {"type": "write_script", "payload": {"parent": ".".join(parent), "name": name, "className": typ, "source": file.read_text()}, "note": "Vitriol main -> " + str(rel), "wait": 80})
                print(str(rel), j.get("status"), j.get("error"))
                if j.get("status") != "done":
                    return 1
                # write_script can succeed on an existing wrong-class Instance
                # without converting it. Read back the class; source parity alone
                # cannot detect an unrequireable LocalScript controller.
                actual_path = ".".join(rel.parts)
                check = request("/api/jobs", {"type": "inspect", "payload": {"path": actual_path, "depth": 0}, "note": "Vitriol script class check", "wait": 25})
                actual_class = check.get("result", {}).get("className") if check.get("status") == "done" else None
                if actual_class != typ:
                    raise RuntimeError(f"Refusing wrong-class script {actual_path}: expected {typ}, got {actual_class}")
            return 0
        differences = []
        for index in range(0, len(files), 5):
            batch = files[index:index + 5]
            paths = [".".join(f.relative_to(code).with_suffix("").parts) for f in batch]
            j = request("/api/jobs", {"type": "read_scripts", "payload": {"paths": paths, "maxBytes": 450000}, "note": "Vitriol main parity", "wait": 80})
            if j.get("status") != "done":
                raise RuntimeError("read_scripts failed: " + str(j.get("error")))
            by_path = {entry["path"]: entry for entry in j["result"]["scripts"]}
            for file, path in zip(batch, paths):
                studio = by_path.get(path, {})
                if studio.get("source") is None or studio["source"].rstrip("\n") != file.read_text().rstrip("\n"):
                    differences.append(path)
        print(json.dumps({"checked": len(files), "drift": differences}, indent=2))
        return int(bool(differences))
    if args.command in ("health", "state"):
        result = request("/api/" + args.command)
    else:
        cmd = args.command
        spec = {
            "ping": ("ping", {}),
            "survey": ("survey", {"maxScriptBytes": 0, "includeSource": False}),
            "inspect": ("inspect", {"path": args.argument or "game", "depth": args.depth}),
            "read": ("read_script", {"path": args.argument}),
            "reads": ("read_scripts", {"paths": (args.argument or "").split(",")}),
            "console": ("console", {"limit": 100}),
        }
        if cmd in ("build", "runfile"):
            if not args.argument:
                p.error("missing input file")
            with open(args.argument, encoding="utf-8") as f:
                payload = json.load(f) if cmd == "build" else {"code": f.read()}
            typ = "build" if cmd == "build" else "run_luau"
        else:
            typ, payload = spec[cmd]
        result = request("/api/jobs", {"type": typ, "payload": payload, "note": "Vitriol " + cmd, "wait": 100})
        if result.get("status") != "done":
            print(json.dumps(result, indent=2))
            return 1
    output = json.dumps(result, indent=2, ensure_ascii=False)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(output + "\n")
        print("Wrote", args.out)
    else:
        print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
