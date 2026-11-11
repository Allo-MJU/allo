import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/dex_store.dart';
import '../storage/pairing_store.dart';
import '../pairing/pairing_credentials.dart';
import '../fishing/fishing_store.dart';

/// Separate keys keep sample companions and rewards out of the real collection.
class LocalDemoDexStore extends DexStore {
  static const key = 'local.fishing.demo.dex.v1';
  Future<void> seed() async {
    for (final id in [
      'road_sprout',
      'puddle_pip',
      'lamp_moth',
      'storm_lantern',
      'highway_comet',
      'sea_mist'
    ]) {
      await add(DexEntry(
          speciesId: id,
          obtainedAt: DateTime.utc(2026, 11, 11),
          envTags: const [],
          regionTag: null,
          tier: 1));
    }
  }

  @override
  Future<List<DexEntry>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? [])
        .map((e) => DexEntry.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> add(DexEntry e) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...?prefs.getStringList(key)];
    final encoded = jsonEncode(e.toJson());
    if (!list.contains(encoded)) list.add(encoded);
    if (!await prefs.setStringList(key, list)) {
      throw StateError('Demo dex save failed');
    }
  }

  @override
  Future<IncubationProgress> incubationProgress(EggTier tier) async =>
      const IncubationProgress();
  @override
  Future<void> saveIncubationProgress(
          EggTier tier, IncubationProgress progress) async =>
      throw UnsupportedError('Demo is fishing only');
}

class LocalDemoFishingStore extends FishingStore {
  static const demoKey = 'local.fishing.demo.profile.v1';
  @override
  Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(demoKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(demoKey, jsonEncode(profile))) {
      throw StateError('Demo fishing save failed');
    }
  }
}

class LocalDemoPairingStore extends PairingStore {
  @override
  Future<PairingCredentials?> read() async => null;
  @override
  Future<void> save(PairingCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}
