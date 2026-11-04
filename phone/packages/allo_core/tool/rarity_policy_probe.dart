import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:allo_core/allo_core.dart';

/// 관측용. 미결정 결과를 테스트 기대값이나 제품 정책으로 확정하지 않는다.
/// Run from the repository root:
/// dart run phone/packages/allo_core/tool/rarity_policy_probe.dart
void main() {
  const engine = RarityEngine();
  final source =
      File.fromUri(Platform.script.resolve('../../../../data/species.json'));
  final table = SpeciesTable.fromJson(
      jsonDecode(source.readAsStringSync()) as Map<String, dynamic>);
  final cases = <({
    String name,
    Set<String> tags,
    int harsh,
    int care,
    List<String> caps
  })>[
    (
      name: 'rain+tunnel / light only',
      tags: {'rain', 'tunnel'},
      harsh: 0,
      care: 0,
      caps: ['light']
    ),
    (
      name: 'rain+tunnel / wiper only',
      tags: {'rain', 'tunnel'},
      harsh: 0,
      care: 0,
      caps: ['wiper']
    ),
    (
      name: 'rain+tunnel / no capabilities',
      tags: {'rain', 'tunnel'},
      harsh: 0,
      care: 0,
      caps: []
    ),
    (
      name: 'rain / harsh3 / care3',
      tags: {'rain'},
      harsh: 3,
      care: 3,
      caps: ['wiper', 'light']
    ),
    (
      name: 'night / harsh3',
      tags: {'night'},
      harsh: 3,
      care: 0,
      caps: ['wiper', 'light']
    ),
    (
      name: 'rain+tunnel / harsh3 / rare first',
      tags: {'rain', 'tunnel'},
      harsh: 3,
      care: 0,
      caps: ['wiper', 'light']
    ),
    (
      name: 'rain+highway+night / supported attribute override',
      tags: {'rain', 'highway', 'night'},
      harsh: 0,
      care: 0,
      caps: ['wiper', 'light']
    ),
    (
      name: 'highway+night / no light',
      tags: {'highway', 'night'},
      harsh: 0,
      care: 0,
      caps: ['wiper']
    ),
    (
      name: 'rain+tunnel+coast / competing rares',
      tags: {'rain', 'tunnel', 'coast'},
      harsh: 0,
      care: 0,
      caps: ['wiper', 'light']
    ),
  ];

  for (final c in cases) {
    final result = engine.judge(
      seenTags: c.tags,
      harshBrake: c.harsh,
      harshSteer: 0,
      careCount: c.care,
      capabilities: c.caps,
    );
    final current = table.pick(result, c.tags, random: Random(1));
    // Comparison only: apply the engine's existing known-signal gates before pick.
    // Region/highway tags remain intact; no new capability mapping is assumed.
    final supportedTags = c.tags
        .where((tag) => switch (tag) {
              'rain' => c.caps.contains('wiper'),
              'tunnel' || 'night' => c.caps.contains('light'),
              _ => true,
            })
        .toSet();
    final supportFiltered =
        table.pick(result, supportedTags, random: Random(1));
    stdout.writeln(jsonEncode({
      'case': c.name,
      'tags': c.tags.toList(),
      'capabilities': c.caps,
      'harsh': c.harsh,
      'care': c.care,
      'judged': {
        'attribute': result.attribute.name,
        'tier': result.tier,
        'harshTotal': result.harshTotal
      },
      'currentPick': describe(current),
      'supportedTagsExperiment': {
        'tags': supportedTags.toList(),
        'pick': describe(supportFiltered)
      },
    }));
  }
}

Map<String, Object> describe(Species species) => {
      'id': species.id,
      'attribute': species.attribute.name,
      'catalogTier': species.tier,
    };
