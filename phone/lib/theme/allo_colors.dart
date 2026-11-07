import 'package:flutter/material.dart';

/// 확정 색상 가이드 및 #49 fad3ad6의 역할 토큰 중 현재 화면에서 쓰는 값.
/// 대응과 미반영 항목: docs/phone-presentation-integration.md.
abstract final class AlloColors {
  static const discoveryBackground = shellYellow;
  static const textPrimary = ink;
  static const actionPrimary = actionGreen;
  static const textInverse = Colors.white;
  static const progressFill = growthGreen;
  static const ink = Color(0xFF111111);
  static const shellYellow = Color(0xFFFCCC44);
  static const growthGreen = Color(0xFF1D9965);
  static const actionGreen = Color(0xFF146B49);
}

abstract final class AlloPresentation {
  static const fontFamily = 'Asta Sans';
  static const hatchDuration = Duration(milliseconds: 2400);
  static const fadeDuration = Duration(milliseconds: 200);
  static const standardCurve = Cubic(.2, .8, .2, 1);
  static const touchMin = 56.0;
  static const touchKid = 72.0;
}
