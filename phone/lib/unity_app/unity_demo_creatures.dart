import 'package:allo_core/allo_core.dart';
import '../storage/dex_store.dart';

/// Isolated, explicitly opted-in sample ownership; never a hatch or reward receipt.
Future<void> seedUnityDemoCreatures(DexStore dex, List<Species> species) async {
  if (dex.profile != 'unity-demo-examples') {
    throw StateError('Demo examples require their isolated ownership profile');
  }
  const examples = ['road_sprout', 'puddle_pip', 'lamp_moth', 'highway_comet'];
  for (final id in examples) {
    final creature = species.firstWhere((s) => s.id == id);
    await dex.add(DexEntry(
      speciesId: id,
      obtainedAt: DateTime.utc(2026, 11, 12),
      envTags: const [],
      regionTag: null,
      tier: creature.tier,
      sourceEggId: 'unity-demo-example-v1-$id',
    ));
  }
}
