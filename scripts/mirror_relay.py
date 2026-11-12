#!/usr/bin/env python3
"""Single-session, memory-only HTTPS frame relay for local debug builds.

Run setup_mirror_relay.py first, then --config tasks/mirror-local/server.json.
Not an internet-facing service. No screen image, token, or request is logged.
"""
import argparse
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import socket
import ssl
import threading
import time

MAX_FRAME_BYTES = 512 * 1024
MAX_AGE_MS = 1500
REQUEST_TIMEOUT_SECONDS = 2.0
MAX_CONNECTIONS = 8


class FrameStore:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.Lock()
        self.frame = None
        self.sequence = 0
        self.received_at = 0.0

    def put(self, frame):
        with self.lock:
            self.sequence += 1
            self.frame = frame
            self.received_at = self.clock()

    def clear(self):
        with self.lock:
            self.frame = None

    def latest(self):
        with self.lock:
            if self.frame is None:
                return None
            age = max(0, int((self.clock() - self.received_at) * 1000))
            if age > MAX_AGE_MS:
                self.frame = None
                return None
            return self.frame, self.sequence, age


class RelayServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False
    request_queue_size = MAX_CONNECTIONS

    def __init__(self, address, token, context, store):
        self.token = token
        self.context = context
        self.store = store
        self.slots = threading.BoundedSemaphore(MAX_CONNECTIONS)
        super().__init__(address, RelayHandler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        # TLS handshakes happen on a bounded worker, not the accept loop.
        secured = None
        def expire():
            peer = secured or request
            try:
                peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            peer.close()

        # A socket idle timeout alone lets a slow sender occupy a slot forever.
        deadline = threading.Timer(REQUEST_TIMEOUT_SECONDS, expire)
        deadline.daemon = True
        deadline.start()
        try:
            request.settimeout(REQUEST_TIMEOUT_SECONDS)
            secured = self.context.wrap_socket(request, server_side=True, do_handshake_on_connect=False)
            secured.do_handshake()
            super().process_request_thread(secured, client_address)
        except (OSError, ssl.SSLError):
            pass
        finally:
            deadline.cancel()
            (secured or request).close()
            self.slots.release()

    def handle_error(self, request, client_address):
        # Do not print traceback context containing client data.
        pass

    def service_actions(self):
        self.store.latest()  # discard expired bytes even with no polling receiver

    def server_close(self):
        self.store.clear()
        super().server_close()


class RelayHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    server_version = 'AlloMirror'
    sys_version = ''

    def log_message(self, *_args):
        pass

    def send_error(self, code, message=None, explain=None):
        self.reply(code)

    def reply(self, code, body=b'', headers=None):
        self.send_response(code)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        self.send_header('X-Content-Type-Options', 'nosniff')
        for name, value in (headers or {}).items():
            self.send_header(name, str(value))
        self.end_headers()
        if body:
            self.wfile.write(body)
        self.close_connection = True

    def authenticated(self):
        if self.path != '/frame':
            self.reply(404)
            return False
        supplied = self.headers.get_all('Authorization', [])
        expected = 'Bearer ' + self.server.token
        if len(supplied) != 1 or not hmac.compare_digest(supplied[0].encode('utf-8'), expected.encode('ascii')):
            self.reply(401)
            return False
        if self.headers.get('Transfer-Encoding') is not None:
            self.reply(400)
            return False
        return True

    def do_GET(self):
        if not self.authenticated():
            return
        frame = self.server.store.latest()
        if frame is None:
            self.reply(204)
        else:
            data, sequence, age = frame
            self.reply(200, data, {'Content-Type': 'image/jpeg', 'X-Frame-Sequence': sequence, 'X-Frame-Age-Ms': age})

    def do_DELETE(self):
        if self.authenticated():
            self.server.store.clear()
            self.reply(204)

    def do_POST(self):
        if not self.authenticated():
            return
        lengths = self.headers.get_all('Content-Length', [])
        if len(lengths) != 1 or re.fullmatch(r'[0-9]{1,8}', lengths[0]) is None:
            self.reply(400)
            return
        length = int(lengths[0])
        if length > MAX_FRAME_BYTES:
            self.reply(413)
            return
        if length < 4:
            self.reply(400)
            return
        if self.headers.get_all('Content-Type', []) != ['image/jpeg']:
            self.reply(415)
            return
        try:
            data = self.rfile.read(length)
        except (OSError, socket.timeout):
            self.reply(408)
            return
        if len(data) != length or not data.startswith(b'\xff\xd8') or not data.endswith(b'\xff\xd9'):
            self.reply(400)
            return
        self.server.store.put(data)
        self.reply(204)


def create_server(bind, port, token, cert, key, *, store=None):
    if re.fullmatch(r'[A-Za-z0-9_-]{32,128}', token) is None:
        raise ValueError('invalid session token')
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    return RelayServer((bind, port), token, context, store if store is not None else FrameStore())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        server = create_server(config['bind'], int(config['port']), config['token'], config['cert'], config['key'])
    except (OSError, ValueError, TypeError, KeyError):
        parser.exit(1, 'Relay configuration could not be loaded.\n')
    print('Local mirror relay started. Press Ctrl-C to stop.', flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
