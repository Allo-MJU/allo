import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/app.dart';
import 'package:allo_phone/explore/explore_screen.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:allo_phone/unity_app/unity_app_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'app_dev_integration_test.dart' show CountingApi;
import 'local_firebase_stores_test.dart' show FailingPreferences;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

class _Vehicle extends RoundFeed {
  int pairs = 0;

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    pairs++;
  }
}

class _RestoreGate extends PairingStore {
  final result = Completer<PairingCredentials?>();

  @override
  Future<PairingCredentials?> read() => result.future;
}

class _CheckpointGame extends GameController {
  _CheckpointGame(_Vehicle feed) : super(feed: feed, dex: DexStore());
  bool? failNext;
  bool active = true;

  @override
  Future<bool> setAppActive(bool value) async {
    active = value;
    final saved = await super.setAppActive(value);
    if (value == failNext) {
      failNext = null;
      return false;
    }
    return saved;
  }
}

class _Surface {
  final messages = <Map<String, dynamic>>[];
  late void Function(String) receive;
  bool attached = false;
  int request = 0;

  UnityViewBuilder get build => ({required onCreated, required onMessage}) {
        receive = onMessage;
        if (!attached) {
          attached = true;
          onCreated((json) => messages.add(jsonDecode(json)));
        }
        return const SizedBox();
      };

  Map<String, dynamic> get app =>
      messages.lastWhere((m) => m['type'] == 'app', orElse: () => {});

  void action(String name, {String? view}) => receive(jsonEncode({
        'v': 1,
        'type': 'appAction',
        'requestId': 'test-${++request}',
        'action': name,
        if (view != null) 'view': view,
      }));

