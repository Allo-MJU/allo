import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DexEntry entry(String species, String source) => DexEntry(
    speciesId: species,
    sourceEggId: source,
    obtainedAt: DateTime.utc(2026, 11, 12),
    envTags: const [],
    regionTag: null,
    tier: 1);

class MemoryDex extends DexStore {
  MemoryDex(this.entries);
  final List<DexEntry> entries;
  @override
  Future<List<DexEntry>> all() async => entries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('camp ownership uses only the injected namespaced collection', () async {
    await DexStore().add(entry('road_sprout', 'normal-egg'));
    final local = DexStore(namespace: 'local.firebase.');
    await local.add(entry('puddle_pip', 'local-egg'));
    expect((await local.allRecords()).single['sourceEggId'], 'local-egg');
    final camp = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'local-firebase'),
        dex: local);
    addTearDown(camp.dispose);
    expect(await camp.load(), isTrue);
    expect(camp.state.creatures.length, 1);
    expect((await DexStore().all()).single.speciesId, 'road_sprout');
  });
  test(
      'allRecords respects existing all override instead of stored normal entries',
      () async {
    await DexStore().add(entry('road_sprout', 'normal-egg'));
    final memory = MemoryDex([entry('lamp_moth', 'memory-egg')]);
    final record = (await memory.allRecords()).single;
    expect(record['sourceEggId'], 'memory-egg');
    expect(record['speciesId'], 'lamp_moth');
  });
}
