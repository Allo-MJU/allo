import 'dart:math' as math;
import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import '../theme/allo_colors.dart';

/// D 에셋이 없을 때도 성장과 금 가기 단계를 보여주는 알.
class EggArt extends StatelessWidget {
  const EggArt(
      {super.key,
      required this.tier,
      required this.progress,
      this.size = 180,
      this.color = AlloColors.shellYellow,
      this.hatchFrame});
  final EggTier tier;
  final double progress;
  final double size;
  final Color color;
  final int? hatchFrame;

  @override
  Widget build(BuildContext context) {
    final stage = progress < 1 / 3
        ? 1
        : progress < 2 / 3
            ? 2
            : 3;
    final path = hatchFrame == null
        ? 'assets/egg/egg_${tier.name}_$stage.png'
        : 'assets/egg/hatch_$hatchFrame.png';
    return Semantics(
      image: true,
      label: hatchFrame == null ? '성장 $stage단계 알' : '알이 깨어나는 중',
      child: ExcludeSemantics(
          child: Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Center(
          child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _EggPainter(stage, hatchFrame, color),
              )),
        ),
      )),
    );
  }
}

class _EggPainter extends CustomPainter {
  _EggPainter(this.stage, this.frame, this.color);
  final int stage;
  final int? frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final side = math.min(size.width, size.height);
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 200);
    final glow = frame != null && frame! >= 4;
    if (glow) {
      final paint = Paint()..color = color.withValues(alpha: .25);
      canvas.drawCircle(const Offset(100, 100), 85, paint);
      paint.color = color;
      for (var i = 0; i < 12; i++) {
        final angle = i * math.pi / 6;
        canvas.drawLine(
            Offset(100 + 58 * math.cos(angle), 100 + 58 * math.sin(angle)),
            Offset(100 + 90 * math.cos(angle), 100 + 90 * math.sin(angle)),
            paint
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round);
      }
    }
    final egg = Path()
      ..moveTo(100, 22)
      ..cubicTo(65, 22, 40, 92, 40, 126)
      ..cubicTo(40, 192, 160, 192, 160, 126)
      ..cubicTo(160, 92, 135, 22, 100, 22)
      ..close();
    canvas.drawOval(const Rect.fromLTWH(48, 176, 104, 12),
        Paint()..color = color.withValues(alpha: .15));
    canvas.drawPath(
        egg,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFFFF9E6), glow ? Colors.white : color],
          ).createShader(const Rect.fromLTWH(40, 22, 120, 160)));
    canvas.drawOval(const Rect.fromLTWH(67, 49, 15, 30),
        Paint()..color = Colors.white.withValues(alpha: .65));
    for (var i = 0; i < stage + 1; i++) {
      canvas.drawCircle(Offset(72 + (i % 2) * 48, 105 + (i ~/ 2) * 30),
          6 + stage.toDouble(), Paint()..color = color.withValues(alpha: .55));
    }
    if (frame != null && frame! <= 3) {
      final crack = Path()
        ..moveTo(98, 45)
        ..lineTo(88, 69)
        ..lineTo(108, 86);
      if (frame! >= 2) {
        crack
          ..lineTo(88, 109)
          ..lineTo(112, 126);
      }
      if (frame! >= 3) {
        crack
          ..lineTo(94, 148)
          ..lineTo(102, 173);
      }
      canvas.drawPath(
          crack,
          Paint()
            ..color = const Color(0xFF66533D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EggPainter old) =>
      old.stage != stage || old.frame != frame || old.color != color;
}
