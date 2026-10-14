#!/usr/bin/env python3
"""Offline fail-closed two-Module sync tests; never contact Studio."""
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("pending_house_church", TOOLS / "sync-pending-house-church.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.entries = mod.plan()
        self.paths = mod.TARGETS

    def test_two_exact_historical_studio_sources_are_pending_offline(self):
        self.assertEqual(set(self.entries), set(self.paths))
        self.assertTrue(all(old != new for old, new, _ in self.entries.values()))
        with patch.object(mod, "request", side_effect=AssertionError("offline bridge call")):
            mod.run("offline", False)

    def test_readonly_check_never_writes(self):
        old = {p: self.entries[p][0] for p in self.paths}
        with patch.object(mod, "guard") as guard, patch.object(mod, "read", return_value=old), \
             patch.object(mod, "job", side_effect=AssertionError("check wrote Studio")):
            mod.run("check", False)
        guard.assert_called_once()

    def test_apply_requires_human_verified_checkpoint_before_bridge(self):
        with patch.object(mod, "request", side_effect=AssertionError("bridge before checkpoint")):
            with self.assertRaisesRegex(RuntimeError, "checkpoint in Version History"):
                mod.run("apply", False)

    def test_both_full_sources_checked_before_first_write(self):
        drift = {p: self.entries[p][0] for p in self.paths}
        drift[self.paths[1]] = "-- unrelated Studio edit"
        with patch.object(mod, "guard"), patch.object(mod, "read", return_value=drift), \
             patch.object(mod, "job", side_effect=AssertionError("wrote before full preflight")):
            with self.assertRaisesRegex(RuntimeError, "BOTH baseline"):
                mod.run("apply", True)

    def test_first_readback_failure_stops_before_second_write(self):
        # A two-Source Studio write is sequential, never atomic. A bad first
        # readback must not touch the second Module or claim full completion.
        old = {p: self.entries[p][0] for p in self.paths}
        written = []
        def fake_read(paths):
            return {path: old[path] for path in paths}
        def fake_job(kind, payload, note):
            self.assertEqual(kind, "write_script")
            written.append(payload["parent"] + "." + payload["name"])
            return {}
        with patch.object(mod, "guard"), patch.object(mod, "read", side_effect=fake_read), \
             patch.object(mod, "job", side_effect=fake_job):
            with self.assertRaisesRegex(RuntimeError, "post-write full Source/class mismatch"):
                mod.run("apply", True)
        self.assertEqual(written, [self.paths[0]])

    def test_each_write_is_guarded_and_read_back_then_final_both(self):
        old = {p: self.entries[p][0] for p in self.paths}
        new = {p: self.entries[p][1] for p in self.paths}
        written = []
        def fake_read(paths):
            if len(paths) == 2:
                return new if len(written) == 2 else old
            p = paths[0]
            return {p: new[p] if p in written else old[p]}
        def fake_job(kind, payload, note):
            self.assertEqual(kind, "write_script")
            p = payload["parent"] + "." + payload["name"]
            self.assertIn(p, self.paths)
            self.assertNotIn(p, written)
            self.assertEqual(payload["className"], "ModuleScript")
            self.assertEqual(payload["source"], new[p])
            written.append(p)
            return {}
        with patch.object(mod, "guard") as guard, patch.object(mod, "read", side_effect=fake_read), \
             patch.object(mod, "job", side_effect=fake_job):
            mod.run("apply", True)
        self.assertEqual(written, list(self.paths))
        self.assertEqual(guard.call_count, 6) # initial, two per write, final


if __name__ == "__main__":
    unittest.main()
