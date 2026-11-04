import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

void main() {
  const e = RarityEngine();

  test('급제동 0회 + rain → water, tier 3', () {
    final r = e.judge(seenTags: {'rain'}, harshBrake: 0, harshSteer: 0);
    expect(r.attribute, Attribute.water);
    expect(r.tier, 3);
  });

  test('급제동 10회 + rain → water, tier 1', () {
    final r = e.judge(seenTags: {'rain'}, harshBrake: 10, harshSteer: 0);
    expect(r.attribute, Attribute.water);
    expect(r.tier, 1);
  });

  test('태그 없음 → normal', () {
    expect(e.judge(seenTags: {}, harshBrake: 0, harshSteer: 0).attribute, Attribute.normal);
  });

  test('rain + tunnel → rain 우선', () {
    expect(e.attributeFor({'rain', 'tunnel'}), Attribute.water);
    expect(e.attributeFor({'tunnel', 'highway'}), Attribute.dark);
    expect(e.attributeFor({'night'}), Attribute.dark);
  });

  test('차가 wiper 를 못 읽으면 rain 이 있어도 water 가 안 나온다', () {
    expect(e.attributeFor({'rain'}, capabilities: ['light', 'seat']), Attribute.normal);
  });

  test('케어 3회가 급제동 1회를 상쇄한다', () {
    expect(e.tierFor(harshBrake: 3, harshSteer: 0, careCount: 0), 2);
    expect(e.tierFor(harshBrake: 3, harshSteer: 0, careCount: 3), 3);
  });

  // 현행 기본 설정의 경계를 검증한다. 밸런스 값을 변경하면 합의된 기준으로 갱신한다.
  test('현행 급격 조작 합계 2/3, 6/7 경계에서 등급이 바뀐다', () {
    for (final entry in {2: 3, 3: 2, 6: 2, 7: 1}.entries) {
      final r = e.judge(seenTags: {}, harshBrake: entry.key, harshSteer: 0);
      expect(r.tier, entry.value, reason: '급격 조작 합계 ${entry.key}회');
    }
  });

  test('돌봄은 3회 단위로 상쇄하고 과다 돌봄도 최대 등급 3을 넘지 않는다', () {
    for (final entry in {2: 2, 3: 3, 100: 3}.entries) {
      final r = e.judge(
        seenTags: {}, harshBrake: 3, harshSteer: 0, careCount: entry.key,
      );
      expect(r.tier, entry.value, reason: '급격 조작 3회, 돌봄 ${entry.key}회');
    }
  });

  test('급제동과 급조향을 합산해 등급과 원래 조작 횟수를 계산한다', () {
    final mixed = e.judge(seenTags: {}, harshBrake: 3, harshSteer: 4);
    final steerOnly = e.judge(seenTags: {}, harshBrake: 0, harshSteer: 7);

    expect(mixed.tier, 1);
    expect(mixed.harshTotal, 7);
    expect(steerOnly.tier, mixed.tier);
    expect(steerOnly.harshTotal, mixed.harshTotal);
  });

  test('wiper 지원 시 운전 품질로 등급이 달라도 rain의 물 속성은 유지된다', () {
    for (final entry in {2: 3, 3: 2, 7: 1}.entries) {
      final r = e.judge(
        seenTags: {'rain', 'tunnel', 'night'},
        harshBrake: entry.key, harshSteer: 0,
        capabilities: ['wiper', 'light'],
      );
      expect(r.attribute, Attribute.water);
      expect(r.tier, entry.value);
    }
  });

  test('light 미지원이면 tunnel과 night 모두 dark를 주지 않는다', () {
    for (final tag in ['tunnel', 'night']) {
      final r = e.judge(
        seenTags: {tag}, harshBrake: 0, harshSteer: 0,
        capabilities: ['wiper', 'seat'],
      );
      expect(r.attribute, Attribute.normal, reason: '$tag에 필요한 light 없음');
      expect(r.tier, 3);
    }
  });

  test('rain을 지원하지 않아도 light가 있으면 tunnel 속성을 선택한다', () {
    final r = e.judge(
      seenTags: {'rain', 'tunnel'}, harshBrake: 7, harshSteer: 0,
      capabilities: ['light'],
    );

    expect(r.attribute, Attribute.dark);
    expect(r.tier, 1);
  });
}
