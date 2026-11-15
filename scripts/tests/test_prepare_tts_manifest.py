import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'prepare_tts_manifest.py'
spec = importlib.util.spec_from_file_location('prepare_tts_manifest', SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ManifestTests(unittest.TestCase):
    def test_complete_current_dialogue_and_character_identity(self):
        result = m.build_manifest()
        self.assertEqual(len(result['references']), 17)
        self.assertEqual(len(result['jobs']), 105)
        self.assertEqual(len(result['storyCatalog']['entries']), 105)
        consumers = [c for j in result['jobs'] for c in j['consumers']]
        self.assertEqual(len(consumers), 129)
        self.assertEqual(len(set(consumers)), 129)
        for job in result['jobs']:
            for target in job['targets']:
                self.assertIn('/' + job['species'] + '/', target)
        for species in ['road_sprout', 'puddle_pip', 'highway_comet']:
            self.assertTrue(all('/StoryVoice/' in c['path'] for c in result['references'][species]['candidates']))

    def test_unmatched_endings_use_current_ui_not_old_recording(self):
        entries = m.build_manifest()['storyCatalog']['entries']
        rain = next(e for e in entries if e['topicId'] == 'rain_path' and e['nodeId'] == 'ending')
        night = next(e for e in entries if e['topicId'] == 'night_stars' and e['nodeId'] == 'ending')
        self.assertEqual(rain['text'], '물방울 여행 지도 완성! 땅속 길도 있었네.')
        self.assertEqual(night['text'], '별이 숨은 게 아니라 빛에 가려 보였구나.')

    def test_sea_pilot_synthesizes_current_lines_without_relabeling_old_audio(self):
        result = m.build_manifest()
        runtime_entries = json.loads((m.ROOT / m.STORY / 'catalog.json').read_text())['entries']
        expected = {
            'prediction': '같은 바람이면 어느 배가 더 멀리 갈까?',
            'choose': '어느 쪽부터 해 볼까?',
            'explain': '바람이 펼쳐진 돛을 밀어 배를 움직였어.',
        }
        for node, text in expected.items():
            with self.subTest(node=node):
                self.assertFalse(any(e['topicId'] == 'coast_sail' and e['nodeId'] == node
                                     for e in runtime_entries))
                entry = next(e for e in result['storyCatalog']['entries']
                             if e['topicId'] == 'coast_sail' and e['nodeId'] == node)
                self.assertEqual(entry['text'], text)
                self.assertEqual(entry['species'], 'tide_keeper')
                job = next(j for j in result['jobs'] if f'story/coast_sail/{node}' in j['consumers'])
                self.assertEqual(job['text'], text)
                self.assertIn(f'unity/allo_explore/Assets/Resources/{entry["resource"]}.wav',
                              job['targets'])
        # These remain original voice references, never current-text runtime mappings.
        for filename in ['coast_sail_choice.wav', 'coast_sail_explain.wav']:
            self.assertTrue((m.ROOT / m.STORY / 'tide_keeper' / filename).is_file())

    def test_stale_runtime_catalog_fails_before_generation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            catalog = root / m.STORY / 'catalog.json'
            catalog.parent.mkdir(parents=True)
            value = json.loads((m.ROOT / m.STORY / 'catalog.json').read_text())
            value['entries'][0]['text'] = '오래된 대사'
            catalog.write_text(json.dumps(value))
            source = Path('phone/assets/data/window_stories_ko.json')
            (root / source).parent.mkdir(parents=True)
            (root / source).write_bytes((m.ROOT / source).read_bytes())
            with self.assertRaisesRegex(ValueError, 'stale'):
                m.build_manifest(root)


if __name__ == '__main__':
    unittest.main()
