import asyncio
from contextlib import aclosing
import io
import json
from pathlib import Path
import tempfile
import unittest
import wave

import httpx
from starlette.requests import ClientDisconnect
from server.tts.app import (AudioCache, MODEL, SYSTEM_VOICES, cache_key, create_app, load_profiles,
                            resolve_voice)
from server.tts.provider import DashScope, SynthesisError

REGISTRY = {'model': MODEL, 'workspace': 'workspace', 'region': 'ap-southeast-1',
            'voices': {'road_sprout': {'voice_id': 'voice-road'}, 'puddle_pip': {'voice_id': 'voice-pip'}}}
PCM = b'\x01\x00\x02\x00' * 2400


class Provider:
    def __init__(self):
        self.calls = []
        self.fail = False
    async def stream(self, voice, text, style=None):
        self.calls.append((voice, text, style))
        yield PCM[:4800]
        if self.fail:
            raise SynthesisError('unavailable')
        yield PCM[4800:]


class GatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.provider = Provider()
        def verify(token):
            if token != 'valid':
                raise ValueError()
            return 'user'
        self.app = create_app(REGISTRY, self.provider, verify, self.temp.name,
                              ({'road_sprout', 'puddle_pip'}, {('road_sprout', '안녕'), ('puddle_pip', '안녕')}))
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app), base_url='https://gateway')
    async def asyncTearDown(self):
        await self.client.aclose()
        self.temp.cleanup()
    async def post(self, path, species='road_sprout', text='안녕', token='valid'):
        return await self.client.post(path, json={'species': species, 'text': text}, headers={'Authorization': 'Bearer '+token})
    async def test_auth_allowlist_and_missing_voice_do_not_call_provider(self):
        self.assertEqual((await self.post('/v1/plaza/clip', token='invalid')).status_code, 401)
        self.assertEqual((await self.post('/v1/plaza/clip', text='다른 대사')).status_code, 400)
        self.assertEqual((await self.post('/v1/story/stream', species='other')).status_code, 400)
        self.assertEqual(self.provider.calls, [])
    async def test_stream_is_pcm_and_cached_plaza_is_wav_same_voice(self):
        first = await self.post('/v1/story/stream')
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.headers['x-audio-endian'], 'little')
        self.assertEqual(first.content, PCM)
        second = await self.post('/v1/plaza/clip')
        with wave.open(io.BytesIO(second.content)) as wav:
            self.assertEqual(wav.getframerate(), 24000)
            self.assertEqual(wav.readframes(wav.getnframes()), PCM)
        self.assertEqual(len(self.provider.calls), 1)
        await self.post('/v1/plaza/clip', species='puddle_pip')
        self.assertEqual(self.provider.calls[-1][0], 'voice-pip')
        self.assertEqual(len(self.provider.calls), 2)
    async def test_partial_failure_not_cached_and_slot_released(self):
        self.provider.fail = True
        result = await self.post('/v1/plaza/clip')
        self.assertEqual(result.status_code, 502)
        self.assertEqual(list(Path(self.temp.name).glob('*.pcm')), [])
        self.assertEqual(self.app.state.limits.active, set())
        self.provider.fail = False
        self.assertEqual((await self.post('/v1/plaza/clip')).status_code, 200)
    async def test_disconnect_before_stream_headers_releases_slot(self):
        body = json.dumps({'species': 'road_sprout', 'text': '안녕'}).encode()
        received = False
        async def receive():
            nonlocal received
            if not received:
                received = True
                return {'type': 'http.request', 'body': body, 'more_body': False}
            await asyncio.Event().wait()
        async def send(event):
            if event['type'] == 'http.response.start':
                raise OSError('client disconnected before first chunk')
        scope = {
            'type': 'http', 'asgi': {'version': '3.0', 'spec_version': '2.4'},
            'http_version': '1.1', 'method': 'POST', 'scheme': 'https',
            'path': '/v1/story/stream', 'raw_path': b'/v1/story/stream',
            'query_string': b'', 'headers': [(b'authorization', b'Bearer valid')],
            'server': ('gateway', 443), 'client': ('test', 1),
        }
        with self.assertRaises(ClientDisconnect):
            await asyncio.wait_for(self.app(scope, receive, send), timeout=2)
        self.assertEqual(self.app.state.limits.active, set())
        self.assertEqual(self.provider.calls, [])
        self.assertEqual(list(Path(self.temp.name).glob('*.pcm')), [])
        self.assertEqual((await self.post('/v1/story/stream')).status_code, 200)
    async def test_limits_and_invalid_text(self):
        self.assertEqual((await self.post('/v1/story/stream', text='x'*601)).status_code, 400)
        for _ in range(30):
            self.assertEqual((await self.post('/v1/plaza/clip')).status_code, 200)
        self.assertEqual((await self.post('/v1/plaza/clip')).status_code, 429)
    async def test_dev_token_only_from_loopback_clients(self):
        dev = 'd' * 32
        app = create_app(REGISTRY, self.provider, lambda t: (_ for _ in ()).throw(ValueError()), self.temp.name,
                         ({'road_sprout'}, set()), dev_token=dev)
        async def status(client_host):
            transport = httpx.ASGITransport(app=app, client=(client_host, 1))
            async with httpx.AsyncClient(transport=transport, base_url='http://gateway') as client:
                return (await client.post('/v1/story/stream', json={'species': 'road_sprout', 'text': '안녕'},
                                          headers={'Authorization': 'Bearer ' + dev})).status_code
        self.assertEqual(await status('127.0.0.1'), 200)
        self.assertEqual(await status('203.0.113.5'), 401)
        with self.assertRaises(ValueError):
            create_app(REGISTRY, self.provider, lambda t: 'u', self.temp.name, ({'road_sprout'}, set()),
                       dev_token='short')
    async def test_unconfigured_gateway_fails_closed(self):
        app = create_app(provider=None, verify=lambda t:'user', cache_dir=self.temp.name,
                         lines=({'road_sprout'}, set()))
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='https://gateway') as client:
            result = await client.post('/v1/story/stream', json={'species':'road_sprout','text':'안녕'},
                                       headers={'Authorization':'Bearer valid'})
        self.assertEqual(result.status_code, 503)

    async def test_unenrolled_species_uses_persona_system_voice(self):
        app = create_app(None, self.provider, lambda t: 'user', self.temp.name, ({'star_owl'}, set()),
                         account={'region': 'ap-southeast-1', 'workspace': 'ws'})
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='https://gateway') as client:
            result = await client.post('/v1/story/stream', json={'species': 'star_owl', 'text': '안녕'},
                                       headers={'Authorization': 'Bearer valid'})
        self.assertEqual(result.status_code, 200)
        voice, _, style = self.provider.calls[-1]
        profile = load_profiles()['star_owl']
        self.assertEqual(voice, profile['voice'])
        self.assertEqual(style, {k: profile[k] for k in ('instruction', 'pitch', 'rate')})

    async def test_cloned_voice_keeps_persona_instruction_only(self):
        await self.post('/v1/story/stream', species='puddle_pip')
        voice, _, style = self.provider.calls[-1]
        self.assertEqual(voice, 'voice-pip')
        self.assertEqual(style, {'instruction': load_profiles()['puddle_pip']['instruction']})


