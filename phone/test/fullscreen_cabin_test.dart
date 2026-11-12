import 'package:allo_phone/app.dart';
import 'package:allo_phone/explore/explore_screen.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:allo_phone/ui_mode.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> startTrip(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(2400, 1080);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AlloApp(
      feed: FakeVehicleFeed(
          scenario: FakeScenario.rainyHighway, timeScale: 100)));
  await tester.pumpAndSettle();
  await tester
      .runAsync(() => rootBundle.loadString('assets/data/species.json'));
  await tester.tap(find.text('체험 시작'));
  await tester.pumpAndSettle();
  for (var i = 0; i < 20 && find.byType(WindowView).evaluate().isEmpty; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pumpAndSettle(); // 화면 전환이 끝나야 알 품기 화면의 접근성 정보가 잡힌다
}

void main() {
  setUp(() {
    fullscreenCabin = true;
    autoEnterExplore = false;
  });
  tearDown(() => fullscreenCabin = false);

  testWidgets('알 품기 화면은 차 안 화면만 꽉 채운다 (제목·버튼 없음)', (tester) async {
    await startTrip(tester);
    final view = tester.getSize(find.byType(WindowView));
    expect(view.width, 800);
    expect(view.height, 360);
    // 아래에 깔린 첫 화면이 아니라 알 품기 화면 안에 제목줄이 없어야 한다
    expect(
        find.descendant(
            of: find.byType(IncubatingScreen), matching: find.byType(AppBar)),
        findsNothing);
    expect(find.text('감싸기'), findsNothing);
    expect(find.textContaining('성장'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('버튼이 없어도 알을 탭하면 감싸기가 된다', (tester) async {
    final semantics = tester.ensureSemantics();
    await startTrip(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('자라고 있는 알')));
    await tester.pump();
    // 감싸기는 차 화면에 보내는 돌봄 횟수로 확인한다
    expect(find.bySemanticsLabel(RegExp('돌봄 1회')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('Unity 빌드: 알을 품으면 바로 탐험, 그 안에서 부화하고 닫으면 부화 화면 → 같이 가자로 다시 탐험',
      (tester) async {
    autoEnterExplore = true;
    addTearDown(() => autoEnterExplore = false);
    await startTrip(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget, reason: '품기 시작과 함께 탐험으로');
    // 체험 주행은 100배속이라 기다리면 부화한다. 탐험이 떠 있는 동안은 부화 화면으로 넘기지 않는다
    for (var i = 0; i < 40 && find.text('같이 가자').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.text('같이 가자'), findsNothing);
    // 테스트에는 Unity 가 없어 깨어나는 연출을 못 봤으므로, 닫으면 부화 화면을 보여 준다
    await tester.tap(find.byTooltip('돌아가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('같이 가자'));
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
