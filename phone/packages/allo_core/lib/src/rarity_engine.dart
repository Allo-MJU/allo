import 'models.dart';

/// 희귀도 판정. docs/roadmap.md C-2.
///
/// - 주행 품질 → tier(1~3). 급제동·급조향이 적을수록 높다.
/// - 환경 태그 → attribute. rain → water, tunnel/night → dark, 없으면 normal.
/// - 둘은 독립이다. 거친 운전으로도 물 속성은 나오되 tier 가 낮다.
class RarityEngine {
  /// tier 3 허용 상한, tier 2 허용 상한. 그 위는 tier 1.
  final int tier3MaxHarsh;
  final int tier2MaxHarsh;

  /// 케어(감싸기·노래) 몇 회가 급제동 1회를 상쇄하는가.
  final int carePerHarsh;

  const RarityEngine(
      {this.tier3MaxHarsh = 2, this.tier2MaxHarsh = 6, this.carePerHarsh = 3});

  /// 태그가 여러 개면 우선순위: rain > tunnel > night.
  Attribute attributeFor(Iterable<String> envTags,
      {Iterable<String>? capabilities}) {
    final tags = _supportedTags(envTags, capabilities);
    if (tags.contains('rain')) return Attribute.water;
    if (tags.contains('tunnel') || tags.contains('night')) {
      return Attribute.dark;
    }
    return Attribute.normal;
  }

  Set<String> _supportedTags(
      Iterable<String> envTags, Iterable<String>? capabilities) {
    final caps = capabilities?.toSet();
    return envTags.where((tag) {
      if (caps == null) return true;
      if (tag == 'rain') return caps.contains('wiper');
      if (tag == 'tunnel' || tag == 'night') return caps.contains('light');
      return true;
    }).toSet();
  }

  /// 급제동+급조향 합에서 케어로 상쇄한 뒤 tier 를 정한다.
  int tierFor(
      {required int harshBrake, required int harshSteer, int careCount = 0}) {
    final offset = carePerHarsh > 0 ? careCount ~/ carePerHarsh : 0;
    final harsh = (harshBrake + harshSteer - offset).clamp(0, 1 << 30);
    if (harsh <= tier3MaxHarsh) return 3;
    if (harsh <= tier2MaxHarsh) return 2;
    return 1;
  }

  /// 세션의 누적 태그(주행 내내 본 태그의 합집합)로 판정한다.
  RarityResult judge({
    required Set<String> seenTags,
    required int harshBrake,
    required int harshSteer,
    int careCount = 0,
    Iterable<String>? capabilities,
  }) {
    final supportedTags =
        Set<String>.unmodifiable(_supportedTags(seenTags, capabilities));
    return RarityResult(
      attribute: attributeFor(supportedTags),
      tier: tierFor(
          harshBrake: harshBrake, harshSteer: harshSteer, careCount: careCount),
      harshTotal: harshBrake + harshSteer,
      supportedTags: supportedTags,
    );
  }
}

class RarityResult {
  final Attribute attribute;
  final int tier;
  final int harshTotal;
  final Set<String>? supportedTags;
  const RarityResult(
      {required this.attribute,
      required this.tier,
      required this.harshTotal,
      this.supportedTags});

  @override
  String toString() =>
      'RarityResult(${attribute.name}, tier $tier, harsh $harshTotal)';
}
