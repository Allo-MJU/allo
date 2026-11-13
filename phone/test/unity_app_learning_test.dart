import 'dart:async';
import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/learning/companion_learning_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'affinity_controller_test.dart' show DemoApi;
import 'companion_learning_test.dart' show catalog, MemoryLearningStore, reply;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;

class DelayedPetGame extends GameController {
  DelayedPetGame(
      {required super.feed,
      required super.dex,
      required super.baseCamp,
      required super.eggApi,
      required super.monotonicMs});
  final petGate = Completer<void>();
  String? replacementEgg;
  @override
  String? get eggId => replacementEgg ?? super.eggId;
  @override
  Future<EggFeedback> petEgg() async {
    await petGate.future;
    return EggFeedback.positive;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late BaseCampController camp;
  late UnityAppController app;
  late CompanionLearningController learning;
  late RoundFeed feed;
  late List<String> spoken;
  late List<Map<String, dynamic>> requests;
  var request = 0, now = 0;
  Future<bool> action(String name,
          [Map<String, dynamic> fields = const {}, String? id]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': id ?? 'r${request++}',
        'action': name,
        ...fields
      }));
  String getTarget() => camp.state.creatures.values
      .firstWhere((c) => c.speciesId == 'road_sprout')
      .id;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = 0;
    request = 0;
    spoken = [];
    requests = [];
    final dex = DexStore();
    for (var i = 0; i < 2; i++) {
      await dex.add(DexEntry(
          speciesId: 'road_sprout',
          obtainedAt: DateTime.utc(2026, 11, 12, i),
          envTags: const [],
          regionTag: null,
          tier: 1,
          sourceEggId: 'owned-$i'));
    }
    camp = BaseCampController(store: CampMemory(), dex: dex);
    feed = RoundFeed();
    game = GameController(
        feed: feed,
        dex: dex,
        baseCamp: camp,
        eggApi: DemoApi(),
        monotonicMs: () => now);
    learning = CompanionLearningController(
        catalog: catalog(),
        store: MemoryLearningStore(),
        request: (r) async {
          requests.add(r);
          return reply(r);
        },
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    app = UnityAppController(game: game, camp: camp, learning: learning);
    expect(await app.initialize(), true);
    await game.pair(sessionA, pairCode: '123456');
    await game.startIncubating(EggTier.small, useAffinity: true);
    feed.sample();
    await action('navigate', {'view': 'cabin'});
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });

  test('window story owns dialogue and rejects stale learning and care intents',
      () async {
    final id = getTarget();
    await action('selectCompanion', {'creatureId': id});
    expect(await action('storyNext', {'creatureId': id}), true);
    expect(learning.snapshot['sceneId'], 'water');
    expect(await action('storyStart', {'topicId': 'coast_sail'}), true);
    expect((app.snapshot['story'] as Map)['active'], true);
    expect(learning.active, false);
    final count = spoken.length;
    expect(await action('storyRepeat', {'creatureId': id}), false);
    expect(
        await action('companionChat', {'creatureId': id, 'text': '질문'}), false);
    expect(await action('commonCare', {'creatureId': id, 'actionId': 'pet'}),
        false);
    expect(await action('selectCompanion', {'creatureId': ''}), false);
    expect(spoken.length, count);
    final story = app.snapshot['story'] as Map;
    expect(
        await action('storyPause', {
          'instanceId': story['instanceId'],
          'nodeId': story['nodeId'],
          'storyRevision': story['revision'],
        }),
        true);
    expect(learning.active, true);
    expect(learning.snapshot['sceneId'], 'water');
    expect(await action('storyRepeat', {'creatureId': id}), true);
  });

  test('modal and notebook ownership stop companion output until released',
      () async {
    final id = getTarget();
    await action('selectCompanion', {'creatureId': id});
    expect(await action('learningUiBlocked', {'blocked': true}), true);
    expect(learning.active, false);
    expect(
        await action('companionChat', {'creatureId': id, 'text': '질문'}), false);
    expect(await action('learningUiBlocked', {'blocked': false}), true);
    expect(learning.active, true);
    await action('storyUiBlocked', {'blocked': true});
    expect(learning.active, false);
    expect(await action('storyStart', {'topicId': 'coast_sail'}), false);
  });

  test(
      'canonical supplied friend uses the existing ownership registry and art metadata',
      () async {
    await game.dex.add(DexEntry(
        speciesId: 'breeze_wyrm',
        obtainedAt: DateTime.utc(2026, 11, 14),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'imported-canonical-friend'));
    expect(await action('refresh'), true);
    final friend = camp.state.creatures.values
        .firstWhere((c) => c.speciesId == 'breeze_wyrm');
    final sent = <Map<String, dynamic>>[];
    app.attach(
        (message) => sent.add(jsonDecode(message) as Map<String, dynamic>));
    await app.handleMessage('{"type":"ready"}');
    expect(await action('selectCompanion', {'creatureId': friend.id}), true);
    expect(learning.speciesId, 'breeze_wyrm');
    expect(learning.snapshot['name'], '산들룡');
    final cast = sent.lastWhere((m) => m['type'] == 'cast');
    expect(cast['companion']['id'], 'breeze_wyrm');
    expect(cast['companion']['attribute'], 'unassigned');
    expect(cast['companion']['sprite'], 'species/breeze_wyrm.png');
    expect(
        (app.snapshot['creatures'] as List)
            .firstWhere((c) => c['id'] == friend.id)['role'],
        '');
    expect(
        await action(
            'commonCare', {'creatureId': friend.id, 'actionId': 'ball'}),
        true);
    expect(await action('refresh'), true);
    expect(camp.state.creatures[friend.id]?.speciesId, 'breeze_wyrm');
  });

  test('opening notebook invalidates an in-flight companion answer', () async {
    final gate = Completer<Map<String, dynamic>>();
    late Map<String, dynamic> sent;
    app.dispose();
    learning = CompanionLearningController(
        catalog: catalog(),
        store: MemoryLearningStore(),
        request: (r) {
          sent = r;
          return gate.future;
        },
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    app = UnityAppController(game: game, camp: camp, learning: learning);
    expect(await app.initialize(), true);
    await action('navigate', {'view': 'cabin'});
    final id = getTarget();
    await action('selectCompanion', {'creatureId': id});
    final pending = action('companionChat', {'creatureId': id, 'text': '질문'});
    await Future<void>.delayed(Duration.zero);
    await action('learningUiBlocked', {'blocked': true});
    final count = spoken.length;
    gate.complete(reply(sent));
    expect(await pending, false);
    expect(spoken.length, count);
    expect(learning.history, isEmpty);
    expect((app.snapshot['story'] as Map)['canPlay'], true);
  });

  test('action names cannot be used as navigation destinations', () async {
    for (final value in [
      'selectCompanion',
      'storyNext',
      'companionChat',
      'commonCare'
    ]) {
      expect(await action('navigate', {'view': value}), false);
      expect(app.view, 'cabin');
    }
  });

  test('seven egg actions score pet once and preserve camp food and materials',
      () async {
    final before = camp.state.toJson();
    for (final id in [
      'snack',
      'water',
      'ball',
      'pet',
      'plush',
      'cushion',
      'blanket'
    ]) {
      expect(
          await action('commonCare',
              {'actionId': id, 'creatureId': '', 'eggId': game.eggId}),
          true);
    }
    expect(game.affinityRound!.score, 3);
    expect((app.snapshot['learning'] as Map)['careSequence'], 7);
    expect(camp.state.toJson()['foodInventory'], before['foodInventory']);
    expect(camp.state.toJson()['materials'], before['materials']);
    expect(spoken, isEmpty);
    expect(requests, isEmpty);
    expect(game.feedCount, 0);
    expect(game.playCount, 0);
    expect(
        await action(
            'commonCare',
            {'actionId': 'snack', 'creatureId': '', 'eggId': game.eggId},
            'one-care'),
        true);
    expect(
        await action(
            'commonCare',
            {'actionId': 'snack', 'creatureId': '', 'eggId': game.eggId},
            'one-care'),
        false);
    expect((app.snapshot['learning'] as Map)['careSequence'], 8);
  });

  test(
      'selected owned friend plays and talks beside new egg without affecting it',
      () async {
    final id = getTarget(), egg = game.eggId;
    expect(await action('selectCompanion', {'creatureId': id}), true);
    for (final care in [
      'snack',
      'water',
      'ball',
      'pet',
      'plush',
      'cushion',
      'blanket'
    ]) {
      expect(await action('commonCare', {'actionId': care, 'creatureId': id}),
          true);
    }
    expect(game.affinityRound!.score, 0);
    expect(game.eggId, egg);
    expect(await action('companionChat', {'creatureId': id, 'text': '씨앗이 뭐야?'}),
        true);
    expect(learning.snapshot['sceneId'], 'seed');
    expect(await action('storyNext', {'creatureId': id}), true);
    expect(learning.snapshot['sceneId'], 'water');
    expect(await action('selectCompanion', {'creatureId': ''}), true);
    final count = spoken.length;
    expect(await action('companionChat', {'creatureId': '', 'text': '알아 안녕'}),
        false);
    expect(spoken.length, count);
    expect(game.affinityRound!.score, 0);
  });

  test('stale action cannot apply to a different selected friend or egg',
      () async {
    final ids = camp.state.creatures.keys.toList();
    await action('selectCompanion', {'creatureId': ids.first});
    await action('selectCompanion', {'creatureId': ids.last});
    expect(
        await action(
            'companionChat', {'creatureId': ids.first, 'text': '옛 친구에게'}),
        false);
    expect(requests, isEmpty);
    expect(await action('storyNext', {'creatureId': ids.first}), false);
    expect(
        await action(
            'commonCare', {'creatureId': ids.first, 'actionId': 'pet'}),
        false);
    await action('selectCompanion', {'creatureId': ''});
    expect(
        await action('commonCare',
            {'creatureId': '', 'eggId': 'old-egg', 'actionId': 'pet'}),
        false);
    expect(game.affinityRound!.score, 0);
  });

  test(
      'photo lock still permits unscored pet visual and blocks progress bypass',
      () async {
    for (var i = 0; i < 17; i++) {
      await game.petEgg();
      now += 10000;
      feed.sample();
    }
    expect(game.affinityRound!.phase, AffinityPhase.photoRequired);
    expect(
        await action('commonCare',
            {'creatureId': '', 'eggId': game.eggId, 'actionId': 'pet'}),
        true);
    expect(game.affinityRound!.score, 50);
    expect(game.affinityRound!.phase, AffinityPhase.photoRequired);
  });

  test('care acknowledgement never animates an egg that replaced its target',
      () async {
    final dex = game.dex;
    app.dispose();
    game.dispose();
    feed = RoundFeed();
    final delayed = DelayedPetGame(
        feed: feed,
        dex: dex,
        baseCamp: camp,
        eggApi: DemoApi(),
        monotonicMs: () => now);
    game = delayed;
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    await game.startIncubating(EggTier.small, useAffinity: true);
    feed.sample();
    await action('navigate', {'view': 'cabin'});
    final pending = action('commonCare',
        {'creatureId': '', 'eggId': game.eggId, 'actionId': 'pet'});
    await Future<void>.delayed(Duration.zero);
    delayed.replacementEgg = 'replacement-egg';
    delayed.petGate.complete();
    expect(await pending, false);
    expect((app.snapshot['learning'] as Map)['careSequence'], 0);
  });

  test(
      'native voice followup keeps session history across its own input activity',
      () async {
    final gate = Completer<String?>();
    app.dispose();
    learning = CompanionLearningController(
        catalog: catalog(),
        store: MemoryLearningStore(),
        request: (r) async {
          requests.add(r);
          return reply(r);
        },
        speak: (s) async {},
        stop: () async {});
    app = UnityAppController(
        game: game,
        camp: camp,
        learning: learning,
        speechInput: () => gate.future);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    final id = getTarget();
    await action('selectCompanion', {'creatureId': id});
    expect(await action('companionChat', {'creatureId': id, 'text': '씨앗이 뭐야?'}),
        true);
    final pending = action('companionSpeech', {'creatureId': id});
    await Future<void>.delayed(Duration.zero);
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    gate.complete('그럼 물은 얼마나 필요해?');
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    expect(await pending, true);
    expect(requests.last['history'], hasLength(2));
    expect((requests.last['history'] as List).first['text'], '씨앗이 뭐야?');
  });

  test('background after STT finishes cancels its pending AI response',
      () async {
    final gate = Completer<Map<String, dynamic>>();
    final entered = Completer<void>();
    late Map<String, dynamic> sent;
    app.dispose();
    learning = CompanionLearningController(
        catalog: catalog(),
        store: MemoryLearningStore(),
        request: (r) {
          sent = r;
          entered.complete();
          return gate.future;
        },
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    app = UnityAppController(
        game: game,
        camp: camp,
        learning: learning,
        speechInput: () async => '음성 질문');
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    final id = getTarget();
    await action('selectCompanion', {'creatureId': id});
    final pending = action('companionSpeech', {'creatureId': id});
    await entered.future;
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    final count = spoken.length;
    gate.complete(reply(sent));
    expect(await pending, false);
    expect(spoken.length, count);
    expect(learning.history, isEmpty);
  });

  test('leaving and returning to cabin cancels pending native transcript',
      () async {
    final gate = Completer<String?>();
    app.dispose();
    learning = CompanionLearningController(
        catalog: catalog(),
        store: MemoryLearningStore(),
        request: (r) async {
          requests.add(r);
          return reply(r);
        },
        speak: (s) async {},
        stop: () async {});
    app = UnityAppController(
        game: game,
        camp: camp,
        learning: learning,
        speechInput: () => gate.future);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    final id = getTarget();
    await action('selectCompanion', {'creatureId': id});
    final pending = action('companionSpeech', {'creatureId': id});
    await Future<void>.delayed(Duration.zero);
    await action('navigate', {'view': 'home'});
    await action('navigate', {'view': 'cabin'});
    gate.complete('이전 음성');
    expect(await pending, false);
    expect(requests, isEmpty);
    expect(learning.snapshot['recording'], false);
  });

  test('host or Unity suspension invalidates pending API even after resume',
      () async {
    final gate = Completer<Map<String, dynamic>>();
    late Map<String, dynamic> sent;
    app.dispose();
    learning = CompanionLearningController(
        catalog: catalog(),
        store: MemoryLearningStore(),
        request: (r) {
          sent = r;
          return gate.future;
        },
        speak: (s) async {
          spoken.add(s);
        },
        stop: () async {});
    app = UnityAppController(game: game, camp: camp, learning: learning);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    final id = getTarget();
    await action('selectCompanion', {'creatureId': id});
    final pending =
        action('companionChat', {'creatureId': id, 'text': '늦은 질문'});
    await Future<void>.delayed(Duration.zero);
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    await app.setHostLifecycle(AppLifecycleState.resumed);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    final count = spoken.length;
    gate.complete(reply(sent));
    expect(await pending, false);
    expect(spoken.length, count);
    expect(learning.history, isEmpty);
  });
}
