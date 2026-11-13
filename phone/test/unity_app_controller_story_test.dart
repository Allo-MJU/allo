import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
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

  Map<String, dynamic> story() =>
      Map<String, dynamic>.from(app.snapshot['story'] as Map);
  Map<String, dynamic> token() => {
        'instanceId': story()['instanceId'],
        'nodeId': story()['nodeId'],
        'storyRevision': story()['revision'],
      };
  Future<bool> action(String name,
          [Map<String, dynamic> fields = const {}, String? id]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': id ?? 'story-test-${request++}',
        'action': name,
        ...fields,
      }));
  Future<void> startStory() async {
    expect(await action('storyStart', {'topicId': 'coast_sail'}), isTrue);
    expect(story()['active'], isTrue);
    expect(story()['paused'], isFalse);
  }

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

  test('distance-based care allows stories until its distance safety margin',
      () async {
    feed.sample(eta: null);
    await game.startIncubating(EggTier.large, useAffinity: true);
    feed.sample(eta: null);
    expect(game.affinityRound!.deadlineMs, isNull);
    expect(story()['canPlay'], isTrue);
    await startStory();
    final target = game.game.hatchAtM!;
    feed.sample(eta: null, distance: target - 400);
    expect(story()['paused'], isTrue);
    expect(story()['canPlay'], isFalse);
  });

  test('story actions are not accepted as navigation destinations', () async {
    expect(await action('navigate', {'view': 'storyStart'}), isFalse);
    expect(app.snapshot['view'], 'cabin');
  });

  test('story selection is local and vehicle refresh does not rewind its node',
      () async {
    await startStory();
    final state = story();
    final choice = (state['choices'] as List).first as Map;
    expect(await action('storyChoose', {...token(), 'actionId': choice['id']}),
        isTrue);
    expect(story()['nodeId'], isNot(state['nodeId']));
    final progressed = story();
    expect(app.snapshot['busy'], isFalse);
    feed.sample(tags: ['coast'], distance: 17);
    expect(story()['nodeId'], progressed['nodeId']);
    expect(story()['revision'], progressed['revision']);
  });

  test('old node and duplicate request cannot advance the story twice',
      () async {
    await startStory();
    final choice = (story()['choices'] as List).first as Map;
    final old = {...token(), 'actionId': choice['id']};
    expect(await action('storyChoose', old, 'one-choice'), isTrue);
    final after = story();
    expect(await action('storyChoose', old, 'one-choice'), isFalse);
    expect(await action('storyChoose', old, 'old-node-new-request'), isFalse);
    expect(story()['nodeId'], after['nodeId']);
    expect(story()['revision'], after['revision']);
  });

  test('story blocks legacy world inputs and starting an egg', () async {
    await startStory();
    final materials = jsonEncode(app.snapshot['materials']);
    final lookout = game.lookOutCount;
    for (final message in [
      {'type': 'lookTogether'},
      {'type': 'spotted', 'id': 'bird'},
      {'type': 'tap', 'kind': 'pet'},
      {'type': 'feed', 'kind': 'apple'},
      {'type': 'drink'},
    ]) {
      expect(await app.handleMessage(jsonEncode(message)), isFalse);
    }
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    expect(game.lookOutCount, lookout);
    expect(jsonEncode(app.snapshot['materials']), materials);
  });

  test('navigation pauses and explicit resume retains the current node',
      () async {
    await startStory();
    final node = story()['nodeId'];
    expect(await action('navigate', {'view': 'camp'}), isTrue);
    expect(story()['paused'], isTrue);
    expect(await action('storyResume', token()), isFalse);
    await action('navigate', {'view': 'cabin'});
    expect(story()['paused'], isTrue);
    expect(await action('storyResume', token()), isTrue);
    expect(story()['nodeId'], node);
  });

  test('open care drawer blocks start and yields an already running story',
      () async {
    await action('storyUiBlocked', {'blocked': true});
    expect(await action('storyStart', {'topicId': 'coast_sail'}), isFalse);
    await action('storyUiBlocked', {'blocked': false});
    await startStory();
    await action('storyUiBlocked', {'blocked': true});
    expect(story()['paused'], isTrue);
    expect(await action('storyResume', token()), isFalse);
    expect(app.snapshot['busy'], isFalse);
  });

  test(
      'foreground Unity can play while its invisible Flutter activity is paused',
      () async {
    await app.handleMessage('{"type":"ready"}');
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(story()['canPlay'], isTrue);
    await startStory();
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    expect(story()['paused'], isTrue);
    expect(story()['canPlay'], isFalse);
  });

  test('host background pauses story without auto-resuming on return',
      () async {
    await startStory();
    await app.setHostLifecycle(AppLifecycleState.paused);
    expect(story()['paused'], isTrue);
    expect(await action('storyResume', token()), isFalse);
    await app.setHostLifecycle(AppLifecycleState.resumed);
    expect(story()['paused'], isTrue);
    expect(await action('storyResume', token()), isTrue);
  });

  test('native speech input blocks starting a story until capture returns',
      () async {
    await game.startIncubating(EggTier.small, useAffinity: true);
    feed.sample(tags: ['coast']);
    final gate = Completer<String?>();
    app.dispose();
    app = UnityAppController(
      game: game,
      camp: camp,
      speechInput: () => gate.future,
    );
    expect(await app.initialize(), isTrue);
    await action('navigate', {'view': 'cabin'});
    final capture = action('speech', {'eggId': game.eggId});
    await Future<void>.delayed(Duration.zero);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), isFalse);
    gate.complete(null);
    await capture;
    expect(app.snapshot['busy'], isFalse);
  });

  test('photo checkpoint yields story and rejects further choices', () async {
    await game.startIncubating(EggTier.small, useAffinity: true);
    feed.sample(tags: ['coast']);
    await startStory();
    for (var i = 0; i < 17; i++) {
      await game.petEgg();
      if (i < 16) {
        now += 10000;
        feed.sample(tags: ['coast']);
      }
    }
    expect(game.affinityRound!.phase, AffinityPhase.photoRequired);
    expect(story()['paused'], isTrue);
    expect(story()['canPlay'], isFalse);
    expect(await action('storyResume', token()), isFalse);
    expect((app.snapshot['egg'] as Map)['photoRequired'], isTrue);
  });
}
