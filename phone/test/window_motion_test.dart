import 'dart:math' as math;
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:allo_phone/widgets/species_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final friend = Species.fromJson({
    'id': 'friend',
    'nameKo': '친구',
    'nameEn': 'Friend',
    'attribute': 'normal',
    'tier': 1
  });
  Widget host(
          {bool moving = true,
          bool reduce = false,
          bool tickers = true,
          bool animate = true,
          int ts = 1,
          int brake = 0,
          List<Species> friends = const []}) =>
      MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: TickerMode(
                  enabled: tickers,
                  child: Scaffold(
                      body: WindowView(
                    random: math.Random(7),
                    animatePassersby: animate,
                    vehicle: VehicleState.fromJson({
                      'ts': ts,
                      'harshBrake': brake,
                      'gear': moving ? 'D' : 'P',
                      'speedKph': moving ? 60 : 0,
                      'envTags': ['coast']
                    }),
                    friends: friends,
                  )))));
  Future<void> spawn(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  }

  testWidgets('기본 경로는 2초 대기 후 한 묶음만 재생하고 6초 쉰다', (tester) async {
    await tester.pumpWidget(host(friends: [friend]));
    await tester.pump(const Duration(milliseconds: 1999));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.byType(SpeciesArt), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(SpeciesArt), findsNothing);
    await tester.pump(const Duration(milliseconds: 5999));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final moving in [true, false]) {
    testWidgets('대기 중 급제동은 즉시 600ms만 반응한다 moving=$moving', (tester) async {
      await tester.pumpWidget(host(moving: moving, friends: [friend]));
      await tester.pump(const Duration(milliseconds: 500));
      await tester
          .pumpWidget(host(moving: moving, ts: 2, brake: 1, friends: [friend]));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SpeciesArt), findsNothing,
          reason: '급변 재생 도중 이전 spawn 예약이 시간을 8초 건너뛰면 안 된다');
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(milliseconds: 5999));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(tester.hasRunningAnimations, moving);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final mode in ['reduce', 'ticker', 'paused']) {
    testWidgets('급변 재생 중 $mode 진입은 반응을 지운다', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpWidget(host(ts: 2, brake: 1));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      if (mode == 'paused') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else {
        await tester.pumpWidget(host(
            ts: 2,
            brake: 1,
            reduce: mode == 'reduce',
            tickers: mode != 'ticker'));
      }
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
      if (mode == 'paused') {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    });
  }

  for (final mode in ['stop', 'reduce', 'ticker', 'disabled']) {
    testWidgets('$mode 변경은 진행중 사건과 다음 예약을 정리한다', (tester) async {
      await tester.pumpWidget(host(friends: [friend]));
      await spawn(tester);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(host(
          moving: mode != 'stop',
          reduce: mode == 'reduce',
          tickers: mode != 'ticker',
          animate: mode != 'disabled',
          friends: [friend]));
      await tester.pumpAndSettle();
      expect(find.byType(SpeciesArt), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(seconds: 20));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(host(friends: [friend]));
      await tester.pump(const Duration(milliseconds: 1999));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('앱 중단은 사건을 지우고 복귀는 새 대기부터 시작한다', (tester) async {
    await tester.pumpWidget(host(friends: [friend]));
    await spawn(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byType(SpeciesArt), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(seconds: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('수집 목록에서 빠진 친구는 같은 장면에서도 사라진다', (tester) async {
    await tester.pumpWidget(host(friends: [friend]));
    await spawn(tester);
    expect(find.byType(SpeciesArt), findsOneWidget);
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.byType(SpeciesArt), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
