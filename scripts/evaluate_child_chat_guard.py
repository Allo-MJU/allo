#!/usr/bin/env python3
"""Run synthetic cases against the real local Guardian model; never print conversation text.

This is a smoke evaluation, not evidence of production child-safety coverage.
Exit 0 only if every case matches; 1 for mismatch/unavailable model.
"""
import argparse
import hashlib
import json
import time
from pathlib import Path
from urllib.request import Request

from child_chat_server import GraniteGuardian, MAX_BODY


def metadata(guard):
    base = guard.url.removesuffix('/api/generate')
    result = {}
    for endpoint in ('version', 'tags'):
        with guard.opener.open(Request(base + '/api/' + endpoint), timeout=5) as response:
            raw = response.read(MAX_BODY + 1)
        if len(raw) > MAX_BODY:
            raise ValueError('metadata_too_large')
        data = json.loads(raw)
        if endpoint == 'version':
            result['ollama_version'] = data.get('version')
        else:
            found = next((m for m in data.get('models', []) if m.get('name') == guard.model), None)
            if found is None:
                raise ValueError('model_not_installed')
            result['model_digest'] = found.get('digest')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', default='granite3-guardian:2b')
    parser.add_argument('--base-url', default='http://127.0.0.1:11434')
    parser.add_argument('--timeout', type=float, default=60)
    parser.add_argument('--cases', type=Path, default=Path(__file__).parent / 'tests/fixtures/child_chat_safety_cases.json')
    args = parser.parse_args()
    guard = GraniteGuardian(args.model, args.base_url, args.timeout)
    version = {'model': guard.model, 'synthetic_only': True,
               'policy_version': guard.POLICY_VERSION,
               'cases_sha256': hashlib.sha256(args.cases.read_bytes()).hexdigest()}
    try:
        version.update(metadata(guard))
    except Exception as error:
        version['metadata_error'] = type(error).__name__
    print(json.dumps({'metadata': version}), flush=True)
    cases = json.loads(args.cases.read_text())
    passed = failed = errors = 0
    for case in cases:
        started = time.monotonic()
        result = {'id': case['id'], 'category': case['category'],
                  'direction': 'output' if case['messages'][-1]['role'] == 'assistant' else 'input',
                  'expected_blocked': case['expected_blocked']}
        try:
            blocked = guard(case['messages'])
            result['actual_blocked'] = blocked
            result['pass'] = blocked is case['expected_blocked']
            passed += result['pass']
            failed += not result['pass']
        except Exception as error:
            result.update({'pass': False, 'error': type(error).__name__})
            errors += 1
        result['seconds'] = round(time.monotonic() - started, 3)
        print(json.dumps(result), flush=True)
    print(json.dumps({'summary': {'total': len(cases), 'passed': passed, 'mismatched': failed, 'errors': errors}}), flush=True)
    return 0 if cases and not failed and not errors and 'metadata_error' not in version else 1


if __name__ == '__main__':
    raise SystemExit(main())
