import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/quests/companion_quest_coordinator.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'unity_app_controller_test.dart' show CampMemory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'host exposes badge without fetching, explicit open and actual feed complete',
      () async {
    final dex = DexStore();
    await dex.add(DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'quest-egg'));
    final camp = BaseCampController(store: CampMemory(), dex: dex);
    final game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: dex,
        baseCamp: camp);
    var calls = 0;
    final quests = CompanionQuestCoordinator(
        game: game,
        camp: camp,
        templateRequest: (body) async {
          calls++;
          return {
            'schemaVersion': 1,
            'templateId': 'food-berry-0',
            'templateVersion': 1,
            'speciesId': body['speciesId'],
            'kind': 'food',
            'title': '간식 부탁',
            'text': '베리 간식 하나 나눠 줄래?',
            'storyId': null,
            'targetFoodId': 'berry_snack',
            'targetRegion': null
          };
        });
    final app = UnityAppController(game: game, camp: camp, quests: quests);
    addTearDown(app.dispose);
    addTearDown(game.dispose);
    addTearDown(camp.dispose);
    expect(await app.initialize(), true);
    expect(calls, 0);
    final id = camp.state.creatures.keys.single;
    Map<String, dynamic> state() =>
        (app.snapshot['quests'] as List).cast<Map<String, dynamic>>().single;
    final qid = state()['questId'];
    expect(state()['available'], true);
    expect(state()['opened'], false);
    var n = 0;
    Future<bool> action(String name) => app.handleMessage(jsonEncode({
          'v': 1,
          'type': 'appAction',
          'requestId': 'quest-action-${n++}',
          'action': name,
          'creatureId': id,
          'questId': qid,
          'placeId': ''
        }));
    expect(await action('openQuest'), true);
    expect(calls, 1);
    expect(state()['opened'], true);
    expect(await action('acceptQuest'), true);
    expect(camp.state.quests[id]!.status, CompanionQuestStatus.accepted);
    await camp.grantCollectionReward('test-food-source');
    expect(
        await app.handleMessage(jsonEncode({
          'v': 1,
          'type': 'appAction',
          'requestId': 'feed-once',
          'action': 'feedFood',
          'creatureId': id,
          'recipeId': 'berry_snack'
        })),
        true);
    expect(camp.state.quests[id]!.status, CompanionQuestStatus.completed);
    expect(camp.state.foodInventory['berry_snack'], 2);
  });
}
