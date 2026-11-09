import 'package:flutter/widgets.dart';

import '../scene/passersby.dart';

/// 뒷좌석 가운데에서 본 차 안의 배치. 모든 좌표는 위젯 크기에 비례한다.
///
/// 옆창은 앞쪽(화면 가운데)으로 갈수록 작아지는 사다리꼴이다. 옆창 풍경은 넓은 직사각형에
/// 그린 뒤 [rectToQuad] 로 이 사다리꼴에 원근을 넣어 붙인다.
class CabinLayout {
  CabinLayout(this.size);

  final Size size;

  double get w => size.width;
  double get h => size.height;

  Offset _p(double x, double y) => Offset(w * x, h * y);

  /// 장식과 상호작용이 공유하는 위치. 오른쪽 앞좌석 등받이 윗단과 왼쪽 유리.
  Offset get passengerSeatGrip => _p(.63, .64);
  Offset get leftWindowContact => _p(.125, .38);
  double get companionSize =>
      (w * .18).clamp(56.0, 160.0).clamp(32.0, h * .4 < 32 ? 32.0 : h * .4);

  /// 시계 방향 네 꼭짓점: 왼쪽 위, 오른쪽 위, 오른쪽 아래, 왼쪽 아래.
  late final List<Offset> left = [
    _p(0.015, 0.09),
    _p(0.235, 0.19),
    _p(0.235, 0.55),
    _p(0.015, 0.68),
  ];
  late final List<Offset> right = [
    _p(0.765, 0.19),
    _p(0.985, 0.09),
    _p(0.985, 0.68),
    _p(0.765, 0.55),
  ];
  late final List<Offset> windshield = [
    _p(0.28, 0.15),
    _p(0.72, 0.15),
    _p(0.76, 0.6),
    _p(0.24, 0.6),
  ];

  List<Offset> quad(Pane pane) => switch (pane) {
        Pane.left => left,
        Pane.right => right,
        Pane.windshield => windshield,
      };

  Path path(Pane pane) => roundedQuad(quad(pane), h * 0.035);

  Rect bounds(Pane pane) => Rect.fromPoints(
      quad(pane).reduce((a, b) =>
          Offset(a.dx < b.dx ? a.dx : b.dx, a.dy < b.dy ? a.dy : b.dy)),
      quad(pane).reduce((a, b) =>
          Offset(a.dx > b.dx ? a.dx : b.dx, a.dy > b.dy ? a.dy : b.dy)));
}

/// 꼭짓점을 [r] 만큼 둥글린 사각형 경로.
Path roundedQuad(List<Offset> q, double r) {
  final p = Path();
  for (var i = 0; i < q.length; i++) {
    final prev = q[(i + q.length - 1) % q.length];
    final cur = q[i];
    final next = q[(i + 1) % q.length];
    final a = cur + _toward(cur, prev, r);
    final b = cur + _toward(cur, next, r);
    if (i == 0) {
      p.moveTo(a.dx, a.dy);
    } else {
      p.lineTo(a.dx, a.dy);
    }
    p.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
  }
  return p..close();
}

Offset _toward(Offset from, Offset to, double r) {
  final d = to - from;
  final len = d.distance;
  if (len == 0) return Offset.zero;
  return d * ((r < len / 2 ? r : len / 2) / len);
}

/// [src] 크기 직사각형을 [quad] (왼쪽 위부터 시계 방향) 로 옮기는 원근 변환.
///
/// 단위 정사각형 → 사각형 호모그래피(Heckbert)에 크기 축소를 앞에 붙인다.
Matrix4 rectToQuad(Size src, List<Offset> quad) {
  final x0 = quad[0].dx, y0 = quad[0].dy;
  final x1 = quad[1].dx, y1 = quad[1].dy;
  final x2 = quad[2].dx, y2 = quad[2].dy;
  final x3 = quad[3].dx, y3 = quad[3].dy;
  final dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  final dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
  double g = 0, hh = 0;
  if (dx3.abs() > 1e-9 || dy3.abs() > 1e-9) {
    final den = dx1 * dy2 - dx2 * dy1;
    g = (dx3 * dy2 - dx2 * dy3) / den;
    hh = (dx1 * dy3 - dx3 * dy1) / den;
  }
  final a = x1 - x0 + g * x1;
  final b = x3 - x0 + hh * x3;
  final d = y1 - y0 + g * y1;
  final e = y3 - y0 + hh * y3;
  final sw = src.width, sh = src.height;
  return Matrix4.zero()
    ..setEntry(0, 0, a / sw)
    ..setEntry(0, 1, b / sh)
    ..setEntry(0, 3, x0)
    ..setEntry(1, 0, d / sw)
    ..setEntry(1, 1, e / sh)
    ..setEntry(1, 3, y0)
    ..setEntry(2, 2, 1)
    ..setEntry(3, 0, g / sw)
    ..setEntry(3, 1, hh / sh)
    ..setEntry(3, 3, 1);
}
