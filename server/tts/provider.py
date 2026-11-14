"""DashScope duplex TTS. Only the server holds the provider credential."""
import asyncio
import json
import uuid
from contextlib import suppress

SAMPLE_RATE = 24000
MAX_PCM_BYTES = SAMPLE_RATE * 2 * 60


class SynthesisError(Exception):
    pass


class DashScope:
    def __init__(self, api_key, workspace, region, model, connector=None):
        if region not in ('ap-southeast-1', 'cn-beijing'):
            raise ValueError('Unsupported DashScope region')
        if not workspace or not all(c.isalnum() or c == '-' for c in workspace):
            raise ValueError('Workspace ID is required')
        if not api_key:
            raise ValueError('DASHSCOPE_API_KEY is required')
        self.url = f'wss://{workspace}.{region}.maas.aliyuncs.com/api-ws/v1/inference'
        self.api_key, self.model = api_key, model
        if connector is None:
            from websockets.asyncio.client import connect
            connector = connect
        self.connect = connector

    async def stream(self, voice, text, style=None):
        style = style or {}
        task_id = str(uuid.uuid4())
        def command(action, payload):
            return json.dumps({'header': {'action': action, 'task_id': task_id, 'streaming': 'duplex'},
                               'payload': payload})
        finished = False
        total = 0
        pending = b''
        try:
            async with self.connect(self.url, additional_headers={'Authorization': 'Bearer ' + self.api_key},
                                    open_timeout=10, close_timeout=2, max_size=MAX_PCM_BYTES) as ws:
                try:
                    async with asyncio.timeout(60):
                        parameters = {
                            'text_type': 'PlainText', 'voice': voice, 'format': 'pcm',
                            'sample_rate': SAMPLE_RATE, 'language_hints': ['ko'], 'volume': 50,
                            'rate': style.get('rate', 1.0), 'pitch': style.get('pitch', 1.0), 'enable_ssml': False}
                        if style.get('instruction'):
                            parameters['instruction'] = style['instruction']
                        await ws.send(command('run-task', {'task_group': 'audio', 'task': 'tts',
                            'function': 'SpeechSynthesizer', 'model': self.model, 'parameters': parameters,
                            'input': {}}))
                        started = False
                        while True:
                            message = await asyncio.wait_for(ws.recv(), 15)
                            if isinstance(message, bytes):
                                if not started:
                                    raise SynthesisError('audio_before_start')
                                total += len(message)
                                if total > MAX_PCM_BYTES:
                                    raise SynthesisError('audio_too_large')
                                pending += message
                                aligned = len(pending) // 2 * 2
                                if aligned:
                                    yield pending[:aligned]
                                    pending = pending[aligned:]
                                continue
                            event = json.loads(message)['header']
                            if event.get('task_id') != task_id:
                                raise SynthesisError('wrong_task')
                            kind = event.get('event')
                            if kind == 'task-started' and not started:
                                started = True
                                await ws.send(command('continue-task', {'input': {'text': text}}))
                                await ws.send(command('finish-task', {'input': {}}))
                            elif kind == 'task-finished':
                                if not started or not total or pending:
                                    raise SynthesisError('invalid_audio')
                                finished = True
                                return
                            elif kind == 'task-failed':
                                raise SynthesisError('provider_failed')
                finally:
                    if not finished:
                        # Closing the downstream stream cancels synthesis too. Never cache partial output.
                        with suppress(Exception):
                            await asyncio.wait_for(ws.send(command('finish-task', {'input': {'directive': 'cancel'}})), 1)
        except (asyncio.CancelledError, GeneratorExit):
            raise
        except Exception:
            # Provider errors may contain credentials or transcripts. Do not propagate bodies.
            raise SynthesisError('synthesis_unavailable') from None
