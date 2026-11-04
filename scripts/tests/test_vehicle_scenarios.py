#!/usr/bin/env python3
"""Offline scenario checks: all external commands are replaced by local stubs."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class Scenarios(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.log = self.dir / 'log'
        for name, body in {
            'adb': '''#!/bin/bash
printf 'adb %s\\n' "$*" >> "$LOG"
[ "${FAIL_ADB:-}" != 1 ] || exit 1
if [ "$1" = devices ]; then printf '%b' "${DEVICES:-List of devices attached\\nemulator-5554\\tdevice\\n}"; fi
if [ "$1" = -s ]; then echo Pleos_Test; fi
''',
            'curl': '''#!/bin/bash
printf 'curl %s\\n' "$*" >> "$LOG"
case "$*" in *"${FAIL_MATCH:-__never__}"*)
  case "$*" in *--fail*|*' -f '*) exit 22;; esac;; esac
[ "${FAIL_CURL:-}" != 1 ] || exit 7
''',
            'sleep': '#!/bin/bash\nexit "${FAIL_SLEEP:-0}"\n',
        }.items():
            p = self.dir / name
            p.write_text(body)
            p.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.dir) + ':' + os.environ['PATH'], LOG=str(self.log))
        self.env.pop('ANDROID_SERIAL', None)

    def run_scenario(self, name, *args, **env):
        result = subprocess.run(['bash', str(ROOT / 'scripts' / name), *args], env=dict(self.env, **env), text=True, capture_output=True)
        return result, self.log.read_text() if self.log.exists() else ''

    def test_rainy_initialization_and_order(self):
        result, log = self.run_scenario('scenario_rainy_highway.sh', '2')
        self.assertEqual(result.returncode, 0, result.stderr)
        for part in ['gear=Park', 'speed=0', 'front_wiper=Off', 'value=Off', 'area=rear_right', 'front_wiper=Low', 'gear=Drive', 'speed=90', 'gear=Park', 'closing=1']:
            self.assertIn(part, log)
        self.assertLess(log.index('front_wiper=Off'), log.index('front_wiper=Low'))
        self.assertLess(log.index('gear=Drive'), log.index('speed=90'))
        self.assertIn('부화', result.stdout)

    def test_tunnel_initialization_and_order(self):
        result, log = self.run_scenario('scenario_tunnel_rough.sh', '1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(log.index('front_wiper=Off'), log.index('value=LowBeam'))
        self.assertLess(log.index('steering=120'), log.index('steering=-120'))
        self.assertIn('closing=1', log)

    def test_http_failure_stops_sequence(self):
        for match in ('browser/session?client=', 'vehicle/body?front_wiper=Low'):
            self.log.unlink(missing_ok=True)
            result, log = self.run_scenario('scenario_rainy_highway.sh', '2', FAIL_MATCH=match)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn('gear=Drive', log)

    def test_transport_adb_and_sleep_failures(self):
        for env in ({'FAIL_CURL':'1'}, {'FAIL_ADB':'1'}, {'FAIL_SLEEP':'1'}):
            self.log.unlink(missing_ok=True)
            result, _ = self.run_scenario('scenario_tunnel_rough.sh', '1', **env)
            self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_device_selection(self):
        for devices in ('List of devices attached\n', 'emulator-5554\tdevice\nemulator-5556\tdevice\n'):
            self.log.unlink(missing_ok=True)
            result, log = self.run_scenario('scenario_rainy_highway.sh', '2', DEVICES=devices)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('curl ', log)

    def test_put_failure_and_close_failure_are_reported(self):
        for match in ('vehicle/gear?gear=Drive', 'closing=1'):
            self.log.unlink(missing_ok=True)
            result, _ = self.run_scenario('scenario_rainy_highway.sh', '2', FAIL_MATCH=match)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('신호 시퀀스 전송 완료', result.stdout)

    def test_invalid_input_precedes_external_commands(self):
        for name, arg in [('scenario_rainy_highway.sh', ''), ('scenario_rainy_highway.sh', '-1'), ('scenario_rainy_highway.sh', 'x'), ('scenario_tunnel_rough.sh', '0'), ('scenario_tunnel_rough.sh', '1+1')]:
            self.log.unlink(missing_ok=True)
            result, log = self.run_scenario(name, arg)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(log, '')

if __name__ == '__main__':
    unittest.main()
