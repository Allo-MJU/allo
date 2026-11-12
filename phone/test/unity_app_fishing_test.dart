import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fishing_feed_integration_test.dart' show MemoryFishingStore;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;

class MutableOwnedDex extends DexStore {
  final records = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> allRecords() async =>
      records.map((r) => Map<String, dynamic>.from(r)).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MutableOwnedDex dex;
  late BaseCampController camp;
  late GameController game;
  late UnityAppController app;
  late MemoryFishingStore fishing;
  var number = 0;
  DexEntry owned({String? source, List<String> tags = const []}) => DexEntry(
      speciesId: 'road_sprout',
      obtainedAt: DateTime.utc(2026),
      envTags: tags,
      regionTag: null,
      tier: 1,
      sourceEggId: source);
  Future<bool> action(String name, [Map<String, dynamic> fields = const {}]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'f${number++}',
        'action': name,
        ...fields
      }));
  Future<List<String>> load(List<DexEntry> entries) async {
    dex.records.addAll(entries.map((e) => e.toJson()));
    await camp.refreshOwnership();
    return camp.state.creatures.keys.toList();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    number = 0;
    dex = MutableOwnedDex();
    fishing = MemoryFishingStore();
    camp = BaseCampController(store: CampMemory(), dex: dex);
    game = GameController(
        feed: RoundFeed(), dex: dex, baseCamp: camp, fishingStore: fishing);
    app = UnityAppController(game: game, camp: camp);
    await app.initialize();
    await game.pair(sessionA, pairCode: '123456');
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });
  test(
      'same-species creature IDs select exact source ownership without material awards',
      () async {
    final first = owned(source: 'egg-one');
    final second = owned(source: 'egg-two');
    final ids = await load([first, second]);
    final before = camp.state.materials;
    expect(await action('selectCarCompanion', {'creatureId': ids[1]}), isTrue);
    expect(fishing.data!['selected'], jsonEncode(second.toJson()));
    expect(await action('selectCarCompanion', {'creatureId': ids[0]}), isTrue);
    expect(fishing.data!['selected'], jsonEncode(first.toJson()));
    (fishing.data!['entries'] as Map)[fishing.data!['selected']]
        ['totalRecords'] = 7;
    await game.fishing.attach(sessionA);
    expect(app.snapshot['fishingRecords'], 7);
    expect(app.snapshot['fishingError'], '');
    expect(camp.state.materials, before);
    expect((app.snapshot['materials'] as List).map((m) => m['count']),
        everyElement(0));
  });
  test('legacy canonical duplicates resolve their original occurrence records',
      () async {
    final first = owned(tags: ['rain', 'city']);
    final second = owned(tags: ['city', 'rain']);
    final ids = await load([first, second]);
    expect(ids, hasLength(2));
    expect(await action('selectCarCompanion', {'creatureId': ids[1]}), isTrue);
    expect(fishing.data!['selected'], jsonEncode(second.toJson()));
    expect(await action('selectCarCompanion', {'creatureId': ids[0]}), isTrue);
    expect(fishing.data!['selected'], jsonEncode(first.toJson()));
  });
  test(
      'disconnected unknown removed and changed-species ownership are rejected',
      () async {
    final ids = await load([owned(source: 'egg-one')]);
    expect(
        await action('selectCarCompanion', {'creatureId': 'unknown'}), isFalse);
    dex.records.single['speciesId'] = 'puddle_pip';
    expect(await action('selectCarCompanion', {'creatureId': ids.single}),
        isFalse);
    dex.records.clear();
    expect(await action('selectCarCompanion', {'creatureId': ids.single}),
        isFalse);
    await load([owned(source: 'egg-one')]);
    expect(await action('disconnect'), isTrue);
    expect(await action('selectCarCompanion', {'creatureId': ids.single}),
        isFalse);
    expect(fishing.data!['selected'], isNull);
  });
  test(
      'fishing summary and retry preserve unrelated game errors without inventing records',
      () async {
    final ids = await load([owned(source: 'egg-one')]);
    fishing.failWrite = true;
    expect(await action('selectCarCompanion', {'creatureId': ids.single}),
        isFalse);
    expect(game.fishing.hasPendingWrite, isTrue);
    expect(app.snapshot['fishingRecords'], 0);
    expect(app.snapshot['fishingError'], isNotEmpty);
    game.error = 'unrelated egg save error';
    expect(await action('retryFishingSave'), isFalse);
    expect(game.error, 'unrelated egg save error');
    fishing.failWrite = false;
    expect(await action('retryFishingSave'), isTrue);
    expect(game.error, 'unrelated egg save error');
    expect(app.snapshot['fishingError'], '');
    expect(app.snapshot['fishingRecords'], 0);
    expect(game.fishing.hasPendingWrite, isFalse);
    expect(camp.state.materials.values, everyElement(0));
  });
  test('successful fishing retry clears only its stale mirrored game error',
      () async {
    final ids = await load([owned(source: 'egg-one')]);
    fishing.failWrite = true;
    expect(await action('selectCarCompanion', {'creatureId': ids.single}),
        isFalse);
    expect(game.error, game.fishing.error);
    expect(game.error, isNotNull);
    fishing.failWrite = false;
    expect(await action('retryFishingSave'), isTrue);
    expect(game.error, isNull);
    expect(app.snapshot['fishingError'], '');
  });
}
