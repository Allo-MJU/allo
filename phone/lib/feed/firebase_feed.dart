import 'dart:async';

import 'package:allo_core/allo_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'vehicle_feed.dart';
import '../pairing/pairing_credentials.dart';

/// Firebase Realtime Database 구현. 경로는 docs/schema.md 3장.
class FirebaseVehicleFeed implements VehicleFeed {
  FirebaseVehicleFeed({FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;
  String? _sid;

  DatabaseReference get _session {
    final sid = _sid;
    if (sid == null) throw StateError('pair() 먼저');
    return _db.ref('sessions/$sid');
  }

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    _sid = null;
    final credentials =
        PairingCredentials.parseFields(sessionId, pairCode ?? '');
    final session = _db.ref('sessions/${credentials.sessionId}');
    final snap =
        await session.child('meta').get().timeout(const Duration(seconds: 10));
    credentials.validateMeta(snap.exists ? _asMap(snap.value) : null,
        now: DateTime.now());
    final events = await session
        .child('events')
        .get()
        .timeout(const Duration(seconds: 10));
    // payload는 빈 객체일 때 Firebase에서 생략된다. 발신자와 타입만 확인한다.
    final ended = events.children.any((snapshot) {
      final event = snapshot.value;
      return event is Map &&
          event['by'] == 'car' &&
          event['type'] == 'sessionEnd';
    });
    if (ended) throw const SessionEndedException();
    final eventKey = session.child('events').push().key!;
    // 페어링 표시와 이벤트를 한 번에 기록한 뒤에만 게임 발행을 허용한다.
    await session.update({
      'meta/paired': true,
      'events/$eventKey': {
        'ts': ServerValue.timestamp,
        'type': 'paired',
        'by': 'phone',
        'payload': <String, Object?>{},
      },
    }).timeout(const Duration(seconds: 10));
    _sid = credentials.sessionId;
  }

  @override
  Stream<VehicleState> watch() => _session
      .child('vehicle')
      .onValue
      .where((e) => e.snapshot.value != null)
      .map(
        (e) => VehicleState.fromJson(_asMap(e.snapshot.value)),
      );

  @override
  Future<VehicleState?> readLatestVehicle() async {
    final session = _session;
    final snapshot = await session
        .child('vehicle')
        .get()
        .timeout(const Duration(seconds: 10));
    return snapshot.value == null
        ? null
        : VehicleState.fromJson(_asMap(snapshot.value));
  }

  @override
  Future<void> publishGame(GameState state) =>
      _session.child('game').set(state.toJson());

  @override
  Future<void> emitEvent(String type,
          {Map<String, Object?> payload = const {}}) =>
      _session.child('events').push().set({
        'ts': ServerValue.timestamp,
        'type': type,
        'by': 'phone',
        'payload': payload,
      });

  @override
  Stream<Map<String, Object?>> events() {
    final session = _session;
    return session
        .child('events')
        .onChildAdded
        .map((e) => _asMap(e.snapshot.value))
        .where((m) => m['by'] == 'car');
  }

  @override
  Future<void> dispose() async {}

  static Map<String, dynamic> _asMap(Object? v) =>
      Map<String, dynamic>.from(v as Map);
}
