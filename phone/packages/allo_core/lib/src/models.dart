/// docs/schema.md 3장과 1:1 로 맞춘다. 필드를 바꾸면 schema.md 먼저.

enum EggTier {
  small(10_000),
  mid(50_000),
  large(150_000);

  /// 거리 폴백의 목표 거리(m). 부화는 이 값의 50% 지점.
  final int targetM;
  const EggTier(this.targetM);

  static EggTier parse(String s) => EggTier.values.firstWhere((e) => e.name == s, orElse: () => EggTier.small);
}

enum Attribute { normal, water, dark }

enum Stage { idle, incubating, hatched }

/// /sessions/{sid}/vehicle — 차량 앱이 1초마다 쓴다.
class VehicleState {
  final int ts;
  final String gear; // P R N D
  final double speedKph;
  final double distanceM; // 세션 누적
  final int harshBrake; // 세션 누적
  final int harshSteer;
  final int wiperLevel;
  final bool headlightOn;
  final bool seatRow2;
  final int? etaSec; // null = 내비 미사용
  final List<String> envTags;
  final List<String> capabilities;

  const VehicleState({
    required this.ts,
    required this.gear,
    required this.speedKph,
    required this.distanceM,
    required this.harshBrake,
    required this.harshSteer,
    required this.wiperLevel,
    required this.headlightOn,
    required this.seatRow2,
    required this.etaSec,
    required this.envTags,
    required this.capabilities,
  });

  factory VehicleState.fromJson(Map<String, dynamic> j) => VehicleState(
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        gear: j['gear'] as String? ?? 'P',
        speedKph: (j['speedKph'] as num?)?.toDouble() ?? 0,
        distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
        harshBrake: (j['harshBrake'] as num?)?.toInt() ?? 0,
        harshSteer: (j['harshSteer'] as num?)?.toInt() ?? 0,
        wiperLevel: (j['wiperLevel'] as num?)?.toInt() ?? 0,
        headlightOn: j['headlightOn'] as bool? ?? false,
        seatRow2: j['seatRow2'] as bool? ?? false,
        etaSec: (j['etaSec'] as num?)?.toInt(),
        envTags: (j['envTags'] as List?)?.cast<String>() ?? const [],
        capabilities: (j['capabilities'] as List?)?.cast<String>() ?? const [],
      );

  VehicleState copyWith({
    int? ts, String? gear, double? speedKph, double? distanceM, int? harshBrake, int? harshSteer,
    int? wiperLevel, bool? headlightOn, bool? seatRow2, int? etaSec, bool clearEta = false,
    List<String>? envTags, List<String>? capabilities,
  }) =>
      VehicleState(
        ts: ts ?? this.ts, gear: gear ?? this.gear, speedKph: speedKph ?? this.speedKph,
        distanceM: distanceM ?? this.distanceM, harshBrake: harshBrake ?? this.harshBrake,
        harshSteer: harshSteer ?? this.harshSteer, wiperLevel: wiperLevel ?? this.wiperLevel,
        headlightOn: headlightOn ?? this.headlightOn, seatRow2: seatRow2 ?? this.seatRow2,
        etaSec: clearEta ? null : (etaSec ?? this.etaSec),
        envTags: envTags ?? this.envTags, capabilities: capabilities ?? this.capabilities,
      );
}

/// /sessions/{sid}/game — 폰 앱이 계산해서 쓴다.
class GameState {
  final int ts;
  final EggTier eggTier;
  final Stage stage;
  final double progress;
  final String? speciesId;
  final Attribute? attribute;
  final int? tier;
  final int careCount;
  final int lookOutCount;
  final double? hatchAtM;
  final int? hatchAtSec;

  const GameState({
    required this.ts,
    required this.eggTier,
    required this.stage,
    required this.progress,
    this.speciesId,
    this.attribute,
    this.tier,
    this.careCount = 0,
    this.lookOutCount = 0,
    this.hatchAtM,
    this.hatchAtSec,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'eggTier': eggTier.name,
        'stage': stage.name,
        'progress': progress,
        'speciesId': speciesId,
        'attribute': attribute?.name,
        'tier': tier,
        'careCount': careCount,
        'lookOutCount': lookOutCount,
        'hatchAtM': hatchAtM,
        'hatchAtSec': hatchAtSec,
      };

  GameState copyWith({
    int? ts, EggTier? eggTier, Stage? stage, double? progress, String? speciesId, Attribute? attribute,
    int? tier, int? careCount, int? lookOutCount, double? hatchAtM, int? hatchAtSec,
  }) =>
      GameState(
        ts: ts ?? this.ts, eggTier: eggTier ?? this.eggTier, stage: stage ?? this.stage,
        progress: progress ?? this.progress, speciesId: speciesId ?? this.speciesId,
        attribute: attribute ?? this.attribute, tier: tier ?? this.tier,
        careCount: careCount ?? this.careCount, lookOutCount: lookOutCount ?? this.lookOutCount,
        hatchAtM: hatchAtM ?? this.hatchAtM, hatchAtSec: hatchAtSec ?? this.hatchAtSec,
      );
}

/// data/species.json 의 한 항목.
class Species {
  final String id;
  final String nameEn;
  final String nameKo;
  final Attribute attribute;
  final int tier;
  final List<String> requiredTags; // 전부 있어야 함
  final int? maxHarsh; // harshBrake + harshSteer 상한
  final String hint;
  final String sprite;

  const Species({
    required this.id,
    required this.nameEn,
    required this.nameKo,
    required this.attribute,
    required this.tier,
    required this.requiredTags,
    required this.maxHarsh,
    required this.hint,
    required this.sprite,
  });

  factory Species.fromJson(Map<String, dynamic> j) {
    final req = (j['requires'] as Map<String, dynamic>?) ?? const {};
    return Species(
      id: j['id'] as String,
      nameEn: j['nameEn'] as String,
      nameKo: j['nameKo'] as String,
      attribute: Attribute.values.firstWhere((a) => a.name == j['attribute']),
      tier: (j['tier'] as num).toInt(),
      requiredTags: (req['envTags'] as List?)?.cast<String>() ?? const [],
      maxHarsh: (req['maxHarsh'] as num?)?.toInt(),
      hint: j['hint'] as String? ?? '',
      sprite: j['sprite'] as String? ?? 'species/${j['id']}.png',
    );
  }
}

/// 도감 한 칸. 폰 로컬에만 저장한다 (서버 X).
class DexEntry {
  final String speciesId;
  final DateTime obtainedAt;
  final List<String> envTags; // 그날의 날씨·환경
  final String? regionTag; // coast / mountain / city — 좌표가 아니라 태그
  final int tier;

  const DexEntry({
    required this.speciesId,
    required this.obtainedAt,
    required this.envTags,
    required this.regionTag,
    required this.tier,
  });

  Map<String, dynamic> toJson() => {
        'speciesId': speciesId,
        'obtainedAt': obtainedAt.toIso8601String(),
        'envTags': envTags,
        'regionTag': regionTag,
        'tier': tier,
      };

  factory DexEntry.fromJson(Map<String, dynamic> j) => DexEntry(
        speciesId: j['speciesId'] as String,
        obtainedAt: DateTime.parse(j['obtainedAt'] as String),
        envTags: (j['envTags'] as List).cast<String>(),
        regionTag: j['regionTag'] as String?,
        tier: (j['tier'] as num).toInt(),
      );
}
