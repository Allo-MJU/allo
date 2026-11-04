import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

GameState state() => const GameState(
    ts: 1, eggTier: EggTier.small, stage: Stage.idle, progress: 0);

DexEntry entry(String? region) => DexEntry(
    speciesId: 'road_sprout',
    obtainedAt: DateTime(2026),
    envTags: const [],
    regionTag: region,
    tier: 1);

void main() {
  test(
      'idle emits unknown and known empty remains distinguishable after RTDB removes array',
      () {
    expect(state().toJson()['regionCollectionKnown'], isFalse);
    final complete = state()
        .copyWith(regionCollectionKnown: true, uncollectedRegions: const []);
    final wire =
        jsonDecode(jsonEncode(complete.toJson())) as Map<String, dynamic>;
    wire.remove('uncollectedRegions');
    expect(wire['regionCollectionKnown'], isTrue);
  });

  test(
      'ordinary state changes preserve summary and explicit false or empty replaces it',
      () {
    final known = state().copyWith(
        regionCollectionKnown: true, uncollectedRegions: const ['coast']);
    expect(known.copyWith(progress: .5).uncollectedRegions, ['coast']);
    expect(known.copyWith(stage: Stage.hatched).regionCollectionKnown, isTrue);
    expect(known.copyWith(uncollectedRegions: const []).uncollectedRegions,
        isEmpty);
    expect(known.copyWith(regionCollectionKnown: false).regionCollectionKnown,
        isFalse);
  });

  test('valid empty and legacy null entries produce a known summary', () {
    final empty = RegionCollection.fromEntries(const []);
    expect(empty.known, isTrue);
    expect(empty.uncollectedRegions, ['coast', 'mountain', 'city']);
    final collected = RegionCollection.fromEntries(
        [entry(null), entry('coast'), entry('coast'), entry('city')]);
    expect(collected.known, isTrue);
    expect(collected.uncollectedRegions, ['mountain']);
  });

  test('invalid stored region never becomes a known empty result', () {
    final invalid = RegionCollection.fromEntries([entry('desert')]);
    expect(invalid.known, isFalse);
    final all =
        RegionCollection.fromEntries(['coast', 'mountain', 'city'].map(entry));
    expect(all.known, isTrue);
    expect(all.uncollectedRegions, isEmpty);
  });
}
