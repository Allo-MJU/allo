import 'dart:async';
import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed, settle;
import 'session_resume_test.dart' show sessionA, sessionB;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('completed catalog pays three once per trip across recreation',
      () async {
    final dex = DexStore();
    final data =
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>;
    final table = SpeciesTable.fromJson(data);
    for (final species in table.all) {
      await dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    (GameController, BaseCampController) make() {
      final camp =
          BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
      return (
        GameController(feed: RoundFeed(), dex: dex, baseCamp: camp),
        camp
      );
    }

    var (game, camp) = make();
    await game.pair(sessionA, pairCode: '123456');
    expect(game.collectionRewardForTrip, isTrue);
    expect(game.eggId, isNull);
    expect(camp.state.foodInventory['berry_snack'], 3);
    expect(await game.ensureTripEgg(), isTrue);
    expect(camp.state.foodInventory['berry_snack'], 3);
    game.dispose();
    camp.dispose();
    (game, camp) = make();
    await game.pair(sessionA, pairCode: '123456');
    expect(game.collectionRewardForTrip, isTrue);
    expect(camp.state.foodInventory['berry_snack'], 3);
    await game.pair(sessionB, pairCode: '123456');
    expect(camp.state.foodInventory['berry_snack'], 6);
    game.dispose();
    camp.dispose();
  });
  test('twelfth hatch trip gets no reward despite duplicate old ownership',
      () async {
    var now = 0;
    final dex = DexStore();
    final table = SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
    final last = table.all.last.id;
    for (final species in table.all.take(11)) {
      await dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    await dex.add(DexEntry(
        speciesId: table.all.first.id,
        obtainedAt: DateTime.utc(2025),
        envTags: [],
        regionTag: null,
        tier: 1));
    final camp =
        BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
    final feed = RoundFeed();
    final game = GameController(
        feed: feed, dex: dex, baseCamp: camp, monotonicMs: () => now);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    expect(game.eggId, isNotNull);
    expect(await game.startIncubating(EggTier.small), isTrue);
    feed.sample(eta: 120);
    await settle();
    now = 60000;
    feed.sample(eta: 60);
    await settle();
    expect(game.hatched?.id, last);
    expect((await dex.all()).map((e) => e.speciesId).toSet().length, 12);
    expect(game.collectionRewardForTrip, isFalse);
    expect(camp.state.foodInventory['berry_snack'] ?? 0, 0);
    expect(await game.ensureTripEgg(), isTrue);
    expect(camp.state.foodInventory['berry_snack'] ?? 0, 0);
    final restoredCamp =
        BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
    final restored =
        GameController(feed: RoundFeed(), dex: dex, baseCamp: restoredCamp);
    addTearDown(restored.dispose);
    addTearDown(restoredCamp.dispose);
    await restored.pair(sessionA, pairCode: '123456');
    expect(restored.collectionRewardForTrip, isFalse);
    expect(restoredCamp.state.foodInventory['berry_snack'] ?? 0, 0);
    await restored.pair(sessionB, pairCode: '123456');
    expect(restored.collectionRewardForTrip, isTrue);
    expect(restoredCamp.state.foodInventory['berry_snack'], 3);
  });

  test('completed demo trip survives recreation without a second reward',
      () async {
    final dex = DexStore();
    final table = SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
    for (final species in table.all) {
      await dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    (GameController, BaseCampController) make() {
      final camp =
          BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
      return (
        GameController(
            feed: FakeVehicleFeed(scenario: FakeScenario.clear),
            dex: dex,
            baseCamp: camp),
        camp
      );
    }

    var (game, camp) = make();
    expect(await game.ensureTripEgg(), isTrue);
    final trip = (await dex.tripEggLedger(true)).demoSessionId;
    expect(trip, isNotNull);
    expect(camp.state.foodInventory['berry_snack'], 3);
    game.dispose();
    camp.dispose();
    (game, camp) = make();
    expect(await game.ensureTripEgg(), isTrue);
    expect((await dex.tripEggLedger(true)).demoSessionId, trip);
    expect(camp.state.foodInventory['berry_snack'], 3);
    game.dispose();
    camp.dispose();
  });

  test('completed demo still records driving resources', () async {
    final dex = DexStore();
    final table = SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
    for (final species in table.all) {
      await dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    final camp =
        BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
    final feed = ControlledFake();
    final game = GameController(feed: feed, dex: dex, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    addTearDown(feed.close);
    expect(await game.ensureTripEgg(), isTrue);
    feed.sample(1, 0);
    await settle();
    feed.sample(2, 1000);
    for (var i = 0; i < 10; i++) {
      await settle();
    }
    expect(camp.state.materials[CampMaterial.wood], 1);
  });

  test(
      'unfinished old egg with complete catalog terminates without same trip reward',
      () async {
    final dex = DexStore();
    final table = SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
    for (final species in table.all.take(11)) {
      await dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    final initial = GameController(feed: RoundFeed(), dex: dex);
    await initial.pair(sessionA, pairCode: '123456');
    final id = initial.eggId;
    expect(await initial.endSession(), isTrue);
    initial.dispose();
    await dex.add(DexEntry(
        speciesId: table.all.last.id,
        obtainedAt: DateTime.utc(2026),
        envTags: [],
        regionTag: null,
        tier: 1));
    final camp =
        BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
    final game = GameController(feed: RoundFeed(), dex: dex, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionB, pairCode: '123456');
    expect(game.eggId, id);
    expect(game.game.stage, Stage.failed);
    expect(game.pairingNotice, contains('도감을 모두'));
    expect(camp.state.foodInventory['berry_snack'] ?? 0, 0);
    final nextCamp =
        BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
    final next =
        GameController(feed: RoundFeed(), dex: dex, baseCamp: nextCamp);
    addTearDown(next.dispose);
    addTearDown(nextCamp.dispose);
    await next.pair(sessionB, pairCode: '123456');
    expect(next.pairingNotice, contains('도감을 모두'));
    expect(nextCamp.state.foodInventory['berry_snack'] ?? 0, 0);
    await next.pair('b0c260a8-e807-42e9-a119-26119837113d', pairCode: '123456');
    expect(next.collectionRewardForTrip, isTrue);
    expect(nextCamp.state.foodInventory['berry_snack'], 3);
  });

  test('demo trip identity save failure grants nothing and retries', () async {
    final dex = FailingLedgerDex();
    final table = SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
    for (final species in table.all) {
      await dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    final camp =
        BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: dex,
        baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    dex.fail = true;
    expect(await game.ensureTripEgg(), isFalse);
    expect(game.collectionRewardForTrip, isFalse);
    expect(camp.state.foodInventory['berry_snack'] ?? 0, 0);
    dex.fail = false;
    expect(await game.ensureTripEgg(), isTrue);
    expect(camp.state.foodInventory['berry_snack'], 3);
    expect((await dex.tripEggLedger(true)).demoSessionId, isNotNull);
  });

  test('dex read failure blocks egg and reward until retry', () async {
    final dex = FailingDex()..fail = true;
    final camp =
        BaseCampController(store: SharedPreferencesBaseCampStore(), dex: dex);
    final game = GameController(feed: RoundFeed(), dex: dex, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    expect(game.eggId, isNull);
    expect(game.collectionRewardForTrip, isFalse);
    dex.fail = false;
    expect(await game.ensureTripEgg(), isTrue);
    expect(game.eggId, isNotNull);
  });

  test('failed camp write remains retryable without duplicate award', () async {
    final dex = DexStore();
    final table = SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
    for (final species in table.all) {
      await dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    final store = FailingRewardStore();
    final camp = BaseCampController(store: store, dex: dex);
    final game = GameController(feed: RoundFeed(), dex: dex, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    store.failReward = true;
    await game.pair(sessionA, pairCode: '123456');
    expect(game.collectionRewardForTrip, isFalse);
    expect(camp.state.foodInventory['berry_snack'] ?? 0, 0);
    store.failReward = false;
    expect(await game.ensureTripEgg(), isTrue);
    expect(game.collectionRewardForTrip, isTrue);
    expect(camp.state.foodInventory['berry_snack'], 3);
    expect(await game.ensureTripEgg(), isTrue);
    expect(camp.state.foodInventory['berry_snack'], 3);
  });
}

class FailingRewardStore implements BaseCampStore {
  final inner = SharedPreferencesBaseCampStore();
  bool failReward = false;
  @override
  Future<Map<String, dynamic>?> load() => inner.load();
  @override
  Future<void> save(Map<String, dynamic> value) {
    final core = value['core'] as Map<String, dynamic>;
    if (failReward && (core['collectionRewardTripIds'] as List).isNotEmpty) {
      throw StateError('save failed');
    }
    return inner.save(value);
  }
}

class FailingDex extends DexStore {
  bool fail = false;
  @override
  Future<List<DexEntry>> all() {
    if (fail) throw StateError('read failed');
    return super.all();
  }
}

class FailingLedgerDex extends DexStore {
  bool fail = false;
  @override
  Future<void> saveTripEggLedger(bool demo, TripEggLedger ledger) {
    if (fail) throw StateError('ledger failed');
    return super.saveTripEggLedger(demo, ledger);
  }
}

class ControlledFake extends FakeVehicleFeed {
  ControlledFake() : super(scenario: FakeScenario.clear);
  final controller = StreamController<VehicleState>.broadcast();
  @override
  Stream<VehicleState> watch() => controller.stream;
  void sample(int ts, double distance) => controller.add(VehicleState.fromJson({
        'ts': ts,
        'gear': 'D',
        'distanceM': distance,
        'envTags': <String>[],
        'capabilities': ['odometer']
      }));
  Future<void> close() => controller.close();
}
