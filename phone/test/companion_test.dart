import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('동행 상호작용은 부화 뒤에만 적용되고 등급·서버 계약을 바꾸지 않는다', () {
    final c = GameController(feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore());
    addTearDown(c.dispose);
    c.feedCompanion();
    c.playWithCompanion();
    expect(c.feedCount, 0);
    expect(c.playCount, 0);
    c.game = c.game.copyWith(stage: Stage.hatched, tier: 3);
    final before = c.game.toJson();
    c.feedCompanion();
    c.playWithCompanion();
    expect(c.feedCount, 1);
    expect(c.playCount, 1);
    expect(c.game.toJson(), before);
  });

  test('창밖 문구는 현재 태그를 따르고 미확인 지역을 단정하지 않는다', () {
    final c = GameController(feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore());
    addTearDown(c.dispose);
    expect(c.lookOutPrompt.$2, 'window');
    c.vehicle = VehicleState.fromJson({
      'envTags': ['rain']
    });
    expect(c.lookOutPrompt.$2, 'rain');
    c.vehicle = VehicleState.fromJson({
      'envTags': ['mountain']
    });
    expect(c.lookOutPrompt.$2, 'mountain');
    c.vehicle = VehicleState.fromJson({});
    expect(c.lookOutPrompt.$2, 'window');
  });

  test('새 알을 시작하면 이전 동행 반응을 초기화한다', () async {
    SharedPreferences.setMockInitialValues({});
    final c = GameController(feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore());
    addTearDown(c.dispose);
    c.game = c.game.copyWith(stage: Stage.hatched);
    c.feedCompanion();
    c.playWithCompanion();
    expect(await c.startIncubating(EggTier.small), isTrue);
    expect(c.feedCount, 0);
    expect(c.playCount, 0);
    expect(c.companionMessage, isNull);
    await c.endSession();
  });
}
