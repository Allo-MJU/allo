import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/story/story_director.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'affinity_controller_test.dart' show DemoApi;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;

class _MemoryStoryStore implements StoryStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class _FailOnceStory extends StoryDirector {
  _FailOnceStory({required super.packs, required super.store})
      : super(playableTopics: const {'coast_sail'});
  var first = true;
  @override
  Future<void> initialize() async {
    if (first) {
      first = false;
      throw StateError('temporary read failure');
    }
    await super.initialize();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late BaseCampController camp;
  late UnityAppController app;
  late RoundFeed feed;
  var serial = 0;
  var now = 0;

  Map<String, dynamic> story() => app.snapshot['story'] as Map<String, dynamic>;
  Future<bool> action(String name, [Map<String, dynamic> fields = const {}]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'pilot-${serial++}',
        'action': name,
        if (name.startsWith('story'))
          'storyPresentationRevision': story()['presentationRevision'],
        ...fields,
      }));
  Future<bool> choose(String id) => action('storyChoose', {
        'instanceId': story()['instanceId'],
        'nodeId': story()['nodeId'],
        'storyRevision': story()['revision'],
        'actionId': id,
      });
  Future<void> start() async {
    expect(await action('storyNotebook', {'open': true}), true);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    serial = now = 0;
    feed = RoundFeed();
    camp = BaseCampController(store: CampMemory());
    game = GameController(
        feed: feed,
        dex: DexStore(),
        baseCamp: camp,
        eggApi: DemoApi(),
        monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    expect(await app.initialize(), true);
    await game.pair(sessionA, pairCode: '123456');
    feed.sample(tags: ['coast']);
    await action('navigate', {'view': 'cabin'});
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });

  test('only explicit notebook entry enables a sea experiment', () async {
    expect(story()['ready'], true);
    expect(story()['notebookOpen'], false);
    expect(story()['active'], false);
    expect(story()['available'], false);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), false);
    expect(await action('storyNotebook', {'open': true}), true);
    expect(story()['notebookOpen'], true);
    expect(app.learning!.active, false);
    expect(await action('storyStart', {'topicId': 'road_seed'}), false);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
    expect(story()['notebookOpen'], false);
    expect(story()['active'], true);
    expect(story()['available'], false);
  });

  for (final prediction in ['a', 'b']) {
    for (final first in ['a', 'b']) {
      test(
          'Unity round trip saves prediction $prediction and first action $first',
          () async {
        final sent = <Map<String, dynamic>>[];
        app.attach((m) => sent.add(jsonDecode(m) as Map<String, dynamic>));
        await app.handleMessage('{"type":"ready"}');
        await start();
        for (final id in [
          'next',
          prediction,
          first,
          'compare',
          'other',
          'discover',
          'why',
          'finish',
          'save'
        ]) {
          expect(await choose(id), true, reason: '${story()['nodeId']}: $id');
        }
        expect(story()['cardCount'], 1);
        final card = (story()['savedCards'] as List).single as Map;
        expect(card['prediction'], contains(prediction == 'a' ? '펼친' : '접은'));
        expect(card['firstAction'], contains(first == 'a' ? '펼치' : '접기'));
        expect(card['observation'], contains('더 멀리'));
        expect(card['principle'], contains('바람'));
        final published =
            sent.lastWhere((m) => m['type'] == 'app')['story'] as Map;
        expect(published['savedCards'], story()['savedCards']);
        expect(published['ackAccepted'], true);
        expect(game.affinityRound!.score, 0);
      });
    }
  }

  test('background pauses the experiment and return needs manual resume',
      () async {
    await start();
    expect(await choose('next'), true);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    await app.setHostLifecycle(AppLifecycleState.paused);
    expect(story()['paused'], true);
    expect(story()['notebookOpen'], false);
    expect(story()['canOpen'], false);
    await app.setHostLifecycle(AppLifecycleState.resumed);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(story()['paused'], true);
    expect(
        await action('storyResume', {
          'instanceId': story()['instanceId'],
          'nodeId': story()['nodeId'],
          'storyRevision': story()['revision'],
        }),
        false);
    expect(await action('storyNotebook', {'open': true}), true);
    expect(
        await action('storyResume', {
          'instanceId': story()['instanceId'],
          'nodeId': story()['nodeId'],
          'storyRevision': story()['revision'],
        }),
        true);
    expect(story()['nodeId'], 'prediction');
  });

  test('foreground native Unity can open while Flutter host is paused',
      () async {
    await app.setHostLifecycle(AppLifecycleState.paused);
    expect(story()['canOpen'], true);
    await start();
    expect(await choose('next'), true);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    expect(story()['canOpen'], false);
    expect(story()['paused'], true);
    expect(story()['notebookOpen'], false);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(story()['paused'], true);
    expect(story()['canOpen'], true);
    await app.setHostLifecycle(AppLifecycleState.detached);
    expect(story()['canOpen'], false);
  });

  test('old notebook close cannot pause the newly opened experiment', () async {
    expect(await action('storyNotebook', {'open': true}), true);
    final oldPresentation = story()['presentationRevision'];
    expect(await action('storyNotebook', {'open': false}), true);
    await start();
    expect(
        await action('storyNotebook', {
          'open': false,
          'storyPresentationRevision': oldPresentation,
        }),
        false);
    expect(story()['active'], true);
    expect(await action('storyNotebook', {'open': false}), true);
    expect(story()['paused'], true);
  });

  test('old start cannot run after the notebook was closed and reopened',
      () async {
    expect(await action('storyNotebook', {'open': true}), true);
    final oldPresentation = story()['presentationRevision'];
    expect(await action('storyNotebook', {'open': false}), true);
    expect(await action('storyNotebook', {'open': true}), true);
    expect(
        await action('storyStart', {
          'topicId': 'coast_sail',
          'storyPresentationRevision': oldPresentation,
        }),
        false);
    expect(story()['active'], false);
    expect(story()['notebookOpen'], true);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
  });

  test(
      'vehicle ticks preserve presentation token but capture loss invalidates it',
      () async {
    expect(await action('storyNotebook', {'open': true}), true);
    final presentation = story()['presentationRevision'];
    feed.sample(tags: ['coast']);
    expect(story()['presentationRevision'], presentation);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    expect(story()['presentationRevision'], isNot(presentation));
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(
        await action('storyStart', {
          'topicId': 'coast_sail',
          'storyPresentationRevision': presentation,
        }),
        false);
  });

  test('notebook captures egg inputs and closes on navigation', () async {
    final egg = game.eggId;
    expect(await action('storyNotebook', {'open': true}), true);
    expect(await action('petEgg', {'eggId': egg}), false);
    expect(await app.handleMessage('{"type":"tap","kind":"pet"}'), false);
    expect(game.affinityRound!.score, 0);
    expect(await action('navigate', {'view': 'home'}), true);
    expect(story()['notebookOpen'], false);
    expect(await action('storyNotebook', {'open': true}), false);
    await action('navigate', {'view': 'cabin'});
    expect(await action('petEgg', {'eggId': egg}), true);
    expect(game.affinityRound!.score, 3);
  });

  test('native speech in flight prevents notebook opening', () async {
    final input = Completer<String?>();
    app.dispose();
    app = UnityAppController(
        game: game, camp: camp, speechInput: () => input.future);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    final capture = action('speech', {'eggId': game.eggId});
    await Future<void>.delayed(Duration.zero);
    expect(story()['canOpen'], false);
    expect(await action('storyNotebook', {'open': true}), false);
    input.complete(null);
    await capture;
    expect(story()['canOpen'], true);
  });

  test('ended session closes presentation without deleting progress', () async {
    await start();
    await choose('next');
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'car'});
    await Future<void>.delayed(Duration.zero);
    expect(game.sessionEnded, true);
    expect(story()['paused'], true);
    expect(story()['notebookOpen'], false);
    expect(story()['canOpen'], false);
    expect(await action('storyNotebook', {'open': true}), false);
    expect(story()['nodeId'], 'prediction');
  });

  test('photo-required pauses pilot and returns input to egg care', () async {
    await start();
    await choose('next');
    for (var i = 0; i < 17; i++) {
      await game.petEgg();
      now += 10000;
      feed.sample();
    }
    expect(game.affinityRound!.phase, AffinityPhase.photoRequired);
    expect(story()['paused'], true);
    expect(story()['canOpen'], false);
    expect(story()['notebookOpen'], false);
    expect(await action('storyNotebook', {'open': true}), false);
  });

  test('malformed v1 save shows retry and preserves raw data until repaired',
      () async {
    app.dispose();
    const malformed = '{"version":1,"cards":["coast_sail"],"session":4}';
    final store = _MemoryStoryStore()..value = malformed;
    final director = StoryDirector(
        packs: StoryPack.decodeList(
            await rootBundle.loadString('assets/data/window_stories_ko.json')),
        store: store,
        playableTopics: const {'coast_sail'});
    app = UnityAppController(game: game, camp: camp, story: director);
    expect(await app.initialize(), true);
    await action('navigate', {'view': 'cabin'});
    expect(story()['ready'], false);
    expect(story()['error'], isNotEmpty);
    expect(story()['cardCount'], 0,
        reason: 'a failed load installs no partial cards');
    expect(await action('storyNotebook', {'open': true}), true);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), false);
    expect(await action('storyRetry'), false);
    await director.flush();
    expect(store.value, malformed);
    store.value = '{"version":1,"cards":["coast_sail"]}';
    expect(await action('storyRetry'), true);
    expect(story()['ready'], true);
    expect(story()['cardCount'], 1);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
  });

  test('story initialization can fail and retry without disabling the app',
      () async {
    app.dispose();
    final director = _FailOnceStory(
        packs: StoryPack.decodeList(
            await rootBundle.loadString('assets/data/window_stories_ko.json')),
        store: _MemoryStoryStore());
    app = UnityAppController(game: game, camp: camp, story: director);
    expect(await app.initialize(), true);
    await action('navigate', {'view': 'cabin'});
    expect(story()['ready'], false);
    expect(story()['error'], isNotEmpty);
    expect(story()['canOpen'], true);
    expect(await action('petEgg', {'eggId': game.eggId}), true);
    expect(await action('storyNotebook', {'open': true}), true);
    expect(await action('storyRetry'), true);
    expect(story()['ready'], true);
    expect(story()['error'], '');
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
  });
}
