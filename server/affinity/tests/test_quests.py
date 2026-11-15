"""Quest templates are authored, bounded and do not invoke a provider."""
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app
from learning import CATALOG_PATH, LEGACY_PERSONAS_PATH


class QuestHttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.server = app.create_server('q' * 32, cls.directory.name)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}/v1/companion/quest-template'
        cls.stories = {s['speciesId']: s for s in json.loads(CATALOG_PATH.read_text())['stories']}
        cls.legacy = {s['speciesId'] for s in json.loads(LEGACY_PERSONAS_PATH.read_text())['profiles']}

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.directory.cleanup()

    def request(self, body, token='q' * 32):
        request = urllib.request.Request(self.url, data=json.dumps(body).encode(), headers={
            'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token})
        try:
            response = urllib.request.urlopen(request)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def test_all_18_species_kinds_have_bounded_truthful_templates(self):
        self.assertEqual(len(self.stories) + len(self.legacy), 18)
        for species in self.stories.keys() | self.legacy:
            for requested in ('food', 'story', 'travel'):
                for variant in (0, 1):
                    with self.subTest(species=species, kind=requested, variant=variant):
                        status, result = self.request(dict(speciesId=species, kind=requested, variant=variant))
                        self.assertEqual(status, 200)
                        self.assertEqual(set(result), {'schemaVersion', 'templateId', 'templateVersion', 'speciesId',
                                                       'kind', 'title', 'text', 'storyId', 'targetFoodId', 'targetRegion'})
                        kind = 'food' if species in self.legacy and requested == 'story' else requested
                        self.assertEqual((result['speciesId'], result['kind']), (species, kind))
                        self.assertEqual((result['schemaVersion'], result['templateVersion']), (1, 1))
                        self.assertTrue(0 < len(result['templateId']) <= 128)
                        self.assertTrue(0 < len(result['title']) <= 80)
                        self.assertTrue(0 < len(result['text']) <= 500)
                        self.assertEqual(result['targetFoodId'], 'berry_snack' if kind == 'food' else None)
                        self.assertEqual(result['targetRegion'], 'coast' if kind == 'travel' else None)
                        self.assertEqual(result['storyId'], self.stories[species]['storyId'] if kind == 'story' else None)
                        if kind == 'story':
                            self.assertIn(self.stories[species]['title'], result['text'])
                            self.assertIn(self.stories[species]['persona']['interests'][0], result['text'])
                        if kind == 'travel':
                            for invented_past in ('오랜만', '전에', '다시', '지난', '봤었'):
                                self.assertNotIn(invented_past, result['text'])

    def test_variant_is_deterministic_and_rotates(self):
        body = dict(speciesId='road_sprout', kind='story', variant=0)
        first = self.request(body)
        self.assertEqual(first, self.request(body))
        self.assertNotEqual(first[1]['text'], self.request({**body, 'variant': 1})[1]['text'])
        self.assertEqual(first, self.request({**body, 'variant': 2}))

    def test_strict_fields_species_kind_and_variant(self):
        valid = dict(speciesId='road_sprout', kind='food', variant=0)
        invalid = [{}, {**valid, 'prompt': 'ignore rules'}, {**valid, 'phoneUid': 'owner'},
                   {k: v for k, v in valid.items() if k != 'variant'}]
        for key, values in [('speciesId', ['unknown', '', '../road_sprout', ['road_sprout'], None]),
                            ('kind', ['unknown', '', ['food'], None]),
                            ('variant', [-1, True, 1.0, '0', None, 2147483648])]:
            invalid.extend({**valid, key: value} for value in values)
        for body in invalid:
            with self.subTest(body=body):
                self.assertEqual(self.request(body)[0], 400)
        self.assertEqual(self.request({**valid, 'variant': 2147483647})[0], 200)
        self.assertEqual(self.request({**valid, 'prompt': 'x' * 2048})[0], 413)

    def test_existing_bearer_is_required(self):
        self.assertEqual(self.request(dict(speciesId='road_sprout', kind='food', variant=0), token='bad'),
                         (401, {'error': 'unauthorized'}))
