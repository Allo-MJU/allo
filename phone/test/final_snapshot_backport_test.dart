import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_end_regression_test.dart' show EndingFeed;
import 'session_resume_test.dart' show sessionA, sessionB;

class FinalFeed extends EndingFeed {
  VehicleState? latest;
  int reads = 0;
  bool fail = false;
  Completer<VehicleState?>? readGate;
  int pairCalls = 0;
  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    pairCalls++;
    await super.pair(sessionId, pairCode: pairCode);
  }

  @override
  Future<VehicleState?> readLatestVehicle() async {
    reads++;
    if (fail) throw StateError('read unavailable');
    return readGate == null ? latest : readGate!.future;
  }

  void server(double distance) => latest = VehicleState.fromJson({
        'ts': 2000,
        'gear': 'P',
        'distanceM': distance,
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('종료 이벤트가 먼저 와도 서버의 최종 4km를 저장한다', () async {
    final feed = FinalFeed();
    final store = DexStore();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), true);
    feed.send(2000);
    feed.server(4000);
    feed.end();
    expect(await c.endSession(), true);
    expect(await store.carriedDistance(EggTier.small), 4000);
    expect(feed.reads, 1);
  });
  test('종료 직전 4.9km에서 최종 5km를 읽어 부화와 도감을 저장한다', () async {
    final feed = FinalFeed();
    final store = DexStore();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), true);
    feed.send(4900);
    feed.server(5000);
    feed.end();
    expect(await c.endSession(), true);
    expect(c.game.stage, Stage.hatched);
    expect(await store.all(), hasLength(1));
    expect(await store.carriedDistance(EggTier.small), 0);
  });
  test('최종 조회 실패는 연결을 보존하고 재시도에서 최종 값을 읽는다', () async {
    final feed = FinalFeed()..fail = true;
    final store = DexStore();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    feed.server(4000);
    feed.end();
    expect(await c.endSession(), false);
    expect(c.sessionSaved, false);
    expect(c.canStart, false);
    expect(await PairingStore().read(), isNotNull);
    feed.fail = false;
    expect(await c.endSession(), true);
    expect(feed.reads, 2);
    expect(await store.carriedDistance(EggTier.small), 4000);
  });

  test('최종 조회 중 중복 종료는 합쳐지고 다른 세션 연결은 시작하지 않는다', () async {
    final feed = FinalFeed()..readGate = Completer<VehicleState?>();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    feed.server(4000);
    feed.end();
    final closing = c.endSession();
    feed.end();
    await c.pair(sessionB, pairCode: '123456');
    expect(feed.pairCalls, 1);
    expect(feed.reads, 1);
    feed.readGate!.complete(feed.latest);
    expect(await closing, true);
    expect(await c.endSession(), true);
    expect(feed.reads, 1);
  });

  test('dispose 뒤 완료된 최종 읽기는 도감과 연결 기록을 바꾸지 않는다', () async {
    final feed = FinalFeed()..readGate = Completer<VehicleState?>();
    final store = DexStore();
    final c = GameController(feed: feed, dex: store);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(4900);
    feed.server(5000);
    feed.end();
    final closing = c.endSession();
    c.dispose();
    feed.readGate!.complete(feed.latest);
    expect(await closing, false);
    expect(await store.all(), isEmpty);
    expect(await PairingStore().read(), isNotNull);
  });

  test('수동 저장 중 종료가 오면 같은 작업에서 최종 거리를 다시 저장한다', () async {
    final feed = FinalFeed();
    final store = GateProgress();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    store.gate = Completer<void>();
    final save = c.endSession();
    await store.entered.future;
    feed.server(4000);
    feed.end();
    store.gate!.complete();
    expect(await save, true);
    expect(feed.reads, 1);
    expect(await store.carriedDistance(EggTier.small), 4000);
  });

  test('구독 취소 중 종료가 와도 최종 부화를 도감에 저장한다', () async {
    final feed = CancelFinalFeed();
    final store = DexStore();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(4900);
    feed.server(5000);
    feed.onCancel = feed.end;
    expect(await c.endSession(), true);
    expect(feed.reads, 1);
    expect(await store.all(), hasLength(1));
    expect(await store.carriedDistance(EggTier.small), 0);
  });
}

class GateProgress extends DexStore {
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    if (gate != null) {
      if (!entered.isCompleted) entered.complete();
      await gate!.future;
    }
    await super.saveIncubationProgress(tier, progress);
  }
}

class CancelFinalFeed extends FinalFeed {
  void Function()? onCancel;
  late final direct = StreamController<VehicleState>(
      sync: true, onCancel: () => onCancel?.call());
  @override
  Stream<VehicleState> watch() => direct.stream;
  @override
  void send(double distance) => direct.add(
      VehicleState.fromJson({'ts': 1000, 'gear': 'D', 'distanceM': distance}));
  @override
  Future<void> dispose() async {
    onCancel = null;
    await direct.close();
    await super.dispose();
  }
}
