import 'dart:convert';

import 'package:allo_phone/explore/explore_screen.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameController fakeController() => GameController(
    feed: FakeVehicleFeed(scenario: FakeScenario.sceneTour),
    dex: DexStore(),
    monotonicMs: () => 0);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unity 없으면 WindowView 로 대체', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ExploreScreen(controller: c, unityAvailable: false)));
    expect(find.byType(WindowView), findsOneWidget);
  });

  testWidgets('Unity 가 ready 를 보내면 scene·cast·settings 를 보낸다', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    final sent = <String>[];
    void Function(String)? toFlutter;
    await tester.pumpWidget(MaterialApp(
      home: ExploreScreen(
        controller: c,
        unityAvailable: true,
        unityView: ({required onCreated, required onMessage}) {
          toFlutter = onMessage;
          onCreated(sent.add);
          return const SizedBox.expand(key: Key('unity'));
        },
      ),
    ));
    expect(find.byKey(const Key('unity')), findsOneWidget);
    expect(sent, isEmpty, reason: 'ready 전에는 보내지 않는다');

    toFlutter!('{"v":1,"type":"ready"}');
    final types = [for (final s in sent) (jsonDecode(s) as Map)['type']];
    expect(types, containsAll(['scene', 'cast', 'settings']));
  });
}
