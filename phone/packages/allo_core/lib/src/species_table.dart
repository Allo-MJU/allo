import 'dart:math';

import 'models.dart';
import 'rarity_engine.dart';

/// data/species.json 을 들고 판정 결과에 맞는 종을 고른다.
class SpeciesTable {
  final List<Species> all;
  const SpeciesTable(this.all);

  factory SpeciesTable.fromJson(Map<String, dynamic> json) =>
      SpeciesTable((json['species'] as List)
          .map((e) => Species.fromJson(e as Map<String, dynamic>))
          .toList());

  Species? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 희귀종(복합 조건) 우선 → 속성·tier 일치 → 같은 속성 낮은 tier 로 내려감.
  Species pick(RarityResult r, Set<String> seenTags, {Random? random}) {
    final rng = random ?? Random();

    final rare = all
        .where((s) => s.requiredTags.length >= 2 && _meets(s, r, seenTags))
        .toList();
    if (rare.isNotEmpty) return rare[rng.nextInt(rare.length)];

    for (var t = r.tier; t >= 1; t--) {
      final c = all
          .where((s) =>
              s.requiredTags.length < 2 &&
              s.attribute == r.attribute &&
              s.tier == t &&
              _meets(s, r, seenTags))
          .toList();
      if (c.isNotEmpty) return c[rng.nextInt(c.length)];
    }
    // 마지막 보루: normal tier 1
    return all.firstWhere((s) => s.attribute == Attribute.normal && s.tier == 1,
        orElse: () => all.first);
  }

  Species? pickUnseen(RarityResult r, Set<String> seenTags, Set<String> owned,
      {Random? random}) {
    final remaining = all.where((s) => !owned.contains(s.id)).toList();
    if (remaining.isEmpty) return null;
    final rng = random ?? Random();
    final rare = remaining
        .where((s) => s.requiredTags.length >= 2 && _meets(s, r, seenTags))
        .toList();
    if (rare.isNotEmpty) return rare[rng.nextInt(rare.length)];
    for (var t = r.tier; t >= 1; t--) {
      final candidates = remaining
          .where((s) =>
              s.requiredTags.length < 2 &&
              s.attribute == r.attribute &&
              s.tier == t &&
              _meets(s, r, seenTags))
          .toList();
      if (candidates.isNotEmpty)
        return candidates[rng.nextInt(candidates.length)];
    }
    final eligible = remaining.where((s) => _meets(s, r, seenTags)).toList();
    final candidates = eligible.isNotEmpty ? eligible : remaining;
    return candidates[rng.nextInt(candidates.length)];
  }

  bool _meets(Species s, RarityResult r, Set<String> seenTags) {
    if (!s.requiredTags.every(seenTags.contains)) return false;
    if (r.supportedTags != null &&
        !s.requiredTags.every(r.supportedTags!.contains)) {
      return false;
    }
    if (s.maxHarsh != null && r.harshTotal > s.maxHarsh!) return false;
    return true;
  }

  /// 모든 종에 도달 가능한 (태그, harsh) 조합이 존재하는지. C-6 완료 기준용.
  List<Species> unreachable() => all.where((s) {
        final tags = s.requiredTags.toSet();
        final r =
            RarityResult(attribute: s.attribute, tier: s.tier, harshTotal: 0);
        return !_meets(s, r, tags);
      }).toList();
}
