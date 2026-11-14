"""Register one reviewed character sample; preserve voice IDs across retries."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import wave
import httpx
from .app import MODEL, default_lines


def validate_sample(path):
    data = path.read_bytes()
    if len(data) > 10 * 1024 * 1024:
        raise ValueError('Sample must be at most 10 MB')
    with wave.open(str(path)) as wav:
        seconds = wav.getnframes() / wav.getframerate()
        if (wav.getsampwidth() != 2 or wav.getnchannels() != 1 or wav.getframerate() < 16000
                or wav.getcomptype() != 'NONE' or not 5 <= seconds <= 60):
            raise ValueError('Use mono PCM16 WAV >=16kHz, 5–60 seconds (10–20 seconds recommended)')
    return data


def save_registry(path, registry):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            json.dump(registry, out, ensure_ascii=False, indent=2)
            out.write('\n')
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def enroll(sample, species, registry_path, region, workspace, api_key, client=None):
    stories, plaza = default_lines()
    if species not in stories | {s for s, _ in plaza}:
        raise ValueError('Unknown character')
    if region not in ('ap-southeast-1', 'cn-beijing') or not workspace or not all(c.isalnum() or c == '-' for c in workspace):
        raise ValueError('Valid region and workspace required')
    data = validate_sample(sample)
    digest = hashlib.sha256(data).hexdigest()
    registry = json.loads(registry_path.read_text()) if registry_path.exists() else {
        'model': MODEL, 'region': region, 'workspace': workspace, 'voices': {}}
    if any(registry.get(k) != v for k, v in [('model', MODEL), ('region', region), ('workspace', workspace)]):
        raise ValueError('Registry account/region/model mismatch; use a separate registry')
    existing = registry['voices'].get(species, {})
    if existing.get('reference_sha256') == digest and existing.get('voice_id'):
        return 'already_registered'
    if existing and existing.get('reference_sha256') != digest:
        raise ValueError('Reference changed; use a new registry and review all voices before switching')
    if not api_key:
        raise ValueError('DASHSCOPE_API_KEY is not configured')
    owned = client is None
    client = client or httpx.Client(timeout=60)
    url = f'https://{workspace}.{region}.maas.aliyuncs.com/api/v1/services/audio/tts/customization'
    def post(input_data):
        try:
            reply = client.post(url, headers={'Authorization': 'Bearer ' + api_key},
                                json={'model': 'voice-enrollment', 'input': input_data})
            reply.raise_for_status()
            return reply.json()['output']
        except Exception:
            raise RuntimeError('DashScope enrollment failed; check account/model/region/sample') from None
    try:
        voice = existing.get('pending_voice_id')
        if not voice:
            voice = post({'action': 'create_voice', 'target_model': MODEL,
                          'prefix': hashlib.sha256(species.encode()).hexdigest()[:10],
                          'audio': 'data:audio/wav;base64,' + base64.b64encode(data).decode(),
                          'language_hints': ['ko']})['voice_id']
            if not isinstance(voice, str) or not voice:
                raise RuntimeError('Missing voice ID')
            registry['voices'][species] = {'pending_voice_id': voice, 'reference_sha256': digest}
            save_registry(registry_path, registry)
        for _ in range(30):
            details = post({'action': 'query_voice', 'voice_id': voice})
            status = details.get('status')
            if status == 'OK':
                if details.get('target_model') != MODEL:
                    raise RuntimeError('Registered voice target_model mismatch')
                registry['voices'][species] = {'voice_id': voice, 'reference_sha256': digest}
                save_registry(registry_path, registry)
                return 'registered'
            if status != 'DEPLOYING':
                raise RuntimeError('Voice not approved; inspect the Model Studio console')
            time.sleep(1)
        return 'pending_review_rerun_to_check'
    finally:
        if owned:
            client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path)
    parser.add_argument('--species', required=True)
    parser.add_argument('--sample', type=Path, required=True)
    parser.add_argument('--registry', type=Path, default=Path('server/tts/voices.local.json'))
    args = parser.parse_args()
    if args.env_file:
        from dotenv import load_dotenv
        load_dotenv(args.env_file, override=False)
    try:
        print(enroll(args.sample, args.species, args.registry, os.environ.get('DASHSCOPE_REGION', ''),
                     os.environ.get('DASHSCOPE_WORKSPACE_ID', ''), os.environ.get('DASHSCOPE_API_KEY', '')))
    except (ValueError, RuntimeError, KeyError, wave.Error):
        # No provider response, token, reference audio or URL in command output.
        parser.exit(1, 'Registration incomplete: check configuration, sample requirements and model access.\n')


if __name__ == '__main__':
    main()
