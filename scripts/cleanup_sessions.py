#!/usr/bin/env python3
"""Bounded Firebase cleanup. Default is dry-run; output contains aggregates only."""

import argparse
from collections import Counter
import json
import os
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

from cleanup_sessions_dry_run import DAY_MS, classify_session, finite_float, unique_object

MAX_RESPONSE_BYTES = 5 * 1024 * 1024
MAX_SESSIONS = 1000
RUN_SECONDS = 240
REQUEST_SECONDS = 10


class CleanupError(Exception):
    """Safe failure marker; external error messages never leave this process."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the Authorization header to a redirected host.
        return None


urlopen = build_opener(ProxyHandler({}), NoRedirect()).open


def target_url(environment):
    project = environment.get("ALLO_FIREBASE_PROJECT_ID", "")
    url = environment.get("ALLO_DB_URL", "")
    token = environment.get("ALLO_FIREBASE_ACCESS_TOKEN", "")
    if not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", project):
        raise CleanupError()
    if not token or any(char.isspace() or ord(char) < 32 for char in token):
        raise CleanupError()
    try:
        parsed = urlsplit(url)
        host = parsed.hostname or ""
        regional = re.fullmatch(
            re.escape(project + "-default-rtdb.") + r"[a-z]+-[a-z]+[0-9]+\.firebasedatabase\.app", host)
        if (parsed.scheme != "https" or parsed.username is not None or parsed.password is not None
                or parsed.port is not None or parsed.path not in ("", "/")
                or parsed.query or parsed.fragment or url != url.strip()
                or host not in (project + ".firebaseio.com", project + "-default-rtdb.firebaseio.com")
                and not regional):
            raise CleanupError()
    except ValueError:
        raise CleanupError() from None
    return "https://" + host, token


def valid_key(key):
    try:
        return (isinstance(key, str) and bool(key) and len(key.encode("utf-8")) <= 768
                and not any(char in ".$#[]/" or ord(char) < 32 or ord(char) == 127 for char in key))
    except UnicodeError:
        return False


def request_json(base, token, deadline, path="sessions", method="GET", etag=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise CleanupError()
    headers = {"Authorization": "Bearer " + token}
    if method == "GET" and path != "sessions":
        headers["X-Firebase-ETag"] = "true"
    if method == "DELETE":
        if not etag:
            raise CleanupError()
        headers["If-Match"] = etag
    request = Request(base + "/" + path + ".json", headers=headers, method=method)
    try:
        with urlopen(request, timeout=min(REQUEST_SECONDS, remaining)) as response:
            if response.status != 200:
                raise CleanupError()
            body = response.read(MAX_RESPONSE_BYTES + 1)
            if len(body) > MAX_RESPONSE_BYTES or time.monotonic() >= deadline:
                raise CleanupError()
            value = json.loads(body.decode("utf-8"), parse_float=finite_float,
                               parse_constant=finite_float, object_pairs_hook=unique_object)
            if isinstance(value, dict) and "error" in value:
                raise CleanupError()
            return value, response.headers.get("ETag")
    except HTTPError as error:
        # 412 is expected only for an individual conditional DELETE.
        if method == "DELETE" and error.code == 412:
            return None, "changed"
        raise CleanupError() from None
    except (OSError, URLError, ValueError, RecursionError):
        raise CleanupError() from None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="delete after independent environment opt-in")
    args = parser.parse_args(argv)
    now_ms = time.time_ns() // 1000000
    deadline = time.monotonic() + RUN_SECONDS
    try:
        base, token = target_url(os.environ)
        if args.apply and os.environ.get("ALLO_CLEANUP_APPLY_ENABLED") != "true":
            raise CleanupError()
        sessions, _ = request_json(base, token, deadline)
        # Firebase's successful empty path is JSON null, never an empty HTTP body.
        if sessions is None:
            sessions = {}
        if (not isinstance(sessions, dict) or "error" in sessions or "sessions" in sessions
                or len(sessions) > MAX_SESSIONS or any(not valid_key(key) for key in sessions)):
            raise CleanupError()
    except CleanupError:
        print("cleanup_error: invalid configuration or initial read failed", file=sys.stderr)
        return 1

    reasons = Counter(classify_session(session, now_ms) for session in sessions.values())
    counts = {"candidate": reasons["expired_24h"], "keep": reasons["recent"],
              "review": len(sessions) - reasons["expired_24h"] - reasons["recent"]}
    report = {"dry_run": not args.apply, "now_ms": now_ms, "cutoff_ms": now_ms - DAY_MS,
              "total_sessions": len(sessions), "counts": counts, "reasons": dict(sorted(reasons.items())),
              "deleted": 0, "skipped_changed": 0, "failed": 0}
    if args.apply:
        for key, session in sessions.items():
            if classify_session(session, now_ms) != "expired_24h":
                continue
            try:
                path = "sessions/" + quote(key, safe="")
                latest, etag = request_json(base, token, deadline, path)
                if classify_session(latest, now_ms) != "expired_24h":
                    report["skipped_changed"] += 1
                    continue
                if not etag:
                    raise CleanupError()
                value, status = request_json(base, token, deadline, path, "DELETE", etag)
                if status == "changed":
                    report["skipped_changed"] += 1
                elif value is None:
                    report["deleted"] += 1
                else:
                    raise CleanupError()
            except CleanupError:
                report["failed"] += 1
    print(json.dumps(report, sort_keys=True))
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
