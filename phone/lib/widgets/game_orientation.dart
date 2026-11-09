import 'dart:async';
import 'package:flutter/services.dart';

/// 게임 라우트가 겹쳐 교체되는 동안 이전 화면이 새 화면의 방향을 풀지 않는다.
abstract final class GameOrientation {
  static int _screens = 0;

  static void acquire() {
    if (_screens++ == 0) {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
  }

  static void release() {
    assert(_screens > 0);
    if (--_screens == 0) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
  }
}
