#!/usr/bin/env python3
"""Export current mobile/plaza lines for cloud synthesis; never calls a provider."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import wave

ROOT = Path(__file__).resolve().parents[1]
STORY = Path('unity/allo_explore/Assets/Resources/StoryVoice')
PLAZA = Path('car/app/src/main/assets/plaza_voice')
PLAZA_CODE = Path('car/app/src/main/java/ai/allo/car/voice/PlazaRecordings.kt')


def build_manifest(root=ROOT):
    catalog = json.loads((root / STORY / 'catalog.json').read_text())['entries']
    packs = json.loads((root / 'phone/assets/data/window_stories_ko.json').read_text())['packs']
    current = {(p['id'], n['id']): n['line'] for p in packs for n in p['nodes']}
    by_node = {}
    narrators = {}
    for entry in catalog:
        key = (entry['topicId'], entry['nodeId'])
        if key in by_node or current.get(key) != entry['text']:
            raise ValueError(f'Duplicate or stale story catalog entry: {key}')
        by_node[key] = entry
        narrators.setdefault(entry['topicId'], set()).add(entry['species'])
    if any(len(v) != 1 for v in narrators.values()):
        raise ValueError('Each story must have exactly one narrator')
    jobs = {}
    story_entries = []

    def add(species, text, target, consumer):
        if not re.fullmatch(r'[a-z][a-z0-9_]*', species) or not text:
            raise ValueError('Invalid speaker or empty transcript')
        # Identical text may only share audio within the SAME character.
        key = hashlib.sha256((species + '\n' + text).encode()).hexdigest()
        job = jobs.setdefault(key, {'id': key, 'species': species, 'text': text,
                                    'language': 'Korean', 'targets': [], 'consumers': []})
        if target not in job['targets']:
            job['targets'].append(target)
        job['consumers'].append(consumer)

    for pack in packs:
        species = next(iter(narrators[pack['id']]))
        for node in pack['nodes']:
            entry = by_node.get((pack['id'], node['id']))
            # Unrecorded or revised lines are synthesized from the actual UI text.
            resource = entry['resource'] if entry else f"StoryVoice/{species}/{pack['id']}_{node['id']}"
            target = f'unity/allo_explore/Assets/Resources/{resource}.wav'
            add(species, node['line'], target, f"story/{pack['id']}/{node['id']}")
            story_entries.append(dict(topicId=pack['id'], nodeId=node['id'],
                                      text=node['line'], species=species, resource=resource))
    code = (root / PLAZA_CODE).read_text()
    entries = re.findall(r'Entry\("([a-z_]+)", "([^"\n]+)", "(plaza_voice/[^"\n]+\.wav)"\)', code)
    if len(entries) != code.count('        Entry('):
        raise ValueError('Unsupported plaza catalog syntax; cannot safely extract every line')
    if not entries:
        raise ValueError('Empty plaza catalog')
    for species, text, asset in entries:
        add(species, text, f'car/app/src/main/assets/{asset}', f'plaza/{species}/{Path(asset).stem}')
    targets = {}
    for job in jobs.values():
        for target in job['targets']:
            if target in targets and targets[target] != job['id']:
                raise ValueError(f'Conflicting transcripts for {target}')
            targets[target] = job['id']
    references = {}
    for species in sorted({j['species'] for j in jobs.values()}):
        # Shared characters keep the story voice on both screens.
        folder = STORY / species if (root / STORY / species).is_dir() else PLAZA / species
        candidates = []
        for path in sorted((root / folder).glob('*.wav')):
            with wave.open(str(path)) as wav:
                if wav.getsampwidth() != 2 or wav.getframerate() < 16000 or wav.getcomptype() != 'NONE':
                    raise ValueError(f'Invalid reference WAV: {path}')
                seconds = wav.getnframes() / wav.getframerate()
            candidates.append({'path': str(path.relative_to(root)), 'seconds': round(seconds, 4),
                               'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        if not candidates:
            raise ValueError(f'No original voice reference for {species}')
        references[species] = {'candidates': sorted(candidates, key=lambda x: -x['seconds'])[:3],
                               'review': 'Audio quality and provider requirements must be checked before enrollment.'}
    return {'version': 1, 'provider': 'dashscope', 'model': None,
            'status': 'prepared_not_generated', 'references': references,
            'jobs': list(jobs.values()), 'storyCatalog': {'entries': story_entries}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'tasks/verification/dashscope/manifest.json')
    args = parser.parse_args()
    result = build_manifest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"Prepared {len(result['jobs'])} unique clips, {len(result['references'])} voices; no API calls or app changes.\n{args.output}")


if __name__ == '__main__':
    main()
