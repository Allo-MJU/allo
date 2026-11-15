import 'package:allo_phone/quests/travel_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmed empty is different from unknown', () {
    expect(TravelHistorySnapshot.fromJson(null).known, true);
    expect(TravelHistorySnapshot.unknown.known, false);
  });
  test('parses persisted arrival and place summary without inventing visits',
      () {
    final history = TravelHistorySnapshot.fromJson({
      'visits': {
        'visit-1': {
          'visitId': 'visit-1',
          'sessionId': 'trip',
          'routeRevision': 1,
          'evidence': 'destination-arrived',
          'placeId': 'place-1',
          'placeName': '바닷가',
          'regionTag': 'coast',
          'arrivedAtMs': 1000,
          'companionIds': ['creature-1']
        }
      },
      'places': {
        'place-1': {
          'placeId': 'place-1',
          'placeName': '바닷가',
          'regionTag': 'coast',
          'visitCount': 1,
          'lastArrivedAtMs': 1000
        }
      }
    });
    expect(history.known, true);
    expect(history.visits.single.companionIds, ['creature-1']);
    expect(history.places['place-1']!.lastArrivedAtMs, 1000);
    expect(
        () => TravelHistorySnapshot.fromJson({
              'visits': {
                'x': {'placeName': 'invalid'}
              }
            }),
        throwsFormatException);
  });
  test('reads callable persisted visit and rejects non-arrival evidence', () {
    final visit = <String, dynamic>{
      'sessionId': 'trip',
      'routeRevision': 'route_1234567890abcdef',
      'placeId': 'place-1',
      'placeName': '바닷가',
      'regionTag': 'coast',
      'arrivedAtMs': 1000,
      'receivedAtMs': 1100,
      'companionIds': ['creature-1'],
      'evidence': 'destination-arrived'
    };
    final history = TravelHistorySnapshot.fromJson({
      'visits': {'visit_1234567890abcdef': visit}
    });
    expect(history.visits.single.visitId, 'visit_1234567890abcdef');
    expect(history.visits.single.routeRevision, 'route_1234567890abcdef');
    visit['evidence'] = 'unknown';
    expect(
        () => TravelHistorySnapshot.fromJson({
              'visits': {'v': visit}
            }),
        throwsFormatException);
  });
  test('merges a companion place arrival outside the recent visit window', () {
    final visit = <String, dynamic>{
      'visitId': 'visit_old',
      'sessionId': 'trip',
      'routeRevision': 'route_1234567890abcdef',
      'placeId': 'p',
      'placeName': '바다',
      'regionTag': 'coast',
      'arrivedAtMs': 1000,
      'receivedAtMs': 1100,
      'companionIds': ['creature-1'],
      'evidence': 'destination-arrived'
    };
    final history = TravelHistorySnapshot.fromJson({
      'companions': {
        'creature-1': {
          'places': {'p': visit}
        }
      }
    });
    expect(history.visits.single.visitId, 'visit_old');
    visit['companionIds'] = ['another'];
    expect(
        () => TravelHistorySnapshot.fromJson({
              'companions': {
                'creature-1': {
                  'places': {'p': visit}
                }
              }
            }),
        throwsFormatException);
  });
}
