"""Finite vehicle TTS allowlists from the same catalogs used by DialogueBank.

Both reviewed/release and unreviewed/debug outputs are accepted; the app owns its
release review filter. Neither endpoint accepts arbitrary text or user speech.
"""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
CAR = Path('car/app/src/main/java/ai/allo/car')
QUESTIONS = ('ask_name', 'ask_origin', 'ask_like', 'ask_mood')
REGIONS = {'coast': '바다', 'mountain': '산', 'city': '도심'}
JOSA = re.compile(r'\{([a-z_]+):([^/{}]+)/([^/{}]+)\}')
SLOT = re.compile(r'\{([a-z_]+)\}')
DIALOGUE_FALLBACK = '이 질문의 답변은 아직 준비 중이에요.'
DESTINATION_FIXED = {
    '지금은 추가로 제안할 곳이 없어요.',
    '바다·산·도심에서 모두 아이를 만났어요. 지금은 따로 추천할 곳이 없어요.',
    '아직 아이를 못 만난 곳이 지금 계신 지역이에요. 다른 지역은 추천할 곳이 없어요.',
    '가까운 곳에서 추천할 장소를 찾지 못했어요.',
    '지금 추천할 장소는 여기까지예요.',
    '지금은 길 안내 중이에요. 안내가 끝나면 다시 물어봐 주세요.',
    '먼저 어디로 갈지 물어봐 주세요.',
    '지금은 길 안내 중이라 목적지를 바꾸지 않을게요.',
    '지금은 내비에 목적지를 넣지 못했어요. 잠시 뒤에 다시 말해 주세요.',
    '제안 상태가 바뀌었어요. 다시 요청해 주세요.',
    '먼저 목적지를 추천해 달라고 말해 주세요.',
}


def render(template, values):
    def particle(m):
        value = values.get(m[1])
        if value is None: return m[0]
        last = value.rstrip()[-1:] if value else ''
        jong = (ord(last) - ord('가')) % 28 if last and '가' <= last <= '힣' else 0
        return m[3] if jong == 0 or (m[2] == '으로' and jong == 8) else m[2]
    out = JOSA.sub(particle, template)
    out = SLOT.sub(lambda m: values.get(m[1], m[0]), out)
    return None if '{' in out else out


def build_car_lines(root=ROOT):
    root = Path(root)
    characters = {s['id']: s for s in json.loads((root/'data/characters.json').read_text())['species']}
    species = {s['id']: s for s in json.loads((root/'data/species.json').read_text())['species']}
    species.update(characters)  # DialogueBank.supplementedBy display names/attributes win.
    catalogs = [json.loads((root/p).read_text())['entries'] for p in (
        'data/dialogue.json', 'car/app/src/main/assets/companion-dialogue.json')]
    banks = []
    for include_unreviewed in (False, True):
        bank = {}
        for entries in catalogs:
            bank.update({e['key']: e['lines'] for e in entries if include_unreviewed or e.get('reviewedBy')})
        banks.append(bank)
    dialogue = {(s, DIALOGUE_FALLBACK) for s in characters}
    for speaker in characters:
        metadata = species[speaker]
        for bank in banks:
            for question in QUESTIONS:
                for target in (speaker, '@'+metadata['attribute'], '*'):
                    rendered = [render(t, {'name': metadata['nameKo']})
                                for t in bank.get(f'{question}|{target}|hatched', [])]
                    valid = [t for t in rendered if t is not None]
                    if valid:
                        dialogue.update((speaker, t) for t in valid)
                        break
    code = (root/CAR/'gleo/DestinationSuggester.kt').read_text()
    candidates = re.findall(r'Destination\("(coast|mountain|city)", "([^"\n]+)", [-\d.]+, [-\d.]+\)', code)
    if not candidates or len(candidates) != code.count('        Destination('):
        raise ValueError('Unsupported destination catalog syntax')
    limit = re.search(r'const val MAX_KM = (\d+)\.0', code)
    if not limit: raise ValueError('Unsupported destination distance bound')
    distances = [''] + [f' 직선으로 약 {km}km예요.' for km in range(5, int(limit[1])+1, 5)]
    destination = set(DESTINATION_FIXED)
    for bank in banks:
        for key, templates in bank.items():
            if key.startswith(('car_suggest_none|*|', 'car_accept|*|')):
                for template in templates:
                    text = render(template, {})
                    if text is not None: destination.add(text)
        for region, place in candidates:
            word = REGIONS[region]
            for km in distances:
                values = {'region_word': word, 'place': place, 'km': km}
                for situation in ('first', 'uncollected', 'alt'):
                    for template in bank.get(f'car_suggest|*|{situation}', []):
                        text = render(template, values)
                        if text is not None: destination.add(text)
                # GleoFunctions fallback when catalogs cannot be loaded/rendered.
                ira = word + ('이라면' if word[-1] in ('산', '심') else '라면')
                destination.update((f'{word} 쪽 {place}도 있어요.{km} 안내할까요?',
                    f'아직 {word}에서 만난 아이가 없어요. {place}까지 안내할까요?{km}',
                    f'{word} 쪽 {place}까지 안내할까요?{km} 같은 {ira} 다른 곳도 괜찮아요.'))
            destination.add(f'{place}까지 안내를 요청했어요.')
            for template in bank.get('car_accept|*|ok', []):
                text = render(template, {'place': place})
                if text is not None: destination.add(text)
    return dialogue, {(s, t) for s in characters for t in destination}
