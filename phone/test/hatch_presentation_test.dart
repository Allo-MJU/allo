import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/hatching_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/widgets/egg_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  GameController controller([Attribute attribute = Attribute.water]) {
    final c = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore());
    c.game = c.game.copyWith(stage: Stage.hatched, progress: 1, tier: 3);
    c.hatched = Species.fromJson({
      'id': 'test',
      'nameKo': '물결지기',
      'nameEn': 'Tide Keeper',
      'attribute': attribute.name,
      'tier': 3
    });
    addTearDown(c.dispose);
    return c;
  }

  Widget app(GameController c, {bool reduce = false, double scale = 1}) =>
      MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  disableAnimations: reduce,
                  textScaler: TextScaler.linear(scale)),
              child: HatchingScreen(controller: c)));

  testWidgets('에셋 없이도 성장 경계의 3단계 알을 표시한다', (tester) async {
    for (final (progress, stage) in [
      (0.0, 1),
      (1 / 3, 2),
      (2 / 3, 3),
      (1.0, 3)
    ]) {
      await tester.pumpWidget(
          MaterialApp(home: EggArt(tier: EggTier.mid, progress: progress)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('성장 $stage단계 알'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('품기 ListView에서 에셋 없는 알도 정사각형이다', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(
      padding: const EdgeInsets.all(24),
      children: const [EggArt(tier: EggTier.small, progress: .5)],
    ))));
    await tester.pumpAndSettle();
    final paint = find.descendant(
        of: find.byType(EggArt), matching: find.byType(CustomPaint));
    expect(tester.getSize(paint), const Size.square(180));
  });

  testWidgets('금 가기→빛→등장 순서이며 게임 상태를 바꾸지 않는다', (tester) async {
    final c = controller();
    final before = c.game.toJson();
    await tester.pumpWidget(app(c));
    expect(find.text('조금씩 깨어나는 중'), findsOneWidget);
    expect(find.text('친구 만나기'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('곧 만나요'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('물결지기'), findsOneWidget);
    expect(find.text('물 속성 · 3등급'), findsOneWidget);
    expect(tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(72));
    expect(c.game.toJson(), before);
    expect(tester.takeException(), isNull);
  });
  testWidgets('건너뛰기 후 결과를 보고 동행으로 이동한다', (tester) async {
    final c = controller();
    final r = GoRouter(initialLocation: '/hatching', routes: [
      GoRoute(
          path: '/hatching', builder: (_, __) => HatchingScreen(controller: c)),
      GoRoute(path: '/companion', builder: (_, __) => const Text('동행 도착')),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('친구 만나기'));
    await tester.pumpAndSettle();
    expect(find.text('동행 도착'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    r.dispose();
  });
  for (final (attribute, label) in [
    (Attribute.water, '물'),
    (Attribute.dark, '어둠'),
    (Attribute.normal, '일반')
  ]) {
    testWidgets('$label 속성 모션 감소는 짧은 페이드로 결과를 표시한다', (tester) async {
      await tester.pumpWidget(app(controller(attribute), reduce: true));
      await tester.pumpAndSettle();
      expect(find.text('$label 속성 · 3등급'), findsOneWidget);
      expect(find.text('건너뛰기'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('시스템 모션 감소에서도 결과 페이드는 200ms를 유지한다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app(controller(), reduce: true));
    await tester.pump(const Duration(milliseconds: 100));
    final fade = tester.widgetList<Opacity>(find.byType(Opacity)).first;
    expect(fade.opacity, closeTo(.5, .05));
    await tester.pumpAndSettle();
  });

  testWidgets('작은 가로 화면과 큰 글씨에서도 결과 버튼에 도달한다', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(controller(), reduce: true, scale: 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('친구 만나기'));
    expect(tester.takeException(), isNull);
    expect(find.text('친구 만나기').hitTestable(), findsOneWidget);
  });
  testWidgets('연출 도중 화면 제거 시 ticker가 남지 않는다', (tester) async {
    await tester.pumpWidget(app(controller()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
