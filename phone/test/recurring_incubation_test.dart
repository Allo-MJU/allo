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
import 'package:allo_phone/feed/fake_feed.dart';
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

class FailingLedger extends DexStore {
  bool fail = true;
  @override
  Future<void> saveTripEggLedger(bool demo, TripEggLedger ledger) async {
    if (fail) throw StateError('failed to save claim');
    await super.saveTripEggLedger(demo, ledger);
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

  test(
      'pair automatically grants one small affinity egg, carry consumes B even after discard',
      () async {
    final store = DexStore();
    final firstFeed = RoundFeed();
    final first = GameController(feed: firstFeed, dex: store);
    await first.pair(sessionA, pairCode: '123456');
    final id = first.eggId;
    expect(id, isNotNull);
    expect(first.game.eggTier, EggTier.small);
    expect(first.usesAffinity, isTrue);
    firstFeed.sample();
    await first.petEgg();
    final score = first.affinityRound!.score;
    await first.pair(sessionB, pairCode: '123456');
    expect(first.eggId, id);
    expect(first.affinityRound!.score, score);
    firstFeed.sample();
    await first.discardEgg();
    await first.pair(sessionA, pairCode: '000111');
    expect(first.eggId, id);
    expect(first.game.stage, Stage.failed);
    await first.endSession();
    first.dispose();
    final again = GameController(feed: RoundFeed(), dex: store);
    addTearDown(again.dispose);
    await again.restorePairing();
    expect(again.game.stage, Stage.failed);
    await again.pair(sessionB, pairCode: '111222');
    await again.startIncubating(EggTier.large);
    expect(again.game.stage, Stage.failed);
    expect(again.eggId, id);
    expect(again.game.eggTier, EggTier.small);
  });
  test('a legacy demo checkpoint survives real pairing without sharing its egg',
      () async {
    final store = DexStore();
    final template = GameController(feed: RoundFeed(), dex: store);
    await template.pair(sessionA, pairCode: '123456');
    await template.endSession();
    final checkpoint = (await store.incubationProgress(EggTier.small)).round!;
    template.dispose();
    SharedPreferences.setMockInitialValues({});
    await store.saveIncubationProgress(
        EggTier.small,
        IncubationProgress(
            carriedM: 1200, round: Map.of(checkpoint)..['sessionId'] = null));
    final real = GameController(feed: RoundFeed(), dex: store);
    addTearDown(real.dispose);
    await real.pair(sessionA, pairCode: '123456');
    expect(real.eggId, isNot(checkpoint['eggId']));
    await real.endSession();
    final demo = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: store);
    addTearDown(demo.dispose);
    expect(await demo.ensureTripEgg(), isTrue);
    expect(demo.eggId, checkpoint['eggId']);
  });

