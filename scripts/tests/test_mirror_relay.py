"""Loopback HTTPS contract tests; no real vehicle, Firebase, or screen capture."""
import hashlib
import http.client
import importlib.util
import json
from pathlib import Path
import ssl
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from mirror_relay import FrameStore, create_server, MAX_FRAME_BYTES
from setup_mirror_relay import create_configuration


class RelayTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.server_path, cls.client_path = create_configuration(Path(cls.directory.name), 'localhost', '127.0.0.1', 8443)
        cls.config = json.loads(cls.server_path.read_text())
        cls.client = json.loads(cls.client_path.read_text())
        cls.context = ssl.create_default_context(cafile=cls.config['cert'])

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def setUp(self):
        self.now = 100.0
        self.store = FrameStore(clock=lambda: self.now)
        self.server = create_server('127.0.0.1', 0, self.config['token'], self.config['cert'], self.config['key'], store=self.store)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(3)

    def request(self, method='GET', path='/frame', body=None, headers=None):
        connection = http.client.HTTPSConnection('localhost', self.server.server_port, context=self.context, timeout=3)
        values = {'Authorization': 'Bearer ' + self.config['token']}
        if body is not None:
            values['Content-Type'] = 'image/jpeg'
        values.update(headers or {})
        connection.request(method, path, body=body, headers=values)
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def test_tls_identity_and_private_configuration(self):
        der = ssl.PEM_cert_to_DER_cert(Path(self.config['cert']).read_text())
        self.assertEqual(self.client['certificateSha256'], hashlib.sha256(der).hexdigest())
        self.assertEqual(self.client['url'], 'https://localhost:8443')
        self.assertGreaterEqual(len(self.client['token']), 32)
        for path in [self.server_path, self.client_path, Path(self.config['key'])]:
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(FileExistsError):
            create_configuration(Path(self.directory.name), 'localhost', '127.0.0.1', 8443)

    def test_latest_frame_age_clear_and_monotonic_sequence(self):
        self.assertEqual(self.request()[0], 204)
        first = b'\xff\xd8first\xff\xd9'
        second = b'\xff\xd8second\xff\xd9'
        self.assertEqual(self.request('POST', body=first)[0], 204)
        self.now += 0.4
        status, headers, data = self.request()
        self.assertEqual((status, data), (200, first))
        self.assertEqual(headers['X-Frame-Sequence'], '1')
        self.assertTrue(399 <= int(headers['X-Frame-Age-Ms']) <= 400)
        self.assertEqual(self.request('POST', body=second)[0], 204)
        self.assertEqual(self.request()[2], second)
        self.assertEqual(self.request()[1]['X-Frame-Sequence'], '2')
        self.assertEqual(self.request('DELETE')[0], 204)
        self.assertEqual(self.request()[0], 204)
        self.request('POST', body=first)
        self.assertEqual(self.request()[1]['X-Frame-Sequence'], '3')
        self.now += 1.501
        self.assertEqual(self.request()[0], 204)
        self.assertIsNone(self.store.latest())

    def test_unauthorized_request_cannot_read_write_or_clear(self):
        image = b'\xff\xd8safe\xff\xd9'
        self.request('POST', body=image)
        for method in ('GET', 'POST', 'DELETE'):
            self.assertEqual(self.request(method, body=image if method == 'POST' else None, headers={'Authorization': 'Bearer wrong'})[0], 401)
        self.assertEqual(self.request()[2], image)

    def test_rejects_invalid_route_type_image_and_oversize(self):
        self.assertEqual(self.request(path='/frame?token=secret')[0], 404)
        self.assertEqual(self.request(path='/')[0], 404)
        self.assertEqual(self.request('POST', body=b'not-jpeg')[0], 400)
        self.assertEqual(self.request('POST', body=b'\xff\xd8\xff\xd9', headers={'Content-Type': 'text/plain'})[0], 415)
        self.assertEqual(self.request('POST', body=b'\xff\xd8\xff\xd9', headers={'Content-Length': str(MAX_FRAME_BYTES + 1)})[0], 413)
        self.assertEqual(self.request('POST', body=b'', headers={'Content-Length': '-1'})[0], 400)
        self.assertEqual(self.request('POST', body=b'', headers={'Transfer-Encoding': 'chunked'})[0], 400)
        self.assertEqual(self.request()[0], 204)

    def test_no_cache_or_cross_origin_headers(self):
        self.request('POST', body=b'\xff\xd8safe\xff\xd9')
        _, headers, _ = self.request()
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertNotIn('Access-Control-Allow-Origin', headers)
        self.assertEqual(headers['Content-Type'], 'image/jpeg')

    def test_slow_request_has_absolute_deadline(self):
        with patch('mirror_relay.REQUEST_TIMEOUT_SECONDS', 0.25):
            raw = socket.create_connection(('localhost', self.server.server_port), timeout=2)
            with self.context.wrap_socket(raw, server_hostname='localhost') as client:
                client.settimeout(2)
                client.sendall(b'POST /frame HTTP/1.0\r\n')
                started = time.monotonic()
                # The server must close an incomplete header, not wait forever.
                try:
                    self.assertEqual(client.recv(1024), b'')
                except (ssl.SSLError, ConnectionResetError):
                    pass
                self.assertLess(time.monotonic() - started, 1.5)

    def test_invalid_setup_host_cannot_inject_openssl_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            for host in ['localhost\nDNS:evil.test', '-config', 'https://localhost', 'localhost/path']:
                with self.assertRaises(ValueError):
                    create_configuration(Path(directory), host, '127.0.0.1', 8443)


if __name__ == '__main__':
    unittest.main()
