import 'dart:async';
import 'package:allo_phone/learning/companion_learning_controller.dart';
import 'package:allo_phone/learning/learning_catalog.dart';
import 'package:allo_phone/learning/learning_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLearningStore implements LearningStore {
  final data = <String, Map<String, dynamic>>{};
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read(String profile, String id) async =>
      data['$profile/$id'];
  @override
  Future<void> write(
      String profile, String id, Map<String, dynamic> value) async {
    if (fail) throw StateError('disk');
    data['$profile/$id'] = Map.of(value);
  }
}

LearningCatalog catalog({int version = 1, String first = 'seed'}) =>
    LearningCatalog.fromJson({
      'schemaVersion': 1,
      'stories': [
        {
          'speciesId': 'road_sprout',
          'storyId': 'garden',
          'version': version,
          'name': '길싹이',
          'firstSceneId': first,
          'migrations': <String, String>{},
          'scenes': [
            {
              'id': first,
              'title': '씨앗',
              'text': '작은 씨앗을 찾았어.',
              'nextSceneId': 'water'
            },
            {
              'id': 'water',
              'title': '물',
              'text': '씨앗에 물을 주었어.',
              'nextSceneId': null
            }
          ]
        }
      ]
    });
const owned = [
  LearningCreature(id: 'one', speciesId: 'road_sprout', name: '길싹이'),
  LearningCreature(id: 'two', speciesId: 'road_sprout', name: '길싹이'),
  LearningCreature(id: 'other', speciesId: 'mistfin', name: '바다안개'),
];
Map<String, dynamic> reply(Map<String, dynamic> request,
        {bool parent = false}) =>
    {
      for (final key in [
        'requestId',
        'creatureId',
        'speciesId',
        'storyId',
        'version',
        'sceneId'
      ])
        key: request[key],
      'text': '물은 씨앗이 자라는 데 필요해.',
      'parentPromptUsed': parent,
    };
