import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_camp_controller_test.dart' show MemoryCampStore, entry;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

class RetryingCampStore extends MemoryCampStore {
  bool failLoad = true;
  @override
  Future<Map<String, dynamic>?> load() async {
    if (failLoad) throw StateError('temporary read failure');
    return super.load();
  }
}

class CapturingCampFeed extends RoundFeed {
  final wire = <Map<String, dynamic>>[];
  @override
  Future<void> publishGame(GameState state) async {
    wire.add(jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>);
    await super.publishGame(state);
  }

  Map<String, dynamic> get collection =>
      wire.last['collectionSummary'] as Map<String, dynamic>;
  int get revision => wire.last['gameRevision'] as int;
}

Future<void> flushPublication() async {
  for (var i = 0; i < 24; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryCampStore store;
  late CapturingCampFeed feed;
  late BaseCampController camp;
  late GameController game;
  late DexStore dex;
  var now = 1700000000000;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = 1700000000000;
    store = MemoryCampStore();
    dex = DexStore();
    feed = CapturingCampFeed();
    camp = BaseCampController(store: store, dex: dex, nowMs: () => now);
    game = GameController(
        feed: feed, dex: dex, baseCamp: camp, monotonicMs: () => now);
    await game.pair(sessionA, pairCode: '123456');
    await flushPublication();
  });
  tearDown(() {
    game.dispose();
    camp.dispose();
  });

  Future<void> sample(double distance, {bool duplicate = false}) async {
    now += 1000;
    feed.sample(distance: distance, duplicate: duplicate);
    await flushPublication();
  }

  test('pairing alone publishes observed kilometer without hatch or selection',
      () async {
    final egg = game.eggId;
    expect(egg, isNotNull);
    expect(game.game.stage, Stage.incubating);
    expect(game.fishing.selectedSpeciesId, isNull);
    expect(feed.watches, 1);
    expect(feed.collection['wood'], 0);
    await sample(0);
    final before = feed.revision;
    await sample(1000);
    expect(feed.collection['wood'], 1);
    expect(feed.collection['stone'], 1);
    expect(feed.collection['ingredient'], 1);
    expect(feed.collection['speciesIds'], isEmpty);
    expect(feed.collection['speciesCount'], 0);
    expect(feed.revision, greaterThan(before));
    expect(game.eggId, egg);
    expect(game.game.stage, Stage.incubating);
    expect(game.fishing.selectedSpeciesId, isNull);
    expect(feed.watches, 1);
  });

  test(
      'retrying initial camp load restores collection without a selected friend',
      () async {
    game.dispose();
    camp.dispose();
    final retryStore = RetryingCampStore();
    feed = CapturingCampFeed();
    camp = BaseCampController(store: retryStore, dex: dex, nowMs: () => now);
    game = GameController(
        feed: feed, dex: dex, baseCamp: camp, monotonicMs: () => now);
    await game.pair(sessionA, pairCode: '123456');
    expect(game.paired, isTrue);
    expect(camp.ready, isFalse);
    expect(feed.watches, 1);
    retryStore.failLoad = false;
    expect(await camp.load(), isTrue);
    await flushPublication();
    expect(feed.watches, 1);
    await sample(9000); // Unobserved distance before retry is not rewarded.
    expect(feed.collection['wood'], 0);
    await sample(9500);
    expect(await camp.refreshOwnership(), isTrue);
    await sample(10000);
    expect(feed.collection['wood'], 1);
    await sample(11000);
    expect(feed.collection['wood'], 2);
    expect(feed.watches, 1);
  });

  test('loading a camp without pairing does not subscribe to a vehicle',
      () async {
    game.dispose();
    camp.dispose();
    feed = CapturingCampFeed();
    camp = BaseCampController(store: store, dex: dex, nowMs: () => now);
    game = GameController(
        feed: feed, dex: dex, baseCamp: camp, monotonicMs: () => now);
    expect(await camp.load(), isTrue);
    await flushPublication();
    expect(feed.watches, 0);
    expect(feed.wire, isEmpty);
  });

  test('pending and failed durable saves cannot publish new material counts',
      () async {
    await sample(0);
    store.block = Completer<void>();
    await sample(1000);
    expect(store.inFlight, 1);
    expect(camp.state.materials[CampMaterial.wood], 0);
    expect(feed.collection['wood'], 0);
    // A later heartbeat must also serialize the last committed camp only.
    now += 10000;
    feed.sample(distance: 1000, duplicate: true);
    await flushPublication();
    expect(
        feed.wire.where((v) => (v['collectionSummary'] as Map?)?['wood'] == 1),
        isEmpty);
    store.failSave = true;
    store.block!.complete();
    await flushPublication();
    expect(feed.collection['wood'], 0);
    expect(camp.state.materials[CampMaterial.wood], 0);
    store.block = null;
    store.failSave = false;
    final before = feed.revision;
    await sample(1000);
    expect(feed.collection['wood'], 1);
    expect(feed.revision, greaterThan(before));
    await sample(1000, duplicate: true);
    expect(feed.collection['wood'], 1);
  });

  test('saved dex assignment and completed facility publish new revisions',
      () async {
    var before = feed.revision;
    await dex.add(entry('road_sprout'));
    await dex.add(entry('puddle_pip'));
    expect(await camp.refreshOwnership(), isTrue);
    await flushPublication();
    expect(feed.collection['speciesIds'], ['puddle_pip', 'road_sprout']);
    expect(feed.collection['speciesCount'], 2);
    expect(feed.revision, greaterThan(before));
    final builder = camp.state.creatures.values
        .firstWhere((c) => c.speciesId == 'road_sprout');
    before = feed.revision;
    expect(await camp.assign(CampRole.builder, builder.id), isTrue);
    await flushPublication();
    expect((feed.wire.last['baseSummary'] as Map)['builderSpeciesId'],
        'road_sprout');
    expect(feed.revision, greaterThan(before));
    await sample(0);
    await sample(2000);
    expect(await camp.startBuild(CampFacility.workshop), isTrue);
    await flushPublication();
    expect((feed.wire.last['baseSummary'] as Map)['activeTaskKinds'],
        ['building']);
    before = feed.revision;
    now += 30000;
    expect(await camp.tick(), isTrue);
    await flushPublication();
    final base = feed.wire.last['baseSummary'] as Map;
    expect(base['structureIds'], ['workshop']);
    expect((base['facilityLevels'] as Map)['workshop'], 1);
    expect(base['activeTaskKinds'], isEmpty);
    expect(feed.revision, greaterThan(before));
  });

  test('resume and stream reconnect baseline skip gaps and duplicates',
      () async {
    await sample(0);
    await sample(1000);
    expect(feed.collection['wood'], 1);
    await game.setAppActive(false);
    await sample(8000);
    await game.setAppActive(true);
    await sample(10000);
    expect(feed.collection['wood'], 1);
    await sample(11000);
    expect(feed.collection['wood'], 2);
    feed.signals.addError(StateError('transport disconnected'));
    await flushPublication();
    await sample(20000);
    expect(feed.collection['wood'], 2);
    await sample(21000);
    expect(feed.collection['wood'], 3);
    await sample(21000, duplicate: true);
    await sample(20000);
    await sample(21000);
    expect(feed.collection['wood'], 3);
    expect(feed.watches, 1);
  });
}
