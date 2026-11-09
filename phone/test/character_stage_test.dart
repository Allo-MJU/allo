import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/widgets/character_stage.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GameController controller() => GameController(
      feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore())
    ..game = const GameState(
        ts: 1, eggTier: EggTier.small, stage: Stage.hatched, progress: 1)
    ..vehicle = VehicleState.fromJson({'ts': 1, 'gear': 'D', 'speedKph': 40})
    ..hatched = Species.fromJson({
      'id': 'test',
      'nameKo': '친구',
      'nameEn': 'Friend',
      'attribute': 'normal',
      'tier': 1
    });
  final target = find.byKey(const ValueKey('character-touch-target'));
  Widget host(WidgetTester tester, GameController c, {bool reduce = false}) =>
      MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(
              body: ListView(children: [
                CharacterStage(
                    controller: c,
                    nowMs: () =>
                        tester.binding.clock.now().millisecondsSinceEpoch),
                const SizedBox(height: 700)
              ]),
            )),
      );
  Future<void> finish(WidgetTester tester, GameController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump();
  }

  testWidgets('터치 반응은 유한하게 끝나고 게임 상태를 변경하지 않는다', (tester) async {
    final c = controller();
    final game = c.game.toJson();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
    expect(find.text('만나서 반가워!'), findsOneWidget);
    expect(find.byIcon(Icons.sentiment_very_satisfied), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('만나서 반가워!'), findsNothing);
    expect(c.game.toJson(), game);
    await finish(tester, c);
  });

  testWidgets('드래그는 창 안에 제한되고 놓으면 원위치로 돌아온다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    final origin = tester.getCenter(target);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(30, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(1000, -1000));
    await tester.pump();
    final rect = tester.getRect(target);
    final window = tester.getRect(find.byType(WindowView));
    expect(rect.left, greaterThanOrEqualTo(window.left));
    expect(rect.right, lessThanOrEqualTo(window.right));
    expect(rect.top, greaterThanOrEqualTo(window.top));
    expect(tester.getCenter(target), isNot(origin));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(target), origin);
    await finish(tester, c);
  });

  testWidgets('급제동은 드래그를 취소하고 낮은 우선 터치를 막는다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    final origin = tester.getCenter(target);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(30, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(40, -20));
    await tester.pump();
    c.vehicle = c.vehicle!.copyWith(ts: 2, harshBrake: 1);
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('앗, 깜짝 놀랐어!'), findsOneWidget);
    expect(find.byKey(const ValueKey('character-attachment-seat')),
        findsOneWidget);
    expect(tester.getCenter(target).dx, greaterThan(origin.dx));
    await gesture.up();
    await tester.tap(target);
    await tester.pump();
    expect(find.text('앗, 깜짝 놀랐어!'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('비가 시작되면 창에 붙고 만료되면 원위치로 돌아온다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    final origin = tester.getCenter(target);
    c.vehicle = c.vehicle!.copyWith(ts: 2, wiperLevel: 2);
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-attachment-window')),
        findsOneWidget);
    expect(tester.getCenter(target).dx, lessThan(origin.dx));
    expect(tester.getCenter(target).dy, lessThan(origin.dy));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.getCenter(target), origin);
    expect(find.byKey(const ValueKey('character-attachment-window')),
        findsNothing);
    await finish(tester, c);
  });

  testWidgets('창문 붙기 도중 드래그가 현재 자리에서 이어진다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    c.vehicle = c.vehicle!.copyWith(ts: 2, wiperLevel: 2);
    c.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final atWindow = tester.getCenter(target);
    final gesture = await tester.startGesture(atWindow);
    await gesture.moveBy(const Offset(40, 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('character-attachment-window')),
        findsNothing);
    expect((tester.getCenter(target) - atWindow).distance, lessThan(45));
    await gesture.up();
    await tester.pumpAndSettle();
    await finish(tester, c);
  });

  testWidgets('모션 감소에서도 창문과 의자 부착은 표시되고 급변이 우선한다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c, reduce: true));
    await tester.pumpAndSettle();
    c.vehicle = c.vehicle!.copyWith(ts: 2, wiperLevel: 2);
    c.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('character-attachment-window')),
        findsOneWidget);
    c.vehicle = c.vehicle!.copyWith(ts: 3, harshSteer: 1);
    c.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('character-attachment-seat')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('character-attachment-window')),
        findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('character-attachment-seat')), findsNothing);
    await finish(tester, c);
  });

  testWidgets('먹이·놀이·창밖 이벤트가 캐릭터 반응으로 이어진다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    c.feedCompanion();
    await tester.pump();
    expect(find.textContaining('맛있게 먹었어요'), findsOneWidget);
    c.playWithCompanion();
    await tester.pump();
    expect(find.textContaining('신나게 뛰어요'), findsOneWidget);
    c.lookOut();
    await tester.pump();
    expect(find.text('창밖에 뭐가 있을까?'), findsOneWidget);
    expect(c.feedCount, 1);
    expect(c.playCount, 1);
    await finish(tester, c);
  });

  testWidgets('모션 감소는 터치 피드백을 유지하되 자동 흔들림은 없다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c, reduce: true));
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
    expect(find.text('만나서 반가워!'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester, c);
  });

  testWidgets('앱 중단 시 반응을 지우고 복귀 때 누적 급변을 재생하지 않는다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    c.vehicle = c.vehicle!.copyWith(ts: 0, harshBrake: 0);
    c.notifyListeners();
    await tester.pump();
    c.vehicle = c.vehicle!.copyWith(ts: 2, harshBrake: 4);
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('만나서 반가워!'), findsNothing);
    expect(find.text('앗, 깜짝 놀랐어!'), findsNothing);
    c.vehicle = c.vehicle!.copyWith(ts: 3, harshBrake: 5);
    c.notifyListeners();
    await tester.pump();
    expect(find.text('앗, 깜짝 놀랐어!'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('동행 단계가 끝나면 반응과 입력을 차단한다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
    c.game = c.game.copyWith(stage: Stage.incubating);
    c.notifyListeners();
    await tester.pump();
    await tester.tap(target);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('캐릭터 반응을 쉬고 있어요.'), findsOneWidget);
    expect(find.text('만나서 반가워!'), findsNothing);
    await finish(tester, c);
  });

  testWidgets('캐릭터 밖의 세로 드래그는 부모 화면을 스크롤한다', (tester) async {
    final c = controller();
    await tester.pumpWidget(host(tester, c));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    await tester.dragFrom(const Offset(20, 400), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    await finish(tester, c);
  });
}
