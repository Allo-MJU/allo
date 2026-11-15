import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed, settle;
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('exact owned companion and place proposal survive full game heartbeat',
      () async {
    final dex = DexStore();
    final entry = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'owned-egg');
    await dex.add(entry);
    final camp = BaseCampController(store: CampMemory(), dex: dex);
    final feed = RoundFeed();
    final game = GameController(feed: feed, dex: dex, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await camp.load();
    await game.pair(sessionA, pairCode: '123456');
    final cid = camp.state.creatures.keys.single;
    expect(await game.selectCarCompanion(entry, creatureId: cid), true);
    expect(
        await game.proposeQuestTravel(
            'quest-1', 'coast', 'place_657e95d442eb2c13'),
        true);
    await settle();
    final json = feed.published.last.toJson();
    expect((json['companion'] as Map)['ownedCreatureId'], cid);
    expect(json['travelRequest'], {
      'wishId': 'quest-1',
      'targetRegion': 'coast',
      'targetPlaceId': 'place_657e95d442eb2c13'
    });
    feed.sample();
    await settle();
    expect(
        feed.published.last.toJson()['travelRequest'], json['travelRequest']);
  });
  test('unpaired phone cannot propose a route', () async {
    final game = GameController(feed: RoundFeed(), dex: DexStore());
    addTearDown(game.dispose);
    expect(
        await game.proposeQuestTravel(
            'quest-1', 'coast', 'place_657e95d442eb2c13'),
        false);
  });
  for (final profileMode in ['current', 'old', 'mismatched']) {
    test(
        'recreated phone validates same-species owned ID in $profileMode profile',
        () async {
      final dex = DexStore();
      final entries = List.generate(
          2,
          (i) => DexEntry(
              speciesId: 'road_sprout',
              obtainedAt: DateTime.utc(2026, 1, i + 1),
              envTags: [],
              regionTag: null,
              tier: 1,
              sourceEggId: 'restart-egg-$i'));
      for (final entry in entries) {
        await dex.add(entry);
      }
      final storage = CampMemory();
      var camp = BaseCampController(store: storage, dex: dex);
      var feed = RoundFeed();
      var game = GameController(feed: feed, dex: dex, baseCamp: camp);
      await camp.load();
      await game.pair(sessionA, pairCode: '123456');
      final cid = camp.state.creatures.keys.last;
      expect(
          await game.selectCarCompanion(entries.last, creatureId: cid), true);
      game.dispose();
      camp.dispose();
      if (profileMode != 'current') {
        final store = FishingStore();
        final profile = (await store.read())!;
        if (profileMode == 'old') {
          profile.remove('selectedOwnedCreatureId');
        } else {
          profile['selectedOwnedCreatureId'] = camp.state.creatures.keys.first;
        }
        await store.write(profile);
      }
      camp = BaseCampController(store: storage, dex: dex);
      feed = RoundFeed();
      game = GameController(feed: feed, dex: dex, baseCamp: camp);
      addTearDown(game.dispose);
      addTearDown(camp.dispose);
      await game.pair(sessionA, pairCode: '123456');
      await settle();
      expect(
          (feed.published.last.toJson()['companion'] as Map)['ownedCreatureId'],
          profileMode == 'mismatched' ? isNull : cid);
    });
  }
  test('recreated phone keeps the second of two identical legacy companions',
      () async {
    final dex = DexStore();
    final entry = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: [],
        regionTag: null,
        tier: 1);
    final raw = jsonEncode(entry.toJson());
    await (await SharedPreferences.getInstance())
        .setStringList('dex.entries.v1', [raw, raw]);
    final storage = CampMemory();
    var camp = BaseCampController(store: storage, dex: dex);
    var feed = RoundFeed();
    var game = GameController(feed: feed, dex: dex, baseCamp: camp);
    await camp.load();
    await game.pair(sessionA, pairCode: '123456');
    final ids = camp.state.creatures.keys.toList();
    expect(ids, hasLength(2));
    expect(await game.selectCarCompanion(entry, creatureId: ids.first), true);
    expect(await game.selectCarCompanion(entry, creatureId: ids.last), true);
    game.dispose();
    camp.dispose();

    camp = BaseCampController(store: storage, dex: dex);
    feed = RoundFeed();
    game = GameController(feed: feed, dex: dex, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    await settle();
    expect(
        (feed.published.last.toJson()['companion'] as Map)['ownedCreatureId'],
        ids.last);
  });
  test(
      'old ambiguous companion selection does not guess an owned ID on restart',
      () async {
    final dex = DexStore();
    final entry = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: [],
        regionTag: null,
        tier: 1);
    final raw = jsonEncode(entry.toJson());
    await (await SharedPreferences.getInstance())
        .setStringList('dex.entries.v1', [raw, raw]);
    final storage = CampMemory();
    var camp = BaseCampController(store: storage, dex: dex);
    var game = GameController(feed: RoundFeed(), dex: dex, baseCamp: camp);
    await camp.load();
    await game.pair(sessionA, pairCode: '123456');
    expect(await game.selectCarCompanion(entry), true);
    game.dispose();
    camp.dispose();
    final fishingStore = FishingStore();
    final oldProfile = (await fishingStore.read())!
      ..remove('selectedOwnedCreatureId');
    await fishingStore.write(oldProfile);

    camp = BaseCampController(store: storage, dex: dex);
    final feed = RoundFeed();
    game = GameController(feed: feed, dex: dex, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    await settle();
    final companion = feed.published.last.toJson()['companion'] as Map;
    expect(companion['speciesId'], 'road_sprout');
    expect(companion['ownedCreatureId'], isNull);
  });
}
