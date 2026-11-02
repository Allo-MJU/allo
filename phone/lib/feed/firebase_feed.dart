import 'dart:async';

import 'package:allo_core/allo_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'vehicle_feed.dart';

/// Firebase Realtime Database 구현. 경로는 docs/schema.md 3장.
class FirebaseVehicleFeed implements VehicleFeed {
  FirebaseVehicleFeed({FirebaseDatabase? db}) : _db = db ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;
  String? _sid;

  DatabaseReference get _session {
    final sid = _sid;
    if (sid == null) throw StateError('pair() 먼저');
    return _db.ref('sessions/$sid');
  }

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    final ref = _db.ref('sessions/$sessionId/meta');
    final snap = await ref.get();
    if (!snap.exists) throw StateError('세션이 없어요');
    final meta = Map<String, dynamic>.from(snap.value as Map);
    if (pairCode != null && meta['pairCode'] != pairCode) throw StateError('코드가 달라요');
    _sid = sessionId;
    await ref.update({'paired': true});
    await emitEvent('paired');
  }

  @override
  Stream<VehicleState> watch() => _session.child('vehicle').onValue.where((e) => e.snapshot.value != null).map(
        (e) => VehicleState.fromJson(_asMap(e.snapshot.value)),
      );

  @override
  Future<void> publishGame(GameState state) => _session.child('game').set(state.toJson());

  @override
  Future<void> emitEvent(String type, {Map<String, Object?> payload = const {}}) => _session.child('events').push().set({
        'ts': ServerValue.timestamp,
        'type': type,
        'by': 'phone',
        'payload': payload,
      });

  @override
  Stream<Map<String, Object?>> events() => _session.child('events').onChildAdded.map((e) => _asMap(e.snapshot.value)).where((m) => m['by'] == 'car');

  @override
  Future<void> dispose() async {}

  static Map<String, dynamic> _asMap(Object? v) => Map<String, dynamic>.from(v as Map);
}
