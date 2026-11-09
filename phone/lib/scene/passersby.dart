import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';

import 'window_scene.dart';

/// 차 안에서 보이는 유리창. 아이는 뒷좌석 가운데에 앉아 앞을 본다.
enum Pane { left, right, windshield }

/// 옆창 풍경이 흐르는 방향. 차가 앞으로 가므로 화면 가운데(앞)에서 바깥(뒤)으로 흐른다.
/// -1 은 왼쪽으로, +1 은 오른쪽으로 흐른다. 앞유리는 다가오므로 0.
int paneFlow(Pane pane) => switch (pane) {
      Pane.left => -1,
      Pane.right => 1,
      Pane.windshield => 0,
    };

/// 창밖을 지나가는 것들. [friend] 는 아이가 모은 ALLO 캐릭터다.
enum PasserbyKind {
  gull,
  flock,
  butterfly,
  firefly,
  cyclist,
  bus,
  oncomingCar,
  umbrella,
  friend,
}

/// 하늘을 나는 것. 땅에 붙은 것과 달리 옆창에서 위쪽에 그린다.
bool isAirborne(PasserbyKind k) =>
    k == PasserbyKind.gull ||
    k == PasserbyKind.flock ||
    k == PasserbyKind.butterfly ||
    k == PasserbyKind.firefly;

class Passerby {
  const Passerby({
    required this.kind,
    required this.pane,
    required this.bornAt,
    required this.life,
    required this.lane,
    required this.scale,
    required this.seed,
    this.friend,
    this.waves = false,
  });

  final PasserbyKind kind;
  final Pane pane;

  /// 나타나는 시각(초). 무리는 조금씩 늦게 나타나도록 미래 시각일 수 있다.
  final double bornAt;

  /// 화면을 지나가는 데 걸리는 시간(초)
  final double life;

  /// 0~1. 하늘을 나는 것은 높이, 땅에 있는 것은 앞뒤 깊이로 쓴다.
  final double lane;
  final double scale;
  final int seed;
  final Species? friend;

  /// 캐릭터가 손을 흔드는지
  final bool waves;

  bool visible(double t) => t >= bornAt && t < bornAt + life;
  bool done(double t) => t >= bornAt + life;
  double progress(double t) => ((t - bornAt) / life).clamp(0.0, 1.0);
}

/// 장면에 나올 수 있는 친구(모은 캐릭터)를 고른다. **속성 규칙은 여기만 바꾼다.**
///
/// 지금은 모은 캐릭터 전부가 후보다. 터널 안에서는 창밖이 벽이라 나오지 않는다.
/// 속성별 등장(예: water 는 바다·비, dark 는 밤)은 C 와 규칙을 정한 뒤 이 함수에 넣는다.
List<Species> eligibleFriends(WindowScene scene, List<Species> friends) {
  if (scene.kind == SceneKind.tunnel) return const [];
  return friends;
}

/// 장면별로 창밖을 지나갈 수 있는 생물·탈것.
List<PasserbyKind> creaturesFor(WindowScene s) {
  if (s.kind == SceneKind.tunnel) return const [PasserbyKind.oncomingCar];
  final rain = s.rainLevel > 0;
  final out = <PasserbyKind>{PasserbyKind.oncomingCar};
  if (s.night) {
    if (!rain && s.kind != SceneKind.city && !s.highway) {
      out.add(PasserbyKind.firefly);
    }
    return out.toList();
  }
  switch (s.kind) {
    case SceneKind.coast:
      out.add(PasserbyKind.gull);
    case SceneKind.mountain:
      out.add(PasserbyKind.flock);
      if (!rain) out.add(PasserbyKind.butterfly);
    case SceneKind.city:
      out.add(PasserbyKind.bus);
      out.add(rain ? PasserbyKind.umbrella : PasserbyKind.cyclist);
    case SceneKind.road:
    case SceneKind.tunnel:
      out.add(PasserbyKind.flock);
      out.add(rain ? PasserbyKind.umbrella : PasserbyKind.butterfly);
      if (!rain) out.add(PasserbyKind.cyclist);
  }
  if (s.highway) {
    // 고속도로에는 사람·자전거가 없다
    out
      ..remove(PasserbyKind.cyclist)
      ..remove(PasserbyKind.umbrella)
      ..remove(PasserbyKind.butterfly);
  }
  return out.toList();
}

