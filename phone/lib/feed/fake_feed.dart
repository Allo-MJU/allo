import 'dart:async';
import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';

import 'vehicle_feed.dart';

/// 시나리오 안에서 시간에 따라 바뀌는 구간. 창밖 장면 확인용 (이슈 #45).
class FakeStage {
  final List<String> tags;
  final int wiperLevel;
  final bool headlightOn;

  const FakeStage(this.tags, {this.wiperLevel = 0, this.headlightOn = false});
}

/// 가짜 경로의 회전 하나. [atM] 은 출발점에서 잰 거리(m)이고, 경로는 [FakeScenario.routeLoopM] 마다 되풀이된다.
class FakeTurn {
  final String type;
  final double atM;

  const FakeTurn(this.type, this.atM);
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

  /// 비어 있지 않으면 내비 안내처럼 다음 회전 3개를 `turns` 로 보낸다.
  /// 거리는 timeScale 을 곱하지 않은 실제 시간 기준(속도 × 경과 초)이라 창밖에서 보이는 거리와 맞는다.
  final List<FakeTurn> route;
  final double routeLoopM;

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
    this.route = const [],
    this.routeLoopM = 0,
  });

  static const _turnDeg = {'right': 90.0, 'left': -90.0, 'uturn': 180.0};
  static const _turnKph = {'right': 20.0, 'left': 20.0, 'uturn': 9.0};

  /// 실제 차처럼 교차로 앞에서 서서히(1.8m/s²) 줄이고, 지난 뒤 서서히(2m/s²) 올린 속도(km/h)
  double speedAt(double travelledM) {
    if (route.isEmpty || routeLoopM <= 0) return speedKph;
    var v = speedKph / 3.6;
    final lap = (travelledM / routeLoopM).floor();
    for (var l = lap - 1; l <= lap + 1; l++) {
      for (final t in route) {
        final vt = _turnKph[t.type];
        if (vt == null) continue;
        final at = l * routeLoopM + t.atM;
        final d = at - travelledM;
        final a = d >= 0 ? 1.8 : 2.0;
        final cap = math.sqrt(math.pow(vt / 3.6, 2) + 2 * a * d.abs());
        if (cap < v) v = cap;
      }
    }
    return v * 3.6;
  }

  /// [travelledM] 를 달렸을 때의 진행 방향. 지난 회전 각도를 더하고, 그 위에 완만하게 굽는 길(±12도, 700m 주기)을 얹는다.
  /// 경로가 없으면 null (내비 위치를 모르는 것과 같다)
  double? headingAt(double travelledM) {
    if (route.isEmpty || routeLoopM <= 0) return null;
    final lap = (travelledM / routeLoopM).floor();
    final perLap = route.fold<double>(0, (a, t) => a + (_turnDeg[t.type] ?? 0));
    var h = lap * perLap;
    final inLap = travelledM - lap * routeLoopM;
    for (final t in route) {
      if (t.atM <= inLap) h += _turnDeg[t.type] ?? 0;
    }
    h += 12 * math.sin(2 * math.pi * travelledM / 700);
    final d = h % 360;
    return d < 0 ? d + 360 : d;
  }

  /// [travelledM] 를 달렸을 때 앞에 남은 회전들 (가까운 순 최대 3개)
  List<Turn> turnsAt(double travelledM) {
    if (route.isEmpty || routeLoopM <= 0) return const [];
    final out = <Turn>[];
    final lap = (travelledM / routeLoopM).floor();
    for (var l = lap; l <= lap + 1 && out.length < 3; l++) {
      for (final t in route) {
        final inM = l * routeLoopM + t.atM - travelledM;
        if (inM >= 0 && out.length < 3) out.add(Turn(t.type, inM.round()));
      }
    }
    return out;
  }

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

  /// 들판 → 바다 → 산 → 낮 도시 → 터널 → 밤 도시 → 폭우 고속도로 순으로 창밖을 15초씩 바꾼다.
  /// tags 는 첫 구간과 같게 둔다.
  static const sceneTour = FakeScenario(
    name: 'scene_tour',
    tags: [],
    speedKph: 70,
    stageEverySec: 15,
    route: [
      FakeTurn('right', 220),
      FakeTurn('left', 560),
      FakeTurn('uturn', 900),
      FakeTurn('keepRight', 1200),
      FakeTurn('left', 1500),
    ],
    routeLoopM: 1800,
    stages: [
      FakeStage([]),
      FakeStage(['coast']),
      FakeStage(['mountain']),
      FakeStage(['city']),
      FakeStage(['tunnel'], headlightOn: true),
      FakeStage(['city', 'night'], headlightOn: true),
      FakeStage(['highway', 'rain'], wiperLevel: 3),
    ],
  );

  static FakeScenario byName(String n) => const [
        rainyHighway,
        tunnelRough,
        clear,
        rough,
        sceneTour
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
  double _road = 0; // 창밖 기준으로 달린 거리 (timeScale 을 곱하지 않는다)
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
    _road = 0;
    _elapsed = 0;
    _harshBrake = 0;
    _harshSteer = 0;
    _latest = null;
    _ended = false;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed++;
      // 창밖 거리(실제 시간 기준)를 속도대로 쌓는다. 교차로에서는 감속한다
      final kph = scenario.speedAt(_road);
      _road += kph / 3.6;
      _dist += kph / 3.6 * timeScale;
      if (scenario.harshEverySec > 0 &&
          _elapsed % scenario.harshEverySec.round() == 0) {
        _harshBrake++;
        if (_elapsed % (scenario.harshEverySec.round() * 2) == 0) _harshSteer++;
      }
      final stage = scenario.stageAt(_elapsed);
      final snapshot = VehicleState(
        ts: startedAt + (_elapsed * timeScale * 1000).round(),
        gear: 'D',
        speedKph: kph,
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
        turns: scenario.turnsAt(_road),
        headingDeg: scenario.headingAt(_road),
        capabilities: [
          'wiper',
          'light',
          'seat',
          'odometer',
          'speed',
          'gear',
          if (scenario.etaSec != null) 'eta',
          if (scenario.route.isNotEmpty) 'turns',
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
