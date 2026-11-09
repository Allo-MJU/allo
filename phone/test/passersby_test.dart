import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/scene/passersby.dart';
import 'package:allo_phone/scene/window_scene.dart';
import 'package:allo_phone/widgets/cabin_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Species sp(String id, Attribute a) => Species(
      id: id,
      nameEn: id,
      nameKo: id,
      attribute: a,
      tier: 1,
      requiredTags: const [],
      maxHarsh: null,
      hint: '',
      sprite: '$id.png',
    );

/// [seconds] 동안 0.1초 간격으로 돌려 나온 것을 모두 모은다.
List<Passerby> run(PasserbySpawner s, WindowScene scene, List<Species> friends,
    {double seconds = 300}) {
  final seen = <Passerby>[];
  for (var t = 0.0; t < seconds; t += 0.1) {
    s.update(t, scene, friends);
    for (final p in s.active) {
      if (!seen.contains(p)) seen.add(p);
    }
  }
  return seen;
}

void main() {
  const coast = WindowScene(kind: SceneKind.coast, speedKph: 60);
  final mist = sp('sea_mist', Attribute.water);

  group('PasserbySpawner', () {
    test('친구는 모은 캐릭터 중에서만 나오고, 평균 수십 초에 한 번이다', () {
      final out = run(PasserbySpawner(random: math.Random(1)), coast, [mist]);
      final friends = out.where((p) => p.kind == PasserbyKind.friend).toList();
      expect(friends, isNotEmpty);
      expect(friends.every((p) => p.friend == mist), isTrue);
      expect(friends.every((p) => p.pane != Pane.windshield), isTrue);
      // 300초에 평균 30초 간격이면 대략 10번 안팎
      expect(friends.length, inInclusiveRange(4, 16));
    });

    test('모은 캐릭터가 없으면 친구는 나오지 않는다', () {
      final out = run(PasserbySpawner(random: math.Random(2)), coast, []);
      expect(out.where((p) => p.kind == PasserbyKind.friend), isEmpty);
      expect(out, isNotEmpty);
    });

    test('장면에 맞는 생물만 나온다', () {
      final out = run(PasserbySpawner(random: math.Random(3)), coast, []);
      final allowed = creaturesFor(coast).toSet();
      expect(out.every((p) => allowed.contains(p.kind)), isTrue);
      expect(out.any((p) => p.kind == PasserbyKind.gull), isTrue);
    });

    test('시드가 같으면 같게, 다르면 다르게 나온다', () {
      List<double> times(int seed) =>
          run(PasserbySpawner(random: math.Random(seed)), coast, [mist],
                  seconds: 60)
              .map((p) => p.bornAt)
              .toList();
      expect(times(5), times(5));
      expect(times(5), isNot(times(6)));
    });

    test('장면이 바뀌면 어울리지 않는 것을 치운다', () {
      final s = PasserbySpawner(random: math.Random(4));
      run(s, coast, [mist], seconds: 40);
      const tunnel = WindowScene(kind: SceneKind.tunnel, speedKph: 60);
      s.onSceneChanged(tunnel, [mist]);
      final allowed = creaturesFor(tunnel).toSet();
      expect(s.active.every((p) => allowed.contains(p.kind)), isTrue);
    });
  });

  group('장면 규칙', () {
    test('터널에서는 친구가 나오지 않는다 (속성 규칙은 eligibleFriends 한 곳)', () {
      const tunnel = WindowScene(kind: SceneKind.tunnel);
      expect(eligibleFriends(tunnel, [mist]), isEmpty);
      expect(eligibleFriends(coast, [mist]), [mist]);
    });

    test('고속도로에는 사람·자전거가 없고, 밤에는 반딧불이가 나온다', () {
      const hw = WindowScene(kind: SceneKind.road, highway: true);
      expect(creaturesFor(hw), isNot(contains(PasserbyKind.cyclist)));
      expect(creaturesFor(hw), isNot(contains(PasserbyKind.umbrella)));
      const night = WindowScene(kind: SceneKind.mountain, night: true);
      expect(creaturesFor(night), contains(PasserbyKind.firefly));
    });

    test('와이퍼는 단이 높을수록 빨리 닦는다', () {
      final (p1, _) = wiperCycle(1);
      final (p2, _) = wiperCycle(2);
      final (p3, _) = wiperCycle(3);
      expect(p1, greaterThan(p2));
      expect(p2, greaterThan(p3));
      expect(wiperCycle(0).$1, 0);
    });

    test('옆창 풍경은 가운데(앞)에서 바깥(뒤)으로 흐른다', () {
      expect(paneFlow(Pane.left), -1);
      expect(paneFlow(Pane.right), 1);
      expect(paneFlow(Pane.windshield), 0);
    });
  });

  test('rectToQuad 는 직사각형 네 꼭짓점을 사다리꼴 꼭짓점으로 옮긴다', () {
    const src = Size(300, 240);
    final quad = CabinLayout(const Size(360, 300)).left;
    final m = rectToQuad(src, quad);
    Offset map(double x, double y) {
      double row(int r) =>
          m.entry(r, 0) * x + m.entry(r, 1) * y + m.entry(r, 3);
      return Offset(row(0) / row(3), row(1) / row(3));
    }

    final corners = [
      map(0, 0),
      map(src.width, 0),
      map(src.width, src.height),
      map(0, src.height),
    ];
    for (var i = 0; i < 4; i++) {
      expect(corners[i].dx, closeTo(quad[i].dx, 1e-6));
      expect(corners[i].dy, closeTo(quad[i].dy, 1e-6));
    }
  });
}
