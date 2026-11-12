import 'dart:typed_data';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/app.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/local_affinity/demo_runtime.dart';
import 'package:allo_phone/main.dart' show configuredEggApi;
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/fishing/fishing_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('optional API configuration is absent by default', () {
    expect(configuredEggApi(), isNull);
  });
  test('debug stores do not mutate normal dex or fishing storage', () async {
    final normal = DexStore();
    final entry = DexEntry(
        speciesId: 'road_sprout',
        obtainedAt: DateTime.utc(2026),
        envTags: const [],
        regionTag: null,
        tier: 1);
    final local = LocalAffinityDex();
    await local.add(entry);
    await local.saveIncubationProgress(
        EggTier.small, const IncubationProgress(carriedM: 123));
    await LocalAffinityFishing().write({'selected': 'demo'});
    expect(await normal.all(), isEmpty);
    expect((await normal.incubationProgress(EggTier.small)).carriedM, 0);
    expect(await FishingStore().read(), isNull);
    expect(await local.all(), hasLength(1));
  });
  test('explicit synthetic API is idempotent and clears receipts on close',
      () async {
    final api = LocalAffinityApi();
    final first = await api.uploadPhoto(
        eggId: 'egg',
        requestId: 'one',
        bytes: Uint8List(0),
        mimeType: 'image/jpeg');
    final retry = await api.uploadPhoto(
        eggId: 'egg',
        requestId: 'two',
        bytes: Uint8List(0),
        mimeType: 'image/jpeg');
    expect(retry, same(first));
    expect(
        await api.evaluate(eggId: 'egg', requestId: 'talk', text: 'test input'),
        SpeechSentiment.positive);
    api.close();
    expect(await api.findPhotoForEgg('egg'), isNull);
    await expectLater(
        api.evaluate(eggId: 'egg', requestId: 'talk2', text: 'test'),
        throwsStateError);
  });
  test('local feed retains paired lease and emits trip end', () async {
    final feed = LocalAffinityFeed();
    final states = <VehicleState>[];
    final sub = feed.watch().listen(states.add);
    await feed.publishGame(const GameState(
        ts: 1,
        eggTier: EggTier.small,
        stage: Stage.idle,
        progress: 0,
        vehicleFeatures: {
          'fishing': {'leaseId': 'lease'}
        }));
    feed.advance(10000);
    await Future<void>.delayed(Duration.zero);
    expect(states.last.gear, 'P');
    expect(states.last.fishingPresence?['leaseId'], 'lease');
    final ended = feed.events().first;
    feed.endTrip();
    expect((await ended)['type'], 'sessionEnd');
    await sub.cancel();
    await feed.dispose();
  });
  testWidgets('general app owns and closes its injected API', (tester) async {
    final api = LocalAffinityApi();
    await tester.pumpWidget(AlloApp(
        feed: FakeVehicleFeed(scenario: FakeScenario.rainyHighway),
        eggApi: api));
    await tester.pump();
    expect(api.closed, false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(api.closed, true);
  });
}
