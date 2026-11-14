import 'dart:async';
import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/learning/companion_learning_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'companion_learning_test.dart' show catalog, MemoryLearningStore, reply;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;

class HeldLearningStore extends MemoryLearningStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Map<String, dynamic>?> read(String profile, String id) async {
    entered.complete();
    await release.future;
    return super.read(profile, id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late BaseCampController camp;
  late UnityAppController app;
  late CompanionLearningController learning;
  late List<String> spoken;
  late List<Map<String, dynamic>> requests;
  late String target;
  Completer<Map<String, dynamic>>? answer;
  var sequence = 0;
  Future<bool> action(String name, [Map<String, dynamic> fields = const {}]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'invite${sequence++}',
        'action': name,
        ...fields
      }));
  Map<String, dynamic> identity() =>
      {'creatureId': target, 'speciesId': 'road_sprout'};
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sequence = 0;
    answer = null;
    spoken = [];
    requests = [];
    final dex = DexStore();
    for (var i = 0; i < 2; i++) {
      await dex.add(DexEntry(
          speciesId: 'road_sprout',
          obtainedAt: DateTime.utc(2026, 11, 14, i),
          envTags: const [],
          regionTag: null,
          tier: 1,
          sourceEggId: 'friend-$i'));
    }
    camp = BaseCampController(store: CampMemory(), dex: dex);
    game = GameController(feed: RoundFeed(), dex: dex, baseCamp: camp);
    learning = CompanionLearningController(
        catalog: catalog(),
        store: MemoryLearningStore(),
        request: (body) {
          if (body['action'] == 'chat') requests.add(body);
          return body['action'] == 'chat' && answer != null
              ? answer!.future
              : Future.value(reply(body));
        },
        speak: (text) async {
          spoken.add(text);
        },
        stop: () async {});
    app = UnityAppController(game: game, camp: camp, learning: learning);
    expect(await app.initialize(), true);
    await game.pair(sessionA, pairCode: '123456');
    target = camp.state.creatures.values
        .firstWhere((c) => c.speciesId == 'road_sprout')
        .id;
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });

  test('Friends summons exact owned creature silently into cabin', () async {
    await action('navigate', {'view': 'dex'});
    expect(await action('selectCarCompanion', {'creatureId': target}), true);
    expect(app.view, 'cabin');
    expect(learning.creatureId, target);
    expect(spoken, isEmpty);
    expect(learning.snapshot['text'], '');
    expect(learning.snapshot['conversationMode'], 'closed');
    expect(
        await action(
            'selectCompanion', {'creatureId': camp.state.creatures.keys.last}),
        false);
    expect(await action('startEgg', {'tier': 'large'}), false);
  });
  test(
      'exact hit opens two-choice invitation and gates old story and chat actions',
      () async {
    await action('selectCarCompanion', {'creatureId': target});
    expect(await action('storyRepeat', {'creatureId': target}), false);
    expect(await action('companionChat', {...identity(), 'text': '안녕'}), false);
    expect(
        await action('companionTapped', {...identity(), 'speciesId': 'wrong'}),
        false);
    expect(
        await action('companionTapped',
            {...identity(), 'creatureId': camp.state.creatures.keys.last}),
        false);
    expect(await action('companionTapped', identity()), true,
        reason: learning.snapshot.toString());
    expect(learning.snapshot['invitationOpen'], true);
    expect(learning.snapshot['conversationMode'], 'menu');
    expect(learning.snapshot['invitationText'], '나한테 궁금한 게 있는 거야?');
    expect(spoken, ['나한테 궁금한 게 있는 거야?']);
    expect(await action('listenStory', identity()), true);
    expect(learning.snapshot['conversationMode'], 'story');
    expect(learning.snapshot['text'], '작은 씨앗을 찾았어.');
    expect(await action('storyNext', {'creatureId': target}), true);
    expect(learning.snapshot['sceneId'], 'water');
    expect(await action('companionTapped', identity()), true);
    expect(await action('talkToCompanion', identity()), true);
    expect(learning.snapshot['conversationMode'], 'chat');
    expect(
        await action('companionChat', {...identity(), 'text': '물은 왜?'}), true);
    expect(requests, hasLength(1));
  });
  test(
      'close, notebook and target change cancel late answers and close invitations',
      () async {
    for (final change in ['close', 'notebook', 'target']) {
      await action('selectCarCompanion', {'creatureId': target});
      await action('companionTapped', identity());
      await action('talkToCompanion', identity());
      answer = Completer<Map<String, dynamic>>();
      final pending = action('companionChat', {...identity(), 'text': '늦은 질문'});
      await Future<void>.delayed(Duration.zero);
      final sent = requests.last;
      if (change == 'close') {
        await action('closeCompanionInvitation', identity());
      }
      if (change == 'notebook') {
        await action('learningUiBlocked', {'blocked': true});
      }
      if (change == 'target') {
        await action('selectCarCompanion',
            {'creatureId': camp.state.creatures.keys.last});
      }
      final count = spoken.length;
      answer!.complete(reply(sent));
      expect(await pending, false);
      expect(spoken.length, count);
      expect(learning.snapshot['conversationMode'], 'closed');
      expect(learning.snapshot['text'], '');
      await action('learningUiBlocked', {'blocked': false});
    }
  });
  test(
      'owned friend with no story receives an honest preparation message on tap',
      () async {
    await game.dex.add(DexEntry(
        speciesId: 'breeze_wyrm',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'unknown-story'));
    await action('refresh');
    final friend = camp.state.creatures.values
        .firstWhere((c) => c.speciesId == 'breeze_wyrm');
    expect(await action('selectCarCompanion', {'creatureId': friend.id}), true);
    expect(spoken, isEmpty);
    final hit = {'creatureId': friend.id, 'speciesId': friend.speciesId};
    expect(await action('companionTapped', hit), true);
    expect(learning.snapshot['conversationMode'], 'menu');
    expect(learning.snapshot['available'], false);
    expect(learning.snapshot['error'], contains('준비 중'));
    expect(await action('listenStory', hit), false);
    expect(await action('talkToCompanion', hit), false);
    expect(requests, isEmpty);
  });

  for (final change in ['navigate', 'disconnect']) {
    test('summon cannot revive a target after $change during progress load',
        () async {
      final held = HeldLearningStore();
      app.dispose();
      learning = CompanionLearningController(
          catalog: catalog(),
          store: held,
          request: null,
          speak: (text) async {
            spoken.add(text);
          },
          stop: () async {});
      app = UnityAppController(game: game, camp: camp, learning: learning);
      await app.initialize();
      await action('navigate', {'view': 'dex'});
      final pending = action('selectCarCompanion', {'creatureId': target});
      await held.entered.future;
      if (change == 'navigate') await action('navigate', {'view': 'settings'});
      if (change == 'disconnect') expect(await game.disconnect(), true);
      held.release.complete();
      expect(await pending, false);
      expect(app.view, change == 'navigate' ? 'settings' : 'dex');
      expect(learning.creatureId, '');
      expect(spoken, isEmpty);
    });
  }

  testWidgets('silent selection never schedules a three minute invitation',
      (tester) async {
    await tester
        .runAsync(() => action('selectCarCompanion', {'creatureId': target}));
    await tester.pump(const Duration(minutes: 4));
    expect(spoken, isEmpty);
    expect(learning.snapshot['conversationMode'], 'closed');
  });
}
