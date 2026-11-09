import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:allo_phone/screens/hatching_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:allo_phone/widgets/game_orientation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('게임 화면이 겹쳐 교체될 때 마지막 화면 이탈 전에는 방향을 해제하지 않는다', (t) async {
    final requests = <dynamic>[];
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        requests.add(call.arguments);
      }
      return null;
    });
    GameOrientation.acquire();
    GameOrientation.acquire();
    GameOrientation.release();
    expect(requests.length, 1);
    expect(
        requests.single,
        containsAll([
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight'
        ]));
    GameOrientation.release();
    expect(requests.last, isEmpty);
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final size in [
    const Size(640, 360),
    const Size(844, 390),
    const Size(1024, 600)
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('품기 $size 글자$scale 알과 노래가 한 화면에 보인다', (t) async {
        await t.binding.setSurfaceSize(size);
        final c = GameController(
            feed: FakeVehicleFeed(scenario: FakeScenario.clear),
            dex: DexStore())
          ..game = const GameState(
              ts: 1,
              eggTier: EggTier.small,
              stage: Stage.incubating,
              progress: .7);
        await t.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16)),
                child: IncubatingScreen(controller: c))));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final egg = find.byKey(const ValueKey('egg-touch-target'));
        expect(egg.hitTestable(), findsOneWidget);
        expect(find.text('감싸기'), findsNothing);
        final scene = t.getRect(find.byType(WindowView));
        expect(scene.left, greaterThanOrEqualTo(24));
        expect(scene.bottom, lessThanOrEqualTo(size.height - 16));
        await t.tap(egg);
        await t.pump();
        expect(c.game.careCount, 1);
        final sing = find.text('♫ 길게 눌러 노래');
        expect(sing.hitTestable(), findsOneWidget);
        await t.longPress(sing);
        await t.pump();
        expect(c.game.careCount, 2);
        expect(find.text('품기 저장하고 나가기').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.binding.setSurfaceSize(null);
      });
      testWidgets('부화 $size 글자$scale 결과와 진입 버튼이 한 화면에 보인다', (t) async {
        await t.binding.setSurfaceSize(size);
        final c = GameController(
            feed: FakeVehicleFeed(scenario: FakeScenario.clear),
            dex: DexStore())
          ..game = const GameState(
              ts: 1, eggTier: EggTier.small, stage: Stage.hatched, progress: 1)
          ..hatched = Species.fromJson({
            'id': 'test',
            'nameKo': '긴 이름의 새로운 친구',
            'nameEn': 'A new friend',
            'attribute': 'normal',
            'tier': 1
          });
        await t.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16)),
                child: HatchingScreen(controller: c))));
        await t.pump();
        expect(find.text('건너뛰기').hitTestable(), findsOneWidget);
        await t.tap(find.text('건너뛰기'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final button = find.widgetWithText(FilledButton, '동행 시작');
        expect(button.hitTestable(), findsOneWidget);
        final rect = t.getRect(button);
        expect(rect.height, greaterThanOrEqualTo(56));
        expect(rect.bottom, lessThanOrEqualTo(size.height - 16));
        expect(rect.right, lessThanOrEqualTo(size.width - 24));
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.binding.setSurfaceSize(null);
      });
    }
  }
}
