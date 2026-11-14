import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
          'scenes': [
            {'id': first},
            {'id': 'water'}
          ]
        }
      ]
    });
const owned = [
  LearningCreature(id: 'one', speciesId: 'road_sprout', name: '길싹이'),
  LearningCreature(id: 'two', speciesId: 'road_sprout', name: '길싹이'),
  LearningCreature(id: 'other', speciesId: 'mistfin', name: '바다안개')
];
Map<String, dynamic> reply(Map<String, dynamic> request,
    {bool parent = false}) {
  final action = request['action'] ?? 'chat';
  final scene = action == 'next' ? 'water' : request['sceneId'];
  return {
    for (final key in [
      'requestId',
      'creatureId',
      'speciesId',
      'storyId',
      'version'
    ])
      key: request[key],
    'sceneId': scene,
    'title': scene == 'water' ? '물' : '씨앗',
    'canNext': scene != 'water',
    'mode': action == 'invite'
        ? 'menu'
        : action == 'chat'
            ? 'chat'
            : 'story',
    'source': action == 'chat' ? 'ai' : 'authored',
    'parentPromptUsed': parent,
    'text': action == 'invite'
        ? '나한테 궁금한 게 있는 거야?'
        : action == 'chat'
            ? '물은 씨앗이 자라는 데 필요해.'
            : scene == 'water'
                ? '씨앗에 물을 주었어.'
                : '작은 씨앗을 찾았어.'
  };
}

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
  test('shipped phone manifest contains identifiers and public names only', () {
    final manifest = jsonDecode(
            File('assets/data/companion_learning.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(LearningCatalog.fromJson(manifest).stories, isNotEmpty);
    for (final story in manifest['stories'] as List) {
      expect(
          (story as Map).keys,
          unorderedEquals([
            'speciesId',
            'storyId',
            'version',
            'name',
            'firstSceneId',
            'scenes'
          ]));
      for (final scene in story['scenes'] as List) {
        expect((scene as Map).keys, ['id']);
      }
    }
  });
  test('egg and unowned targets never speak or request backend', () async {
    expect(await controller.chat('hi', requestId: 'r'), false);
    expect(await controller.repeat(), false);
    expect(await controller.next(), false);
    expect(await controller.select('unowned'), false);
    expect(spoken, isEmpty);
    expect(requests, isEmpty);
  });
  test(
      'backend owns invitation text and story transitions; selection stays silent',
      () async {
    controller.dispose();
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        request: (r) async {
          requests.add(r);
          return {
            ...reply(r),
            'sceneId': r['sceneId'],
            'title': '서버 제목',
            'text': r['action'] == 'invite' ? '서버 초대' : '서버가 고른 장면',
            'canNext': true
          };
        },
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
    await controller.select('one');
    expect(spoken, isEmpty);
    expect(requests, isEmpty);
    expect(await controller.openInvitation(), true);
    expect(requests.single['action'], 'invite');
    expect(spoken.single, '서버 초대');
    expect(await controller.listenStory(), true);
    expect(controller.snapshot['text'], '서버가 고른 장면');
    expect(await controller.next(), true);
    expect(requests.last['action'], 'next');
    expect(controller.snapshot['sceneId'], 'seed');
    expect(controller.snapshot['title'], '서버 제목');
  });
  test(
      'explicit server next; exact ownership and real/demo progress stay separate',
      () async {
    await controller.select('one');
    await controller.repeat();
    expect(await controller.next(), true);
    expect(controller.snapshot['sceneId'], 'water');
    expect(await controller.next(), false);
    await controller.select('two');
    await controller.repeat();
    expect(controller.snapshot['sceneId'], 'seed');
    await controller.select('one');
    expect(controller.snapshot['sceneId'], 'water');
    controller.setContext(profile: 'demo', creatures: owned, active: true);
    await controller.select('one');
    await controller.repeat();
    expect(controller.snapshot['sceneId'], 'seed');
    expect(store.data.keys, containsAll(['real/one', 'real/two', 'demo/one']));
    expect(store.data.toString(), isNot(contains('작은 씨앗')));
  });
  test(
      'save failure leaves confirmed scene unchanged and does not narrate reply',
      () async {
    await controller.select('one');
    await controller.repeat();
    spoken.clear();
    store.fail = true;
    expect(await controller.next(), false);
    expect(controller.snapshot['sceneId'], 'seed');
    expect(controller.snapshot['error'], isNotEmpty);
    expect(spoken, isEmpty);
  });
  test(
      'invalid response shows an error without inventing a local story fallback',
      () async {
    controller.dispose();
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        request: (r) async => {...reply(r), 'sceneId': 'wrong'},
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
    await controller.select('one');
    expect(await controller.chat('질문', requestId: 'x'), false);
    expect(controller.snapshot['source'], '');
    expect(controller.snapshot['text'], '');
    expect(controller.snapshot['error'], isNotEmpty);
    expect(controller.snapshot['sceneId'], 'seed');
    expect(controller.history, isEmpty);
    expect(spoken, isEmpty);
  });
  test(
      'late backend responses dropped after selection, suspension and profile switch',
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
      gate.complete(reply(sent));
      expect(await pending, false);
      expect(spoken, isEmpty);
      expect(controller.history, isEmpty);
      expect(controller.snapshot['busy'], false);
    }
  });
  test('history bounded to six exchanges; client does not own parent frequency',
      () async {
    controller.dispose();
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        request: (r) async {
          requests.add(r);
          return reply(r, parent: true);
        },
        speak: (_) async {},
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
    await controller.select('one');
    for (var i = 0; i < 8; i++) {
      expect(await controller.chat('질문 $i', requestId: 'q$i'), true);
    }
    expect(controller.history, hasLength(12));
    expect(controller.history.first['text'], '질문 2');
    expect(await controller.chat('질문 7', requestId: 'q7'), false);
    expect(requests.map((r) => r['allowParentPrompt']), everyElement(true));
    expect(store.data.toString(), isNot(contains('질문')));
    expect(store.data['real/one']!.containsKey('parentGap'), false);
  });
  test(
      'unknown story only shows preparation notice and never requests a fabricated turn',
      () async {
    expect(await controller.select('other'), true);
    expect(await controller.openInvitation(), true);
    expect(controller.snapshot['available'], false);
    expect(controller.snapshot['error'], contains('준비 중'));
    expect(await controller.chat('hi', requestId: 'n'), false);
    expect(spoken, isEmpty);
    expect(requests, isEmpty);
  });
  test('changed story restarts through explicit invitation and backend listen',
      () async {
    await controller.select('one');
    await controller.repeat();
    store.data['real/one']!['storyId'] = 'retired';
    await controller.select('one');
    expect(controller.snapshot['error'], isNotEmpty);
    expect(store.data['real/one']!['storyId'], 'retired');
    expect(await controller.openInvitation(), true);
    expect(await controller.listenStory(), true);
    expect(controller.snapshot['conversationMode'], 'story');
    expect(store.data['real/one']!['storyId'], 'garden');
  });
  test('unconfigured backend fails honestly and leaves scene unchanged',
      () async {
    controller.dispose();
    controller = CompanionLearningController(
        catalog: catalog(),
        store: store,
        request: null,
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    controller.setContext(profile: 'real', creatures: owned, active: true);
    await controller.select('one');
    expect(await controller.openInvitation(), false);
    expect(controller.snapshot['conversationMode'], 'menu');
    expect(controller.snapshot['error'], isNotEmpty);
    expect(controller.snapshot['text'], '');
    expect(spoken, isEmpty);
  });
  testWidgets('no automatic invitation or narration after four idle minutes',
      (tester) async {
    await tester.runAsync(() => controller.select('one'));
    await tester.pump(const Duration(minutes: 4));
    expect(spoken, isEmpty);
    expect(requests, isEmpty);
    expect(controller.snapshot['conversationMode'], 'closed');
  });
}