void main() {
  late MemoryLearningStore store;
  late CompanionLearningController controller;
  late List<String> spoken;
  late List<Map<String, dynamic>> requests;
  setUp(() {
    store = MemoryLearningStore();
    spoken = [];
    requests = [];
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        request: (r) async {
          requests.add(r);
          return reply(r);
        },
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
  });
  tearDown(() => controller.dispose());
  test('egg and unowned targets never speak or request AI', () async {
    expect(await controller.chat('hi', requestId: 'r'), false);
    expect(await controller.repeat(), false);
    expect(await controller.next(), false);
    expect(await controller.select('unowned'), false);
    expect(spoken, isEmpty);
    expect(requests, isEmpty);
    expect(controller.snapshot['creatureId'], '');
  });
  test('explicit next only; same species ownership and real/demo separated',
      () async {
    await controller.select('one');
    await controller.chat('어떻게 자라?', requestId: 'a');
    await controller.repeat();
    expect(controller.snapshot['sceneId'], 'seed');
    expect(await controller.next(), true);
    expect(controller.snapshot['sceneId'], 'water');
    expect(await controller.next(), false);
    await controller.select('two');
    expect(controller.snapshot['sceneId'], 'seed');
    await controller.select('one');
    expect(controller.snapshot['sceneId'], 'water');
    controller.setContext(profile: 'demo', creatures: owned, active: true);
    await controller.select('one');
    expect(controller.snapshot['sceneId'], 'seed');
    expect(store.data.keys, containsAll(['real/one', 'real/two', 'demo/one']));
    expect(store.data.toString(), isNot(contains('어떻게 자라')));
  });
  test('save failure leaves confirmed scene unchanged', () async {
    await controller.select('one');
    store.fail = true;
    expect(await controller.next(), false);
    expect(controller.snapshot['sceneId'], 'seed');
    expect(controller.snapshot['error'], isNotEmpty);
  });
  test('wrong context returns honest authored fallback without progress',
      () async {
    controller.dispose();
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        request: (r) async => {...reply(r), 'sceneId': 'wrong'},
        speak: (s) async {},
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
    await controller.select('one');
    expect(await controller.chat('질문', requestId: 'x'), false);
    expect(controller.snapshot['source'], 'fallback');
    expect(controller.snapshot['text'], '작은 씨앗을 찾았어.');
    expect(controller.snapshot['sceneId'], 'seed');
    expect(controller.history, isEmpty);
  });
  test('late responses dropped after selection, suspension and profile switch',
      () async {
    for (final change in ['selection', 'suspend', 'profile']) {
      final gate = Completer<Map<String, dynamic>>();
      late Map<String, dynamic> sent;
      controller.dispose();
      controller = CompanionLearningController(
          catalog: catalog(),
          store: store,
          request: (r) {
            sent = r;
            return gate.future;
          },
          speak: (s) async {
            spoken.add(s);
          },
          stop: () async {});
      controller.setContext(profile: 'real', creatures: owned, active: true);
      await controller.select('one');
      final pending = controller.chat('질문', requestId: change);
      await Future<void>.delayed(Duration.zero);
      if (change == 'selection') await controller.select('two');
      if (change == 'suspend') controller.setActive(false);
      if (change == 'profile') {
        controller.setContext(profile: 'demo', creatures: owned, active: true);
      }
      final before = spoken.length;
      gate.complete(reply(sent));
      expect(await pending, false);
      expect(spoken.length, before);
      expect(controller.history, isEmpty);
      expect(controller.snapshot['busy'], false);
    }
  });
  test('six exchange history and duplicate completed request guard', () async {
    await controller.select('one');
    for (var i = 0; i < 8; i++) {
      expect(await controller.chat('질문 $i', requestId: 'q$i'), true);
    }
    expect(controller.history, hasLength(12));
    expect(controller.history.first['text'], '질문 2');
    expect(await controller.chat('질문 7', requestId: 'q7'), false);
    expect(requests.last['history'], hasLength(12));
    expect(store.data.toString(), isNot(contains('질문')));
  });
  test('parent suggestion suppressed through next ten normal replies',
      () async {
    controller.dispose();
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        request: (r) async {
          requests.add(r);
          return reply(r, parent: r['allowParentPrompt'] == true);
        },
        speak: (s) async {},
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
    await controller.select('one');
    for (var i = 0; i < 12; i++) {
      await controller.chat('질문', requestId: 'p$i');
    }
    expect(requests[0]['allowParentPrompt'], true);
    expect(requests.sublist(1, 11).map((r) => r['allowParentPrompt']),
        everyElement(false));
    expect(requests[11]['allowParentPrompt'], true);
  });
  test('different story ID never silently reuses a scene from old content',
      () async {
    await controller.select('one');
    await controller.next();
    store.data['real/one']!['storyId'] = 'retired_story';
    await controller.select('one');
    expect(controller.snapshot['sceneId'], 'seed');
    expect(controller.snapshot['error'], isNotEmpty);
    expect(store.data['real/one']!['storyId'], 'retired_story');
    expect(await controller.repeat(), true);
    expect(store.data['real/one']!['storyId'], 'garden');
  });

  test('unknown species has no invented story', () async {
    expect(await controller.select('other'), true);
    expect(controller.snapshot['available'], false);
    expect(await controller.chat('hi', requestId: 'n'), false);
    expect(spoken, isEmpty);
  });
  test(
      'version preserves valid scene; missing scene waits for explicit restart',
      () async {
    await controller.select('one');
    await controller.next();
    controller.replaceCatalog(catalog(version: 2));
    await controller.select('one');
    expect(controller.snapshot['sceneId'], 'water');
    store.data['real/two'] = {
      'storyId': 'garden',
      'version': 1,
      'sceneId': 'deleted',
      'introduced': true,
      'completed': <String>[],
      'parentGap': 10,
      'invited': false
    };
    controller.replaceCatalog(catalog(version: 3, first: 'new'));
    await controller.select('two');
    expect(controller.snapshot['error'], isNotEmpty);
    expect(store.data['real/two']!['sceneId'], 'deleted');
    expect(await controller.repeat(), true);
    expect(store.data['real/two']!['sceneId'], 'new');
  });
  testWidgets('one proactive invitation and mute/recording gates',
      (tester) async {
    controller.dispose();
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        idleDuration: const Duration(seconds: 3),
        request: null,
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
    await controller.select('one');
    spoken.clear();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(controller.snapshot['source'], 'invitation');
    expect(spoken, hasLength(1));
    await tester.pump(const Duration(seconds: 12));
    expect(spoken, hasLength(1));
    controller.setMuted(true);
    await controller.repeat();
    await tester.pump(const Duration(seconds: 4));
    expect(spoken, hasLength(1));
    controller.setMuted(false);
    controller.setRecording(true);
    await tester.pump(const Duration(seconds: 4));
    expect(spoken, hasLength(1));
    controller.dispose();
  });
}
