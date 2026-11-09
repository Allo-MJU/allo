import 'dart:async';

import 'package:allo_phone/ui_mode.dart';

/// 기존 화면 테스트는 버튼이 보이는 예전 화면으로 돈다.
/// 꽉 찬 차 안 화면은 fullscreen_cabin_test.dart 에서 켜서 확인한다.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  fullscreenCabin = false;
  await testMain();
}
