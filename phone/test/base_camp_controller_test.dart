import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final stored = <String, Object>{};
  var failWrite = false;
  var failRead = false;

  setUp(() async {
    stored.clear();
    failWrite = false;
    failRead = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll' || call.method == 'getAllWithParameters') {
        if (failRead) throw PlatformException(code: 'read_failed');
        return Map<String, Object>.of(stored);
      }
      final args = Map<String, Object?>.from(call.arguments as Map);
      if (call.method == 'setString' || call.method == 'setStringList') {
        if (failWrite) return false;
        stored[args['key']! as String] = args['value']!;
        return true;
      }
      throw StateError('Unexpected preferences method: ${call.method}');
    });
    await (await SharedPreferences.getInstance()).reload();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('preferences failed writes reload durable value and isolate demo',
      () async {
    final real = SharedPreferencesBaseCampStore();
    final demo = SharedPreferencesBaseCampStore(profile: 'demo');
    await real.save({'version': 1, 'value': 3});
    await demo.save({'version': 1, 'value': 9});
    failWrite = true;
    await expectLater(
        real.save({'version': 1, 'value': 999}), throwsStateError);
    expect((await real.load())!['value'], 3);
    expect((await demo.load())!['value'], 9);
    expect(() => SharedPreferencesBaseCampStore(profile: '../demo'),
        throwsArgumentError);
  });

  test('preferences malformed JSON and read errors remain errors', () async {
    final store = SharedPreferencesBaseCampStore();
    stored['flutter.baseCamp.v1.default'] = '{broken';
    await expectLater(store.load(), throwsFormatException);
    expect(stored['flutter.baseCamp.v1.default'], '{broken');
    failRead = true;
    await expectLater(store.load(), throwsA(isA<PlatformException>()));
  });

  test('publishes only after durable save and serializes overlapping inputs',
      () async {
    var now = epoch;
    final store = MemoryCampStore();
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => now);
    addTearDown(controller.dispose);
    expect(await controller.load(), isTrue);
    final before = controller.state.toJson();
    store.block = Completer<void>();
    final first = controller.recordLookOut(eventId: 'one');
    final second = controller.recordLookOut(eventId: 'two');
    await flush();
    expect(controller.busy, isTrue);
    expect(controller.state.toJson(), before);
    expect(store.inFlight, 1);
    store.block!.complete();
    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(controller.state.materials[CampMaterial.wood], 1);
    now += 60000;
    expect(await controller.recordLookOut(eventId: 'two'), isTrue);
    expect(controller.state.materials[CampMaterial.wood], 2);
    expect(store.maxInFlight, 1);
  });

  test('save failure preserves public state and retry can catch up', () async {
    var now = epoch;
    final store = MemoryCampStore();
    final controller = BaseCampController(
        store: store, dex: TestDex([entry('road_sprout')]), nowMs: () => now);
    addTearDown(controller.dispose);
    expect(await controller.load(), isTrue);
    final builder = controller.state.creatures.keys.single;
    await controller.assign(CampRole.builder, builder);
    await controller.recordLookOut(eventId: 'a');
    now += 60000;
    await controller.recordLookOut(eventId: 'b');
    await controller.startBuild(CampFacility.workshop);
    final before = controller.state.toJson();
    now += 60000;
    store.failSave = true;
    expect(await controller.tick(), isFalse);
    expect(controller.ready, isTrue);
    expect(controller.error, 'save_failed');
    expect(controller.state.toJson(), before);
    store.failSave = false;
    expect(await controller.tick(), isTrue);
    expect(controller.state.facilities[CampFacility.workshop], 1);
    expect(controller.state.jobs, isEmpty);
    final detached = controller.state;
    detached.advanceTo(now + 1);
    expect(controller.state.nowMs, now);
  });

  test(
      'ownership read failures retain running jobs and never save empty ownership',
      () async {
    var now = epoch;
    final store = MemoryCampStore();
    final dex = TestDex([entry('road_sprout')]);
    final controller =
        BaseCampController(store: store, dex: dex, nowMs: () => now);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.assign(
        CampRole.builder, controller.state.creatures.keys.single);
    await controller.recordLookOut(eventId: 'a');
    now += 60000;
    await controller.recordLookOut(eventId: 'b');
    await controller.startBuild(CampFacility.workshop);
    final saved = jsonEncode(store.value);
    final before = controller.state.toJson();
    dex.fail = true;
    now += 1000;
    expect(await controller.refreshOwnership(), isFalse);
    expect(controller.error, 'ownership_read_failed');
    expect(controller.state.toJson(), before);
    expect(jsonEncode(store.value), saved);
    dex.fail = false;
    dex.entries = [];
    expect(await controller.refreshOwnership(), isTrue);
    expect(controller.state.jobs, isEmpty);
    expect(controller.state.materials[CampMaterial.wood], 2);
  });

  test(
      'legacy duplicate IDs survive order restart and normalized env tag order',
      () async {
    final store = MemoryCampStore();
    final a = entry('road_sprout', tags: ['rain', 'city']);
    final b = entry('puddle_pip');
    final dex = TestDex([a, b, a]);
    final first =
        BaseCampController(store: store, dex: dex, nowMs: () => epoch);
    expect(await first.load(), isTrue);
    final firstIds = first.state.creatures.values
        .where((c) => c.speciesId == 'road_sprout')
        .map((c) => c.id)
        .toSet();
    final cookId = first.state.creatures.values
        .singleWhere((c) => c.speciesId == 'puddle_pip')
        .id;
    first.dispose();
    dex.entries = [
      b,
      entry('road_sprout', tags: ['city', 'rain']),
      a
    ];
    final resumed =
        BaseCampController(store: store, dex: dex, nowMs: () => epoch);
    addTearDown(resumed.dispose);
    expect(await resumed.load(), isTrue);
    expect(resumed.state.creatures.keys.toSet(), {...firstIds, cookId});
    expect(resumed.state.creatures[cookId]!.speciesId, 'puddle_pip');
    dex.entries = [];
    await resumed.refreshOwnership();
    dex.entries = [a];
    await resumed.refreshOwnership();
    expect(firstIds, contains(resumed.state.creatures.keys.single));
    expect(dex.writes, 0);
  });

  test(
      'source IDs survive metadata changes and unknown species cannot be workers',
      () async {
    final store = MemoryCampStore();
    final dex = TestDex([
      SourceEntry('egg-1', 'future_species', ['city'])
    ]);
    final controller =
        BaseCampController(store: store, dex: dex, nowMs: () => epoch);
    addTearDown(controller.dispose);
    await controller.load();
    final id = controller.state.creatures.keys.single;
    dex.entries = [
      SourceEntry('egg-1', 'future_species', ['rain'])
    ];
    await controller.refreshOwnership();
    expect(controller.state.creatures.keys.single, id);
    expect(await controller.assign(CampRole.builder, id), isFalse);
    expect(controller.canUseAction(id, 'greeting'), isFalse);
    expect(controller.performAction(id, 'greeting'), isNull);
    expect(dex.writes, 0);
  });

  test(
      'first fresh drive on load and reattach is baseline, stale does not consume it',
      () async {
    var now = epoch;
    final store = MemoryCampStore();
    var controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => now);
    await controller.load();
    expect(
        await controller.recordVehicle(
            sessionId: 's', vehicle: vehicle(1, 1000)),
        isTrue);
    expect(controller.state.materials[CampMaterial.wood], 0);
    expect(
        await controller.recordVehicle(
            sessionId: 's', vehicle: vehicle(2, 2000)),
        isTrue);
    expect(controller.state.materials[CampMaterial.wood], 1);
    controller.dispose();
    now += 600000;
    controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => now);
    addTearDown(() => controller.dispose());
    await controller.load();
    expect(
        await controller.recordVehicle(
            sessionId: 's', vehicle: vehicle(2, 2000)),
        isFalse);
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(3, 12000));
    expect(controller.state.materials[CampMaterial.wood], 1);
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(4, 13000));
    expect(controller.state.materials[CampMaterial.wood], 2);
    controller.beginDrivingSession('s');
    expect(
        await controller.recordVehicle(
            sessionId: 's', vehicle: vehicle(4, 13000)),
        isFalse);
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(5, 23000));
    expect(controller.state.materials[CampMaterial.wood], 2);
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(6, 24000));
    expect(controller.state.materials[CampMaterial.wood], 3);
  });

  test('failed load preserves malformed data and cannot mutate until ready',
      () async {
    final store = MemoryCampStore()..value = {'version': 999};
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    addTearDown(controller.dispose);
    expect(await controller.load(), isFalse);
    expect(controller.ready, isFalse);
    expect(await controller.recordLookOut(eventId: 'x'), isFalse);
    expect(store.value, {'version': 999});
    expect(store.saves, 0);
  });

  test('dispose while saving commits durable value without publishing',
      () async {
    final store = MemoryCampStore();
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    await controller.load();
    var notices = 0;
    controller.addListener(() => notices++);
    store.block = Completer<void>();
    final pending = controller.recordLookOut(eventId: 'one');
    await flush();
    final previous = controller.state.toJson();
    controller.dispose();
    final noticesAtDispose = notices;
    store.block!.complete();
    await pending;
    expect(notices, noticesAtDispose);
    expect(controller.state.toJson(), previous);
    final restored =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    addTearDown(restored.dispose);
    expect(await restored.load(), isTrue);
    expect(restored.state.materials[CampMaterial.wood], 1);
  });

  test('default ownership reload excludes failed cached dex writes', () async {
    final dex = DexStore();
    await dex.add(entry('road_sprout'));
    final controller =
        BaseCampController(store: MemoryCampStore(), nowMs: () => epoch);
    addTearDown(controller.dispose);
    await controller.load();
    failWrite = true;
    await expectLater(dex.add(entry('puddle_pip')), throwsStateError);
    expect(await dex.all(), hasLength(2));
    failWrite = false;
    expect(await controller.refreshOwnership(), isTrue);
    expect(controller.state.creatures.values.map((c) => c.speciesId),
        ['road_sprout']);
    failRead = true;
    expect(await controller.refreshOwnership(), isFalse);
    expect(controller.state.creatures, hasLength(1));
  });

  test('parallel build commands cannot overdraw the same durable resources',
      () async {
    var now = epoch;
    final controller = BaseCampController(
        store: MemoryCampStore(),
        dex: TestDex([entry('road_sprout')]),
        nowMs: () => now);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.assign(
        CampRole.builder, controller.state.creatures.keys.single);
    await controller.recordLookOut(eventId: 'first');
    now += 60000;
    await controller.recordLookOut(eventId: 'second');
    final results = await Future.wait([
      controller.startBuild(CampFacility.workshop),
      controller.startBuild(CampFacility.workshop),
    ]);
    expect(results, [true, false]);
    expect(controller.state.jobs, hasLength(1));
    expect(controller.state.materials[CampMaterial.wood], 0);
    expect(controller.state.materials[CampMaterial.stone], 1);
    await controller.cancel(CampRole.builder);
    expect(controller.state.materials[CampMaterial.wood], 2);
  });

  test(
      'load catches up jobs and food expiry before publishing and learned actions remain gated',
      () async {
    var now = epoch;
    final store = MemoryCampStore();
    final dex = TestDex(
        [entry('road_sprout'), entry('puddle_pip'), entry('lamp_moth')]);
    var controller =
        BaseCampController(store: store, dex: dex, nowMs: () => now);
    await controller.load();
    String id(String species) => controller.state.creatures.values
        .singleWhere((c) => c.speciesId == species)
        .id;
    final builder = id('road_sprout'),
        cook = id('puddle_pip'),
        trainer = id('lamp_moth');
    await controller.assign(CampRole.builder, builder);
    await controller.assign(CampRole.cook, cook);
    await controller.assign(CampRole.trainer, trainer);
    for (var i = 0; i < 8; i++) {
      expect(await controller.recordLookOut(eventId: 'event-$i'), isTrue);
      now += 60000;
    }
    for (final facility in CampFacility.values) {
      expect(await controller.startBuild(facility), isTrue);
      now += 30000;
      expect(await controller.tick(), isTrue);
    }
    expect(await controller.startCooking('berry_snack'), isTrue);
    now += 30000;
    await controller.tick();
    expect(controller.state.foodInventory['berry_snack'], 1);
    expect(controller.state.recipeBook['berry_snack'], 1);
    expect(await controller.feedFood('berry_snack', cook), isTrue);
    expect(await controller.startCooking('berry_snack'), isTrue);
    expect(await controller.startTraining('greeting', builder), isTrue);
    expect(controller.performAction(builder, 'greeting'), isNull);
    controller.dispose();
    now += 360000;
    controller = BaseCampController(store: store, dex: dex, nowMs: () => now);
    addTearDown(() => controller.dispose());
    expect(await controller.load(), isTrue);
    expect(controller.state.jobs, isEmpty);
    expect(controller.state.foodInventory['berry_snack'], 1);
    expect(controller.state.recipeBook['berry_snack'], 2);
    expect(controller.performAction(builder, 'greeting'), 'greeting');
    final beforeAction = controller.state.materials;
    controller.performAction(builder, 'greeting');
    expect(controller.state.materials, beforeAction);
    expect(await controller.startCooking('berry_snack'), isTrue);
    now += 20000;
    await controller.tick();
    expect(controller.state.jobs.containsKey(CampRole.cook), isTrue);
    now += 10000;
    await controller.tick();
    expect(controller.state.foodInventory['berry_snack'], 2);
    expect(controller.state.recipeBook['berry_snack'], 3);
  });

  test(
      'failed catchup save retains unready state and retries from durable envelope',
      () async {
    var now = epoch;
    final store = MemoryCampStore();
    final dex = TestDex([entry('road_sprout')]);
    final original =
        BaseCampController(store: store, dex: dex, nowMs: () => now);
    await original.load();
    await original.assign(
        CampRole.builder, original.state.creatures.keys.single);
    await original.recordLookOut(eventId: 'a');
    now += 60000;
    await original.recordLookOut(eventId: 'b');
    await original.startBuild(CampFacility.workshop);
    original.dispose();
    final saved = jsonEncode(store.value);
    now += 30000;
    store.failSave = true;
    final resumed =
        BaseCampController(store: store, dex: dex, nowMs: () => now);
    addTearDown(resumed.dispose);
    expect(await resumed.load(), isFalse);
    expect(resumed.ready, isFalse);
    expect(resumed.error, 'save_failed');
    expect(jsonEncode(store.value), saved);
    store.failSave = false;
    expect(await resumed.load(), isTrue);
    expect(resumed.state.facilities[CampFacility.workshop], 1);
  });

  test('drive baseline survives failed save before accepting subsequent reward',
      () async {
    final store = MemoryCampStore();
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    addTearDown(controller.dispose);
    await controller.load();
    store.failSave = true;
    expect(
        await controller.recordVehicle(
            sessionId: 's', vehicle: vehicle(1, 1000)),
        isFalse);
    store.failSave = false;
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(2, 11000));
    expect(controller.state.materials[CampMaterial.wood], 0);
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(3, 12000));
    expect(controller.state.materials[CampMaterial.wood], 1);
  });

  test(
      'actual preference profiles maintain isolated controller resources on restart',
      () async {
    final real = BaseCampController(
        store: SharedPreferencesBaseCampStore(),
        dex: TestDex([]),
        nowMs: () => epoch);
    final demo = BaseCampController(
        store: SharedPreferencesBaseCampStore(profile: 'demo'),
        dex: TestDex([]),
        nowMs: () => epoch);
    await real.load();
    await demo.load();
    await demo.recordLookOut(eventId: 'demo-only');
    real.dispose();
    demo.dispose();
    final reopened = BaseCampController(
        store: SharedPreferencesBaseCampStore(),
        dex: TestDex([]),
        nowMs: () => epoch);
    addTearDown(reopened.dispose);
    expect(await reopened.load(), isTrue);
    expect(reopened.state.materials[CampMaterial.wood], 0);
  });

  test(
      'disposing with a queued mutation drains busy state without extra writes',
      () async {
    final store = MemoryCampStore();
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    await controller.load();
    store.block = Completer<void>();
    final writing = controller.recordLookOut(eventId: 'one');
    final queued = controller.recordLookOut(eventId: 'two');
    await flush();
    controller.dispose();
    store.block!.complete();
    await writing;
    expect(await queued, isFalse);
    expect(controller.busy, isFalse);
    expect(store.saves, 2);
  });

  test('explicit real dex reload excludes rejected cached ownership writes',
      () async {
    final dex = DexStore();
    await dex.add(entry('road_sprout'));
    final controller = BaseCampController(
        store: MemoryCampStore(), dex: dex, nowMs: () => epoch);
    addTearDown(controller.dispose);
    await controller.load();
    failWrite = true;
    await expectLater(dex.add(entry('puddle_pip')), throwsStateError);
    failWrite = false;
    expect(await controller.refreshOwnership(), isTrue);
    expect(controller.state.creatures, hasLength(1));
  });

  testWidgets('periodic idle clock does not write unchanged camp resources',
      (tester) async {
    final store = MemoryCampStore();
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    await controller.load();
    await tester.pump(const Duration(seconds: 3));
    final saves = store.saves;
    controller.dispose();
    expect(saves, 1);
  });

  testWidgets('active job timer catches up the provided epoch clock',
      (tester) async {
    var now = epoch;
    final controller = BaseCampController(
        store: MemoryCampStore(),
        dex: TestDex([entry('road_sprout')]),
        nowMs: () => now);
    await controller.load();
    await controller.assign(
        CampRole.builder, controller.state.creatures.keys.single);
    await controller.recordLookOut(eventId: 'a');
    now += 60000;
    await controller.recordLookOut(eventId: 'b');
    await controller.startBuild(CampFacility.workshop);
    now += 30000;
    await tester.pump(const Duration(seconds: 1));
    final level = controller.state.facilities[CampFacility.workshop];
    controller.dispose();
    expect(level, 1);
  });

  test('commands enqueued by busy listeners remain in the same save queue',
      () async {
    final store = MemoryCampStore();
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    addTearDown(controller.dispose);
    await controller.load();
    store.block = Completer<void>();
    Future<bool>? second;
    var enqueued = false;
    controller.addListener(() {
      if (controller.busy && !enqueued) {
        enqueued = true;
        second = controller.recordLookOut(eventId: 'listener');
      }
    });
    final first = controller.recordLookOut(eventId: 'caller');
    await flush();
    final maximum = store.maxInFlight;
    store.block!.complete();
    final firstResult = await first;
    final secondResult = await second!;
    expect(maximum, 1);
    expect(firstResult, isTrue);
    expect(secondResult, isFalse);
    expect(controller.state.materials[CampMaterial.wood], 1);
  });

  test('queued pre-resume samples cannot consume the resumed baseline',
      () async {
    final store = MemoryCampStore();
    final controller =
        BaseCampController(store: store, dex: TestDex([]), nowMs: () => epoch);
    addTearDown(controller.dispose);
    expect(await controller.load(), isTrue);
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(1, 0));
    store.block = Completer<void>();
    final writing = controller.tick();
    await flush();
    final oldSample =
        controller.recordVehicle(sessionId: 's', vehicle: vehicle(2, 1000));
    controller.beginDrivingSession('s');
    final resumed =
        controller.recordVehicle(sessionId: 's', vehicle: vehicle(3, 11000));
    store.block!.complete();
    expect(await writing, isTrue);
    expect(await oldSample, isTrue);
    expect(await resumed, isTrue);
    expect(controller.state.materials[CampMaterial.wood], 1);
    await controller.recordVehicle(sessionId: 's', vehicle: vehicle(4, 12000));
    expect(controller.state.materials[CampMaterial.wood], 2);
  });

  test('actual saved source ID survives metadata updates without rewriting dex',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final record = {...entry('road_sprout').toJson(), 'sourceEggId': 'egg-1'};
    await preferences.setStringList('dex.entries.v1', [jsonEncode(record)]);
    final controller =
        BaseCampController(store: MemoryCampStore(), nowMs: () => epoch);
    addTearDown(controller.dispose);
    expect(await controller.load(), isTrue);
    final id = controller.state.creatures.keys.single;
    expect(await controller.assign(CampRole.builder, id), isTrue);
    record['envTags'] = ['rain'];
    final raw = jsonEncode(record);
    await preferences.setStringList('dex.entries.v1', [raw]);
    expect(await controller.refreshOwnership(), isTrue);
    expect(controller.state.creatures.keys.single, id);
    expect(controller.state.assignments[CampRole.builder], id);
    expect(preferences.getStringList('dex.entries.v1'), [raw]);
  });

  test(
      'raw source records still validate dex payload and preserve prior ownership on failure',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final record = {...entry('road_sprout').toJson(), 'sourceEggId': 'egg-1'};
    await preferences.setStringList('dex.entries.v1', [jsonEncode(record)]);
    expect((await DexStore().allRecords()).single['sourceEggId'], 'egg-1');
    expect((await DexStore().all()).single.speciesId, 'road_sprout');
    final store = MemoryCampStore();
    final controller = BaseCampController(store: store, nowMs: () => epoch);
    addTearDown(controller.dispose);
    expect(await controller.load(), isTrue);
    final previous = controller.state.toJson();
    final saved = jsonEncode(store.value);
    record['obtainedAt'] = 'not-a-date';
    final raw = jsonEncode(record);
    await preferences.setStringList('dex.entries.v1', [raw]);
    expect(await controller.refreshOwnership(), isFalse);
    expect(controller.error, 'ownership_read_failed');
    expect(controller.state.toJson(), previous);
    expect(jsonEncode(store.value), saved);
    expect(preferences.getStringList('dex.entries.v1'), [raw]);
  });
}

