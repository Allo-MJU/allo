import 'package:flutter/material.dart';

/// 뒷좌석에서 본 앞좌석. 머리받침과 등받이 경계가 캐릭터의 손 앵커다.
class SeatBack extends StatelessWidget {
  const SeatBack({super.key, required this.headHeight});
  final double headHeight;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: CustomPaint(painter: _SeatBackPainter(headHeight)),
        ),
      );
}

class _SeatBackPainter extends CustomPainter {
  const _SeatBackPainter(this.headHeight);
  final double headHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final shoulder = headHeight;
    final h = size.height;
    final body = Path()
      ..moveTo(w * .13, shoulder)
      ..quadraticBezierTo(w * .03, shoulder + 8, w * .04, shoulder + 28)
      ..lineTo(0, h - 7)
      ..quadraticBezierTo(w * .5, h + 3, w, h - 7)
      ..lineTo(w * .96, shoulder + 28)
      ..quadraticBezierTo(w * .97, shoulder + 8, w * .87, shoulder)
      ..close();
    canvas.drawShadow(body, Colors.black.withValues(alpha: .45), 5, false);

    // 두 금속 지지봉과 가죽 머리받침: 등받이와 분리해 뒷좌석 시점을 만든다.
    for (final x in [w * .34, w * .66]) {
      final rod = Rect.fromLTWH(x - 2, shoulder * .5, 4, shoulder * .55);
      canvas.drawRect(
          rod,
          Paint()
            ..shader = const LinearGradient(colors: [
              Color(0xFF66716F),
              Color(0xFFD0D5CA),
              Color(0xFF59645F),
            ]).createShader(rod));
    }
    final head = RRect.fromRectAndRadius(
        Rect.fromLTRB(w * .21, 1, w * .79, shoulder * .72),
        Radius.circular(w * .09));
    canvas.drawShadow(Path()..addRRect(head), Colors.black38, 3, false);
    canvas.drawRRect(
        head,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF636B5D), Color(0xFF3F473E), Color(0xFF29332F)],
          ).createShader(head.outerRect));
    canvas.drawRRect(
        head.deflate(4),
        Paint()
          ..color = const Color(0xFF8C9380)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    final bounds = Rect.fromLTRB(0, shoulder, w, h);
    canvas.drawPath(
        body,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF737B69), Color(0xFF424D43), Color(0xFF252F2C)],
          ).createShader(bounds));
    canvas.save();
    canvas.clipPath(body);
    // 중앙 천 패널과 두툼한 양옆 지지대.
    final panel = RRect.fromRectAndRadius(
        Rect.fromLTRB(w * .18, shoulder + 10, w * .82, h + 12),
        Radius.circular(w * .12));
    canvas.drawRRect(
        panel,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF364039), Color(0xFF56614F), Color(0xFF364039)],
          ).createShader(panel.outerRect));
    final seam = Paint()
      ..color = const Color(0xFF8C937D)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(panel.deflate(4), seam);
    for (double y = shoulder + 22; y < h - 12; y += 7) {
      canvas.drawLine(Offset(w * .22, y), Offset(w * .22, y + 3), seam);
      canvas.drawLine(Offset(w * .78, y), Offset(w * .78, y + 3), seam);
    }
    // 등받이 뒤 수납 포켓. 입구가 살짝 벌어진 모습과 하단 곡률.
    final pocketTop = shoulder + (h - shoulder) * .60;
    final pocket = Path()
      ..moveTo(w * .23, pocketTop)
      ..quadraticBezierTo(w * .5, pocketTop + 7, w * .77, pocketTop)
      ..lineTo(w * .74, h - 12)
      ..quadraticBezierTo(w * .5, h - 5, w * .26, h - 12)
      ..close();
    canvas.drawPath(pocket, Paint()..color = const Color(0xFF303C34));
    canvas.drawPath(pocket, seam);
    canvas.drawPath(
        Path()
          ..moveTo(w * .23, pocketTop)
          ..quadraticBezierTo(w * .5, pocketTop + 7, w * .77, pocketTop),
        Paint()
          ..color = const Color(0xFF17231F)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke);
    canvas.restore();
    canvas.drawPath(
        body,
        Paint()
          ..color = const Color(0xFF28352D)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
    // 캐릭터가 붙잡을 등받이 윗단의 얇은 하이라이트.
    canvas.drawLine(
        Offset(w * .14, shoulder + 2),
        Offset(w * .86, shoulder + 2),
        Paint()
          ..color = const Color(0xFFA3AA91)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SeatBackPainter oldDelegate) =>
      oldDelegate.headHeight != headHeight;
}
