"""Local demo transport only: no gameplay or reward calculation."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

lock = threading.Lock()
state = {'game': None, 'vehicle': None, 'events': []}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, value, status=200):
        payload = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        url = urlsplit(self.path)
        with lock:
            if url.path in ('/game', '/vehicle'):
                result = state[url.path[1:]]
            elif url.path == '/events':
                try:
                    after = int(parse_qs(url.query).get('after', ['0'])[0])
                except ValueError:
                    return self.respond({'error': 'invalid cursor'}, 400)
                result = {'events': [e for e in state['events'] if e['id'] > after], 'cursor': len(state['events'])}
            elif url.path == '/health':
                result = {'mode': 'local-mock-transport', 'ok': True}
            else:
                return self.respond({'error': 'not found'}, 404)
        self.respond(result)

    def write_json(self):
        path = urlsplit(self.path).path
        if path not in ('/game', '/vehicle', '/events'):
            return self.respond({'error': 'not found'}, 404)
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 1024 * 1024:
                return self.respond({'error': 'invalid size'}, 400)
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise ValueError()
        except (ValueError, json.JSONDecodeError):
            return self.respond({'error': 'invalid JSON object'}, 400)
        with lock:
            if path == '/events':
                state['events'].append({'id': len(state['events']) + 1, 'event': data})
            else:
                state[path[1:]] = data
        self.respond({'ok': True})

    do_POST = write_json
    do_PUT = write_json

if __name__ == '__main__':
    print('Local mock bridge listening on 127.0.0.1:8765', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
