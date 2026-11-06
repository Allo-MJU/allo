"""Offline CLI checks; all IDs and payloads here are synthetic."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


TEST_DIR = Path(__file__).resolve().parent
SCRIPT = TEST_DIR.parent / "cleanup_sessions_dry_run.py"
FIXTURE = TEST_DIR / "fixtures" / "cleanup_sessions.json"
NOW_MS = "1793761200000"  # 2026-11-04 03:00:00 UTC, fixed for reproducibility.


class CleanupSessionsTest(unittest.TestCase):
    def run_cli(self, path, now=NOW_MS):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path), "--now-ms", now],
            capture_output=True, text=True, check=False,
        )

    def run_input(self, content, now=NOW_MS):
        with tempfile.TemporaryDirectory(dir=TEST_DIR) as directory:
            path = Path(directory) / "private-input.json"
            path.write_text(content, encoding="utf-8")
            return self.run_cli(path, now)

    def test_fixture_counts_and_privacy(self):
        result = self.run_cli(FIXTURE)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["dry_run"])
        self.assertEqual(report["policy"], "issue_23_proposal_not_approved")
        self.assertEqual(report["cutoff_ms"], 1793674800000)
        self.assertEqual(report["total_sessions"], 21)
        self.assertEqual(report["counts"], {"candidate": 5, "keep": 4, "review": 12})
        self.assertEqual(report["reasons"], {
            "expired_24h": 3, "recent": 4, "orphan_missing_meta": 2,
            "missing_created_at": 2, "invalid_created_at_type": 4,
            "invalid_meta": 2, "invalid_created_at_value": 1,
            "future_created_at": 1, "invalid_session": 2,
        })
        self.assertEqual(result.stderr, "")
        for session_id in json.loads(FIXTURE.read_text(encoding="utf-8")):
            self.assertNotIn(session_id, result.stdout)
        self.assertNotIn("must-not-log-payload", result.stdout + result.stderr)

    def test_each_fixture_session_is_classified_independently(self):
        expected = {
            "sid_expired_old": "expired_24h",
            "sid_boundary_before": "recent",  # age 24h - 1ms
            "sid_boundary_exact": "expired_24h",  # age exactly 24h
            "sid_boundary_after": "expired_24h",  # age 24h + 1ms
            "sid_normal": "recent", "sid_now": "recent", "sid_fractional_ms": "recent",
            "sid_orphan_vehicle": "orphan_missing_meta",
            "sid_orphan_null_meta": "orphan_missing_meta",
            "sid_missing_created_at": "missing_created_at",
            "sid_null_created_at": "missing_created_at",
            "sid_string_created_at": "invalid_created_at_type",
            "sid_boolean_created_at": "invalid_created_at_type",
            "sid_array_created_at": "invalid_created_at_type",
            "sid_object_created_at": "invalid_created_at_type",
            "sid_string_meta": "invalid_meta", "sid_array_meta": "invalid_meta",
            "sid_negative_created_at": "invalid_created_at_value",
            "sid_future_created_at": "future_created_at",
            "sid_invalid_session": "invalid_session", "sid_empty_session": "invalid_session",
        }
        sessions = json.loads(FIXTURE.read_text(encoding="utf-8"))
        for session_id, reason in expected.items():
            with self.subTest(case=session_id):
                result = self.run_input(json.dumps({session_id: sessions[session_id]}))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["reasons"], {reason: 1})

    def test_confirmed_empty_object_is_success(self):
        result = self.run_input("{}")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["total_sessions"], 0)
        self.assertEqual(report["counts"], {"candidate": 0, "keep": 0, "review": 0})

    def test_malformed_orphan_children_require_review(self):
        for session in ({"vehicle": "must-not-log-payload"}, {"events": False},
                        {"game": []}, {"vehicle": {}, "game": 123}, {"meta": None}):
            with self.subTest(session=session):
                result = self.run_input(json.dumps({"private_sid": session}))
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(result.stdout)
                self.assertEqual(report["reasons"], {"invalid_session": 1})
                self.assertEqual(report["counts"], {"candidate": 0, "keep": 0, "review": 1})
                self.assertNotIn("must-not-log-payload", result.stdout + result.stderr)

    def test_wrong_responses_are_errors_without_payload_logs(self):
        for content in ("", "{", "null", "[]", "true", '"must-not-log-payload"',
                        '{"error":"must-not-log-payload"}',
                        '{"sessions":{"must-not-log-payload":{"vehicle":{}}}}',
                        '{"sid":{"meta":{"createdAt":NaN}}}',
                        '{"sid":{"meta":{"createdAt":Infinity}}}',
                        '{"sid":{"meta":{"createdAt":-Infinity}}}',
                        '{"sid":{"meta":{"createdAt":1e999}}}',
                        '{"sid":{},"sid":{"vehicle":{}}}'):
            with self.subTest(content=content):
                result = self.run_input(content)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("input_error", result.stderr)
                self.assertNotIn("must-not-log-payload", result.stderr)

    def test_read_failures_do_not_become_empty_success(self):
        with tempfile.TemporaryDirectory(dir=TEST_DIR) as directory:
            path = Path(directory) / "must-not-log-filename.json"
            for target in (path, Path(directory)):
                result = self.run_cli(target)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("input_error", result.stderr)
                self.assertNotIn("must-not-log-filename", result.stderr)
            path.write_bytes(b"\xff")
            result = self.run_cli(path)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")

    def test_invalid_reference_clock_is_rejected(self):
        for now in ("-1", "NaN", "1.5"):
            with self.subTest(now=now):
                result = self.run_input("{}", now)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_epoch_zero_is_a_number_not_a_missing_value(self):
        result = self.run_input('{"sid":{"meta":{"createdAt":0}}}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["reasons"], {"expired_24h": 1})


if __name__ == "__main__":
    unittest.main()
