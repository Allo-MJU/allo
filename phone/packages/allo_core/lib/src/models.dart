/// docs/schema.md 3장과 1:1 로 맞춘다. 필드를 바꾸면 schema.md 먼저.

enum EggTier {
  small(10000),
  mid(50000),
  large(150000);

  /// 거리 폴백의 목표 거리(m). 부화는 이 값의 50% 지점.
  final int targetM;
  const EggTier(this.targetM);

  static EggTier parse(String s) => EggTier.values
      .firstWhere((e) => e.name == s, orElse: () => EggTier.small);
}

enum Attribute { normal, water, dark }

enum Stage { idle, incubating, hatched, failed }

/// 내비 경로의 다음 회전 하나. schema.md 3.3 `turns`. 창밖 표시 전용이며 판정에 쓰지 않는다.
class Turn {
  /// left | right | uturn | keepLeft | keepRight
  final String type;

  /// 그 회전까지 남은 거리(m)
  final int inM;

  const Turn(this.type, this.inM);

  static const types = {'left', 'right', 'uturn', 'keepLeft', 'keepRight'};

  /// 모르는 type 이나 깨진 값은 null (버린다)
  static Turn? tryParse(Object? j) {
    if (j is! Map) return null;
    final type = j['type'];
    final inM = j['inM'];
    if (type is! String ||
        !types.contains(type) ||
        inM is! num ||
        !inM.isFinite) {
      return null;
    }
    return Turn(type, inM.round().clamp(0, 1 << 30));
  }

  /// 가까운 순 최대 3개
  static List<Turn> parseList(Object? j) {
    if (j is! List) return const [];
    final out = [for (final e in j) Turn.tryParse(e)].whereType<Turn>().toList()
      ..sort((a, b) => a.inM.compareTo(b.inM));
    return out.take(3).toList();
  }

  Map<String, Object?> toJson() => {'type': type, 'inM': inM};

  @override
  bool operator ==(Object other) =>
      other is Turn && other.type == type && other.inM == inM;

  @override
  int get hashCode => Object.hash(type, inM);

  @override
  String toString() => 'Turn($type, ${inM}m)';
}

/// Optional steering-derived display cue. It never affects gameplay decisions.
class Cornering {
  const Cornering({required this.bend, required this.receivedAtMs});

  final double bend; // [-1, 1], negative left / positive right
  final int receivedAtMs; // SDK delivery time, not a hardware timestamp

  bool get isValid =>
      bend.isFinite &&
      bend >= -1 &&
      bend <= 1 &&
      receivedAtMs > 0 &&
      receivedAtMs <= 9007199254740991;

  static Cornering? parse(Object? value) {
    if (value is! Map || value['version'] != 1) return null;
    final bend = value['bend'];
    final timestamp = value['receivedAtMs'];
    if (bend is! num ||
        timestamp is! num ||
        !timestamp.isFinite ||
        timestamp <= 0 ||
        timestamp > 9007199254740991 ||
        timestamp != timestamp.toInt()) return null;
    final signal =
        Cornering(bend: bend.toDouble(), receivedAtMs: timestamp.toInt());
    return signal.isValid ? signal : null;
  }

  Map<String, Object> toJson() =>
      {'version': 1, 'bend': bend, 'receivedAtMs': receivedAtMs};
}

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
  final List<Turn> turns; // 누락 = 빈 목록
  final double? headingDeg; // 진행 방향 0~360 (북 0, 시계 방향). null = 모름
  final Cornering? cornering;
  final List<String> capabilities;

  /// Optional v1 parking/activity evidence. Missing or malformed is ineligible.
  final Map<String, dynamic>? fishingPresence;

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
    this.turns = const [],
    this.headingDeg,
    this.cornering,
    required this.capabilities,
    this.fishingPresence,
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
        turns: Turn.parseList(j['turns']),
        headingDeg: _heading(j['headingDeg']),
        cornering: Cornering.parse(j['cornering']),
        capabilities: (j['capabilities'] as List?)?.cast<String>() ?? const [],
        fishingPresence: j['fishingPresence'] is Map
            ? Map<String, dynamic>.from(j['fishingPresence'] as Map)
            : null,
      );

  VehicleState copyWith({
    int? ts,
    String? gear,
    double? speedKph,
    double? distanceM,
    int? harshBrake,
    int? harshSteer,
    int? wiperLevel,
    bool? headlightOn,
    bool? seatRow2,
    int? etaSec,
    bool clearEta = false,
    List<String>? envTags,
    List<Turn>? turns,
    double? headingDeg,
    Cornering? cornering,
    bool clearCornering = false,
    List<String>? capabilities,
    Map<String, dynamic>? fishingPresence,
  }) =>
      VehicleState(
        ts: ts ?? this.ts,
        gear: gear ?? this.gear,
        speedKph: speedKph ?? this.speedKph,
        distanceM: distanceM ?? this.distanceM,
        harshBrake: harshBrake ?? this.harshBrake,
        harshSteer: harshSteer ?? this.harshSteer,
        wiperLevel: wiperLevel ?? this.wiperLevel,
        headlightOn: headlightOn ?? this.headlightOn,
        seatRow2: seatRow2 ?? this.seatRow2,
        etaSec: clearEta ? null : (etaSec ?? this.etaSec),
        envTags: envTags ?? this.envTags,
        turns: turns ?? this.turns,
        headingDeg: headingDeg ?? this.headingDeg,
        cornering: clearCornering ? null : (cornering ?? this.cornering),
        capabilities: capabilities ?? this.capabilities,
        fishingPresence: fishingPresence ?? this.fishingPresence,
      );
}

