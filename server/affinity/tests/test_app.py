import base64
import contextlib
import concurrent.futures
import io
import http.client
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
try:
    import app
except ImportError:
    app = None

TOKEN = 'demo-room-' + 'a' * 32


def png(width=8, height=6):
    out = io.BytesIO()
    Image.new('RGB', (width, height), 'red').save(out, 'PNG')
    return out.getvalue()


class AvailabilityTests(unittest.TestCase):
    def test_service_factory_exists(self):
        self.assertIsNotNone(app, 'The demo service must implement the HTTP app factory')


@unittest.skipIf(app is None, 'Service not implemented')
class HttpTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.start()

    def start(self, evaluate=None):
        self.server = app.create_server(TOKEN, self.directory.name, evaluate=evaluate)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:%d' % self.server.server_port

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def tearDown(self):
        self.stop()
        self.directory.cleanup()

    def request(self, path, payload=None, token=TOKEN, data=None, method=None):
        headers = {'Content-Type': 'application/json'}
        if token is not None:
            headers['Authorization'] = 'Bearer ' + token
        if payload is not None:
            data = json.dumps(payload).encode()
        request = urllib.request.Request(self.url + path, data=data, headers=headers, method=method)
        try:
            response = urllib.request.urlopen(request, timeout=3)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            raw = response.read()
            return response.status, response.headers, raw

    def evaluate(self, **fields):
        payload = {'eggId': 'egg_1', 'requestId': 'request-1', 'text': '여행 가고 싶어'}
        payload.update(fields)
        return self.request('/v1/egg/evaluate', payload)

    def photo(self, **fields):
        payload = {'eggId': 'egg_1', 'requestId': 'request-1', 'imageBase64': base64.b64encode(png()).decode(), 'mimeType': 'image/png'}
        payload.update(fields)
        return self.request('/v1/egg/photo', payload)

    def test_health_and_all_private_routes_require_auth(self):
        self.assertEqual(self.request('/health', token=None)[0], 200)
        for path, data in [('/v1/egg/evaluate', {}), ('/v1/egg/photo', {}), ('/v1/egg/photos', None), ('/v1/egg/photos/' + 'a'*32, None)]:
            with self.subTest(path=path):
                self.assertEqual(self.request(path, data, token=None)[0], 401)
                self.assertEqual(self.request(path, data, token='wrong')[0], 401)

    def test_missing_provider_returns_503_without_user_text(self):
        status, _, body = self.evaluate(text='UNIQUE_PRIVATE_UTTERANCE')
        self.assertEqual(status, 503)
        self.assertNotIn(b'UNIQUE_PRIVATE_UTTERANCE', body)

    def test_evaluation_correlation_trim_and_no_text_persistence(self):
        self.stop()
        self.start(evaluate=lambda value: 'positive' if value == '좋아' else 'negative')
        status, _, body = self.evaluate(text=' 좋아 ')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {'eggId': 'egg_1', 'requestId': 'request-1', 'sentiment': 'positive'})
        for path in Path(self.directory.name).rglob('*'):
            if path.is_file():
                self.assertNotIn('좋아'.encode(), path.read_bytes())

    def test_evaluation_invalid_output_and_exception_are_sanitized(self):
        for result in ('bad', {'sentiment': 'positive'}, TimeoutError('PRIVATE TEXT')):
            self.stop()
            def evaluate(_):
                if isinstance(result, Exception):
                    raise result
                return result
            self.start(evaluate=evaluate)
            status, _, body = self.evaluate()
            self.assertIn(status, (502, 503))
            self.assertNotIn(b'PRIVATE', body)

    def test_evaluation_schema_ids_and_text_bounds(self):
        for fields in ({'eggId': '../x'}, {'requestId': 'x'*129}, {'text': ''}, {'text': ' '*4}, {'text': 'x'*501}, {'text': 1}, {'extra': 'value'}):
            with self.subTest(fields=fields):
                self.assertEqual(self.evaluate(**fields)[0], 400)
        self.assertEqual(self.request('/v1/egg/evaluate', data=b'x'*16385)[0], 413)
        self.assertEqual(self.request('/v1/egg/evaluate', data=b'{oops')[0], 400)
        self.assertEqual(self.request('/v1/egg/evaluate', data=b'[]')[0], 400)

    def test_upload_reencodes_png_to_private_jpeg_with_metadata_stripped(self):
        status, _, raw = self.photo()
        self.assertEqual(status, 200)
        receipt = json.loads(raw)
        self.assertEqual(set(receipt), {'eggId', 'requestId', 'photoId', 'uploadedAtMs'})
        self.assertEqual(receipt['eggId'], 'egg_1')
        self.assertIsInstance(receipt['uploadedAtMs'], int)
        status, headers, body = self.request('/v1/egg/photos/' + receipt['photoId'])
        self.assertEqual(status, 200)
        self.assertEqual(headers['Content-Type'], 'image/jpeg')
        self.assertNotIn('Access-Control-Allow-Origin', headers)
        image = Image.open(io.BytesIO(body))
        self.assertEqual(image.format, 'JPEG')
        self.assertEqual(image.size, (8, 6))
        self.assertFalse(image.getexif())
        self.assertNotIn('png', ''.join(p.name for p in Path(self.directory.name).rglob('*')))

    def test_jpeg_orientation_is_applied_and_exif_removed(self):
        out = io.BytesIO()
        image = Image.new('RGB', (4, 7), 'blue')
        exif = Image.Exif()
        exif[274] = 6
        exif[270] = 'private metadata'
        image.save(out, 'JPEG', exif=exif)
        status, _, raw = self.photo(imageBase64=base64.b64encode(out.getvalue()).decode(), mimeType='image/jpeg')
        self.assertEqual(status, 200)
        _, _, body = self.request('/v1/egg/photos/' + json.loads(raw)['photoId'])
        stored = Image.open(io.BytesIO(body))
        self.assertEqual(stored.size, (7, 4))
        self.assertFalse(stored.getexif())
        self.assertNotIn(b'private metadata', body)

    def test_bad_images_mime_bounds_and_path_traversal_are_rejected(self):
        for fields in ({'imageBase64': 'not base64?'}, {'imageBase64': base64.b64encode(b'not image').decode()}, {'mimeType': 'text/plain'}, {'mimeType': 'image/jpeg'}, {'imageBase64': base64.b64encode(png(4001, 3000)).decode()}, {'extra': True}):
            with self.subTest(fields=list(fields)):
                self.assertEqual(self.photo(**fields)[0], 400)
        self.assertEqual(self.photo(imageBase64=base64.b64encode(b'x'*(5*1024*1024+1)).decode())[0], 413)
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port)
        connection.request('POST', '/v1/egg/photo', headers={'Authorization': 'Bearer ' + TOKEN, 'Content-Type': 'application/json', 'Content-Length': str(7*1024*1024+1)})
        response = connection.getresponse()
        self.assertEqual(response.status, 413)
        response.read()
        connection.close()
        for path in ('/v1/egg/photos/../db.sqlite3', '/v1/egg/photos/%2e%2e', '/v1/egg/photos/' + 'a'*31, '/v1/egg/photos/' + 'a'*32):
            self.assertEqual(self.request(path)[0], 404)

    def test_idempotence_and_conflicting_request_or_egg(self):
        first = self.photo()
        second = self.photo()
        self.assertEqual(first[0], 200)
        self.assertEqual(first[2], second[2])
        self.assertEqual(self.photo(eggId='other')[0], 409)
        self.assertEqual(self.photo(imageBase64=base64.b64encode(png(9, 8)).decode())[0], 409)
        self.assertEqual(self.photo(requestId='new')[0], 409)

    def test_concurrent_identical_requests_have_one_receipt_and_file(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda _: self.photo(), range(6)))
        self.assertEqual({r[0] for r in results}, {200})
        self.assertEqual(len({r[2] for r in results}), 1)
        self.assertEqual(len(list(Path(self.directory.name).rglob('*.jpg'))), 1)

    def test_gallery_shared_between_clients_survives_restart(self):
        status, _, raw = self.photo()
        self.assertEqual(status, 200)
        receipt = json.loads(raw)
        self.stop()
        self.start()
        status, _, listing = self.request('/v1/egg/photos')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(listing), {'photos': [receipt]})
        self.assertEqual(self.request('/v1/egg/photos/' + receipt['photoId'])[0], 200)
        self.assertEqual(self.request('/v1/egg/photos/' + receipt['photoId'], token=None)[0], 401)
        # Independent server/client, same storage and same room token.
        other = app.create_server(TOKEN, self.directory.name)
        thread = threading.Thread(target=other.serve_forever, daemon=True)
        thread.start()
        old_url = self.url
        try:
            self.url = 'http://127.0.0.1:%d' % other.server_port
            self.assertEqual(json.loads(self.request('/v1/egg/photos')[2]), {'photos': [receipt]})
        finally:
            self.url = old_url
            other.shutdown()
            other.server_close()
            thread.join()

    def test_other_room_cannot_read_existing_photos(self):
        receipt = json.loads(self.photo()[2])
        self.stop()
        self.server = app.create_server('b'*32, self.directory.name)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:%d' % self.server.server_port
        self.assertEqual(json.loads(self.request('/v1/egg/photos', token='b'*32)[2]), {'photos': []})
        self.assertEqual(self.request('/v1/egg/photos/' + receipt['photoId'], token='b'*32)[0], 404)

    def test_storage_failure_leaves_no_image_or_temp_file(self):
        # Real SQLite rollback after the image has been atomically renamed.
        with sqlite3.connect(str(Path(self.directory.name) / 'photos.sqlite3')) as connection:
            connection.execute("CREATE TRIGGER reject_photo BEFORE INSERT ON photos BEGIN SELECT RAISE(ABORT, 'private database error'); END")
        status, _, raw = self.photo()
        self.assertEqual(status, 500)
        self.assertNotIn(b'private path', raw)
        self.assertFalse(list(Path(self.directory.name).rglob('*.jpg')))
        self.assertFalse(list(Path(self.directory.name).rglob('*.tmp')))
        self.assertEqual(json.loads(self.request('/v1/egg/photos')[2]), {'photos': []})
        with sqlite3.connect(str(Path(self.directory.name) / 'photos.sqlite3')) as connection:
            connection.execute('DROP TRIGGER reject_photo')
        self.assertEqual(self.photo()[0], 200)

    def test_access_logs_do_not_include_tokens_paths_or_utterances(self):
        out = io.StringIO()
        with contextlib.redirect_stderr(out):
            self.request('/v1/egg/photos?secret=PRIVATE_QUERY', token='PRIVATE_TOKEN')
            self.evaluate(text='PRIVATE_TEXT')
        self.assertEqual(out.getvalue(), '')

    def test_room_gallery_returns_only_100_most_recent_receipts(self):
        with sqlite3.connect(str(Path(self.directory.name) / 'photos.sqlite3')) as connection:
            room = self.server.store.room
            for index in range(103):
                connection.execute('INSERT INTO photos VALUES (?, ?, ?, ?, ?, ?, ?)',
                                   (room, 'egg-%d' % index, 'request-%d' % index, 'digest', 'image/png', '%032x' % index, index))
        status, _, raw = self.request('/v1/egg/photos')
        self.assertEqual(status, 200)
        photos = json.loads(raw)['photos']
        self.assertEqual(len(photos), 100)
        self.assertEqual(photos[0]['uploadedAtMs'], 102)
        self.assertEqual(photos[-1]['uploadedAtMs'], 3)

    def test_json_duplicate_fields_and_invalid_utf8_are_rejected(self):
        for raw in (b'{"eggId":"first","eggId":"second","requestId":"r","text":"hi"}', b'\xff'):
            self.assertEqual(self.request('/v1/egg/evaluate', data=raw)[0], 400)

    def test_large_reencoded_jpeg_is_rejected_even_when_input_is_under_limit(self):
        image = Image.frombytes('RGB', (4000, 3000), os.urandom(4000 * 3000 * 3))
        original = io.BytesIO()
        image.save(original, 'JPEG', quality=35)
        self.assertLess(len(original.getvalue()), 5 * 1024 * 1024)
        status, _, _ = self.photo(imageBase64=base64.b64encode(original.getvalue()).decode(), mimeType='image/jpeg')
        self.assertEqual(status, 413)
        self.assertFalse(list(Path(self.directory.name).rglob('*.jpg')))

    def test_storage_directory_and_database_permissions_are_private(self):
        self.stop()
        os.chmod(self.directory.name, 0o755)
        os.chmod(Path(self.directory.name) / 'images', 0o755)
        self.start()
        self.assertEqual(os.stat(self.directory.name).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(Path(self.directory.name) / 'images').st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(Path(self.directory.name) / 'photos.sqlite3').st_mode & 0o777, 0o600)
        receipt = json.loads(self.photo()[2])
        image = Path(self.directory.name) / 'images' / (receipt['photoId'] + '.jpg')
        self.assertEqual(image.stat().st_mode & 0o777, 0o600)

    def test_by_egg_lookup_recovers_original_receipt_outside_recent_100(self):
        original = json.loads(self.photo()[2])
        with sqlite3.connect(str(Path(self.directory.name) / 'photos.sqlite3')) as connection:
            for index in range(101):
                connection.execute('INSERT INTO photos VALUES (?, ?, ?, ?, ?, ?, ?)',
                                   (self.server.store.room, 'newer-%d' % index, 'new-request-%d' % index,
                                    'digest', 'image/png', '%032x' % index, original['uploadedAtMs'] + index + 1))
        listing = json.loads(self.request('/v1/egg/photos')[2])['photos']
        self.assertNotIn(original, listing)
        self.assertEqual(self.photo(requestId='replacement-request')[0], 409)
        status, _, raw = self.request('/v1/egg/photos/by-egg/egg_1')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw), original)
        self.assertEqual(self.server.store.find_by_egg('egg_1'), original)
        self.assertEqual(self.request('/v1/egg/photos/by-egg/egg_1', token=None)[0], 401)
        self.assertEqual(self.request('/v1/egg/photos/by-egg/egg_1', token='wrong')[0], 401)

    def test_by_egg_lookup_rejects_unknown_invalid_and_other_room_ids(self):
        self.photo()
        for egg_id in ('unknown', '../egg_1', '%2e%2e', 'x'*129, 'egg_1/extra'):
            self.assertEqual(self.request('/v1/egg/photos/by-egg/' + egg_id)[0], 404)
        self.stop()
        other_token = 'other-room-' + 'b'*32
        self.server = app.create_server(other_token, self.directory.name)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:%d' % self.server.server_port
        self.assertEqual(self.request('/v1/egg/photos/by-egg/egg_1', token=other_token)[0], 404)

    def test_token_must_be_explicit_and_at_least_32_characters(self):
        for token in ('', 'short'):
            with self.assertRaises(ValueError):
                app.create_server(token, self.directory.name)


