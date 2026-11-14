import 'dart:async';
import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/feed/vehicle_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed;
import 'unity_app_controller_test.dart' show CampMemory;

class ManualDemoFeed extends FakeVehicleFeed {
  ManualDemoFeed() : super(scenario: FakeScenario.clear);
  final samples = StreamController<VehicleState>.broadcast(sync: true);
  int watches = 0, stamp = 0;
  @override
  Stream<VehicleState> watch() {
    watches++;
    return samples.stream;
  }

  void sample({int? eta = 600}) => samples.add(VehicleState.fromJson({
        'ts': ++stamp,
        'gear': 'D',
        'etaSec': eta,
        'distanceM': 0,
        'harshBrake': 0,
        'envTags': <String>[],
        'capabilities': ['odometer']
      }));
  @override
  Future<void> dispose() async {
    await samples.close();
    await super.dispose();
  }
}

class FailingDemoProgress extends DexStore {
  bool fail = false;
  @override
  Future<void> saveTripEggLedger(bool demo, TripEggLedger ledger) {
    if (fail) throw StateError('disk full');
    return super.saveTripEggLedger(demo, ledger);
  }

  @override
  Future<void> saveTripProgress(
      bool demo, EggTier tier, IncubationProgress value) {
    if (fail) throw StateError('disk full');
    return super.saveTripProgress(demo, tier, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late BaseCampController camp;
  late UnityAppController app;
  late VehicleFeed feed;
  var now = 0, sequence = 0;
  Future<void> boot({DexStore? store, VehicleFeed? source}) async {
    feed = source ?? ManualDemoFeed();
    final dex = store ?? DexStore();
    camp = BaseCampController(store: CampMemory(), dex: dex);
    game = GameController(
        feed: feed, dex: dex, baseCamp: camp, monotonicMs: () => now);
    app = UnityAppController(game: game, camp: camp);
    expect(await app.initialize(), true);
    app.view = 'pairing';
  }

  void close() {
    app.dispose();
    game.dispose();
    camp.dispose();
  }

  Future<bool> action(String name) => app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'test-pair-${sequence++}',
        'action': name,
        if (name == 'pair') ...{
          'sessionId': '00000000-0000-4000-8000-000000000001',
          'pairCode': '000000'
        }
      }));
  Future<String> failAndSave() async {
    expect(await action('pair'), true);
    (feed as ManualDemoFeed).sample();
    await Future<void>.delayed(Duration.zero);
    now += const Duration(hours: 1).inMilliseconds;
    (feed as ManualDemoFeed).sample();
    await Future<void>.delayed(Duration.zero);
    expect(game.game.stage, Stage.failed);
    final id = game.eggId!;
    expect(await game.endSession(), true);
    return id;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = sequence = 0;
    await boot();
  });
  tearDown(close);

  test('test connection grants one active egg and repeated clicks preserve it',
      () async {
    expect(await action('testPair'), true);
    final egg = game.eggId;
    expect(egg, isNotNull);
    expect((app.snapshot['egg'] as Map)['active'], true);
    expect(app.view, 'cabin');
    app.view = 'pairing';
    expect(await action('testPair'), true);
    expect(game.eggId, egg);
    expect((feed as ManualDemoFeed).watches, 1);
  });

  test(
      'received vehicle samples without ETA are not labelled as waiting for connection',
      () async {
    expect(await action('testPair'), true);
    (feed as ManualDemoFeed).sample(eta: null);
    await Future<void>.delayed(Duration.zero);
    expect(game.vehicle, isNotNull);
    expect(game.affinityRound, isNotNull);
    expect((app.snapshot['egg'] as Map)['remainingLabel'], '도착 시간 정보가 없어요');
  });

  test('test connection replaces a restored failed demo trip with one new egg',
      () async {
    final previous = await failAndSave();
    final dex = game.dex;
    close();
    await boot(store: dex);
    expect(game.game.stage, Stage.idle);
    expect(await action('testPair'), true);
    expect(game.eggId, isNot(previous));
    expect((app.snapshot['egg'] as Map)['active'], true);
    expect(app.snapshot['connected'], true);
    final next = game.eggId;
    app.view = 'pairing';
    expect(await action('testPair'), true);
    expect(game.eggId, next);
  });

  test(
      'test connection cannot bypass real pairing or run outside the connection form',
      () async {
    app.view = 'home';
    expect(await action('testPair'), false);
    expect(game.paired, false);
    close();
    await boot(source: RoundFeed());
    expect(await action('testPair'), false);
    expect(game.paired, false);
    expect(game.eggId, isNull);
  });

  test(
      'initial grant save failure stays in the form and retries the missing egg',
      () async {
    close();
    final dex = FailingDemoProgress()..fail = true;
    await boot(store: dex);
    expect(await action('testPair'), false);
    expect(app.view, 'pairing');
    expect(game.eggId, isNull);
    dex.fail = false;
    expect(await action('testPair'), true);
    expect(game.eggId, isNotNull);
    expect((app.snapshot['egg'] as Map)['active'], true);
    expect(app.view, 'cabin');
  });

  test('failed trip save prevents a new grant and can be retried', () async {
    close();
    final dex = FailingDemoProgress();
    await boot(store: dex);
    final previous = await failAndSave();
    app.view = 'pairing';
    dex.fail = true;
    expect(await action('testPair'), false);
    expect(game.eggId, previous);
    expect(game.sessionEnded, true);
    dex.fail = false;
    expect(await action('testPair'), true);
    expect(game.eggId, isNot(previous));
    expect((app.snapshot['egg'] as Map)['active'], true);
  });
}
