import 'dart:convert';
import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/fishing/fishing_controller.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryFishingStore extends FishingStore {
  Map<String, dynamic>? data;
  bool fail = false;
  Completer<void>? gate;
  Map<String, dynamic> clone(Map<String, dynamic> p) =>
      (jsonDecode(jsonEncode(p)) as Map).cast<String, dynamic>();
  @override
  Future<Map<String, dynamic>?> read() async =>
      data == null ? null : clone(data!);
  @override
  Future<void> write(Map<String, dynamic> p) async {
    await gate?.future;
    if (fail) throw StateError('disk');
    data = clone(p);
  }
}

DexEntry entry(String id, int at) => DexEntry(
    speciesId: id,
    obtainedAt: DateTime.fromMillisecondsSinceEpoch(at),
    envTags: const [],
    regionTag: null,
    tier: 1);
void main() {
  late MemoryFishingStore store;
  late FishingController c;
  var now = 0, seq = 0, ids = 0;
  FishingController create() => FishingController(
      store: store,
      onChanged: () {},
      clockMs: () => now,
      newId: () => 'id-${++ids}');
  Map<String, dynamic> f() =>
      c.snapshotFields['fishing'] as Map<String, dynamic>;
  Future<void> presence(
      {int delta = 1000,
      String? lease,
      int? sequence,
      String epoch = 'car',
      bool active = true,
      bool parked = true}) async {
    now += delta;
    c.observePresence({
      'version': 1,
      'leaseId': lease ?? f()['leaseId'],
      'epoch': epoch,
      'sequence': sequence ?? ++seq,
      'active': active,
      'parkedAllowed': parked
    });
    await c.settled;
  }

  Map<String, Object?> request(String action, String id) {
    final x = f();
    return {
      'type': 'fishingRequested',
      'by': 'car',
      'payload': {
        'requestId': id,
        'action': action,
        'leaseId': x['leaseId'],
        'displayId': x['displayId'],
        'displayRevision': x['displayRevision'],
        'activityId': x['activityId'],
        'cycle': x['cycle']
      }
    };
  }

  Future<void> advance(int n) async {
    for (var i = 0; i < n; i++) {
      await presence();
    }
  }

  Future<void> start() async {
    await presence(delta: 0);
    await c.handleEvent(request('start', 'start'));
    await presence();
  }

  setUp(() async {
    store = MemoryFishingStore();
    now = 0;
    seq = 0;
    ids = 0;
    c = create();
    await c.attach('session');
    await c.select(entry('road_sprout', 1));
  });
  tearDown(() => c.dispose());
  test('도감의 동일 종 획득 기록은 선택과 관찰 기록을 공유하지 않는다', () async {
    final first = entry('road_sprout', 1);
    final second = entry('road_sprout', 2);
    expect(c.isSelected(first), isTrue);
    expect(c.isSelected(second), isFalse);
    expect(c.companionLocation, 'car');
    await start();
    await advance(60);
    expect(c.recordsFor(first), 1);
    expect(c.recordsFor(second), 0);
    await c.select(second);
    expect(c.isSelected(first), isFalse);
    expect(c.isSelected(second), isTrue);
    expect(c.recordsFor(first), 1);
    expect(c.recordsFor(second), 0);
  });
  test('저장 실패한 도감 선택은 현재 선택 표시를 바꾸지 않는다', () async {
    store.fail = true;
    final second = entry('puddle_pip', 2);
    await c.select(second);
    expect(c.isSelected(entry('road_sprout', 1)), isTrue);
    expect(c.isSelected(second), isFalse);
    expect(c.error, isNotNull);
  });

  test(
      '60 valid seconds atomically grants one reward, duplicates do not repeat',
      () async {
    await start();
    await advance(59);
    expect(f()['elapsedMs'], 59000);
    expect(c.totalRecords, 0);
    await advance(1);
    expect(f()['state'], 'reward');
    expect(c.totalRecords, 1);
    expect(f()['cycle'], 1);
    expect(f()['rewardName'], '물고기 관찰 1');
    await presence(delta: 0, sequence: seq);
    expect(c.totalRecords, 1);
    await advance(1);
    expect(f()['elapsedMs'], 0);
    await advance(60);
    expect(c.totalRecords, 2);
  });
  test('duplicate start preserves elapsed progress', () async {
    await presence(delta: 0);
    final r = request('start', 'same');
    await c.handleEvent(r);
    await presence();
    await advance(4);
    await c.handleEvent(r);
    expect(f()['elapsedMs'], 4000);
    expect(f()['requestId'], 'same');
  });
  test(
      'reward failure exposes no reward and retry persists exactly once across restart',
      () async {
    await start();
    await advance(59);
    store.fail = true;
    await advance(1);
    expect(f()['state'], 'saveFailed');
    expect(c.totalRecords, 0);
    expect(f()['rewardName'], isNull);
    await advance(5);
    expect(c.totalRecords, 0);
    store.fail = false;
    await c.retrySave();
    expect(c.totalRecords, 1);
    expect(f()['state'], 'paused');
    await c.retrySave();
    expect(c.totalRecords, 1);
    final revision = c.snapshotFields['gameRevision'] as int;
    c.dispose();
    c = create();
    await c.attach('session');
    expect(c.totalRecords, 1);
    expect(f()['state'], 'paused');
    expect(c.snapshotFields['gameRevision'], greaterThan(revision));
  });
  test('checkpoint failure blocks selection and accrual until durable retry',
      () async {
    await start();
    store.fail = true;
    await advance(5);
    await c.select(entry('sea_mist', 2));
    expect(c.selectedSpeciesId, 'road_sprout');
    await advance(5);
    expect(f()['elapsedMs'], 5000);
    store.fail = false;
    await c.retrySave();
    expect(f()['state'], 'paused');
    await c.select(entry('sea_mist', 2));
    expect(c.selectedSpeciesId, 'sea_mist');
  });
  test('lifecycle rotates lease and rejects stale presence or commands',
      () async {
    await start();
    await advance(2);
    final old = f()['leaseId'] as String;
    await c.setActive(false);
    await c.setActive(true);
    await presence(lease: old);
    await c.handleEvent(request('resume', 'r1'));
    expect(f()['state'], 'paused');
    await presence();
    await c.handleEvent(request('resume', 'r2'));
    await presence();
    await advance(1);
    expect(f()['elapsedMs'], 3000);
  });
  test('sequence gaps and epoch changes pause instead of adding missing time',
      () async {
    await start();
    await advance(2);
    await presence(sequence: seq + 3);
    expect(f()['state'], 'paused');
    expect(f()['elapsedMs'], 2000);
    await presence();
    await c.handleEvent(request('resume', 'r'));
    await presence();
    await presence(epoch: 'new');
    expect(f()['state'], 'paused');
    expect(f()['elapsedMs'], 2000);
  });
  test('watchdog pauses autonomously and rotates lease', () async {
    await start();
    await advance(2);
    final old = f()['leaseId'];
    now += 3001;
    await c.tick();
    expect(f()['state'], 'paused');
    expect(f()['elapsedMs'], 2000);
    expect(f()['leaseId'], isNot(old));
  });
  test('2s interval inclusive, longer interval fails closed', () async {
    await start();
    await presence(delta: 2000);
    expect(f()['elapsedMs'], 2000);
    await presence(delta: 2001);
    expect(f()['state'], 'paused');
    expect(f()['elapsedMs'], 2000);
  });
  test('negative eligibility pauses even with duplicate sequence', () async {
    await start();
    await advance(1);
    await presence(parked: false, sequence: seq);
    expect(f()['state'], 'paused');
    expect(f()['elapsedMs'], 1000);
    await presence();
    await c.handleEvent(request('resume', 'r'));
    await presence();
    await presence(active: false);
    expect(f()['state'], 'paused');
  });
  test('same species different entries keep independent progress', () async {
    await start();
    await advance(3);
    await c.select(entry('road_sprout', 2));
    expect(f()['elapsedMs'], 0);
    await c.select(entry('road_sprout', 1));
    expect(f()['elapsedMs'], 3000);
    expect(f()['state'], 'paused');
  });
  test('restored running checkpoint is paused with no offline credit',
      () async {
    await start();
    await advance(5);
    c.dispose();
    now += 900000;
    c = create();
    await c.attach('session');
    expect(f()['state'], 'paused');
    expect(f()['elapsedMs'], 5000);
    await presence();
    expect(f()['elapsedMs'], 5000);
  });
  test(
      'transfer location and receipt commit together, no false success on failure',
      () async {
    await start();
    await advance(2);
    final x = f();
    final r = {
      'type': 'companionTransferRequested',
      'by': 'car',
      'payload': {
        'requestId': 't',
        'displayId': x['displayId'],
        'displayRevision': x['displayRevision']
      }
    };
    store.fail = true;
    await c.handleEvent(r);
    expect((c.snapshotFields['companion'] as Map)['location'], 'car');
    expect(c.snapshotFields['transferResult'], isNull);
    store.fail = false;
    await c.retrySave();
    expect((c.snapshotFields['companion'] as Map)['location'], 'phone');
    expect((c.snapshotFields['transferResult'] as Map)['status'], 'accepted');
    expect(store.data!['location'], 'phone');
    expect((store.data!['transferReceipts'] as Map).containsKey('t'), true);
  });
  test('failed selection retains old display until atomic retry', () async {
    final old = (c.snapshotFields['companion'] as Map)['displayId'];
    store.fail = true;
    await c.select(entry('sea_mist', 2));
    expect(c.selectedSpeciesId, 'road_sprout');
    expect((c.snapshotFields['companion'] as Map)['displayId'], old);
    store.fail = false;
    await c.retrySave();
    expect(c.selectedSpeciesId, 'sea_mist');
  });
  test('new session changes lease and advances revision reservation', () async {
    final old = f()['leaseId'];
    final high = c.snapshotFields['gameRevision'] as int;
    await c.detach();
    await c.setActive(true);
    await c.attach('new');
    expect(c.snapshotFields['gameRevision'], greaterThan(high));
    expect(f()['leaseId'], isNot(old));
  });
  test('malformed profile fails closed without erasing saved records',
      () async {
    c.dispose();
    store.data = {'version': 999};
    c = create();
    await c.attach('session');
    expect(c.initialized, false);
    expect(c.error, isNotNull);
    expect(store.data, {'version': 999});
    expect(c.snapshotFields, isEmpty);
  });
  test('vehicle retry can use a fresh lease after failed write', () async {
    await start();
    store.fail = true;
    await advance(5);
    store.fail = false;
    await presence();
    await c.handleEvent(request('retry', 'retry'));
    expect(f()['state'], 'paused');
    expect(c.error, isNull);
  });
  test(
      'same selected phone companion returns to car with new display and retained progress',
      () async {
    await start();
    await advance(3);
    final x = f();
    final r = {
      'type': 'companionTransferRequested',
      'by': 'car',
      'payload': {
        'requestId': 'transfer',
        'displayId': x['displayId'],
        'displayRevision': x['displayRevision']
      }
    };
    await c.handleEvent(r);
    expect((c.snapshotFields['companion'] as Map)['location'], 'phone');
    await c.handleEvent(r);
    expect((c.snapshotFields['transferResult'] as Map)['status'], 'accepted');
    c.dispose();
    c = create();
    await c.attach('session');
    await c.handleEvent(r);
    expect(
        (c.snapshotFields['transferResult'] as Map)['requestId'], 'transfer');
    await c.select(entry('road_sprout', 1));
    expect((c.snapshotFields['companion'] as Map)['location'], 'car');
    expect(f()['displayId'], isNot(x['displayId']));
    expect(f()['elapsedMs'], 3000);
    expect(f()['state'], 'paused');
  });
  test(
      'new lease retry acknowledges new request without losing committed receipt',
      () async {
    await start();
    store.fail = true;
    await advance(5);
    store.fail = false;
    await presence();
    await c.handleEvent(request('retry', 'new-retry'));
    expect(f()['requestId'], 'new-retry');
    expect(f()['state'], 'paused');
  });
  test(
      'save operations expose saving before persisted reward and no false record',
      () async {
    final states = <String>[];
    c.dispose();
    c = FishingController(
        store: store,
        clockMs: () => now,
        newId: () => 'id-${++ids}',
        onChanged: () {
          if (c.initialized && c.selectedSpeciesId != null) {
            states.add((c.snapshotFields['fishing'] as Map)['state'] as String);
          }
        });
    await c.attach('session');
    await start();
    await advance(60);
    expect(states, contains('saving'));
    expect(c.totalRecords, 1);
    expect(f()['state'], 'reward');
  });
  test('presence received during blocked reward save never accrues next cycle',
      () async {
    await start();
    await advance(59);
    store.gate = Completer<void>();
    now += 1000;
    c.observePresence({
      'version': 1,
      'leaseId': f()['leaseId'],
      'epoch': 'car',
      'sequence': ++seq,
      'active': true,
      'parkedAllowed': true
    });
    await Future<void>.delayed(Duration.zero);
    expect(f()['state'], 'saving');
    for (var i = 0; i < 10; i++) {
      now += 1000;
      c.observePresence({
        'version': 1,
        'leaseId': f()['leaseId'],
        'epoch': 'car',
        'sequence': ++seq,
        'active': true,
        'parkedAllowed': true
      });
    }
    store.gate!.complete();
    await c.settled;
    store.gate = null;
    expect(c.totalRecords, 1);
    expect(f()['state'], 'reward');
    await presence();
    expect(f()['state'], 'paused');
    await presence();
    await c.handleEvent(request('resume', 'after-save'));
    await presence();
    expect(f()['elapsedMs'], 0);
    expect(c.totalRecords, 1);
  });
  test(
      'background transition fences already queued presence before disk settles',
      () async {
    await start();
    await advance(4);
    store.gate = Completer<void>();
    now += 1000;
    c.observePresence({
      'version': 1,
      'leaseId': f()['leaseId'],
      'epoch': 'car',
      'sequence': ++seq,
      'active': true,
      'parkedAllowed': true
    });
    await Future<void>.delayed(Duration.zero);
    final paused = c.setActive(false);
    final old = f()['elapsedMs'];
    now += 1000;
    c.observePresence({
      'version': 1,
      'leaseId': f()['leaseId'],
      'epoch': 'car',
      'sequence': ++seq,
      'active': true,
      'parkedAllowed': true
    });
    store.gate!.complete();
    await paused;
    await c.settled;
    expect(f()['state'], 'paused');
    expect(f()['elapsedMs'], old);
  });
  test('unprocessed old transfer cannot execute after same-session restart',
      () async {
    await presence();
    final old = f();
    final r = {
      'type': 'companionTransferRequested',
      'by': 'car',
      'payload': {
        'requestId': 'unprocessed',
        'displayId': old['displayId'],
        'displayRevision': old['displayRevision']
      }
    };
    c.dispose();
    c = create();
    await c.attach('session');
    await presence();
    expect(f()['displayId'], isNot(old['displayId']));
    await c.handleEvent(r);
    expect((c.snapshotFields['transferResult'] as Map)['status'],
        'staleSelection');
    expect((c.snapshotFields['companion'] as Map)['location'], 'car');
  });
}
