import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:allo_phone/story/story_director.dart';
import 'package:allo_phone/scene/window_scene.dart';

class MemoryStore implements StoryStore {
  String? value;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('disk full');
    value = next;
  }
}

void main() {
  final packs = StoryPack.decodeList(
      File('assets/data/window_stories_ko.json').readAsStringSync());
  late StoryDirector d;
  late MemoryStore store;
  int serial = 0;
  Map<String, dynamic> intent([String? choice]) => {
        'requestId': 'test-${serial++}',
        'instanceId': d.snapshot['instanceId'],
        'nodeId': d.snapshot['nodeId'],
        'storyRevision': d.snapshot['revision'],
        if (choice != null) 'actionId': choice,
      };
  Future<bool> choose(String id) => d.handle('storyChoose', intent(id));
  void context(WindowScene scene,
          {int now = 0,
          bool play = true,
          bool offer = true,
          bool connected = true}) =>
      d.updateContext(
          scene: scene,
          nowMs: now,
          canOffer: offer,
          canPlay: play,
          connected: connected);
  Future<void> start([String topic = 'coast_sail']) async {
    expect(
        await d.handle(
            'storyStart', {'requestId': 'start-${serial++}', 'topicId': topic}),
        isTrue);
  }

  Future<void> ending({String first = 'a'}) async {
    for (final id in [
      'next',
      first,
      'compare',
      'other',
      'discover',
      'finish'
    ]) {
      expect(await choose(id), isTrue);
    }
    expect(d.snapshot['nodeId'], 'ending');
  }

  setUp(() async {
    store = MemoryStore();
    d = StoryDirector(packs: packs, store: store);
    await d.initialize();
    context(const WindowScene(kind: SceneKind.coast));
  });
  tearDown(() => d.dispose());

  test('all eight packs have both executable branches and explanatory path',
      () async {
    expect(packs, hasLength(8));
    for (final pack in packs) {
      for (final first in ['a', 'b']) {
        await start(pack.id);
        for (final id in [
          'next',
          first,
          'compare',
          'other',
          'discover',
          'why',
          'finish'
        ]) {
          expect(await choose(id), isTrue, reason: '${pack.id}: $id');
        }
        expect(d.snapshot['nodeId'], 'ending');
        expect(await choose('save'), isTrue);
        expect(await choose('more'), isTrue);
        expect(await choose('close'), isTrue);
      }
    }
    expect(d.snapshot['cardCount'], 8);
  });

  test('new night overrides existing rain without restarting active stories',
      () async {
    context(const WindowScene(kind: SceneKind.coast, rainLevel: 1), now: 10000);
    context(const WindowScene(kind: SceneKind.coast, rainLevel: 1), now: 15000);
    expect(d.snapshot['topicId'], 'rain_path');
    context(const WindowScene(kind: SceneKind.coast, rainLevel: 1, night: true),
        now: 20000);
    context(const WindowScene(kind: SceneKind.coast, rainLevel: 1, night: true),
        now: 25000);
    expect(d.snapshot['topicId'], 'night_stars');
    await start();
    final before = d.snapshot;
    context(const WindowScene(kind: SceneKind.tunnel), now: 30000);
    expect(d.snapshot['revision'], before['revision']);
    expect(d.snapshot['topicId'], 'coast_sail');
  });

  test('speed and rain intensity do not restart an active node', () async {
    await start();
    await choose('next');
    await choose('b');
    final before = d.snapshot;
    context(
        const WindowScene(kind: SceneKind.coast, speedKph: 75, rainLevel: 1),
        now: 1000);
    context(
        const WindowScene(kind: SceneKind.coast, speedKph: 90, rainLevel: 2),
        now: 2000);
    expect(d.snapshot['nodeId'], before['nodeId']);
    expect(d.snapshot['instanceId'], before['instanceId']);
    expect(d.snapshot['revision'], before['revision']);
  });
  test('stale node and duplicate input never advance twice', () async {
    await start();
    final request = intent('next');
    expect(await d.handle('storyChoose', request), isTrue);
    expect(await d.handle('storyChoose', request), isFalse);
    expect(
        await d.handle('storyChoose', {...request, 'requestId': 'different'}),
        isFalse);
    expect(d.snapshot['nodeId'], 'choose');
  });
  test('care preemption pauses and rejects already-issued choice', () async {
    await start();
    final request = intent('next');
    context(const WindowScene(kind: SceneKind.tunnel), play: false, now: 1000);
    expect(d.paused, isTrue);
    expect(await d.handle('storyChoose', request), isFalse);
    context(const WindowScene(kind: SceneKind.city), now: 2000);
    expect(d.paused, isTrue);
    expect(await d.handle('storyResume', intent()), isTrue);
    expect(d.snapshot['topicId'], 'coast_sail');
  });
  test('save failure leaves ending and retry saves exactly one card', () async {
    await start();
    await ending();
    await Future<void>.delayed(Duration.zero);
    store.fail = true;
    expect(await choose('save'), isFalse);
    expect(d.snapshot['cardCount'], 0);
    expect(d.snapshot['nodeId'], 'ending');
    store.fail = false;
    expect(await choose('save'), isTrue);
    expect(d.snapshot['cardCount'], 1);
    expect(await d.handle('storyReplay', intent()), isTrue);
    for (final id in ['b', 'compare', 'other', 'discover', 'finish', 'save']) {
      expect(await choose(id), isTrue);
    }
    expect(d.snapshot['cardCount'], 1);
  });
  test('saved progress restores paused and cards survive restart', () async {
    await start();
    await ending();
    await choose('save');
    final restored = StoryDirector(packs: packs, store: store);
    await restored.initialize();
    expect(restored.paused, isTrue);
    expect(restored.snapshot['nodeId'], 'saved');
    expect(restored.snapshot['cardCount'], 1);
    restored.dispose();
  });
  test('pause while save is pending preserves committed card', () async {
    await start();
    await ending();
    await Future<void>.delayed(Duration.zero);
    store.gate = Completer<void>();
    final save = choose('save');
    await Future<void>.delayed(Duration.zero);
    final pauseIntent = intent();
    expect(await d.handle('storyPause', {...pauseIntent, 'storyRevision': -1}),
        isFalse);
    expect(await d.handle('storyPause', pauseIntent), isTrue);
    expect(d.pending, isTrue);
    expect(await d.handle('storyPause', pauseIntent), isFalse);
    expect(await d.handle('storyResume', intent()), isFalse);
    store.gate!.complete();
    expect(await save, isTrue);
    await Future<void>.delayed(Duration.zero);
    final restored = StoryDirector(packs: packs, store: store);
    await restored.initialize();
    expect(d.paused, isTrue);
    expect(restored.snapshot['cardCount'], 1);
    restored.dispose();
  });
  test('offline hides environment invitation but allows explicit local stories',
      () async {
    context(const WindowScene(kind: SceneKind.road), connected: false);
    expect(d.snapshot['available'], isFalse);
    await start('night_stars');
    expect(d.snapshot['notice'], contains('상상 탐험'));
  });
  test('new region cannot show another automatic invitation within 90 seconds',
      () {
    expect(d.snapshot['available'], isTrue);
    context(const WindowScene(kind: SceneKind.city), now: 10000);
    expect(d.snapshot['available'], isFalse);
    context(const WindowScene(kind: SceneKind.city), now: 90000);
    expect(d.snapshot['available'], isTrue);
    expect(d.snapshot['topicId'], 'city_bridge');
  });
  test('dismiss suppresses invitations for three minutes', () async {
    expect(await d.handle('storyDismiss', intent()), isTrue);
    context(const WindowScene(kind: SceneKind.mountain), now: 179999);
    expect(d.snapshot['available'], isFalse);
    context(const WindowScene(kind: SceneKind.mountain), now: 180000);
    expect(d.snapshot['available'], isTrue);
  });
  test(
      'tunnel candidate expires immediately on exit; weather waits five seconds',
      () {
    context(const WindowScene(kind: SceneKind.tunnel), now: 90000);
    expect(d.snapshot['topicId'], 'tunnel_shadow');
    context(const WindowScene(kind: SceneKind.coast, rainLevel: 1),
        now: 100000);
    expect(d.snapshot['topicId'], 'coast_sail');
    context(const WindowScene(kind: SceneKind.coast, rainLevel: 1),
        now: 104999);
    expect(d.snapshot['topicId'], 'coast_sail');
    context(const WindowScene(kind: SceneKind.coast, rainLevel: 1),
        now: 105000);
    expect(d.snapshot['topicId'], 'rain_path');
  });
}
