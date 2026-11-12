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
  test('saved ended demo exposes cabin start only after the save finishes',
      () async {
    app.dispose();
    game.dispose();
    final dex = SavingStore();
    final fake = CountingFakeFeed();
    game = GameController(feed: fake, dex: dex, monotonicMs: () => 0);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    expect(await action('startEgg', {'tier': 'small'}), isTrue);
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
    expect(app.snapshot['canStart'], isTrue);
    expect(game.sessionEnded,
        isTrue); // Publishing eligibility never starts a trip.
    expect(game.eggId, previousEgg);
    expect((app.snapshot['egg'] as Map)['active'], isFalse);
    expect(await action('startEgg', {'tier': 'small'}), isTrue);
    expect(game.sessionEnded, isFalse);
    expect(game.sessionSaved, isFalse);
    expect(fake.watches, 2); // A new journey resumes the saved unfinished egg.
    expect(game.game.stage, Stage.incubating);
    expect(app.snapshot['view'], 'cabin');
  });
  test('failed demo end save keeps cabin next-trip start disabled', () async {
    app.dispose();
    game.dispose();
    final dex = SavingStore();
    game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: dex,
        monotonicMs: () => 0);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await action('navigate', {'view': 'cabin'});
    expect(await action('startEgg', {'tier': 'small'}), isTrue);
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
    expect(feed.watches, 2); // Camp pairing watch, then egg watch.
  });
  test(
      'first boot can restore unfinished egg once and discarded egg can restart',
      () async {
    final dex = game.dex;
    final egg = game.eggId;
    await game.endSession();
    app.dispose();
    game.dispose();
    feed = RoundFeed();
    game = GameController(
        feed: feed, dex: dex, eggApi: api, monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    expect(app.snapshot['canStart'], isTrue);
    expect(await action('startEgg', {'tier': 'small'}), isTrue);
    feed.sample();
    expect(game.eggId, egg);
    expect(app.snapshot['canStart'], isFalse);
    await action('navigate', {'view': 'cabin'});
    expect(await action('discardEgg', {'eggId': egg}), isTrue);
    expect(app.snapshot['canStart'], isTrue);
    expect(await action('startEgg', {'tier': 'small'}), isTrue);
    feed.sample();
    expect(game.eggId, isNot(egg));
  });
  test(
      'saved hatch blocks manual tier changes until core grants the 30 minute repeat',
      () async {
    await hatchCurrent();
    final egg = game.eggId;
    expect((await game.dex.all()).single.sourceEggId, egg);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'large'}), isFalse);
    expect(game.eggId, egg);
    // Cold start may restore the saved hatch once, preserving its repeat clock.
    final dex = game.dex;
    await game.endSession();
    app.dispose();
    game.dispose();
    feed = RoundFeed();
    game = GameController(
        feed: feed, dex: dex, eggApi: api, monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    expect(app.snapshot['canStart'], isTrue);
    expect(await action('startEgg', {'tier': 'small'}), isTrue);
    expect(game.game.stage, Stage.hatched);
    expect(game.eggId, egg);
    expect(app.snapshot['canStart'], isFalse);
    now += 1799999;
    feed.sample(eta: 600);
    expect(game.eggId, egg);
    now += 1;
    feed.sample(eta: 600);
    expect(game.eggId, isNot(egg));
    expect(game.game.stage, Stage.incubating);
    expect(game.game.eggTier, EggTier.small);
    expect(game.affinityRound!.score, 0);
    expect(app.snapshot['canStart'], isFalse);
  });
  test(
      'explicit disconnect pair resumes stopped round without allowing active replacement',
      () async {
    final egg = game.eggId;
    await game.petEgg();
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'mid'}), isFalse);
    expect(await action('disconnect'), isTrue);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        isTrue);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'mid'}), isFalse);
    expect(feed.watches, 4);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    feed.sample();
    expect(game.eggId, egg);
    expect(game.affinityRound!.score, 3);
    expect(feed.watches, 4);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'small'}), isFalse);
    expect(feed.watches, 4);
  });
  for (final session in [sessionA, sessionB]) {
    test('direct pair $session resumes current egg and retains input timer',
        () async {
      await action('navigate', {'view': 'cabin'});
      await game.petEgg();
      final egg = game.eggId;
      expect(await action('pair', {'sessionId': session, 'pairCode': '123456'}),
          isTrue);
      expect(feed.watches, 4);
      feed.sample();
      expect(game.eggId, egg);
      expect(game.affinityRound!.score, 3);
      expect((app.snapshot['egg'] as Map)['active'], isTrue);
      expect(app.snapshot['canStart'], isFalse);
      now += 10000;
      feed.sample();
      expect(await action('petEgg', {'eggId': egg}), isTrue);
      expect(game.affinityRound!.score, 6);
      expect(await action('startEgg', {'tier': 'large'}), isFalse);
      expect(feed.watches, 4);
    });
  }
  test('real ended trip pairs a new vehicle and resumes unfinished egg once',
      () async {
    await action('navigate', {'view': 'cabin'});
    await game.petEgg();
    final egg = game.eggId;
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'car'});
    expect(await game.endSession(), isTrue);
    expect(game.sessionSaved, isTrue);
    expect(await action('pair', {'sessionId': sessionB, 'pairCode': '123456'}),
        isTrue);
    expect(feed.watches, 4);
    feed.sample();
    expect(game.eggId, egg);
    expect(game.affinityRound!.score, 3);
    expect(game.sessionEnded, isFalse);
    expect(app.snapshot['canStart'], isFalse);
    now += 10000;
    feed.sample();
    expect(await action('petEgg', {'eggId': egg}), isTrue);
    expect(game.affinityRound!.score, 6);
  });
  test('first idle pairing never creates an egg or starts a vehicle watch',
      () async {
    app.dispose();
    game.dispose();
    feed = RoundFeed();
    game = GameController(
        feed: feed, dex: DexStore(), eggApi: api, monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        isTrue);
    expect(game.game.stage, Stage.idle);
    expect(game.eggId, isNull);
    expect(feed.watches, 0);
    expect(app.snapshot['canStart'], isTrue);
  });
  test('same-session saved hatch pair resumes its original 30 minute cooldown',
      () async {
    await hatchCurrent();
    final egg = game.eggId;
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        isTrue);
    expect(feed.watches, 4);
    expect(game.game.stage, Stage.hatched);
    expect(game.eggId, egg);
    expect(app.snapshot['canStart'], isFalse);
    expect(await action('startEgg', {'tier': 'large'}), isFalse);
    now += 1799999;
    feed.sample(eta: 600);
    expect(game.eggId, egg);
    now += 1;
    feed.sample(eta: 600);
    expect(game.eggId, isNot(egg));
    expect(game.game.stage, Stage.incubating);
    expect(game.game.eggTier, EggTier.small);
    expect(feed.watches, 4);
  });
  test(
      'new-session pair closes old saved hatch without auto-minting another egg',
      () async {
    await hatchCurrent();
    expect(await action('pair', {'sessionId': sessionB, 'pairCode': '123456'}),
        isTrue);
    expect(game.game.stage, Stage.idle);
    expect(feed.watches, 3);
    expect((app.snapshot['egg'] as Map)['active'], isFalse);
    expect(app.snapshot['canStart'], isTrue);
    expect(await action('startEgg', {'tier': 'mid'}), isTrue);
    expect(feed.watches, 4);
    expect(game.game.stage, Stage.incubating);
    expect(game.game.eggTier, EggTier.mid);
  });
}
