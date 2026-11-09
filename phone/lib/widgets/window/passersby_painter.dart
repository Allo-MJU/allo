part of '../window_view.dart';

/// 창밖을 지나가는 생물·탈것을 그린다. 마주 오는 차는 앞유리 원근 도로에서 그린다.
///
/// 옆창은 왼쪽 창 기준으로 그리고(앞=오른쪽, 뒤=왼쪽), 오른쪽 창은 좌우를 뒤집는다.
class _PasserbyPainter extends CustomPainter {
  _PasserbyPainter(this.spawner, this.motion, this.pane)
      : super(repaint: motion);

  final PasserbySpawner spawner;
  final _Motion motion;
  final Pane pane;

  @override
  void paint(Canvas canvas, Size size) {
    final t = motion.seconds;
    final flip = paneFlow(pane) > 0;
    if (flip) {
      canvas
        ..save()
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    for (final p in spawner.active) {
      if (p.pane != pane || !p.visible(t)) continue;
      if (p.kind == PasserbyKind.friend || p.kind == PasserbyKind.oncomingCar) {
        continue;
      }
      _draw(canvas, size, p, t);
    }
    if (flip) canvas.restore();
  }

  void _draw(Canvas canvas, Size size, Passerby p, double t) {
    final w = size.width;
    final h = size.height;
    final pr = p.progress(t);
    final age = t - p.bornAt;
    final s = h * 0.06 * p.scale;
    final front = pane == Pane.windshield;
    // 하늘을 나는 것: 옆창에서는 뒤로 밀려나고, 앞유리에서는 하늘을 가로지른다
    if (isAirborne(p.kind)) {
      final fromLeft = p.seed.isEven;
      final x = front
          ? (fromLeft
              ? -s * 2 + pr * (w + s * 4)
              : w + s * 2 - pr * (w + s * 4))
          : w + s * 2 - pr * (w + s * 4);
      final y = h * (front ? 0.08 + p.lane * 0.22 : 0.12 + p.lane * 0.3) +
          math.sin(age * 1.7 + p.seed) * h * 0.03;
      final c = Offset(x, y);
      switch (p.kind) {
        case PasserbyKind.gull:
          _gull(canvas, c, s * (front ? 0.8 : 1.1), age * 7 + p.seed);
        case PasserbyKind.flock:
          for (var k = 0; k < 6; k++) {
            final row = (k + 1) ~/ 2;
            final side = k.isOdd ? -1 : 1;
            _bird(canvas, c + Offset(row * s * 0.9, side * row * s * 0.45),
                s * 0.45, age * 9 + k);
          }
        case PasserbyKind.butterfly:
          _butterfly(
              canvas,
              c + Offset(0, math.sin(age * 5 + p.seed) * s * 1.5 + h * 0.35),
              s * 0.7,
              age,
              p.seed);
        case PasserbyKind.firefly:
          _firefly(canvas, size, p, age);
        default:
      }
      return;
    }
    // 땅에 있는 것: 풍경과 함께 앞(오른쪽)에서 뒤(왼쪽)로 흐른다
    final base = h * (0.78 + p.lane * 0.06);
    final x = w + s * 6 - pr * (w + s * 12);
    switch (p.kind) {
      case PasserbyKind.cyclist:
        _cyclist(canvas, Offset(x, base), s * 1.3, age, p.seed);
      case PasserbyKind.bus:
        _bus(canvas, Offset(x, base), s * 1.6);
      case PasserbyKind.umbrella:
        _umbrella(canvas, Offset(x, base), s * 1.2, p.seed);
      default:
    }
  }

  void _gull(Canvas canvas, Offset c, double s, double phase) {
    final flap = math.sin(phase);
    final wing = Path()
      ..moveTo(c.dx - s, c.dy - flap * s * 0.3)
      ..quadraticBezierTo(
          c.dx - s * 0.45, c.dy - s * 0.55 * (0.4 + flap), c.dx, c.dy)
      ..quadraticBezierTo(c.dx + s * 0.45, c.dy - s * 0.55 * (0.4 + flap),
          c.dx + s, c.dy - flap * s * 0.3);
    canvas
      ..drawPath(
          wing,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.22
            ..strokeCap = StrokeCap.round
            ..color = Colors.white)
      ..drawCircle(c + Offset(0, s * 0.05), s * 0.13,
          Paint()..color = const Color(0xFFEDEDED))
      ..drawCircle(Offset(c.dx - s, c.dy - flap * s * 0.3), s * 0.1,
          Paint()..color = const Color(0xFF4A4F55))
      ..drawCircle(Offset(c.dx + s, c.dy - flap * s * 0.3), s * 0.1,
          Paint()..color = const Color(0xFF4A4F55));
  }

  void _bird(Canvas canvas, Offset c, double s, double phase) {
    final f = math.sin(phase) * 0.5 + 0.5;
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - s, c.dy - s * 0.5 * f)
          ..quadraticBezierTo(c.dx - s * 0.4, c.dy - s * 0.4, c.dx, c.dy)
          ..quadraticBezierTo(
              c.dx + s * 0.4, c.dy - s * 0.4, c.dx + s, c.dy - s * 0.5 * f),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, s * 0.2)
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF3A3A48));
  }

  void _butterfly(Canvas canvas, Offset c, double s, double age, int seed) {
    final color = const [
      Color(0xFFFFE27A),
      Color(0xFFFFFFFF),
      Color(0xFFF6A35B),
    ][seed % 3];
    final open = (math.sin(age * 16) * 0.5 + 0.5) * 0.8 + 0.2;
    final wing = Paint()..color = color;
    for (final side in [-1.0, 1.0]) {
      canvas
        ..drawOval(
            Rect.fromCenter(
                center: c + Offset(side * s * 0.45 * open, -s * 0.2),
                width: s * 0.9 * open,
                height: s * 0.9),
            wing)
        ..drawOval(
            Rect.fromCenter(
                center: c + Offset(side * s * 0.35 * open, s * 0.35),
                width: s * 0.6 * open,
                height: s * 0.6),
            wing);
    }
    canvas.drawLine(
        c - Offset(0, s * 0.5),
        c + Offset(0, s * 0.6),
        Paint()
          ..color = const Color(0xFF3B3026)
          ..strokeWidth = math.max(1, s * 0.12));
  }

  void _firefly(Canvas canvas, Size size, Passerby p, double age) {
    final w = size.width;
    final h = size.height;
    for (var k = 0; k < 5; k++) {
      final x = w * (_rand(p.seed * 5 + k, 91)) +
          _noise(age * 0.8 + k * 3, p.seed + k) * w * 0.15 -
          age * w * 0.05;
      final y = h * (0.45 + 0.35 * _rand(p.seed * 5 + k, 92)) +
          (_noise(age * 0.7 + k, p.seed + 9) - 0.5) * h * 0.15;
      final blink = (math.sin(age * 3 + k * 1.7) * 0.5 + 0.5);
      final fade = math.min(1.0, math.min(age, p.life - age) / 0.8);
      final a = blink * fade;
      _glowCircle(canvas, Offset(x, y), h * 0.012,
          const Color(0xFFDFFF8A).withValues(alpha: a),
          spread: 3);
      canvas.drawCircle(Offset(x, y), h * 0.008,
          Paint()..color = const Color(0xFFF4FFC4).withValues(alpha: a));
    }
  }

  void _cyclist(Canvas canvas, Offset base, double s, double age, int seed) {
    final wheel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s * 0.09)
      ..color = const Color(0xFF2E2E2E);
    final r = s * 0.42;
    final back = base + Offset(-s * 0.6, -r);
    final front = base + Offset(s * 0.6, -r);
    final seat = base + Offset(-s * 0.15, -s * 1.15);
    final bar = base + Offset(s * 0.45, -s * 1.25);
    final shirt = const [
      Color(0xFFE2614B),
      Color(0xFF4A90D0),
      Color(0xFFF2C14E),
    ][seed % 3];
    canvas
      ..drawCircle(back, r, wheel)
      ..drawCircle(front, r, wheel)
      ..drawLine(back, seat, wheel)
      ..drawLine(seat, front, wheel)
      ..drawLine(front, bar, wheel)
      ..drawLine(back, base + Offset(s * 0.1, -r), wheel)
      // 사람: 몸통·머리
      ..drawLine(
          seat + Offset(0, -s * 0.05),
          bar + Offset(-s * 0.2, -s * 0.55),
          Paint()
            ..color = shirt
            ..strokeWidth = s * 0.32
            ..strokeCap = StrokeCap.round)
      ..drawCircle(bar + Offset(-s * 0.18, -s * 0.85), s * 0.2,
          Paint()..color = const Color(0xFF3B2E26));
    // 페달 밟는 다리
    final k = math.sin(age * 9);
    canvas.drawLine(
        seat,
        base + Offset(k * s * 0.25, -r),
        Paint()
          ..color = const Color(0xFF3B4A5C)
          ..strokeWidth = s * 0.16
          ..strokeCap = StrokeCap.round);
  }

  void _bus(Canvas canvas, Offset base, double s) {
    final body = RRect.fromRectAndRadius(
        Rect.fromLTRB(base.dx - s * 3, base.dy - s * 2.1, base.dx + s * 3,
            base.dy - s * 0.3),
        Radius.circular(s * 0.35));
    canvas.drawRRect(body, Paint()..color = const Color(0xFF3FA36B));
    canvas.drawRect(
        Rect.fromLTRB(base.dx - s * 3, base.dy - s * 0.9, base.dx + s * 3,
            base.dy - s * 0.7),
        Paint()..color = const Color(0xFFF3F1E7));
    final glass = Paint()..color = const Color(0xFF5E7E9C);
    for (var x = -2.7; x < 2.6; x += 0.95) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  base.dx + x * s, base.dy - s * 1.85, s * 0.75, s * 0.75),
              Radius.circular(s * 0.1)),
          glass);
    }
    final tire = Paint()..color = const Color(0xFF1E1E1E);
    for (final x in [-1.9, 1.9]) {
      canvas.drawCircle(base + Offset(x * s, -s * 0.3), s * 0.38, tire);
    }
  }

  void _umbrella(Canvas canvas, Offset base, double s, int seed) {
    final color = const [
      Color(0xFFE2614B),
      Color(0xFFFFD34E),
      Color(0xFF4A90D0),
      Color(0xFF58D8A0),
    ][seed % 4];
    canvas
      ..drawLine(
          base + Offset(0, -s * 0.05),
          base + Offset(0, -s * 0.9),
          Paint()
            ..color = const Color(0xFF3B4A5C)
            ..strokeWidth = s * 0.3
            ..strokeCap = StrokeCap.round)
      ..drawLine(
          base + Offset(0, -s * 1.0),
          base + Offset(0, -s * 1.7),
          Paint()
            ..color = const Color(0xFF2E2E2E)
            ..strokeWidth = math.max(1, s * 0.06))
      ..drawArc(
          Rect.fromCenter(
              center: base + Offset(0, -s * 1.6), width: s * 1.6, height: s),
          math.pi,
          math.pi,
          true,
          Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PasserbyPainter oldDelegate) => oldDelegate.pane != pane;
}
