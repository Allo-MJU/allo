import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/scene/window_scene.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VehicleState v(List<String> tags,
        {String gear = 'D', double speed = 60, int wiper = 0, int ts = 1}) =>
    VehicleState(
      ts: ts,
      gear: gear,
      speedKph: speed,
      distanceM: 0,
      harshBrake: 0,
      harshSteer: 0,
      wiperLevel: wiper,
      headlightOn: false,
      seatRow2: true,
      etaSec: null,
      envTags: tags,
      capabilities: const ['wiper', 'light'],
    );

void main() {
  group('WindowScene.fromVehicle', () {
    test('지역 태그로 장면을 고르고, 없으면 기본 도로', () {
      expect(WindowScene.fromVehicle(v(['coast'])).kind, SceneKind.coast);
      expect(WindowScene.fromVehicle(v(['mountain'])).kind, SceneKind.mountain);
      expect(WindowScene.fromVehicle(v(['city'])).kind, SceneKind.city);
      expect(WindowScene.fromVehicle(v([])).kind, SceneKind.road);
      expect(WindowScene.fromVehicle(v(['highway'])).kind, SceneKind.road);
      expect(WindowScene.fromVehicle(null), WindowScene.initial);
    });

    test('지역 태그가 여러 개면 coast → mountain → city 순', () {
      expect(WindowScene.fromVehicle(v(['city', 'mountain'])).kind,
          SceneKind.mountain);
      expect(
          WindowScene.fromVehicle(v(['city', 'coast'])).kind, SceneKind.coast);
    });

    test('터널은 지역보다 우선하고 비·밤을 끈다', () {
      final s = WindowScene.fromVehicle(
          v(['coast', 'tunnel', 'rain', 'night'], wiper: 2));
      expect(s.kind, SceneKind.tunnel);
      expect(s.rainLevel, 0);
      expect(s.night, isFalse);
    });

    test('비 세기는 wiperLevel 1~3, rain 태그 없으면 0', () {
      expect(WindowScene.fromVehicle(v(['rain'], wiper: 2)).rainLevel, 2);
      expect(WindowScene.fromVehicle(v(['rain'], wiper: 0)).rainLevel, 1);
      expect(WindowScene.fromVehicle(v(['rain'], wiper: 9)).rainLevel, 3);
      expect(WindowScene.fromVehicle(v([], wiper: 3)).rainLevel, 0);
    });

    test('밤·고속도로는 그대로 반영', () {
      final s = WindowScene.fromVehicle(v(['city', 'night', 'highway']));
      expect(s.night, isTrue);
      expect(s.highway, isTrue);
    });

    test('P 이거나 속도 0 이면 멈춘다', () {
      expect(
          WindowScene.fromVehicle(v([], gear: 'P', speed: 30)).moving, isFalse);
      expect(WindowScene.fromVehicle(v([], speed: 0)).moving, isFalse);
      expect(WindowScene.fromVehicle(v([], speed: 80)).speedKph, 80);
    });
  });

  group('SceneStabilizer', () {
    WindowScene s(SceneKind k, {bool night = false}) =>
        WindowScene(kind: k, night: night);

    test('첫 장면은 바로 보인다', () {
      final st = SceneStabilizer(holdMs: 4000);
      expect(st.update(s(SceneKind.coast), 0).kind, SceneKind.coast);
    });

    test('지역 전환은 holdMs 동안 이어질 때만', () {
      final st = SceneStabilizer(holdMs: 4000);
      st.update(s(SceneKind.road), 0);
      expect(st.update(s(SceneKind.coast), 1000).kind, SceneKind.road);
      expect(st.update(s(SceneKind.coast), 4000).kind, SceneKind.road);
      expect(st.update(s(SceneKind.coast), 5000).kind, SceneKind.coast);
    });

    test('경계에서 왔다 갔다 하면 장면을 바꾸지 않는다', () {
      final st = SceneStabilizer(holdMs: 4000);
      st.update(s(SceneKind.road), 0);
      for (var t = 1000; t <= 10000; t += 1000) {
        final k = (t ~/ 1000).isOdd ? SceneKind.coast : SceneKind.road;
        expect(st.update(s(k), t).kind, SceneKind.road, reason: '$t ms');
      }
    });

    test('다른 지역으로 후보가 바뀌면 유지 시간을 다시 센다', () {
      final st = SceneStabilizer(holdMs: 4000);
      st.update(s(SceneKind.road), 0);
      st.update(s(SceneKind.coast), 1000);
      st.update(s(SceneKind.mountain), 3000);
      expect(st.update(s(SceneKind.mountain), 6000).kind, SceneKind.road);
      expect(st.update(s(SceneKind.mountain), 7000).kind, SceneKind.mountain);
    });

    test('터널 진입·이탈은 바로 바꾼다', () {
      final st = SceneStabilizer(holdMs: 4000);
      st.update(s(SceneKind.mountain), 0);
      expect(st.update(s(SceneKind.tunnel), 100).kind, SceneKind.tunnel);
      expect(st.update(s(SceneKind.city), 200).kind, SceneKind.city);
    });

    test('장면을 붙잡고 있어도 밤 같은 효과는 바로 반영한다', () {
      final st = SceneStabilizer(holdMs: 4000);
      st.update(s(SceneKind.road), 0);
      final out = st.update(s(SceneKind.coast, night: true), 1000);
      expect(out.kind, SceneKind.road);
      expect(out.night, isTrue);
    });
  });

  group('FakeScenario.sceneTour', () {
    test('구간마다 태그가 바뀌고 처음으로 돌아온다', () {
      const t = FakeScenario.sceneTour;
      expect(t.stageAt(0).tags, isEmpty); // 들판
      expect(t.stageAt(t.stageEverySec).tags, ['coast']);
      expect(t.stageAt(t.stageEverySec * 4).headlightOn, isTrue); // 터널
      expect(t.stageAt(t.stageEverySec * t.stages.length).tags, isEmpty);
      expect(FakeScenario.byName('scene_tour'), same(t));
    });

    test('구간이 없는 기존 시나리오는 원래 값을 쓴다', () {
      final s = FakeScenario.rainyHighway.stageAt(123);
      expect(s.tags, ['rain', 'highway']);
      expect(s.wiperLevel, 2);
    });
  });

  group('WindowView', () {
    Widget host(VehicleState? state, {bool motion = false, Key? key}) =>
        MaterialApp(
          home: SceneMotion(
            enabled: motion,
            child: Scaffold(
              body: WindowView(
                  key: key,
                  vehicle: state,
                  child: const Icon(Icons.egg, size: 80)),
            ),
          ),
        );

    testWidgets('모든 장면을 그리고 정지 상태면 애니메이션이 끝난다', (tester) async {
      for (final tags in [
        ['coast', 'rain'],
        ['mountain', 'night'],
        ['city', 'highway'],
        ['tunnel'],
        <String>[],
      ]) {
        // 장면마다 새 상태로 그려 유지 시간에 막히지 않게 한다.
        await tester
            .pumpWidget(host(v(tags, wiper: 2), key: ValueKey(tags.join(','))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.byIcon(Icons.egg), findsOneWidget);
    });

    testWidgets('장면을 접근성 라벨로 알려 준다', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(v(['coast', 'rain', 'night'], wiper: 1)));
      expect(find.bySemanticsLabel(RegExp('창밖: 바다, 비, 밤')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('움직임을 켜면 달리는 동안 프레임이 이어지고, 정차하면 멈춘다', (tester) async {
      await tester.pumpWidget(host(v(['mountain'], speed: 80), motion: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
          host(v(['mountain'], gear: 'P', speed: 0, ts: 2), motion: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
