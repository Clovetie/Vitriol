#!/usr/bin/env python3
"""Offline fail-closed checks for one-Module saved-Source ingress sync."""
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("ingress_sync", TOOLS / "sync-house-ingress-lastknown.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class GuardedIngressSync(unittest.TestCase):
    def test_offline_baseline_is_exact_current_saved_source(self):
        old, desired = sync.plan()
        self.assertNotEqual(old, desired)
        self.assertEqual(sync.digest(old)[:16], "f6968a3f7027dac0")
        self.assertIn("LAST-SEEN", desired)
        with patch.object(sync, "request", side_effect=AssertionError("offline called bridge")):
            sync.run("offline", False)

    def test_check_is_read_only(self):
        old, _ = sync.plan()
        with patch.object(sync, "guard") as guard, patch.object(sync, "read_exact", return_value=old), \
             patch.object(sync, "job", side_effect=AssertionError("read-only check wrote")):
            sync.run("check", False)
        guard.assert_called_once()

    def test_requires_verified_save_before_bridge(self):
        with patch.object(sync, "request", side_effect=AssertionError("bridge before attestation")):
            with self.assertRaisesRegex(RuntimeError, "Version History"):
                sync.run("apply", False)

    def test_refuses_unrelated_studio_source_before_any_write(self):
        with patch.object(sync, "guard"), patch.object(sync, "read_exact", return_value="unexpected user edit"), \
             patch.object(sync, "job", side_effect=AssertionError("wrote unrelated Source")):
            with self.assertRaisesRegex(RuntimeError, "BOTH baseline"):
                sync.run("apply", True)

    def test_single_write_rechecked_and_read_back(self):
        old, desired = sync.plan()
        writes = []
        def fake_job(kind, payload, note):
            self.assertEqual(kind, "write_script")
            self.assertEqual(payload["parent"], "ServerStorage.Vitriol.Services")
            self.assertEqual(payload["name"], "CreatureService")
            self.assertEqual(payload["className"], "ModuleScript")
            self.assertEqual(payload["source"], desired)
            writes.append(kind)
            return {}
        with patch.object(sync, "guard") as guard, \
             patch.object(sync, "read_exact", side_effect=[old, old, desired]) as read, \
             patch.object(sync, "job", side_effect=fake_job):
            sync.run("apply", True)
        self.assertEqual(writes, ["write_script"])
        self.assertEqual(guard.call_count, 3)
        self.assertEqual(read.call_count, 3)


if __name__ == "__main__":
    unittest.main()