/// 0~360 으로 맞춘 진행 방향. 숫자가 아니거나 NaN·무한대면 null
double? _heading(Object? v) {
  if (v is! num || !v.isFinite) return null;
  final d = v.toDouble() % 360;
  return d < 0 ? d + 360 : d;
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
  final double? affinityScore;
  final String? affinityPhase;
  final bool photoQuestCompleted;
  final bool regionCollectionKnown;
  final List<String> uncollectedRegions;

  /// Composed by the single phone writer, never published as a separate patch.
  final Map<String, dynamic> vehicleFeatures;

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
    this.affinityScore,
    this.affinityPhase,
    this.photoQuestCompleted = false,
    this.regionCollectionKnown = false,
    this.uncollectedRegions = const [],
    this.vehicleFeatures = const {},
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
        if (affinityScore != null) ...{
          'contractVersion': 2,
          'affinity': {
            'score': affinityScore,
            'target': 100,
            'phase': affinityPhase,
            'photoCompleted': photoQuestCompleted
          },
        },
        'regionCollectionKnown': regionCollectionKnown,
        if (regionCollectionKnown)
          'uncollectedRegions': List<String>.of(uncollectedRegions),
        for (final key in const [
          'contractVersion',
          'gameRevision',
          'companion',
          'transferResult',
          'fishing',
          'collectionSummary',
          'baseSummary',
          'travelRequest'
        ])
          if (vehicleFeatures.containsKey(key)) key: vehicleFeatures[key],
      };

  GameState copyWith({
    int? ts,
    EggTier? eggTier,
    Stage? stage,
    double? progress,
    String? speciesId,
    Attribute? attribute,
    int? tier,
    int? careCount,
    int? lookOutCount,
    double? hatchAtM,
    int? hatchAtSec,
    Map<String, dynamic>? vehicleFeatures,
    double? affinityScore,
    String? affinityPhase,
    bool? photoQuestCompleted,
    bool? regionCollectionKnown,
    List<String>? uncollectedRegions,
  }) =>
      GameState(
        ts: ts ?? this.ts,
        eggTier: eggTier ?? this.eggTier,
        stage: stage ?? this.stage,
        progress: progress ?? this.progress,
        speciesId: speciesId ?? this.speciesId,
        attribute: attribute ?? this.attribute,
        tier: tier ?? this.tier,
        careCount: careCount ?? this.careCount,
        lookOutCount: lookOutCount ?? this.lookOutCount,
        hatchAtM: hatchAtM ?? this.hatchAtM,
        hatchAtSec: hatchAtSec ?? this.hatchAtSec,
        affinityScore: affinityScore ?? this.affinityScore,
        affinityPhase: affinityPhase ?? this.affinityPhase,
        photoQuestCompleted: photoQuestCompleted ?? this.photoQuestCompleted,
        regionCollectionKnown:
            regionCollectionKnown ?? this.regionCollectionKnown,
        uncollectedRegions: uncollectedRegions ?? this.uncollectedRegions,
        vehicleFeatures: vehicleFeatures ?? this.vehicleFeatures,
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
  final String? sourceEggId;
  final String speciesId;
  final DateTime obtainedAt;
  final List<String> envTags; // 그날의 날씨·환경
  final String? regionTag; // coast / mountain / city — 좌표가 아니라 태그
  final int tier;

  const DexEntry({
    this.sourceEggId,
    required this.speciesId,
    required this.obtainedAt,
    required this.envTags,
    required this.regionTag,
    required this.tier,
  });

  Map<String, dynamic> toJson() => {
        'speciesId': speciesId,
        'obtainedAt': obtainedAt.toIso8601String(),
        if (sourceEggId != null) 'sourceEggId': sourceEggId,
        'envTags': envTags,
        'regionTag': regionTag,
        'tier': tier,
      };

  factory DexEntry.fromJson(Map<String, dynamic> j) => DexEntry(
        sourceEggId: j['sourceEggId'] as String?,
        speciesId: j['speciesId'] as String,
        obtainedAt: DateTime.parse(j['obtainedAt'] as String),
        envTags: (j['envTags'] as List).cast<String>(),
        regionTag: j['regionTag'] as String?,
        tier: (j['tier'] as num).toInt(),
      );
}
