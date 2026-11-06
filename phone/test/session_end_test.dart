import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_resume_test.dart'
    show SnapshotFeed, FailingProgressStore, sessionA, sessionB;

class EndingFeed extends SnapshotFeed {
  bool alreadyEnded = false;
  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    if (alreadyEnded) throw const SessionEndedException();
  }

  final eventStream =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  @override
  Stream<Map<String, Object?>> events() => eventStream.stream;
  void end() => eventStream.add({'type': 'sessionEnd', 'by': 'car'});
  @override
  Future<void> dispose() async {
    await super.dispose();
    await eventStream.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('앱이 꺼진 동안 종료된 세션의 자동 재연결은 기록을 지우고 새 QR을 안내한다', () async {
    await PairingStore()
        .save(PairingCredentials.parseFields(sessionA, '123456'));
    final c = GameController(
        feed: EndingFeed()..alreadyEnded = true, dex: DexStore());
    addTearDown(c.dispose);
    await c.restorePairing();
    expect(c.paired, isFalse);
    expect(c.canStart, isFalse);
    expect(await PairingStore().read(), isNull);
    expect(c.error, contains('새 QR'));
  });

  test('연결 정보 삭제 실패도 저장된 진행을 유지하고 재시도한다', () async {
    final feed = EndingFeed();
    final pairing = ClearFailStore();
    final c =
        GameController(feed: feed, dex: DexStore(), pairingStore: pairing);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    pairing.fail = true;
    feed.end();
    expect(await c.endSession(), isFalse);
    expect(c.needsNewPairing, isFalse);
    expect(c.canStart, isFalse);
    expect(await DexStore().carriedDistance(EggTier.small), 2000);
    pairing.fail = false;
    expect(await c.endSession(), isTrue);
    expect(c.needsNewPairing, isTrue);
    expect(await pairing.read(), isNull);
  });

  test('품기 시작이 로컬 읽기를 기다리는 중 종료되면 구독을 시작하지 않는다', () async {
    final feed = EndingFeed();
    final store = SlowProgressStore();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    final start = c.startIncubating(EggTier.small);
    await store.entered.future;
    feed.end();
    await c.endSession();
    store.result.complete(const IncubationProgress());
    expect(await start, isFalse);
    expect(c.needsNewPairing, isTrue);
    feed.send(5000);
    expect(c.game.stage, Stage.idle);
  });

  test('payload 없는 종료 이벤트는 진행을 저장하고 연결 정보를 지운다', () async {
    final feed = EndingFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    feed.end();
    expect(c.canStart, isFalse);
    expect(await c.endSession(), isTrue);
    expect(await PairingStore().read(), isNull);
    expect(await DexStore().carriedDistance(EggTier.small), 2000);
    expect(c.pairingNotice, contains('새 QR'));
    feed.send(4000);
    expect(c.game.progress, .4);
    await c.pair(sessionB, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.send(1000);
    expect(c.game.progress, .6);
    await c.endSession();
  });

  test('종료 시 저장 실패는 기록을 버리지 않고 재시도하며 새 품기를 막는다', () async {
    final feed = EndingFeed();
    final store = FailingProgressStore();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(2000);
    store.fail = true;
    feed.end();
    expect(await c.endSession(), isFalse);
    expect(c.canStart, isFalse);
    expect(await c.startIncubating(EggTier.small), isFalse);
    expect(await PairingStore().read(), isNotNull);
    feed.send(4000);
    expect(c.game.progress, .4);
    store.fail = false;
    expect(await c.endSession(), isTrue);
    expect(await PairingStore().read(), isNull);
    expect(await store.carriedDistance(EggTier.small), 2000);
  });

  test('부화 뒤 중복 종료 이벤트도 도감을 한 번만 저장한다', () async {
    final feed = EndingFeed();
    final c = GameController(feed: feed, dex: DexStore());
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.send(5000);
    feed.end();
    feed.end();
    expect(await c.endSession(), isTrue);
    expect(c.paired, isFalse);
    expect((await DexStore().all()).length, 1);
    expect(await PairingStore().read(), isNull);
  });
}

class ClearFailStore extends PairingStore {
  bool fail = false;
  @override
  Future<void> clear() async {
    if (fail) throw StateError('clear unavailable');
    await super.clear();
  }
}

class SlowProgressStore extends DexStore {
  final entered = Completer<void>();
  final result = Completer<IncubationProgress>();
  @override
  Future<IncubationProgress> incubationProgress(EggTier tier) {
    entered.complete();
    return result.future;
  }
}
