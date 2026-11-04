import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed, settle;
import 'session_resume_test.dart' show sessionA;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('region observes first valid signal after idle', () async {
    var now = 0;
    final feed = RoundFeed();
    final c =
        GameController(feed: feed, dex: DexStore(), monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: 119, tags: ['city']);
    now = 1000;
    feed.sample(eta: 120, tags: ['city']);
    for (var second = 1; second <= 60; second++) {
      now = 1000 + second * 1000;
      feed.sample(eta: 120, tags: [second < 31 ? 'city' : 'coast']);
    }
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect((await c.dex.all()).single.regionTag, 'city');
  });
  test('pause reset preserves recorded harsh', () async {
    var now = 0;
    final feed = RoundFeed();
    final c =
        GameController(feed: feed, dex: DexStore(), monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: null, distance: 0, harsh: 0);
    now = 1000;
    feed.sample(eta: null, distance: 1000, harsh: 8);
    await c.setAppActive(false);
    now = 100000;
    await c.setAppActive(true);
    feed.sample(eta: null, distance: 1000, harsh: 0);
    now = 101000;
    feed.sample(eta: null, distance: 5000, harsh: 0);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(c.game.tier, 1);
  });
}
