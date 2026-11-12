import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'affinity_controller_test.dart' show DemoApi;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

class FailingCheckpointDex extends DexStore {
  bool fail = false;
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    if (fail) throw StateError('disk full');
    await super.saveIncubationProgress(tier, progress);
  }
}

class CampMemory extends BaseCampStore {
  Map<String, dynamic>? saved;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> load() async => saved;
  @override
  Future<void> save(Map<String, dynamic> value) async {
    if (fail) throw StateError('disk full');
    saved = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late UnityAppController app;
  late BaseCampController camp;
  late CampMemory storage;
  late RoundFeed feed;
  late DemoApi api;
  var request = 0;
  Future<bool> action(String name,
          [Map<String, dynamic> fields = const {}, String? id]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': id ?? 'r${request++}',
        'action': name,
        ...fields
      }));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    request = 0;
    storage = CampMemory();
    camp = BaseCampController(store: storage);
    feed = RoundFeed();
    api = DemoApi();
    game = GameController(
        feed: feed,
        dex: DexStore(),
        eggApi: api,
        baseCamp: camp,
        monotonicMs: () => 0);
    app = UnityAppController(
        game: game,
        camp: camp,
        speechInput: () async => 'hello',
        photoInput: () async => Uint8List.fromList([1]));
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    await game.startIncubating(EggTier.small, useAffinity: true);
    feed.sample();
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });
  test(
      'valid current cabin pet commits once, duplicate request never mutates again',
      () async {
    expect(await action('navigate', {'view': 'cabin'}), isTrue);
    final egg = game.eggId!;
    expect(await action('petEgg', {'eggId': egg}, 'pet-one'), isTrue);
    expect((app.snapshot['egg'] as Map)['score'], 3);
    expect(await action('petEgg', {'eggId': egg}, 'pet-one'), isFalse);
    expect(game.affinityRound!.score, 3);
  });
  test(
      'malformed, wrong version, stale egg and outside cabin cannot trigger input',
      () async {
    expect(await app.handleMessage('{broken'), isFalse);
    expect(
        await app.handleMessage(jsonEncode({
          'v': 2,
          'type': 'appAction',
          'requestId': 'bad',
          'action': 'petEgg',
          'eggId': game.eggId
        })),
        isFalse);
    expect(await action('speech', {'eggId': game.eggId}), isFalse);
    await action('navigate', {'view': 'cabin'});
    expect(await action('petEgg', {'eggId': 'old'}), isFalse);
    expect(await action('placeEgg', {'eggId': game.eggId, 'zone': 4}), isFalse);
    expect(api.speechCalls, 0);
    expect(game.affinityRound!.score, 0);
  });
  test('snapshot exact DTO, canonical dex and zero unearned materials', () {
    expect(app.snapshot.keys.toSet(), {
      'v',
      'type',
      'revision',
      'view',
      'ready',
      'busy',
      'error',
      'notice',
      'connected',
      'isDemo',
      'canStart',
      'sessionEnded',
      'speechAvailable',
      'photoAvailable',
      'egg',
      'materials',
      'facilities',
      'creatures',
      'jobs',
      'foods',
      'training',
      'dex',
      'rewardStatus',
      'gyro',
      'reducedMotion',
      'assignments'
    });
    expect((app.snapshot['materials'] as List).map((e) => e['count']),
        everyElement(0));
    expect((app.snapshot['dex'] as List).map((e) => e['id']),
        contains('road_sprout'));
    expect(jsonEncode(app.snapshot), isNot(contains('hello')));
  });
  test(
      'camp rejects unaffordable build and save failure keeps committed balance',
      () async {
    final before = app.snapshot['materials'];
    expect(await action('build', {'facility': 'workshop'}), isFalse);
    expect(app.snapshot['materials'], before);
    storage.fail = true;
    expect(await action('refresh'), isFalse);
    expect(app.snapshot['materials'], before);
    expect(app.snapshot['error'], isNotEmpty);
  });
  test('native speech callback is rechecked after leaving cabin', () async {
    final gate = Completer<String?>();
    app.dispose();
    app = UnityAppController(
        game: game, camp: camp, speechInput: () => gate.future);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    final speech = action('speech', {'eggId': game.eggId});
    await Future<void>.delayed(Duration.zero);
    await action('navigate', {'view': 'home'});
    gate.complete('private transcript');
    expect(await speech, isFalse);
    expect(api.speechCalls, 0);
    expect(jsonEncode(app.snapshot), isNot(contains('private transcript')));
  });
  test(
      'legacy cabin lookout routes through real material rule and home blocks it',
      () async {
    expect(await app.handleMessage('{"type":"lookTogether"}'), isFalse);
    await action('navigate', {'view': 'cabin'});
    game.game = game.game.copyWith(stage: Stage.hatched);
    expect(await app.handleMessage('{"type":"lookTogether"}'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(game.lookOutCount, 1);
    expect(camp.state.materials[CampMaterial.wood], 1);
  });
  test('disconnect saves and clears pairing before rejecting further egg input',
      () async {
    await action('navigate', {'view': 'cabin'});
    expect(await action('disconnect'), isTrue);
    expect(game.paired, isFalse);
    expect(await game.pairingStore.read(), isNull);
    expect(await action('petEgg', {'eggId': game.eggId}), isFalse);
  });
  test('failed affinity save never publishes unconfirmed score or success',
      () async {
    app.dispose();
    game.dispose();
    final dex = FailingCheckpointDex();
    feed = RoundFeed();
    game =
        GameController(feed: feed, dex: dex, eggApi: api, monotonicMs: () => 0);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    await game.startIncubating(EggTier.small, useAffinity: true);
    feed.sample();
    await action('navigate', {'view': 'cabin'});
    dex.fail = true;
    expect(await action('petEgg', {'eggId': game.eggId}), isFalse);
    expect((app.snapshot['egg'] as Map)['score'], 0);
    expect(app.snapshot['error'], isNotEmpty);
  });
  test(
      'real earned camp balance pays exactly once through serialized build dispatch',
      () async {
    await game.dex.add(DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'owned-builder'));
    await camp.refreshOwnership();
    await camp.recordVehicle(
        sessionId: 'cost-test',
        vehicle: VehicleState.fromJson({'ts': 100, 'distanceM': 0}));
    await camp.recordVehicle(
        sessionId: 'cost-test',
        vehicle: VehicleState.fromJson({'ts': 101, 'distanceM': 2000}));
    final worker = camp.state.creatures.keys.single;
    expect(await action('assign', {'role': 'builder', 'creatureId': worker}),
        isTrue);
    expect(camp.state.materials[CampMaterial.wood], 2);
    final results = await Future.wait([
      action('build', {'facility': 'workshop'}, 'build-once'),
      action('build', {'facility': 'workshop'}, 'build-once')
    ]);
    expect(results, [true, false]);
    expect(camp.state.materials[CampMaterial.wood], 0);
    expect(camp.state.materials[CampMaterial.stone], 1);
    expect(camp.state.jobs, hasLength(1));
    expect((app.snapshot['jobs'] as List).single['targetId'], 'workshop');
  });
  test('Unity background lifecycle pauses egg input then resume restores it',
      () async {
    await action('navigate', {'view': 'cabin'});
    await app.setHostLifecycle(AppLifecycleState.paused);
    expect(
        await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}'),
        isTrue);
    expect(await action('petEgg', {'eggId': game.eggId}), isFalse);
    expect(game.affinityRound!.score, 0);
    expect(
        await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}'),
        isTrue);
    expect(await action('petEgg', {'eggId': game.eggId}), isTrue);
  });
  test(
      'own native input remains active across proxy pause and pauses after callback',
      () async {
    final gate = Completer<String?>();
    app.dispose();
    app = UnityAppController(
        game: game, camp: camp, speechInput: () => gate.future);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    final input = action('speech', {'eggId': game.eggId});
    await Future<void>.delayed(Duration.zero);
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    gate.complete('hello');
    expect(await input, isTrue);
    expect(api.speechCalls, 1);
    expect(game.affinityRound!.speechRemainingMs, 180000);
    expect(await action('petEgg', {'eggId': game.eggId}), isFalse);
  });
}
