import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/app.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/explore/explore_screen.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/screens/dex_screen.dart';
import 'package:allo_phone/screens/home_screen.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:allo_phone/ui_mode.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 광장 흐름(꽉 찬 화면 모드): 체험 시작 → 광장. 주행 중 Flutter 차 안 화면은 없다
Future<void> startTrip(WidgetTester tester,
    {String? demoSpecies, double timeScale = 100}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(2400, 1080);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final feed = FakeVehicleFeed(
      scenario: FakeScenario.rainyHighway, timeScale: timeScale);
  final controller =
      GameController(feed: feed, dex: DexStore(), demoSpeciesId: demoSpecies);
  // Load real assets outside the fake clock; keep the feed timer on test time.
  await tester.runAsync(controller.loadSpecies);
  // Preserve the distance-only plaza UI while new trip grants default to affinity.
  expect(await controller.startIncubating(EggTier.small), isTrue);
  await tester
      .pumpWidget(AlloApp(feed: feed, createController: () => controller));
  await tester.pumpAndSettle();
  await tester
      .runAsync(() => rootBundle.loadString('assets/data/species.json'));
  await tester.tap(find.text('체험 시작'));
  await tester.pumpAndSettle();
  for (var i = 0;
      i < 20 &&
          find.byType(HomeScreen).evaluate().isEmpty &&
          find.byType(ExploreScreen).evaluate().isEmpty;
      i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    fullscreenCabin = true;
    autoEnterExplore = false;
  });
  tearDown(() => fullscreenCabin = false);

  testWidgets('체험을 시작하면 광장: 알 카드와 차 안으로·도감 버튼, Flutter 차 안 화면은 없다',
      (tester) async {
    await startTrip(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(IncubatingScreen), findsNothing);
    expect(find.byType(WindowView), findsNothing);
    expect(find.text('광장'), findsOneWidget);
    expect(find.text('차 안으로'), findsOneWidget);
    expect(find.text('도감'), findsOneWidget);
    expect(find.text('알을 품는 중'), findsOneWidget);
    expect(find.text('주행 종료'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('광장에서 알을 탭하면 감싸기가 된다', (tester) async {
    final semantics = tester.ensureSemantics();
    await startTrip(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('자라고 있는 알')));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('자라고 있는 알, 돌봄 1회')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('광장 ↔ 차 안 ↔ 도감을 오갈 수 있다', (tester) async {
    await startTrip(tester, timeScale: 1); // 오가는 동안 부화하지 않게 천천히
    await tester.tap(find.text('차 안으로'));
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget);
    await tester.tap(find.byTooltip('돌아가기'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget, reason: '차 안에서 나오면 광장');
    await tester.tap(find.text('도감'));
    // 도감은 저장소를 비동기로 읽는다. 다 읽을 때까지 로딩 표시가 돌므로 pumpAndSettle 대신 잠깐 기다린다
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(AppBar, '도감'), findsOneWidget); // 도감 제목
    expect(find.byType(DexScreen), findsOneWidget);
    await tester.tap(find.byTooltip('돌아가기'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget, reason: '도감에서 돌아오면 광장');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('광장에서 부화하면 부화 화면 → 같이 가자 → 광장의 동행 카드', (tester) async {
    await startTrip(tester, demoSpecies: 'road_sprout');
    for (var i = 0; i < 40 && find.text('같이 가자').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('같이 가자'), findsOneWidget);
    expect(find.text('길싹이'), findsWidgets, reason: 'DEMO_SPECIES 로 고정한 종');
    await tester.tap(find.text('같이 가자'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('길싹이'), findsOneWidget);
    expect(find.text('차 안으로'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('광장의 주행 종료 → 종료 화면', (tester) async {
    await startTrip(tester);
    await tester.tap(find.text('주행 종료'));
    // 기록 저장은 실제 비동기(저장소)라 잠깐씩 기다리며 종료 화면을 기다린다
    for (var i = 0; i < 40 && find.text('체험 다시 시작').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('체험 다시 시작'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500)); // 화면 전환이 끝나면 광장은 없다
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Unity 빌드: 알을 품으면 바로 차 안, 그 안에서 부화하고 나오면 부화 화면 → 같이 가자로 다시 차 안',
      (tester) async {
    autoEnterExplore = true;
    addTearDown(() => autoEnterExplore = false);
    await startTrip(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget,
        reason: '품기 시작과 함께 차 안으로');
    // 체험 주행은 100배속이라 기다리면 부화한다. 차 안이 떠 있는 동안은 부화 화면으로 넘기지 않는다
    for (var i = 0; i < 40 && find.text('같이 가자').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.text('같이 가자'), findsNothing);
    // 테스트에는 Unity 가 없어 깨어나는 연출을 못 봤으므로, 나오면 부화 화면을 보여 준다
    await tester.tap(find.byTooltip('돌아가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('같이 가자'));
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget);
    // 다시 나오면 광장 (알마다 한 번만 자동으로 들어가므로 또 들어가지 않는다)
    await tester.tap(find.byTooltip('돌아가기'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ExploreScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
