"""Fixed quest copy from the existing story registry; no provider or user state."""
import json

from learning import CATALOG_PATH, LEGACY_PERSONAS_PATH, LearningError

BODY_LIMIT = 1024


class QuestTemplates:
    def __init__(self):
        self.stories = {s['speciesId']: s for s in json.loads(CATALOG_PATH.read_text(encoding='utf-8'))['stories']}
        self.profiles = {s['speciesId']: s for s in json.loads(LEGACY_PERSONAS_PATH.read_text(encoding='utf-8'))['profiles']}
        self.profiles.update(self.stories)

    def __call__(self, value):
        if not isinstance(value, dict) or set(value) != {'speciesId', 'kind', 'variant'}:
            raise LearningError(400, 'invalid_fields')
        species, kind, variant = value['speciesId'], value['kind'], value['variant']
        if not isinstance(species, str) or species not in self.profiles:
            raise LearningError(400, 'invalid_species')
        if not isinstance(kind, str) or kind not in ('food', 'story', 'travel'):
            raise LearningError(400, 'invalid_kind')
        if type(variant) is not int or not 0 <= variant <= 2147483647:
            raise LearningError(400, 'invalid_variant')
        if kind == 'story' and species not in self.stories:
            kind = 'food'
        slot = variant % 2
        story_id = None
        if kind == 'food':
            title = '베리 간식 부탁'
            text = ('오늘은 베리 간식이 먹고 싶어. 하나 나눠 줄래?',
                    '베리 간식을 같이 먹고 싶어. 하나 나눠 줄래?')[slot]
        elif kind == 'story':
            story = self.stories[species]
            story_id = story['storyId']
            title = '이야기와 함께 관찰하기'
            # Reference authored interests and title without extending events or claiming a real view.
            request = ('창밖에서 눈에 띄는 색 하나를 같이 찾아볼까?',
                       '창밖에서 눈에 띄는 모양 하나를 같이 찾아볼까?')[slot]
            interest = story["persona"]["interests"][0]
            text = f'내 관심사는 ‘{interest}’야. 「{story["title"]}」 이야기를 떠올리며, {request} 살펴봤다면 알려 줘.'
        else:
            title = '함께 바다 보러 가기'
            # Visit history and exact destination selection belong to the authenticated client flow.
            text = ('바다를 함께 보러 갈까?', '바닷가 풍경을 함께 보러 가고 싶어. 같이 갈까?')[slot]
        return {
            'schemaVersion': 1, 'templateId': f'{species}_{kind}_{slot}', 'templateVersion': 1,
            'speciesId': species, 'kind': kind, 'title': title, 'text': text,
            'storyId': story_id, 'targetFoodId': 'berry_snack' if kind == 'food' else None,
            'targetRegion': 'coast' if kind == 'travel' else None,
        }
