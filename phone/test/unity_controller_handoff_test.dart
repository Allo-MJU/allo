import 'dart:convert';

import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unity_app_controller_test.dart' show CampMemory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller handoff preserves Unity revisions and detaches old sender',
      () async {
    SharedPreferences.setMockInitialValues({});
    Future<UnityAppController> create() async {
      final dex = DexStore();
      final camp = BaseCampController(store: CampMemory(), dex: dex);
      final game = GameController(
          feed: FakeVehicleFeed(scenario: FakeScenario.clear),
          dex: dex,
          baseCamp: camp);
      final app = UnityAppController(game: game, camp: camp);
      addTearDown(() {
        app.dispose();
        game.dispose();
        camp.dispose();
      });
      expect(await app.initialize(), true);
      return app;
    }

    final previous = await create();
    final oldMessages = <Map<String, dynamic>>[];
    previous.attach((s) => oldMessages.add(jsonDecode(s)));
    await previous.handleMessage('{"type":"ready"}');
    for (var i = 0; i < 5; i++) {
      previous.game.notifyListeners();
    }
    final oldRevision =
        oldMessages.lastWhere((m) => m['type'] == 'app')['revision'] as int;
    final next = await create();
    final newMessages = <Map<String, dynamic>>[];
    void send(String s) => newMessages.add(jsonDecode(s));
    expect(() => Function.apply(next.attach, [send], {#replacing: previous}),
        returnsNormally);
    await next.handleMessage('{"type":"ready"}');
    expect(newMessages.lastWhere((m) => m['type'] == 'app')['revision'],
        greaterThan(oldRevision));
    final oldCount = oldMessages.length;
    previous.game.notifyListeners();
    expect(oldMessages, hasLength(oldCount));
  });
}
