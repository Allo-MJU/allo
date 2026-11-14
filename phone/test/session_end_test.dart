import 'dart:async';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/vehicle_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sessionA = 'b0c260a8-e807-42e9-a119-26119837113b';
const _sessionB = 'b0c260a8-e807-42e9-a119-26119837113c';
const _end = <String, Object?>{'ts': 3000, 'type': 'sessionEnd', 'by': 'car'};

class EndFeed implements VehicleFeed {
  final signals = StreamController<VehicleState>.broadcast(sync: true);
  final carEvents =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  final published = <GameState>[];
  VehicleState? latest;
  Completer<VehicleState?>? readGate;
  bool failRead = false;
  int reads = 0;

  void send(double distance, {bool deliver = true}) {
    latest = VehicleState.fromJson({
      'ts': 2000,
      'gear': 'P',
      'distanceM': distance,
    });
    if (deliver) signals.add(latest!);
  }

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {}
  @override
  Stream<VehicleState> watch() => signals.stream;
  @override
  Stream<Map<String, Object?>> events() => carEvents.stream;
  @override
  Future<VehicleState?> readLatestVehicle() async {
    reads++;
    if (failRead) throw StateError('offline');
    return readGate == null ? latest : await readGate!.future;
  }

  @override
  Future<void> publishGame(GameState state) async => published.add(state);
  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {}
  @override
  Future<void> dispose() async {
    await signals.close();
    await carEvents.close();
  }
}

class SavingStore extends DexStore {
  int progressWrites = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    progressWrites++;
    await gate?.future;
    if (fail) throw StateError('disk full');
    await super.saveIncubationProgress(tier, progress);
  }
}

