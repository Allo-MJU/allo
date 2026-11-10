part of '../window_view.dart';

/// 창밖 사람. 옆창은 옆모습, 앞유리 인도는 앞·뒷모습으로 그린다.
///
/// 비율은 실제 사람(머리 ≈ 키의 1/7)에 맞추고, 걸을 때 다리·팔이 반대로 흔들리며
/// 무릎·팔꿈치가 굽는다. 몸 뒤쪽 팔다리는 한 톤 어둡게 칠해 입체감을 낸다.
/// 생김새(피부·머리·옷·소품·키)는 [seed] 로 고정해 같은 사람이 계속 같은 모습이다.
class _Look {
  _Look(int seed)
      : skin = _skins[seed % _skins.length],
        hair = _hairs[(seed ~/ 3) % _hairs.length],
        shirt = _shirts[(seed ~/ 5) % _shirts.length],
        pants = _pants[(seed ~/ 7) % _pants.length],
        kid = _rand(seed, 201) < 0.2,
        longHair = _rand(seed, 202) < 0.4,
        backpack = _rand(seed, 203) < 0.3,
        hat = _rand(seed, 204) < 0.15,
        bag = _rand(seed, 205) < 0.25;

  final Color skin, hair, shirt, pants;
  final bool kid, longHair, backpack, hat, bag;

  static const _skins = [
    Color(0xFFF1C7A5),
    Color(0xFFE0A97E),
    Color(0xFFC68A5E),
    Color(0xFF8D5A3B),
  ];
  static const _hairs = [
    Color(0xFF2B211C),
    Color(0xFF4A3426),
    Color(0xFF7A5A3A),
    Color(0xFF1C1C1C),
    Color(0xFFC9A46A),
  ];
  static const _shirts = [
    Color(0xFFE2614B),
    Color(0xFF4A90D0),
    Color(0xFFF2C14E),
    Color(0xFF58D8A0),
    Color(0xFFF1E6CF),
    Color(0xFFB487D8),
    Color(0xFF3F7D5A),
  ];
  static const _pants = [
    Color(0xFF3B4A5C),
    Color(0xFF2E3440),
    Color(0xFF6B5B4A),
    Color(0xFF4F6F8F),
    Color(0xFF8A8F96),
  ];
}

Color _dark(Color c, [double t = 0.28]) => Color.lerp(c, Colors.black, t)!;

/// 두 마디 팔다리. [a] 는 위 마디가 수직에서 벌어진 각도, [bend] 는 아래 마디가 더 굽은 각도.
(Offset, Offset) _limb(
    Offset from, double len1, double len2, double a, double bend, int facing) {
  final mid = from + Offset(math.sin(a) * len1 * facing, math.cos(a) * len1);
  final end = mid +
      Offset(math.sin(a - bend) * len2 * facing, math.cos(a - bend) * len2);
  return (mid, end);
}

