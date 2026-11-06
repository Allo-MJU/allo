import 'models.dart';

/// The device's stored collection record, never a claim about actual visits.
class RegionCollection {
  static const regions = ['coast', 'mountain', 'city'];

  const RegionCollection.unknown()
      : known = false,
        uncollectedRegions = const [];

  RegionCollection._(Iterable<String> uncollected)
      : known = true,
        uncollectedRegions = List.unmodifiable(uncollected);

  factory RegionCollection.fromEntries(Iterable<DexEntry> entries) {
    final collected = <String>{};
    for (final entry in entries) {
      final region = entry.regionTag;
      if (region == null) continue;
      if (!regions.contains(region)) return const RegionCollection.unknown();
      collected.add(region);
    }
    return RegionCollection._(regions.where((r) => !collected.contains(r)));
  }

  final bool known;
  final List<String> uncollectedRegions;
}