class ProfileTests(unittest.TestCase):
    def test_every_voiced_character_has_a_verified_korean_profile(self):
        from server.tts.app import default_lines
        story, plaza = default_lines()
        voiced = story | {species for species, _ in plaza}
        profiles = load_profiles()
        self.assertEqual(set(profiles), voiced)
        self.assertEqual(len(voiced), 17)
        for profile in profiles.values():
            self.assertIn(profile['voice'], SYSTEM_VOICES)
            self.assertTrue(profile['instruction'].startswith('한국어로'))

    def test_invalid_profiles_rejected(self):
        good = {'voice': 'longanhuan_v3.1', 'pitch': 1.0, 'rate': 1.0, 'instruction': '한국어로 말해.'}
        for bad in ({**good, 'voice': 'longpaopao_v3.1'}, {**good, 'pitch': 3.0}, {**good, 'instruction': ''},
                    {**good, 'extra': 1}, {**good, 'instruction': '한국어로 말해. 또렷하게.'},
                    {**good, 'instruction': '한국어로 ' + '아주 ' * 15 + '말해.'}):
            with tempfile.NamedTemporaryFile('w', suffix='.json') as f:
                json.dump({'model': MODEL, 'profiles': {'dewcap': bad}}, f)
                f.flush()
                with self.assertRaises(ValueError):
                    load_profiles(f.name)


class FakeSocket:
    def __init__(self, fail=False):
        self.sent = []
        self.step = 0
        self.fail = fail
        self.closed = False
    async def __aenter__(self):
        return self
    async def __aexit__(self, *args):
        self.closed = True
    async def send(self, message):
        self.sent.append(json.loads(message))
    async def recv(self):
        self.step += 1
        task = self.sent[0]['header']['task_id']
        if self.step == 1:
            return json.dumps({'header':{'event':'task-started','task_id':task}})
        if self.step == 2:
            return b'\x01\x00\x02'
        if self.step == 3:
            return b'\x00'
        return json.dumps({'header': {'event':'task-failed' if self.fail else 'task-finished', 'task_id':task}})


