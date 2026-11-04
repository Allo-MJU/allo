import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/vehicle_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_resume_test.dart' show SnapshotFeed;

const sid = 'b0c260a8-e807-42e9-a119-26119837113b';
const code = '004829';

void main() {
  testWidgets('자동 재연결도 저장된 세션의 거리 위치를 복원한다', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await PairingStore().save(PairingCredentials.parseFields(sid, code));
      await DexStore().saveIncubationProgress(
          EggTier.small,
          const IncubationProgress(
              carriedM: 2000, sessionDistances: {sid: 2000}));
      final feed = SnapshotFeed();
      final c = GameController(feed: feed, dex: DexStore());
      try {
        await c.restorePairing();
        expect(await c.startIncubating(EggTier.small), isTrue);
        feed.send(2000);
        expect(c.game.progress, .4);
        feed.send(2500);
        expect(c.game.progress, .5);
        await c.endSession();
      } finally {
        c.dispose();
      }
    });
  });

  test('차량 QR에서 앞자리 0을 포함한 코드를 보존한다', () {
    final credentials =
        PairingCredentials.fromQr('allo://pair?sid=$sid&code=$code');
    expect(credentials.sessionId, sid);
    expect(credentials.code, code);
  });

  test('다른 QR·경로 주입·중복 매개변수·잘못된 코드를 거부한다', () {
    for (final raw in [
      'https://example.com?sid=$sid&code=$code',
      'allo://pair?sid=../../sessions&code=$code',
      'allo://pair?sid=$sid&code=$code&code=123456',
      'allo://pair?sid=$sid&code=12345',
      'allo://pair?sid=$sid&code=１２３４５６',
      'allo://pair?sid=$sid&code=$code#other',
      'allo://pair/path?sid=$sid&code=$code',
      'allo://pair?sid=$sid',
      'allo://pair?sid=%FF&code=123456',
    ]) {
      expect(() => PairingCredentials.fromQr(raw),
          throwsA(isA<PairingException>()),
          reason: raw);
    }
  });

  test('서버 메타가 없거나 코드가 다르거나 24시간 만료되면 거부한다', () {
    final credentials = PairingCredentials.parseFields(sid, code);
    final now = DateTime(2026, 11, 4, 12);
    final valid = {
      'createdAt': now.millisecondsSinceEpoch - 1000,
      'pairCode': code
    };
    credentials.validateMeta(valid, now: now);
    for (final meta in <Map<String, dynamic>?>[
      null,
      {},
      {...valid, 'pairCode': '123456'},
      {
        ...valid,
        'createdAt':
            now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch
      },
    ]) {
      expect(() => credentials.validateMeta(meta, now: now),
          throwsA(isA<PairingException>()));
    }
  });

  testWidgets('연결 전 시작 차단·중복 연결 차단·서버 성공 후 저장 및 재연결', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final feed = _RecordingFeed()..gate = Completer<void>();
      final c = GameController(feed: feed, dex: DexStore());
      try {
        expect(c.canStart, isFalse);
        expect(await c.startIncubating(EggTier.small), isFalse);
        final pairing = c.pair(sid, pairCode: code);
        expect(c.busy, isTrue);
        expect(c.paired, isFalse);
        await c.pair(sid, pairCode: code);
        expect(feed.calls, 1);
        expect(await PairingStore().read(), isNull);
        feed.gate!.complete();
        await pairing;
        expect(c.canStart, isTrue);
        expect((await PairingStore().read())!.code, code);
      } finally {
        c.dispose();
      }
      final restoredFeed = _RecordingFeed();
      final restored = GameController(feed: restoredFeed, dex: DexStore());
      try {
        await restored.restorePairing();
        await restored.restorePairing();
        expect(restoredFeed.calls, 1);
        expect(restored.canStart, isTrue);
      } finally {
        restored.dispose();
      }
    });
  });

  testWidgets('입력 및 서버 연결 실패는 시작·세션 저장을 허용하지 않는다', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final feed = _RecordingFeed()..fail = true;
      final c = GameController(feed: feed, dex: DexStore());
      try {
        await c.pair('bad', pairCode: '1');
        expect(feed.calls, 0);
        await c.pair(sid, pairCode: code);
        expect(c.paired, isFalse);
        expect(c.canStart, isFalse);
        expect(c.busy, isFalse);
        expect(c.error, isNotNull);
        expect(await PairingStore().read(), isNull);
        feed.fail = false;
        await c.pair(sid, pairCode: code);
        expect(c.paired, isTrue);
      } finally {
        c.dispose();
      }
    });
  });

  testWidgets('손상된 로컬 연결 기록은 제거한다', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(
          {'pairing.session.v1': 'invalid json'});
      expect(await PairingStore().read(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('pairing.session.v1'), isFalse);
    });
  });
}

class _RecordingFeed implements VehicleFeed {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    calls++;
    if (fail) throw StateError('offline');
    await gate?.future;
  }

  @override
  Stream<VehicleState> watch() => const Stream.empty();
  @override
  Stream<Map<String, Object?>> events() => const Stream.empty();
  @override
  Future<void> publishGame(GameState state) async {}
  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {}
  @override
  Future<void> dispose() async {}
}
