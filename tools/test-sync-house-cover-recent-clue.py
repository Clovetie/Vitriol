#!/usr/bin/env python3
"""Offline fail-closed checks of the TWO existing-Module recent-clue sync."""
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location("cover_sync", Path(__file__).with_name("sync-house-cover-recent-clue.py"))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class GuardedCoverSync(unittest.TestCase):
    def test_exact_pinned_local_sources_and_backup(self):
        prior, desired = sync.plan()
        self.assertEqual(set(prior), set(sync.PINS))
        for path in sync.PINS:
            self.assertEqual(sync.digest(prior[path]), sync.PINS[path][0])
            self.assertEqual(sync.digest(desired[path]), sync.PINS[path][1])
            self.assertNotEqual(prior[path], desired[path])

    def test_no_attestation_refuses_before_bridge(self):
        with mock.patch.object(sync, "guard") as guard:
            with self.assertRaisesRegex(RuntimeError, "checkpoint"):
                sync.run("apply", False)
            guard.assert_not_called()

    def test_read_only_pending_and_mixed_or_drift_refuse(self):
        prior, desired = sync.plan()
        with mock.patch.object(sync, "guard"), mock.patch.object(sync, "read_exact", return_value=prior), mock.patch.object(sync, "job") as job:
            sync.run("check")
            job.assert_not_called()
        for changed in ({**prior, list(prior)[0]: "unknown"}, {**prior, list(prior)[0]: desired[list(prior)[0]]}):
            with mock.patch.object(sync, "guard"), mock.patch.object(sync, "read_exact", return_value=changed), mock.patch.object(sync, "job") as job:
                with self.assertRaisesRegex(RuntimeError, "unexpected or partially"):
                    sync.run("check")
                job.assert_not_called()

    def test_interrupted_edit_guard_refuses_any_write(self):
        prior, _ = sync.plan()
        with mock.patch.object(sync, "guard", side_effect=[None, RuntimeError("loadstring() is not available")]), mock.patch.object(sync, "read_exact", return_value=prior), mock.patch.object(sync, "job") as job:
            with self.assertRaisesRegex(RuntimeError, "loadstring"):
                sync.run("apply", True)
            job.assert_not_called()

    def test_bridge_failure_after_first_write_stops_second_and_flags_partial(self):
        # A flaky Edit guard must never send a second write after an
        # unverified first. The next read-only check must expose the mixed
        # Source state, not silently call it finished or retry automatically.
        prior, desired = sync.plan()
        current = dict(prior)
        writes = []
        def read():
            return dict(current)
        def write(kind, payload, note):
            self.assertEqual(kind, "write_script")
            path = payload["parent"] + "." + payload["name"]
            current[path] = payload["source"]
            writes.append(path)
            return {}
        guards = [None, None, None, None, RuntimeError("loadstring() is not available")]
        with mock.patch.object(sync, "guard", side_effect=guards), mock.patch.object(sync, "read_exact", side_effect=read), mock.patch.object(sync, "job", side_effect=write):
            with self.assertRaisesRegex(RuntimeError, "loadstring"):
                sync.run("apply", True)
        self.assertEqual(writes, [list(sync.PINS)[0]])
        self.assertEqual(current[writes[0]], desired[writes[0]])
        self.assertEqual(current[list(sync.PINS)[1]], prior[list(sync.PINS)[1]])
        with mock.patch.object(sync, "guard"), mock.patch.object(sync, "read_exact", side_effect=read), mock.patch.object(sync, "job") as job:
            with self.assertRaisesRegex(RuntimeError, "partially updated"):
                sync.run("check")
            job.assert_not_called()

    def test_only_two_existing_modules_written_then_exact_readback(self):
        prior, desired = sync.plan()
        current = dict(prior)
        writes = []
        def read():
            return dict(current)
        def job(kind, payload, note):
            self.assertEqual(kind, "write_script")
            path = payload["parent"] + "." + payload["name"]
            self.assertEqual(payload["className"], "ModuleScript")
            self.assertEqual(current[path], prior[path])
            self.assertEqual(payload["source"], desired[path])
            current[path] = payload["source"]
            writes.append(path)
            return {}
        with mock.patch.object(sync, "guard"), mock.patch.object(sync, "read_exact", side_effect=read), mock.patch.object(sync, "job", side_effect=job):
            sync.run("apply", True)
        self.assertEqual(writes, list(sync.PINS))
        self.assertEqual(current, desired)


if __name__ == "__main__":
    unittest.main()
