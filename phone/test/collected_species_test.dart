import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'recurring_incubation_test.dart' show RoundFeed, settle;
import 'session_resume_test.dart' show sessionA;

class CollectionStore extends DexStore {
  bool failRead = false;
  bool failSave = false;

  @override
  Future<List<DexEntry>> all() async {
    if (failRead) throw StateError('unreadable');
    return super.all();
  }

  @override
  Future<void> add(DexEntry entry) async {
    if (failSave) throw StateError('disk full');
    await super.add(entry);
  }
}

DexEntry entry(String id, {int year = 2026}) => DexEntry(
    speciesId: id,
    obtainedAt: DateTime(year),
    envTags: const [],
    tier: 1,
    regionTag: null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GameController> start(CollectionStore store, RoundFeed feed) async {
    final c = GameController(feed: feed, dex: store, monotonicMs: () => 0);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    return c;
  }

  test('saved species are deduplicated and unknown IDs cannot become friends',
      () async {
    final store = CollectionStore();
    await store.add(entry('road_sprout'));
    await store.add(entry('road_sprout', year: 2027));
    await store.add(entry('unknown'));
    final c = await start(store, RoundFeed());
    expect(c.collectedSpecies.map((s) => s.id), ['road_sprout']);
    c.collectedSpecies.clear();
    expect(c.collectedSpecies.map((s) => s.id), ['road_sprout']);
  });

  test('failed reload clears stale friends and a later reload restores them',
      () async {
    final store = CollectionStore();
    await store.add(entry('road_sprout'));
    final c = await start(store, RoundFeed());
    expect(c.collectedSpecies, isNotEmpty);
    store.failRead = true;
    await c.startIncubating(EggTier.small);
    expect(c.collectedSpecies, isEmpty);
    store.failRead = false;
    await c.startIncubating(EggTier.small);
    expect(c.collectedSpecies.map((s) => s.id), ['road_sprout']);
  });

  test('successful hatch notifies listeners of the newly saved friend',
      () async {
    final feed = RoundFeed();
    final c = await start(CollectionStore(), feed);
    final observed = <List<String>>[];
    c.addListener(
        () => observed.add(c.collectedSpecies.map((s) => s.id).toList()));
    feed.sample(eta: null);
    feed.sample(eta: null, distance: 5000);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(c.collectedSpecies.map((s) => s.id), [c.hatched!.id]);
    expect(observed.last, [c.hatched!.id]);
  });

  test(
      'failed hatch save excludes new friend and restored retry refreshes collection',
      () async {
    final store = CollectionStore();
    final feed = RoundFeed();
    final c = await start(store, feed);
    store.failSave = true;
    feed.sample(eta: null);
    feed.sample(eta: null, distance: 5000);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(c.collectedSpecies, isEmpty);
    expect(await c.setAppActive(false), isTrue);
    store.failSave = false;
    final restored = await start(store, RoundFeed());
    await settle();
    expect(restored.game.stage, Stage.hatched);
    expect(restored.collectedSpecies.map((s) => s.id), [c.hatched!.id]);
  });
}
