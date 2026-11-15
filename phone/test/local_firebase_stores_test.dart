import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/local_firebase/stores.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Platform error injection tests failed persistence rather than an app-store stub.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingPreferences extends InMemorySharedPreferencesStore {
  FailingPreferences() : super.withData({});
  String? failSuffix;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failSuffix != null && key.endsWith(failSuffix!)) return false;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final pair = PairingCredentials.parseFields(
      '00000000-0000-4000-8000-000000000001', '123456');

  test(
      'default keys unchanged, namespaced data isolated and retained on recreation',
      () async {
    await DexStore().add(LocalFirebaseStores.samples.first);
    await DexStore().setCarriedDistance(EggTier.small, 12);
    await FishingStore().write({'normal': true});
    await PairingStore().save(pair);
    final local = LocalFirebaseStores();
    expect(await local.dex.all(), isEmpty);
    expect(await local.dex.carriedDistance(EggTier.small), 0);
    expect(await local.fishing.read(), isNull);
    expect(await local.pairing.read(), isNull);
    await local.seedSamples();
    await local.dex.saveIncubationProgress(
        EggTier.small,
        const IncubationProgress(
            carriedM: 30,
            sessionDistances: {'s': 15},
            round: {'phase': 'local'}));
    await local.fishing.write({'selected': 'local'});
    await local.pairing.save(pair);
    final again = LocalFirebaseStores();
    expect((await again.dex.all()).length, 3);
    final progress = await again.dex.incubationProgress(EggTier.small);
    expect(progress.carriedM, 30);
    expect(progress.sessionDistances, {'s': 15});
    expect(progress.round, {'phase': 'local'});
    expect(await again.fishing.read(), {'selected': 'local'});
    expect((await again.pairing.read())?.sessionId, pair.sessionId);
    await again.pairing.clear();
    expect((await PairingStore().read())?.code, pair.code);
    expect(await FishingStore().read(), {'normal': true});
    expect(await DexStore().carriedDistance(EggTier.small), 12);
    expect((await DexStore().all()).length, 1);
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'dex.entries.v1',
      'hatch.progress.v2.small',
      FishingStore.key,
      'pairing.session.v1'
    ]) {
      expect(prefs.containsKey(key), isTrue);
    }
  });

  test('legacy distance migration does not read another namespace', () async {
    SharedPreferences.setMockInitialValues({
      'hatch.carried.v1.small': 11.0,
      'local.firebase.hatch.carried.v1.small': 22.0
    });
    expect(await DexStore().carriedDistance(EggTier.small), 11);
    expect(await LocalFirebaseStores().dex.carriedDistance(EggTier.small), 22);
  });

  test('seed remains idempotent and retains existing local collection',
      () async {
    final local = LocalFirebaseStores();
    await local.dex.add(DexEntry(
        speciesId: 'river_glider',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1));
    await local.seedSamples();
    await LocalFirebaseStores().seedSamples();
    expect((await local.dex.all()).length, 4);
    expect(
        LocalFirebaseStores.samples.map((e) => e.obtainedAt).toSet().length, 3);
    expect(
        LocalFirebaseStores.samples.map((e) => e.regionTag).toSet().length, 3);
    expect(await DexStore().all(), isEmpty);
  });

  test('malformed local pairing removes only its own key', () async {
    await PairingStore().save(pair);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local.firebase.pairing.session.v1', 'broken');
    expect(await LocalFirebaseStores().pairing.read(), isNull);
    expect((await PairingStore().read())?.code, pair.code);
  });

  test(
      'real-trip migration retries a demo copy cached after a failed disk write',
      () async {
    final platform = FailingPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final store = DexStore();
    await store.saveIncubationProgress(
        EggTier.small,
        const IncubationProgress(
            carriedM: 1500,
            round: {'eggId': 'legacy-demo', 'sessionId': null}));
    platform.failSuffix = 'hatch.demo.v1.small';
    await expectLater(
        store.tripProgress(false, EggTier.small), throwsStateError);
    platform.failSuffix = null;
    final real = await store.tripProgress(false, EggTier.small);
    expect(real.round, isNull);
    await store.saveTripProgress(
        false, EggTier.small, const IncubationProgress());
    await (await SharedPreferences.getInstance()).reload();
    expect((await store.tripProgress(true, EggTier.small)).round?['eggId'],
        'legacy-demo');
  });

  for (final failing in ['dex.entries.v1', 'samples.seeded.v1']) {
    test('failed $failing write is surfaced and retry has no duplicates',
        () async {
      final platform = FailingPreferences()..failSuffix = failing;
      SharedPreferencesStorePlatform.instance = platform;
      final local = LocalFirebaseStores();
      await expectLater(local.seedSamples(), throwsStateError);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getBool('local.firebase.samples.seeded.v1'), isNot(true));
      platform.failSuffix = null;
      await LocalFirebaseStores().seedSamples();
      expect((await local.dex.all()).length, 3);
      expect(prefs.getBool('local.firebase.samples.seeded.v1'), isTrue);
    });
  }

  test('namespaced progress fishing and pairing propagate persistence failures',
      () async {
    final platform = FailingPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final local = LocalFirebaseStores();
    platform.failSuffix = 'hatch.progress.v2.small';
    await expectLater(
        local.dex.setCarriedDistance(EggTier.small, 5), throwsStateError);
    platform.failSuffix = FishingStore.key;
    await expectLater(local.fishing.write({'value': 1}), throwsStateError);
    expect(await local.fishing.read(), isNull);
    platform.failSuffix = 'pairing.session.v1';
    await expectLater(local.pairing.save(pair), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('local.firebase.pairing.session.v1'), isNull);
  });
}