@unittest.skipIf(app is None, 'Service not implemented')
class ProviderTests(unittest.TestCase):
    def invoke(self, response):
        class Transport:
            def __call__(self, request, timeout):
                self.request = request
                self.timeout = timeout
                if isinstance(response, Exception):
                    raise response
                return io.BytesIO(json.dumps(response).encode())
        transport = Transport()
        value = app.OpenAIReviewer('test-key', transport=transport)('부화하면 좋겠다')
        return value, transport

    def test_responses_request_uses_strict_schema_and_separate_untrusted_text(self):
        response = {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': '{"sentiment":"positive"}'}]}]}
        value, transport = self.invoke(response)
        self.assertEqual(value, 'positive')
        request = transport.request
        body = json.loads(request.data)
        self.assertEqual(request.full_url, 'https://api.openai.com/v1/responses')
        self.assertFalse(body['store'])
        self.assertEqual(body['model'], 'gpt-4.1-mini')
        self.assertEqual(body['max_output_tokens'], 128)
        self.assertEqual(body['input'][0]['role'], 'system')
        self.assertEqual(body['input'][1]['role'], 'user')
        self.assertEqual(body['input'][1]['content'], '부화하면 좋겠다')
        schema = body['text']['format']
        self.assertEqual(schema['type'], 'json_schema')
        self.assertTrue(schema['strict'])
        self.assertFalse(schema['schema']['additionalProperties'])
        self.assertEqual(schema['schema']['properties']['sentiment']['enum'], ['positive', 'negative', 'neutral'])
        self.assertLessEqual(transport.timeout, 30)

    def test_refusal_incomplete_invalid_output_and_timeout_raise_safe_error(self):
        cases = [
            {'status': 'incomplete', 'output': []},
            {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'refusal', 'refusal': 'PRIVATE'}]}]},
            {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': '{"sentiment":"wrong"}'}]}]},
            {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'PRIVATE'}]}]},
            {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': '{"sentiment":"neutral","reason":"PRIVATE"}'}]}]},
            TimeoutError('PRIVATE')]
        for response in cases:
            with self.subTest(response_type=type(response).__name__):
                with self.assertRaises(app.ProviderError) as error:
                    self.invoke(response)
                self.assertNotIn('PRIVATE', str(error.exception))


if __name__ == '__main__':
    unittest.main()
