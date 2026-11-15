import 'dart:convert';
import 'package:allo_phone/app.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/explore/explore_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_resume_test.dart' show sessionA;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'Unity route owns navigation through session end without Flutter overlays',
      (tester) async {
    final messages = <Map<String, dynamic>>[];
    late void Function(String) receive;
    final feed = FakeVehicleFeed(scenario: FakeScenario.rainyHighway);
    await tester.pumpWidget(AlloApp(
        feed: feed,
        useUnityApp: true,
        unityView: ({required onCreated, required onMessage}) {
          receive = onMessage;
          onCreated(
              (json) => messages.add(jsonDecode(json) as Map<String, dynamic>));
          return const SizedBox(key: Key('unity-surface'));
        }));
    await tester.pumpAndSettle();
    receive('{"type":"ready"}');
    await tester.pump();
    expect(unityExploreOpen.value, isTrue);
    expect(find.byKey(const Key('unity-surface')), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    for (var i = 0;
        i < 500 &&
            !messages.any((m) => m['type'] == 'app' && m['ready'] == true);
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(messages.where((m) => m['type'] == 'app').last['ready'], true);
    expect(messages.where((m) => m['type'] == 'app').last['canStart'], false);
    expect(messages.where((m) => m['type'] == 'app').last['connected'], false);
    receive(jsonEncode({
      'v': 1,
      'type': 'appAction',
      'requestId': 'explicit-pair',
      'action': 'pair',
      'sessionId': sessionA,
      'pairCode': '123456'
    }));
    for (var i = 0;
        i < 500 &&
            !messages.any((m) => m['type'] == 'app' && m['connected'] == true);
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(messages.where((m) => m['type'] == 'app').last['connected'], true);
    receive('{"v":1,"type":"appAction","requestId":"end","action":"endTrip"}');
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 500 &&
            !messages
                .any((m) => m['type'] == 'app' && m['sessionEnded'] == true);
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.byKey(const Key('unity-surface')), findsOneWidget);
    expect(
        messages.where((m) => m['type'] == 'app').last['sessionEnded'], isTrue);
    expect(messages.map((m) => m['type']).toSet(),
        containsAll(['app', 'scene', 'cast', 'route', 'settings']));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(unityExploreOpen.value, isFalse);
  });
}
