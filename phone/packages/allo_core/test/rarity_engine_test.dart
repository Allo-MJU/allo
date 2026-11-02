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
}
