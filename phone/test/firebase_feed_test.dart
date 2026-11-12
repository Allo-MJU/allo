import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/firebase_feed.dart';
import 'package:allo_phone/feed/firebase_session_access.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

const sid = 'b0c260a8-e807-42e9-a119-26119837113b';
const sessionPath = 'sessions/$sid';

void main() {
  test('payload 없는 차량 종료 이벤트가 있으면 연결 쓰기 전에 거부한다', () async {
    final db = _Database(events: {
      'ended': {'type': 'sessionEnd', 'by': 'car', 'ts': 1},
    });
    final feed = FirebaseVehicleFeed(db: db, sessionAccess: _Access());
    await expectLater(feed.pair(sid, pairCode: '004829'),
        throwsA(isA<SessionEndedException>()));
    expect(db.updates, isEmpty);
    expect(
        () => feed.publishGame(const GameState(
            ts: 1, eggTier: EggTier.small, stage: Stage.idle, progress: 0)),
        throwsStateError);
  });

  test('서버 참여 성공 후 종료 조회만 하며 회원/paired를 직접 쓰지 않는다', () async {
    final db = _Database(events: {
      'phone': {'type': 'sessionEnd', 'by': 'phone'},
      'other': {'type': 'destinationSuggest', 'by': 'car'},
      'malformed': 'not an event',
    });
    final feed = FirebaseVehicleFeed(db: db, sessionAccess: _Access());
    await feed.pair(sid, pairCode: '004829');
    expect(db.reads, ['$sessionPath/events']);
    expect(db.updates, isEmpty);
  });

  test('이벤트가 없는 새 세션은 정상 연결한다', () async {
    final db = _Database();
    await FirebaseVehicleFeed(db: db, sessionAccess: _Access())
        .pair(sid, pairCode: '004829');
    expect(db.reads, ['$sessionPath/events']);
    expect(db.updates, isEmpty);
  });

  test('종료 여부 조회 실패를 정상 세션으로 간주하거나 쓰지 않는다', () async {
    final db = _Database()..failEvents = true;
    await expectLater(
        FirebaseVehicleFeed(db: db, sessionAccess: _Access())
            .pair(sid, pairCode: '004829'),
        throwsStateError);
    expect(db.updates, isEmpty);
  });

  test('코드가 틀리면 종료 조회와 연결 쓰기를 하지 않는다', () async {
    final db = _Database();
    await expectLater(
        FirebaseVehicleFeed(db: db, sessionAccess: _Access())
            .pair(sid, pairCode: '123456'),
        throwsA(isA<PairingException>()));
    expect(db.reads, isEmpty);
    expect(db.updates, isEmpty);
  });
}

// SDK 경계를 구현해 실제 FirebaseVehicleFeed.pair의 조회 순서와 쓰기를 검사한다.
// 사용하지 않는 SDK API는 noSuchMethod로 실패하므로 예상 밖 호출을 숨기지 않는다.
class _Database implements FirebaseDatabase {
  _Database({this.events});
  final Object? events;
  bool failEvents = false;
  final reads = <String>[];
  final updates = <(String, Map<String, Object?>)>[];

  @override
  DatabaseReference ref([String? path]) => _Reference(this, path ?? '');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reference implements DatabaseReference {
  _Reference(this.db, this.path);
  final _Database db;
  @override
  final String path;
  @override
  String? get key => path.split('/').last;
  @override
  DatabaseReference child(String path) => _Reference(db, '${this.path}/$path');
  @override
  DatabaseReference push() => child('generated');
  @override
  Future<DataSnapshot> get() async {
    db.reads.add(path);
    if (path == '$sessionPath/meta') {
      return _Snapshot({
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'pairCode': '004829',
      });
    }
    if (path == '$sessionPath/events') {
      if (db.failEvents) throw StateError('network unavailable');
      return _Snapshot(db.events);
    }
    throw StateError('Unexpected read: $path');
  }

  @override
  Future<void> update(Map<String, Object?> value) async {
    db.updates.add((path, value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot implements DataSnapshot {
  _Snapshot(this.value);
  @override
  final Object? value;
  @override
  bool get exists => value != null;
  @override
  Iterable<DataSnapshot> get children {
    final data = value;
    if (data is Map) return data.values.map(_Snapshot.new);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access implements FirebaseSessionAccess {
  @override
  Future<Map<String, dynamic>> join(PairingCredentials credentials) async {
    if (credentials.code != '004829') {
      throw const PairingException('Wrong code');
    }
    return {
      'sessionId': credentials.sessionId,
      'paired': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'pairCode': credentials.code
    };
  }
}
