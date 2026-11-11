import 'dart:async';

import 'package:allo_phone/feed/firebase_feed.dart';
import 'package:allo_phone/feed/firebase_session_access.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

const _sessionA = 'b0c260a8-e807-42e9-a119-26119837113b';
const _sessionB = 'b0c260a8-e807-42e9-a119-26119837113c';

class _Snapshot extends Fake implements DataSnapshot {
  _Snapshot(this.value);
  @override
  final Object? value;
  @override
  bool get exists => value != null;
  @override
  Iterable<DataSnapshot> get children => value is Map
      ? (value as Map).values.map((value) => _Snapshot(value))
      : const [];
}

class _Event extends Fake implements DatabaseEvent {
  _Event(Object? value) : snapshot = _Snapshot(value);
  @override
  final DataSnapshot snapshot;
}

class _Database extends Fake implements FirebaseDatabase {
  final values = <String, Object?>{};
  final reads = <String>[];
  final updates = <String>[];
  final eventStreams = <String, StreamController<DatabaseEvent>>{};
  final pendingReads = <String, Future<DataSnapshot>>{};

  void addSession(String id) {
    values['sessions/$id/meta'] = {
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'pairCode': '123456',
      'paired': false,
      'carAppVersion': 'test',
    };
  }

  @override
  DatabaseReference ref([String? path]) => _Reference(this, path ?? '');

  Future<void> close() async {
    for (final stream in eventStreams.values) {
      await stream.close();
    }
  }
}

class _Reference extends Fake implements DatabaseReference {
  _Reference(this.db, this.path);
  final _Database db;
  @override
  final String path;
  @override
  DatabaseReference child(String child) => _Reference(db, '$path/$child');
  @override
  Future<DataSnapshot> get() async {
    db.reads.add(path);
    if (db.pendingReads.containsKey(path)) return db.pendingReads[path]!;
    return _Snapshot(db.values[path]);
  }

  @override
  DatabaseReference push() => _Reference(db, '$path/push-id');
  @override
  String? get key => path.split('/').last;
  @override
  Future<void> update(Map<String, Object?> value) async {
    db.updates.add(path);
  }

  @override
  Stream<DatabaseEvent> get onChildAdded => db.eventStreams
      .putIfAbsent(path, () => StreamController<DatabaseEvent>.broadcast())
      .stream;
}

void main() {
  late _Database db;
  late FirebaseVehicleFeed feed;
  setUp(() {
    db = _Database()
      ..addSession(_sessionA)
      ..addSession(_sessionB);
    feed = FirebaseVehicleFeed(db: db, sessionAccess: _Access());
  });
  tearDown(() => db.close());

  test('과거 시각의 차량 종료 기록이 있으면 페어링 쓰기 전에 거부한다', () async {
    db.values['sessions/$_sessionA/events'] = {
      'old-end': {
        'ts': 1,
        'type': 'sessionEnd',
        'by': 'car',
        'payload': <String, Object?>{},
      },
    };
    await expectLater(feed.pair(_sessionA, pairCode: '123456'),
        throwsA(isA<PairingException>()));
    expect(db.updates, isEmpty);
  });

  test('폰 이벤트와 차량의 다른 이벤트는 종료로 보지 않는다', () async {
    db.values['sessions/$_sessionA/events'] = {
      'phone': {'ts': 1, 'type': 'sessionEnd', 'by': 'phone'},
      'car': {'ts': 2, 'type': 'destinationSuggest', 'by': 'car'},
    };
    await feed.pair(_sessionA, pairCode: '123456');
    expect(db.updates, isEmpty);
  });

  test('호출해 둔 이벤트 스트림은 다음 페어링의 세션으로 바뀌지 않는다', () async {
    await feed.pair(_sessionA, pairCode: '123456');
    final events = feed.events();
    await feed.pair(_sessionB, pairCode: '123456');
    final received = events.first;
    db.eventStreams['sessions/$_sessionA/events']!.add(_Event({
      'ts': 10,
      'by': 'car',
      'type': 'sessionEnd',
      'payload': <String, Object?>{},
    }));
    expect((await received)['type'], 'sessionEnd');
  });

  test('최신 차량 읽기는 호출한 세션에 고정되며 누락된 값은 null이다', () async {
    await feed.pair(_sessionA, pairCode: '123456');
    expect(await feed.readLatestVehicle(), isNull);
    final lastSnapshot = Completer<DataSnapshot>();
    db.pendingReads['sessions/$_sessionA/vehicle'] = lastSnapshot.future;
    final reading = feed.readLatestVehicle();
    await feed.pair(_sessionB, pairCode: '123456');
    db.values['sessions/$_sessionB/vehicle'] = {'ts': 200, 'distanceM': 100};
    lastSnapshot.complete(_Snapshot({'ts': 100, 'distanceM': 2400}));
    final vehicle = await reading;
    expect(vehicle?.ts, 100);
    expect(vehicle?.distanceM, 2400);
    expect(db.reads.lastWhere((path) => path.endsWith('/vehicle')),
        'sessions/$_sessionA/vehicle');
  });

  test('Fake 최신값 읽기는 새 틱이나 거리를 만들지 않는다', () async {
    final fake = FakeVehicleFeed(scenario: FakeScenario.rainyHighway);
    expect(await fake.readLatestVehicle(), isNull);
    final emitted =
        await fake.watch().first.timeout(const Duration(seconds: 3));
    final latest = await fake.readLatestVehicle();
    expect(latest, same(emitted));
    expect(latest?.distanceM, 500);
    expect(await fake.readLatestVehicle(), same(latest));
    await fake.dispose();
  });
}

class _Access implements FirebaseSessionAccess {
  @override
  Future<Map<String, dynamic>> join(PairingCredentials credentials) async => {
        'sessionId': credentials.sessionId,
        'paired': true,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'pairCode': credentials.code,
      };
}
