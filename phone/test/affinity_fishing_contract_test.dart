import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'affinity_controller_test.dart' show DemoApi, RecordingStore;
import 'fishing_feed_integration_test.dart' show MemoryFishingStore;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'controller publishes affinity lifecycle with existing companion and reward intact',
      () async {
    var now = 0, sequence = 0;
    final feed = RoundFeed();
    final store = RecordingStore();
    final c = GameController(
        feed: feed,
        dex: store,
        eggApi: DemoApi(),
        fishingStore: MemoryFishingStore(),
        affinityRandom: Random(1),
        monotonicMs: () => now);
    addTearDown(c.dispose);
    final entry = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026, 11, 11),
        envTags: const [],
        regionTag: null,
        tier: 1);
    await store.add(entry);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.selectCarCompanion(entry), isTrue);
    Future<void> settle() async {
      await c.fishing.settled;
      await Future<void>.delayed(Duration.zero);
    }

    await settle();
    Map<String, dynamic> last() => feed.published.last.toJson();
    Future<void> sample([int elapsed = 0]) async {
      now += elapsed;
      final f = last()['fishing'] as Map;
      feed.signals.add(VehicleState.fromJson({
        'ts': ++sequence,
        'gear': 'P',
        'etaSec': 5400,
        'distanceM': 0,
        'fishingPresence': {
          'version': 1,
          'leaseId': f['leaseId'],
          'epoch': 'car-test',
          'sequence': sequence,
          'active': true,
          'parkedAllowed': true
        }
      }));
      await settle();
    }

    await sample();
    final f = last()['fishing'] as Map;
    feed.carEvents.add({
      'by': 'car',
      'type': 'fishingRequested',
      'payload': {
        'requestId': 'start-one',
        'leaseId': f['leaseId'],
        'displayId': f['displayId'],
        'displayRevision': f['displayRevision'],
        'activityId': f['activityId'],
        'cycle': f['cycle'],
        'action': 'start'
      }
    });
    await settle();
    await sample();
    for (var i = 0; i < 60; i++) {
      await sample(1000);
    }
    expect((last()['fishing'] as Map)['totalRecords'], 1);
    expect((last()['fishing'] as Map)['state'], 'reward');
    final originalCompanion =
        Map<String, dynamic>.from(last()['companion'] as Map);
    final originalFishing = Map<String, dynamic>.from(last()['fishing'] as Map);
    final captures = <String, dynamic>{};
    Future<void> capture(String name) async {
      await settle();
      final state = last();
      expect(state['companion'], originalCompanion, reason: name);
      for (final key in [
        'displayId',
        'displayRevision',
        'activityId',
        'cycle',
        'elapsedMs',
        'totalRecords'
      ]) {
        expect((state['fishing'] as Map)[key], originalFishing[key],
            reason: '$name:$key');
      }
      expect(jsonEncode(state), isNot(contains('photoId')));
      expect(jsonEncode(state), isNot(contains('imageBase64')));
      captures[name] = jsonDecode(jsonEncode(state));
    }

    expect(await c.startIncubating(EggTier.small, useAffinity: true), isTrue);
    await sample();
    await capture('incubating');
    for (var i = 0; i < 17; i++) {
      await c.petEgg();
      if (i < 16) await sample(10000);
    }
    expect(c.affinityRound?.score, 50);
    await capture('photoRequired');
    await c.uploadEggPhoto(Uint8List.fromList([1, 2, 3]));
    await capture('photoCompleted');
    store.failAdd = true;
    for (var i = 0; i < 12; i++) {
      await sample(10000);
      await c.petEgg();
    }
    await settle();
    expect(c.game.affinityPhase, 'resultPending');
    expect(c.game.stage, Stage.incubating);
    expect(feed.hatchEvents, 0);
    await capture('resultPending');
    store.failAdd = false;
    expect(await c.endSession(), isTrue);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    expect(await store.all(), hasLength(2));
    await capture('hatched');
    expect(await c.startIncubating(EggTier.small, useAffinity: true), isTrue);
    await sample();
    await sample(30 * 60000);
    expect(c.game.stage, Stage.incubating);
    expect(c.affinityRound?.score, 0);
    expect(c.game.photoQuestCompleted, isFalse);
    await capture('nextEgg');
    await c.discardEgg();
    expect(c.game.stage, Stage.failed);
    await capture('discarded');
    final discardedRevision = last()['gameRevision'] as int;
    await sample(6000);
    expect(last()['gameRevision'], greaterThan(discardedRevision),
        reason: 'discarded egg must not stop companion heartbeat');
    expect(await c.startIncubating(EggTier.small, useAffinity: true), isTrue);
    await sample();
    await sample(41 * 60000);
    expect(c.game.stage, Stage.failed);
    await capture('failed');
    final failedRevision = last()['gameRevision'] as int;
    await sample(6000);
    expect(last()['gameRevision'], greaterThan(failedRevision),
        reason: 'failed egg must not stop companion heartbeat');
    expect(feed.hatchEvents, 1);
    expect(await store.all(), hasLength(2));
    final revisions = feed.published
        .map((g) => g.toJson()['gameRevision'])
        .whereType<int>()
        .toList();
    for (var i = 1; i < revisions.length; i++) {
      expect(revisions[i], greaterThan(revisions[i - 1]));
    }

    // Keep real serializer output; only normalize generated identifiers and wall-clock/order values.
    var index = 0;
    for (final state in captures.values.cast<Map<String, dynamic>>()) {
      state['ts'] = 1700000000000 + index;
      state['gameRevision'] = ++index;
      for (final block in ['companion', 'fishing']) {
        final value = state[block] as Map;
        value['displayId'] = 'fixture-companion';
        if (block == 'fishing') {
          value['leaseId'] = 'fixture-lease';
          value['activityId'] = 'fixture-activity';
        }
      }
    }
    final fixture = File('../data/fixtures/affinity-fishing-v2.json');
    if (Platform.environment['UPDATE_AFFINITY_FIXTURE'] == '1') {
      fixture.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(captures)}\n');
    }
    expect(captures, jsonDecode(fixture.readAsStringSync()));
  });
}
