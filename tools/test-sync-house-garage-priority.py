#!/usr/bin/env python3
"""Offline fail-closed checks for the ONE-Module priority sync. No bridge calls."""
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("priority_sync", TOOLS / "sync-house-garage-priority.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class GuardedSyncTests(unittest.TestCase):
    def test_real_offline_plan_from_exact_zip_hash(self):
        previous, desired = sync.plan()
        self.assertNotEqual(previous, desired)
        self.assertIn("house and noFreshClue", desired)
        with patch.object(sync, "request", side_effect=AssertionError("offline made bridge call")):
            sync.run("offline", False)

    def test_check_is_read_only_when_pending(self):
        desired = sync.LOCAL.read_text(encoding="utf-8")
        with patch.object(sync, "plan", return_value=("old", desired)), \
             patch.object(sync, "guard") as guard, \
             patch.object(sync, "read_exact", return_value="old") as read, \
             patch.object(sync, "job", side_effect=AssertionError("check wrote Studio")):
            sync.run("check", False)
        guard.assert_called_once()
        read.assert_called_once()

    def test_refuses_apply_without_human_verified_place_checkpoint(self):
        desired = sync.LOCAL.read_text(encoding="utf-8")
        with patch.object(sync, "plan", return_value=("old", desired)), \
             patch.object(sync, "guard"), patch.object(sync, "read_exact", return_value="old"), \
             patch.object(sync, "job", side_effect=AssertionError("wrote without save attestation")):
            with self.assertRaisesRegex(RuntimeError, "Save to Roblox with Notes"):
                sync.run("apply", False)

    def test_refuses_unrelated_studio_source_even_with_save_attestation(self):
        desired = sync.LOCAL.read_text(encoding="utf-8")
        with patch.object(sync, "plan", return_value=("old", desired)), \
             patch.object(sync, "guard"), patch.object(sync, "read_exact", return_value="user edit"), \
             patch.object(sync, "job", side_effect=AssertionError("overwrote user Source")):
            with self.assertRaisesRegex(RuntimeError, "BOTH exact baseline"):
                sync.run("apply", True)

    def test_one_write_requires_guard_and_full_source_readback(self):
        desired = sync.LOCAL.read_text(encoding="utf-8")
        writes = []
        with patch.object(sync, "plan", return_value=("old", desired)), \
             patch.object(sync, "guard") as guard, \
             patch.object(sync, "read_exact", side_effect=["old", "old", desired]) as read, \
             patch.object(sync, "job", side_effect=lambda kind, payload, note: writes.append((kind, payload)) or {}) :
            sync.run("apply", True)
        self.assertEqual(guard.call_count, 3)
        self.assertEqual(read.call_count, 3)
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0][0], "write_script")
        self.assertEqual(writes[0][1]["source"], desired)
        self.assertEqual(writes[0][1]["className"], "ModuleScript")


if __name__ == "__main__":
    unittest.main()
