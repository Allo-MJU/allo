import 'dart:async';

import 'package:allo_core/allo_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'vehicle_feed.dart';
import 'firebase_session_access.dart';
import '../pairing/pairing_credentials.dart';

/// Firebase Realtime Database 구현. 경로는 docs/schema.md 3장.
class FirebaseVehicleFeed implements VehicleFeed {
  FirebaseVehicleFeed(
      {FirebaseDatabase? db,
      FirebaseSessionAccess? sessionAccess,
      String functionsRegion = 'asia-northeast3'})
      : _db = db ?? FirebaseDatabase.instance,
        _sessionAccess = sessionAccess ??
            AuthenticatedFirebaseSessionAccess(
                functionsRegion: functionsRegion);

  final FirebaseDatabase _db;
  final FirebaseSessionAccess _sessionAccess;
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
    // The server authenticates, verifies the code and claims this phone UID
    // before any session data is readable. Membership/paired writes are server-only.
    await _sessionAccess.join(credentials);
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
