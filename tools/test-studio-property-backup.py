#!/usr/bin/env python3
"""Offline integrity/fail-closed checks of selected Edit property inventory."""
import importlib.util
import hashlib
import json
import sys
import unittest
import zipfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("studio_property_backup", TOOLS / "backup-studio-edit-properties.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class PropertyBackupTests(unittest.TestCase):
    def basic(self):
        return {"ok": True, "mode": "Edit", "placeId": backup.PLACE_ID,
            "root": "Workspace", "studioWritten": False, "sourceIncluded": False,
            "playCaptured": False, "count": 2,
            "entries": [{"index": 1, "name": "Workspace", "fullName": "Workspace",
                "className": "Workspace", "tags": [], "attributes": [], "properties": []},
               {"index": 2, "name": "Part_A", "fullName": "Workspace.Part_A",
                "className": "Part", "parentIndex": 1, "tags": [], "attributes": {},
                "properties": {"CFrame": {"type": "CFrame", "components": [0] * 12},
                               "Size": {"type": "Vector3", "components": [1, 1, 1]}}}]}

    def test_empty_lua_maps_normalize_without_erasing_geometry(self):
        result = self.basic()
        entries = backup.validate("Workspace", result)
        self.assertEqual(entries[0]["attributes"], {})
        self.assertEqual(entries[0]["properties"], {})
        self.assertIn("CFrame", entries[1]["properties"])

    def test_wrong_place_or_play_is_not_called_edit_backup(self):
        for key, value in (("placeId", 1), ("mode", "Play"), ("studioWritten", True),
                           ("sourceIncluded", True)):
            result = self.basic()
            result[key] = value
            with self.assertRaisesRegex(RuntimeError, "wrong-scope"):
                backup.validate("Workspace", result)

    def test_missing_geometry_or_broken_parent_refuses_inventory(self):
        result = self.basic()
        del result["entries"][1]["properties"]["CFrame"]
        with self.assertRaisesRegex(RuntimeError, "BasePart geometry"):
            backup.validate("Workspace", result)
        result = self.basic()
        result["entries"][1]["parentIndex"] = 2
        with self.assertRaisesRegex(RuntimeError, "hierarchy"):
            backup.validate("Workspace", result)

    def test_source_zip_and_property_zip_cover_the_same_75_script_instances(self):
        # The two captures were sequential, not a single place snapshot. This
        # only catches missing/renamed/reclassed script *records* between them;
        # it cannot claim matching Sources at the later inventory time.
        source_zip = backup.ROOT / "backups/vitriol-studio-edit-sources-2026-10-13.zip"
        with zipfile.ZipFile(source_zip) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["placeId"], backup.PLACE_ID)
            self.assertEqual(manifest["mode"], "Edit")
            scripts = manifest["scripts"]
            self.assertEqual(len(scripts), 75)
            self.assertEqual(len({row["path"] for row in scripts}), len(scripts))
            for row in scripts:
                raw = archive.read(row["file"])
                self.assertEqual(len(raw), row["bytes"])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), row["sha256"])
        with zipfile.ZipFile(backup.OUTPUT) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["placeId"], backup.PLACE_ID)
            found = []
            for root in manifest["roots"]:
                raw = archive.read(root["file"])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), root["sha256"])
                found.extend(row for row in json.loads(raw)["entries"]
                             if row["className"] in ("Script", "LocalScript", "ModuleScript"))
        self.assertEqual(len(found), len(scripts))
        self.assertEqual(len({row["fullName"] for row in found}), len(found))
        self.assertEqual({(row["fullName"], row["className"]) for row in found},
                         {(row["path"], row["className"]) for row in scripts})

    def test_zip_hashes_and_authored_geometry_are_independently_verifiable(self):
        with zipfile.ZipFile(backup.OUTPUT) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["placeId"], backup.PLACE_ID)
            self.assertFalse(manifest["atomic"])
            self.assertEqual(len(manifest["roots"]), len(backup.SERVICES))
            rows = []
            for root in manifest["roots"]:
                data = archive.read(root["file"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), root["sha256"])
                group = json.loads(data)
                self.assertEqual(len(group["entries"]), root["instances"])
                rows.extend(group["entries"])
        self.assertGreaterEqual(len(rows), 1900)
        by_path = {row["fullName"]: row for row in rows}
        road = by_path["Workspace.Map.Roads.Road_Main"]
        self.assertEqual(road["properties"]["Size"]["components"][2], 593)
        lever = by_path["Workspace.Map.Interactions.Church_BellLever"]
        self.assertEqual(lever["properties"]["CFrame"]["components"][2], -199)
        switch = by_path["Workspace.Map.Interactions.Station_FloodlightSwitch"]
        self.assertEqual(switch["properties"]["CFrame"]["components"][2], -111)
        sound = by_path["Workspace.Map.Interactions.Bell.Bell.Bell.BellRing"]
        self.assertEqual(sound["properties"]["SoundId"], "rbxassetid://130139735590457")
        self.assertIn("Workspace.Dragon_Slayer", by_path)  # Studio-only user Tool


if __name__ == "__main__":
    unittest.main()
