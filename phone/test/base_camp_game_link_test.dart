import 'dart:typed_data';
import 'package:allo_core/allo_core.dart';
import 'affinity_controller_test.dart' show DemoApi;
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

Future<void> drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('saved affinity hatch unlocks camp ownership without restart', () async {
    var now = 0;
    final camp = BaseCampController(store: SharedPreferencesBaseCampStore(profile: 'demo'), nowMs: () => now);
    final feed = RoundFeed();
    final game = GameController(feed: feed, dex: DexStore(), monotonicMs: () => now, baseCamp: camp, eggApi: DemoApi());
    addTearDown(game.dispose); addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    expect(await game.startIncubating(EggTier.small, useAffinity: true), isTrue);
    feed.sample(eta: 5400); await drain();
    for (var i=0; i<17; i++) { now=i*10000; await game.petEgg(); }
    expect(game.affinityRound!.phase, AffinityPhase.photoRequired);
    await game.uploadEggPhoto(Uint8List.fromList([1,2,3]));
    for (var i=0; i<12; i++) { now+=10000; await game.petEgg(); }
    await drain();
    expect(game.game.stage, Stage.hatched);
    expect(camp.state.creatures.length, 1);
    expect(camp.state.creatures.values.single.speciesId, game.hatched!.id);
  });
  test(
      'existing vehicle subscription earns camp materials and skips suspended distance',
      () async {
    var now = 0;
    final camp = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'demo'),
        nowMs: () => now);
    final feed = RoundFeed();
    final game = GameController(
        feed: feed, dex: DexStore(), monotonicMs: () => now, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    expect(await game.startIncubating(EggTier.small), isTrue);
    feed.sample(distance: 0);
    await drain();
    now = 1000;
    feed.sample(distance: 1000);
    await drain();
    expect(camp.state.materials[CampMaterial.wood], 1);
    expect(feed.watches, 1);
    await game.setAppActive(false);
    now = 10000;
    feed.sample(distance: 9000);
    await drain();
    await game.setAppActive(true);
    feed.sample(distance: 10000);
    await drain();
    expect(camp.state.materials[CampMaterial.wood], 1);
    now = 11000;
    feed.sample(distance: 11000);
    await drain();
    expect(camp.state.materials[CampMaterial.wood], 2);
    expect(feed.watches, 1);
  });
  test(
      'saved hatch becomes owned and lookOut earns only a bounded activity bonus',
      () async {
    var now = 0;
    final camp = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'demo'),
        nowMs: () => now);
    final feed = RoundFeed();
    final game = GameController(
        feed: feed, dex: DexStore(), monotonicMs: () => now, baseCamp: camp);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await game.pair(sessionA, pairCode: '123456');
    expect(await game.startIncubating(EggTier.small), isTrue);
    feed.sample(eta: 120);
    await drain();
    now = 60000;
    feed.sample(eta: 60);
    await drain();
    expect(game.game.stage, Stage.hatched);
    expect(camp.state.creatures.length, 1);
    final before = camp.state.materials[CampMaterial.wood]!;
    game.lookOut();
    await drain();
    expect(camp.state.materials[CampMaterial.wood], before + 1);
    game.lookOut();
    await drain();
    expect(camp.state.materials[CampMaterial.wood], before + 1);
    now = 120000;
    game.lookOut();
    await drain();
    expect(camp.state.materials[CampMaterial.wood], before + 2);
  });
}
