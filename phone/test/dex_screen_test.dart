import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/dex_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_end_test.dart' show EndFeed;
import 'session_resume_test.dart' show sessionA;
import 'fishing_feed_integration_test.dart' show MemoryFishingStore;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<GameController> openDex(WidgetTester tester, DexStore store) async {
    await tester
        .runAsync(() => rootBundle.loadString('assets/data/species.json'));
    final controller = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: store);
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await tester
          .pumpWidget(MaterialApp(home: DexScreen(controller: controller)));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('빈 도감은 12종을 포함하고 잠긴 칸에서 획득 힌트를 보여준다', (tester) async {
    await openDex(tester, _MemoryDex([]));
    expect(find.text('만난 친구 0 / 12'), findsOneWidget);
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(grid.delegate.estimatedChildCount, 12);
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('dex-road_sprout'))) + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('어디서든 처음 만나는 친구'), findsOneWidget);
    expect(find.text('아직 만나지 못한 친구'), findsOneWidget);
    expect(find.text('Road Sprout'), findsNothing);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dex-sea_mist')), 250);
    await tester.tap(find.byKey(const ValueKey('dex-sea_mist')));
    await tester.pumpAndSettle();
    expect(find.text('비 오는 바닷가에서만'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('중복 획득은 한 칸으로 모으고 저장된 상세와 미확정 지역을 표시한다', (tester) async {
    final store = _MemoryDex([
      DexEntry(
          speciesId: 'road_sprout',
          obtainedAt: DateTime(2026, 11, 3),
          envTags: const [],
          regionTag: null,
          tier: 1),
      DexEntry(
          speciesId: 'road_sprout',
          obtainedAt: DateTime(2026, 11, 4),
          envTags: const ['rain', 'highway'],
          regionTag: 'coast',
          tier: 1),
    ]);
    await openDex(tester, store);
    expect(find.text('만난 친구 1 / 12'), findsOneWidget);
    expect(find.text('2번 만남'), findsOneWidget);
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('dex-road_sprout'))) + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Road Sprout'), findsOneWidget);
    expect(find.text('속성: 일반'), findsOneWidget);
    expect(find.text('등급 1'), findsNWidgets(2));
    expect(find.text('획득 날짜: 2026.11.04'), findsOneWidget);
    expect(find.text('획득 날짜: 2026.11.03'), findsOneWidget);
    expect(find.text('환경: 기록 없음'), findsOneWidget);
    expect(find.text('환경: 비 · 고속도로'), findsOneWidget);
    expect(find.text('지역: 미확정'), findsOneWidget);
    expect(find.text('지역: 바닷가'), findsOneWidget);
    expect(store.entries.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 가로 화면과 큰 글씨에서도 상세와 선택 버튼을 스크롤한다', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openDex(
        tester,
        _MemoryDex([
          DexEntry(
              speciesId: 'road_sprout',
              obtainedAt: DateTime(2026, 11, 12),
              envTags: const [],
              regionTag: null,
              tier: 2)
        ]));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dex-road_sprout')), 150);
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('dex-road_sprout'))) + const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('이 친구와 차량에서 함께하기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('등급 2'), findsOneWidget);
    expect(find.text('날씨: 기록 없음'), findsOneWidget);
  });

  testWidgets('도감 선택 저장 실패 후 재시도하면 선택 표시와 동행 상태를 갱신한다', (tester) async {
    final feed = EndFeed();
    final fishing = MemoryFishingStore();
    final record = DexEntry(
        speciesId: 'puddle_pip',
        obtainedAt: DateTime(2026, 11, 12),
        envTags: const ['rain'],
        regionTag: 'coast',
        tier: 2);
    final c = GameController(
        feed: feed, dex: _MemoryDex([record]), fishingStore: fishing);
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await c.fishing.attach(sessionA);
      c.paired = true;
      await tester.pumpWidget(MaterialApp(home: DexScreen(controller: c)));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('dex-puddle_pip')));
    await tester.tap(find.byKey(const ValueKey('dex-puddle_pip')));
    await tester.pumpAndSettle();
    fishing.failWrite = true;
    await tester.ensureVisible(find.text('이 친구와 차량에서 함께하기'));
    await tester.runAsync(() async {
      await tester.tap(find.text('이 친구와 차량에서 함께하기'));
      await Future<void>.delayed(Duration.zero);
      await c.fishing.settled;
    });
    await tester.pumpAndSettle();
    expect(c.fishing.isSelected(record), isFalse);
    expect(c.fishing.hasPendingWrite, isTrue, reason: 'error=${c.error}, paired=${c.paired}, busy=${c.busy}, initialized=${c.fishing.initialized}');
    expect(find.text('차량 동행으로 선택됨'), findsNothing);
    fishing.failWrite = false;
    // Retry must remain available even when this failed record was never selected.
    await tester.ensureVisible(find.text('저장 다시 확인'));
    await tester.runAsync(() async {
      await tester.tap(find.text('저장 다시 확인'));
      await c.fishing.settled;
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(c.fishing.isSelected(record), isTrue);
    expect(find.text('차량 동행으로 선택됨'), findsOneWidget);
    expect(
        c.game.toJson()['companion']['speciesId'], 'puddle_pip');
    expect(tester.takeException(), isNull);
  });

  testWidgets('읽기 실패 후 재시도로 도감을 다시 불러온다', (tester) async {
    final store = _MemoryDex([])..failNext = true;
    await openDex(tester, store);
    expect(find.text('도감을 불러오지 못했어요.'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('만난 친구 0 / 12'), findsOneWidget);
    expect(store.reads, 2);
    expect(tester.takeException(), isNull);
  });
}

class _MemoryDex extends DexStore {
  _MemoryDex(this.entries);
  final List<DexEntry> entries;
  bool failNext = false;
  int reads = 0;

  @override
  Future<List<DexEntry>> all() async {
    reads++;
    if (failNext) {
      failNext = false;
      throw StateError('storage unavailable');
    }
    return entries;
  }
}
