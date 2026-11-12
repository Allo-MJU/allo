import 'dart:convert';
import 'dart:io';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_end_test.dart' show EndFeed;
import 'session_resume_test.dart' show sessionA;

class MemoryFishingStore extends FishingStore {
  Map<String, dynamic>? data;
  bool failRead = false, failWrite = false;
  @override
  Future<Map<String, dynamic>?> read() async {
    if (failRead) throw StateError('read failure');
    return data == null
        ? null
        : (jsonDecode(jsonEncode(data)) as Map).cast<String, dynamic>();
  }

  @override
  Future<void> write(Map<String, dynamic> profile) async {
    if (failWrite) throw StateError('write failure');
    data = (jsonDecode(jsonEncode(profile)) as Map).cast<String, dynamic>();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shared wire fixture survives full-game serializer and presence reader',
      () {
    final fixture =
        jsonDecode(File('../data/fixtures/fishing-v1.json').readAsStringSync())
            as Map;
    final expected = Map<String, dynamic>.from(fixture['game'] as Map);
    final features = Map<String, dynamic>.from(expected)
      ..removeWhere((k, _) => ![
            'contractVersion',
            'gameRevision',
            'companion',
            'fishing'
          ].contains(k));
    final game = GameState(
        ts: expected['ts'],
        eggTier: EggTier.small,
        stage: Stage.incubating,
        progress: .25,
        vehicleFeatures: features);
    final serialized = game.toJson();
    for (final key in expected.keys) {
      expect(serialized[key], expected[key], reason: key);
    }
    expect(
        VehicleState.fromJson({'fishingPresence': fixture['presence']})
            .fishingPresence,
        fixture['presence']);
    expect(VehicleState.fromJson({'fishingPresence': 'bad'}).fishingPresence,
        isNull);
  });

