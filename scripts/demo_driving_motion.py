#!/usr/bin/env python3
"""Exercise real Pleos VHAL via Virtual Console; does not write Firebase/game state.
Run adb forward tcp:8088 tcp:8088 first. Always restores zero speed and Park.
"""
import argparse
import json
import time
import urllib.request


def request(base, path, method):
    with urllib.request.urlopen(urllib.request.Request(base + path, method=method), timeout=3) as r:
        payload = r.read().decode()
        if payload:
            value = json.loads(payload)
            if isinstance(value, dict) and (value.get('error') or value.get('ok') is False):
                raise RuntimeError(payload)


def run(base, cycles):
    def beat(): request(base, '/browser/session?client=allo-motion-demo', 'POST')
    def gear(value):
        beat(); request(base, '/vehicle/gear?gear=' + value, 'PUT')
    def speed(value, brake=0):
        beat()
        request(base, f'/vehicle/controls?speed={round(value)}&accelerator=0&brake={brake}&steering=0', 'PUT')
    def hold(value, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            speed(value); time.sleep(.2)
    def ramp(start, end, seconds, brake=0):
        begun = time.monotonic()
        while True:
            fraction = min(1, (time.monotonic() - begun) / seconds)
            speed(start + (end - start) * fraction, brake)
            if fraction >= 1: break
            time.sleep(.2)
    try:
        gear('Park'); hold(0, 1)
        gear('Drive')
        for index in range(cycles):
            print(f'cycle {index + 1}: low speed 15 km/h', flush=True)
            ramp(0, 15, 2); hold(15, 3)
            print('accelerate to 85 km/h', flush=True)
            ramp(15, 85, 4); hold(85, 3)
            print('hard stop: 85 → 0 km/h in 0.6s', flush=True)
            ramp(85, 0, .6, 100); hold(0, 4)
            print('resume at 40 km/h', flush=True)
            ramp(0, 40, 3); hold(40, 3)
            print('gentle stop: 40 → 0 km/h in 6s', flush=True)
            ramp(40, 0, 6); hold(0, 2)
    finally:
        try:
            try: speed(0)
            finally: gear('Park')
        finally:
            request(base, '/browser/session?client=allo-motion-demo&closing=1', 'POST')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='http://127.0.0.1:8088')
    parser.add_argument('--cycles', type=int, default=1)
    args = parser.parse_args()
    if not 1 <= args.cycles <= 5: parser.error('--cycles must be 1..5')
    run(args.base, args.cycles)
