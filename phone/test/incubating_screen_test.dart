import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  GameController controller(Stage stage) => GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: DexStore(),
      )..game = GameState(
          ts: 0,
          eggTier: EggTier.small,
          stage: stage,
          progress: stage == Stage.hatched ? 1 : 0,
        );

  GoRouter router(GameController c, {void Function()? onHatching}) => GoRouter(
        initialLocation: '/incubating',
        redirect: (_, state) {
          if (state.uri.path == '/hatching') onHatching?.call();
          return null;
        },
        routes: [
          GoRoute(
            path: '/incubating',
            builder: (_, __) => IncubatingScreen(controller: c),
          ),
          GoRoute(
            path: '/hatching',
            builder: (_, __) => const Scaffold(body: Text('부화 화면')),
          ),
        ],
      );

  testWidgets('진입 전에 이미 부화했다면 후속 신호 없이 부화 화면으로 이동한다', (tester) async {
    final c = controller(Stage.hatched);
    final r = router(c);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    expect(find.text('부화 화면'), findsOneWidget);
    expect(find.text('알 품기'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    r.dispose();
    c.dispose();
  });

  testWidgets('한 프레임에 부화 알림이 반복돼도 화면 전환은 한 번이다', (tester) async {
    final c = controller(Stage.incubating);
    var transitions = 0;
    final r = router(c, onHatching: () => transitions++);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    expect(find.text('알 품기'), findsOneWidget);
    c.game = c.game.copyWith(stage: Stage.hatched, progress: 1);
    c.notifyListeners();
    c.notifyListeners();
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('부화 화면'), findsOneWidget);
    expect(transitions, 1);
    await tester.pumpWidget(const SizedBox());
    r.dispose();
    c.dispose();
  });

  testWidgets('예약된 부화 전환 전에 화면이 제거되면 이동하지 않는다', (tester) async {
    final c = controller(Stage.incubating);
    var transitions = 0;
    final r = router(c, onHatching: () => transitions++);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    c.game = c.game.copyWith(stage: Stage.hatched, progress: 1);
    c.notifyListeners();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(transitions, 0);
    r.dispose();
    c.dispose();
  });
}
