import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/explore/explore_screen.dart';
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

  group('탐험 중 부화', () {
    // 탐험 화면 대신, 닫을 때 정해진 결과를 돌려주는 빈 화면
    GoRouter exploreRouter(GameController c,
            {required bool? closeWith, bool autoEnter = false}) =>
        GoRouter(
          initialLocation: '/incubating',
          routes: [
            GoRoute(
                path: '/incubating',
                builder: (_, __) => IncubatingScreen(
                    controller: c, enterExplore: autoEnter)),
            GoRoute(
                path: '/hatching',
                builder: (_, __) => const Scaffold(body: Text('부화 화면'))),
            GoRoute(
                path: '/companion',
                builder: (_, __) => const Scaffold(body: Text('동행 화면'))),
            GoRoute(
                path: '/explore',
                builder: (context, __) => _FakeExplore(hatchShown: closeWith)),
          ],
        );

    Future<void> openExplore(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text('차 안 둘러보기'), 200);
      await tester.tap(find.text('차 안 둘러보기'));
      await tester.pumpAndSettle();
      expect(find.text('탐험 닫기'), findsOneWidget);
    }

    testWidgets('탐험이 떠 있는 동안 부화해도 부화 화면으로 넘어가지 않는다', (tester) async {
      final c = controller(Stage.incubating);
      final r = exploreRouter(c, closeWith: true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      await openExplore(tester);
      c.game = c.game.copyWith(stage: Stage.hatched, progress: 1);
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('탐험 닫기'), findsOneWidget, reason: '탐험이 그대로 떠 있어야 한다');
      expect(find.text('부화 화면'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      r.dispose();
      c.dispose();
    });

    testWidgets('탐험에서 깨어나는 연출을 봤으면(true) 닫을 때 동행 화면으로 간다', (tester) async {
      final c = controller(Stage.incubating);
      final r = exploreRouter(c, closeWith: true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      await openExplore(tester);
      c.game = c.game.copyWith(stage: Stage.hatched, progress: 1);
      c.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('탐험 닫기'));
      await tester.pumpAndSettle();
      expect(find.text('동행 화면'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      r.dispose();
      c.dispose();
    });

    testWidgets('연출을 못 봤으면(Unity 없음) 닫을 때 부화 화면으로 간다', (tester) async {
      final c = controller(Stage.incubating);
      final r = exploreRouter(c, closeWith: null);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      await openExplore(tester);
      c.game = c.game.copyWith(stage: Stage.hatched, progress: 1);
      c.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('탐험 닫기'));
      await tester.pumpAndSettle();
      expect(find.text('부화 화면'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      r.dispose();
      c.dispose();
    });

    testWidgets('Unity 빌드에서는 품기를 시작하면 바로 탐험으로 들어간다', (tester) async {
      final c = controller(Stage.incubating);
      final r = exploreRouter(c, closeWith: null, autoEnter: true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      expect(find.text('탐험 닫기'), findsOneWidget);
      // 닫으면 품기 화면에 남고 (자동으로 다시 열지 않는다)
      await tester.tap(find.text('탐험 닫기'));
      await tester.pumpAndSettle();
      expect(find.text('탐험 닫기'), findsNothing);
      expect(find.byType(IncubatingScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      r.dispose();
      c.dispose();
    });
  });
}

/// 탐험 화면 대신: 열려 있는 동안 [exploreScreenOpen] 을 켜고, 닫힐 때 깨어나는 연출을 봤는지 남긴다
class _FakeExplore extends StatefulWidget {
  const _FakeExplore({required this.hatchShown});
  final bool? hatchShown;

  @override
  State<_FakeExplore> createState() => _FakeExploreState();
}

class _FakeExploreState extends State<_FakeExplore> {
  @override
  void initState() {
    super.initState();
    exploreScreenOpen.value = true;
  }

  @override
  void dispose() {
    exploreHatchShown = widget.hatchShown == true;
    exploreScreenOpen.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: TextButton(
          onPressed: () => context.pop(), child: const Text('탐험 닫기')));
}
