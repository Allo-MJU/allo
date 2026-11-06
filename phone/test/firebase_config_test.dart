import 'dart:async';

import 'package:allo_phone/app.dart';
import 'package:allo_phone/config/firebase_config.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const validConfig = FirebaseConfig(
  apiKey: 'test-api-key',
  appId: '1:123:android:example',
  messagingSenderId: '123',
  projectId: 'allo-test',
  databaseUrl: 'https://allo-test-default-rtdb.firebaseio.com',
);

const missingConfig = FirebaseConfig(
  apiKey: '',
  appId: '',
  messagingSenderId: '',
  projectId: '',
  databaseUrl: '',
);

void main() {
  test('주입된 값으로 FirebaseOptions를 구성한다', () {
    final options = validConfig.toOptions();
    expect(options.apiKey, validConfig.apiKey);
    expect(options.appId, validConfig.appId);
    expect(options.messagingSenderId, validConfig.messagingSenderId);
    expect(options.projectId, validConfig.projectId);
    expect(options.databaseURL, validConfig.databaseUrl);
  });

  test('설정 누락과 DB 경로 오입력을 초기화 전에 거부한다', () {
    expect(missingConfig.toOptions, throwsFormatException);
    const wrongUrl = FirebaseConfig(
      apiKey: 'test-api-key',
      appId: 'test-app-id',
      messagingSenderId: '123',
      projectId: 'allo-test',
      databaseUrl: 'https://allo-test.firebaseio.com/sessions',
    );
    expect(wrongUrl.toOptions, throwsFormatException);
  });

  test('Fake 모드는 Firebase 설정과 초기화가 필요 없다', () async {
    final app = await createApp(
      config: missingConfig,
      initializeFirebase: (_) async => fail('Fake 모드에서 초기화하면 안 된다'),
    );
    expect(app, isA<AlloApp>());
    expect((app as AlloApp).feed, isA<FakeVehicleFeed>());
    await app.feed.dispose();
  });

  test('Firebase 초기화 완료 후에만 feed를 생성한다', () async {
    final initialized = Completer<void>();
    var feedCreated = false;
    final future = createApp(
      feedKind: 'firebase',
      config: validConfig,
      initializeFirebase: (options) {
        expect(options.databaseURL, validConfig.databaseUrl);
        return initialized.future;
      },
      createFirebaseFeed: () {
        feedCreated = true;
        return FakeVehicleFeed(scenario: FakeScenario.clear);
      },
    );
    expect(feedCreated, isFalse);
    initialized.complete();
    final app = await future as AlloApp;
    expect(feedCreated, isTrue);
    await app.feed.dispose();
  });

  testWidgets('설정이 없으면 오류 화면에서 체험 모드로 전환한다', (tester) async {
    final app = await createApp(
      feedKind: 'firebase',
      config: missingConfig,
      initializeFirebase: (_) async => fail('누락된 설정으로 초기화하면 안 된다'),
    );
    await tester.pumpWidget(app);
    expect(find.text('차량 연결 설정이 준비되지 않았어요.'), findsOneWidget);
    await tester.tap(find.text('체험 모드 시작'));
    await tester.pumpAndSettle();
    expect(find.text('차 없이 알로를 체험해 보세요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SDK 실패 원문과 설정 값을 오류 화면에 노출하지 않는다', (tester) async {
    final app = await createApp(
      feedKind: 'firebase',
      config: validConfig,
      initializeFirebase: (_) async => throw StateError('secret test-api-key'),
      createFirebaseFeed: () => throw StateError('초기화 실패 후 호출하면 안 된다'),
    );
    await tester.pumpWidget(app);
    expect(find.text('차량 연결을 준비하지 못했어요. 앱을 다시 실행해 주세요.'), findsOneWidget);
    expect(find.textContaining('test-api-key'), findsNothing);
    expect(find.text('체험 모드 시작'), findsOneWidget);
  });
}
