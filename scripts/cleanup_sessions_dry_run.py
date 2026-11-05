#!/usr/bin/env python3
"""Classify a local /sessions snapshot; no network, writes, or deletion.

Candidate means eligible under issue #23's unapproved proposal, not permission
to delete. Input is the raw session-ID mapping, without a {"sessions": ...}
wrapper. Only aggregate counts leave this process.
"""

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import sys


DAY_MS = 86_400_000
ACTION = {
    "expired_24h": "candidate",
    "orphan_missing_meta": "candidate",
    "recent": "keep",
}


def finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("non-finite number")
    return number


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def classify_session(session, now_ms):
    if not isinstance(session, dict) or not session.keys() & {"meta", "vehicle", "game", "events"}:
        return "invalid_session"
    meta = session.get("meta")
    if meta is None:
        children = [session[key] for key in ("vehicle", "game", "events")
                    if session.get(key) is not None]
        if not children or any(not isinstance(child, dict) for child in children):
            return "invalid_session"
        return "orphan_missing_meta"
    if not isinstance(meta, dict):
        return "invalid_meta"
    created_at = meta.get("createdAt")
    if created_at is None:
        return "missing_created_at"
    # bool subclasses int in Python; it is not an epoch-ms number in JSON.
    if type(created_at) not in (int, float):
        return "invalid_created_at_type"
    if created_at < 0:
        return "invalid_created_at_value"
    if created_at > now_ms:
        return "future_created_at"
    if created_at <= now_ms - DAY_MS:
        return "expired_24h"
    return "recent"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="local raw /sessions JSON snapshot")
    parser.add_argument("--now-ms", type=int, required=True, help="fixed reference epoch milliseconds")
    args = parser.parse_args()
    if args.now_ms < 0:
        parser.error("--now-ms must be nonnegative")

    try:
        sessions = json.loads(
            args.input.read_text(encoding="utf-8"),
            parse_float=finite_float, parse_constant=finite_float,
            object_pairs_hook=unique_object,
        )
        if not isinstance(sessions, dict) or "error" in sessions or "sessions" in sessions:
            raise ValueError("expected raw session mapping")
    except (OSError, UnicodeError, ValueError, RecursionError):
        # Never echo a path, session ID, payload, or response error body.
        print("input_error: unreadable or invalid raw /sessions JSON", file=sys.stderr)
        return 1

    reasons = Counter(classify_session(session, args.now_ms) for session in sessions.values())
    counts = {"candidate": 0, "keep": 0, "review": 0}
    for reason, count in reasons.items():
        counts[ACTION.get(reason, "review")] += count
    print(json.dumps({
        "dry_run": True,
        "policy": "issue_23_proposal_not_approved",
        "now_ms": args.now_ms,
        "cutoff_ms": args.now_ms - DAY_MS,
        "total_sessions": len(sessions),
        "counts": counts,
        "reasons": dict(sorted(reasons.items())),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