const epoch = 1700000000000;
Future<void> flush() => Future<void>.delayed(Duration.zero);

DexEntry entry(String species, {List<String> tags = const ['city']}) =>
    DexEntry(
      speciesId: species,
      obtainedAt: DateTime.utc(2026, 11, 12),
      envTags: tags,
      regionTag: 'city',
      tier: 1,
    );

VehicleState vehicle(int ts, double distance) => VehicleState(
      ts: ts,
      gear: 'D',
      speedKph: 60,
      distanceM: distance,
      harshBrake: 0,
      harshSteer: 0,
      wiperLevel: 0,
      headlightOn: false,
      seatRow2: true,
      etaSec: null,
      envTags: const [],
      capabilities: const [],
    );

class SourceEntry extends DexEntry {
  SourceEntry(this.source, String species, List<String> tags)
      : super(
          speciesId: species,
          obtainedAt: DateTime.utc(2026, 11, 12),
          envTags: tags,
          regionTag: 'city',
          tier: 1,
        );
  final String source;
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'sourceEggId': source};
}

class TestDex extends DexStore {
  TestDex(this.entries);
  List<DexEntry> entries;
  bool fail = false;
  int writes = 0;
  @override
  Future<List<Map<String, dynamic>>> allRecords() async {
    if (fail) throw StateError('ownership unavailable');
    return entries.map((entry) => entry.toJson()).toList();
  }

  @override
  Future<void> add(DexEntry e) async {
    writes++;
    throw StateError('Must not write dex');
  }
}

class MemoryCampStore implements BaseCampStore {
  Map<String, dynamic>? value;
  bool failSave = false;
  Completer<void>? block;
  int saves = 0, inFlight = 0, maxInFlight = 0;
  @override
  Future<Map<String, dynamic>?> load() async => value == null
      ? null
      : jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<void> save(Map<String, dynamic> next) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await block?.future;
      if (failSave) throw StateError('disk failed');
      value = jsonDecode(jsonEncode(next)) as Map<String, dynamic>;
      saves++;
    } finally {
      inFlight--;
    }
  }
}