/// 옆모습으로 걷는 사람. [feet] 는 발이 닿는 땅, [height] 는 키(픽셀),
/// [phase] 는 걸음 주기(라디안), [facing] 은 1 이면 오른쪽, -1 이면 왼쪽을 본다.
void _walkerSide(
    Canvas canvas, Offset feet, double height, double phase, int seed,
    {int facing = 1, bool umbrella = false, Color Function(Color)? tint}) {
  final look = _Look(seed);
  final h = height * (look.kid ? 0.66 : 1.0);
  final t = tint ?? (Color c) => c;
  final stride = 0.42;
  // 걸음에 따라 몸이 살짝 오르내린다 (두 발이 벌어질 때 가장 낮다)
  final bob = (math.cos(phase * 2)).abs() * h * 0.015;
  final hip = feet + Offset(0, -h * 0.5 + bob);
  final shoulder = feet + Offset(h * 0.02 * facing, -h * 0.81 + bob);
  final legW = h * 0.07, armW = h * 0.05;
  Paint stroke(Color c, double w) => Paint()
    ..color = t(c)
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  void leg(double a, bool far) {
    // 앞으로 내딛는 다리는 펴지고, 뒤로 차는 다리는 무릎이 굽는다
    final bend = a < 0 ? 0.6 * (-a / stride) : 0.08;
    final (knee, foot) = _limb(hip, h * 0.25, h * 0.25, a, bend, facing);
    final c = far ? _dark(look.pants) : look.pants;
    canvas.drawPath(
        Path()
          ..moveTo(hip.dx, hip.dy)
          ..lineTo(knee.dx, knee.dy)
          ..lineTo(foot.dx, foot.dy),
        stroke(c, legW)..strokeJoin = StrokeJoin.round);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                foot.dx - h * 0.02 * facing - (facing < 0 ? h * 0.07 : 0),
                foot.dy - h * 0.025,
                h * 0.07,
                h * 0.035),
            Radius.circular(h * 0.015)),
        Paint()
          ..color = t(far ? const Color(0xFF1E1E1E) : const Color(0xFF2E2A27)));
  }

  void arm(double a, bool far) {
    final (elbow, hand) = _limb(shoulder, h * 0.17, h * 0.16, a, -0.35, facing);
    final c = far ? _dark(look.shirt) : look.shirt;
    canvas
      ..drawPath(
          Path()
            ..moveTo(shoulder.dx, shoulder.dy)
            ..lineTo(elbow.dx, elbow.dy)
            ..lineTo(hand.dx, hand.dy),
          stroke(c, armW)..strokeJoin = StrokeJoin.round)
      ..drawCircle(hand, armW * 0.55,
          Paint()..color = t(far ? _dark(look.skin) : look.skin));
  }

  final swing = math.sin(phase) * stride;
  // 1. 몸 뒤쪽 팔·다리 (어둡게)
  leg(-swing, true);
  if (!umbrella) arm(swing * 0.9, true);
  // 2. 백팩
  if (look.backpack) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: shoulder + Offset(-h * 0.09 * facing, h * 0.13),
                width: h * 0.09,
                height: h * 0.2),
            Radius.circular(h * 0.03)),
        Paint()..color = t(_Look._shirts[(seed + 3) % _Look._shirts.length]));
  }
  // 3. 몸통: 엉덩이에서 어깨까지, 앞쪽이 밝고 뒤쪽이 어둡다
  final torso = Path()
    ..moveTo(hip.dx - h * 0.07, hip.dy + h * 0.02)
    ..lineTo(hip.dx + h * 0.07, hip.dy + h * 0.02)
    ..lineTo(shoulder.dx + h * 0.075, shoulder.dy + h * 0.02)
    ..quadraticBezierTo(shoulder.dx, shoulder.dy - h * 0.035,
        shoulder.dx - h * 0.075, shoulder.dy + h * 0.02)
    ..close();
  canvas.drawPath(torso, Paint()..color = t(look.shirt));
  canvas.drawPath(
      Path()
        ..moveTo(hip.dx - h * 0.07 * facing, hip.dy + h * 0.02)
        ..lineTo(hip.dx - h * 0.015 * facing, hip.dy + h * 0.02)
        ..lineTo(shoulder.dx - h * 0.02 * facing, shoulder.dy)
        ..lineTo(shoulder.dx - h * 0.075 * facing, shoulder.dy + h * 0.02)
        ..close(),
      Paint()..color = t(_dark(look.shirt, 0.18)));
  // 허리띠 선
  canvas.drawLine(hip + Offset(-h * 0.07, 0), hip + Offset(h * 0.07, 0),
      stroke(_dark(look.pants, 0.3), h * 0.02));
  // 4. 몸 앞쪽 다리
  leg(swing, false);
  // 5. 목·머리
  final head = shoulder + Offset(h * 0.015 * facing, -h * 0.1);
  canvas.drawLine(
      shoulder, head + Offset(0, h * 0.04), stroke(look.skin, h * 0.04));
  canvas.drawOval(
      Rect.fromCenter(center: head, width: h * 0.13, height: h * 0.15),
      Paint()..color = t(look.skin));
  // 머리카락: 뒤통수와 정수리를 덮는다
  final hairPath = Path()
    ..addArc(
        Rect.fromCenter(center: head, width: h * 0.14, height: h * 0.16),
        math.pi * (facing > 0 ? 0.85 : 0.15) - (facing > 0 ? 0 : math.pi * 0.0),
        math.pi * 1.25 * (facing > 0 ? 1 : -1));
  canvas.drawPath(hairPath, Paint()..color = t(look.hair));
  if (look.longHair) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                head.dx - h * 0.075 * facing - (facing > 0 ? 0 : h * 0.05),
                head.dy - h * 0.02,
                h * 0.05,
                h * 0.13),
            Radius.circular(h * 0.025)),
        Paint()..color = t(look.hair));
  }
  if (look.hat) {
    canvas
      ..drawArc(
          Rect.fromCenter(
              center: head + Offset(0, -h * 0.03),
              width: h * 0.15,
              height: h * 0.12),
          math.pi,
          math.pi,
          true,
          Paint()..color = t(_Look._shirts[(seed + 1) % _Look._shirts.length]))
      ..drawLine(
          head + Offset(0, -h * 0.03),
          head + Offset(h * 0.12 * facing, -h * 0.03),
          stroke(_Look._shirts[(seed + 1) % _Look._shirts.length], h * 0.02));
  }
  // 눈과 코끝 (보는 쪽)
  canvas.drawCircle(head + Offset(h * 0.035 * facing, -h * 0.005), h * 0.008,
      Paint()..color = t(const Color(0xFF2B211C)));
  // 6. 몸 앞쪽 팔 (우산을 들면 앞으로 들어 올린다)
  if (umbrella) {
    final (elbow, hand) =
        _limb(shoulder, h * 0.17, h * 0.15, -0.3, -1.6, facing);
    canvas.drawPath(
        Path()
          ..moveTo(shoulder.dx, shoulder.dy)
          ..lineTo(elbow.dx, elbow.dy)
          ..lineTo(hand.dx, hand.dy),
        stroke(look.shirt, armW)..strokeJoin = StrokeJoin.round);
    final top = hand + Offset(-h * 0.03 * facing, -h * 0.42);
    final canopy = _Look._shirts[(seed + 2) % _Look._shirts.length];
    canvas
      ..drawLine(hand + Offset(0, h * 0.03), top,
          stroke(const Color(0xFF2E2E2E), h * 0.012))
      ..drawArc(
          Rect.fromCenter(
              center: top + Offset(0, h * 0.06),
              width: h * 0.6,
              height: h * 0.3),
          math.pi,
          math.pi,
          true,
          Paint()..color = t(canopy))
      ..drawArc(
          Rect.fromCenter(
              center: top + Offset(-h * 0.08, h * 0.06),
              width: h * 0.3,
              height: h * 0.3),
          math.pi * 1.5,
          math.pi * 0.5,
          true,
          Paint()..color = t(_dark(canopy, 0.15)));
  } else {
    arm(-swing * 0.9, false);
    if (look.bag) {
      final (_, hand) =
          _limb(shoulder, h * 0.17, h * 0.16, -swing * 0.9, -0.35, facing);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: hand + Offset(0, h * 0.06),
                  width: h * 0.1,
                  height: h * 0.08),
              Radius.circular(h * 0.015)),
          Paint()..color = t(const Color(0xFF8A5A3C)));
    }
  }
}

