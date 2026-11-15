import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:allo_phone/scene/window_scene.dart';
import 'package:allo_phone/story/story_director.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class DelayedStoryStore implements StoryStore {
  String? value;
  bool fail = false, failRead = false;
  Completer<void>? gate;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('unavailable');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('disk full');
    this.value = value;
  }
}

class DelayedPreferencesStore extends SharedPreferencesStoryStore {
  DelayedPreferencesStore({required super.prefix});
  Completer<void>? gate;
  @override
  Future<void> write(String value) async {
    if (gate != null) await gate!.future;
    await super.write(value);
  }
}

// Fails the native write while retaining SharedPreferences' real optimistic cache.
class FailingSavedPreferences extends InMemorySharedPreferencesStore {
  FailingSavedPreferences({required this.throws}) : super.empty();
  final bool throws;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.failed-save' &&
        value is String &&
        (jsonDecode(value)['session'] as Map?)?['nodeId'] == 'saved') {
      if (throws) throw StateError('native disk write failed');
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  final packs = StoryPack.decodeList(
      File('assets/data/window_stories_ko.json').readAsStringSync());
  late StoryDirector director;
  late DelayedStoryStore store;
  var request = 0;
  Map<String, dynamic> intent([String? choice]) => {
        'requestId': 'pilot-${request++}',
        'instanceId': director.snapshot['instanceId'],
        'nodeId': director.snapshot['nodeId'],
        'storyRevision': director.snapshot['revision'],
        if (choice != null) 'actionId': choice,
      };
  void ready(StoryDirector d) => d.updateContext(
      scene: const WindowScene(kind: SceneKind.coast),
      nowMs: 0,
      canOffer: false,
      canPlay: true,
      connected: true);
  Future<bool> choose(String choice) =>
      director.handle('storyChoose', intent(choice));
  Future<void> start() async {
    expect(
        await director.handle('storyStart',
            {'requestId': 'start-${request++}', 'topicId': 'coast_sail'}),
        isTrue);
    expect(await choose('next'), isTrue);
    expect(director.snapshot['nodeId'], 'prediction');
  }

  Future<void> complete(String prediction, String first) async {
    expect(await choose(prediction), isTrue);
    expect(await choose(first), isTrue);
    for (final choice in ['compare', 'other', 'discover']) {
      expect(await choose(choice), isTrue);
    }
    expect(director.snapshot['nodeId'], 'discovery');
    expect(await choose('finish'), isFalse,
        reason: 'the explanation is mandatory');
    expect(await choose('why'), isTrue);
    expect(await choose('finish'), isTrue);
    expect(director.snapshot['nodeId'], 'ending');
  }

  setUp(() async {
    store = DelayedStoryStore();
    director = StoryDirector(packs: packs, store: store);
    await director.initialize();
    ready(director);
  });
  tearDown(() => director.dispose());

  for (final throws in [false, true]) {
    test(
        'failed native save (${throws ? 'throw' : 'false'}) cannot restore an uncommitted card',
        () async {
      final previousPlatform = SharedPreferencesStorePlatform.instance;
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance =
          FailingSavedPreferences(throws: throws);
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previousPlatform;
        SharedPreferences.setMockInitialValues({});
      });
      director.dispose();
      director = StoryDirector(
          packs: packs,
          store: SharedPreferencesStoryStore(prefix: 'failed-save'));
      await director.initialize();
      ready(director);
      await start();
      await complete('a', 'b');
      await director.flush();
      expect(await choose('save'), false);
      expect(director.snapshot['cardCount'], 0);
      final restored = StoryDirector(
          packs: packs,
          store: SharedPreferencesStoryStore(prefix: 'failed-save'));
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.snapshot['cardCount'], 0);
      expect(restored.snapshot['nodeId'], 'ending');
    });
  }

  for (final prediction in ['a', 'b']) {
    for (final first in ['a', 'b']) {
      test(
          'personal record matches prediction $prediction and first action $first',
          () async {
        await start();
        await complete(prediction, first);
        expect(await choose('save'), isTrue);
        final card = (director.snapshot['savedCards'] as List).single as Map;
        expect(
            card['prediction'],
            prediction == 'a'
                ? '돛을 펼친 배가 더 멀리 갈 것 같았어.'
                : '돛을 접은 배가 더 멀리 갈 것 같았어.');
        expect(card['firstAction'], first == 'a' ? '돛 펼치기' : '돛 접기');
        expect(card['observation'], '같은 시간 동안 돛을 펼친 배가 더 멀리 갔어.');
        expect(card['principle'], '바람이 펼쳐진 돛을 밀어 배를 움직일 수 있어.');
        expect(card['nextQuestion'], '바람으로 움직이는 다른 물건도 있을까?');
        final restarted = StoryDirector(packs: packs, store: store);
        await restarted.initialize();
        expect(
            restarted.snapshot['savedCards'], director.snapshot['savedCards']);
        restarted.dispose();
      });
    }
  }

  test('failed replay save preserves old personal record until retry succeeds',
      () async {
    await start();
    await complete('a', 'b');
    expect(await choose('save'), isTrue);
    final oldCard = (director.snapshot['savedCards'] as List).single;
    expect(await director.handle('storyReplay', intent()), isTrue);
    expect(director.snapshot['nodeId'], 'prediction');
    await complete('b', 'a');
    await Future<void>.delayed(Duration.zero);
    store.fail = true;
    expect(await choose('save'), isFalse);
    expect((director.snapshot['savedCards'] as List).single, oldCard);
    expect(director.snapshot['prediction'], '돛을 접은 배가 더 멀리 갈 것 같았어.');
    store.fail = false;
    expect(await choose('save'), isTrue);
    expect(director.snapshot['cardCount'], 1);
    expect((director.snapshot['savedCards'] as List).single['prediction'],
        '돛을 접은 배가 더 멀리 갈 것 같았어.');
  });

  test('replacement waits pending save and rejects writes from previous owner',
      () async {
    await start();
    await complete('b', 'a');
    await Future<void>.delayed(Duration.zero);
    store.gate = Completer<void>();
    final saving = choose('save');
    await Future<void>.delayed(Duration.zero);
    final replacement = StoryDirector(packs: packs, store: store);
    var loaded = false;
    final initializing = replacement.initialize().then((_) => loaded = true);
    await Future<void>.delayed(Duration.zero);
    expect(loaded, isFalse);
    expect(await director.handle('storyClose', intent()), isFalse);
    store.gate!.complete();
    await saving;
    await initializing;
    expect(replacement.snapshot['cardCount'], 1);
    expect(replacement.snapshot['nodeId'], 'saved');
    expect(await director.handle('storyClose', intent()), isFalse);
    director.pause();
    await director.flush();
    expect(jsonDecode(store.value!)['session']['nodeId'], 'saved');
    expect((replacement.snapshot['savedCards'] as List).single['firstAction'],
        '돛 펼치기');
    replacement.dispose();
  });

  test('legacy cards stay readable without invented personal evidence',
      () async {
    store.value = jsonEncode({
      'version': 1,
      'cards': ['coast_sail', 'road_seed']
    });
    final restored = StoryDirector(packs: packs, store: store);
    await restored.initialize();
    final cards = restored.snapshot['savedCards'] as List;
    expect(cards, hasLength(2));
    expect(cards.every((card) => !card.containsKey('prediction')), isTrue);
    restored.dispose();
  });

  test('pilot retains other unfinished session until explicit sea start',
      () async {
    final session = {
      'topicId': 'road_seed',
      'packVersion': 1,
      'nodeId': 'compare_a'
    };
    store.value = jsonEncode({
      'version': 1,
      'cards': ['road_seed'],
      'session': session
    });
    director.dispose();
    director = StoryDirector(
        packs: packs, store: store, playableTopics: {'coast_sail'});
    await director.initialize();
    ready(director);
    expect(director.paused, isFalse);
    expect(director.active, isFalse);
    expect(director.snapshot['notice'], contains('미완료'));
    expect(
        await director.handle('storyStart',
            {'requestId': 'blocked-other', 'topicId': 'road_seed'}),
        isFalse);
    director.pause();
    await director.flush();
    expect(jsonDecode(store.value!)['session'], session);
    expect(await director.handle('storyDismiss', intent()), isTrue);
    await director.flush();
    expect(jsonDecode(store.value!)['session'], session);
    await start();
    await director.flush();
    expect(jsonDecode(store.value!)['session']['topicId'], 'coast_sail');
    expect(director.snapshot['cardCount'], 1);
  });

  test('prediction and observations survive each pause and restart boundary',
      () async {
    await start();
    final choices = ['b', 'a', 'compare', 'other', 'discover', 'why', 'finish'];
    for (final choice in choices) {
      expect(await choose(choice), isTrue);
      director.pause();
      await director.flush();
      final previous = director.snapshot;
      director.dispose();
      director = StoryDirector(packs: packs, store: store);
      await director.initialize();
      ready(director);
      expect(director.paused, isTrue);
      expect(director.snapshot['nodeId'], previous['nodeId']);
      expect(director.snapshot['prediction'], '돛을 접은 배가 더 멀리 갈 것 같았어.');
      expect(director.snapshot['firstAction'], previous['firstAction']);
      expect(await director.handle('storyResume', intent()), isTrue);
    }
    expect(await choose('save'), isTrue);
    expect(director.snapshot['cardCount'], 1);
  });

  test('pack mismatch resets unfinished evidence and preserves saved card',
      () async {
    store.value = jsonEncode({
      'version': 1,
      'cards': ['coast_sail'],
      'records': {
        'coast_sail': {'prediction': '이전 예상'}
      },
      'session': {
        'topicId': 'coast_sail',
        'packVersion': 1,
        'nodeId': 'ending',
        'evidence': {'prediction': '버릴 예상'}
      }
    });
    director.dispose();
    director = StoryDirector(packs: packs, store: store);
    await director.initialize();
    ready(director);
    expect(director.paused, isTrue);
    expect(director.snapshot['nodeId'], 'intro');
    expect(director.snapshot.containsKey('prediction'), isFalse);
    expect((director.snapshot['savedCards'] as List).single['prediction'],
        '이전 예상');
    expect(await director.handle('storyResume', intent()), isTrue);
    expect(await choose('next'), isTrue);
    expect(director.snapshot['nodeId'], 'prediction');
  });

  test('stale and duplicate prediction actions cannot choose first action',
      () async {
    await start();
    final stale = intent('b');
    expect(await director.handle('storyChoose', stale), isTrue);
    expect(await director.handle('storyChoose', stale), isFalse);
    expect(
        await director
            .handle('storyChoose', {...stale, 'requestId': 'stale-copy'}),
        isFalse);
    expect(director.snapshot['nodeId'], 'choose');
    expect(director.snapshot.containsKey('firstAction'), isFalse);
    expect(director.snapshot['prediction'], '돛을 접은 배가 더 멀리 갈 것 같았어.');
  });

  test('ending replay choice clears previous live evidence', () async {
    await start();
    await complete('b', 'a');
    expect(await choose('replay'), isTrue);
    expect(director.snapshot['nodeId'], 'prediction');
    expect(director.snapshot.containsKey('prediction'), isFalse);
    expect(director.snapshot.containsKey('firstAction'), isFalse);
    expect(await director.handle('storySave', intent()), isFalse);
  });

  test(
      'distinct SharedPreferences stores with same key share ownership barrier',
      () async {
    SharedPreferences.setMockInitialValues({});
    final first = DelayedPreferencesStore(prefix: 'test.pilot.owner');
    director.dispose();
    director = StoryDirector(packs: packs, store: first);
    await director.initialize();
    ready(director);
    await start();
    await complete('a', 'b');
    await director.flush();
    first.gate = Completer<void>();
    final save = choose('save');
    await Future<void>.delayed(Duration.zero);
    final replacement = StoryDirector(
        packs: packs,
        store: SharedPreferencesStoryStore(prefix: 'test.pilot.owner'));
    var loaded = false;
    final loading = replacement.initialize().then((_) => loaded = true);
    await Future<void>.delayed(Duration.zero);
    expect(loaded, isFalse);
    director.dispose();
    first.gate!.complete();
    await save;
    await loading;
    expect(replacement.snapshot['cardCount'], 1);
    expect((replacement.snapshot['savedCards'] as List).single['firstAction'],
        '돛 접기');
    ready(replacement);
    // The new owner can persist without reverting the completed card.
    replacement.pause();
    await replacement.flush();
    expect(
        jsonDecode(
            (await SharedPreferencesStoryStore(prefix: 'test.pilot.owner')
                .read())!)['cards'],
        ['coast_sail']);
    replacement.dispose();
    director = StoryDirector(packs: packs, store: store);
  });

  test('malformed load blocks direct writes until a successful initialization',
      () async {
    director.dispose();
    store.value = '{"version":1,"cards":"broken"}';
    final raw = store.value;
    director = StoryDirector(packs: packs, store: store);
    await expectLater(director.initialize(), throwsFormatException);
    ready(director);
    expect(
        await director.handle('storyStart',
            {'requestId': 'corrupt-start', 'topicId': 'coast_sail'}),
        false);
    director.pause();
    await director.flush();
    expect(store.value, raw);
    store.value = null;
    await director.initialize();
    ready(director);
    await start();
  });

  test('storage read error is retryable without replacing owner', () async {
    store.failRead = true;
    await expectLater(director.initialize(), throwsStateError);
    expect(director.snapshot['notice'], isNotEmpty);
    store.failRead = false;
    await director.initialize();
    expect(director.snapshot['notice'], isEmpty);
    await start();
    expect(director.snapshot['nodeId'], 'prediction');
  });
  test('previous controller input cannot advance a new run with same clock',
      () async {
    expect(
        await director.handle('storyStart',
            {'requestId': 'first-owner-start', 'topicId': 'coast_sail'}),
        isTrue);
    final previousInput = intent('next');
    expect(await director.handle('storyClose', intent()), isTrue);
    await director.flush();
    director.dispose();
    director = StoryDirector(packs: packs, store: store);
    await director.initialize();
    ready(director);
    expect(
        await director.handle('storyStart',
            {'requestId': 'second-owner-start', 'topicId': 'coast_sail'}),
        isTrue);
    expect(await director.handle('storyChoose', previousInput), isFalse);
    expect(director.snapshot['nodeId'], 'intro');
  });
}
