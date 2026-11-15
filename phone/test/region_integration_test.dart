import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed, settle;
import 'session_resume_test.dart' show sessionA;

class RegionFeed extends RoundFeed {
  final wire = <Map<String, dynamic>>[];
  @override
  Future<void> publishGame(GameState state) async {
    wire.add(state.toJson());
  }
}

class UnreadableDex extends DexStore {
  @override
  Future<List<DexEntry>> all() async => throw const FormatException('corrupt');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  var now = 0;
  late RegionFeed feed;
  late GameController c;
  Future<void> start({DexStore? store}) async {
    now = 0;
    feed = RegionFeed();
    c = GameController(
        feed: feed, dex: store ?? DexStore(), monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    await settle();
  }

  test(
      'empty collection is known and summary survives care, hatch and a long trip',
      () async {
    await start();
    expect(c.game.regionCollectionKnown, isTrue);
    expect(c.game.uncollectedRegions, ['coast', 'mountain', 'city']);
    final eggId = c.eggId;
    feed.sample();
    c.care();
    now = 40 * 60000;
    feed.sample();
    await settle();
    now = 70 * 60000;
    feed.sample(eta: 1200);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(c.eggId, eggId);
    expect((await c.dex.all()).single.sourceEggId, eggId);
    expect(c.game.regionCollectionKnown, isTrue);
    expect(feed.wire, isNotEmpty);
    expect(feed.wire.every((s) => s['regionCollectionKnown'] == true), isTrue);
  });

  test(
      'longest observed region replaces first tag and saved summary is published',
      () async {
    await start();
    feed.sample(eta: null, tags: ['coast']);
    now = 1000;
    feed.sample(eta: null, tags: ['city']);
    now = 2000;
    feed.sample(eta: null, tags: ['city']);
    now = 3000;
    feed.sample(eta: null, distance: 5000, tags: ['mountain']);
    await settle();
    expect((await c.dex.all()).single.regionTag, 'city');
    expect(c.game.uncollectedRegions, ['coast', 'mountain']);
    expect(feed.wire.last['uncollectedRegions'], ['coast', 'mountain']);
  });

  test('twenty second gap and duplicate signal cannot extend five second hold',
      () async {
    await start();
    feed.sample(eta: null, tags: ['city']);
    now = 4000;
    feed.sample(eta: null, tags: ['city'], duplicate: true);
    now = 20000;
    feed.sample(eta: null, distance: 5000);
    await settle();
    expect((await c.dex.all()).single.regionTag, isNull);
  });

  test(
      'paused wall time is not region time and old region is not held through resume',
      () async {
    await start();
    feed.sample(eta: null, tags: ['coast']);
    now = 1000;
    feed.sample(eta: null, distance: 1000, tags: ['city']);
    now = 3000;
    expect(await c.setAppActive(false), isTrue);
    now = 100000;
    expect(await c.setAppActive(true), isTrue);
    feed.sample(eta: null, distance: 1000, tags: ['city']);
    now = 101000;
    feed.sample(eta: null, distance: 5000, tags: ['city']);
    await settle();
    expect((await c.dex.all()).single.regionTag, 'city');
  });

  test('region checkpoint survives process restart', () async {
    await start();
    feed.sample(eta: null, tags: ['coast']);
    now = 1000;
    feed.sample(eta: null, distance: 1000, tags: ['city']);
    now = 4000;
    feed.sample(eta: null, distance: 3000, tags: ['city']);
    expect(await c.setAppActive(false), isTrue);
    final nextFeed = RegionFeed()..stamp = feed.stamp;
    var nextNow = 500000;
    final next = GameController(
        feed: nextFeed, dex: DexStore(), monotonicMs: () => nextNow);
    addTearDown(next.dispose);
    await next.pair(sessionA, pairCode: '123456');
    await next.startIncubating(EggTier.small);
    nextFeed.sample(eta: null, distance: 3000, tags: ['coast']);
    nextNow += 1000;
    nextFeed.sample(eta: null, distance: 5000, tags: ['coast']);
    await settle();
    expect((await next.dex.all()).single.regionTag, 'city');
  });

  test(
      'unreadable collection remains unknown instead of advertising all missing regions',
      () async {
    await start(store: UnreadableDex());
    feed.sample(eta: null);
    c.care();
    await settle();
    expect(c.game.regionCollectionKnown, isFalse);
    expect(feed.wire.last['regionCollectionKnown'], isFalse);
    expect(feed.wire.last.containsKey('uncollectedRegions'), isFalse);
  });
}
