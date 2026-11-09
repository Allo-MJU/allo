part of '../window_view.dart';

/// 차 안: 천장·기둥·문 패널·대시보드·운전대·앞좌석·가운데 콘솔·룸미러와 알 장식.
///
/// 유리창 자리는 비워 두고(짝홀 채우기) 그 아래에 깔린 창밖 그림이 보이게 한다.
/// 밤에는 실내가 푸르게 어두워지고, 터널에서는 지나가는 주황 등에 맞춰 밝아졌다 어두워진다.
class _CabinPainter extends CustomPainter {
  _CabinPainter(this.scene, this.motion, this.layout) : super(repaint: motion);

  final WindowScene scene;
  final _Motion motion;
  final CabinLayout layout;

  /// 장면에 맞춰 실내 색을 바꾼다
  Color _c(Color c) {
    if (scene.kind == SceneKind.tunnel) {
      final pulse = 0.5 + 0.5 * math.sin(motion.meters / 8 * math.pi * 2);
      final warm = Color.lerp(c, const Color(0xFF6B4A2A), 0.5)!;
      return Color.lerp(warm, Colors.black, 0.35 - pulse * 0.15)!;
    }
    if (scene.night) return Color.lerp(c, const Color(0xFF151B33), 0.62)!;
    if (scene.rainLevel > 0) {
      return Color.lerp(c, const Color(0xFF59606A), 0.18)!;
    }
    return c;
  }

  Paint _fill(Color c) => Paint()..color = _c(c);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final L = layout;

