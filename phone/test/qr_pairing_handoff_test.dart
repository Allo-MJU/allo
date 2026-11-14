import 'dart:async';

import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/explore/explore_screen.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/unity_app/unity_app_controller.dart';
import 'package:allo_phone/unity_app/unity_app_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('allo/explore');
  final credentials = PairingCredentials.parseFields(
      '11111111-1111-1111-1111-111111111111', '123456');
  late UnityAppController controller;
  late GameController game;
  late BaseCampController camp;
  late List<String> calls;
  bool openWorks = true;
  bool closeFails = false;
  Completer<void>? closeGate;
  var resumes = 0;

  setUp(() {
    calls = [];
    openWorks = true;
    closeFails = false;
    closeGate = null;
    resumes = 0;
    game = GameController(
        feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore());
    camp = BaseCampController(store: SharedPreferencesBaseCampStore());
    controller = UnityAppController(game: game, camp: camp);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'close') {
        await closeGate?.future;
        if (closeFails) throw PlatformException(code: 'close_failed');
      }
      if (call.method == 'open') return openWorks;
      return null;
    });
  });
  tearDown(() {
    controller.dispose();
    game.dispose();
    camp.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> host(WidgetTester tester, {WidgetBuilder? scanner}) async {
    await tester.pumpWidget(MaterialApp(
      home: UnityAppScreen(
        controller: controller,
        pairingScannerBuilder: scanner ??
            (context) => Scaffold(
                  appBar: AppBar(title: const Text('Scanner')),
                  body: TextButton(
                    onPressed: () => Navigator.of(context).pop(credentials),
                    child: const Text('Scan success'),
                  ),
                ),
        unityView: ({required onCreated, required onMessage}) {
          onCreated((_) {}, () => resumes++);
          return const SizedBox(key: Key('unity'));
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('QR route returns credentials only after reopening Unity',
      (tester) async {
    await host(tester);
    final result = controller.pairingScanner!();
    await tester.pumpAndSettle();
    expect(calls, ['close']);
    expect(find.text('Scanner'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(resumes, 0);
    await tester.tap(find.text('Scan success'));
    await tester.pumpAndSettle();
    expect(await result, same(credentials));
    expect(calls, ['close', 'open']);
    expect(find.byKey(const Key('unity')), findsOneWidget);
  });

  testWidgets('back cancels QR and reopens Unity without credentials',
      (tester) async {
    await host(tester);
    final result = controller.pairingScanner!();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(calls, ['close', 'open']);
  });

  testWidgets('failed Unity reopen does not deliver scanned credentials',
      (tester) async {
    await host(tester);
    openWorks = false;
    final result = controller.pairingScanner!();
    final error = expectLater(result, throwsA(isA<PairingException>()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan success'));
    await tester.pumpAndSettle();
    await error;
  });

  testWidgets(
      'native close failure does not show scanner or deliver credentials',
      (tester) async {
    await host(tester);
    closeFails = true;
    final result = controller.pairingScanner!();
    await expectLater(result, throwsA(isA<PlatformException>()));
    await tester.pumpAndSettle();
    expect(find.text('Scanner'), findsNothing);
    expect(calls, ['close']);
  });

  testWidgets('dispose cancels pending QR without reopening or hanging',
      (tester) async {
    await host(tester);
    final result = controller.pairingScanner!();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(controller.pairingScanner, isNull);
    expect(calls, ['close']);
    expect(unityExploreOpen.value, isFalse);
  });

  testWidgets('dispose while native close is pending ignores late completion',
      (tester) async {
    await host(tester);
    closeGate = Completer<void>();
    final result = controller.pairingScanner!();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(await result, isNull);
    closeGate!.complete();
    await tester.pumpAndSettle();
    expect(calls, ['close']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controller replacement cancels QR and removes the owned route',
      (tester) async {
    await host(tester);
    final oldController = controller;
    final result = oldController.pairingScanner!();
    await tester.pumpAndSettle();
    controller = UnityAppController(game: game, camp: camp);
    await host(tester);
    expect(await result, isNull);
    expect(oldController.pairingScanner, isNull);
    expect(controller.pairingScanner, isNotNull);
    expect(find.text('Scanner'), findsNothing);
    expect(calls, ['close']);
    oldController.dispose();
  });

  testWidgets('disposal does not clear a callback replaced by the caller',
      (tester) async {
    await host(tester);
    Future<PairingCredentials?> replacement() async => credentials;
    controller.pairingScanner = replacement;
    await tester.pumpWidget(const SizedBox());
    expect(controller.pairingScanner, same(replacement));
  });

  testWidgets('injected callback remains owned by its caller', (tester) async {
    Future<PairingCredentials?> injected() async => credentials;
    controller.pairingScanner = injected;
    await host(tester);
    expect(controller.pairingScanner, same(injected));
    await tester.pumpWidget(const SizedBox());
    expect(controller.pairingScanner, same(injected));
    expect(calls, isEmpty);
  });
}
