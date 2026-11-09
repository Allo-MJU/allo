import 'dart:async';

import 'package:allo_core/allo_core.dart';

import 'vehicle_feed.dart';

/// 시나리오 안에서 시간에 따라 바뀌는 구간. 창밖 장면 확인용 (이슈 #45).
class FakeStage {
  final List<String> tags;
  final int wiperLevel;
  final bool headlightOn;

  const FakeStage(this.tags, {this.wiperLevel = 0, this.headlightOn = false});
}

/// 가짜 신호 주입기. Day 1 부터 이걸로 개발한다.
class FakeScenario {
  final String name;
  final List<String> tags;
  final int wiperLevel;
  final bool headlightOn;
  final int? etaSec;
  final double harshEverySec; // 0 이면 급제동 없음
  final double speedKph;

  /// 비어 있지 않으면 [stageEverySec] 초마다 다음 구간으로 넘어가며 tags·wiperLevel·headlightOn 을 바꾼다.
  final List<FakeStage> stages;
  final int stageEverySec;

  const FakeScenario({
    required this.name,
    required this.tags,
    this.wiperLevel = 0,
    this.headlightOn = false,
    this.etaSec,
    this.harshEverySec = 0,
    this.speedKph = 80,
    this.stages = const [],
    this.stageEverySec = 8,
  });

  FakeStage stageAt(int elapsedSec) => stages.isEmpty
      ? FakeStage(tags, wiperLevel: wiperLevel, headlightOn: headlightOn)
      : stages[(elapsedSec ~/ stageEverySec) % stages.length];

  static const rainyHighway = FakeScenario(
      name: 'rainy_highway',
      tags: ['rain', 'highway'],
      wiperLevel: 2,
      speedKph: 90);
  static const tunnelRough = FakeScenario(
      name: 'tunnel_rough',
      tags: ['tunnel'],
      headlightOn: true,
      harshEverySec: 8,
      speedKph: 60);
  static const clear =
      FakeScenario(name: 'clear', tags: [], speedKph: 50, etaSec: 600);
  static const rough =
      FakeScenario(name: 'rough', tags: [], harshEverySec: 5, speedKph: 50);

  /// 바다 → 비 오는 바다 → 산 → 터널 → 밤 도시 → 폭우 고속도로 순으로 창밖을 바꾼다.
  /// tags 는 첫 구간과 같게 둔다.
  static const sceneTour = FakeScenario(
    name: 'scene_tour',
    tags: ['coast'],
    speedKph: 70,
    stages: [
      FakeStage(['coast']),
      FakeStage(['coast', 'rain'], wiperLevel: 2),
      FakeStage(['mountain']),
      FakeStage(['tunnel'], headlightOn: true),
      FakeStage(['city', 'night'], headlightOn: true),
      FakeStage(['highway', 'rain'], wiperLevel: 3),
    ],
  );

  /// 8초마다 비/풍경 변화, 5초마다 차량 급변으로 두 부착 반응을 체험한다.
  static const characterTour = FakeScenario(
    name: 'character_tour',
    tags: [],
    speedKph: 70,
    harshEverySec: 5,
    stages: [
      FakeStage([]),
      FakeStage(['rain'], wiperLevel: 2),
      FakeStage(['coast']),
      FakeStage(['mountain']),
    ],
  );

  static FakeScenario byName(String n) => const [
        rainyHighway,
        tunnelRough,
        clear,
        rough,
        sceneTour,
        characterTour
      ].firstWhere((s) => s.name == n, orElse: () => rainyHighway);
}

class FakeVehicleFeed implements VehicleFeed {
  FakeVehicleFeed({required this.scenario, this.timeScale = 20});

  final FakeScenario scenario;

  /// 1초 틱마다 timeScale 초만큼 달린 것으로 친다. 20이면 rainy_highway의 작은 알이 약 10초 만에 부화.
  final double timeScale;

  final _events = StreamController<Map<String, Object?>>.broadcast();
  Timer? _timer;
  VehicleState? _latest;
  bool _ended = false;
  double _dist = 0;
  int _harshBrake = 0;
  int _harshSteer = 0;
  int _elapsed = 0;

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {}

  @override
  Stream<VehicleState> watch() {
    final ctrl = StreamController<VehicleState>();
    _timer?.cancel();
    _dist = 0;
    _elapsed = 0;
    _harshBrake = 0;
    _harshSteer = 0;
    _latest = null;
    _ended = false;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed++;
      _dist += scenario.speedKph / 3.6 * timeScale;
      if (scenario.harshEverySec > 0 &&
          _elapsed % scenario.harshEverySec.round() == 0) {
        _harshBrake++;
        if (_elapsed % (scenario.harshEverySec.round() * 2) == 0) _harshSteer++;
      }
      final stage = scenario.stageAt(_elapsed);
      final snapshot = VehicleState(
        ts: startedAt + (_elapsed * timeScale * 1000).round(),
        gear: 'D',
        speedKph: scenario.speedKph,
        distanceM: _dist,
        harshBrake: _harshBrake,
        harshSteer: _harshSteer,
        wiperLevel: stage.wiperLevel,
        headlightOn: stage.headlightOn,
        seatRow2: true,
        etaSec: scenario.etaSec == null
            ? null
            : (scenario.etaSec! - (_elapsed * timeScale).round())
                .clamp(0, 1 << 30),
        envTags: stage.tags,
        capabilities: [
          'wiper',
          'light',
          'seat',
          'odometer',
          'speed',
          'gear',
          if (scenario.etaSec != null) 'eta'
        ],
      );
      _latest = snapshot;
      ctrl.add(snapshot);
    });
    _timer = timer;
    ctrl.onCancel = timer.cancel;
    return ctrl.stream;
  }

  /// 체험에서도 실제 차량과 같은 종료 이벤트를 보낸다.
  void endTrip() {
    if (_ended || _events.isClosed) return;
    _ended = true;
    _timer?.cancel();
    _latest = _latest?.copyWith(gear: 'P', speedKph: 0);
    _events.add({
      'ts': _latest?.ts ?? DateTime.now().millisecondsSinceEpoch,
      'type': 'sessionEnd',
      'by': 'car',
    });
  }

  @override
  Future<VehicleState?> readLatestVehicle() async => _latest;

  @override
  Future<void> publishGame(GameState state) async {}

  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {}

  @override
  Stream<Map<String, Object?>> events() => _events.stream;

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _events.close();
  }
}
