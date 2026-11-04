import 'package:allo_phone/app.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final viaDex in [false, true]) {
    testWidgets('체험 주행 종료 후 ${viaDex ? "도감 경유" : "직접"} 재시작에서 이어간다',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester
          .runAsync(() => rootBundle.loadString('assets/data/species.json'));
      await tester.pumpWidget(
          AlloApp(feed: FakeVehicleFeed(scenario: FakeScenario.rainyHighway)));

      Future<void> untilVisible(String label) async {
        for (var i = 0; i < 50 && find.text(label).evaluate().isEmpty; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        expect(find.text(label), findsOneWidget);
      }

      await tester.pumpAndSettle();
      await tester.tap(find.text('체험 시작'));
      await untilVisible('알 품기');
      await tester.pump(const Duration(seconds: 2));
      final c = tester
          .widget<IncubatingScreen>(find.byType(IncubatingScreen))
          .controller;
      expect(c.game.progress, .2);
      await tester.tap(find.text('주행 종료'));
      await untilVisible('기록을 저장했어요');
      expect(c.sessionSaved, isTrue);
      expect(find.text('체험 다시 시작'), findsOneWidget);
      expect(find.text('새 차량 연결'), findsNothing);
      if (viaDex) {
        await tester.tap(find.text('도감 보기'));
        await untilVisible('만난 친구 0 / 12');
        await tester.tap(find.byTooltip('돌아가기'));
      } else {
        await tester.tap(find.text('체험 다시 시작'));
      }
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ButtonStyleButton>(find.ancestor(
                  of: find.text('체험 시작'),
                  matching:
                      find.byWidgetPredicate((w) => w is ButtonStyleButton)))
              .onPressed,
          isNotNull);
      await tester.tap(find.text('체험 시작'));
      await untilVisible('알 품기');
      await tester.pump(const Duration(seconds: 1));
      expect(c.game.progress, .3);
      await tester.tap(find.text('주행 종료'));
      await untilVisible('기록을 저장했어요');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