/// 앞·뒷모습으로 걷는 사람 (앞유리 인도). 멀리 있어 작게 보이므로 실루엣 위주로 그린다.
void _walkerFront(
    Canvas canvas, Offset feet, double height, double phase, int seed,
    {bool umbrella = false, Color Function(Color)? tint, bool back = false}) {
  final look = _Look(seed);
  final h = height * (look.kid ? 0.66 : 1.0);
  if (h < 3) return;
  final t = tint ?? (Color c) => c;
  final lift = math.sin(phase);
  final bob = lift.abs() * h * 0.015;
  final hipY = feet.dy - h * 0.5 + bob;
  final shY = feet.dy - h * 0.81 + bob;
  final legW = math.max(1.0, h * 0.075), armW = math.max(0.8, h * 0.05);
  Paint stroke(Color c, double w) => Paint()
    ..color = t(c)
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;
  // 다리: 번갈아 들린다
  for (final s in [-1, 1]) {
    final up = math.max(0.0, lift * s) * h * 0.06;
    canvas.drawLine(Offset(feet.dx + s * h * 0.045, hipY),
        Offset(feet.dx + s * h * 0.05, feet.dy - up), stroke(look.pants, legW));
  }
  // 엉덩이(바지 윗부분)
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(feet.dx - h * 0.085, hipY - h * 0.02,
              feet.dx + h * 0.085, hipY + h * 0.07),
          Radius.circular(h * 0.03)),
      Paint()..color = t(look.pants));
  // 몸통: 어깨가 둥글고 허리로 갈수록 좁아진다
  canvas.drawPath(
      Path()
        ..moveTo(feet.dx - h * 0.08, hipY + h * 0.02)
        ..lineTo(feet.dx - h * 0.105, shY + h * 0.06)
        ..quadraticBezierTo(feet.dx - h * 0.105, shY, feet.dx - h * 0.05, shY)
        ..lineTo(feet.dx + h * 0.05, shY)
        ..quadraticBezierTo(
            feet.dx + h * 0.105, shY, feet.dx + h * 0.105, shY + h * 0.06)
        ..lineTo(feet.dx + h * 0.08, hipY + h * 0.02)
        ..close(),
      Paint()..color = t(look.shirt));
  canvas.drawRect(
      Rect.fromLTRB(feet.dx + h * 0.03, shY + h * 0.02, feet.dx + h * 0.1,
          hipY + h * 0.03),
      Paint()..color = t(_dark(look.shirt, 0.15)));
  if (look.backpack && back) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(feet.dx - h * 0.075, shY + h * 0.03,
                feet.dx + h * 0.075, shY + h * 0.22),
            Radius.circular(h * 0.03)),
        Paint()..color = t(_Look._shirts[(seed + 3) % _Look._shirts.length]));
  }
  // 팔: 앞뒤로 흔들려 짧아졌다 길어진다
  for (final s in [-1, 1]) {
    final len = h * (0.3 + 0.03 * lift * s);
    canvas.drawLine(Offset(feet.dx + s * h * 0.11, shY + h * 0.03),
        Offset(feet.dx + s * h * 0.13, shY + len), stroke(look.shirt, armW));
  }
  // 손
  for (final s2 in [-1, 1]) {
    final len = h * (0.3 + 0.03 * lift * s2);
    canvas.drawCircle(Offset(feet.dx + s2 * h * 0.13, shY + len), armW * 0.6,
        Paint()..color = t(look.skin));
  }
  // 목·머리
  canvas.drawLine(Offset(feet.dx, shY + h * 0.01),
      Offset(feet.dx, shY - h * 0.04), stroke(look.skin, h * 0.045));
  final head = Offset(feet.dx, shY - h * 0.09);
  canvas.drawOval(
      Rect.fromCenter(center: head, width: h * 0.13, height: h * 0.15),
      Paint()..color = t(back ? look.hair : look.skin));
  if (!back) {
    canvas.drawArc(
        Rect.fromCenter(center: head, width: h * 0.14, height: h * 0.16),
        math.pi,
        math.pi,
        true,
        Paint()..color = t(look.hair));
  }
  if (umbrella) {
    final c = _Look._shirts[(seed + 2) % _Look._shirts.length];
    canvas.drawArc(
        Rect.fromCenter(
            center: head + Offset(0, -h * 0.12),
            width: h * 0.62,
            height: h * 0.3),
        math.pi,
        math.pi,
        true,
        Paint()..color = t(c));
  }
}