Future<GameController> _start(EndFeed feed, {DexStore? dex}) async {
  final c = GameController(feed: feed, dex: dex ?? DexStore());
  await c.pair(_sessionA, pairCode: '123456');
  expect(await c.startIncubating(EggTier.small), isTrue);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('수동 저장 실패 중 버퍼에 쌓인 주행 신호도 재개 후 반영한다', () async {
    final feed = EndFeed();
    final store = SavingStore()
      ..gate = Completer<void>()
      ..fail = true;
    final c = await _start(feed, dex: store);
    addTearDown(c.dispose);
    feed.send(2000);
    final saving = c.endSession();
    await Future<void>.delayed(Duration.zero);
    feed.send(3000);
    store.gate!.complete();
    expect(await saving, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(c.game.progress, .6);
    store.fail = false;
    expect(await c.endSession(), isTrue);
    expect(await store.carriedDistance(EggTier.small), 3000);
  });

  test('수동 저장 뒤 구독 해제 중 종료가 도착해도 최종 신호를 저장한다', () async {
    final feed = EndFeed();
    final c = await _start(feed);
    addTearDown(c.dispose);
    feed.send(2000);
    feed.send(3000, deliver: false);
    feed.signals.onCancel = () => feed.carEvents.add(_end);
    expect(await c.endSession(), isTrue);
    expect(c.sessionSaved, isTrue);
    expect(await DexStore().carriedDistance(EggTier.small), 3000);
  });

  test('차량 종료는 즉시 새 품기를 막고 2km를 자동 저장한다', () async {
    final feed = EndFeed();
    final c = await _start(feed);
    addTearDown(c.dispose);
    feed.send(2000);
    feed.carEvents.add(_end);
    expect(c.canStart, isFalse);
    expect(await c.endSession(), isTrue);
    expect(await DexStore().carriedDistance(EggTier.small), 2000);
    expect(c.paired, isFalse);
    expect(await PairingStore().read(), isNull);
    feed.send(4000);
    expect(c.game.progress, .4);
    expect(await c.startIncubating(EggTier.small), isFalse);
  });

  test('종료 콜백이 마지막 신호보다 먼저 와도 최종 3km를 저장한다', () async {
    final feed = EndFeed();
    final c = await _start(feed);
    addTearDown(c.dispose);
    feed.send(2000);
    feed.send(3000, deliver: false);
    feed.carEvents.add(_end);
    expect(c.canStart, isFalse);
    expect(await c.endSession(), isTrue);
    expect(await DexStore().carriedDistance(EggTier.small), 3000);
    expect(c.game.progress, .6);
  });

  test('중복 종료와 수동 종료는 저장 작업 하나를 공유한다', () async {
    final feed = EndFeed();
    final store = SavingStore()..gate = Completer<void>();
    final c = await _start(feed, dex: store);
    addTearDown(c.dispose);
    feed.send(2000);
    feed.carEvents.add(_end);
    final first = c.endSession();
    feed.carEvents.add({..._end, 'ts': 4000});
    final second = c.endSession();
    expect(identical(first, second), isTrue);
    store.gate!.complete();
    expect(await first, isTrue);
    expect(store.progressWrites, 1);
    expect(await DexStore().carriedDistance(EggTier.small), 2000);
  });

  test('이월 저장 실패는 잠금을 유지하고 재시도 후 다음 세션에서 이어간다', () async {
    final feed = EndFeed();
    final store = SavingStore()..fail = true;
    final c = await _start(feed, dex: store);
    addTearDown(c.dispose);
    feed.send(2000);
    feed.carEvents.add(_end);
    expect(await c.endSession(), isFalse);
    expect(c.canStart, isFalse);
    expect(c.error, isNotNull);
    await c.pair(_sessionB, pairCode: '123456');
    expect(c.paired, isFalse);
    store.fail = false;
    expect(await c.endSession(), isTrue);
    await c.pair(_sessionB, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.send(1000);
    expect(c.game.progress, .6);
    await c.endSession();
  });

  test('최종 신호 읽기 실패 시 성공 처리하지 않고 읽기 재시도를 허용한다', () async {
    final feed = EndFeed()..failRead = true;
    final c = await _start(feed);
    addTearDown(c.dispose);
    feed.send(2000);
    feed.carEvents.add(_end);
    expect(await c.endSession(), isFalse);
    expect(c.canStart, isFalse);
    feed.failRead = false;
    feed.send(3000, deliver: false);
    expect(await c.endSession(), isTrue);
    expect(await DexStore().carriedDistance(EggTier.small), 3000);
  });

  test('마지막 저장 신호로 부화하면 이월은 0이고 도감은 한 건이다', () async {
    final feed = EndFeed();
    final c = await _start(feed);
    addTearDown(c.dispose);
    feed.send(4000);
    feed.send(5000, deliver: false);
    feed.carEvents.add(_end);
    expect(c.canStart, isFalse);
    expect(await c.endSession(), isTrue);
    expect(c.game.stage, Stage.hatched);
    expect((await DexStore().all()).length, 1);
    expect(await DexStore().carriedDistance(EggTier.small), 0);
    expect(feed.published.last.stage, Stage.hatched);
  });

  test('부화 저장 중 종료는 완료를 기다리고 도감을 중복 저장하지 않는다', () async {
    final feed = EndFeed();
    final store = SavingStore()..gate = Completer<void>();
    final c = await _start(feed, dex: store);
    addTearDown(c.dispose);
    feed.send(5000);
    feed.carEvents.add(_end);
    var finished = false;
    final closing = c.endSession().then((value) {
      finished = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(c.canStart, isFalse);
    store.gate!.complete();
    expect(await closing, isTrue);
    expect((await DexStore().all()).length, 1);
    // Freeze the result before adding to the dex, then mark it committed.
    expect(store.progressWrites, 2);
  });

  test('알 지급 전 과거 종료 이벤트도 종료로 처리하며 같은 세션을 되살리지 않는다', () async {
    final feed = EndFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(_sessionA, pairCode: '123456');
    feed.carEvents.add({..._end, 'ts': 1});
    expect(c.canStart, isFalse);
    expect(await c.endSession(), isTrue);
    expect(await c.startIncubating(EggTier.small), isFalse);
    await c.pair(_sessionA, pairCode: '123456');
    expect(c.canStart, isFalse);
    expect((await DexStore().all()), isEmpty);
  });

  test('종료 이벤트만으로 저장을 끝내며 별도 종료 버튼이 필요하지 않다', () async {
    final feed = EndFeed();
    final c = await _start(feed);
    addTearDown(c.dispose);
    final finished = Completer<void>();
    c.addListener(() {
      if (c.sessionSaved && !finished.isCompleted) finished.complete();
    });
    feed.send(2000);
    feed.carEvents.add(_end);
    await finished.future.timeout(const Duration(seconds: 2));
    expect(await DexStore().carriedDistance(EggTier.small), 2000);
    expect(c.canStart, isFalse);
  });

  test('수동 저장 도중 종료가 도착하면 같은 작업에서 최종 거리까지 갱신한다', () async {
    final feed = EndFeed();
    final store = SavingStore()..gate = Completer<void>();
    final c = await _start(feed, dex: store);
    addTearDown(c.dispose);
    feed.send(2000);
    final saving = c.endSession();
    // 종료가 오기 전 시작한 체크포인트 저장을 대기시킨다.
    await Future<void>.delayed(Duration.zero);
    feed.send(3000, deliver: false);
    feed.carEvents.add(_end);
    expect(c.endSession(), same(saving));
    store.gate!.complete();
    expect(await saving, isTrue);
    expect(c.sessionSaved, isTrue);
    expect(await DexStore().carriedDistance(EggTier.small), 3000);
  });

  test('페어링 정보 삭제 실패도 완료로 표시하지 않고 재시도한다', () async {
    final feed = EndFeed();
    final pairing = FailingPairingStore();
    final c =
        GameController(feed: feed, dex: DexStore(), pairingStore: pairing);
    addTearDown(c.dispose);
    await c.pair(_sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    feed.carEvents.add(_end);
    expect(await c.endSession(), isFalse);
    expect(c.sessionSaved, isFalse);
    expect(c.canStart, isFalse);
    pairing.fail = false;
    expect(await c.endSession(), isTrue);
    expect(c.sessionSaved, isTrue);
    expect(await PairingStore().read(), isNull);
    expect(await DexStore().carriedDistance(EggTier.small), 2000);
  });

  test('종료 후 dispose된 컨트롤러의 지연된 최종 읽기는 기록을 덮어쓰지 않는다', () async {
    final feed = EndFeed()..readGate = Completer<VehicleState?>();
    final c = await _start(feed);
    feed.send(2000);
    feed.carEvents.add(_end);
    final closing = c.endSession();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await DexStore().saveIncubationProgress(
        EggTier.small, const IncubationProgress(carriedM: 3000));
    feed.readGate!
        .complete(VehicleState.fromJson({'ts': 2000, 'distanceM': 4000}));
    expect(await closing, isFalse);
    expect(await DexStore().carriedDistance(EggTier.small), 3000);
  });

  test('지연된 페어링 저장 확인을 기다리던 이전 컨트롤러는 새 연결 정보를 지우지 않는다', () async {
    final feed = EndFeed();
    final store = DelayedPairingStore();
    final c = GameController(feed: feed, dex: DexStore(), pairingStore: store);
    final pairing = c.pair(_sessionA, pairCode: '123456');
    await store.written.future;
    feed.carEvents.add(_end);
    final closing = c.endSession();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await PairingStore()
        .save(PairingCredentials.parseFields(_sessionB, '123456'));
    store.acknowledged.complete();
    await pairing;
    expect(await closing, isFalse);
    expect((await PairingStore().read())?.sessionId, _sessionB);
  });

  test('종료 중 dispose되면 실패한 이전 부화 저장을 새로 재시도하지 않는다', () async {
    final feed = EndFeed();
    final store = DelayedFailingDex();
    final c = await _start(feed, dex: store);
    feed.send(5000);
    feed.carEvents.add(_end);
    final closing = c.endSession();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await DexStore().saveIncubationProgress(
        EggTier.small, const IncubationProgress(carriedM: 3000));
    store.gate.complete();
    expect(await closing, isFalse);
    expect(store.calls, 1);
    expect(await DexStore().carriedDistance(EggTier.small), 3000);
  });

  test('다른 이벤트와 기어 P만으로는 차량 세션을 종료하지 않는다', () async {
    final feed = EndFeed();
    final c = await _start(feed);
    addTearDown(c.dispose);
    feed.send(2000);
    feed.carEvents.add({'type': 'destinationSuggest', 'by': 'car'});
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'phone'});
    feed.carEvents.add({'type': 'sessionEnd'});
    expect(c.canStart, isTrue);
    c.care();
    expect(c.careCount, 1);
    await c.endSession();
  });
}

class FailingPairingStore extends PairingStore {
  bool fail = true;
  @override
  Future<void> clear() async {
    if (fail) throw StateError('remove failed');
    await super.clear();
  }
}

class DelayedPairingStore extends PairingStore {
  final written = Completer<void>();
  final acknowledged = Completer<void>();
  @override
  Future<void> save(PairingCredentials credentials) async {
    await super.save(credentials);
    written.complete();
    await acknowledged.future;
  }
}

class DelayedFailingDex extends DexStore {
  int calls = 0;
  final gate = Completer<void>();
  @override
  Future<void> add(DexEntry entry) async {
    if (++calls == 1) {
      await gate.future;
      throw StateError('deferred failure');
    }
    await super.add(entry);
  }
}
