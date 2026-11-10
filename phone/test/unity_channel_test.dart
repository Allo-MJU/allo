import 'dart:ui' as ui;

import 'package:allo_phone/explore/unity_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('allo/explore');

/// Unity(Kotlin) 가 Flutter 로 보내는 메시지를 엔진과 같은 경로(ChannelBuffers)로 넣는다.
/// 받을 처리기가 없으면 엔진은 마지막 메시지를 보관했다가 다음 처리기에 준다.
Future<void> fromUnity(WidgetTester tester, String json) async {
  ui.channelBuffers.push(
      _channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('fromUnity', json)),
      (_) {});
  await tester.pump();
}

Widget launcher(List<String> got) => MaterialApp(
      home: androidUnityView(
        onCreated: (send, [resume]) {},
        onMessage: got.add,
      ),
    );

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => true);
  });

  testWidgets('탐험 화면이 없을 때 온 메시지는 다음 화면에 전달하지 않는다', (tester) async {
    final first = <String>[];
    await tester.pumpWidget(launcher(first));
    await tester.pumpWidget(const SizedBox()); // 탐험 화면 닫힘

    await fromUnity(tester, '{"v":1,"type":"close"}'); // 닫힌 뒤 늦게 온 close

    final second = <String>[];
    await tester.pumpWidget(launcher(second));
    await tester.pump();
    expect(second, isEmpty, reason: '이전 회차의 close 를 받으면 새 화면이 바로 닫힌다');

    await fromUnity(tester, '{"v":1,"type":"ready"}');
    expect(second, ['{"v":1,"type":"ready"}']);
  });
}
