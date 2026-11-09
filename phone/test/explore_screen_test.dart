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
    await tester.pumpWidget(
        MaterialApp(home: ExploreScreen(controller: c, unityAvailable: false)));
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

  testWidgets('Unity 가 close 를 보내면 탐험 화면을 닫는다', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    void Function(String)? toFlutter;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ExploreScreen(
              controller: c,
              unityAvailable: true,
              unityView: ({required onCreated, required onMessage}) {
                toFlutter = onMessage;
                onCreated((_) {});
                return const SizedBox.expand(key: Key('unity'));
              },
            ),
          )),
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget);
    toFlutter!('{"v":1,"type":"close"}');
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsNothing);
  });

  testWidgets('Unity 가 close 를 보낸 뒤 앱이 돌아와도 Unity 를 다시 열지 않는다', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    void Function(String)? toFlutter;
    var resumed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ExploreScreen(
              controller: c,
              unityAvailable: true,
              unityView: ({required onCreated, required onMessage}) {
                toFlutter = onMessage;
                onCreated((_) {}, () => resumed++);
                return const SizedBox.expand();
              },
            ),
          )),
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    toFlutter!('{"v":1,"type":"close"}');
    // 닫히는 전환이 끝나기 전에 Flutter 화면이 다시 앞으로 온다
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(resumed, 0);
  });

  test('Unity 탐험 화면이 앞에 있는 동안은 앱이 활성 상태다', () {
    expect(appActiveFor(AppLifecycleState.resumed, unityOpen: false), isTrue);
    expect(appActiveFor(AppLifecycleState.paused, unityOpen: false), isFalse);
    expect(appActiveFor(AppLifecycleState.hidden, unityOpen: true), isTrue);
    expect(appActiveFor(AppLifecycleState.paused, unityOpen: true), isTrue);
    // 화면이 꺼지거나 앱이 끝나는 중이면 Unity 가 열려 있어도 멈춘다
    expect(appActiveFor(AppLifecycleState.detached, unityOpen: true), isFalse);
  });

  testWidgets('Unity 탐험 화면이 열리면 unityExploreOpen 이 켜지고, close 로 꺼진다',
      (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    void Function(String)? toFlutter;
    await tester.pumpWidget(MaterialApp(
      home: ExploreScreen(
        controller: c,
        unityAvailable: true,
        unityView: ({required onCreated, required onMessage}) {
          toFlutter = onMessage;
          onCreated((_) {});
          return const SizedBox.expand();
        },
      ),
    ));
    expect(unityExploreOpen.value, isTrue);
    toFlutter!('{"v":1,"type":"close"}');
    expect(unityExploreOpen.value, isFalse);
  });

  testWidgets('close 가 두 번 오거나 시스템 뒤로 가기와 겹쳐도 탐험 화면 하나만 닫는다', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    void Function(String)? toFlutter;
    final explore = MaterialPageRoute<void>(
      builder: (_) => ExploreScreen(
        controller: c,
        unityAvailable: true,
        unityView: ({required onCreated, required onMessage}) {
          toFlutter = onMessage;
          onCreated((_) {});
          return const SizedBox.expand();
        },
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(explore),
                child: const Text('동행'),
              ),
            ),
          )),
          child: const Text('처음'),
        ),
      ),
    ));
    await tester.tap(find.text('처음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동행'));
    await tester.pumpAndSettle();
    // 시스템 뒤로 가기가 먼저 탐험 화면을 닫고, 늦게 온 close 가 또 닫으려 한다
    await tester.binding.handlePopRoute();
    toFlutter!('{"v":1,"type":"close"}');
    toFlutter!('{"v":1,"type":"close"}');
    await tester.pumpAndSettle();
    expect(find.text('동행'), findsOneWidget, reason: '동행 화면까지 닫히면 안 된다');
  });
}
