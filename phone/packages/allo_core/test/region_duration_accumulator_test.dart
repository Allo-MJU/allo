import 'dart:convert';
import 'package:test/test.dart';
import 'package:allo_core/src/region_duration_accumulator.dart';

void main() {
  test('regular observations produce the same time regardless of interval', () {
    for (final interval in [1000, 4000]) {
      final a = RegionDurationAccumulator();
      var now = 0;
      for (final entry in {'city': 25, 'mountain': 10, 'coast': 5}.entries) {
        for (var elapsed = 0;
            elapsed < entry.value * 60000;
            elapsed += interval) {
          a.observe(atMs: now, envTags: [entry.key]);
          now += interval;
        }
      }
      expect(a.finish(now), 'city');
      expect(
          a.durationMs, {'city': 1500000, 'mountain': 600000, 'coast': 300000});
      expect(a.unknownMs, 0);
      expect(a.activeMs, 2400000);
    }
  });
  test('stale region is held for at most five seconds', () {
    final a = RegionDurationAccumulator()..observe(atMs: 0, envTags: ['city']);
    expect(a.finish(20000), isNull);
    expect(a.durationMs['city'], 5000);
    expect(a.unknownMs, 15000);
  });
  test('ties and insufficient evidence have no winner', () {
    final tie = RegionDurationAccumulator()
      ..observe(atMs: 0, envTags: ['city'])
      ..observe(atMs: 1000, envTags: ['coast']);
    expect(tie.finish(2000), isNull);
    final uncertain = RegionDurationAccumulator()
      ..observe(atMs: 0, envTags: ['city'])
      ..observe(atMs: 2000, envTags: ['coast'])
      ..observe(atMs: 3000, envTags: []);
    expect(uncertain.finish(4000), isNull);
    final sufficient = RegionDurationAccumulator()
      ..observe(atMs: 0, envTags: ['city'])
      ..observe(atMs: 3000, envTags: ['coast'])
      ..observe(atMs: 4000, envTags: []);
    expect(sufficient.finish(5000), 'city');
    expect(RegionDurationAccumulator().finish(0), isNull);
  });
  test('missing or multiple region tags count as unknown', () {
    final a = RegionDurationAccumulator()
      ..observe(atMs: 0, envTags: [])
      ..observe(atMs: 1000, envTags: ['city', 'coast'])
      ..observe(atMs: 2000, envTags: ['city', 'other']);
    expect(a.finish(3000), isNull);
    expect(a.unknownMs, 2000);
    expect(a.durationMs['city'], 1000);
  });
  test('duplicate and reverse observations do not change or extend hold', () {
    final a = RegionDurationAccumulator()
      ..observe(atMs: 1000, envTags: ['city'])
      ..observe(atMs: 1000, envTags: ['coast'])
      ..observe(atMs: 500, envTags: ['mountain']);
    expect(a.finish(10000), isNull);
    expect(a.durationMs['city'], 5000);
    expect(a.unknownMs, 5000);
  });
  test('finish closes tail and freezes the result', () {
    final a = RegionDurationAccumulator(startAtMs: 100)
      ..observe(atMs: 100, envTags: ['city']);
    expect(a.finish(1100), 'city');
    a.observe(atMs: 2000, envTags: ['coast']);
    a.breakContinuity(3000);
    expect(a.finish(4000), 'city');
    expect(a.activeMs, 1000);
  });
  test('checkpoint and restore preserve totals without old region or pause',
      () {
    final a = RegionDurationAccumulator()..observe(atMs: 0, envTags: ['city']);
    final data =
        jsonDecode(jsonEncode(a.checkpoint(2000))) as Map<String, dynamic>;
    final b = RegionDurationAccumulator.restore(data, atMs: 100000);
    b.observe(atMs: 103000, envTags: ['coast']);
    expect(b.finish(104000), isNull);
    expect(b.durationMs['city'], 2000);
    expect(b.durationMs['coast'], 1000);
    expect(b.unknownMs, 3000);
    expect(b.activeMs, 6000);
  });
  test('break continuity closes the held region', () {
    final a = RegionDurationAccumulator()
      ..observe(atMs: 0, envTags: ['city'])
      ..breakContinuity(2000);
    expect(a.finish(4000), isNull);
    expect(a.durationMs['city'], 2000);
    expect(a.unknownMs, 2000);
  });
  test('rejects malformed checkpoint data', () {
    for (final data in [
      <String, dynamic>{},
      {
        'durations': {'city': -1, 'coast': 0, 'mountain': 0},
        'unknownMs': 0
      },
      {
        'durations': {'city': 0, 'coast': 0, 'forest': 1},
        'unknownMs': 0
      },
      {
        'durations': {'city': 0, 'coast': 0, 'mountain': 0},
        'unknownMs': -1
      },
      {
        'durations': {'city': 0.5, 'coast': 0, 'mountain': 0},
        'unknownMs': 0
      },
    ]) {
      expect(() => RegionDurationAccumulator.restore(data, atMs: 0),
          throwsFormatException);
    }
  });
}
