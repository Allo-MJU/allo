import 'models.dart';

/// 부화 타이밍. docs/roadmap.md C-3.
///
/// case A: etaSec 있음 → 세션 시작 시점 ETA 의 50% 경과 시 부화.
/// case B: etaSec 없음 → eggTier 목표 거리의 50% 누적 시 부화. 이전 주행에서 이어진다.
class HatchTimer {
  final EggTier eggTier;

  /// 이전 주행에서 넘어온 누적 거리(m). 거리 폴백에서만 쓴다.
  final double carriedM;

  /// 세션 시작 시 ETA(초). 주행 중 ETA 가 바뀌어도 고정한다(중간 지점이 흔들리지 않게).
  int? _etaAtStartSec;
  int? _startTs;
  double _sessionDistanceM = 0;

  HatchTimer({required this.eggTier, this.carriedM = 0});

  /// 거리 기준 부화 지점(m). ETA 모드에서는 null.
  double? get hatchAtM => _etaAtStartSec == null ? eggTier.targetM / 2 : null;

  /// ETA 기준 부화 지점(초, 세션 시작부터). 거리 모드에서는 null.
  int? get hatchAtSec => _etaAtStartSec == null ? null : _etaAtStartSec! ~/ 2;

  bool get usesEta => _etaAtStartSec != null;

  /// 지금까지 누적 거리 (이어하기 포함).
  double get totalDistanceM => carriedM + _sessionDistanceM;

  /// 매 틱 호출. 반환값은 0..1 진행도.
  double update(VehicleState v) {
    _startTs ??= v.ts;
    _sessionDistanceM = v.distanceM;

    // ETA 가 세션 도중에 처음 들어오면(내비를 늦게 켬) 그 시점부터 ETA 모드로 전환한다.
    // 단 이미 거리 진행이 더 앞서 있으면 거리 모드를 유지한다 (진행도가 뒤로 가지 않게).
    if (_etaAtStartSec == null && v.etaSec != null && v.etaSec! > 0) {
      final distProgress = totalDistanceM / (eggTier.targetM / 2);
      if (distProgress < 0.5) {
        _etaAtStartSec = v.etaSec;
        _startTs = v.ts;
      }
    }

    final eta = _etaAtStartSec;
    final double p;
    if (eta != null) {
      final elapsedSec = (v.ts - _startTs!) / 1000.0;
      p = elapsedSec / (eta / 2);
    } else {
      p = totalDistanceM / (eggTier.targetM / 2);
    }
    return p.clamp(0.0, 1.0);
  }

  bool shouldHatch(double progress) => progress >= 1.0;

  /// 세션 종료 시 다음 주행으로 넘길 거리. ETA 모드로 부화했으면 0.
  double carryOver({required bool hatched}) => hatched ? 0 : totalDistanceM;
}
