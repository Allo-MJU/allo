import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

class ManualFake extends FakeVehicleFeed {
  ManualFake() : super(scenario: FakeScenario.rough);
  final signals = StreamController<VehicleState>.broadcast(sync: true);
  @override
  Stream<VehicleState> watch() => signals.stream;
  void sample(double distance, int harsh, int stamp) =>
      signals.add(VehicleState.fromJson({
        'ts': stamp,
        'gear': 'D',
        'distanceM': distance,
        'harshBrake': harsh,
        'capabilities': ['odometer'],
      }));
  @override
  Future<void> dispose() async {
    await signals.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('deferred first egg excludes idle distance', () async {
    final feed = RoundFeed();
    final c = GameController(feed: feed, dex: DexStore(), monotonicMs: () => 0);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: 119, distance: 6000);
    expect(c.game.stage, Stage.idle);
    feed.sample(eta: null, distance: 7000);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.progress, 0);
  });
  test('distance while inactive is not credited on resume', () async {
    final feed = RoundFeed();
    final c = GameController(feed: feed, dex: DexStore(), monotonicMs: () => 0);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: null, distance: 0);
    feed.sample(eta: null, distance: 1000);
    await c.setAppActive(false);
    feed.sample(eta: null, distance: 6000);
    await c.setAppActive(true);
    feed.sample(eta: null, distance: 6000);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.progress, .2);
  });
  test('fake restart keeps previous harsh judgment', () async {
    final store = DexStore();
    final firstFeed = ManualFake();
    final first =
        GameController(feed: firstFeed, dex: store, monotonicMs: () => 0);
    await first.startIncubating(EggTier.small);
    firstFeed.sample(0, 0, 1);
    firstFeed.sample(2000, 8, 2);
    await first.setAppActive(false);
    first.dispose();
    final nextFeed = ManualFake();
    final next =
        GameController(feed: nextFeed, dex: store, monotonicMs: () => 0);
    addTearDown(next.dispose);
    await next.startIncubating(EggTier.small);
    nextFeed.sample(0, 0, 3);
    nextFeed.sample(3000, 0, 4);
    expect(next.game.stage, Stage.hatched);
    expect(next.game.tier, 1);
  });
}
