import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:allo_phone/unity_app/village_selection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'unity_app_controller_test.dart' show CampMemory;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

class FailingVillageStore extends PreferencesVillageSelectionStore {
  bool failRead = false, failWrite = false;
  @override
  Future<List<String>?> read(String profile) async {
    if (failRead) throw StateError('disk unavailable');
    return super.read(profile);
  }

  @override
  Future<void> write(String profile, List<String> ids) async {
    if (failWrite) throw StateError('disk full');
    return super.write(profile, ids);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late BaseCampController camp;
  late UnityAppController app;
  var request = 0;
  Future<bool> select(List<dynamic> ids) => app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'village-${request++}',
        'action': 'setVillageFriends',
        'creatureIds': ids,
      }));
  Future<void> add(int n) async {
    await game.dex.add(DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026, 1, n + 1),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'egg-$n'));
    await camp.refreshOwnership();
  }

  Future<void> start(
      {String profile = 'default',
      String namespace = '',
      bool fake = true}) async {
    final dex = DexStore(namespace: namespace, profile: profile);
    camp = BaseCampController(store: CampMemory(), dex: dex);
    game = GameController(
        feed:
            fake ? FakeVehicleFeed(scenario: FakeScenario.clear) : RoundFeed(),
        dex: dex,
        baseCamp: camp);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
  }

  void stop() {
    app.dispose();
    game.dispose();
    camp.dispose();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    request = 0;
    await start();
  });
  tearDown(stop);
  test(
      'completed catalogue test connection grants only three for the same trip',
      () async {
    final table = SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
    for (final species in table.all) {
      await game.dex.add(DexEntry(
          speciesId: species.id,
          obtainedAt: DateTime.utc(2026),
          envTags: [],
          regionTag: null,
          tier: 1));
    }
    await camp.refreshOwnership();
    Future<bool> testPair() => app.handleMessage(jsonEncode({
          'v': 1,
          'type': 'appAction',
          'requestId': 'completed-test-${request++}',
          'action': 'testPair'
        }));
    app.view = 'pairing';
    expect(await testPair(), true);
    expect(game.collectionRewardForTrip, true);
    expect(game.eggId, isNull);
    expect(camp.state.foodInventory['berry_snack'], 3);
    app.view = 'pairing';
    expect(await testPair(), true);
    expect(camp.state.foodInventory['berry_snack'], 3);
  });
  test(
      'legacy defaults first four exact owned IDs, including duplicate species',
      () async {
    for (var n = 0; n < 5; n++) {
      await add(n);
    }
    expect(app.snapshot['villageCreatureIds'],
        camp.state.creatures.keys.take(4).toList());
    expect(await select(camp.state.creatures.keys.skip(1).toList()), true);
    expect(app.snapshot['villageCreatureIds'],
        camp.state.creatures.keys.skip(1).toList());
  });
  test('paired village choices publish ordered species and explicit empty',
      () async {
    stop();
    await start(fake: false);
    await add(0);
    await add(1);
    await game.dex.add(DexEntry(
        speciesId: 'tide_keeper',
        obtainedAt: DateTime.utc(2026, 2),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'sea'));
    await camp.refreshOwnership();
    await game.pair(sessionA, pairCode: '123456');
    final feed = game.feed as RoundFeed;
    Map summary() => feed.published.last.toJson()['collectionSummary'] as Map;
    await Future<void>.delayed(Duration.zero);
    expect(summary()['villageSpeciesIds'], ['road_sprout', 'tide_keeper']);
    expect(summary()['villageSpeciesCount'], 2);
    final ids = camp.state.creatures.keys.toList();
    expect(await select([ids.last, ids.first]), true);
    await Future<void>.delayed(Duration.zero);
    expect(summary()['villageSpeciesIds'], ['tide_keeper', 'road_sprout']);
    expect(await select([]), true);
    await Future<void>.delayed(Duration.zero);
    expect(summary()['villageSpeciesIds'], isEmpty);
    expect(summary()['villageSpeciesCount'], 0);
    await add(2);
    await Future<void>.delayed(Duration.zero);
    expect(summary()['villageSpeciesCount'], 0);
  });

  test('failed village save never changes the published vehicle choice',
      () async {
    stop();
    await start(fake: false);
    await add(0);
    app.dispose();
    final store = FailingVillageStore();
    app = UnityAppController(
        game: game, camp: camp, villageSelectionStore: store);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    final feed = game.feed as RoundFeed;
    await Future<void>.delayed(Duration.zero);
    expect(
        (feed.published.last.toJson()['collectionSummary']
            as Map)['villageSpeciesIds'],
        ['road_sprout']);
    store.failWrite = true;
    expect(await select([]), false);
    await Future<void>.delayed(Duration.zero);
    expect(
        (feed.published.last.toJson()['collectionSummary']
            as Map)['villageSpeciesIds'],
        ['road_sprout']);
  });

  test('unreadable saved choice omits vehicle fields until retry succeeds',
      () async {
    stop();
    await start(fake: false);
    await add(0);
    app.dispose();
    final store = FailingVillageStore()..failRead = true;
    app = UnityAppController(
        game: game, camp: camp, villageSelectionStore: store);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
    final feed = game.feed as RoundFeed;
    Map summary() => feed.published.last.toJson()['collectionSummary'] as Map;
    await Future<void>.delayed(Duration.zero);
    expect(summary().containsKey('villageSpeciesCount'), false);
    expect(summary().containsKey('villageSpeciesIds'), false);
    store.failRead = false;
    expect(
        await app.handleMessage(jsonEncode({
          'v': 1,
          'type': 'appAction',
          'requestId': 'retry-village',
          'action': 'refresh',
        })),
        true);
    await Future<void>.delayed(Duration.zero);
    expect(summary()['villageSpeciesCount'], 1);
    expect(summary()['villageSpeciesIds'], ['road_sprout']);
  });

  test('explicit empty persists across reload and newly collected friends',
      () async {
    await add(0);
    expect(await select([]), true);
    await add(1);
    expect(app.snapshot['villageCreatureIds'], isEmpty);
    stop();
    await start();
    expect(app.snapshot['villageCreatureIds'], isEmpty);
  });
  test(
      'unknown, repeated, malformed and five IDs never replace confirmed selection',
      () async {
    for (var n = 0; n < 5; n++) {
      await add(n);
    }
    final ids = camp.state.creatures.keys.toList();
    expect(await select([ids[4]]), true);
    for (final invalid in [
      [ids[0], ids[0]],
      ['unknown'],
      ids,
      [null],
      [12]
    ]) {
      expect(await select(invalid), false);
      expect(app.snapshot['villageCreatureIds'], [ids[4]]);
    }
  });
  test('save failure keeps prior confirmed IDs and permits retry', () async {
    await add(0);
    await add(1);
    app.dispose();
    final store = FailingVillageStore();
    app = UnityAppController(
        game: game, camp: camp, villageSelectionStore: store);
    await app.initialize();
    final ids = camp.state.creatures.keys.toList();
    expect(await select([ids.first]), true);
    store.failWrite = true;
    expect(await select([ids.last]), false);
    expect(app.snapshot['villageCreatureIds'], [ids.first]);
    expect(app.snapshot['error'], contains('저장하지 못했어요'));
    store.failWrite = false;
    expect(await select([ids.last]), true);
    app.dispose();
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    expect(app.snapshot['villageCreatureIds'], [ids.last]);
  });
  test('load failure does not invent defaults and refresh permits recovery',
      () async {
    await add(0);
    app.dispose();
    final store = FailingVillageStore()..failRead = true;
    app = UnityAppController(
        game: game, camp: camp, villageSelectionStore: store);
    await app.initialize();
    expect(app.snapshot['villageSelectionReady'], false);
    expect(app.snapshot['villageCreatureIds'], isEmpty);
    expect(await select([]), false);
    store.failRead = false;
    expect(
        await app.handleMessage(jsonEncode({
          'v': 1,
          'type': 'appAction',
          'requestId': 'refresh-village',
          'action': 'refresh'
        })),
        true);
    expect(app.snapshot['villageSelectionReady'], true);
    expect(
        app.snapshot['villageCreatureIds'], camp.state.creatures.keys.toList());
  });
  test('saved IDs are isolated by namespace, profile and real or demo feed',
      () async {
    await add(0);
    expect(await select([]), true);
    for (final variant in [
      (profile: 'other', namespace: '', fake: true),
      (profile: 'default', namespace: 'other.', fake: true),
      (profile: 'default', namespace: '', fake: false)
    ]) {
      stop();
      await start(
          profile: variant.profile,
          namespace: variant.namespace,
          fake: variant.fake);
      if (camp.state.creatures.isEmpty) await add(0);
      expect(app.snapshot['villageCreatureIds'],
          camp.state.creatures.keys.toList());
    }
    stop();
    await start();
    expect(app.snapshot['villageCreatureIds'], isEmpty);
  });
}
