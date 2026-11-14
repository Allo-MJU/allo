"""Authenticated mobile PCM streaming / fixed plaza WAV cache gateway."""
import asyncio
from collections import OrderedDict, deque
from contextlib import aclosing
import hashlib
import hmac
import io
import json
import logging
import os
from pathlib import Path
import tempfile
import time
import wave

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import Response, StreamingResponse
from .provider import DashScope, MAX_PCM_BYTES, SAMPLE_RATE, SynthesisError

LOG = logging.getLogger('uvicorn.error')
ROOT = Path(__file__).resolve().parents[2]
MODEL = 'qwen-audio-3.1-tts-plus'
PROFILES_FILE = Path(__file__).with_name('voice_profiles.json')
# System voices verified to synthesize Korean on this model in ap-southeast-1 (2026-11-14).
SYSTEM_VOICES = {'longanlingxin_v3.1', 'longanhuan_v3.1', 'longanfengyue_v3.1', 'xunanchuan_v3.1'}


def load_profiles(path=PROFILES_FILE):
    data = json.loads(Path(path).read_text())
    if data.get('model') != MODEL:
        raise ValueError('Voice profiles must use model ' + MODEL)
    profiles = data['profiles']
    for species, profile in profiles.items():
        if set(profile) != {'voice', 'pitch', 'rate', 'instruction'}:
            raise ValueError('Invalid voice profile fields: ' + species)
        if profile['voice'] not in SYSTEM_VOICES:
            raise ValueError('Unverified system voice: ' + species)
        if not all(isinstance(profile[k], (int, float)) and 0.5 <= profile[k] <= 2.0 for k in ('pitch', 'rate')):
            raise ValueError('pitch/rate must be within 0.5-2.0: ' + species)
        # Long or multi-sentence instructions get read aloud by the model (observed 2026-11-14).
        instruction = profile['instruction']
        if (not isinstance(instruction, str) or not 0 < len(instruction) <= 40
                or instruction.rstrip('.').count('.') or '\n' in instruction):
            raise ValueError('instruction must be one sentence of at most 40 chars: ' + species)
    return profiles


def resolve_voice(registry, profiles, species):
    """Cloned voice when enrolled (instruction only), otherwise the persona's system voice."""
    profile = profiles.get(species)
    if not profile:
        return None, None
    cloned = (registry or {}).get('voices', {}).get(species, {}).get('voice_id')
    if cloned:
        return cloned, {'instruction': profile['instruction']}
    return profile['voice'], {k: profile[k] for k in ('instruction', 'pitch', 'rate')}


def cache_key(account, species, text, voice, style):
    value = [account['region'], account['workspace'], MODEL, voice, sorted(style.items()),
             species, text, 'ko', SAMPLE_RATE, 'pcm16le-v2']
    return hashlib.sha256(json.dumps(value, ensure_ascii=False).encode()).hexdigest()


class AudioCache:
    def __init__(self, path, budget=64 * 1024 * 1024):
        self.path, self.budget = Path(path), budget
        self.path.mkdir(parents=True, exist_ok=True)

    def read(self, key):
        path = self.path / (key + '.pcm')
        if not path.exists():
            return None
        if not 0 < path.stat().st_size <= MAX_PCM_BYTES or path.stat().st_size % 2:
            path.unlink(missing_ok=True)
            return None
        return path.read_bytes()

    def write(self, key, data):
        if not data or len(data) % 2 or len(data) > MAX_PCM_BYTES:
            raise SynthesisError('invalid_audio')
        fd, name = tempfile.mkstemp(dir=self.path, suffix='.part')
        try:
            with os.fdopen(fd, 'wb') as out:
                out.write(data)
            os.replace(name, self.path / (key + '.pcm'))
        finally:
            Path(name).unlink(missing_ok=True)
        files = sorted(self.path.glob('*.pcm'), key=lambda p: p.stat().st_mtime, reverse=True)
        size = 0
        for path in files:
            size += path.stat().st_size
            if size > self.budget:
                path.unlink(missing_ok=True)