  Future<void> until(WidgetTester tester, bool Function() reached) async {
    for (var i = 0; i < 200 && !reached(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(reached(), true,
        reason: 'view=${app['view']} demo=${app['isDemo']} '
            'ready=${app['ready']} connected=${app['connected']} '
            'error=${app['error']}');
  }
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('one live Unity surface enters an isolated test trip and returns',
      (tester) async {
    final feed = _Vehicle();
    final api = CountingApi();
    final game = GameController(feed: feed, dex: DexStore(), eggApi: api);
    final surface = _Surface();
    var created = 0;
    await tester.pumpWidget(AlloApp(
      feed: feed,
      useUnityApp: true,
      eggApi: api,
      createController: () {
        created++;
        return game;
      },
      unityView: surface.build,
    ));
    surface.receive('{"type":"ready"}');
    await surface.until(tester, () => surface.app['ready'] == true);
    surface.action('navigate', view: 'pairing');
    await tester.pump();
    expect(surface.app['isDemo'], false);
    expect(surface.app['testConnectionAvailable'], true);
    final firstRevision = surface.app['revision'] as int;
    surface.action('testPair');
    // A manual pair from the outgoing UI can already be queued behind testPair.
    surface.receive(jsonEncode({
      'v': 1,
      'type': 'appAction',
      'requestId': 'outgoing-pair',
      'action': 'pair',
      'sessionId': sessionA,
      'pairCode': '123456',
    }));
    await surface.until(tester, () => surface.app['isDemo'] == true);
    expect(surface.app['view'], 'cabin');
    expect(surface.app['connected'], true);
    expect(surface.app['canReturnToVehicle'], true);
    expect(surface.app['revision'] as int, greaterThan(firstRevision));
    final egg = (surface.app['egg'] as Map)['id'];
    expect(egg, isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
        surface.messages
            .where((m) => m['type'] == 'route' && m['cornering'] != null),
        isNotEmpty);
    expect(game.paired, false);
    expect(feed.pairs, 0);
    expect(feed.watches, 0);
    expect(feed.published, isEmpty);
    final testGraph =
        tester.widget<UnityAppScreen>(find.byType(UnityAppScreen)).controller;
    final lastSample = testGraph.game.vehicle!;
    expect(lastSample.distanceM, greaterThan(0));
    surface.action('navigate', view: 'settings');
    await tester.pump();
    final testRevision = surface.app['revision'] as int;
    surface.action('returnToVehicle');
    await surface.until(tester, () => surface.app['isDemo'] == false);
    expect(surface.app['revision'] as int, greaterThan(testRevision));
    expect(surface.app['view'], 'pairing');
    expect(surface.app['connected'], false);
    final hiddenMaterials = Map.of(testGraph.camp.state.materials);
    await tester.pump(const Duration(seconds: 15));
    expect(testGraph.game.vehicle!.ts, lastSample.ts);
    expect(testGraph.camp.state.materials, hiddenMaterials);
    expect(api.closeCount, 0);
    expect(
        (await DexStore(profile: 'test-connection').tripEggLedger(true)).claims,
        isNotEmpty);
    expect((await game.dex.tripEggLedger(true)).claims, isEmpty);
    expect((await game.dex.tripEggLedger(false)).claims, isEmpty);
    surface.action('testPair');
    await surface.until(tester, () => surface.app['isDemo'] == true);
    expect((surface.app['egg'] as Map)['id'], egg);
    final restored =
        tester.widget<UnityAppScreen>(find.byType(UnityAppScreen)).controller;
    expect(restored.game.vehicle?.distanceM, lastSample.distanceM);
    await tester.pump(const Duration(seconds: 1));
    expect(restored.game.vehicle!.distanceM, greaterThan(lastSample.distanceM));
    expect(restored.game.vehicle!.ts, greaterThan(lastSample.ts));
    final beforeDisconnect = restored.game.vehicle!;
    final testDex = DexStore(profile: 'test-connection');
    final currentId = (await testDex.tripEggLedger(true)).demoSessionId;
    surface.action('navigate', view: 'settings');
    surface.action('disconnect');
    await surface.until(tester, () => surface.app['connected'] == false);
    expect((await testDex.tripEggLedger(true)).demoSessionId, currentId);
    surface.action('testPair');
    await surface.until(
        tester,
        () =>
            surface.app['connected'] == true && surface.app['view'] == 'cabin');
    expect((await testDex.tripEggLedger(true)).demoSessionId, currentId);
    await tester.pump(const Duration(seconds: 1));
    final afterReconnect = restored.game.vehicle!;
    expect(afterReconnect.distanceM, greaterThan(beforeDisconnect.distanceM),
        reason:
            'Same test SID, timestamp delta ${afterReconnect.ts - beforeDisconnect.ts}ms');
    expect(afterReconnect.ts, greaterThan(beforeDisconnect.ts));
    expect(created, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(api.closeCount, 1);
  });

  testWidgets(
      'both modes use the latest shared gyro and reduced-motion settings',
      (tester) async {
    final surface = _Surface();
    await tester.pumpWidget(
        AlloApp(feed: _Vehicle(), useUnityApp: true, unityView: surface.build));
    surface.receive('{"type":"ready"}');
    await surface.until(tester, () => surface.app['ready'] == true);
    surface.action('navigate', view: 'pairing');
    surface.action('testPair');
    await surface.until(tester, () => surface.app['isDemo'] == true);
    surface.action('navigate', view: 'settings');
    surface.receive(
        '{"type":"appAction","v":1,"requestId":"test-prefs","action":"settings","gyro":false,"reducedMotion":true}');
    await surface.until(tester, () => surface.app['gyro'] == false);
    surface.action('returnToVehicle');
    await surface.until(tester, () => surface.app['isDemo'] == false);
    expect(surface.app['gyro'], false);
    expect(surface.app['reducedMotion'], true);
    surface.receive(
        '{"type":"appAction","v":1,"requestId":"vehicle-prefs","action":"settings","gyro":true,"reducedMotion":false}');
    await surface.until(tester, () => surface.app['gyro'] == true);
    surface.action('testPair');
    await surface.until(tester, () => surface.app['isDemo'] == true);
    expect(surface.app['gyro'], true);
    expect(surface.app['reducedMotion'], false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'a failed fishing selection must be retried before either transfer',
      (tester) async {
    final platform = FailingPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final surface = _Surface();
    await tester.pumpWidget(
        AlloApp(feed: _Vehicle(), useUnityApp: true, unityView: surface.build));
    surface.receive('{"type":"ready"}');
    await surface.until(tester, () => surface.app['ready'] == true);
    surface.action('navigate', view: 'pairing');
    for (final action in ['testPair', 'returnToVehicle']) {
      final current =
          tester.widget<UnityAppScreen>(find.byType(UnityAppScreen)).controller;
      if (!current.game.isFake) await current.game.fishing.attach(sessionA);
      platform.failSuffix = FishingStore.key;
      await current.game.fishing.select(DexEntry(
          speciesId: 'road_sprout',
          obtainedAt: DateTime.utc(2026),
          envTags: const [],
          regionTag: null,
          tier: 1));
      expect(current.game.fishing.hasPendingWrite, true);
      surface.action('navigate', view: 'pairing');
      bool? result;
      unawaited(current
          .handleMessage(jsonEncode({
            'v': 1,
            'type': 'appAction',
            'action': action,
            'requestId': 'blocked-$action'
          }))
          .then((r) => result = r));
      await surface.until(tester, () => result != null);
      expect(result, false);
      expect(surface.app['isDemo'], current.game.isFake);
      platform.failSuffix = null;
      await current.game.fishing.retrySave();
      expect(current.game.fishing.hasPendingWrite, false);
      surface.action(action);
      await surface.until(
          tester, () => surface.app['isDemo'] != current.game.isFake);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'restarting the host resumes the same test trip and its road rewards',
      (tester) async {
    Future<_Surface> openTestDrive() async {
      final surface = _Surface();
      await tester.pumpWidget(AlloApp(
          feed: _Vehicle(), useUnityApp: true, unityView: surface.build));
      surface.receive('{"type":"ready"}');
      await surface.until(tester, () => surface.app['ready'] == true);
      surface.action('navigate', view: 'pairing');
      surface.action('testPair');
      await surface.until(tester, () => surface.app['isDemo'] == true);
      return surface;
    }

    final first = await openTestDrive();
    final before =
        tester.widget<UnityAppScreen>(find.byType(UnityAppScreen)).controller;
    for (var tick = 0; tick < 8; tick++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final last = before.game.vehicle!;
    final wood = before.camp.state.materials[CampMaterial.wood]!;
    final trip = await DexStore(profile: 'test-connection').tripEggLedger(true);
    expect(wood, greaterThan(0));
    first.action('navigate', view: 'settings');
    first.action('returnToVehicle');
    await first.until(tester, () => first.app['isDemo'] == false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final second = await openTestDrive();
    final after =
        tester.widget<UnityAppScreen>(find.byType(UnityAppScreen)).controller;
    final restored =
        await DexStore(profile: 'test-connection').tripEggLedger(true);
    expect(restored.demoSessionId, trip.demoSessionId);
    expect(restored.eggId, trip.eggId);
    await tester.pump(const Duration(seconds: 1));
    final firstSample = after.game.vehicle!;
    expect(after.camp.state.materials[CampMaterial.wood], wood);
    // The prior 3 km already belongs to the saved egg. Counting it again
    // on its first resumed tick would cross the small egg's 5 km target.
    expect(after.game.game.stage, Stage.incubating);
    for (var tick = 0; tick < 4; tick++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final newWood = after.camp.state.materials[CampMaterial.wood]!;
    expect([
      firstSample.distanceM > last.distanceM,
      firstSample.ts > last.ts,
      newWood > wood
    ], everyElement(true),
        reason: 'distance ${last.distanceM} → ${firstSample.distanceM}, '
            'timestamp delta ${firstSample.ts - last.ts}ms, wood $wood → $newWood');
    second.action('endTrip');
    await second.until(tester, () => after.game.sessionSaved);
    second.action('navigate', view: 'pairing');
    second.action('testPair');
    await second.until(
        tester, () => second.app['view'] == 'cabin' && after.game.paired);
    final nextTrip =
        await DexStore(profile: 'test-connection').tripEggLedger(true);
    expect(nextTrip.demoSessionId, isNot(restored.demoSessionId));
    await tester.pump(const Duration(seconds: 1));
    expect(after.game.vehicle!.distanceM, closeTo(70 / 3.6 * 20, .01));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a failed checkpoint keeps the current mode active on each side',
      (tester) async {
    final feed = _Vehicle();
    final game = _CheckpointGame(feed);
    final surface = _Surface();
    await tester.pumpWidget(AlloApp(
        feed: feed,
        useUnityApp: true,
        createController: () => game,
        unityView: surface.build));
    surface.receive('{"type":"ready"}');
    await surface.until(tester, () => surface.app['ready'] == true);
    surface.action('navigate', view: 'pairing');
    game.failNext = false;
    surface.action('testPair');
    await surface.until(tester, () => game.failNext == null && game.active);
    expect(surface.app['isDemo'], false);
    expect(
        (await DexStore(profile: 'test-connection').tripEggLedger(true)).claims,
        isEmpty);
    surface.action('testPair');
    await surface.until(tester, () => surface.app['isDemo'] == true);
    expect(game.active, false);
    surface.action('navigate', view: 'settings');
    game.failNext = true;
    surface.action('returnToVehicle');
    await surface.until(tester, () => game.failNext == null && !game.active);
    expect(surface.app['isDemo'], true);
    expect(surface.app['connected'], true);
    surface.action('returnToVehicle');
    await surface.until(tester, () => surface.app['isDemo'] == false);
    expect(game.active, true);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a pending saved vehicle wins over a test connection request',
      (tester) async {
    final feed = _Vehicle();
    final pairing = _RestoreGate();
    final game =
        GameController(feed: feed, dex: DexStore(), pairingStore: pairing);
    final surface = _Surface();
    await tester.pumpWidget(AlloApp(
        feed: feed,
        useUnityApp: true,
        createController: () => game,
        unityView: surface.build));
    surface.receive('{"type":"ready"}');
    await tester.pump();
    surface.action('navigate', view: 'pairing');
    surface.action('testPair');
    await tester.pump();
    pairing.result.complete(PairingCredentials.parseFields(sessionA, '123456'));
    await surface.until(tester, () => surface.app['connected'] == true);
    expect(surface.app['isDemo'], false);
    expect(surface.app['testConnectionAvailable'], false);
    expect(feed.pairs, 1);
    expect(
        (await DexStore(profile: 'test-connection').tripEggLedger(true)).claims,
        isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('closing the host abandons a switch waiting on stored pairing',
      (tester) async {
    final feed = _Vehicle();
    final pairing = _RestoreGate();
    final game =
        GameController(feed: feed, dex: DexStore(), pairingStore: pairing);
    final surface = _Surface();
    await tester.pumpWidget(AlloApp(
        feed: feed,
        useUnityApp: true,
        createController: () => game,
        unityView: surface.build));
    surface.receive('{"type":"ready"}');
    surface.action('navigate', view: 'pairing');
    surface.action('testPair');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pairing.result.complete(null);
    await tester.pump();
    expect(feed.pairs, 0);
    expect(
        (await DexStore(profile: 'test-connection').tripEggLedger(true)).claims,
        isEmpty);
  });
}
