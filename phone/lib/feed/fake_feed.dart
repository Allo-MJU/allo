import 'dart:async';

import 'package:allo_core/allo_core.dart';

import 'vehicle_feed.dart';

/// 가짜 신호 주입기. Day 1 부터 이걸로 개발한다.
class FakeScenario {
  final String name;
  final List<String> tags;
  final int wiperLevel;
  final bool headlightOn;
  final int? etaSec;
  final double harshEverySec; // 0 이면 급제동 없음
  final double speedKph;

  const FakeScenario({
    required this.name,
    required this.tags,
    this.wiperLevel = 0,
    this.headlightOn = false,
    this.etaSec,
    this.harshEverySec = 0,
    this.speedKph = 80,
  });

  static const rainyHighway = FakeScenario(name: 'rainy_highway', tags: ['rain', 'highway'], wiperLevel: 2, speedKph: 90);
  static const tunnelRough = FakeScenario(name: 'tunnel_rough', tags: ['tunnel'], headlightOn: true, harshEverySec: 8, speedKph: 60);
  static const clear = FakeScenario(name: 'clear', tags: [], speedKph: 50, etaSec: 600);
  static const rough = FakeScenario(name: 'rough', tags: [], harshEverySec: 5, speedKph: 50);

  static FakeScenario byName(String n) => const [rainyHighway, tunnelRough, clear, rough].firstWhere((s) => s.name == n, orElse: () => rainyHighway);
}

class FakeVehicleFeed implements VehicleFeed {
  FakeVehicleFeed({required this.scenario, this.timeScale = 20});

  final FakeScenario scenario;

  /// 1초 틱마다 timeScale 초만큼 달린 것으로 친다. 20 이면 10km 알이 약 25초 만에 부화.
  final double timeScale;

  final _events = StreamController<Map<String, Object?>>.broadcast();
  Timer? _timer;
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed++;
      _dist += scenario.speedKph / 3.6 * timeScale;
      if (scenario.harshEverySec > 0 && _elapsed % scenario.harshEverySec.round() == 0) {
        _harshBrake++;
        if (_elapsed % (scenario.harshEverySec.round() * 2) == 0) _harshSteer++;
      }
      ctrl.add(VehicleState(
        ts: DateTime.now().millisecondsSinceEpoch,
        gear: 'D',
        speedKph: scenario.speedKph,
        distanceM: _dist,
        harshBrake: _harshBrake,
        harshSteer: _harshSteer,
        wiperLevel: scenario.wiperLevel,
        headlightOn: scenario.headlightOn,
        seatRow2: true,
        etaSec: scenario.etaSec == null ? null : (scenario.etaSec! - (_elapsed * timeScale).round()).clamp(0, 1 << 30),
        envTags: scenario.tags,
        capabilities: const ['wiper', 'light', 'seat', 'odometer', 'speed', 'gear'],
      ));
    });
    ctrl.onCancel = () => _timer?.cancel();
    return ctrl.stream;
  }

  @override
  Future<void> publishGame(GameState state) async {}

  @override
  Future<void> emitEvent(String type, {Map<String, Object?> payload = const {}}) async {}

  @override
  Stream<Map<String, Object?>> events() => _events.stream;

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _events.close();
  }
}
