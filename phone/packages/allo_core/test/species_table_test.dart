import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

void main() {
  late SpeciesTable table;
  setUpAll(() {
    final file = File('../../../data/species.json');
    table = SpeciesTable.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  });

  test('12종이고 id 가 유일하다', () {
    expect(table.all.length, 12);
    expect(table.all.map((s) => s.id).toSet().length, 12);
  });

  test('속성 3 × tier 3 기본 9종이 모두 있다', () {
    for (final a in Attribute.values) {
      for (var t = 1; t <= 3; t++) {
        expect(table.all.where((s) => s.attribute == a && s.tier == t && s.requiredTags.length < 2), isNotEmpty,
            reason: '${a.name} tier $t 없음');
      }
    }
  });

  test('모든 종에 도달 가능한 조건이 있다', () {
    expect(table.unreachable(), isEmpty);
  });

  test('rain + 부드러운 운전 → water tier 3', () {
    const e = RarityEngine();
    final r = e.judge(seenTags: {'rain'}, harshBrake: 0, harshSteer: 0);
    final s = table.pick(r, {'rain'}, random: Random(1));
    expect(s.attribute, Attribute.water);
    expect(s.tier, 3);
  });

  test('rain + tunnel 복합 조건이면 희귀종이 우선한다', () {
    const e = RarityEngine();
    final r = e.judge(seenTags: {'rain', 'tunnel'}, harshBrake: 0, harshSteer: 0);
    final s = table.pick(r, {'rain', 'tunnel'}, random: Random(1));
    expect(s.requiredTags.length, greaterThanOrEqualTo(2));
  });
}
