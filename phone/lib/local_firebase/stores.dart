import 'package:allo_core/allo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fishing/fishing_store.dart';
import '../storage/dex_store.dart';
import '../storage/pairing_store.dart';

/// Persistent synthetic data, isolated from the normal app's collection and session.
class LocalFirebaseStores {
  static const namespace = 'local.firebase.';
  static const _seedKey = '${namespace}samples.seeded.v1';
  final dex = DexStore(namespace: namespace);
  final fishing = FishingStore(namespace: namespace);
  final pairing = PairingStore(namespace: namespace);

  static final samples = List<DexEntry>.unmodifiable([
    DexEntry(
      sourceEggId: 'local-firebase-sample-road-sprout-v1',
      speciesId: 'road_sprout',
      obtainedAt: DateTime.utc(2026, 11, 10, 9),
      envTags: const ['city'],
      regionTag: 'city',
      tier: 1,
    ),
    DexEntry(
      sourceEggId: 'local-firebase-sample-puddle-pip-v1',
      speciesId: 'puddle_pip',
      obtainedAt: DateTime.utc(2026, 11, 11, 14),
      envTags: const ['rain', 'coast'],
      regionTag: 'coast',
      tier: 1,
    ),
    DexEntry(
      sourceEggId: 'local-firebase-sample-lamp-moth-v1',
      speciesId: 'lamp_moth',
      obtainedAt: DateTime.utc(2026, 11, 12, 20),
      envTags: const ['night', 'tunnel'],
      regionTag: 'mountain',
      tier: 1,
    ),
  ]);

  /// Record completion only after all writes succeed. Stable source IDs make retries safe.
  Future<void> seedSamples() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool(_seedKey) == true) return;
    for (final entry in samples) {
      await dex.add(entry);
    }
    if (!await prefs.setBool(_seedKey, true)) {
      throw StateError('Could not save local Firebase sample seed');
    }
  }
}
