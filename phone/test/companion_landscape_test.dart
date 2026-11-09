import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/companion_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/widgets/character_stage.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

GameController makeController() => GameController(
    feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore())
  ..game = const GameState(
      ts: 1, eggTier: EggTier.small, stage: Stage.hatched, progress: 1)
  ..vehicle = VehicleState.fromJson({'ts': 1, 'gear': 'D', 'speedKph': 40});

void main() {
  for (final size in [
    const Size(640, 360),
    const Size(844, 390),
    const Size(1024, 600)
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('가로 $size 글자 $scale: 장면과 주 조작이 안전영역 안에 있다', (t) async {
        await t.binding.setSurfaceSize(size);
        final c = makeController();
        await t.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16)),
                child: CompanionScreen(controller: c))));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final scene =
            t.getRect(find.byKey(const ValueKey('companion-game-scene')));
        final panel =
            t.getRect(find.byKey(const ValueKey('companion-controls')));
        expect(scene.right, lessThanOrEqualTo(panel.left));
        expect(scene.left, greaterThanOrEqualTo(24));
        expect(panel.right, lessThanOrEqualTo(size.width - 24));
        for (final label in ['먹이', '놀아주기', '봤어!']) {
          final button = find.widgetWithText(FilledButton, label);
          expect(button.hitTestable(), findsOneWidget);
          final rect = t.getRect(button);
          expect(rect.height, greaterThanOrEqualTo(label == '봤어!' ? 72 : 56));
          expect(rect.bottom, lessThanOrEqualTo(size.height - 16));
          await t.tap(button);
          await t.pump();
        }
        expect(c.feedCount, 1);
        expect(c.playCount, 1);
        expect(c.lookOutCount, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.binding.setSurfaceSize(null);
      });
    }
  }

  testWidgets('동행 진입에 양쪽 가로 요청, 이탈에 방향 제한 해제', (t) async {
    final orientations = <dynamic>[];
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add(call.arguments);
      }
      return null;
    });
    final c = makeController();
    await t.pumpWidget(MaterialApp(home: CompanionScreen(controller: c)));
    await t.pumpAndSettle();
    expect(
        orientations.first,
        containsAll([
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight'
        ]));
    await t.pumpWidget(const SizedBox());
    expect(orientations.last, isEmpty);
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    c.dispose();
  });

  testWidgets('장면 크기가 바뀌면 드래그를 취소하고 새 장면 안으로 복귀한다', (t) async {
    final c = makeController();
    Widget host(Size size) => MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                    size: size,
                    child: CharacterStage(
                        controller: c,
                        sceneSize: size,
                        nowMs: () =>
                            t.binding.clock.now().millisecondsSinceEpoch,
                        layoutBuilder: (scene, message) => scene)))));
    await t.pumpWidget(host(const Size(500, 300)));
    await t.pumpAndSettle();
    final target = find.byKey(const ValueKey('character-touch-target'));
    final gesture = await t.startGesture(t.getCenter(target));
    await gesture.moveBy(const Offset(50, -30));
    await t.pump();
    await gesture.moveBy(const Offset(80, -30));
    await t.pump();
    await t.pumpWidget(host(const Size(320, 220)));
    await t.pumpAndSettle();
    final origin = t.getCenter(target);
    await gesture.moveBy(const Offset(-100, -100));
    await t.pump();
    expect(t.getCenter(target), origin);
    final window = t.getRect(find.byType(WindowView));
    final actor = t.getRect(target);
    expect(window.contains(actor.topLeft), isTrue);
    expect(window.contains(actor.bottomRight), isTrue);
    await gesture.up();
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
}
