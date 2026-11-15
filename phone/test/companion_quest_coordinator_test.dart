import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/quests/companion_quest_coordinator.dart';
import 'package:allo_phone/quests/travel_history_store.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmptyHistory extends TravelHistoryStore {
  @override
  Future<TravelHistorySnapshot> load() async =>
      TravelHistorySnapshot.fromJson(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'hidden quests stop polling and discard pre-switch arrivals and templates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dex = DexStore(namespace: 'quest-lifecycle.');
    for (final egg in ['travel', 'offer']) {
      await dex.add(DexEntry(
          speciesId: 'road_sprout',
          sourceEggId: egg,
          obtainedAt: DateTime.utc(2026),
          envTags: const [],
          regionTag: null,
          tier: 1));
    }
    var now = 1700000000000;
    final camp = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'quest-lifecycle'),
        dex: dex,
        nowMs: () => now);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.sceneTour),
        dex: dex,
        baseCamp: camp);
    await camp.load();
    final ids = camp.state.creatures.keys.toList();
    final travel = ids.first, other = ids.last;
    await camp.offerQuest(CompanionQuest(
        creatureId: travel,
        questId: 'trip',
        kind: CompanionQuestKind.travel,
        templateId: 'travel',
        templateVersion: 1,
        issuedAtMs: now,
        nextEligibleAtMs: now + BaseCamp.questIntervalMs));
    await camp.acceptQuest(travel, 'trip', targetPlaceId: 'shore');
    now += 1000;
    final arrival = TravelHistorySnapshot.fromJson({
      'visits': {
        'v': {
          'sessionId': 's',
          'routeRevision': 'route_1234567890abcdef',
          'evidence': 'destination-arrived',
          'placeId': 'shore',
          'placeName': '바다',
          'regionTag': 'coast',
          'arrivedAtMs': now,
          'companionIds': [travel]
        }
      }
    });
    final history = ControlledHistory();
    var requests = 0;
    final oldTemplate = Completer<Map<String, dynamic>>();
    final coordinator = CompanionQuestCoordinator(
        game: game,
        camp: camp,
        historyStore: history,
        loadPlaces: () async => [],
        nowMs: () => now,
        templateRequest: (_) {
          requests++;
          return oldTemplate.future;
        });
    try {
      await coordinator.initialize();
      expect(history.reads, 1);
      coordinator.setActive(false);
      await tester.pump(const Duration(seconds: 31));
      await coordinator.refresh();
      expect(history.reads, 1,
          reason:
              'Neither the timer nor a manual refresh should read while hidden');
      final hiddenOpen = coordinator.open(other);
      expect(requests, 0);
      await hiddenOpen;

      coordinator.setActive(true);
      await tester.pump();
      final staleHistory = history.gate = Completer<TravelHistorySnapshot>();
      final beforeRead = history.reads;
      final oldRead = coordinator.refresh();
      expect(history.reads, beforeRead + 1);
      final oldOpen = coordinator.open(other);
      expect(requests, 1);
      coordinator.setActive(false);
      history.gate = null;
      coordinator.setActive(true);
      await tester.pump();
      staleHistory.complete(arrival);
      oldTemplate.complete({
        'schemaVersion': 1,
        'templateId': 'snack',
        'templateVersion': 1,
        'speciesId': 'road_sprout',
        'kind': 'food',
        'title': '간식',
        'text': '함께 먹자',
        'storyId': null,
        'targetFoodId': 'berry_snack',
        'targetRegion': null
      });
      await Future.wait([oldRead, oldOpen]);
      expect(camp.state.quests[travel]!.status, CompanionQuestStatus.accepted);
      expect(camp.state.quests[other], isNull);

      final reads = history.reads;
      history.value = arrival;
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(history.reads, reads + 1);
      expect(camp.state.quests[travel]!.completedVisitId, 'v');
    } finally {
      coordinator.dispose();
      game.dispose();
      camp.dispose();
    }
  });
  test('invitation opens only after user request and preserves its id',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dex = DexStore(namespace: 'quest-test.');
    await dex.add(DexEntry(
        speciesId: 'road_sprout',
        sourceEggId: 'egg',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1));
    final store =
        DelayedStore(SharedPreferencesBaseCampStore(profile: 'quest-test'));
    var now = 1700000000000;
    final camp = BaseCampController(store: store, dex: dex, nowMs: () => now);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.sceneTour),
        dex: dex,
        baseCamp: camp);
    await camp.load();
    var requests = 0;
    final c = CompanionQuestCoordinator(
        game: game,
        camp: camp,
        historyStore: EmptyHistory(),
        loadPlaces: () async => [],
        nowMs: () => now,
        templateRequest: (body) async {
          requests++;
          return {
            'schemaVersion': 1,
            'templateId': 'food-1',
            'templateVersion': 1,
            'speciesId': 'road_sprout',
            'kind': 'food',
            'title': '간식',
            'text': '함께 먹자',
            'storyId': null,
            'targetFoodId': 'berry_snack',
            'targetRegion': null
          };
        });
    addTearDown(c.dispose);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await c.initialize();
    expect(requests, 0);
    final invitation = c.snapshot.single;
    expect(invitation['available'], true);
    expect(invitation['opened'], false);
    await c.open(invitation['creatureId'] as String,
        questId: invitation['questId'] as String);
    expect(requests, 1);
    expect(c.snapshot.single['opened'], true);
    expect(c.snapshot.single['questId'], invitation['questId']);
    store.gate = Completer<void>();
    final id = invitation['creatureId'] as String;
    final questId = invitation['questId'] as String;
    final first = c.accept(id, questId);
    final second = c.accept(id, questId);
    store.gate!.complete();
    await Future.wait([first, second]);
    expect(c.snapshot.single['status'], 'accepted');
    expect(c.snapshot.single['error'], isNull);
    now += BaseCamp.questIntervalMs + 1;
    await camp.grantCollectionReward('trip');
    await camp.feedFood('berry_snack', id);
    expect(c.snapshot.single['questId'], questId);
    expect(c.snapshot.single['status'], 'completed');
    c.later(id);
    expect(c.snapshot.single['questId'], isNot(questId));
  });
  test('a later confirmed arrival completes only the accepted matching trip',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dex = DexStore(namespace: 'quest-travel.');
    await dex.add(DexEntry(
        speciesId: 'road_sprout',
        sourceEggId: 'egg',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1));
    var now = 1700000000000;
    final camp = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'quest-travel'),
        dex: dex,
        nowMs: () => now);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.sceneTour),
        dex: dex,
        baseCamp: camp);
    await camp.load();
    final id = camp.state.creatures.keys.single;
    final q = CompanionQuest(
        creatureId: id,
        questId: 'q',
        kind: CompanionQuestKind.travel,
        templateId: 't',
        templateVersion: 1,
        issuedAtMs: now,
        nextEligibleAtMs: now + BaseCamp.questIntervalMs);
    expect(await camp.offerQuest(q), true);
    expect(await camp.acceptQuest(id, 'q', targetPlaceId: 'p'), true);
    final history = MutableHistory();
    final c = CompanionQuestCoordinator(
        game: game,
        camp: camp,
        historyStore: history,
        loadPlaces: () async => [],
        nowMs: () => now);
    addTearDown(c.dispose);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await c.initialize();
    expect(camp.state.quests[id]!.status, CompanionQuestStatus.accepted);
    now += 1000;
    final oldVisit = <String, dynamic>{
      'visitId': 'v',
      'sessionId': 's',
      'routeRevision': 'route_1234567890abcdef',
      'evidence': 'destination-arrived',
      'placeId': 'p',
      'placeName': '바다',
      'regionTag': 'coast',
      'arrivedAtMs': now,
      'companionIds': [id]
    };
    history.value = TravelHistorySnapshot.fromJson({
      'visits': {
        for (var i = 0; i < 201; i++)
          'other_$i': {
            'sessionId': 's',
            'routeRevision': 'route_1234567890abcdef',
            'evidence': 'destination-arrived',
            'placeId': 'other',
            'placeName': '다른 곳',
            'regionTag': 'city',
            'arrivedAtMs': now + 1 + i,
            'companionIds': ['another']
          }
      },
      'companions': {
        id: {
          'places': {'p': oldVisit}
        }
      },
      'places': {
        'p': {
          'placeId': 'p',
          'placeName': '바다',
          'regionTag': 'coast',
          'visitCount': 1,
          'lastArrivedAtMs': now
        }
      }
    });
    await c.refresh();
    expect(camp.state.quests[id]!.status, CompanionQuestStatus.completed);
    await c.refresh();
    expect(camp.state.quests[id]!.completedVisitId, 'v');
  });
  test('refresh and closing one friend do not cancel another open', () async {
    SharedPreferences.setMockInitialValues({});
    final dex = DexStore(namespace: 'quest-concurrent.');
    for (final egg in ['a', 'b']) {
      await dex.add(DexEntry(
          speciesId: 'road_sprout',
          sourceEggId: egg,
          obtainedAt: DateTime.utc(2026),
          envTags: const [],
          regionTag: null,
          tier: 1));
    }
    var now = 1700000000000;
    final camp = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'quest-concurrent'),
        dex: dex,
        nowMs: () => now);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.sceneTour),
        dex: dex,
        baseCamp: camp);
    await camp.load();
    final response = Completer<Map<String, dynamic>>();
    final c = CompanionQuestCoordinator(
        game: game,
        camp: camp,
        historyStore: EmptyHistory(),
        loadPlaces: () async => [],
        nowMs: () => now,
        templateRequest: (_) => response.future);
    addTearDown(c.dispose);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    await c.initialize();
    final firstId = c.snapshot.first['questId'];
    now += BaseCamp.questIntervalMs;
    expect(c.snapshot.first['questId'], isNot(firstId));
    final ids = camp.state.creatures.keys.toList();
    final pending = c.open(ids[1]);
    await c.refresh();
    c.later(ids[0]);
    response.complete({
      'schemaVersion': 1,
      'templateId': 'food-1',
      'templateVersion': 1,
      'speciesId': 'road_sprout',
      'kind': 'food',
      'title': '간식',
      'text': '함께 먹자',
      'storyId': null,
      'targetFoodId': 'berry_snack',
      'targetRegion': null
    });
    await pending;
    expect(c.snapshot.singleWhere((q) => q['creatureId'] == ids[1])['opened'],
        true);
  });
  test(
      'older companion coast visit produces grounded copy; recent and unknown do not',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dex = DexStore(namespace: 'quest-copy.');
    await dex.add(DexEntry(
        speciesId: 'road_sprout',
        sourceEggId: 'egg',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1));
    final now = 1700000000000;
    final camp = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'quest-copy'),
        dex: dex,
        nowMs: () => now);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.sceneTour),
        dex: dex,
        baseCamp: camp);
    await camp.load();
    final id = camp.state.creatures.keys.single;
    await camp.offerQuest(CompanionQuest(
        creatureId: id,
        questId: 'q_0',
        kind: CompanionQuestKind.travel,
        templateId: 't',
        templateVersion: 1,
        issuedAtMs: now,
        nextEligibleAtMs: now + BaseCamp.questIntervalMs));
    final history = MutableHistory();
    final c = CompanionQuestCoordinator(
        game: game,
        camp: camp,
        historyStore: history,
        nowMs: () => now,
        loadPlaces: () async => [
              const TravelPlace(
                  placeId: 'other', name: '다른 바다', region: 'coast')
            ],
        templateRequest: (_) async => {
              'schemaVersion': 1,
              'templateId': 't',
              'templateVersion': 1,
              'speciesId': 'road_sprout',
              'kind': 'travel',
              'title': '여행',
              'text': '바다를 함께 보러 갈까?',
              'storyId': null,
              'targetFoodId': null,
              'targetRegion': 'coast'
            });
    addTearDown(c.dispose);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    TravelHistorySnapshot historyAt(int at) => TravelHistorySnapshot.fromJson({
          'visits': {
            for (var i = 0; i < 201; i++)
              'other_$i': {
                'sessionId': 's',
                'routeRevision': 'route_1234567890abcdef',
                'evidence': 'destination-arrived',
                'placeId': 'other',
                'placeName': '다른 곳',
                'regionTag': 'city',
                'arrivedAtMs': at + 1 + i,
                'companionIds': ['another']
              }
          },
          'companions': {
            id: {
              'places': {
                'p': {
                  'visitId': 'v',
                  'sessionId': 's',
                  'routeRevision': 'route_1234567890abcdef',
                  'placeId': 'p',
                  'placeName': '지난 바다',
                  'regionTag': 'coast',
                  'arrivedAtMs': at,
                  'companionIds': [id],
                  'evidence': 'destination-arrived'
                }
              }
            }
          },
          'places': {
            'p': {
              'placeId': 'p',
              'placeName': '지난 바다',
              'regionTag': 'coast',
              'visitCount': 1,
              'lastArrivedAtMs': at
            }
          }
        });
    history.value = historyAt(now - 15 * 24 * 60 * 60 * 1000);
    await c.initialize();
    await c.open(id);
    expect(c.snapshot.single['text'], contains('지난 바다'));
    history.value = historyAt(now - 14 * 24 * 60 * 60 * 1000);
    await c.refresh();
    expect(c.snapshot.single['text'], contains('지난 바다'));
    history.value = historyAt(now - 14 * 24 * 60 * 60 * 1000 + 1);
    await c.refresh();
    expect(c.snapshot.single['text'], isNot(contains('지난 바다')));
    history.value = TravelHistorySnapshot.unknown;
    await c.refresh();
    expect(c.snapshot.single['text'], isNot(contains('지난 바다')));
    expect(c.snapshot.single['candidates'], isEmpty);
  });
}

class MutableHistory extends TravelHistoryStore {
  TravelHistorySnapshot value = TravelHistorySnapshot.unknown;
  @override
  Future<TravelHistorySnapshot> load() async => value;
}

class ControlledHistory extends MutableHistory {
  int reads = 0;
  Completer<TravelHistorySnapshot>? gate;
  @override
  Future<TravelHistorySnapshot> load() {
    reads++;
    return gate?.future ?? Future.value(value);
  }
}

class DelayedStore implements BaseCampStore {
  DelayedStore(this.inner);
  final BaseCampStore inner;
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>?> load() => inner.load();
  @override
  Future<void> save(Map<String, dynamic> value) async {
    if (gate != null) await gate!.future;
    await inner.save(value);
  }
}
