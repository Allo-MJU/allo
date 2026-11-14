import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'affinity_controller_test.dart' show DemoApi;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA, sessionB;
import 'session_end_test.dart' show SavingStore;

class FakeSavingDex extends SavingStore {
  @override
  Future<void> saveTripProgress(
      bool demo, EggTier tier, IncubationProgress progress) async {
    if (demo) {
      progressWrites++;
      await gate?.future;
      if (this.fail) throw StateError('disk full');
    }
    await super.saveTripProgress(demo, tier, progress);
  }
}

class FailingCheckpointDex extends DexStore {
  bool fail = false;
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    if (fail) throw StateError('disk full');
    await super.saveIncubationProgress(tier, progress);
  }
}

class CountingFakeFeed extends FakeVehicleFeed {
  CountingFakeFeed() : super(scenario: FakeScenario.clear);
  int watches = 0;
  @override
  Stream<VehicleState> watch() {
    watches++;
    return super.watch();
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
  var now = 0;
  Future<bool> action(String name,
          [Map<String, dynamic> fields = const {}, String? id]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': id ?? 'r${request++}',
        'action': name,
        ...fields
      }));
  Future<void> hatchCurrent() async {
    for (var i = 0; i < 17; i++) {
      await game.petEgg();
      if (i < 16) {
        now += 10000;
        feed.sample();
      }
    }
    expect(game.affinityRound!.score, 50);
    await game.uploadEggPhoto(Uint8List.fromList([1]));
    for (var i = 0; i < 12; i++) {
      now += 10000;
      feed.sample();
      await game.petEgg();
    }
    await Future<void>.delayed(Duration.zero);
    expect(game.game.stage, Stage.hatched);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    request = 0;
    now = 0;
    storage = CampMemory();
    camp = BaseCampController(store: storage);
    feed = RoundFeed();
    api = DemoApi();
    game = GameController(
        feed: feed,
        dex: DexStore(),
        eggApi: api,
        baseCamp: camp,
        monotonicMs: () => now);
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
      'explicit demo pairing grants one egg and legacy start stays rejected after trip end',
      () async {
    app.dispose();
    game.dispose();
    final dex = FakeSavingDex();
    final fake = CountingFakeFeed();
    game = GameController(feed: fake, dex: dex, monotonicMs: () => 0);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(game.eggId, isNull);
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    await action('navigate', {'view': 'cabin'});
    expect(game.eggId, isNotNull);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    final previousEgg = game.eggId;
    dex.gate = Completer<void>();
    expect(await action('endTrip'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(game.sessionEnded, isTrue);
    expect(game.endingSession, isTrue);
    expect(game.sessionSaved, isFalse);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    final saved = game.endSession();
    dex.gate!.complete();
    expect(await saved, isTrue);
    expect(game.sessionSaved, isTrue);
    expect(app.snapshot['canStart'], isFalse);
    expect(game.sessionEnded, isTrue);
    expect(game.eggId, previousEgg);
    expect((app.snapshot['egg'] as Map)['active'], isFalse);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    game.prepareNextFakeTrip();
    expect(await game.ensureTripEgg(), isTrue);
    expect(game.sessionEnded, isFalse);
    expect(game.sessionSaved, isFalse);
    expect(
        fake.watches, 2); // Explicit demo advance resumes the unfinished egg.
    expect(game.game.stage, Stage.incubating);
    expect(app.snapshot['view'], 'cabin');
  });
  test('test connection credentials enter cabin once without replacing the egg',
      () async {
    app.dispose();
    game.dispose();
    final fake = CountingFakeFeed();
    game = GameController(feed: fake, dex: DexStore(), monotonicMs: () => 0);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(app.snapshot['connected'], false);
    expect(app.snapshot['isDemo'], true);
    const credentials = {
      'sessionId': '00000000-0000-4000-8000-000000000001',
      'pairCode': '000000'
    };
    await action('navigate', {'view': 'pairing'});
    expect(await action('pair', credentials), true);
    expect(app.view, 'cabin');
    expect(app.snapshot['connected'], true);
    final egg = game.eggId;
    expect(egg, isNotNull);
    await action('navigate', {'view': 'pairing'});
    expect(await action('pair', credentials), true);
    expect(app.view, 'cabin');
    expect(game.eggId, egg);
    expect(fake.watches, 1);
  });
  test('failed demo end save keeps cabin next-trip start disabled', () async {
    app.dispose();
    game.dispose();
    final dex = FakeSavingDex();
    game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: dex,
        monotonicMs: () => 0);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(game.eggId, isNull);
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    await action('navigate', {'view': 'cabin'});
    expect(game.eggId, isNotNull);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    dex.fail = true;
    await action('endTrip');
    await Future<void>.delayed(Duration.zero);
    expect(await game.endSession(), isFalse);
    expect(game.sessionSaved, isFalse);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    expect(game.sessionEnded, isTrue);
  });
  test('saved real vehicle end never enables next demo journey', () async {
    await action('navigate', {'view': 'cabin'});
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'car'});
    expect(await game.endSession(), isTrue);
    expect(game.sessionSaved, isTrue);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    expect(game.sessionEnded, isTrue);
  });
  test('saved discard is accepted even when core feedback is none', () async {
    await action('navigate', {'view': 'cabin'});
    final egg = game.eggId;
    expect(await action('discardEgg', {'eggId': egg}), isTrue);
    expect(game.eggFeedback, EggFeedback.none);
    expect(game.affinityRound!.phase, AffinityPhase.discarded);
    expect((app.snapshot['egg'] as Map)['phase'], 'discarded');
    expect(await action('discardEgg', {'eggId': egg}), isFalse);
  });
  test('discard save failure is rejected and does not publish discarded egg',
      () async {
    app.dispose();
    game.dispose();
    final dex = FailingCheckpointDex();
    feed = RoundFeed();
    game = GameController(feed: feed, dex: dex, monotonicMs: () => 0);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    await game.startIncubating(EggTier.small, useAffinity: true);
    feed.sample();
    await action('navigate', {'view': 'cabin'});
    dex.fail = true;
    expect(await action('discardEgg', {'eggId': game.eggId}), isFalse);
    expect((app.snapshot['egg'] as Map)['phase'], 'incubating');
    expect(app.snapshot['error'], isNotEmpty);
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
      'pairingScanAvailable',
      'isDemo',
      'canStart',
      'sessionEnded',
      'speechAvailable',
      'photoAvailable',
      'story',
      'egg',
      'learning',
      'materials',
      'facilities',
      'creatures',
      'jobs',
      'foods',
      'training',
      'dex',
      'rewardStatus',
      'fishingRecords',
      'fishingError',
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
  test('active egg cannot be replaced manually by changing tier', () async {
    final egg = game.eggId;
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'mid'}), isFalse);
    expect(game.eggId, egg);
    expect(game.game.eggTier, EggTier.small);
    expect(feed.watches, 1); // Pairing prepares the egg and vehicle watch once.
  });
  test(
      'first pair after boot restores unfinished egg; discard cannot grant again',
      () async {
    final dex = game.dex, egg = game.eggId;
    await game.endSession();
    app.dispose();
    game.dispose();
    feed = RoundFeed();
    game = GameController(
        feed: feed, dex: dex, eggApi: api, monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    feed.sample();
    expect(game.eggId, egg);
    expect(app.snapshot['canStart'], false);
    expect(await action('startEgg', {'tier': 'small'}), false);
    await action('navigate', {'view': 'cabin'});
    expect(await action('discardEgg', {'eggId': egg}), true);
    expect(await action('startEgg', {'tier': 'small'}), false);
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    feed.sample();
    expect(game.eggId, egg);
    expect(game.affinityRound!.phase, AffinityPhase.discarded);
  });
  test('saved hatch restores without a thirty minute repeating grant',
      () async {
    await hatchCurrent();
    final egg = game.eggId, dex = game.dex;
    expect((await dex.all()).single.sourceEggId, egg);
    await game.endSession();
    app.dispose();
    game.dispose();
    feed = RoundFeed();
    game = GameController(
        feed: feed, dex: dex, eggApi: api, monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    expect(game.game.stage, Stage.hatched);
    expect(game.eggId, egg);
    expect(await action('startEgg', {'tier': 'large'}), false);
    now += 7200000;
    feed.sample(eta: 600);
    expect(game.eggId, egg);
    expect(game.game.stage, Stage.hatched);
    expect(app.snapshot['canStart'], false);
  });
  test(
      'explicit disconnect pair resumes stopped round without active replacement',
      () async {
    final egg = game.eggId;
    await game.petEgg();
    expect(await action('disconnect'), true);
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    feed.sample();
    expect(game.eggId, egg);
    expect(game.affinityRound!.score, 3);
    final watches = feed.watches;
    expect(await action('startEgg', {'tier': 'mid'}), false);
    expect(await action('startEgg', {'tier': 'small'}), false);
    expect(feed.watches, watches);
    expect(app.snapshot['canStart'], false);
  });
  for (final session in [sessionA, sessionB]) {
    test('direct pair $session resumes current egg and retains input timer',
        () async {
      await action('navigate', {'view': 'cabin'});
      await game.petEgg();
      final egg = game.eggId;
      expect(await action('pair', {'sessionId': session, 'pairCode': '123456'}),
          true);
      feed.sample();
      expect(game.eggId, egg);
      expect(game.affinityRound!.score, 3);
      expect((app.snapshot['egg'] as Map)['active'], true);
      now += 10000;
      feed.sample();
      expect(await action('petEgg', {'eggId': egg}), true);
      expect(game.affinityRound!.score, 6);
      expect(await action('startEgg', {'tier': 'large'}), false);
    });
  }
  test(
      'real ended trip pairs new vehicle and automatically resumes unfinished egg',
      () async {
    await action('navigate', {'view': 'cabin'});
    await game.petEgg();
    final egg = game.eggId;
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'car'});
    expect(await game.endSession(), true);
    expect(await action('pair', {'sessionId': sessionB, 'pairCode': '123456'}),
        true);
    feed.sample();
    expect(game.eggId, egg);
    expect(game.affinityRound!.score, 3);
    expect(game.sessionEnded, false);
    now += 10000;
    feed.sample();
    expect(await action('petEgg', {'eggId': egg}), true);
    expect(game.affinityRound!.score, 6);
    expect(app.snapshot['canStart'], false);
  });
  test('first idle pairing automatically creates one default small egg',
      () async {
    app.dispose();
    game.dispose();
    feed = RoundFeed();
    game = GameController(
        feed: feed, dex: DexStore(), eggApi: api, monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    feed.sample();
    expect(game.game.stage, Stage.incubating);
    expect(game.eggId, isNotNull);
    expect(game.game.eggTier, EggTier.small);
    expect(app.snapshot['canStart'], false);
  });
  test('same-session saved hatch pair never starts a repeat', () async {
    await hatchCurrent();
    final egg = game.eggId;
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    expect(game.game.stage, Stage.hatched);
    expect(game.eggId, egg);
    now += 7200000;
    feed.sample(eta: 600);
    expect(game.eggId, egg);
    expect(game.game.stage, Stage.hatched);
    expect(await action('startEgg', {'tier': 'large'}), false);
  });
  test('new-session pair closes old hatch and automatically grants default egg',
      () async {
    await hatchCurrent();
    final old = game.eggId;
    expect(await action('pair', {'sessionId': sessionB, 'pairCode': '123456'}),
        true);
    feed.sample();
    expect(game.game.stage, Stage.incubating);
    expect(game.eggId, isNot(old));
    expect(game.game.eggTier, EggTier.small);
    expect((app.snapshot['egg'] as Map)['active'], true);
    expect(await action('startEgg', {'tier': 'mid'}), false);
  });
}
