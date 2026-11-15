import 'dart:async';
import 'dart:convert';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:flutter/widgets.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_resume_test.dart' show sessionA;
import 'unity_app_controller_test.dart' show CampMemory;

class DeferredPairGame extends GameController {
  DeferredPairGame(
      {required super.feed, required super.dex, required super.baseCamp});
  final entered = Completer<void>();
  final gate = Completer<void>();
  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    entered.complete();
    await gate.future;
    await super.pair(sessionId, pairCode: pairCode);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late BaseCampController camp;
  late UnityAppController app;
  late List<Map<String, dynamic>> messages;
  var request = 0;
  Future<bool> action(String name, [Map<String, dynamic> fields = const {}]) =>
      app.handleMessage(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'cabin-${request++}',
        'action': name,
        ...fields
      }));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    request = 0;
    messages = [];
    final dex = DexStore();
    camp = BaseCampController(store: CampMemory(), dex: dex);
    game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: dex,
        baseCamp: camp);
    app = UnityAppController(game: game, camp: camp);
    expect(await app.initialize(), true);
    app.attach((m) => messages.add(jsonDecode(m) as Map<String, dynamic>));
    await app.handleMessage('{"type":"ready"}');
  });
  tearDown(() {
    app.dispose();
    game.dispose();
    camp.dispose();
  });
  test('fresh fake cabin has no connection egg companion or automatic story',
      () async {
    await action('navigate', {'view': 'cabin'});
    expect(game.paired, false);
    expect(game.eggId, isNull);
    expect((app.snapshot['egg'] as Map)['active'], false);
    expect((app.snapshot['story'] as Map)['notebookOpen'], false);
    expect((app.snapshot['story'] as Map)['active'], false);
    expect((app.snapshot['story'] as Map)['canOpen'], false);
    final cast = messages.lastWhere((m) => m['type'] == 'cast');
    expect(cast['companion'], isNull);
    expect(cast['friends'], isEmpty);
  });
  test('pairing route accepts manual pair then returns cabin with one egg',
      () async {
    expect(await action('navigate', {'view': 'pairing'}), true);
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    expect(app.view, 'cabin');
    expect(game.paired, true);
    expect(game.eggId, isNotNull);
    final egg = game.eggId;
    await action('navigate', {'view': 'pairing'});
    expect(await action('pair', {'sessionId': sessionA, 'pairCode': '123456'}),
        true);
    expect(game.eggId, egg);
  });
  test('legacy scripted and experiment routes cannot capture cabin ownership',
      () async {
    await action('navigate', {'view': 'cabin'});
    for (final name in [
      'storyStart',
      'storyResume',
      'storyReplay',
      'listenStory',
      'talkToCompanion',
      'storyNext',
      'storyRepeat'
    ]) {
      expect(
          await action(name, {
            'creatureId': 'old',
            'speciesId': 'road_sprout',
            'topicId': 'coast_sail'
          }),
          false);
    }
    expect(await action('storyUiBlocked', {'blocked': true}), true);
    expect((app.snapshot['story'] as Map)['notebookOpen'], false);
    expect((app.snapshot['story'] as Map)['active'], false);
  });
  test('QR cancel and scanner failure never pair or grant an egg', () async {
    await action('navigate', {'view': 'pairing'});
    app.pairingScanner = () async => null;
    expect(await action('scanPairingQr'), false);
    expect(app.view, 'pairing');
    expect(game.eggId, isNull);
    app.pairingScanner = () async => throw StateError('camera unavailable');
    expect(await action('scanPairingQr'), false);
    expect(game.paired, false);
    expect(game.eggId, isNull);
    expect(app.snapshot['error'], isNotEmpty);
  });
  test(
      'QR succeeds across native hide and return and duplicate scan is blocked',
      () async {
    final gate = Completer<PairingCredentials?>();
    var scans = 0;
    app.pairingScanner = () {
      scans++;
      return gate.future;
    };
    await action('navigate', {'view': 'pairing'});
    final pending = action('scanPairingQr');
    expect(await action('scanPairingQr'), false);
    expect(scans, 1);
    await app.setHostLifecycle(AppLifecycleState.paused);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":false}');
    await app.setHostLifecycle(AppLifecycleState.resumed);
    await app.handleMessage('{"v":1,"type":"appLifecycle","active":true}');
    gate.complete(PairingCredentials.parseFields(sessionA, '123456'));
    expect(await pending, true);
    expect(game.paired, true);
    expect(game.eggId, isNotNull);
    expect(app.view, 'cabin');
  });
  test('leaving pairing invalidates a late QR without changing the trip',
      () async {
    final gate = Completer<PairingCredentials?>();
    app.pairingScanner = () => gate.future;
    await action('navigate', {'view': 'pairing'});
    final pending = action('scanPairingQr');
    await action('navigate', {'view': 'cabin'});
    await action('navigate', {'view': 'pairing'});
    gate.complete(PairingCredentials.parseFields(sessionA, '123456'));
    expect(await pending, false);
    expect(game.paired, false);
    expect(game.eggId, isNull);
  });
  test('detaching and reattaching the host discards its old QR result',
      () async {
    final gate = Completer<PairingCredentials?>();
    app.pairingScanner = () => gate.future;
    await action('navigate', {'view': 'pairing'});
    final pending = action('scanPairingQr');
    await app.setHostLifecycle(AppLifecycleState.detached);
    await app.setHostLifecycle(AppLifecycleState.resumed);
    gate.complete(PairingCredentials.parseFields(sessionA, '123456'));
    expect(await pending, false);
    expect(game.paired, false);
    expect(game.eggId, isNull);
  });
  test('late manual pair cannot redirect after leaving and reopening pairing',
      () async {
    app.dispose();
    game.dispose();
    final delayed = DeferredPairGame(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear),
        dex: DexStore(),
        baseCamp: camp);
    game = delayed;
    app = UnityAppController(game: game, camp: camp);
    expect(await app.initialize(), true);
    await action('navigate', {'view': 'pairing'});
    final pending =
        action('pair', {'sessionId': sessionA, 'pairCode': '123456'});
    await delayed.entered.future;
    await action('navigate', {'view': 'home'});
    await action('navigate', {'view': 'pairing'});
    delayed.gate.complete();
    expect(await pending, true);
    expect(game.paired, true);
    expect(app.view, 'pairing');
  });
  test('settings QR button scans and cancel preserves settings without a grant',
      () async {
    var scans = 0;
    app.pairingScanner = () async {
      scans++;
      return null;
    };
    await action('navigate', {'view': 'settings'});
    expect(app.snapshot['pairingScanAvailable'], true);
    expect(await action('scanPairingQr'), false);
    expect(scans, 1);
    expect(app.view, 'settings');
    expect(game.eggId, isNull);
    app.pairingScanner =
        () async => PairingCredentials.parseFields(sessionA, '123456');
    expect(await action('scanPairingQr'), true);
    expect(game.paired, true);
    expect(game.eggId, isNotNull);
    expect(app.view, 'cabin');
  });
  test('settings QR result is invalid after navigating to the pairing screen',
      () async {
    final gate = Completer<PairingCredentials?>();
    var scans = 0;
    app.pairingScanner = () {
      scans++;
      return gate.future;
    };
    await action('navigate', {'view': 'settings'});
    final pending = action('scanPairingQr');
    expect(scans, 1);
    await action('navigate', {'view': 'pairing'});
    gate.complete(PairingCredentials.parseFields(sessionA, '123456'));
    expect(await pending, false);
    expect(game.paired, false);
    expect(game.eggId, isNull);
    expect(app.view, 'pairing');
  });
  test('QR requires a pairing entry screen and an available scanner', () async {
    expect(app.snapshot['pairingScanAvailable'], false);
    expect(await action('scanPairingQr'), false);
    await action('navigate', {'view': 'pairing'});
    expect(await action('scanPairingQr'), false);
  });
}