  test(
      'real feed API selects owned record, processes parking requests, saves reward and restores',
      () async {
    var now = 0;
    final feed = EndFeed();
    final store = MemoryFishingStore();
    final dex = DexStore();
    final c = GameController(
        feed: feed, dex: dex, fishingStore: store, monotonicMs: () => now);
    addTearDown(c.dispose);
    final entry = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026, 11, 11),
        envTags: const [],
        regionTag: null,
        tier: 1);
    await dex.add(entry);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.selectCarCompanion(entry), isTrue);
    Future<void> settle() async {
      await c.fishing.settled;
      await Future<void>.delayed(Duration.zero);
    }

    await settle();
    var seq = 0;
    Map<String, dynamic> lastFishing() => Map<String, dynamic>.from(
        feed.published.last.toJson()['fishing'] as Map);
    Future<void> sample() async {
      feed.signals.add(VehicleState.fromJson({
        'ts': now + 1,
        'gear': 'P',
        'fishingPresence': {
          'version': 1,
          'leaseId': lastFishing()['leaseId'],
          'epoch': 'car-test',
          'sequence': ++seq,
          'active': true,
          'parkedAllowed': true,
        }
      }));
      await settle();
    }

    await sample();
    final f = lastFishing();
    final request = <String, Object?>{
      'by': 'car',
      'type': 'fishingRequested',
      'payload': {
        'requestId': 'start-one',
        'leaseId': f['leaseId'],
        'displayId': f['displayId'],
        'displayRevision': f['displayRevision'],
        'activityId': f['activityId'],
        'cycle': f['cycle'],
        'action': 'start',
      }
    };
    feed.carEvents.add(request);
    await settle();
    expect(lastFishing()['state'], 'running');
    await sample(); // Start establishes a fresh baseline; no pre-request time is credited.
    for (var i = 0; i < 60; i++) {
      now += 1000;
      await sample();
    }
    expect(lastFishing()['state'], 'reward');
    expect(lastFishing()['totalRecords'], 1);
    expect(lastFishing()['rewardName'], isNotEmpty);
    feed.carEvents.add(request);
    await settle();
    expect(lastFishing()['totalRecords'], 1);
    expect(c.game.stage, Stage.idle,
        reason: 'fishing must not start/reset an egg');
    final revisions = feed.published
        .map((g) => g.toJson()['gameRevision'])
        .whereType<int>()
        .toList();
    for (var i = 1; i < revisions.length; i++) {
      expect(revisions[i], greaterThan(revisions[i - 1]));
    }
    final before = store.data;
    final other = GameController(
        feed: EndFeed(), dex: dex, fishingStore: store, monotonicMs: () => now);
    addTearDown(other.dispose);
    await other.pair(sessionA, pairCode: '123456');
    expect(other.fishing.totalRecords, 1);
    expect(other.game.toJson()['gameRevision'], greaterThan(revisions.last));
    expect(before, isNotNull);
  });

  test('unowned same-species record cannot be selected', () async {
    final c = GameController(
        feed: EndFeed(), dex: DexStore(), fishingStore: MemoryFishingStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(
        await c.selectCarCompanion(DexEntry(
            speciesId: 'road_sprout',
            obtainedAt: DateTime.utc(2026),
            envTags: [],
            regionTag: null,
            tier: 1)),
        isFalse);
    expect(c.fishing.selectedSpeciesId, isNull);
  });
  test(
      'failed initialization can pair again and first selection retry starts vehicle subscription',
      () async {
    var now = 0;
    final feed = EndFeed();
    final store = MemoryFishingStore()..failRead = true;
    final dex = DexStore();
    final c = GameController(
        feed: feed, dex: dex, fishingStore: store, monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(c.fishing.initialized, isFalse);
    store.failRead = false;
    await c.pair(sessionA, pairCode: '123456');
    expect(c.fishing.initialized, isTrue);
    final entry = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: [],
        regionTag: null,
        tier: 1);
    await dex.add(entry);
    store.failWrite = true;
    expect(await c.selectCarCompanion(entry), isFalse);
    store.failWrite = false;
    await c.fishing.retrySave();
    await Future<void>.delayed(Duration.zero);
    expect(feed.signals.hasListener, isTrue);
    final f = Map<String, dynamic>.from(
        feed.published.last.toJson()['fishing'] as Map);
    feed.signals.add(VehicleState.fromJson({
      'ts': 1,
      'gear': 'P',
      'fishingPresence': {
        'version': 1,
        'leaseId': f['leaseId'],
        'epoch': 'car',
        'sequence': 1,
        'active': true,
        'parkedAllowed': true,
      }
    }));
    await c.fishing.settled;
    feed.carEvents.add({
      'by': 'car',
      'type': 'fishingRequested',
      'payload': {
        'requestId': 'start',
        'leaseId': f['leaseId'],
        'displayId': f['displayId'],
        'displayRevision': f['displayRevision'],
        'action': 'start',
        'activityId': f['activityId'],
        'cycle': f['cycle'],
      }
    });
    await c.fishing.settled;
    await Future<void>.delayed(Duration.zero);
    expect(
        (feed.published.last.toJson()['fishing'] as Map)['state'], 'running');
    store.failWrite = true;
    feed.carEvents.add({'by': 'car', 'type': 'sessionEnd'});
    expect(await c.endSession(), isFalse);
    expect(c.sessionSaved, isFalse);
    store.failWrite = false;
    expect(await c.endSession(), isTrue);
    expect(c.sessionSaved, isTrue);
    await c.pair('b0c260a8-e807-42e9-a119-26119837113c', pairCode: '123456');
    expect(c.fishing.initialized, isTrue);
    await Future<void>.delayed(Duration.zero);
    final next = Map<String, dynamic>.from(
        feed.published.last.toJson()['fishing'] as Map);
    feed.signals.add(VehicleState.fromJson({
      'ts': 2,
      'gear': 'P',
      'fishingPresence': {
        'version': 1,
        'leaseId': next['leaseId'],
        'epoch': 'next-car',
        'sequence': 1,
        'active': true,
        'parkedAllowed': true,
      }
    }));
    await c.fishing.settled;
    feed.carEvents.add({
      'by': 'car',
      'type': 'fishingRequested',
      'payload': {
        'requestId': 'resume',
        'leaseId': next['leaseId'],
        'displayId': next['displayId'],
        'displayRevision': next['displayRevision'],
        'action': 'resume',
        'activityId': next['activityId'],
        'cycle': next['cycle'],
      }
    });
    await c.fishing.settled;
    await Future<void>.delayed(Duration.zero);
    expect(
        (feed.published.last.toJson()['fishing'] as Map)['state'], 'running');
  });
}
