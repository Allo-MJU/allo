import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'affinity_controller_test.dart' show DemoApi;
import 'fishing_feed_integration_test.dart' show MemoryFishingStore;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;
import 'base_camp_controller_test.dart' show MemoryCampStore;

class CountingLoadStore extends CampMemory {
  int saves = 0;
  final gate = Completer<void>();
  @override
  Future<void> save(Map<String, dynamic> value) async {
    await gate.future;
    saves++;
    await super.save(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'merged affinity, saved camp and fishing compose while disconnect stops both feeds',
      () async {
    var now = 0;
    final dex = DexStore(profile: 'unity-demo-examples');
    final owned = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026, 11, 12),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'merge-owned');
    await dex.add(owned);
    final camp = BaseCampController(
        store: CampMemory(),
        dex: dex,
        nowMs: () => DateTime.utc(2026).millisecondsSinceEpoch + now);
    final feed = RoundFeed();
    final game = GameController(
        feed: feed,
        dex: dex,
        baseCamp: camp,
        fishingStore: MemoryFishingStore(),
        eggApi: DemoApi(),
        monotonicMs: () => now);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    expect(await game.selectCarCompanion(owned), isTrue);
    expect(
        await game.startIncubating(EggTier.small, useAffinity: true), isTrue);
    feed.sample();
    await camp.tick();
    now = 1000;
    feed.sample(distance: 2000);
    await camp.tick();
    expect(await game.petEgg(), EggFeedback.positive);
    await game.fishing.settled;
    await Future<void>.delayed(Duration.zero);
    final state = feed.published.last.toJson();
    expect((state['affinity'] as Map)['score'], 3);
    expect((state['companion'] as Map)['speciesId'], 'road_sprout');
    expect(state['contractVersion'], 2);
    expect(state['gameRevision'], isA<int>());
    expect(state['fishing'], isA<Map>());
    expect(camp.state.materials[CampMaterial.wood], 2);
    expect(camp.state.creatures, hasLength(1));
    final watches = feed.watches;
    final stamp = game.vehicle!.ts;
    expect(await game.disconnect(), isTrue);
    await game.fishing.settled;
    expect(game.paired, isFalse);
    expect(game.fishing.initialized, isFalse);
    expect(feed.watches, watches);
    now += 10000;
    feed.sample(distance: 5000);
    await camp.tick();
    expect(game.vehicle!.ts, stamp);
    expect(camp.state.materials[CampMaterial.wood], 2);
    expect(await game.petEgg(), EggFeedback.none);
  });
  test(
      'profiled fishing keeps existing default storage and isolates demo writes',
      () async {
    final real = FishingStore();
    final demo = FishingStore(profile: 'unity-demo-examples');
    const original = {'version': 1, 'selected': 'original-real'};
    await real.write(original);
    expect(await demo.read(), isNull);
    await demo.write({'version': 1, 'selected': 'demo-example'});
    expect(await real.read(), original);
    expect(await FishingStore(profile: 'unity-demo-examples').read(),
        {'version': 1, 'selected': 'demo-example'});
    expect((await SharedPreferences.getInstance()).getString(FishingStore.key),
        isNotNull);
    expect(() => FishingStore(profile: '../default'), throwsArgumentError);
  });
  test('concurrent camp initialization shares one saved load', () async {
    final store = CountingLoadStore();
    final camp = BaseCampController(store: store);
    addTearDown(camp.dispose);
    final first = camp.load();
    final second = camp.load();
    store.gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(store.saves, 1);
    expect(await camp.load(), isTrue); // A later explicit reload still works.
    expect(store.saves, 2);
  });
  test('namespace DI composes with demo profile without changing existing keys',
      () async {
    final namespaced = DexStore(namespace: 'local.firebase.');
    final samples = DexStore(profile: 'unity-demo-examples');
    final combined =
        DexStore(namespace: 'local.firebase.', profile: 'unity-demo-examples');
    DexEntry entry(String source) => DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: source);
    await namespaced.add(entry('namespaced'));
    await samples.add(entry('samples'));
    expect(await combined.all(), isEmpty);
    await combined.add(entry('combined'));
    expect((await namespaced.allRecords()).single['sourceEggId'], 'namespaced');
    expect((await samples.allRecords()).single['sourceEggId'], 'samples');
    expect((await combined.allRecords()).single['sourceEggId'], 'combined');
    expect(await DexStore().all(), isEmpty);
    final legacyFishing = FishingStore(namespace: 'local.firebase.');
    final sampleFishing = FishingStore(profile: 'unity-demo-examples');
    final combinedFishing = FishingStore(
        namespace: 'local.firebase.', profile: 'unity-demo-examples');
    await legacyFishing.write({'selection': 'namespaced'});
    await sampleFishing.write({'selection': 'samples'});
    expect(await combinedFishing.read(), isNull);
    await combinedFishing.write({'selection': 'combined'});
    expect(await legacyFishing.read(), {'selection': 'namespaced'});
    expect(await sampleFishing.read(), {'selection': 'samples'});
    expect(await combinedFishing.read(), {'selection': 'combined'});
  });
  test('camp load recovery during disconnect cannot resurrect a vehicle watch',
      () async {
    final store = MemoryCampStore()..failSave = true;
    final camp = BaseCampController(store: store);
    final feed = RoundFeed();
    final game = GameController(
        feed: feed,
        dex: DexStore(),
        baseCamp: camp,
        fishingStore: MemoryFishingStore());
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    expect(camp.ready, isFalse);
    final pairedWatches = feed.watches;
    expect(pairedWatches, 1); // Pairing now starts the one trip egg subscription.
    store.failSave = false;
    store.block = Completer<void>();
    final retry = camp.load();
    game.addListener(() {
      if (game.busy && !store.block!.isCompleted) store.block!.complete();
    });
    expect(await game.disconnect(), isTrue);
    expect(await retry, isTrue);
    expect(camp.ready, isTrue);
    expect(game.paired, isFalse);
    expect(feed.watches, pairedWatches);
    expect(feed.signals.hasListener, isFalse);
  });
}
