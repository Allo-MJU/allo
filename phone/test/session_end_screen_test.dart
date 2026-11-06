import 'package:allo_phone/app.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_end_test.dart' show EndingFeed;
import 'session_resume_test.dart' show sessionA;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('품기 중 차량 종료 후 연결 화면으로 돌아가 새 QR을 안내한다', (tester) async {
    await tester.runAsync(() => PairingStore()
        .save(PairingCredentials.parseFields(sessionA, '123456')));
    final feed = EndingFeed();
    await tester.pumpWidget(AlloApp(feed: feed));
    Future<void> untilVisible(String text) async {
      for (var i = 0; i < 50 && find.text(text).evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pumpAndSettle();
      }
      expect(find.text(text), findsOneWidget);
    }

    await untilVisible('차량과 연결됐어요');
    await tester.tap(find.text('알 품기 시작'));
    await untilVisible('알 품기');
    feed.send(2000);
    await tester.pump();
    feed.end();
    await untilVisible('주행이 끝났어요. 차량의 새 QR을 스캔해 주세요.');
    expect(find.text('알 품기'), findsNothing);
    expect(find.text('QR 스캔'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
