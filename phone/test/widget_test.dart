import 'package:allo_phone/app.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('체험 시작 → 돌봄 → 부화 → 동행 → 도감', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(AlloApp(
        feed: FakeVehicleFeed(
            scenario: FakeScenario.rainyHighway, timeScale: 100)));
    await tester.pumpAndSettle();
    expect(find.text('차 없이 알로를 체험해 보세요'), findsOneWidget);
    expect(find.text('QR 스캔'), findsNothing);
    await tester.runAsync(() => rootBundle.loadString('assets/data/species.json'));
    await tester.tap(find.text('체험 시작'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && find.text('알 품기').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.text('알 품기'), findsOneWidget);
    await tester.tap(find.text('감싸기'));
    await tester.pump();
    expect(find.textContaining('돌봄 1회'), findsOneWidget);
    await tester.longPress(find.text('♫ 길게 눌러 노래'));
    await tester.pump();
    expect(find.textContaining('돌봄 2회'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('친구 만나기'), findsOneWidget);
    await tester.tap(find.text('친구 만나기'));
    await tester.pumpAndSettle();
    expect(find.text('봤어!'), findsOneWidget);
    await tester.tap(find.text('먹이'));
    await tester.pumpAndSettle();
    expect(find.textContaining('맛있게 먹었어요'), findsOneWidget);
    await tester.tap(find.text('놀아주기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('먹이 1회 · 놀이 1회'), findsOneWidget);
    expect(find.textContaining('신나게 뛰어요'), findsOneWidget);
    await tester.tap(find.text('도착'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && find.text('도감').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('도감'), findsOneWidget);
    expect(find.byIcon(Icons.pets), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
