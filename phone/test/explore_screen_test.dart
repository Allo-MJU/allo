import 'dart:convert';

import 'package:allo_core/allo_core.dart';
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

  testWidgets('Unity 의 tap·feed 는 동행 반응으로, spotted 는 창밖 발견으로 센다',
      (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    c.game = c.game.copyWith(stage: Stage.hatched);
    final sent = <String>[];
    void Function(String)? toFlutter;
    await tester.pumpWidget(MaterialApp(
      home: ExploreScreen(
        controller: c,
        unityAvailable: true,
        unityView: ({required onCreated, required onMessage}) {
          toFlutter = onMessage;
          onCreated(sent.add);
          return const SizedBox.expand();
        },
      ),
    ));
    toFlutter!('{"v":1,"type":"ready"}');
    toFlutter!('{"v":1,"type":"tap","id":"x"}');
    toFlutter!('{"v":1,"type":"feed"}');
    toFlutter!('{"v":1,"type":"spotted","id":"nobody"}');
    expect(c.playCount, 1);
    expect(c.feedCount, 1);
    expect(c.lookOutCount, 1);
    toFlutter!('{"v":1,"type":"tap","kind":"ball"}');
    toFlutter!('{"v":1,"type":"drink"}');
    toFlutter!('{"v":1,"type":"lookTogether"}');
    expect(c.playCount, 2);
    expect(c.feedCount, 2);
    expect(c.lookOutCount, 2);
    final toasts = [
      for (final s in sent)
        if ((jsonDecode(s) as Map)['type'] == 'toast')
          (jsonDecode(s) as Map)['text']
    ];
    expect(toasts, contains('봤어!'));
    expect(toasts, contains('같이 봤어요!'));
    expect(toasts, contains(c.companionMessage),
        reason: '먹이·놀이 반응 문구도 Unity 에 보낸다');
  });

  testWidgets('체험 주행이면 settings 에 canEndTrip 이 켜진다', (tester) async {
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
          return const SizedBox.expand();
        },
      ),
    ));
    toFlutter!('{"v":1,"type":"ready"}');
    final settings = sent
        .map((s) => jsonDecode(s) as Map)
        .firstWhere((m) => m['type'] == 'settings');
    expect(settings['canEndTrip'], isTrue);
  });

  testWidgets('Unity 의 endTrip 은 체험 주행을 끝내고 Unity 화면을 내린다', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    expect(await c.startIncubating(EggTier.small), isTrue);
    var closed = 0;
    void Function(String)? toFlutter;
    await tester.pumpWidget(MaterialApp(
      home: ExploreScreen(
        controller: c,
        unityAvailable: true,
        closeUnity: () async => closed++,
        unityView: ({required onCreated, required onMessage}) {
          toFlutter = onMessage;
          onCreated((_) {});
          return const SizedBox.expand();
        },
      ),
    ));
    toFlutter!('{"v":1,"type":"ready"}');
    toFlutter!('{"v":1,"type":"endTrip"}');
    for (var i = 0; i < 50 && !c.sessionEnded; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(c.sessionEnded, isTrue);
    expect(closed, 1, reason: '주행이 끝나면 Flutter 가 Unity 를 내린다');
    expect(unityExploreOpen.value, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(closed, 1, reason: '이미 내렸으면 dispose 에서 또 내리지 않는다');
    // 종료 저장이 끝날 때까지 시계를 돌린다 (위젯 테스트의 가짜 시간)
    for (var i = 0; i < 100 && !c.sessionSaved; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.sessionSaved, isTrue);
  });

  testWidgets('Flutter 가 먼저 탐험 화면을 떠나면 Unity 를 내린다', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    var closed = 0;
    await tester.pumpWidget(MaterialApp(
      home: ExploreScreen(
        controller: c,
        unityAvailable: true,
        closeUnity: () async => closed++,
        unityView: ({required onCreated, required onMessage}) {
          onCreated((_) {});
          return const SizedBox.expand();
        },
      ),
    ));
    await tester.pumpWidget(const SizedBox());
    expect(closed, 1);
  });

  testWidgets('탐험 중 품던 알이 깨어나면 egg 가 hatched·태어남 문구로 바뀌고, 닫을 때 true 를 돌려준다',
      (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    c.game = c.game.copyWith(stage: Stage.incubating, progress: 0.7);
    final sent = <String>[];
    void Function(String)? toFlutter;
    Object? result = 'none';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => ExploreScreen(
                controller: c,
                unityAvailable: true,
                unityView: ({required onCreated, required onMessage}) {
                  toFlutter = onMessage;
                  onCreated(sent.add);
                  return const SizedBox.expand();
                },
              ),
            ));
          },
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    toFlutter!('{"v":1,"type":"ready"}');
    List<Map> eggs() => [
          for (final s in sent)
            if ((jsonDecode(s) as Map)['type'] == 'egg') jsonDecode(s) as Map
        ];
    expect(eggs().last['state'], 'incubating');
    expect(eggs().last['progress'], 0.7);
    // egg 는 cast 보다 먼저 간다 (Unity 가 새 동행을 둥지에서 꺼내려면)
    final types = [for (final s in sent) (jsonDecode(s) as Map)['type']];
    expect(types.indexOf('egg'), lessThan(types.indexOf('cast')));

    // 돌보기
    toFlutter!('{"v":1,"type":"care","kind":"rub"}');
    expect(c.careCount, 1);

    c.hatched = const Species(
        id: 'puddle_pip',
        nameEn: 'Puddle Pip',
        nameKo: '퍼들핍',
        attribute: Attribute.water,
        tier: 1,
        requiredTags: [],
        maxHarsh: null,
        hint: '',
        sprite: 'species/puddle_pip.png');
    c.game = c.game.copyWith(stage: Stage.hatched, progress: 1);
    c.notifyListeners();
    expect(eggs().last['state'], 'hatched');
    expect(eggs().last['bornText'], '퍼들핍이 태어났어요!');

    toFlutter!('{"v":1,"type":"close"}');
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('이미 부화한 뒤에 들어오면 태어남 문구 없이 hatched 만 보내고, 닫을 때 false', (tester) async {
    final c = fakeController();
    addTearDown(c.dispose);
    c.game = c.game.copyWith(stage: Stage.hatched, progress: 1);
    final sent = <String>[];
    void Function(String)? toFlutter;
    Object? result = 'none';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => ExploreScreen(
                controller: c,
                unityAvailable: true,
                unityView: ({required onCreated, required onMessage}) {
                  toFlutter = onMessage;
                  onCreated(sent.add);
                  return const SizedBox.expand();
                },
              ),
            ));
          },
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    toFlutter!('{"v":1,"type":"ready"}');
    final egg = [
      for (final s in sent)
        if ((jsonDecode(s) as Map)['type'] == 'egg') jsonDecode(s) as Map
    ].last;
    expect(egg['state'], 'hatched');
    expect(egg['bornText'], '');
    toFlutter!('{"v":1,"type":"close"}');
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
