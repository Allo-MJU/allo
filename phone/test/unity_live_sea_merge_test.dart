import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/quests/companion_quest_coordinator.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'affinity_controller_test.dart' show DemoApi;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late BaseCampController camp;
  late UnityAppController app;
  late Completer<Map<String, dynamic>> template;
  late String creatureId, questId;
  var serial = 0, requests = 0;
  Map<String, dynamic> story() => app.snapshot['story'] as Map<String, dynamic>;
  Future<bool> action(String name, [Map<String, dynamic> fields = const {}]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'live-sea-${serial++}',
        'action': name,
        'creatureId': creatureId,
        'questId': questId,
        if (name.startsWith('story'))
          'storyPresentationRevision': story()['presentationRevision'],
        ...fields,
      }));
  Map<String, dynamic> response() => {
        'schemaVersion': 1,
        'templateId': 'food-berry-0',
        'templateVersion': 1,
        'speciesId': 'road_sprout',
        'kind': 'food',
        'title': '간식 부탁',
        'text': '베리 간식 하나 나눠 줄래?',
        'storyId': null,
        'targetFoodId': 'berry_snack',
        'targetRegion': null,
      };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    serial = requests = 0;
    template = Completer<Map<String, dynamic>>();
    final dex = DexStore();
    await dex.add(DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'live-sea-owned'));
    camp = BaseCampController(store: CampMemory(), dex: dex);
    final feed = RoundFeed();
    game =
        GameController(feed: feed, dex: dex, baseCamp: camp, eggApi: DemoApi());
    final quests = CompanionQuestCoordinator(
        game: game,
        camp: camp,
        templateRequest: (_) {
          requests++;
          return template.future;
        });
    app = UnityAppController(game: game, camp: camp, quests: quests);
    expect(await app.initialize(), true);
    await game.pair(sessionA, pairCode: '123456');
    feed.sample(tags: ['coast']);
    creatureId = camp.state.creatures.keys.single;
    questId = (app.snapshot['quests'] as List).single['questId'] as String;
    await action('navigate', {'view': 'cabin'});
    await app.setHostLifecycle(AppLifecycleState.paused);
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });

  test('native-host handoff pauses sea and invalidates old notebook capture',
      () async {
    expect(await action('storyNotebook', {'open': true}), true);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
    final presentation = story()['presentationRevision'];
    app.detach();
    expect(story()['paused'], true);
    expect(story()['notebookOpen'], false);
    expect(story()['presentationRevision'], greaterThan(presentation));
    expect(app.learning!.active, false);
    final rejected = action('openQuest');
    if (requests > 0) template.complete(response());
    expect(await rejected, false);
    expect(requests, 0);

    app.attach((_) {});
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(story()['canOpen'], true);
    expect(story()['paused'], true);
    expect(
        await action('storyStart', {
          'topicId': 'coast_sail',
          'storyPresentationRevision': presentation,
        }),
        false);
  });

  test('sea capture and quest template request cannot overlap', () async {
    expect(await action('storyNotebook', {'open': true}), true);
    final rejected = action('openQuest');
    if (requests > 0) template.complete(response());
    expect(await rejected, false);
    expect(requests, 0);
    expect(await action('storyNotebook', {'open': false}), true);
    final opening = action('openQuest');
    expect(requests, 1);
    expect(await action('storyNotebook', {'open': true}), false);
    template.complete(response());
    await opening;
    expect(await action('laterQuest'), true);
    expect(await action('storyNotebook', {'open': true}), true);
  });

  test('handoff discards pending quest result and closes a notebook', () async {
    final opening = action('openQuest');
    expect(requests, 1);
    app.detach();
    template.complete(response());
    await opening;
    expect(camp.state.quests[creatureId], isNull);
    expect((app.snapshot['quests'] as List).single['opened'], false);
    app.attach((_) {});
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(await action('storyNotebook', {'open': true}), true);
    final presentation = story()['presentationRevision'];
    await app.setHostLifecycle(AppLifecycleState.detached);
    expect(story()['notebookOpen'], false);
    expect(story()['presentationRevision'], greaterThan(presentation));
  });

  test('isolated test profile does not retire the vehicle story owner',
      () async {
    expect(await action('storyNotebook', {'open': true}), true);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
    final dex = DexStore(profile: 'test-connection');
    final testCamp = BaseCampController(store: CampMemory(), dex: dex);
    final testGame = GameController(
        feed: RoundFeed(), dex: dex, baseCamp: testCamp, eggApi: DemoApi());
    final testApp = UnityAppController(game: testGame, camp: testCamp);
    addTearDown(() {
      testApp.dispose();
      testGame.dispose();
      testCamp.dispose();
    });
    expect(await testApp.initialize(), true);
    expect((testApp.snapshot['story'] as Map)['cardCount'], 0);
    testApp.attach((_) {}, replacing: app);
    expect(story()['paused'], true);
    app.attach((_) {}, replacing: testApp);
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(await action('storyNotebook', {'open': true}), true);
    expect(
        await action('storyResume', {
          'instanceId': story()['instanceId'],
          'nodeId': story()['nodeId'],
          'storyRevision': story()['revision'],
        }),
        true);
    expect(story()['active'], true);
  });

  test('legacy demo profile keeps its cards outside the isolated test profile',
      () async {
    app.dispose();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        'unityApp.story.v1',
        jsonEncode({
          'version': 1,
          'cards': ['coast_sail']
        }));
    Future<UnityAppController> create(String profile) async {
      final dex = DexStore(profile: profile);
      final otherCamp = BaseCampController(store: CampMemory(), dex: dex);
      final otherGame =
          GameController(feed: RoundFeed(), dex: dex, baseCamp: otherCamp);
      final other = UnityAppController(game: otherGame, camp: otherCamp);
      addTearDown(() {
        other.dispose();
        otherGame.dispose();
        otherCamp.dispose();
      });
      expect(await other.initialize(), true);
      return other;
    }

    final legacy = await create('unity-demo-examples');
    expect((legacy.snapshot['story'] as Map)['cardCount'], 1);
    final isolated = await create('test-connection');
    expect((isolated.snapshot['story'] as Map)['cardCount'], 0);
    expect((legacy.snapshot['story'] as Map)['cardCount'], 1);
    expect(
        preferences.getString('unityApp.story.v1'),
        jsonEncode({
          'version': 1,
          'cards': ['coast_sail']
        }));
  });
}
