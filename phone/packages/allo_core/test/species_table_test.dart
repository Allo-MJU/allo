import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

void main() {
  late SpeciesTable table;
  setUpAll(() {
    final file = File('../../../data/species.json');
    table = SpeciesTable.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  });

  test('12종이고 id 가 유일하다', () {
    expect(table.all.length, 12);
    expect(table.all.map((s) => s.id).toSet().length, 12);
  });

  test('속성 3 × tier 3 기본 9종이 모두 있다', () {
    for (final a in Attribute.values) {
      for (var t = 1; t <= 3; t++) {
        expect(
            table.all.where((s) =>
                s.attribute == a && s.tier == t && s.requiredTags.length < 2),
            isNotEmpty,
            reason: '${a.name} tier $t 없음');
      }
    }
  });

  test('실제 등급 판정과 종 선택을 거쳐 현재 12종에 모두 도달한다', () {
    const engine = RarityEngine();
    final cases = <({String id, Set<String> tags, int harsh})>[
      (id: 'road_sprout', tags: {}, harsh: 7),
      (id: 'bridge_hopper', tags: {}, harsh: 3),
      (id: 'mountain_sprite', tags: {}, harsh: 0),
      (id: 'puddle_pip', tags: {'rain'}, harsh: 7),
      (id: 'river_glider', tags: {'rain'}, harsh: 3),
      (id: 'tide_keeper', tags: {'rain'}, harsh: 0),
      (id: 'lamp_moth', tags: {'night'}, harsh: 7),
      (id: 'tunnel_moth', tags: {'tunnel'}, harsh: 3),
      (id: 'star_owl', tags: {'night'}, harsh: 0),
      (id: 'storm_lantern', tags: {'rain', 'tunnel'}, harsh: 0),
      (id: 'highway_comet', tags: {'highway', 'night'}, harsh: 0),
      (id: 'sea_mist', tags: {'coast', 'rain'}, harsh: 0),
    ];
    final reached = <String>{};

    for (final c in cases) {
      final result = engine.judge(
        seenTags: c.tags,
        harshBrake: c.harsh,
        harshSteer: 0,
        capabilities: ['wiper', 'light'],
      );
      final species = table.pick(result, c.tags, random: Random(1));

      expect(species.id, c.id, reason: '태그 ${c.tags}, 급제동 ${c.harsh}');
      reached.add(species.id);
    }

    expect(reached, table.all.map((s) => s.id).toSet());
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
    final r =
        e.judge(seenTags: {'rain', 'tunnel'}, harshBrake: 0, harshSteer: 0);
    final s = table.pick(r, {'rain', 'tunnel'}, random: Random(1));
    expect(s.requiredTags.length, greaterThanOrEqualTo(2));
  });
  test('지원하지 않는 태그는 희귀종과 일반종 선택에서 제외한다', () {
    const engine = RarityEngine();
    final cases = <({Set<String> tags, List<String> caps, String id})>[
      (tags: {'rain', 'tunnel'}, caps: ['light'], id: 'tunnel_moth'),
      (tags: {'rain', 'tunnel'}, caps: ['wiper'], id: 'tide_keeper'),
      (tags: {'rain', 'tunnel'}, caps: [], id: 'mountain_sprite'),
      (tags: {'highway', 'night'}, caps: ['wiper'], id: 'mountain_sprite'),
    ];
    for (final c in cases) {
      final result = engine.judge(
          seenTags: c.tags, harshBrake: 0, harshSteer: 0, capabilities: c.caps);
      expect(table.pick(result, c.tags, random: Random(1)).id, c.id);
    }
  });

  test('전체 지원 또는 지원 정보 생략 시 기존 희귀종 우선 정책을 유지한다', () {
    const engine = RarityEngine();
    final tags = {'rain', 'highway', 'night'};
    for (final caps in <List<String>?>[
      null,
      ['wiper', 'light']
    ]) {
      final result = engine.judge(
          seenTags: tags, harshBrake: 0, harshSteer: 0, capabilities: caps);
      expect(result.attribute, Attribute.water);
      expect(table.pick(result, tags, random: Random(1)).id, 'highway_comet');
    }
    const legacy =
        RarityResult(attribute: Attribute.water, tier: 3, harshTotal: 0);
    expect(table.pick(legacy, tags, random: Random(1)).id, 'highway_comet');
  });

  test('돌봄으로 보정한 등급과 종의 원시 급격 조작 조건은 별개다', () {
    const engine = RarityEngine();
    final tags = {'rain'};
    final result = engine.judge(
        seenTags: tags,
        harshBrake: 3,
        harshSteer: 0,
        careCount: 3,
        capabilities: ['wiper']);
    expect(result.tier, 3);
    expect(result.harshTotal, 3);
    expect(table.pick(result, tags, random: Random(1)).id, 'river_glider');
  });
  test('unseen priority, fallback, final species and complete catalog', () {
    const result =
        RarityResult(attribute: Attribute.water, tier: 3, harshTotal: 0);
    final tags = {'rain', 'tunnel'};
    final allIds = table.all.map((s) => s.id).toSet();
    expect(table.pickUnseen(result, tags, {}, random: Random(1))!.id,
        'storm_lantern');
    expect(
        table
            .pickUnseen(result, tags, {'storm_lantern'}, random: Random(1))!
            .id,
        'tide_keeper');
    expect(table.pickUnseen(result, tags, allIds.difference({'sea_mist'}))!.id,
        'sea_mist');
    expect(table.pickUnseen(result, tags, allIds), isNull);
  });
}
