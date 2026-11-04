import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/dex_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<GameController> openDex(WidgetTester tester, DexStore store) async {
    await tester.runAsync(() => rootBundle.loadString('assets/data/species.json'));
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
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.childrenDelegate.estimatedChildCount, 12);
    await tester.tap(find.byKey(const ValueKey('dex-road_sprout')));
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
    await tester.tap(find.byKey(const ValueKey('dex-road_sprout')));
    await tester.pumpAndSettle();
    expect(find.text('Road Sprout'), findsOneWidget);
    expect(find.text('속성: 일반 · 등급 1'), findsOneWidget);
    expect(find.text('획득 날짜: 2026.11.04'), findsOneWidget);
    expect(find.text('획득 날짜: 2026.11.03'), findsOneWidget);
    expect(find.text('환경: 기록 없음'), findsOneWidget);
    expect(find.text('환경: 비 · 고속도로'), findsOneWidget);
    expect(find.text('지역: 미확정'), findsOneWidget);
    expect(find.text('지역: 바닷가'), findsOneWidget);
    expect(store.entries.length, 2);
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
