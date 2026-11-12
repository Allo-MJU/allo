import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed, settle;
import 'session_resume_test.dart' show sessionA;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('동행 중 새 차량 신호는 주기적으로 같은 펫 상태를 재발행한다', () async {
    SharedPreferences.setMockInitialValues({});
    var now = 0;
    final feed = RoundFeed();
    final c =
        GameController(feed: feed, dex: DexStore(), monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: 600);
    now = 300000;
    feed.sample(eta: 300);
    await settle();
    expect(c.game.stage, Stage.hatched);
    final species = c.game.speciesId;
    final count = feed.published.length;
    now += 2999;
    feed.sample(eta: 297);
    await settle();
    expect(feed.published.length, count);
    now += 1;
    feed.sample(eta: 297);
    await settle();
    expect(feed.published.length, count + 1);
    expect(feed.published.last.stage, Stage.hatched);
    expect(feed.published.last.speciesId, species);
    await c.setAppActive(false);
    final paused = feed.published.length;
    now += 10000;
    feed.sample(eta: 280);
    await settle();
    expect(feed.published.length, paused);
  });
}
