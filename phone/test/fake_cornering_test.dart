import 'dart:async';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'legacy feed keeps its capabilities and has no cornering by default',
      (tester) async {
    final feed = FakeVehicleFeed(scenario: FakeScenario.sceneTour);
    final emitted = <VehicleState>[];
    final sub = feed.watch().listen(emitted.add);
    await tester.pump(const Duration(seconds: 1));
    final state = emitted.single;
    expect(state.cornering, isNull);
    expect(state.capabilities,
        ['wiper', 'light', 'seat', 'odometer', 'speed', 'gear', 'turns']);
    expect(state.distanceM, closeTo(70 / 3.6 * 20, 0.001));
    expect(state.envTags, isEmpty);
    expect(state.turns, FakeScenario.sceneTour.turnsAt(70 / 3.6));
    expect(state.headingDeg, FakeScenario.sceneTour.headingAt(70 / 3.6));
    expect(await feed.readLatestVehicle(), same(emitted.last));
    unawaited(sub.cancel());
    unawaited(feed.dispose());
    await tester.pump();
  });

  testWidgets(
      'opted in tour repeats neutral right and left cues with wallclock receipt',
      (tester) async {
    final feed = FakeVehicleFeed(
        scenario: FakeScenario.sceneTour,
        timeScale: 1000,
        simulateCornering: true);
    final emitted = <VehicleState>[];
    final sub = feed.watch().listen(emitted.add);
    final before = DateTime.now().millisecondsSinceEpoch;
    await tester.pump(const Duration(seconds: 48));
    final after = DateTime.now().millisecondsSinceEpoch;
    expect(emitted, hasLength(48));
    final bends = emitted.map((state) => state.cornering!.bend).toList();
    expect(bends, contains(0.0));
    expect(bends.any((bend) => bend < 0), isTrue);
    expect(bends.any((bend) => bend > 0), isTrue);
    expect(bends.take(24).toList(), bends.skip(24).toList());
    for (final state in emitted) {
      expect(state.capabilities, contains('steering'));
      expect(state.cornering!.isValid, isTrue);
      expect(state.cornering!.receivedAtMs, inInclusiveRange(before, after));
      expect(state.cornering!.receivedAtMs, lessThan(state.ts));
    }
    final latest = await feed.readLatestVehicle();
    expect(latest, same(emitted.last));
    expect(latest!.cornering!.receivedAtMs, inInclusiveRange(before, after));
    unawaited(sub.cancel());
    unawaited(feed.dispose());
    await tester.pump();
  });

  testWidgets(
      'tour still cycles field coast mountain city and highway with cues enabled',
      (tester) async {
    final feed = FakeVehicleFeed(
        scenario: FakeScenario.sceneTour, simulateCornering: true);
    final emitted = <VehicleState>[];
    final sub = feed.watch().listen(emitted.add);
    await tester.pump(const Duration(seconds: 105));
    expect(emitted[14].envTags, ['coast']);
    expect(emitted[29].envTags, ['mountain']);
    expect(emitted[44].envTags, ['city']);
    expect(emitted[89].envTags, ['highway', 'rain']);
    expect(emitted[104].envTags, isEmpty);
    unawaited(sub.cancel());
    unawaited(feed.dispose());
    await tester.pump();
  });

  testWidgets('endTrip clears cue and stops ticks and disposal leaves no timer',
      (tester) async {
    final feed = FakeVehicleFeed(
        scenario: FakeScenario.sceneTour, simulateCornering: true);
    final emitted = <VehicleState>[];
    final events = <Map<String, Object?>>[];
    final sub = feed.watch().listen(emitted.add);
    final eventSub = feed.events().listen(events.add);
    await tester.pump(const Duration(seconds: 8));
    expect(emitted.last.cornering!.bend, greaterThan(0));
    feed.endTrip();
    feed.endTrip();
    await tester.pump();
    final stopped = await feed.readLatestVehicle();
    expect(stopped!.gear, 'P');
    expect(stopped.speedKph, 0);
    expect(stopped.cornering, isNull);
    await tester.pump(const Duration(seconds: 30));
    expect(emitted, hasLength(8));
    expect(events, hasLength(1));
    unawaited(sub.cancel());
    unawaited(eventSub.cancel());
    unawaited(feed.dispose());
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
  });
  testWidgets('disposing an active simulated drive cancels its timer',
      (tester) async {
    final feed = FakeVehicleFeed(
        scenario: FakeScenario.sceneTour, simulateCornering: true);
    final emitted = <VehicleState>[];
    final sub = feed.watch().listen(emitted.add);
    await tester.pump(const Duration(seconds: 2));
    expect(emitted, hasLength(2));
    unawaited(feed.dispose());
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(emitted, hasLength(2));
    feed.endTrip(); // Already disposed: no event or timer exception.
    unawaited(sub.cancel());
    await tester.pump();
  });
  testWidgets(
      'pause preserves latest state distance and both scene and bend phases',
      (tester) async {
    final feed = FakeVehicleFeed(
        scenario: FakeScenario.sceneTour, simulateCornering: true);
    final emitted = <VehicleState>[];
    final sub = feed.watch().listen(emitted.add);
    await tester.pump(const Duration(seconds: 5));
    final before = await feed.readLatestVehicle();
    expect(before!.cornering!.bend, 0);
    feed.setPaused(true);
    await tester.pump(const Duration(seconds: 24));
    expect(emitted, hasLength(5));
    expect(await feed.readLatestVehicle(), same(before));
    feed.setPaused(false);
    final resumedAt = DateTime.now().millisecondsSinceEpoch;
    await tester.pump(const Duration(seconds: 1));
    final resumed = (await feed.readLatestVehicle())!;
    expect(emitted, hasLength(6));
    expect(resumed.distanceM, greaterThan(before.distanceM));
    expect(resumed.ts - before.ts, 20000);
    expect(
        resumed.cornering!.bend, 0.65); // Logical second 6, not real second 30.
    expect(resumed.cornering!.receivedAtMs,
        inInclusiveRange(resumedAt, DateTime.now().millisecondsSinceEpoch));
    expect(resumed.envTags, isEmpty); // Still before logical second 15.
    await tester.pump(const Duration(seconds: 9));
    expect(emitted.last.envTags, ['coast']);
    feed.endTrip();
    feed.setPaused(false);
    await tester.pump(const Duration(seconds: 4));
    expect(emitted, hasLength(15));
    unawaited(sub.cancel());
    unawaited(feed.dispose());
    await tester.pump();
    feed.setPaused(false);
    await tester.pump(const Duration(seconds: 4));
    expect(emitted, hasLength(15));
  });
}
