import 'dart:convert';

import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
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
  late UnityAppController app;
  late BaseCampController camp;
  late RoundFeed feed;
  var request = 0;
  var now = 0;

  Future<bool> action(String name,
          [Map<String, dynamic> fields = const {}, String? id]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': id ?? 'story-test-${request++}',
        'action': name,
        ...fields,
      }));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    request = 0;
    now = 0;
    feed = RoundFeed();
    camp = BaseCampController(store: CampMemory());
    game = GameController(
      feed: feed,
      dex: DexStore(),
      eggApi: DemoApi(),
      baseCamp: camp,
      monotonicMs: () => now,
    );
    app = UnityAppController(game: game, camp: camp);
    expect(await app.initialize(), isTrue);
    await game.pair(sessionA, pairCode: '123456');
    feed.sample(tags: ['coast']);
    await action('navigate', {'view': 'cabin'});
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });

  test('voice configuration is transient and leaves game story unchanged',
      () async {
    final sent = <Map<String, dynamic>>[];
    app.attach((json) => sent.add(jsonDecode(json) as Map<String, dynamic>));
    final before = jsonEncode(app.snapshot);
    const requestId = '0123456789abcdef0123456789abcdef';
    expect(
        await app.handleMessage(jsonEncode({
          'v': 1,
          'type': 'storyVoiceConfigRequest',
          'requestId': requestId,
        })),
        isTrue);
    expect(sent.last['type'], 'storyVoiceConfig');
    expect(sent.last['requestId'], requestId);
    expect(sent.last['token'], '');
    expect(jsonEncode(app.snapshot), before);
    expect(
        await app.handleMessage(jsonEncode({
          'v': 1,
          'type': 'storyVoiceConfigRequest',
          'requestId': '../../bad',
        })),
        isFalse);
  });

  test('window story experiment never automatically starts or offers in cabin',
      () async {
    expect((app.snapshot['story'] as Map)['active'], false);
    expect((app.snapshot['story'] as Map)['notebookOpen'], false);
    for (final tags in [
      ['coast'],
      ['rain'],
      ['city'],
      ['tunnel']
    ]) {
      now += 60000;
      feed.sample(tags: tags);
      expect((app.snapshot['story'] as Map)['active'], false);
      expect((app.snapshot['story'] as Map)['available'], false);
      expect((app.snapshot['story'] as Map)['notebookOpen'], false);
    }
  });
  test('legacy experiment intents cannot start or resume over egg care',
      () async {
    final egg = game.eggId;
    for (final name in [
      'storyStart',
      'storyChoose',
      'storyResume',
      'storyReplay',
      'storySave',
      'storyDismiss',
      'storyClose'
    ]) {
      expect(
          await action(name, {
            'topicId': 'coast_sail',
            'instanceId': 'stale',
            'nodeId': 'intro',
            'storyRevision': 1
          }),
          false);
    }
    expect(game.eggId, egg);
    expect(await action('petEgg', {'eggId': egg}), true);
    expect(game.affinityRound!.score, 3);
  });
  test('stale story modal signal cannot block egg care or direct learning',
      () async {
    expect(await action('storyUiBlocked', {'blocked': true}), true);
    expect(app.learning!.active, true);
    expect(await action('petEgg', {'eggId': game.eggId}), true);
    expect(game.affinityRound!.score, 3);
  });
  test('host and Unity lifecycle do not resurrect the experimental story',
      () async {
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    await app.setHostLifecycle(AppLifecycleState.resumed);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect((app.snapshot['story'] as Map)['active'], false);
    expect((app.snapshot['story'] as Map)['notebookOpen'], false);
    expect(await action('navigate', {'view': 'storyStart'}), false);
    expect(app.view, 'cabin');
  });
}