class Limits:
    """Single-process bounds; deploy one worker/instance until shared quotas are added."""
    def __init__(self):
        self.users = OrderedDict()
        self.active = set()

    def take(self, uid, chars):
        now = time.monotonic()
        history = self.users.setdefault(uid, deque())
        while history and history[0][0] < now - 3600:
            history.popleft()
        if sum(t > now - 60 for t, _ in history) >= 30 or sum(n for _, n in history) + chars > 10000:
            raise HTTPException(429, 'voice_rate_limited')
        self.users.move_to_end(uid)
        if len(self.users) > 10000:
            self.users.popitem(last=False)
        if uid in self.active or len(self.active) >= 4:
            raise HTTPException(429, 'voice_busy')
        history.append((now, chars))
        self.active.add(uid)

    def release(self, uid):
        self.active.discard(uid)


def wav_bytes(pcm):
    out = io.BytesIO()
    with wave.open(out, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm)
    return out.getvalue()


def firebase_verifier(token):
    from firebase_admin import auth, get_app, initialize_app
    try:
        get_app()
    except ValueError:
        initialize_app(options={'projectId': os.environ['FIREBASE_PROJECT_ID']})
    claims = auth.verify_id_token(token, check_revoked=True)
    return claims['uid']


def default_lines():
    # Reuse the audited exporter; game data remains the source of fixed text.
    from scripts.prepare_tts_manifest import build_manifest
    manifest = build_manifest()
    plaza = {(j['species'], j['text']) for j in manifest['jobs']
             if any(c.startswith('plaza/') for c in j['consumers'])}
    story = {e['species'] for e in manifest['storyCatalog']['entries']}
    return story, plaza


async def collect_until_disconnect(request, provider, voice, text, style=None):
    async def collect():
        data = bytearray()
        async with asyncio.timeout(65):
            async with aclosing(provider.stream(voice, text, style)) as upstream:
                async for chunk in upstream:
                    data.extend(chunk)
                    if len(data) > MAX_PCM_BYTES:
                        raise SynthesisError('audio_too_large')
        return bytes(data)

    async def disconnected():
        while True:
            message = await request.receive()
            if message['type'] == 'http.disconnect':
                return

    synthesis = asyncio.create_task(collect())
    disconnect = asyncio.create_task(disconnected())
    try:
        completed, _ = await asyncio.wait((synthesis, disconnect), return_when=asyncio.FIRST_COMPLETED)
        if disconnect in completed:
            raise HTTPException(499, 'client_disconnected')
        return await synthesis
    finally:
        for task in (synthesis, disconnect):
            if not task.done():
                task.cancel()
        await asyncio.gather(synthesis, disconnect, return_exceptions=True)


