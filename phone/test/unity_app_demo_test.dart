import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/app.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/feed/vehicle_feed.dart';
import 'package:allo_phone/fishing/fishing_controller.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late void Function(String) receive;
  Future<Map<String, dynamic>> launch(WidgetTester tester, VehicleFeed feed,
      {required bool enabled}) async {
    rootBundle.evict('assets/data/species.json');
    rootBundle.evict('assets/data/characters.json');
    rootBundle.evict('assets/data/window_stories_ko.json');
    rootBundle.evict('assets/data/companion_learning.json');
    Map<String, dynamic>? current;
    Map<String, dynamic>? lastMessage;
    await tester.pumpWidget(AlloApp(
        feed: feed,
        useUnityApp: true,
        demoCreatures: enabled,
        unityView: ({required onCreated, required onMessage}) {
          receive = onMessage;
          onCreated((json) {
            final message = jsonDecode(json) as Map<String, dynamic>;
            if (message['type'] == 'app') lastMessage = message;
            if (message['type'] == 'app' &&
                ((message['ready'] == true && message['busy'] == false) ||
                    message['error'] != '')) {
              current = message;
            }
          });
          return const SizedBox();
        }));
    await tester.pumpAndSettle();
    receive('{"type":"ready"}');
    // New trip preparation spans asset I/O and fake-zone storage callbacks.
    for (var i = 0; i < 500 && current == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(current, isNotNull,
        reason: 'Unity app did not finish automatic trip preparation: ${jsonEncode(lastMessage)}');
    expect(current!['ready'], isTrue, reason: current!['error'] as String);
    await tester.pump();
    return current!;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('sample flag off and real feeds never create sample ownership',
      (tester) async {
    final off = await launch(
        tester, FakeVehicleFeed(scenario: FakeScenario.clear),
        enabled: false);
    expect(off['creatures'], isEmpty);
    await close(tester);
    final real = await launch(tester, RoundFeed(), enabled: true);
    expect(real['isDemo'], isFalse);
    expect(real['creatures'], isEmpty);
    expect(await DexStore().all(), isEmpty);
    await close(tester);
  });
  testWidgets(
      'opt-in fake samples use real canonical assets, all roles and zero materials',
      (tester) async {
    final snapshot = await launch(
        tester, FakeVehicleFeed(scenario: FakeScenario.clear),
        enabled: true);
    expect(snapshot['ready'], isTrue, reason: jsonEncode(snapshot));
    expect(snapshot['isDemo'], isTrue);
    final creatures = snapshot['creatures'] as List;
    expect(creatures.map((c) => c['speciesId']).toSet(),
        {'road_sprout', 'puddle_pip', 'lamp_moth', 'highway_comet'});
    expect(creatures.map((c) => c['role']).toSet(),
        {'builder', 'cook', 'trainer'});
    for (final creature in creatures) {
      expect(creature['sprite'], 'species/${creature['speciesId']}.png');
      expect(
          (await tester.runAsync(
                  () => rootBundle.load('assets/${creature['sprite']}')))!
              .lengthInBytes,
          greaterThan(0));
    }
    expect((snapshot['materials'] as List).map((m) => m['count']),
        everyElement(0));
    for (final role in ['builder', 'cook', 'trainer']) {
      final worker = creatures.firstWhere((c) => c['role'] == role);
      receive(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'assign-$role',
        'action': 'assign',
        'role': role,
        'creatureId': worker['id']
      }));
      await tester.pumpAndSettle();
    }
    final camp =
        await SharedPreferencesBaseCampStore(profile: 'unity-demo-examples')
            .load();
    expect((camp!['core'] as Map)['assignments'], hasLength(3));

    await close(tester);
  });
  testWidgets(
      'repeated launches retain stable ownership IDs and preserve original profiles',
      (tester) async {
    final original = DexStore();
    await original.add(DexEntry(
        speciesId: 'sea_mist',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 3,
        sourceEggId: 'earned-original'));
    final examples = DexStore(profile: 'unity-demo-examples');
    await examples.add(DexEntry(
        speciesId: 'sea_mist',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 3,
        sourceEggId: 'earned-example-profile'));
    final originalCamp = SharedPreferencesBaseCampStore(profile: 'demo');
    await originalCamp.save({'preserve': 'existing demo'});
    final productionFishingStore = FishingStore();
    final productionFishing =
        FishingController(store: productionFishingStore, onChanged: () {});
    await productionFishing.attach(sessionA);
    await productionFishing.select((await original.all()).single);
    final productionProfile = (await productionFishingStore.read())!;
    final checkpoint = (productionProfile['entries']
        as Map)[productionProfile['selected']] as Map<String, dynamic>;
    checkpoint.addAll({
      'state': 'paused',
      'activityId': 'existing-production-activity',
      'elapsedMs': 23000,
      'totalRecords': 2
    });
    await productionFishingStore.write(productionProfile);
    await productionFishing
        .attach(sessionA); // Verify the saved checkpoint is valid.
    expect(productionFishing.error, isNull);
    productionFishing.dispose();
    final prefs = await SharedPreferences.getInstance();
    final productionRaw = prefs.getString(FishingStore.key);
    expect(productionRaw, isNotNull);
    final first = await launch(
        tester, FakeVehicleFeed(scenario: FakeScenario.clear),
        enabled: true);
    final ids = (first['creatures'] as List).map((c) => c['id']).toList();
    receive(jsonEncode({
      'v': 1,
      'type': 'appAction',
      'requestId': 'pair-example-profile',
      'action': 'pair',
      'sessionId': sessionA,
      'pairCode': '123456'
    }));
    await tester.pumpAndSettle();
    final demoFishing =
        await FishingStore(profile: 'unity-demo-examples').read();
    expect(demoFishing,
        isNotNull); // The actual app paired and attached its demo store.
    final demoSession = demoFishing!['session'];
    expect(demoSession, startsWith('demo-'));
    expect(demoFishing['selected'], isNull);
    expect(demoFishing['entries'], isEmpty);
    await prefs.reload();
    expect(prefs.getString(FishingStore.key), productionRaw);
    final demoCamp =
        (await SharedPreferencesBaseCampStore(profile: 'unity-demo-examples')
            .load())!['core'] as Map;
    expect(demoCamp['creatures'], hasLength(5));
    expect((demoCamp['materials'] as Map).values, everyElement(0));
    await close(tester);
    final second = await launch(
        tester, FakeVehicleFeed(scenario: FakeScenario.clear),
        enabled: true);
    expect((second['creatures'] as List).map((c) => c['id']).toList(), ids);
    expect(
        (await FishingStore(profile: 'unity-demo-examples').read())!['session'],
        demoSession);
    expect(
        (await DexStore(profile: 'unity-demo-examples').all()), hasLength(5));
    expect((await original.all()).single.sourceEggId, 'earned-original');
    expect(await originalCamp.load(), {'preserve': 'existing demo'});
    await prefs.reload();
    expect(prefs.getString(FishingStore.key), productionRaw);
    await close(tester);
  });
  test('profile ownership and progress cannot overwrite default storage',
      () async {
    final original = DexStore();
    final examples = DexStore(profile: 'unity-demo-examples');
    await original.add(DexEntry(
        speciesId: 'sea_mist',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 3,
        sourceEggId: 'original'));
    await original.setCarriedDistance(EggTier.small, 42);
    expect(await examples.all(), isEmpty);
    expect(await examples.carriedDistance(EggTier.small), 0);
    await examples.setCarriedDistance(EggTier.small, 99);
    expect(await original.carriedDistance(EggTier.small), 42);
    expect(() => DexStore(profile: '../default'), throwsArgumentError);
  });
  testWidgets('legacy Flutter host ignores sample flag even for a fake feed',
      (tester) async {
    await tester.pumpWidget(AlloApp(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        useUnityApp: false,
        demoCreatures: true));
    await tester.pumpAndSettle();
    expect(await DexStore().all(), isEmpty);
    expect(await DexStore(profile: 'unity-demo-examples').all(), isEmpty);
    await close(tester);
  });
}