class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def test_waits_for_start_streams_aligned_pcm_before_finish(self):
        socket = FakeSocket()
        provider = DashScope('test-key','workspace','ap-southeast-1',MODEL,lambda *a,**k:socket)
        async with aclosing(provider.stream('voice-road','안녕')) as stream:
            self.assertEqual(await anext(stream), b'\x01\x00')
            self.assertFalse(socket.closed)
            self.assertEqual([e['header']['action'] for e in socket.sent], ['run-task','continue-task','finish-task'])
            self.assertEqual(await anext(stream), b'\x02\x00')
            with self.assertRaises(StopAsyncIteration):
                await anext(stream)
        self.assertTrue(socket.closed)
        self.assertEqual(len({e['header']['task_id'] for e in socket.sent}),1)
        self.assertEqual(socket.sent[0]['payload']['parameters']['voice'], 'voice-road')
        self.assertNotIn('instruction', socket.sent[0]['payload']['parameters'])
    async def test_style_sent_as_instruction_pitch_rate(self):
        socket = FakeSocket()
        provider = DashScope('test-key','workspace','ap-southeast-1',MODEL,lambda *a,**k:socket)
        style = {'instruction': '한국어로 말해.', 'pitch': 1.2, 'rate': 0.9}
        async for _ in provider.stream('longanhuan_v3.1','안녕', style): pass
        params = socket.sent[0]['payload']['parameters']
        self.assertEqual((params['instruction'], params['pitch'], params['rate']), ('한국어로 말해.', 1.2, 0.9))
    async def test_cancellation_sends_cancel_and_closes_upstream(self):
        socket = FakeSocket()
        provider = DashScope('test-key','workspace','cn-beijing',MODEL,lambda *a,**k:socket)
        stream = provider.stream('voice-road','안녕')
        await anext(stream)
        await stream.aclose()
        self.assertTrue(socket.closed)
        self.assertEqual(socket.sent[-1]['payload']['input'], {'directive':'cancel'})
    async def test_task_failure_sanitized(self):
        socket = FakeSocket(fail=True)
        provider = DashScope('test-key','workspace','cn-beijing',MODEL,lambda *a,**k:socket)
        with self.assertRaisesRegex(SynthesisError, '^synthesis_unavailable$'):
            async for _ in provider.stream('voice-road','안녕'): pass


class CacheTests(unittest.TestCase):
    def test_voice_change_invalidates_and_partial_wav_rejected(self):
        account = {'region': 'ap-southeast-1', 'workspace': 'ws'}
        voice, style = resolve_voice(None, load_profiles(), 'road_sprout')
        original = cache_key(account, 'road_sprout', '안녕', voice, style)
        self.assertNotEqual(original, cache_key(account, 'road_sprout', '안녕', 'voice-new', style))
        self.assertNotEqual(original, cache_key(account, 'road_sprout', '안녕', voice, {**style, 'pitch': 1.0}))
        self.assertNotEqual(original, cache_key(account, 'road_sprout', '안녕', voice,
                                                {**style, 'instruction': '한국어로 다르게.'}))
        with tempfile.TemporaryDirectory() as temp:
            cache = AudioCache(temp)
            with self.assertRaises(SynthesisError): cache.write(original, b'\x01')
            self.assertIsNone(cache.read(original))


if __name__ == '__main__': unittest.main()

class DisconnectTests(unittest.IsolatedAsyncioTestCase):
    async def test_plaza_disconnect_cancels_stalled_provider(self):
        from server.tts.app import collect_until_disconnect
        from fastapi import HTTPException
        started, closed = asyncio.Event(), asyncio.Event()
        class Stalled:
            async def stream(self, voice, text, style=None):
                try:
                    started.set()
                    await asyncio.Event().wait()
                    yield b'never'
                finally:
                    closed.set()
        class Disconnected:
            async def receive(self):
                await started.wait()
                return {'type':'http.disconnect'}
        with self.assertRaises(HTTPException) as error:
            await asyncio.wait_for(collect_until_disconnect(Disconnected(), Stalled(), 'voice', 'text'), 1)
        self.assertEqual(error.exception.status_code, 499)
        self.assertTrue(closed.is_set())
