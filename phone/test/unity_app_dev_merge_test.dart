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
}
