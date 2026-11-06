import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/vehicle_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sessionA = 'b0c260a8-e807-42e9-a119-26119837113b';
const sessionB = 'b0c260a8-e807-42e9-a119-26119837113c';

class SnapshotFeed implements VehicleFeed {
  final signals = StreamController<VehicleState>.broadcast(sync: true);
  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {}
  void send(double distance) => signals.add(VehicleState.fromJson({
        'ts': 1000,
        'distanceM': distance,
        'gear': 'D',
      }));
  @override
  Stream<VehicleState> watch() => signals.stream;
  @override
  Stream<Map<String, Object?>> events() => const Stream.empty();
  @override
  Future<VehicleState?> readLatestVehicle() async => null;
  @override
  Future<void> publishGame(GameState state) async {}
  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {}
  @override
  Future<void> dispose() async => signals.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('품기 저장 실패 뒤에도 신호를 받아 성장하고 저장 재시도가 가능하다', () async {
    final feed = SnapshotFeed();
    final store = FailingProgressStore();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    store.fail = true;
    expect(await c.endSession(), isFalse);
    feed.send(3000);
    expect(c.game.progress, .6);
    store.fail = false;
    expect(await c.endSession(), isTrue);
    expect(await store.carriedDistance(EggTier.small), 3000);
    feed.send(4000);
    expect(c.game.progress, .6);
  });

  test('같은 세션을 반복 재개해도 2km는 40%이며 새 주행분만 더한다', () async {
    final feed = SnapshotFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    expect(c.game.progress, .4);
    for (var i = 0; i < 3; i++) {
      await c.endSession();
      await c.startIncubating(EggTier.small);
      feed.send(2000);
      expect(c.game.progress, .4);
    }
    feed.send(3000);
    expect(c.game.progress, .6);
    await c.endSession();
  });

  test('앱 재실행 시 같은 세션 체크포인트를 복원하고 새 세션은 누적한다', () async {
    final feed = SnapshotFeed();
    final c = GameController(feed: feed, dex: DexStore());
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    await c.endSession();
    c.dispose();
    final nextFeed = SnapshotFeed();
    final next = GameController(feed: nextFeed, dex: DexStore());
    addTearDown(next.dispose);
    await next.pair(sessionA, pairCode: '123456');
    await next.startIncubating(EggTier.small);
    nextFeed.send(2000);
    expect(next.game.progress, .4);
    await next.endSession();
    await next.pair(sessionB, pairCode: '123456');
    await next.startIncubating(EggTier.small);
    nextFeed.send(1000);
    expect(next.game.progress, .6);
    await next.endSession();
  });

  test('신호 없이 재종료하거나 오래된 스냅샷을 받아도 저장 거리를 보존한다', () async {
    final feed = SnapshotFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    await c.endSession();
    await c.startIncubating(EggTier.small);
    await c.endSession();
    await c.startIncubating(EggTier.small);
    feed.send(1000);
    expect(c.game.progress, .4);
    feed.send(2500);
    expect(c.game.progress, .5);
    feed.send(2000);
    expect(c.game.progress, .5);
    await c.endSession();
    expect(await DexStore().carriedDistance(EggTier.small), 2500);
  });

  test('세션 정보 없는 구버전 저장은 보존하고 첫 스냅샷을 중복 가산하지 않는다', () async {
    SharedPreferences.setMockInitialValues({'hatch.carried.v1.small': 2000.0});
    final feed = SnapshotFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    expect(c.game.progress, .4);
    feed.send(3000);
    expect(c.game.progress, .6);
    await c.endSession();
    final saved = await DexStore().incubationProgress(EggTier.small);
    expect(saved.carriedM, 3000);
    expect(saved.sessionDistances[sessionA], 3000);
  });

  test('A에서 B로 이동한 뒤 A에 다시 연결해도 이미 계산한 거리는 더하지 않는다', () async {
    final feed = SnapshotFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    await c.endSession();
    await c.pair(sessionB, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(1000);
    expect(c.game.progress, .6);
    await c.endSession();
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    expect(c.game.progress, .6);
    expect(c.game.stage, Stage.incubating);
    feed.send(2500);
    expect(c.game.progress, .7);
    await c.endSession();
  });

  test('부화 후 같은 세션의 새 알은 사용한 거리로 즉시 부화하지 않는다', () async {
    final feed = SnapshotFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(5000);
    expect(c.game.stage, Stage.hatched);
    await c.endSession();
    await c.startIncubating(EggTier.small);
    feed.send(5000);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.progress, 0);
    feed.send(6000);
    expect(c.game.progress, .2);
    await c.endSession();
  });
}

class FailingProgressStore extends DexStore {
  bool fail = false;
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    if (fail) throw StateError('storage unavailable');
    await super.saveIncubationProgress(tier, progress);
  }
}