/// 자전거 탄 사람 (옆모습). [base] 는 바퀴가 닿는 땅.
void _cyclistSide(Canvas canvas, Offset base, double s, double age, int seed) {
  final look = _Look(seed);
  final wheel = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, s * 0.07)
    ..color = const Color(0xFF2E2E2E);
  final frame = Paint()
    ..strokeWidth = math.max(1, s * 0.07)
    ..strokeCap = StrokeCap.round
    ..color = _Look._shirts[(seed + 4) % _Look._shirts.length];
  final r = s * 0.42;
  final back = base + Offset(-s * 0.62, -r);
  final front = base + Offset(s * 0.62, -r);
  final crank = base + Offset(0, -r);
  final seat = base + Offset(-s * 0.2, -s * 1.12);
  final bar = base + Offset(s * 0.48, -s * 1.22);
  for (final c in [back, front]) {
    canvas
      ..drawCircle(c, r, wheel)
      ..drawCircle(c, r * 0.12, Paint()..color = const Color(0xFF8A8F96));
  }
  canvas
    ..drawLine(back, crank, frame)
    ..drawLine(crank, seat, frame)
    ..drawLine(seat, bar + Offset(-s * 0.1, s * 0.12), frame)
    ..drawLine(crank, bar + Offset(-s * 0.1, s * 0.12), frame)
    ..drawLine(bar, front, frame)
    ..drawLine(back, seat, frame);
  // 페달을 돌리는 두 다리 (뒤쪽 다리는 어둡게)
  for (final (k, far) in [(math.pi, true), (0.0, false)]) {
    final a = age * 7 + k;
    final pedal = crank + Offset(math.cos(a), math.sin(a)) * s * 0.2;
    final hip = seat + Offset(0, -s * 0.05);
    final mid = Offset.lerp(hip, pedal, 0.5)! + Offset(s * 0.18, -s * 0.12);
    canvas.drawPath(
        Path()
          ..moveTo(hip.dx, hip.dy)
          ..lineTo(mid.dx, mid.dy)
          ..lineTo(pedal.dx, pedal.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.13
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = far ? _dark(look.pants) : look.pants);
  }
  // 몸통은 핸들 쪽으로 기울고, 팔은 핸들을 잡는다
  final shoulder = seat + Offset(s * 0.32, -s * 0.5);
  canvas
    ..drawLine(
        seat + Offset(0, -s * 0.05),
        shoulder,
        Paint()
          ..strokeWidth = s * 0.24
          ..strokeCap = StrokeCap.round
          ..color = look.shirt)
    ..drawLine(
        shoulder,
        bar,
        Paint()
          ..strokeWidth = s * 0.09
          ..strokeCap = StrokeCap.round
          ..color = _dark(look.shirt, 0.1));
  final head = shoulder + Offset(s * 0.12, -s * 0.22);
  canvas
    ..drawCircle(head, s * 0.14, Paint()..color = look.skin)
    // 헬멧
    ..drawArc(
        Rect.fromCircle(center: head + Offset(0, -s * 0.02), radius: s * 0.16),
        math.pi,
        math.pi,
        true,
        Paint()..color = _Look._shirts[(seed + 1) % _Look._shirts.length]);
}
