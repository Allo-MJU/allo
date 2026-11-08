import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:allo_phone/screens/companion_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/widgets/egg_art.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

VehicleState vehicle(List<String> tags, {double speed = 80}) =>
    VehicleState.fromJson(
        {'gear': 'D', 'speedKph': speed, 'envTags': tags, 'wiperLevel': 3});

void main() {
  testWidgets('비 오는 고속 주행도 시간·속도만 바뀌면 같은 정지 그림이다', (tester) async {
    final key = GlobalKey();
    Widget host(double speed) => MaterialApp(
            home: Scaffold(
                body: Center(
          child: RepaintBoundary(
              key: key,
              child: SizedBox(
                  width: 320,
                  child: WindowView(
                      vehicle: vehicle(['coast', 'rain'], speed: speed)))),
        )));
    Future<Uint8List> pixels() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    await tester.pumpWidget(host(80));
    await tester.pumpAndSettle();
    final before = await pixels();
    await tester.pump(const Duration(seconds: 5));
    expect(await pixels(), orderedEquals(before));
    await tester.pumpWidget(host(120));
    await tester.pumpAndSettle();
    expect(await pixels(), orderedEquals(before));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('터널·날씨 전환은 페이드만 하고 알은 유지한다', (tester) async {
    Widget host(List<String> tags) => MaterialApp(
            home: Scaffold(
                body: WindowView(
          vehicle: vehicle(tags),
          child: const EggArt(tier: EggTier.mid, progress: .5, size: 120),
        )));
    await tester.pumpWidget(host(['coast', 'rain']));
    await tester.pumpAndSettle();
    final egg = tester.element(find.byType(EggArt));
    await tester.pumpWidget(host(['tunnel']));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('창밖: 터널'), findsOneWidget);
    expect(tester.element(find.byType(EggArt)), same(egg));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('시스템 동작 줄이기에서도 장면은 200ms 페이드한다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    Widget host(List<String> tags) =>
        MaterialApp(home: Scaffold(body: WindowView(vehicle: vehicle(tags))));
    await tester.pumpWidget(host(['coast']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(['tunnel']));
    // didUpdateWidget에서 시작한 ticker의 첫 프레임을 기준으로 시간을 잰다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    final layers = find.descendant(
        of: find.byType(WindowView), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(layers).opacity, 1);
    // Flutter simulation은 duration 초과 프레임에서 ticker를 완료한다.
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('품기 창 앞에서 성장 단계와 감싸기 동작을 보존한다', (tester) async {
    final c = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore());
    c.game = c.game.copyWith(stage: Stage.incubating, progress: .7);
    c.vehicle = vehicle(['mountain']);
    await tester.pumpWidget(MaterialApp(home: IncubatingScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(WindowView), matching: find.byType(EggArt)),
        findsOneWidget);
    expect(find.bySemanticsLabel('성장 3단계 알'), findsOneWidget);
    await tester.ensureVisible(find.text('감싸기'));
    await tester.tap(find.text('감싸기'));
    await tester.pump();
    expect(c.game.careCount, 1);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('동행은 창밖 상태 변경 후에도 먹이·놀이를 보존한다', (tester) async {
    final c = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore());
    c.game = c.game.copyWith(stage: Stage.hatched);
    c.vehicle = vehicle(['city', 'night']);
    await tester.pumpWidget(MaterialApp(home: CompanionScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byType(WindowView), findsOneWidget);
    await tester.ensureVisible(find.text('먹이'));
    await tester.tap(find.text('먹이'));
    await tester.pump();
    c.vehicle = vehicle(['tunnel']);
    c.notifyListeners();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('놀아주기'));
    await tester.tap(find.text('놀아주기'));
    await tester.pumpAndSettle();
    expect(c.feedCount, 1);
    expect(c.playCount, 1);
    expect(find.bySemanticsLabel('창밖: 터널'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
