import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/pairing_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('체험 시작은 여행 알을 한 번 준비하고 부화 화면으로 이동한다', (tester) async {
    final c = _EntryController();
    final router = _router(c);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('체험 시작'));
    await tester.pumpAndSettle();

    expect(c.ensureCalls, 1);
    expect(find.text('알 화면'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    router.dispose();
    c.dispose();
  });

  testWidgets('알을 고르는 두 번째 시작 모드를 제공하지 않는다', (tester) async {
    final c = _EntryController();
    final router = _router(c);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('마음으로 알 품기'), findsNothing);
    expect(find.byKey(const Key('start-affinity')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    router.dispose();
    c.dispose();
  });

  testWidgets('여행 알 준비에 실패하면 부화 화면으로 이동하지 않는다', (tester) async {
    final c = _EntryController()..ensureResult = false;
    final router = _router(c);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('체험 시작'));
    await tester.pumpAndSettle();

    expect(c.ensureCalls, 1);
    expect(find.text('알 화면'), findsNothing);
    expect(find.text('차 없이 알로를 체험해 보세요'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    router.dispose();
    c.dispose();
  });
}

GoRouter _router(GameController c) => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => PairingScreen(controller: c)),
        GoRoute(path: '/incubating', builder: (_, __) => const Text('알 화면')),
      ],
    );

class _EntryController extends GameController {
  _EntryController()
      : super(
            feed: FakeVehicleFeed(scenario: FakeScenario.clear),
            dex: DexStore());

  int ensureCalls = 0;
  bool ensureResult = true;

  @override
  Future<bool> ensureTripEgg(
      {EggTier tier = EggTier.small, bool useAffinity = true}) async {
    ensureCalls++;
    return ensureResult;
  }

  @override
  Future<bool> startIncubating(EggTier tier, {bool useAffinity = false}) =>
      throw StateError('Pairing entry must not start an egg directly');
}
