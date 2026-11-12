import 'package:allo_phone/app.dart';
import 'package:allo_phone/explore/explore_screen.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _tap(WidgetTester tester, Finder f, {bool long = false}) async {
  if (f.evaluate().isEmpty) {
    // 가로 화면에서는 아래쪽 버튼이 아직 만들어지지 않았을 수 있다
    await tester.scrollUntilVisible(f, 120,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  long ? await tester.longPress(f) : await tester.tap(f);
}

void main() {
  testWidgets('체험 시작 → 돌봄 → 부화 → 동행 → 도감', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // 가로 휴대폰 화면 (800×360). 아래 버튼은 스크롤해서 누른다.
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AlloApp(
        feed: FakeVehicleFeed(
            scenario: FakeScenario.rainyHighway, timeScale: 100)));
    await tester.pumpAndSettle();
    expect(find.text('차 없이 알로를 체험해 보세요'), findsOneWidget);
    expect(find.text('QR 스캔'), findsNothing);
    await tester
        .runAsync(() => rootBundle.loadString('assets/data/species.json'));
    await _tap(tester, find.text('체험 시작'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && find.text('알 품기').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.text('알 품기'), findsOneWidget);
    await _tap(tester, find.text('감싸기'));
    await tester.pump();
    expect(find.textContaining('돌봄 1회'), findsOneWidget);
    await _tap(tester, find.text('♫ 길게 눌러 노래'), long: true);
    await tester.pump();
    expect(find.textContaining('돌봄 2회'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('같이 가자'), findsOneWidget);
    await _tap(tester, find.text('같이 가자'));
    await tester.pumpAndSettle();
    expect(find.text('봤어!'), findsOneWidget);
    await _tap(tester, find.text('차 안 둘러보기'));
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget);
    await tester.tap(find.byTooltip('돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('봤어!'), findsOneWidget);
    await _tap(tester, find.text('먹이'));
    await tester.pumpAndSettle();
    expect(find.textContaining('맛있게 먹었어요'), findsOneWidget);
    await _tap(tester, find.text('놀아주기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('먹이 1회 · 놀이 1회'), findsOneWidget);
    expect(find.textContaining('신나게 뛰어요'), findsOneWidget);
    await _tap(tester, find.text('도착'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && find.text('도감').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('도감'), findsOneWidget);
    expect(find.text('만난 친구 1 / 12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
