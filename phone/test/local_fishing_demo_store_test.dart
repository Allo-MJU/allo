import 'package:flutter_test/flutter_test.dart';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:allo_phone/local_fishing/demo_stores.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('demo samples and fishing saves never overwrite production keys',
      () async {
    SharedPreferences.setMockInitialValues({
      'dex.entries.v1': <String>['existing-real-record'],
      'companion.fishing.profile.v1': 'existing-real-profile',
      'pairing.session.v1': 'existing-real-pairing',
    });
    final dex = LocalDemoDexStore();
    await dex.seed();
    await dex.seed();
    expect((await dex.all()).length, 6);
    await dex.saveIncubationProgress(
        EggTier.small, const IncubationProgress(carriedM: 123));
    expect(await LocalDemoDexStore().carriedDistance(EggTier.small), 123);
    expect(await DexStore().carriedDistance(EggTier.small), 0);
    final fishing = LocalDemoFishingStore();
    await fishing.write({'version': 1, 'savedReward': 4});
    expect(
        await LocalDemoFishingStore().read(), {'version': 1, 'savedReward': 4});
    await LocalDemoPairingStore().clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('dex.entries.v1'), ['existing-real-record']);
    expect(prefs.getString('companion.fishing.profile.v1'),
        'existing-real-profile');
    expect(prefs.getString('pairing.session.v1'), 'existing-real-pairing');
  });
}
