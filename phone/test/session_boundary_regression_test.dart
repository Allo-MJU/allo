import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed, RoundStore, settle;
import 'session_resume_test.dart' show sessionA, sessionB;

class BoundaryFeed extends RoundFeed {
  final endedSessions = <String>{};
  final bySession = <String, List<GameState>>{};
  String? currentSession;

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    if (endedSessions.contains(sessionId)) throw const SessionEndedException();
    await super.pair(sessionId, pairCode: pairCode);
    currentSession = sessionId;
  }

  @override
  Future<void> publishGame(GameState state) async {
    bySession.putIfAbsent(currentSession!, () => []).add(state);
    await super.publishGame(state);
  }
}

class CheckpointFailingStore extends RoundStore {
  bool failCheckpoint = true;

  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    final round = progress.round;
    final game = round?['game'] as Map?;
    if (failCheckpoint &&
        game?['stage'] == 'hatched' &&
        round?['pendingEntry'] == null) {
      throw StateError('completed checkpoint unavailable');
    }
    await super.saveIncubationProgress(tier, progress);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('완료한 A 뒤 B 연결의 첫 발행은 이전 생물 없는 idle이다', () async {
    final feed = BoundaryFeed();
    final store = DexStore();
    var now = 0;
    final c = GameController(feed: feed, dex: store, monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.sample(eta: 600, distance: 1000);
    now = 300000;
    feed.sample(eta: 300, distance: 2000);
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(await store.all(), hasLength(1));
    feed.carEvents.add({'type': 'sessionEnd', 'by': 'car'});
    expect(await c.endSession(), isTrue);
    expect(c.sessionSaved, isTrue);

    await c.pair(sessionB, pairCode: '123456');
    await settle();
    expect(c.paired, isTrue);
    final published = feed.bySession[sessionB]!;
    expect(published, isNotEmpty);
    expect(published.first.stage, Stage.idle);
    expect(published.every((g) => g.speciesId == null), isTrue);
    expect(published.first.regionCollectionKnown, isTrue);
    expect(c.hatched, isNull);
    expect(await store.all(), hasLength(1));
    expect(
        (await store.incubationProgress(EggTier.small))
            .sessionDistances[sessionA],
        2000);
  });

  test('재실행에서 종료된 A 동행을 복원하지 않고 B의 새 알을 시작한다', () async {
    final feed = BoundaryFeed();
    final store = DexStore();
    var now = 0;
    final c = GameController(feed: feed, dex: store, monotonicMs: () => now);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.sample(eta: 600, distance: 1000);
    now = 300000;
    feed.sample(eta: 300, distance: 2000);
    await settle();
    expect(await store.all(), hasLength(1));
    expect(await c.setAppActive(false), isTrue);
    final previousEgg = c.eggId;
    c.dispose();

    final nextFeed = BoundaryFeed()..endedSessions.add(sessionA);
    var nextNow = 0;
    final next =
        GameController(feed: nextFeed, dex: store, monotonicMs: () => nextNow);
    addTearDown(next.dispose);
    await next.restorePairing();
    expect(next.paired, isFalse);
    expect(next.error, isNotNull);
    await next.pair(sessionB, pairCode: '123456');
    expect(await next.startIncubating(EggTier.small), isTrue);
    nextFeed.sample(eta: 600);
    expect(next.game.stage, Stage.incubating);
    expect(next.game.progress, 0);
    expect(next.game.speciesId, isNull);
    expect(next.eggId, isNot(previousEgg));
    nextNow = 60000;
    nextFeed.sample(eta: 540, distance: 1000);
    expect(next.game.progress, .2);
    expect(await store.all(), hasLength(1));
    expect(await next.endSession(), isTrue);
    final saved = await store.incubationProgress(EggTier.small);
    expect(saved.sessionDistances[sessionA], 2000);
    expect(saved.sessionDistances[sessionB], 1000);
  });

  test('같은 A에 다시 연결하면 저장한 동행을 첫 발행과 재시작에서 유지한다', () async {
    final feed = BoundaryFeed();
    var now = 0;
    final c =
        GameController(feed: feed, dex: DexStore(), monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: 600);
    now = 300000;
    feed.sample(eta: 300);
    await settle();
    final previousEgg = c.eggId;
    final species = c.game.speciesId;
    final before = feed.bySession[sessionA]!.length;
    await c.pair(sessionA, pairCode: '123456');
    await settle();
    expect(feed.bySession[sessionA]![before].stage, Stage.hatched);
    expect(c.game.speciesId, species);
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.sample(eta: 300);
    expect(c.game.stage, Stage.hatched);
    expect(c.eggId, previousEgg);
  });

  test('다른 B로 미부화 시간 진행과 돌봄 태그를 이어간다', () async {
    final feed = BoundaryFeed();
    var now = 0;
    final c =
        GameController(feed: feed, dex: DexStore(), monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: 600, distance: 1000, tags: ['coast']);
    c.care();
    now = 120000;
    feed.sample(eta: 480, distance: 2000, tags: ['coast']);
    final previousEgg = c.eggId;
    await c.pair(sessionB, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.sample(eta: 5400);
    expect(c.game.stage, Stage.incubating);
    expect(c.game.progress, .4);
    expect(c.game.hatchAtSec, 300);
    expect(c.eggId, previousEgg);
    expect(c.careCount, 1);
    expect(c.seenTags, contains('coast'));
    expect(await c.endSession(), isTrue);
    final saved = await c.dex.incubationProgress(EggTier.small);
    expect(saved.round!['sessionId'], sessionB);
    expect(saved.sessionDistances[sessionA], 2000);
    expect(saved.sessionDistances[sessionB], 0);
  });

  test('다른 세션의 pendingEntry는 저장 실패 중 보존하고 같은 결과를 재시도한다', () async {
    final store = RoundStore()..fail = true;
    final feed = BoundaryFeed();
    var now = 0;
    final c = GameController(feed: feed, dex: store, monotonicMs: () => now);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: 600, distance: 1000);
    now = 300000;
    feed.sample(eta: 300, distance: 2000);
    await settle();
    expect(await c.setAppActive(false), isTrue);
    final saved = await store.incubationProgress(EggTier.small);
    expect(saved.round!['pendingEntry'], isNotNull);
    final previousEgg = c.eggId;
    c.dispose();

    final nextFeed = BoundaryFeed()..endedSessions.add(sessionA);
    final next =
        GameController(feed: nextFeed, dex: store, monotonicMs: () => 0);
    addTearDown(next.dispose);
    await next.restorePairing();
    await next.pair(sessionB, pairCode: '123456');
    expect(await next.startIncubating(EggTier.small), isTrue);
    await settle();
    nextFeed.sample(eta: 5400, distance: 1000);
    expect(next.game.stage, Stage.hatched);
    expect(next.eggId, previousEgg);
    expect(await store.all(), isEmpty);
    expect(await next.endSession(), isFalse);
    expect(
        (await store.incubationProgress(EggTier.small)).round!['pendingEntry'],
        isNotNull);
    store.fail = false;
    expect(await next.endSession(), isTrue);
    expect(await next.endSession(), isTrue);
    final entries = await store.all();
    expect(entries, hasLength(1));
    expect(entries.single.toJson(), store.attempts.first.toJson());
    expect(
        (await store.incubationProgress(EggTier.small)).round!['pendingEntry'],
        isNull);
    final completed = await store.incubationProgress(EggTier.small);
    expect(completed.round!['sessionId'], sessionA);
    expect(completed.sessionDistances[sessionA], 2000);
    expect(completed.sessionDistances[sessionB], 1000);
    expect(await next.startIncubating(EggTier.small), isTrue);
    nextFeed.sample(eta: 600, distance: 1000);
    expect(next.game.stage, Stage.incubating);
    expect(next.game.progress, 0);
    expect(next.game.speciesId, isNull);
    expect(next.eggId, isNot(previousEgg));
    expect(await store.all(), hasLength(1));
  });

  test('도감만 저장된 pending A를 B 재실행과 C로 이동해도 원회차와 거리를 보존한다', () async {
    const sessionC = 'b0c260a8-e807-42e9-a119-26119837113d';
    final store = CheckpointFailingStore();
    final feed = BoundaryFeed();
    var now = 0;
    final first =
        GameController(feed: feed, dex: store, monotonicMs: () => now);
    await first.pair(sessionA, pairCode: '123456');
    await first.startIncubating(EggTier.small);
    feed.sample(eta: 600, distance: 1000);
    now = 300000;
    feed.sample(eta: 300, distance: 2000);
    await settle();
    final previousEgg = first.eggId;
    expect(await first.setAppActive(false), isTrue);
    first.dispose();

    final sessions = [sessionB, sessionB, sessionC];
    late GameController current;
    late BoundaryFeed currentFeed;
    for (var i = 0; i < sessions.length; i++) {
      currentFeed = BoundaryFeed();
      current =
          GameController(feed: currentFeed, dex: store, monotonicMs: () => 0);
      if (i == 1) {
        await current.restorePairing();
        expect(current.paired, isTrue);
      } else {
        await current.pair(sessions[i], pairCode: '123456');
      }
      expect(await current.startIncubating(EggTier.small), isTrue);
      await settle();
      currentFeed.sample(eta: 600, distance: 1000);
      expect(current.game.stage, Stage.hatched);
      expect(current.eggId, previousEgg);
      expect(await current.endSession(), isFalse);
      expect(await current.setAppActive(false), isTrue);
      final pending = await store.incubationProgress(EggTier.small);
      expect(pending.round!['sessionId'], sessionA);
      expect(pending.round!['pendingEntry'], isNotNull);
      expect(pending.sessionDistances[sessionA], 2000);
      expect(pending.sessionDistances[sessionB], 1000);
      expect(await store.all(), hasLength(1));
      if (i < sessions.length - 1) current.dispose();
    }
    addTearDown(current.dispose);
    expect(await current.setAppActive(true), isTrue);
    store.failCheckpoint = false;
    expect(await current.endSession(), isTrue);
    final completed = await store.incubationProgress(EggTier.small);
    expect(completed.round!['sessionId'], sessionA);
    expect(completed.sessionDistances[sessionA], 2000);
    expect(completed.sessionDistances[sessionB], 1000);
    expect(completed.sessionDistances[sessionC], 1000);
    expect((await store.all()).single.toJson(), store.attempts.first.toJson());
    final publishedBefore = currentFeed.bySession[sessionC]!.length;
    await current.pair(sessionC, pairCode: '123456');
    await settle();
    expect(currentFeed.bySession[sessionC]![publishedBefore].stage, Stage.idle);
    expect(await current.startIncubating(EggTier.small), isTrue);
    currentFeed.sample(eta: 600, distance: 1000);
    expect(current.game.stage, Stage.incubating);
    expect(current.game.progress, 0);
    expect(current.game.speciesId, isNull);
    expect(current.game.hatchAtSec, 300);
    expect(current.eggId, isNot(previousEgg));
  });

  test('B 복구에서 재시도 성공 후 lifecycle 저장과 재실행도 A 완료회차를 승계하지 않는다', () async {
    final store = RoundStore()..fail = true;
    final feed = BoundaryFeed();
    var now = 0;
    final first =
        GameController(feed: feed, dex: store, monotonicMs: () => now);
    await first.pair(sessionA, pairCode: '123456');
    await first.startIncubating(EggTier.small);
    feed.sample(eta: 600, distance: 1000);
    now = 300000;
    feed.sample(eta: 300, distance: 2000);
    await settle();
    expect(await first.setAppActive(false), isTrue);
    final previousEgg = first.eggId;
    first.dispose();
    final retryFeed = BoundaryFeed();
    final retry =
        GameController(feed: retryFeed, dex: store, monotonicMs: () => 0);
    await retry.pair(sessionB, pairCode: '123456');
    await retry.startIncubating(EggTier.small);
    await settle();
    retryFeed.sample(eta: 600, distance: 1000);
    expect(await retry.setAppActive(false), isTrue);
    retry.dispose();

    store.fail = false;
    final savedFeed = BoundaryFeed();
    final saved =
        GameController(feed: savedFeed, dex: store, monotonicMs: () => 0);
    await saved.restorePairing();
    expect(await saved.startIncubating(EggTier.small), isTrue);
    await settle();
    expect(await store.all(), hasLength(1));
    expect(await saved.setAppActive(false), isTrue);
    final completed = await store.incubationProgress(EggTier.small);
    expect(completed.round!['sessionId'], sessionA);
    expect(completed.round!['pendingEntry'], isNull);
    expect(completed.sessionDistances[sessionA], 2000);
    expect(completed.sessionDistances[sessionB], 1000);
    saved.dispose();

    final nextFeed = BoundaryFeed();
    final next =
        GameController(feed: nextFeed, dex: store, monotonicMs: () => 0);
    addTearDown(next.dispose);
    await next.restorePairing();
    expect(await next.startIncubating(EggTier.small), isTrue);
    nextFeed.sample(eta: 600, distance: 1000);
    expect(next.game.stage, Stage.incubating);
    expect(next.game.progress, 0);
    expect(next.game.hatchAtSec, 300);
    expect(next.eggId, isNot(previousEgg));
    expect(await store.all(), hasLength(1));
  });

  test('sessionId 없는 legacy 동행을 종료된 타 세션으로 단정하지 않는다', () async {
    final store = DexStore();
    final feed = BoundaryFeed();
    var now = 0;
    final c = GameController(feed: feed, dex: store, monotonicMs: () => now);
    await c.pair(sessionA, pairCode: '123456');
    await c.startIncubating(EggTier.small);
    feed.sample(eta: 600);
    now = 300000;
    feed.sample(eta: 300);
    await settle();
    expect(await c.setAppActive(false), isTrue);
    final previousEgg = c.eggId;
    final saved = await store.incubationProgress(EggTier.small);
    await store.saveIncubationProgress(
        EggTier.small,
        IncubationProgress(
            carriedM: saved.carriedM,
            sessionDistances: saved.sessionDistances,
            round: Map.of(saved.round!)..remove('sessionId')));
    c.dispose();
    final nextFeed = BoundaryFeed();
    final next =
        GameController(feed: nextFeed, dex: store, monotonicMs: () => 0);
    addTearDown(next.dispose);
    await next.pair(sessionB, pairCode: '123456');
    expect(await next.startIncubating(EggTier.small), isTrue);
    nextFeed.sample(eta: 600);
    expect(next.game.stage, Stage.hatched);
    expect(next.eggId, previousEgg);
    expect(await store.all(), hasLength(1));
  });
}
