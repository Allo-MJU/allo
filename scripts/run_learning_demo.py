"""Run the local emulator API; never persist or print the provider key."""
import getpass
import json
import os
from pathlib import Path
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    config = root / 'phone/config/learning-demo.local.json'
    if not config.exists():
        raise SystemExit('Local emulator configuration is missing; rebuild the configured demo first.')
    values = json.loads(config.read_text())
    token = values.get('ALLO_DEMO_TOKEN', '')
    if not isinstance(token, str) or len(token) < 32 or any(ord(c) < 33 or ord(c) > 126 for c in token):
        raise SystemExit('Invalid private demo token.')
    if sys.argv[1:] == ['--check']:
        print('Local emulator configuration valid. No provider call was made.')
        return
    keyless = sys.argv[1:] == ['--without-ai']
    if sys.argv[1:] and not keyless:
        raise SystemExit('Usage: run_learning_demo.py [--check|--without-ai]')
    key = None if keyless else (os.environ.get('OPENAI_API_KEY') or getpass.getpass('OpenAI API key (hidden, not saved): ').strip())
    if not keyless and not key:
        raise SystemExit('No API key supplied.')
    if keyless:
        os.environ.pop('OPENAI_API_KEY', None)
    else:
        os.environ['OPENAI_API_KEY'] = key
    os.environ.update(ALLO_DEMO_TOKEN=token,
                      ALLO_DEMO_HOST='127.0.0.1', ALLO_DEMO_PORT='8787')
    sys.path.insert(0, str(root / 'server/affinity'))
    try:
        import app
    except ModuleNotFoundError:
        raise SystemExit('Run with server/affinity/.venv/bin/python after installing requirements.') from None
    print('Starting emulator API on 127.0.0.1:8787. Keep this terminal open; Ctrl+C stops it.')
    if keyless:
        print('Keyless mode: pairing/legacy authored API checks work; new direct greet/chat requires an API key.')
    app.main()


if __name__ == '__main__':
    main()
