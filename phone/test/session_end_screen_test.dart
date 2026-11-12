import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/app.dart';
import 'package:allo_phone/feed/vehicle_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:allo_phone/screens/session_end_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sid = 'b0c260a8-e807-42e9-a119-26119837113b';

// 저장소 Future와 위젯 프레임은 서로 다른 스케줄러에서 완료될 수 있다.
Future<void> _flushStorage(
    WidgetTester tester, bool Function() finished) async {
  for (var i = 0; i < 20 && !finished(); i++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  expect(finished(), isTrue);
}

void main() {
  for (final phase in ['품기', '부화 전환 직전', '부화 연출', '동행']) {
    testWidgets('$phase 중 차량이 종료되면 저장 완료 화면에서 새 연결과 도감으로 이동한다', (tester) async {
      SharedPreferences.setMockInitialValues({
        'pairing.session.v1': jsonEncode({'sid': _sid, 'code': '123456'}),
      });
      await tester
          .runAsync(() => rootBundle.loadString('assets/data/species.json'));
      final feed = _TripFeed();
      await tester.pumpWidget(AlloApp(feed: feed));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('알 품기 시작'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('알 품기 시작'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20 && find.text('알 품기').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(find.text('알 품기'), findsOneWidget);
      final c = tester
          .widget<IncubatingScreen>(find.byType(IncubatingScreen))
          .controller;

      await tester.runAsync(() async {
        feed.send(phase == '품기' ? 2000 : 5000);
        if (phase == '부화 전환 직전') {
          feed.endTrip();
        }
      });
      if (phase != '부화 전환 직전') await tester.pumpAndSettle();
      if (phase == '동행') {
        await tester.tap(find.text('같이 가자'));
        await tester.pumpAndSettle();
        expect(find.text('봤어!'), findsOneWidget);
      }
      if (phase != '부화 전환 직전') {
        feed.endTrip();
      }
      await _flushStorage(tester, () => c.sessionSaved);
      await tester.pumpAndSettle();

      expect(find.text('기록을 저장했어요'), findsOneWidget);
      expect(find.text('새 차량 연결'), findsOneWidget);
      expect(find.text('도감 보기'), findsOneWidget);
      expect(find.text('같이 가자'), findsNothing);
      await tester.tap(find.text('새 차량 연결'));
      await tester.pumpAndSettle();
      expect(find.text('차 화면의 QR을 찍어 주세요'), findsOneWidget);
      final start = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '알 품기 시작'));
      expect(start.onPressed, isNull);
      await tester.scrollUntilVisible(find.text('도감 보기'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('도감 보기'));
      await tester.pump();
      await _flushStorage(
          tester, () => find.textContaining('만난 친구').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.text('도감'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('작은 화면과 큰 글씨에서도 저장 진행·실패·재시도 후 도감 이동을 안내한다', (tester) async {
    tester.view.physicalSize = const Size(320, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final feed = _TripFeed();
    final store = _GateDex()..fail = true;
    late GameController c;
    await tester.runAsync(() async {
      c = GameController(feed: feed, dex: store);
      await c.pair(_sid, pairCode: '123456');
      expect(await c.startIncubating(EggTier.small), isTrue);
    });
    await tester.runAsync(() async {
      feed.send(2000);
      store.gate = Completer<void>();
      feed.endTrip();
    });
    final router = GoRouter(
      initialLocation: '/session-end',
      routes: [
        GoRoute(
          path: '/session-end',
          builder: (_, __) => SessionEndScreen(controller: c),
        ),
        GoRoute(
          path: '/dex',
          builder: (_, __) => const Scaffold(body: Text('저장된 도감')),
        ),
        GoRoute(
          path: '/pairing',
          builder: (_, __) => const Scaffold(body: Text('새 QR 연결')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
    ));
    await tester.pump();
    expect(find.text('기록을 저장하고 있어요'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('새 차량 연결'), findsNothing);
    expect(find.text('다시 저장'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      store.gate!.complete();
      expect(await c.endSession(), isFalse);
    });
    await tester.pumpAndSettle();
    expect(find.text('기록을 저장하지 못했어요'), findsOneWidget);
    expect(find.text('새 차량 연결'), findsNothing);
    expect(c.sessionSaved, isFalse);
    store.fail = false;
    await tester.runAsync(() async => store.gate = Completer<void>());
    await tester.ensureVisible(find.text('다시 저장'));
    await tester.runAsync(() => tester.tap(find.text('다시 저장')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('다시 저장'), findsNothing);

    await tester.runAsync(() async {
      store.gate!.complete();
      expect(await c.endSession(), isTrue);
    });
    await tester.pumpAndSettle();
    expect(find.text('기록을 저장했어요'), findsOneWidget);
    expect(await tester.runAsync(() => store.carriedDistance(EggTier.small)),
        2000);
    await tester.ensureVisible(find.text('도감 보기'));
    await tester.tap(find.text('도감 보기'));
    await tester.pumpAndSettle();
    expect(find.text('저장된 도감'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    c.dispose();
  });
}

class _GateDex extends DexStore {
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    await gate?.future;
    if (fail) throw StateError('storage unavailable');
    await super.saveIncubationProgress(tier, progress);
  }
}

class _TripFeed implements VehicleFeed {
  final _signals = StreamController<VehicleState>.broadcast(sync: true);
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  VehicleState? _latest;

  void send(double distance) {
    _latest = VehicleState.fromJson({
      'ts': 1000,
      'gear': 'D',
      'distanceM': distance,
    });
    _signals.add(_latest!);
  }

  // 차량의 종료 이벤트는 payload 키가 없다.
  void endTrip() =>
      _events.add({'ts': 2000, 'by': 'car', 'type': 'sessionEnd'});

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {}
  @override
  Stream<VehicleState> watch() => _signals.stream;
  @override
  Future<VehicleState?> readLatestVehicle() async {
    return _latest;
  }

  @override
  Stream<Map<String, Object?>> events() => _events.stream;
  @override
  Future<void> publishGame(GameState state) async {}
  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {}
  @override
  Future<void> dispose() async {
    await _signals.close();
    await _events.close();
  }
}
