import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class TravelVisit {
  const TravelVisit(
      {required this.visitId,
      required this.sessionId,
      required this.routeRevision,
      required this.placeId,
      required this.placeName,
      required this.regionTag,
      required this.arrivedAtMs,
      required this.companionIds});
  final String visitId, sessionId, placeId, placeName, regionTag;
  final String routeRevision;
  final int arrivedAtMs;
  final List<String> companionIds;
}

class TravelPlaceSummary {
  const TravelPlaceSummary(
      {required this.placeId,
      required this.placeName,
      required this.regionTag,
      required this.visitCount,
      required this.lastArrivedAtMs});
  final String placeId, placeName, regionTag;
  final int visitCount, lastArrivedAtMs;
}

class TravelHistorySnapshot {
  const TravelHistorySnapshot(
      {required this.known, required this.visits, required this.places});
  static const unknown =
      TravelHistorySnapshot(known: false, visits: [], places: {});
  final bool known;
  final List<TravelVisit> visits;
  final Map<String, TravelPlaceSummary> places;
  factory TravelHistorySnapshot.fromJson(Object? value) {
    if (value == null) {
      return const TravelHistorySnapshot(known: true, visits: [], places: {});
    }
    try {
      final root = Map<String, dynamic>.from(value as Map);
      final visits = <String, TravelVisit>{};
      final places = <String, TravelPlaceSummary>{};
      void addVisit(String id, Object? raw,
          {String? companion, String? place}) {
        final j = Map<String, dynamic>.from(raw as Map);
        final ids = (j['companionIds'] ?? []) as List;
        final revision = j['routeRevision'];
        if (!(revision is String &&
                RegExp(r'^route_[0-9a-f]{16,32}$').hasMatch(revision)) &&
            !(revision is int && revision > 0)) {
          throw const FormatException();
        }
        if (j['evidence'] != 'destination-arrived' ||
            (j['visitId'] != null && j['visitId'] != id)) {
          throw const FormatException();
        }
        final v = TravelVisit(
            visitId: id,
            sessionId: j['sessionId'] as String,
            routeRevision: revision.toString(),
            placeId: j['placeId'] as String,
            placeName: j['placeName'] as String,
            regionTag: j['regionTag'] as String,
            arrivedAtMs: j['arrivedAtMs'] as int,
            companionIds: List<String>.unmodifiable(ids.cast<String>()));
        if ([v.visitId, v.sessionId, v.placeId, v.placeName, v.regionTag]
                .any((s) => s.isEmpty) ||
            v.arrivedAtMs < 0 ||
            v.companionIds.any((s) => s.isEmpty) ||
            (companion != null && !v.companionIds.contains(companion)) ||
            (place != null && v.placeId != place)) {
          throw const FormatException();
        }
        final previous = visits[id];
        if (previous != null &&
            (previous.sessionId != v.sessionId ||
                previous.routeRevision != v.routeRevision ||
                previous.placeId != v.placeId ||
                previous.placeName != v.placeName ||
                previous.regionTag != v.regionTag ||
                previous.arrivedAtMs != v.arrivedAtMs ||
                previous.companionIds.join('\u0000') !=
                    v.companionIds.join('\u0000'))) {
          throw const FormatException();
        }
        visits[id] = v;
      }

      final rawVisits =
          Map<String, dynamic>.from((root['visits'] ?? {}) as Map);
      for (final e in rawVisits.entries) {
        addVisit(e.key, e.value);
      }
      final companions =
          Map<String, dynamic>.from((root['companions'] ?? {}) as Map);
      for (final c in companions.entries) {
        if (c.key.isEmpty) throw const FormatException();
        final profile = Map<String, dynamic>.from(c.value as Map);
        final indexed =
            Map<String, dynamic>.from((profile['places'] ?? {}) as Map);
        for (final p in indexed.entries) {
          final item = Map<String, dynamic>.from(p.value as Map);
          addVisit(item['visitId'] as String, item,
              companion: c.key, place: p.key);
        }
      }
      final rawPlaces =
          Map<String, dynamic>.from((root['places'] ?? {}) as Map);
      for (final e in rawPlaces.entries) {
        final j = Map<String, dynamic>.from(e.value as Map);
        final p = TravelPlaceSummary(
            placeId: j['placeId'] as String,
            placeName: j['placeName'] as String,
            regionTag: j['regionTag'] as String,
            visitCount: j['visitCount'] as int,
            lastArrivedAtMs: j['lastArrivedAtMs'] as int);
        if (p.placeId != e.key ||
            [p.placeId, p.placeName, p.regionTag].any((s) => s.isEmpty) ||
            p.visitCount < 1 ||
            p.lastArrivedAtMs < 0) {
          throw const FormatException();
        }
        places[e.key] = p;
      }
      return TravelHistorySnapshot(
          known: true,
          visits: List.unmodifiable(visits.values),
          places: Map.unmodifiable(places));
    } catch (_) {
      throw const FormatException('Invalid travel history');
    }
  }
}

class TravelHistoryStore {
  TravelHistoryStore({FirebaseAuth? auth, FirebaseDatabase? database})
      : _auth = auth,
        _database = database;
  final FirebaseAuth? _auth;
  final FirebaseDatabase? _database;
  Future<TravelHistorySnapshot> load() async {
    try {
      final auth = _auth ?? FirebaseAuth.instance;
      final uid = auth.currentUser?.uid;
      if (uid == null) return TravelHistorySnapshot.unknown;
      final root =
          (_database ?? FirebaseDatabase.instance).ref('travelHistory/$uid');
      final snapshots = await Future.wait([
        root.child('places').get(),
        root.child('visits').orderByChild('arrivedAtMs').limitToLast(200).get(),
        root.child('companions').get(),
      ]);
      if (auth.currentUser?.uid != uid) return TravelHistorySnapshot.unknown;
      return TravelHistorySnapshot.fromJson({
        'places': snapshots[0].value ?? {},
        'visits': snapshots[1].value ?? {},
        'companions': snapshots[2].value ?? {}
      });
    } catch (_) {
      return TravelHistorySnapshot.unknown;
    }
  }
}