def create_app(registry=None, provider=None, verify=None, cache_dir=None, lines=None, profiles=None,
               account=None, dev_token=None):
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    verify = verify or firebase_verifier
    cache = AudioCache(cache_dir or os.environ.get('TTS_CACHE_DIR', '/tmp/allo-tts-cache'))
    limits = Limits()
    story_species, plaza_lines = lines or default_lines()
    profiles = load_profiles() if profiles is None else profiles
    if registry is None:
        path = os.environ.get('TTS_VOICES_FILE')
        registry = json.loads(Path(path).read_text()) if path and Path(path).is_file() else None
    if registry and registry.get('model') != MODEL:
        raise ValueError('Registry must use supported model ' + MODEL)
    if account is None:
        source = registry or {'region': os.environ.get('DASHSCOPE_REGION', ''),
                              'workspace': os.environ.get('DASHSCOPE_WORKSPACE_ID', '')}
        account = {'region': source['region'], 'workspace': source['workspace']}
    if registry and (registry['region'], registry['workspace']) != (account['region'], account['workspace']):
        raise ValueError('Registry account does not match the configured workspace/region')
    if provider is None and os.environ.get('DASHSCOPE_API_KEY') and account['workspace']:
        provider = DashScope(os.environ['DASHSCOPE_API_KEY'], account['workspace'], account['region'], MODEL)
    # Local voice testing only: accepted solely from loopback clients. Never set in deployment.
    dev_token = os.environ.get('TTS_DEV_TOKEN', '') if dev_token is None else dev_token
    if dev_token and len(dev_token) < 24:
        raise ValueError('TTS_DEV_TOKEN must be at least 24 characters')

    async def request_data(request, plaza):
        auth = request.headers.get('authorization', '')
        if not auth.startswith('Bearer ') or len(auth) > 8192:
            raise HTTPException(401, 'authentication_required')
        client = request.client.host if request.client else ''
        if dev_token and client in ('127.0.0.1', '::1') and hmac.compare_digest(auth[7:], dev_token):
            uid = 'local-dev'
        else:
            uid = None
        try:
            if uid is None:
                uid = await asyncio.to_thread(verify, auth[7:])
            if not isinstance(uid, str) or not uid:
                raise ValueError()
        except Exception:
            raise HTTPException(401, 'authentication_required') from None
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 8192:
                raise HTTPException(413, 'request_too_large')
        try:
            value = json.loads(body)
            if not isinstance(value, dict) or set(value) != {'species', 'text'}:
                raise ValueError()
            species, text = value['species'], value['text']
            if not isinstance(species, str) or not isinstance(text, str) or not text.strip() or len(text) > 600:
                raise ValueError()
        except (ValueError, KeyError, TypeError):
            raise HTTPException(400, 'invalid_voice_request') from None
        if (plaza and (species, text) not in plaza_lines) or (not plaza and species not in story_species):
            raise HTTPException(400, 'unknown_character_or_line')
        voice, style = resolve_voice(registry, profiles, species)
        if not voice or provider is None:
            raise HTTPException(503, 'character_voice_not_configured')
        limits.take(uid, len(text))
        key = cache_key(account, species, text, voice, style)
        # Character→voice audit for operations. No token, user ID or line text in logs.
        LOG.info('voice %s species=%s voice=%s pitch=%s rate=%s cached=%s', 'plaza' if plaza else 'story',
                 species, voice, style.get('pitch', '-'), style.get('rate', '-'), cache.read(key) is not None)
        return uid, species, text, voice, style, key

    @app.get('/healthz')
    async def health():
        return {'status': 'ok', 'configured': provider is not None}

    class ReleasingStream(StreamingResponse):
        async def __call__(self, scope, receive, send):
            try:
                await super().__call__(scope, receive, send)
            finally:
                try:
                    await self.body_iterator.aclose()
                finally:
                    limits.release(self.uid)

    @app.post('/v1/story/stream')
    async def story(request: Request):
        uid, species, text, voice, style, key = await request_data(request, False)
        async def output():
            try:
                cached = cache.read(key)
                if cached is not None:
                    for offset in range(0, len(cached), 8192):
                        yield cached[offset:offset + 8192]
                    return
                pcm = bytearray()
                async with aclosing(provider.stream(voice, text, style)) as upstream:
                    async for chunk in upstream:
                        pcm.extend(chunk)
                        if len(pcm) > MAX_PCM_BYTES:
                            raise SynthesisError('audio_too_large')
                        yield chunk
                cache.write(key, bytes(pcm))
            finally:
                limits.release(uid)
        response = ReleasingStream(output(), media_type='application/octet-stream', headers={
            'X-Audio-Format': 's16le', 'X-Audio-Sample-Rate': str(SAMPLE_RATE), 'X-Audio-Channels': '1',
            'X-Audio-Endian': 'little', 'X-Accel-Buffering': 'no', 'Cache-Control': 'no-store'})
        response.uid = uid
        return response

    @app.post('/v1/plaza/clip')
    async def plaza(request: Request):
        uid, species, text, voice, style, key = await request_data(request, True)
        try:
            pcm = cache.read(key)
            if pcm is None:
                pcm = await collect_until_disconnect(request, provider, voice, text, style)
                cache.write(key, pcm)
            return Response(wav_bytes(pcm), media_type='audio/wav', headers={
                'ETag': '"' + key + '"', 'Cache-Control': 'private, max-age=86400'})
        except (SynthesisError, TimeoutError):
            raise HTTPException(502, 'synthesis_unavailable') from None
        finally:
            limits.release(uid)
    app.state.limits = limits
    return app
