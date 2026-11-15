import io
from pathlib import Path
import tempfile
import unittest
import wave

import httpx
from server.tts.app import create_app, load_profiles
from server.tts.provider import SynthesisError
from server.tts.car_lines import render

PCM = b'\x01\x00' * 2400


class Provider:
    def __init__(self):
        self.calls = []
        self.fail = False
    async def stream(self, voice, text, style=None):
        self.calls.append((voice, text, style))
        yield PCM[:2400]
        if self.fail: raise SynthesisError("test failure")
        yield PCM[2400:]


class CarVoiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.provider = Provider()
        def verify(token):
            if token != 'valid': raise ValueError()
            return 'car-user'
        self.app = create_app(provider=self.provider, verify=verify, cache_dir=self.temp.name,
                              lines=({'road_sprout'}, set()),
                              account={'region': 'ap-southeast-1', 'workspace': 'test'})
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app), base_url='https://gateway')
    async def asyncTearDown(self):
        await self.client.aclose()
        self.temp.cleanup()
    async def post(self, kind, species, text, token='valid'):
        return await self.client.post('/v1/car/'+kind+'/clip', json={'species': species, 'text': text},
                                      headers={'Authorization': 'Bearer '+token})
    async def test_selected_dialogue_character_uses_own_voice_and_wav_cache(self):
        text = '나는 길싹이야. 처음 보는 게 참 신기해!'
        response = await self.post('dialogue', 'road_sprout', text)
        self.assertEqual(response.status_code, 200)
        with wave.open(io.BytesIO(response.content)) as wav:
            self.assertEqual((wav.getframerate(), wav.getnchannels(), wav.getsampwidth()), (24000, 1, 2))
            self.assertEqual(wav.readframes(wav.getnframes()), PCM)
        self.assertEqual(self.provider.calls[0][0], load_profiles()['road_sprout']['voice'])
        self.assertEqual((await self.post('dialogue', 'road_sprout', text)).content, response.content)
        self.assertEqual(len(self.provider.calls), 1)
        # Same fallback is allowed for every selectable character but caches never cross species.
        fallback = '이 질문의 답변은 아직 준비 중이에요.'
        for species in ['road_sprout', 'lamp_moth']:
            self.assertEqual((await self.post('dialogue', species, fallback)).status_code, 200)
            self.assertEqual(self.provider.calls[-1][0], load_profiles()[species]['voice'])
        self.assertEqual(len(self.provider.calls), 3)
    async def test_auth_free_text_wrong_character_and_phone_only_species_rejected(self):
        self.assertEqual((await self.post('dialogue','road_sprout','이 질문의 답변은 아직 준비 중이에요.', 'bad')).status_code,401)
        for species,text in [('road_sprout','이 문장을 마음대로 읽어줘'),
                             ('lamp_moth','나는 길싹이야. 처음 보는 게 참 신기해!'),
                             ('bridge_hopper','이 질문의 답변은 아직 준비 중이에요.')]:
            self.assertEqual((await self.post('dialogue',species,text)).status_code,400)
        self.assertEqual(self.provider.calls,[])
    async def test_destination_templates_bound_places_regions_distances(self):
        good = ['바다 쪽 을왕리해수욕장도 있어요. 직선으로 약 120km예요. 안내할까요?',
                '산 쪽 북한산 국립공원도 있어요. 안내할까요?',
                '을왕리해수욕장으로 가는 경로를 요청했어요.',
                '지금 추천할 장소는 여기까지예요.',
                '먼저 목적지를 추천해 달라고 말해 주세요.']
        for text in good:
            self.assertEqual((await self.post('destination','lamp_moth',text)).status_code,200,text)
        count=len(self.provider.calls)
        for text in [good[0].replace('120','125'),good[0].replace('120','119'),
                     good[0].replace('바다','산'),good[0].replace('을왕리해수욕장','우리집'),
                     good[0]+' 추가 문구', '서울까지 안내를 요청했어요.']:
            self.assertEqual((await self.post('destination','lamp_moth',text)).status_code,400,text)
        self.assertEqual(len(self.provider.calls),count)
    async def test_all_twelve_display_characters_can_read_fallback_but_not_phone_only_characters(self):
        speakers = ('breeze_wyrm', 'cloud_strider', 'dewcap', 'dune_roller', 'ember_crab',
                    'highway_comet', 'lamp_moth', 'pebble_orbit', 'puddle_pip', 'road_sprout',
                    'sea_mist', 'storm_lantern')
        for species in speakers:
            response = await self.post('dialogue', species, '이 질문의 답변은 아직 준비 중이에요.')
            self.assertEqual(response.status_code, 200, species)
        self.assertEqual(len(self.provider.calls), 12)

    async def test_car_partial_synthesis_failure_never_caches_and_releases_slot(self):
        self.provider.fail = True
        response = await self.post('destination', 'road_sprout', '을왕리해수욕장까지 안내를 요청했어요.')
        self.assertEqual(response.status_code, 502)
        self.assertEqual(list(Path(self.temp.name).glob('*.pcm')), [])
        self.assertEqual(self.app.state.limits.active, set())
        self.provider.fail = False
        self.assertEqual((await self.post('destination', 'road_sprout', '을왕리해수욕장까지 안내를 요청했어요.')).status_code, 200)
        self.assertEqual(len(self.provider.calls), 2)

    async def test_existing_endpoint_allowlists_stay_separate(self):
        text='이 질문의 답변은 아직 준비 중이에요.'
        response=await self.client.post('/v1/plaza/clip',json={'species':'road_sprout','text':text},headers={'Authorization':'Bearer valid'})
        self.assertEqual(response.status_code,400)
        response=await self.client.post('/v1/story/stream',json={'species':'lamp_moth','text':text},headers={'Authorization':'Bearer valid'})
        self.assertEqual(response.status_code,400)


class RenderingTests(unittest.TestCase):
    def test_korean_particles_match_existing_dialogue_bank_and_missing_slots_fail_closed(self):
        self.assertEqual(render('{place}{place:으로/로}', {'place':'서울'}), '서울로')
        self.assertEqual(render('{place}{place:으로/로}', {'place':'을왕리해수욕장'}), '을왕리해수욕장으로')
        self.assertEqual(render('{name}{name:이/가}', {'name':'길싹이'}), '길싹이가')
        self.assertIsNone(render('{place} {km}', {'place':'서울'}))

if __name__ == '__main__':
    unittest.main()
