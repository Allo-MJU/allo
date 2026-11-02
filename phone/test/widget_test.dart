import 'package:allo_phone/app.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('앱이 페어링 화면으로 뜬다', (tester) async {
    await tester.pumpWidget(AlloApp(feed: FakeVehicleFeed(scenario: FakeScenario.clear)));
    await tester.pumpAndSettle();
    expect(find.text('차 화면의 QR을 찍어 주세요'), findsOneWidget);
  });
}
