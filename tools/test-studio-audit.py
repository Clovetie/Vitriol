#!/usr/bin/env python3
"""Offline fail-closed tests for the read-only Studio audit; no bridge credentials needed."""
import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("vitriol_studio_audit", TOOLS / "vitriol-studio-audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.name = "StarterPlayer.StarterPlayerScripts.Vitriol.ClientMain"
        self.file = audit.CODE / "StarterPlayer/StarterPlayerScripts/Vitriol/ClientMain.luau"
        self.expected = {self.name: (self.file, "LocalScript")}
        self.survey_class = "LocalScript"
        self.source = self.file.read_text(encoding="utf-8")
        self.mode = "false"
        self.verifier_ok = True
        self.calls = []

    def fake_job(self, kind, payload, note):
        self.calls.append((kind, note))
        if kind == "ping":
            return {"placeId": audit.PLACE_ID}
        if note.endswith("Edit-mode check"):
            return {"returned": self.mode}
        if kind == "run_luau":
            return {"returned": json.dumps({"ok": self.verifier_ok, "defects": ["fixture"] if not self.verifier_ok else []})}
        if kind == "survey":
            return {"scripts": [{"path": self.name, "className": self.survey_class}]}
        if kind == "read_scripts":
            return {"scripts": [{"path": self.name, "source": self.source}]}
        raise AssertionError((kind, note))

    def run_fixture(self):
        with patch.object(audit, "job", self.fake_job), patch.object(audit, "scripts", lambda: self.expected):
            return audit.run()

    def test_success_checks_verifiers_classes_and_source(self):
        result = self.run_fixture()
        self.assertTrue(result["passed"])
        self.assertEqual(result["scripts"]["sourceChecked"], 1)
        self.assertEqual(sum(1 for kind, _ in self.calls if kind == "run_luau"), len(audit.VERIFIERS) + 1)

    def test_refuses_play(self):
        self.mode = "true"
        with self.assertRaisesRegex(RuntimeError, "stop Play"):
            self.run_fixture()
        self.assertNotIn("survey", [kind for kind, _ in self.calls])

    def test_refuses_verifier_defect_but_collects_read_only_evidence(self):
        self.verifier_ok = False
        with self.assertRaisesRegex(audit.AuditFailure, "reported defects") as context:
            self.run_fixture()
        self.assertEqual(len(context.exception.report["verifiers"]), len(audit.VERIFIERS))
        self.assertEqual(context.exception.report["scripts"]["sourceChecked"], 1)
        self.assertFalse(context.exception.report["passed"])
        self.assertIn("survey", [kind for kind, _ in self.calls])

    def test_refuses_wrong_script_class(self):
        self.survey_class = "ModuleScript"
        with self.assertRaisesRegex(RuntimeError, "wrong-class"):
            self.run_fixture()
        self.assertNotIn("read_scripts", [kind for kind, _ in self.calls])

    def test_refuses_source_drift(self):
        self.source = "-- stale Studio source"
        with self.assertRaisesRegex(audit.AuditFailure, "source drift") as context:
            self.run_fixture()
        self.assertEqual(context.exception.report["scripts"]["drift"], [self.name])

    def test_exact_bytes_do_not_ignore_whitespace_or_newlines(self):
        self.source += "\n"
        with self.assertRaisesRegex(audit.AuditFailure, "source drift"):
            self.run_fixture()

    def test_records_one_missing_studio_terminal_lf_without_masking_interior_edits(self):
        self.assertTrue(self.source.endswith("\n"))
        self.source = self.source[:-1]
        result = self.run_fixture()
        self.assertEqual(result["scripts"]["terminalNewlineOnly"], [self.name])
        self.assertEqual(result["scripts"]["exact"], 0)
        self.assertTrue(result["passed"])
        self.assertEqual(audit.source_verdict(self.name, self.source.replace("\n", "\n\n", 1),
                                              self.file.read_text(encoding="utf-8")), "unexpected")

    def test_preserves_only_pinned_studio_sources(self):
        import zipfile
        import hashlib
        backup = audit.ROOT / "backups/vitriol-studio-edit-sources-2026-10-13.zip"
        with zipfile.ZipFile(backup) as archive:
            manifest = {row["path"]: row for row in json.loads(archive.read("manifest.json"))["scripts"]}
            for name, (local_hash, studio_hash, _) in audit.PRESERVED_SOURCES.items():
                local = (audit.CODE / Path(*name.split("."))).with_suffix(".luau").read_text(encoding="utf-8")
                if name.endswith(".DayNightConfig"):
                    # The owner explicitly confirmed the NEW 70-second Night;
                    # retain the original 200-second ZIP as historical evidence.
                    current = audit.ROOT / "backups/vitriol-studio-edit-daynight-70-2026-10-13.zip"
                    with zipfile.ZipFile(current) as later:
                        row = json.loads(later.read("manifest.json"))
                        self.assertEqual(row["path"], name)
                        self.assertEqual(row["placeId"], audit.PLACE_ID)
                        self.assertEqual(row["mode"], "Edit")
                        studio_bytes = later.read(row["file"])
                        self.assertEqual(len(studio_bytes), row["bytes"])
                        self.assertEqual(hashlib.sha256(studio_bytes).hexdigest(), row["sha256"])
                        studio = studio_bytes.decode("utf-8")
                else:
                    studio = archive.read(manifest[name]["file"]).decode("utf-8")
                self.assertEqual(hashlib.sha256(local.encode()).hexdigest(), local_hash)
                self.assertEqual(hashlib.sha256(studio.encode()).hexdigest(), studio_hash)
                self.assertEqual(audit.source_verdict(name, studio, local), "preserved")
                self.assertEqual(audit.source_verdict(name, studio + "\n", local), "unexpected")
                self.assertEqual(audit.source_verdict(name, studio, local + "\n"), "unexpected")
                self.assertEqual(audit.source_verdict("Other." + name, studio, local), "unexpected")

    def test_refuses_duplicate_source_rows(self):
        def bad_job(kind, payload, note):
            result = self.fake_job(kind, payload, note)
            if kind == "read_scripts":
                result["scripts"].append(dict(result["scripts"][0]))
            return result
        with patch.object(audit, "job", bad_job), patch.object(audit, "scripts", lambda: self.expected):
            with self.assertRaisesRegex(RuntimeError, "partial or duplicated"):
                audit.run()


if __name__ == "__main__":
    unittest.main()
