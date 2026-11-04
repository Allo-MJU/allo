import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('PR #8: 생략된 ETA·환경 태그는 거리 폴백으로 읽는다', () {
    final vehicle =
        VehicleState.fromJson({'ts': 1000, 'gear': 'D', 'distanceM': 2500});
    expect(vehicle.etaSec, isNull);
    expect(vehicle.envTags, isEmpty);
    final timer = HatchTimer(eggTier: EggTier.small);
    expect(timer.update(vehicle), 0.5);
    expect(timer.usesEta, isFalse);
  });

  testWidgets('ETA 가속·목표 필드·도감 저장', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final c = GameController(
          feed: FakeVehicleFeed(scenario: FakeScenario.clear, timeScale: 100),
          dex: DexStore());
      try {
        final hatched = Completer<void>();
        c.addListener(() {
          if (c.game.hatchAtSec != null) expect(c.game.hatchAtM, isNull);
          if (c.game.stage == Stage.hatched && !hatched.isCompleted) {
            hatched.complete();
          }
        });
        expect(await c.startIncubating(EggTier.small), isTrue);
        await hatched.future.timeout(const Duration(seconds: 7));
        await c.endSession();
        final saved = await DexStore().all();
        expect(saved.single.speciesId, c.hatched!.id);
        expect(saved.single.envTags, isEmpty);
      } finally {
        c.dispose();
      }
    });
  });

  testWidgets('도감 저장 실패 후 재시도해도 중복 등록되지 않는다', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final c = GameController(
          feed: FakeVehicleFeed(
              scenario: FakeScenario.rainyHighway, timeScale: 200),
          dex: _FailOnceStore());
      try {
        final failed = Completer<void>();
        c.addListener(() {
          if (c.error != null && !failed.isCompleted) failed.complete();
        });
        expect(await c.startIncubating(EggTier.small), isTrue);
        await failed.future.timeout(const Duration(seconds: 4));
        expect(await c.endSession(), isTrue);
        expect((await DexStore().all()).length, 1);
        expect(await c.startIncubating(EggTier.small), isTrue);
        await c.endSession();
      } finally {
        c.dispose();
      }
    });
  });

  testWidgets('새 Fake 주행은 누적 신호가 초기화된다', (tester) async {
    await tester.runAsync(() async {
      final feed = FakeVehicleFeed(scenario: FakeScenario.rainyHighway);
      try {
        await feed.watch().take(2).toList();
        final next = await feed.watch().first;
        expect(next.distanceM, 500);
      } finally {
        await feed.dispose();
      }
    });
  });
}

class _FailOnceStore extends DexStore {
  bool failed = false;
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    if (!failed) {
      failed = true;
      throw StateError('storage unavailable');
    }
    await super.saveIncubationProgress(tier, progress);
  }
}
