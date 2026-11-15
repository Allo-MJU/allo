import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/explore/explore_messages.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unity_app_controller_test.dart' show CampMemory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cue = Cornering(bend: -0.5, receivedAtMs: 1200);

  test('route bridge retains navigation and the signed steering receipt', () {
    final message =
        jsonDecode(routeMessage(const [], headingDeg: 15, cornering: cue))
            as Map<String, dynamic>;
    expect(message['cornering'], cue.toJson());
    expect(message['heading'], 15);
  });

  test('missing or malformed constructed cues clear the Unity steering input',
      () {
    for (final value in [
      null,
      const Cornering(bend: double.nan, receivedAtMs: 1200),
      const Cornering(bend: 2, receivedAtMs: 1200),
      const Cornering(bend: 0.5, receivedAtMs: -1),
    ]) {
      final message = jsonDecode(routeMessage(const [], cornering: value));
      expect(message['cornering'], isNull);
    }
  });

  test('full Unity host publishes and clears the current vehicle cue',
      () async {
    SharedPreferences.setMockInitialValues({});
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
    expect(await app.initialize(), isTrue);
    game.vehicle = VehicleState.fromJson({
      'cornering': cue.toJson(),
      'headingDeg': 15,
      'turns': [const Turn('right', 200).toJson()],
    });
    final messages = <Map<String, dynamic>>[];
    app.attach((message) => messages.add(jsonDecode(message)));
    await app.handleMessage('{"type":"ready"}');
    final route = messages.lastWhere((message) => message['type'] == 'route');
    expect(route['cornering'], cue.toJson());
    expect(route['turns'], [const Turn('right', 200).toJson()]);
    game.vehicle = game.vehicle!.copyWith(clearCornering: true);
    await app.handleMessage('{"type":"ready"}');
    expect(
        messages
            .lastWhere((message) => message['type'] == 'route')['cornering'],
        isNull);
  });
}