  test('migration records terminal A and keeps B mid-tier progress for B',
      () async {
    final store = DexStore();
    final template = GameController(feed: RoundFeed(), dex: store);
    await template.pair(sessionA, pairCode: '123456');
    await template.endSession();
    final round = (await store.incubationProgress(EggTier.small)).round!;
    template.dispose();
    SharedPreferences.setMockInitialValues({});
    await store.saveIncubationProgress(
        EggTier.small,
        IncubationProgress(
            round: Map.of(round)
              ..['game'] = {...round['game'] as Map, 'stage': 'failed'}));
    await store.saveIncubationProgress(
        EggTier.mid,
        IncubationProgress(
            carriedM: 1250,
            round: Map.of(round)
              ..['sessionId'] = sessionB
              ..['eggId'] = 'legacy-B'));
    final feed = RoundFeed();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '111222');
    expect(c.eggId, isNot('legacy-B'));
    expect(c.game.stage, isNot(Stage.incubating));
    await c.pair(sessionB, pairCode: '222333');
    expect(c.eggId, 'legacy-B');
    expect(c.game.eggTier, EggTier.mid);
  });

  test(
      'failed grant is invisible and concurrent retries restore one committed ID',
      () async {
    final store = FailingLedger();
    final feed = RoundFeed();
    final c = GameController(feed: feed, dex: store);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(c.eggId, isNull);
    expect(feed.watches, 0);
    store.fail = false;
    final calls = [c.ensureTripEgg(), c.ensureTripEgg(tier: EggTier.large)];
    expect(await Future.wait(calls), [true, true]);
    final id = c.eggId;
    expect(id, isNotNull);
    expect(feed.watches, 1);
    final next = GameController(feed: RoundFeed(), dex: store);
    addTearDown(next.dispose);
    await next.restorePairing();
    expect(next.eggId, id);
  });

  test(
      'a pending legacy A result settles before adopting unfinished B on trip C',
      () async {
    final store = RoundStore()..fail = true;
    final feed = RoundFeed();
    final a = GameController(feed: feed, dex: store, monotonicMs: () => 0);
    await a.pair(sessionA, pairCode: '123456');
    await a.startIncubating(EggTier.small);
    feed.sample(eta: null, distance: 1000);
    await a.setAppActive(false);
    final progress = await store.incubationProgress(EggTier.small);
    await a.setAppActive(true);
    feed.sample(eta: null, distance: 1000);
    feed.sample(eta: null, distance: 5000);
    await settle();
    final pending = await store.incubationProgress(EggTier.small);
    expect(pending.round!['pendingEntry'], isNotNull);
    a.dispose();
    SharedPreferences.setMockInitialValues({});
    await store.saveIncubationProgress(EggTier.small, pending);
    await store.saveIncubationProgress(
        EggTier.mid,
        IncubationProgress(
            carriedM: progress.carriedM,
            round: Map.of(progress.round!)
              ..['eggId'] = 'unfinished'
              ..['sessionId'] = sessionB));
    store.fail = false;
    final c = GameController(feed: RoundFeed(), dex: store);
    addTearDown(c.dispose);
    await c.pair('b0c260a8-e807-42e9-a119-26119837113d', pairCode: '111222');
    expect(c.eggId, 'unfinished');
    expect(c.game.eggTier, EggTier.mid);
    expect((await store.all()).single.sourceEggId, pending.round!['eggId']);
  });
  test('90분 이동 중 40분 부화 후 70분과 80분에 새 알을 주지 않는다', () async {
    await start();
    final id = c.eggId;
    at(0);
    at(40);
    await settle();
    expect(c.game.stage, Stage.hatched);
    at(70, eta: 1200);
    at(80, eta: 600);
    await settle();
    expect(c.eggId, id);
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    expect((await c.dex.all()).single.sourceEggId, id);
    expect(feed.watches, 1);
  });

  test('ETA 수정이나 소실에도 최초 계산을 유지하며 새 여행은 거리 모드가 가능하다', () async {
    await start();
    at(0, eta: 660);
    at(2, eta: null);
    expect(c.game.hatchAtSec, 300);
    expect(c.game.progress, .4);
    at(5, eta: 100);
    await settle();
    expect(c.game.stage, Stage.hatched);
    await c.pair(sessionB, pairCode: '111222');
    await c.startIncubating(EggTier.mid);
    at(6, eta: null);
    feed.sample(eta: 5400, distance: 1000);
    expect(c.game.hatchAtSec, isNull);
    expect(c.game.hatchAtM, 5000);
    expect(c.game.progress, .2);
  });

  test('2분 미만은 계획만 보류하고 동일한 알로 부화한다', () async {
    await start();
    final id = c.eggId;
    at(0, eta: 119);
    expect(c.game.stage, Stage.idle);
    expect(c.game.hatchAtM, isNull);
    expect(c.game.hatchAtSec, isNull);
    expect(c.tripEggAwaitingPlan, isTrue);
    expect(c.eggId, id);
    at(1, eta: 5400);
    expect(c.tripEggAwaitingPlan, isFalse);
    at(41);
    await settle();
    at(71, eta: 119);
    at(72, eta: 600);
    expect(c.game.stage, Stage.hatched);
    expect(c.eggId, id);
    expect(feed.hatchEvents, 1);
  });

  test('늦은 관측은 한 건만 부화하고 이후 중복 신호는 도감을 변경하지 않는다', () async {
    await start();
    at(0, eta: 18000, harsh: 10, tags: ['rain']);
    c.care();
    at(250, eta: 3000, harsh: 10);
    await settle();
    feed.sample(eta: 600, harsh: 10, duplicate: true);
    await settle();
    expect(feed.hatchEvents, 1);
    expect(c.game.stage, Stage.hatched);
    expect(c.game.hatchAtSec, 2400);
    expect(c.careCount, 1);
    expect((await c.dex.all()).single.envTags, contains('rain'));
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
  test('동행 복원 후 남은 시간을 진행해도 같은 동행을 유지', () async {
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
    expect(next.game.stage, Stage.hatched);
    expect(next.eggId, c.eggId);
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

  testWidgets('부화한 친구는 긴 주행에도 동행 화면에 남는다', (tester) async {
    await tester.runAsync(() => PairingStore()
        .save(PairingCredentials.parseFields(sessionA, '123456')));
    final uiFeed = RoundFeed();
    var uiClock = 0;
    // Exercise the legacy distance-only tour with a previously saved egg.
    await tester.runAsync(() async {
      final priorFeed = RoundFeed();
      final prior = GameController(
          feed: priorFeed, dex: DexStore(), monotonicMs: () => 0);
      await prior.pair(sessionA, pairCode: '123456');
      await prior.startIncubating(EggTier.small);
      priorFeed.sample(eta: 18000);
      await prior.endSession();
      prior.dispose();
    });
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
    await tester.scrollUntilVisible(find.text('차 안으로 가기'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('차 안으로 가기'));
    await until('알 품기');
    uiFeed.sample(eta: 18000);
    uiClock = 40 * 60000;
    uiFeed.sample(eta: 15600);
    await tester.pumpAndSettle();
    await until('같이 가자');
    await tester.runAsync(settle);
    await tester.tap(find.text('같이 가자'));
    await tester.pumpAndSettle();
    expect(find.text('먹이'), findsOneWidget);
    uiClock = 140 * 60000;
    uiFeed.sample(eta: 1200);
    await tester.pumpAndSettle();
    expect(find.text('먹이'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
