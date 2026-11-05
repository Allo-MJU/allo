"""Offline execution contract: HTTP is replaced before the runner starts."""

from contextlib import redirect_stderr, redirect_stdout
import gc
import io
import json
from pathlib import Path
import sys
import unittest
import warnings
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cleanup_sessions as cleanup

NOW = 1793761200000
ENV = {
    "ALLO_DB_URL": "https://allo-test-default-rtdb.asia-southeast1.firebasedatabase.app",
    "ALLO_FIREBASE_PROJECT_ID": "allo-test",
    "ALLO_FIREBASE_ACCESS_TOKEN": "synthetic-private-token",
    "ALLO_CLEANUP_APPLY_ENABLED": "true",
}
EXPIRED = {"meta": {"createdAt": NOW - 86400000}, "game": {"stage": "private-payload"}}


class Response(io.BytesIO):
    def __init__(self, value=None, etag=None, raw=None, status=200):
        super().__init__(json.dumps(value).encode() if raw is None else raw)
        self.status = status
        self.headers = {"ETag": etag} if etag is not None else {}


class ExecutionTests(unittest.TestCase):
    def run_cleanup(self, responses=(), apply=False, env=None):
        calls = []
        pending = iter(responses)

        def open_request(request, timeout):
            calls.append(request)
            response = next(pending)
            if isinstance(response, Exception):
                raise response
            return response

        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.dict("os.environ", ENV if env is None else env, clear=True), \
             patch.object(cleanup, "urlopen", open_request), \
             patch.object(cleanup.time, "time_ns", return_value=NOW * 1000000), \
             redirect_stdout(stdout), redirect_stderr(stderr):
            code = cleanup.main(["--apply"] if apply else [])
        output = stdout.getvalue() + stderr.getvalue()
        for secret in ("private-id", "private-payload", "synthetic-private-token"):
            self.assertNotIn(secret, output)
        for response in responses[:len(calls)]:
            if isinstance(response, (Response, HTTPError)):
                self.assertTrue(response.closed, "consumed response must be closed")
        return code, json.loads(stdout.getvalue()) if stdout.getvalue() else None, calls

    def test_default_dry_run_preserves_every_session(self):
        sessions = {"private-id": EXPIRED, "orphan": {"vehicle": {}},
                    "recent": {"meta": {"createdAt": NOW}},
                    "invalid": {"meta": {"createdAt": "yesterday"}},
                    "missing": {"meta": {}}, "future": {"meta": {"createdAt": NOW + 1}}}
        code, report, calls = self.run_cleanup([Response(sessions)])
        self.assertEqual(code, 0)
        self.assertTrue(report["dry_run"])
        self.assertEqual(report["counts"], {"candidate": 1, "keep": 1, "review": 4})
        self.assertEqual([r.method for r in calls], ["GET"])

    def test_apply_only_deletes_rechecked_expired_with_matching_etag(self):
        code, report, calls = self.run_cleanup([
            Response({"private-id": EXPIRED, "orphan": {"vehicle": {}},
                      "normal": {"meta": {"createdAt": NOW}},
                      "invalid": {"meta": {"createdAt": "yesterday"}},
                      "missing": {"meta": {}}, "future": {"meta": {"createdAt": NOW + 1}}}),
            Response(EXPIRED, '"v1"'), Response(None)], apply=True)
        self.assertEqual(code, 0)
        self.assertEqual(report["deleted"], 1)
        self.assertEqual([r.method for r in calls], ["GET", "GET", "DELETE"])
        self.assertEqual(calls[1].get_header("X-firebase-etag"), "true")
        self.assertEqual(calls[2].get_header("If-match"), '"v1"')
        for request in calls:
            self.assertEqual(request.get_header("Authorization"), "Bearer synthetic-private-token")
            self.assertNotIn("token", request.full_url)

    def test_changed_or_removed_candidate_is_preserved(self):
        for latest in (None, {"meta": {"createdAt": NOW}}, {"vehicle": {}},
                       {"meta": {"createdAt": NOW + 1}}):
            with self.subTest(latest=latest):
                code, report, calls = self.run_cleanup([
                    Response({"private-id": EXPIRED}), Response(latest, '"new"')], apply=True)
                self.assertEqual(code, 0)
                self.assertEqual(report["skipped_changed"], 1)
                self.assertNotIn("DELETE", [r.method for r in calls])

    def test_etag_conflict_is_skip_without_retry(self):
        conflict = HTTPError("private-id", 412, "private-payload", {},
                             io.BytesIO(b"private-payload synthetic-private-token"))
        code, report, calls = self.run_cleanup([
            Response({"private-id": EXPIRED}), Response(EXPIRED, '"v1"'), conflict], apply=True)
        self.assertEqual(code, 0)
        self.assertEqual(report["skipped_changed"], 1)
        self.assertEqual(len(calls), 3)

    def test_http_errors_do_not_emit_resource_warnings(self):
        for method in ("GET", "DELETE"):
            for status in (403, 412, 500):
                with self.subTest(method=method, status=status):
                    def open_request(request, timeout):
                        raise HTTPError("private-id", status,
                                        "private-payload synthetic-private-token", {},
                                        io.BytesIO(b"private-payload synthetic-private-token"))

                    with warnings.catch_warnings(record=True) as caught:
                        warnings.simplefilter("always", ResourceWarning)
                        with patch.object(cleanup, "urlopen", open_request):
                            args = (ENV["ALLO_DB_URL"], ENV["ALLO_FIREBASE_ACCESS_TOKEN"],
                                    cleanup.time.monotonic() + 10, "sessions/private-id",
                                    method, '"v1"')
                            if method == "DELETE" and status == 412:
                                self.assertEqual(cleanup.request_json(*args), (None, "changed"))
                            else:
                                with self.assertRaises(cleanup.CleanupError):
                                    cleanup.request_json(*args)
                        # HTTPError tracebacks can keep the response alive until cyclic GC.
                        gc.collect()
                    self.assertEqual(caught, [], [str(item.message) for item in caught])

    def test_missing_etag_fails_without_delete(self):
        code, report, calls = self.run_cleanup([
            Response({"private-id": EXPIRED}), Response(EXPIRED)], apply=True)
        self.assertEqual(code, 1)
        self.assertEqual(report["failed"], 1)
        self.assertEqual(len(calls), 2)

    def test_empty_null_is_success_but_empty_200_body_is_failure(self):
        for value in (None, {}):
            code, report, _ = self.run_cleanup([Response(value)])
            self.assertEqual(code, 0)
            self.assertEqual(report["total_sessions"], 0)
        self.assertEqual(self.run_cleanup([Response(raw=b"")])[0], 1)

    def test_http_and_timeout_read_failures_are_nonzero(self):
        failures = [HTTPError("private-id", status, "private-payload", {},
                              io.BytesIO(b"private-payload synthetic-private-token"))
                    for status in (401, 403, 412, 429, 500, 503)]
        failures += [TimeoutError("private-payload"), URLError("private-payload")]
        for error in failures:
            with self.subTest(error=type(error).__name__):
                code, _, calls = self.run_cleanup([error], apply=True)
                self.assertEqual(code, 1)
                self.assertEqual(len(calls), 1)

    def test_partial_failure_reports_failure_and_other_deletions(self):
        denied = HTTPError("private-id", 403, "private-payload", {},
                           io.BytesIO(b"private-payload synthetic-private-token"))
        code, report, calls = self.run_cleanup([
            Response({"one": EXPIRED, "two": EXPIRED}), Response(EXPIRED, '"v1"'), denied,
            Response(EXPIRED, '"v2"'), Response(None)], apply=True)
        self.assertEqual(code, 1)
        self.assertEqual(report["deleted"], 1)
        self.assertEqual(report["failed"], 1)
        self.assertEqual(len(calls), 5)

    def test_apply_requires_separate_exact_opt_in_before_network(self):
        for flag in (None, "false", "TRUE", "1"):
            env = dict(ENV)
            env.pop("ALLO_CLEANUP_APPLY_ENABLED")
            if flag is not None:
                env["ALLO_CLEANUP_APPLY_ENABLED"] = flag
            code, _, calls = self.run_cleanup(apply=True, env=env)
            self.assertEqual(code, 1)
            self.assertEqual(calls, [])

    def test_missing_target_auth_or_project_fails_before_network(self):
        for key in ("ALLO_DB_URL", "ALLO_FIREBASE_PROJECT_ID", "ALLO_FIREBASE_ACCESS_TOKEN"):
            env = dict(ENV)
            env.pop(key)
            code, _, calls = self.run_cleanup(env=env)
            self.assertEqual(code, 1)
            self.assertEqual(calls, [])

    def test_wrong_project_or_unsafe_url_fails_before_network(self):
        for url in ("http://allo-test.firebaseio.com", "https://other-project.firebaseio.com",
                    "https://allo-test.firebaseio.com.evil.test", "https://allo-test.firebaseio.com/sessions",
                    "https://user@allo-test.firebaseio.com", "https://allo-test.firebaseio.com?auth=private",
                    "https://allo-test.firebaseio.com:444", "https://allo-test.firebaseio.com/#fragment"):
            env = dict(ENV, ALLO_DB_URL=url)
            code, _, calls = self.run_cleanup(env=env)
            self.assertEqual(code, 1)
            self.assertEqual(calls, [])

    def test_malformed_or_oversized_response_fails_before_delete(self):
        for raw in (b"", b"[]", b'{"error":"private-payload"}',
                    b'{"sessions":{}}', b'{"sid":{"meta":{"createdAt":NaN}}}',
                    b'{"id":{},"id":{}}', b" " * (cleanup.MAX_RESPONSE_BYTES + 1)):
            code, _, calls = self.run_cleanup([Response(raw=raw)], apply=True)
            self.assertEqual(code, 1)
            self.assertEqual(len(calls), 1)

    def test_session_limit_and_invalid_keys_fail_before_delete(self):
        for sessions in ({str(i): EXPIRED for i in range(cleanup.MAX_SESSIONS + 1)},
                         {"bad/path": EXPIRED}, {"bad\nkey": EXPIRED}):
            code, _, calls = self.run_cleanup([Response(sessions)], apply=True)
            self.assertEqual(code, 1)
            self.assertEqual(len(calls), 1)

    def test_delete_unexpected_body_or_status_is_failure(self):
        for response in (Response({"private-payload": True}), Response(None, status=204)):
            code, report, _ = self.run_cleanup([
                Response({"private-id": EXPIRED}), Response(EXPIRED, '"v1"'), response], apply=True)
            self.assertEqual(code, 1)
            self.assertEqual(report["failed"], 1)

    def test_invalid_unicode_key_fails_without_logging_or_delete(self):
        code, _, calls = self.run_cleanup([Response({"\ud800": EXPIRED})], apply=True)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)

    def test_error_response_during_recheck_is_failure(self):
        code, report, calls = self.run_cleanup([
            Response({"private-id": EXPIRED}), Response({"error": "private-payload"})], apply=True)
        self.assertEqual(code, 1)
        self.assertEqual(report["failed"], 1)
        self.assertEqual(len(calls), 2)

    def test_deadline_stops_before_any_network_request(self):
        with patch.object(cleanup.time, "monotonic", side_effect=[0, 241]):
            code, _, calls = self.run_cleanup([Response({})])
        self.assertEqual(code, 1)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
