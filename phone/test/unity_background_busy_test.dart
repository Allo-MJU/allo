import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GatedCampStore extends BaseCampStore {
  Map<String, dynamic>? saved;
  Completer<void>? saveGate;
  Completer<void>? saveStarted;

  void holdSave() {
    saveGate = Completer<void>();
    saveStarted = Completer<void>();
  }

  void releaseSave() {
    final gate = saveGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<Map<String, dynamic>?> load() async => saved;

  @override
  Future<void> save(Map<String, dynamic> value) async {
    final started = saveStarted;
    if (started != null && !started.isCompleted) started.complete();
    await saveGate?.future;
    saved = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GatedCampStore store;
  late BaseCampController camp;
  late GameController game;
  late UnityAppController app;
  late List<Map<String, dynamic>> emitted;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = GatedCampStore();
    camp = BaseCampController(store: store, nowMs: () => 1000);
    game = GameController(
      feed: FakeVehicleFeed(scenario: FakeScenario.clear),
      dex: DexStore(),
      baseCamp: camp,
    );
    app = UnityAppController(game: game, camp: camp);
    expect(await app.initialize(), isTrue);
    emitted = [];
    app.attach((message) {
      final value = jsonDecode(message) as Map<String, dynamic>;
      if (value['type'] == 'app') emitted.add(value);
    });
    expect(await app.handleMessage('{"v":1,"type":"ready"}'), isTrue);
    expect(app.snapshot['busy'], isFalse);
    emitted.clear();
  });

  tearDown(() {
    store.releaseSave();
    app.dispose();
    game.dispose();
    camp.dispose();
  });

  for (final background in ['vehicle sample', 'camp tick']) {
    test('$background save does not make Unity globally busy', () async {
      store.holdSave();
      final saving = background == 'vehicle sample'
          ? camp.recordVehicle(
              sessionId: 'background-trip',
              vehicle: VehicleState(
                ts: 1,
                gear: 'D',
                speedKph: 60,
                distanceM: 1000,
                harshBrake: 0,
                harshSteer: 0,
                wiperLevel: 0,
                headlightOn: false,
                seatRow2: true,
                etaSec: null,
                envTags: const [],
                capabilities: const [],
              ),
            )
          : camp.tick();
      await store.saveStarted!.future;
      try {
        expect(camp.busy, isTrue);
        expect(game.busy, isFalse);
        expect(emitted, isNotEmpty);
        expect(
            emitted.map((snapshot) => snapshot['busy']), everyElement(false));
        expect(app.snapshot['busy'], isFalse);
      } finally {
        store.releaseSave();
        expect(await saving, isTrue);
      }
      expect(camp.busy, isFalse);
      expect(app.snapshot['busy'], isFalse);
      expect(emitted.map((snapshot) => snapshot['busy']), everyElement(false));
    });
  }

  test('dispatched refresh stays globally busy until its camp save finishes',
      () async {
    store.holdSave();
    final refreshing = app.handleMessage(jsonEncode({
      'v': 1,
      'type': 'appAction',
      'requestId': 'refresh-1',
      'action': 'refresh',
    }));
    await store.saveStarted!.future;
    try {
      expect(camp.busy, isTrue);
      expect(game.busy, isFalse);
      expect(app.snapshot['busy'], isTrue);
      expect(emitted, isNotEmpty);
      expect(emitted.map((snapshot) => snapshot['busy']), everyElement(true));
    } finally {
      store.releaseSave();
      expect(await refreshing, isTrue);
    }
    expect(camp.busy, isFalse);
    expect(app.snapshot['busy'], isFalse);
    expect(emitted.last['busy'], isFalse);
  });
}
