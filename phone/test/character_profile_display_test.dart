import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_camp_controller_test.dart' show MemoryCampStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<UnityAppController> appWithSpecies(List<String> species) async {
    final dex = DexStore();
    for (var i = 0; i < species.length; i++) {
      await dex.add(DexEntry(
        speciesId: species[i],
        obtainedAt: DateTime.utc(2026, 11, 15),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'display-test-$i',
      ));
    }
    final camp = BaseCampController(store: MemoryCampStore(), dex: dex);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: dex,
        baseCamp: camp);
    final app = UnityAppController(game: game, camp: camp);
    addTearDown(() {
      app.dispose();
      game.dispose();
      camp.dispose();
    });
    expect(await app.initialize(), isTrue);
    return app;
  }

  test('unknown species sends empty display metadata without losing ownership',
      () async {
    final app = await appWithSpecies(['unknown_species']);
    final creature = (app.snapshot['creatures'] as List).single as Map;
    expect(creature['speciesId'], 'unknown_species');
    expect(creature['id'], isNot('unknown_species'));
    expect(creature['personaSummary'], '');
    expect(creature['personaTraits'], isEmpty);
  });

  test('owned instances receive their exact species display metadata',
      () async {
    final document = jsonDecode(
            await rootBundle.loadString('assets/data/character_profiles.json'))
        as Map;
    final profiles = {
      for (final profile in document['profiles'] as List)
        (profile as Map)['id']: profile
    };
    final app =
        await appWithSpecies(['road_sprout', 'puddle_pip', 'road_sprout']);
    final creatures = (app.snapshot['creatures'] as List).cast<Map>();
    expect(creatures.map((c) => c['id']).toSet(), hasLength(3));
    expect(
        creatures.where((c) => c['speciesId'] == 'road_sprout'), hasLength(2));
    expect(profiles['road_sprout']!['summary'],
        isNot(profiles['puddle_pip']!['summary']));
    for (final creature in creatures) {
      final profile = profiles[creature['speciesId']]!;
      expect(creature['personaSummary'], profile['summary']);
      expect(creature['personaTraits'], profile['traits']);
    }
  });

  test('bundled profiles cover the character catalog with display fields only',
      () async {
    final document = jsonDecode(
            await rootBundle.loadString('assets/data/character_profiles.json'))
        as Map;
    final catalog =
        jsonDecode(await rootBundle.loadString('assets/data/characters.json'))
            as Map;
    final legacy =
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map;
    expect(document.keys, unorderedEquals(['schemaVersion', 'profiles']));
    expect(document['schemaVersion'], 1);
    final profiles = (document['profiles'] as List).cast<Map>();
    expect(profiles, hasLength(18));
    expect(
        profiles.map((p) => p['id']),
        unorderedEquals({
          ...(catalog['species'] as List).map((c) => c['id']),
          ...(legacy['species'] as List).map((c) => c['id']),
        }));
    for (final profile in profiles) {
      expect(profile.keys, unorderedEquals(['id', 'summary', 'traits']));
      expect(profile['summary'], isA<String>());
      expect((profile['summary'] as String).trim(), isNotEmpty);
      expect(profile['traits'], isA<List>());
      final traits = profile['traits'] as List;
      expect(traits.length, inInclusiveRange(2, 3));
      expect(traits.every((t) => t is String && t.trim().isNotEmpty), isTrue);
    }
  });
}
