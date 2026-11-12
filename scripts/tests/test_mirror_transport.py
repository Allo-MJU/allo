"""Run the Android debug clients' real Kotlin TLS transport against the local relay.

Requires the same cached Kotlin compiler as check_mirror_kotlin.py, no device.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from check_mirror_kotlin import compiler, ROOT
from mirror_relay import create_server
from setup_mirror_relay import create_configuration


class KotlinTransportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='allo-mirror-transport-')
        cls.directory = Path(cls.temp.name)
        cp, std = compiler()
        classes = cls.directory / 'classes'
        sources = list((ROOT / 'mirror-common/src/main/kotlin').rglob('*.kt'))
        sources += [ROOT / 'mirror-common/src/test/kotlin/ai/allo/mirror/MirrorTransportCheck.kt']
        subprocess.run(['java', '-cp', os.pathsep.join(cp), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                        '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', std,
                        '-d', str(classes), *map(str, sources)], check=True, timeout=60)
        cls.runtime = os.pathsep.join([str(classes), std])
        server_path, client_path = create_configuration(cls.directory / 'identity', 'localhost', '127.0.0.1', 8443)
        cls.config = json.loads(server_path.read_text())
        cls.client = json.loads(client_path.read_text())

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        c = self.config
        self.server = create_server('127.0.0.1', 0, c['token'], c['cert'], c['key'])
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(3)

    def run_client(self, mode, **changes):
        data = dict(self.client, url=f'https://localhost:{self.server.server_port}')
        data.update(changes)
        config_path = self.directory / 'client-private.json'
        config_path.write_text(json.dumps(data))
        config_path.chmod(0o600)
        result = subprocess.run(['java', '-cp', self.runtime, 'ai.allo.mirror.MirrorTransportCheckKt',
                                 str(config_path), mode], capture_output=True, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_upload_receive_and_clear_over_real_tls(self):
        self.run_client('roundtrip')

    def test_matching_pin_does_not_disable_hostname_validation(self):
        self.run_client('reject', url=f'https://127.0.0.1:{self.server.server_port}')

    def test_wrong_pin_is_rejected(self):
        self.run_client('reject', certificateSha256='00' * 32)

    def test_wrong_token_is_rejected(self):
        self.run_client('reject', token='x' * 43)


if __name__ == '__main__':
    unittest.main()
