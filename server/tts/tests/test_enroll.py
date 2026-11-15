import json
from pathlib import Path
import tempfile
import unittest
import wave
from server.tts.enroll import enroll, validate_sample
from server.tts.app import MODEL

class Reply:
    def __init__(self, value): self.value = value
    def raise_for_status(self): pass
    def json(self): return {'output':self.value}
class Client:
    def __init__(self, approved=True): self.actions=[]; self.approved=approved
    def post(self, url, headers, json):
        action=json['input']['action']; self.actions.append(action)
        if action=='create_voice': return Reply({'voice_id':'voice-test'})
        return Reply({'status':'OK' if self.approved else 'UNDEPLOYED','target_model':MODEL})

class EnrollTests(unittest.TestCase):
    def sample(self, path, seconds):
        with wave.open(str(path),'wb') as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(24000);w.writeframes(b'\x01\x00'*int(24000*seconds))
    def test_short_sample_rejected_without_network(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'sample.wav';self.sample(p,3)
            with self.assertRaises(ValueError): validate_sample(p)
    def test_voice_shared_registered_once_and_registry_not_secret(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'sample.wav';self.sample(p,10);r=Path(t)/'voices.json';client=Client()
            self.assertEqual(enroll(p,'road_sprout',r,'ap-southeast-1','workspace','secret',client),'registered')
            self.assertEqual(enroll(p,'road_sprout',r,'ap-southeast-1','workspace','secret',client),'already_registered')
            self.assertEqual(client.actions,['create_voice','query_voice'])
            self.assertNotIn('secret',r.read_text())
            self.assertEqual(json.loads(r.read_text())['voices']['road_sprout']['voice_id'],'voice-test')
    def test_rejected_voice_is_not_active_and_retry_does_not_recreate(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'sample.wav';self.sample(p,10);r=Path(t)/'voices.json';client=Client(False)
            with self.assertRaises(RuntimeError): enroll(p,'road_sprout',r,'cn-beijing','workspace','secret',client)
            self.assertNotIn('voice_id',json.loads(r.read_text())['voices']['road_sprout'])
            client.approved=True
            enroll(p,'road_sprout',r,'cn-beijing','workspace','secret',client)
            self.assertEqual(client.actions.count('create_voice'),1)
    def test_cross_region_registry_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'sample.wav';self.sample(p,10);r=Path(t)/'voices.json';client=Client()
            enroll(p,'road_sprout',r,'cn-beijing','workspace','secret',client)
            with self.assertRaises(ValueError): enroll(p,'road_sprout',r,'ap-southeast-1','workspace','secret',client)
