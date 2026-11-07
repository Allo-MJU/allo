import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/app.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:flutter/material.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_end_test.dart' show EndFeed;
import 'session_resume_test.dart' show sessionA, sessionB;

class RoundFeed extends EndFeed {
  int watches = 0, hatchEvents = 0, stamp = 0;
  @override
  Stream<VehicleState> watch() {
    watches++;
    return super.watch();
  }

  void sample(
      {int? eta = 5400,
      double distance = 0,
      int harsh = 0,
      List<String> tags = const [],
      bool duplicate = false}) {
    latest = VehicleState.fromJson({
      'ts': duplicate ? stamp : ++stamp,
      'gear': 'D',
      'etaSec': eta,
      'distanceM': distance,
      'harshBrake': harsh,
      'envTags': tags,
      'capabilities': ['odometer']
    });
    signals.add(latest!);
  }

  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {
    if (type == 'hatched') hatchEvents++;
  }
}

class RoundStore extends DexStore {
  bool fail = false;
  final attempts = <DexEntry>[];
  @override
  Future<void> add(DexEntry entry) async {
    attempts.add(entry);
    if (fail) throw StateError('disk full');
    await super.add(entry);
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  var now = 0;
  late RoundFeed feed;
  late GameController c;
  Future<void> start({DexStore? store}) async {
    now = 0;
    feed = RoundFeed();
    c = GameController(
        feed: feed, dex: store ?? DexStore(), monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
  }

  void at(int minutes,
      {int? eta = 5400, int harsh = 0, List<String> tags = const []}) {
    now = minutes * 60000;
    feed.sample(eta: eta, harsh: harsh, tags: tags);
  }

  test('90분 40분 부화 70분 새 알 최신 ETA로 80분 부화 watch는 1회', () async {
    await start();
    at(0);
    at(40);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    at(70, eta: 1200);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.hatchAtSec, 600);
    expect(c.game.progress, 0);
    at(80, eta: 600);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 2);
    expect((await c.dex.all()).length, 2);
    expect(feed.watches, 1);
  });
  test('80분 최종 회차와 81분 반복 경계', () async {
    await start();
    at(0, eta: 4800);
    at(40);
    await settle();
    at(80, eta: 600);
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    await c.endSession();
    await c.startIncubating(EggTier.mid);
    at(81, eta: 4860);
    at(121);
    await settle();
    at(151, eta: 660);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.hatchAtSec, 300);
  });
  test('ETA 수정 소실에도 고정 거리 모드도 중간 전환하지 않는다', () async {
    await start();
    at(0, eta: 660);
    at(2, eta: null);
    expect(c.game.hatchAtSec, 300);
    expect(c.game.progress, .4);
    at(5, eta: 100);
    expect(c.game.stage, Stage.hatched);
    await c.endSession();
    await c.startIncubating(EggTier.mid);
    at(6, eta: null);
    feed.sample(eta: 5400, distance: 5000);
    expect(c.game.hatchAtSec, isNull);
    expect(c.game.hatchAtM, 25000);
    expect(c.game.progress, .2);
  });
  test('2분 미만 첫 알 idle 다음 알은 기존 동행 유지', () async {
    await start();
    at(0, eta: 119);
    expect(c.game.stage, Stage.idle);
    expect(c.game.hatchAtM, isNull);
    expect(c.game.hatchAtSec, isNull);
    at(1, eta: 5400);
    at(41);
    await settle();
    at(71, eta: 119);
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    at(72, eta: 600);
    expect(c.game.stage, Stage.incubating);
  });
  test('새 알 돌봄 태그 급제동 기준 초기화 중복 결과 방지', () async {
    await start();
    at(0, harsh: 10, tags: ['rain']);
    c.care();
    at(40, harsh: 10);
    await settle();
    at(70, eta: 1200, harsh: 10);
    expect(c.careCount, 0);
    expect(c.seenTags, isNot(contains('rain')));
    at(80, eta: 600, harsh: 10);
    await settle();
    feed.sample(eta: 600, harsh: 10, duplicate: true);
    await settle();
    expect(feed.hatchEvents, 2);
    expect((await c.dex.all()).last.tier, 3);
  });
  test('늦은 관측은 과거 여러 알을 소급 생성하지 않는다', () async {
    await start();
    at(0, eta: 18000);
    at(250, eta: 3000);
    await settle();
    expect(feed.hatchEvents, 1);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.progress, 0);
    expect(c.game.hatchAtSec, 1500);
    expect((await c.dex.all()).length, 1);
  });
  test('저장 실패는 다음 알 차단 재시도 동일 DexEntry 사용', () async {
    final store = RoundStore()..fail = true;
    await start(store: store);
    at(0);
    at(40);
    await settle();
    at(70, eta: 1200);
    at(80, eta: 600);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    store.fail = false;
    expect(await c.endSession(), isTrue);
    expect(store.attempts.length, 2);
    expect(identical(store.attempts[0], store.attempts[1]), isTrue);
    expect((await store.all()).length, 1);
  });
  test('pause와 재실행은 중단 제외 같은 알 돌봄 복원', () async {
    await start();
    at(0);
    at(10);
    c.care();
    expect(await c.setAppActive(false), isTrue);
    now = 100 * 60000;
    expect(await c.setAppActive(true), isTrue);
    at(110);
    expect(c.game.progress, .5);
    expect(await c.setAppActive(false), isTrue);
    final nextFeed = RoundFeed();
    var nextNow = 90000000;
    final next = GameController(
        feed: nextFeed, dex: DexStore(), monotonicMs: () => nextNow);
    addTearDown(next.dispose);
    await next.pair(sessionA, pairCode: '123456');
    await next.startIncubating(EggTier.small);
    nextFeed.sample(eta: null);
    expect(next.game.progress, .5);
    expect(next.careCount, 1);
    nextNow += 20 * 60000;
    nextFeed.sample(eta: null);
    expect(next.game.stage, Stage.hatched);
    await next.endSession();
  });
  test('동행 복원 후 남은 시간만 진행하여 다음 알 지급', () async {
    await start();
    at(0);
    at(40);
    await settle();
    at(50);
    expect(await c.setAppActive(false), isTrue);
    final nextFeed = RoundFeed();
    var clock = 0;
    final next = GameController(
        feed: nextFeed, dex: DexStore(), monotonicMs: () => clock);
    addTearDown(next.dispose);
    await next.pair(sessionA, pairCode: '123456');
    await next.startIncubating(EggTier.small);
    nextFeed.sample(eta: 2400);
    expect(next.game.stage, Stage.hatched);
    expect(next.hatched, isNotNull);
    clock = 20 * 60000;
    nextFeed.sample(eta: 1200);
    expect(next.game.stage, Stage.incubating);
    expect(nextFeed.watches, 1);
  });
  test('다음 알 시각 원격 종료 우선', () async {
    await start();
    at(0);
    at(40);
    await settle();
    now = 70 * 60000;
    feed.latest = feed.latest!.copyWith(etaSec: 1200);
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'car'});
    expect(await c.endSession(), isTrue);
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    expect(c.sessionSaved, isTrue);
  });
  test('같은 알을 다른 차량 세션에서 이어도 이전 급제동 평가는 보존한다', () async {
    await start();
    at(0, eta: null);
    feed.sample(eta: null, distance: 2000, harsh: 8);
    await c.endSession();
    await c.pair(sessionB, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: null, distance: 0);
    feed.sample(eta: null, distance: 3000);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(c.game.tier, 1);
  });

  test('최종 종료된 시간 모드 동행은 새 주행의 첫 알을 막지 않는다', () async {
    await start();
    at(0, eta: 600);
    at(5, eta: 300);
    await settle();
    expect(c.game.stage, Stage.hatched);
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'car'});
    expect(await c.endSession(), isTrue);
    await c.pair(sessionB, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    at(6, eta: 600);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.progress, 0);
    expect(feed.hatchEvents, 1);
  });

  testWidgets('hatching와 companion 양쪽에서 다음 알 화면으로 돌아간다', (tester) async {
    await tester.runAsync(() => PairingStore()
        .save(PairingCredentials.parseFields(sessionA, '123456')));
    final uiFeed = RoundFeed();
    var uiClock = 0;
    await tester.pumpWidget(AlloApp(feed: uiFeed, monotonicMs: () => uiClock));
    Future<void> until(String text) async {
      for (var i = 0; i < 60 && find.text(text).evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(find.text(text), findsOneWidget);
    }

    await until('차량과 연결됐어요');
    await tester.tap(find.text('알 품기 시작'));
    await until('알 품기');
    uiFeed.sample(eta: 18000);
    uiClock = 40 * 60000;
    uiFeed.sample(eta: 15600);
    await tester.pumpAndSettle();
    await until('친구 만나기');
    await tester.runAsync(settle);
    uiClock = 70 * 60000;
    uiFeed.sample(eta: 13800);
    await until('알 품기');
    uiClock = 110 * 60000;
    uiFeed.sample(eta: 11400);
    await tester.pumpAndSettle();
    await until('친구 만나기');
    await tester.pumpAndSettle();
    await tester.tap(find.text('친구 만나기'));
    await tester.pumpAndSettle();
    expect(find.text('먹이'), findsOneWidget);
    uiClock = 140 * 60000;
    uiFeed.sample(eta: 1200);
    await until('알 품기');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
