import 'package:allo_phone/screen_share/screen_share_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('ai.allo/screen_share');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets('시작과 중지는 별도 명령으로 전달한다', (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ScreenShareButton())));
    await tester.tap(find.byTooltip('화면 공유 시제품'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('화면 공유 시작'));
    await tester.pumpAndSettle();
    expect(calls, ['open']);
    await tester.tap(find.byTooltip('화면 공유 시제품'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('화면 공유 중지'));
    await tester.pumpAndSettle();
    expect(calls, ['open', 'stop']);
  });
  testWidgets('네이티브 오류는 연결 정보 없이 안내한다', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'failed', message: 'secret-token');
    });
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ScreenShareButton())));
    await tester.tap(find.byTooltip('화면 공유 시제품'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('화면 공유 시작'));
    await tester.pumpAndSettle();
    expect(find.text('화면 공유를 시작할 수 없어요. 연결 설정을 확인해 주세요.'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
  });
  testWidgets('Android가 아니면 진입 버튼을 표시하지 않는다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScreenShareButton()));
    expect(find.byTooltip('화면 공유 시제품'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