    // 1. 실내 몸체: 유리창 세 곳을 뚫은 면
    final shell = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(L.path(Pane.left), Offset.zero)
      ..addPath(L.path(Pane.right), Offset.zero)
      ..addPath(L.path(Pane.windshield), Offset.zero);
    canvas.drawPath(
        shell,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _c(const Color(0xFFE4DACB)),
              _c(const Color(0xFFCFC2AF)),
              _c(const Color(0xFF8E7B69)),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Offset.zero & size));

    // 2. 기둥 그늘: 앞유리와 옆창 사이(A 필러)
    for (final (side, ws) in [(L.left, 0), (L.right, 1)]) {
      final f = L.windshield;
      final pts = ws == 0
          ? [side[1], f[0], f[3], side[2]]
          : [f[1], side[0], side[3], f[2]];
      canvas.drawPath(
          Path()..addPolygon(pts, true), _fill(const Color(0xFFB9AA96)));
    }
    // 천장 손잡이와 실내등
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w * 0.5, h * 0.06),
                width: w * 0.12,
                height: h * 0.04),
            Radius.circular(h * 0.02)),
        _fill(const Color(0xFFF3EDE2)));
    if (scene.night) {
      _glowCircle(
          canvas, Offset(w * 0.5, h * 0.06), h * 0.025, const Color(0x55FFF1C8),
          spread: 2.5);
    }
    for (final side in [-1.0, 1.0]) {
      final cx = side < 0 ? w * 0.12 : w * 0.88;
      canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.05, h * (side < 0 ? 0.075 : 0.105))
            ..quadraticBezierTo(
                cx, h * 0.03, cx + w * 0.05, h * (side < 0 ? 0.105 : 0.075)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = h * 0.014
            ..strokeCap = StrokeCap.round
            ..color = _c(const Color(0xFF9C8C78)));
    }

    // 3. 유리 테두리 고무와 유리 반사
    final rubber = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.014
      ..color = _c(const Color(0xFF2B2622));
    for (final pane in Pane.values) {
      final path = L.path(pane);
      canvas
        ..save()
        ..clipPath(path);
      final b = L.bounds(pane);
      final glare = Paint()..color = Colors.white.withValues(alpha: 0.07);
      canvas
        ..drawPath(
            Path()
              ..moveTo(b.left + b.width * 0.15, b.top)
              ..lineTo(b.left + b.width * 0.35, b.top)
              ..lineTo(b.left + b.width * 0.1, b.bottom)
              ..lineTo(b.left - b.width * 0.1, b.bottom)
              ..close(),
            glare)
        ..drawPath(
            Path()
              ..moveTo(b.left + b.width * 0.45, b.top)
              ..lineTo(b.left + b.width * 0.52, b.top)
              ..lineTo(b.left + b.width * 0.32, b.bottom)
              ..lineTo(b.left + b.width * 0.25, b.bottom)
              ..close(),
            glare)
        ..restore()
        ..drawPath(path, rubber);
    }

    // 4. 문 패널: 옆창 아래, 팔걸이와 손잡이
    for (final side in [-1.0, 1.0]) {
      final q = side < 0 ? L.left : L.right;
      final outer = side < 0 ? q[3] : q[2];
      final inner = side < 0 ? q[2] : q[3];
      final panel = Path()
        ..moveTo(outer.dx, outer.dy + h * 0.02)
        ..lineTo(inner.dx, inner.dy + h * 0.02)
        ..lineTo(inner.dx + side * -w * 0.01, h)
        ..lineTo(side < 0 ? 0 : w, h)
        ..close();
      canvas.drawPath(panel, _fill(const Color(0xFF7A6553)));
      // 위쪽 트림
      canvas.drawLine(
          outer + Offset(0, h * 0.03),
          inner + Offset(0, h * 0.03),
          Paint()
            ..strokeWidth = h * 0.025
            ..color = _c(const Color(0xFFD8CBB7)));
      // 팔걸이
      final arm = Path()
        ..moveTo(outer.dx, outer.dy + h * 0.14)
        ..lineTo(inner.dx, inner.dy + h * 0.1)
        ..lineTo(inner.dx, inner.dy + h * 0.15)
        ..lineTo(outer.dx, outer.dy + h * 0.22)
        ..close();
      canvas.drawPath(arm, _fill(const Color(0xFF5E4C3F)));
      // 문 손잡이
      final hx = Offset.lerp(outer, inner, 0.55)! + Offset(0, h * 0.07);
      canvas
        ..drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: hx, width: w * 0.06, height: h * 0.025),
                Radius.circular(h * 0.012)),
            _fill(const Color(0xFFBFC4C6)))
        // 스피커
        ..drawCircle(Offset.lerp(outer, inner, 0.4)! + Offset(0, h * 0.28),
            w * 0.035, _fill(const Color(0xFF4E4036)));
    }

    // 5. 대시보드: 앞좌석 사이로 보인다
    final dash = Path()
      ..moveTo(w * 0.22, h * 0.61)
      ..quadraticBezierTo(w * 0.5, h * 0.55, w * 0.78, h * 0.61)
      ..lineTo(w * 0.78, h * 0.72)
      ..lineTo(w * 0.22, h * 0.72)
      ..close();
    canvas
      ..drawPath(dash, _fill(const Color(0xFF3E3631)))
      ..drawPath(
          Path()
            ..moveTo(w * 0.22, h * 0.61)
            ..quadraticBezierTo(w * 0.5, h * 0.55, w * 0.78, h * 0.61),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = h * 0.008
            ..color = _c(const Color(0xFF6A5E55)));
    // 가운데 화면 (차량 디스플레이)
    final screen = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.66),
            width: w * 0.12,
            height: h * 0.045),
        Radius.circular(h * 0.01));
    canvas.drawRRect(screen, Paint()..color = const Color(0xFF14261F));
    canvas.drawCircle(
        screen.center, h * 0.012, Paint()..color = _Palette.logoYellowGlow);
    // 계기판 불빛 (운전석 쪽)
    if (scene.night || scene.kind == SceneKind.tunnel) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(w * 0.37, h * 0.62),
              width: w * 0.12,
              height: h * 0.03),
          Paint()..color = const Color(0x4458D8A0));
    }
    // 운전대: 왼쪽 좌석 너머로 윗부분만 보인다
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(w * 0.37, h * 0.71),
            width: w * 0.19,
            height: h * 0.2),
        math.pi * 1.05,
        math.pi * 0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.022
          ..strokeCap = StrokeCap.round
          ..color = _c(const Color(0xFF26211E)));

    // 6. 룸미러와 알 장식
    _mirror(canvas, size);

    // 7. 앞좌석 두 개
    for (final cx in [0.37, 0.63]) {
      _seat(canvas, size, w * cx);
    }

    // 8. 가운데 팔걸이·콘솔 (캐릭터가 올라앉는 자리)
    final console = RRect.fromRectAndCorners(
        Rect.fromLTRB(w * 0.4, h * 0.84, w * 0.6, h * 1.02),
        topLeft: Radius.circular(h * 0.04),
        topRight: Radius.circular(h * 0.04));
    canvas
      ..drawRRect(console, _fill(const Color(0xFF4A3D34)))
      ..drawLine(
          Offset(w * 0.41, h * 0.85),
          Offset(w * 0.59, h * 0.85),
          Paint()
            ..strokeWidth = h * 0.006
            ..color = _c(const Color(0xFF7A685A)));
  }

  void _seat(Canvas canvas, Size size, double cx) {
    final w = size.width;
    final h = size.height;
    final sw = w * 0.21;
    // 머리받침 기둥
    final post = Paint()
      ..strokeWidth = math.max(1.5, w * 0.008)
      ..color = _c(const Color(0xFFA9AEB0));
    for (final dx in [-0.025, 0.025]) {
      canvas.drawLine(
          Offset(cx + w * dx, h * 0.6), Offset(cx + w * dx, h * 0.66), post);
    }
    // 머리받침
    final head = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, h * 0.57), width: w * 0.1, height: h * 0.075),
        Radius.circular(h * 0.035));
    canvas
      ..drawRRect(head, _fill(const Color(0xFF5A4A40)))
      ..drawRRect(head.deflate(h * 0.012).shift(Offset(-w * 0.004, -h * 0.006)),
          _fill(const Color(0xFF6E5C50)));
    // 등받이: 위가 둥글고 아래로 넓어진다
    final back = Path()
      ..moveTo(cx - sw * 0.42, h * 1.02)
      ..lineTo(cx - sw * 0.46, h * 0.7)
      ..quadraticBezierTo(cx - sw * 0.46, h * 0.64, cx - sw * 0.3, h * 0.64)
      ..lineTo(cx + sw * 0.3, h * 0.64)
      ..quadraticBezierTo(cx + sw * 0.46, h * 0.64, cx + sw * 0.46, h * 0.7)
      ..lineTo(cx + sw * 0.42, h * 1.02)
      ..close();
    canvas.drawPath(
        back,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              _c(const Color(0xFF6E5C50)),
              _c(const Color(0xFF5A4A40)),
              _c(const Color(0xFF4A3C33)),
            ],
          ).createShader(Rect.fromLTRB(cx - sw / 2, h * 0.64, cx + sw / 2, h)));
    // 박음질 선과 등받이 주머니
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, h * 0.004)
      ..color = _c(const Color(0xFF8A7768));
    canvas
      ..drawLine(Offset(cx - sw * 0.2, h * 0.68),
          Offset(cx - sw * 0.22, h * 0.98), seam)
      ..drawLine(Offset(cx + sw * 0.2, h * 0.68),
          Offset(cx + sw * 0.22, h * 0.98), seam)
      ..drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(cx - sw * 0.3, h * 0.82, cx + sw * 0.3, h * 0.96),
              Radius.circular(h * 0.02)),
          seam);
  }

  /// 룸미러에 매단 알 장식. 달릴 때 조금씩 흔들리고, 급제동·급조향이면 크게 흔들린다.
  void _mirror(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = motion.seconds;
    final top = Offset(w * 0.5, h * 0.15);
    final mirror = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.215),
            width: w * 0.15,
            height: h * 0.045),
        Radius.circular(h * 0.02));
    canvas
      ..drawLine(
          top,
          mirror.center,
          Paint()
            ..strokeWidth = h * 0.012
            ..color = _c(const Color(0xFF2E2A27)))
      ..drawRRect(mirror, _fill(const Color(0xFF2E2A27)))
      ..drawRRect(
          mirror.deflate(h * 0.006),
          Paint()
            ..shader = LinearGradient(colors: [
              _c(const Color(0xFF9FB3C2)),
              _c(const Color(0xFF6E8396)),
            ]).createShader(mirror.outerRect));

    final idle = 0.08 * math.sin(t * 2.3) * (scene.moving ? 1 : 0.2);
    final since = t - motion.kickAt;
    final kick = since >= 0 && since < 6
        ? 0.6 * math.exp(-since * 1.2) * math.sin(since * 8)
        : 0.0;
    final angle = idle + kick;
    final pivot = Offset(w * 0.5, mirror.bottom);
    final len = h * 0.045;
    final egg = pivot + Offset(math.sin(angle), math.cos(angle)) * len;
    canvas.drawLine(
        pivot,
        egg,
        Paint()
          ..strokeWidth = 1
          ..color = _c(const Color(0xFF8A5A3C)));
    canvas
      ..save()
      ..translate(egg.dx, egg.dy + h * 0.022)
      ..rotate(-angle)
      ..drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: h * 0.026, height: h * 0.034),
          Paint()..color = _c(_Palette.eggYellow))
      ..drawOval(
          Rect.fromCenter(
              center: Offset(-h * 0.006, -h * 0.01),
              width: h * 0.01,
              height: h * 0.014),
          Paint()..color = Colors.white.withValues(alpha: 0.6))
      ..restore();
  }

  @override
  bool shouldRepaint(_CabinPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.layout.size != layout.size;
}