/// 와이퍼 한 주기(초)와 그중 실제로 닦는 비율. 1 단은 간헐 와이퍼라 쉬는 시간이 길다.
(double period, double sweep) wiperCycle(int level) => switch (level) {
      <= 0 => (0, 0),
      1 => (3.2, 0.36),
      2 => (1.5, 0.8),
      _ => (0.9, 1.0),
    };

/// 창밖을 지나가는 것들을 무작위 간격으로 만든다.
///
/// 실제 앱은 매번 다르게 움직이고, 테스트는 [random] 에 시드를 고정해 같은 결과를 본다.
class PasserbySpawner {
  PasserbySpawner({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;
  final List<Passerby> active = [];

  double _nextCreature = 1.5;
  double _nextFriend = 8;
  int _seed = 0;

  static const maxActive = 7;

  void update(double t, WindowScene scene, List<Species> friends) {
    active.removeWhere((p) => p.done(t));
    if (t >= _nextCreature) {
      final kinds = creaturesFor(scene);
      if (kinds.isNotEmpty && active.length < maxActive) {
        final kind = kinds[_rng.nextInt(kinds.length)];
        final pane = _paneFor(kind);
        // 가끔은 두세 마리가 몰려서 나온다
        final n = kind == PasserbyKind.flock ||
                kind == PasserbyKind.oncomingCar ||
                kind == PasserbyKind.bus
            ? 1
            : _rng.nextDouble() < 0.3
                ? 2 + _rng.nextInt(2)
                : 1;
        for (var i = 0; i < n && active.length < maxActive; i++) {
          active
              .add(_make(kind, pane, t + i * (0.3 + _rng.nextDouble() * 0.7)));
        }
      }
      _nextCreature = t + 2.5 + _rng.nextDouble() * 5.5;
    }
    if (t >= _nextFriend) {
      final pool = eligibleFriends(scene, friends);
      if (active.length < maxActive &&
          pool.isNotEmpty &&
          !active.any((p) => p.kind == PasserbyKind.friend)) {
        active.add(Passerby(
          kind: PasserbyKind.friend,
          pane: _rng.nextBool() ? Pane.left : Pane.right,
          bornAt: t,
          life: 5 + _rng.nextDouble() * 4,
          lane: _rng.nextDouble(),
          scale: 0.9 + _rng.nextDouble() * 0.25,
          seed: _seed++,
          friend: pool[_rng.nextInt(pool.length)],
          waves: _rng.nextDouble() < 0.6,
        ));
      }
      // 평균 30초에 한 번
      _nextFriend = t + 18 + _rng.nextDouble() * 24;
    }
  }

  /// 장면이 바뀌면 그 장면에 어울리지 않는 것은 바로 치운다.
  void onSceneChanged(WindowScene scene, List<Species> friends) {
    final kinds = creaturesFor(scene).toSet();
    final pool = eligibleFriends(scene, friends).toSet();
    active.removeWhere((p) => p.kind == PasserbyKind.friend
        ? !pool.contains(p.friend)
        : !kinds.contains(p.kind));
  }

  Pane _paneFor(PasserbyKind k) {
    switch (k) {
      case PasserbyKind.oncomingCar:
        return Pane.windshield;
      case PasserbyKind.flock:
      case PasserbyKind.gull:
        final r = _rng.nextDouble();
        return r < 0.34
            ? Pane.windshield
            : r < 0.67
                ? Pane.left
                : Pane.right;
      default:
        return _rng.nextBool() ? Pane.left : Pane.right;
    }
  }

  Passerby _make(PasserbyKind kind, Pane pane, double bornAt) {
    final (lo, hi) = switch (kind) {
      PasserbyKind.gull => (4.0, 6.5),
      PasserbyKind.flock => (5.0, 8.0),
      PasserbyKind.butterfly => (3.0, 5.0),
      PasserbyKind.firefly => (4.0, 7.0),
      PasserbyKind.cyclist => (2.5, 4.0),
      PasserbyKind.bus => (2.0, 3.0),
      PasserbyKind.oncomingCar => (2.2, 3.6),
      PasserbyKind.umbrella => (2.5, 3.5),
      PasserbyKind.friend => (5.0, 9.0),
    };
    return Passerby(
      kind: kind,
      pane: pane,
      bornAt: bornAt,
      life: lo + _rng.nextDouble() * (hi - lo),
      lane: _rng.nextDouble(),
      scale: 0.75 + _rng.nextDouble() * 0.5,
      seed: _seed++,
    );
  }
}
