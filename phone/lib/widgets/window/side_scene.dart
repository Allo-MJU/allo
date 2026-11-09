part of '../window_view.dart';

/// 지브리풍 나무: 그늘색 잎 덩어리 위에 해 쪽(왼쪽 위)으로 밝은 잎 덩어리를 얹는다.
void _tree(Canvas canvas, double x, double base, double size, int seed,
    Paint trunk, Paint dark, Paint lit) {
  canvas.drawRect(
      Rect.fromLTWH(
          x - size * 0.05, base - size * 0.45, size * 0.1, size * 0.45),
      trunk);
  for (var k = 0; k < 6; k++) {
    final a = k / 6 * math.pi * 2 + _rand(seed, k) * 0.6;
    final r = size * (0.2 + _rand(seed, k + 10) * 0.1);
    canvas.drawCircle(
        Offset(x + math.cos(a) * size * 0.22,
            base - size * 0.72 + math.sin(a) * size * 0.2),
        r,
        dark);
  }
  for (var k = 0; k < 4; k++) {
    final r = size * (0.12 + _rand(seed, k + 20) * 0.07);
    canvas.drawCircle(
        Offset(x - size * (0.14 - k * 0.07), base - size * (0.88 - k * 0.04)),
        r,
        lit);
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.motion, {this.mirror = false})
      : super(repaint: motion);

  final WindowScene scene;
  final _Motion motion;

  /// 오른쪽 옆창: 풍경을 좌우로 뒤집어 왼쪽에서 오른쪽(차 뒤쪽)으로 흐르게 한다.
  final bool mirror;

  // 겹마다 1m 당 흐르는 픽셀. 멀수록 느리다.
  static const _cloudPx = 0.25;
  static const _farPx = 0.6;
  static const _midPx = 3.0;
  static const _nearPx = 12.0;

  Size? _bandSize;
  final _bands = <String, Paint>{};

  /// 화면 크기에 묶인 세로 그라디언트. 크기가 같으면 매 프레임 다시 만들지 않는다.
  Paint _band(String key, Size size, Rect r, List<Color> colors,
      [List<double>? stops]) {
    if (_bandSize != size) {
      _bands.clear();
      _bandSize = size;
    }
    return _bands.putIfAbsent(
        key,
        () => Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: stops,
          ).createShader(r));
  }

  List<Color> get _sky => scene.night
      ? _Palette.night
      : scene.rainLevel > 0
          ? _Palette.rain
          : _Palette.day;

  /// 지평선 색. 먼 것일수록 이 색에 묻힌다(대기 원근).
  Color get _haze => _sky[2];

  Color _far(Color c, double t) => Color.lerp(c, _haze, t)!;

  @override
  void paint(Canvas canvas, Size size) {
    if (!mirror) return _paintScene(canvas, size);
    canvas
      ..save()
      ..translate(size.width, 0)
      ..scale(-1, 1);
    _paintScene(canvas, size);
    canvas.restore();
  }

  void _paintScene(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final m = motion.meters;

    if (scene.kind == SceneKind.tunnel) {
      _tunnel(canvas, size, m);
      return;
    }

    final all = Offset.zero & size;
    canvas.drawRect(all, _band('sky', size, all, _sky, const [0, 0.45, 0.78]));
    if (scene.night) {
      _stars(canvas, w, h);
    } else if (scene.rainLevel == 0) {
      // 왼쪽 위 햇빛 번짐
      canvas.drawCircle(
          Offset(w * 0.12, h * 0.05),
          h * 0.9,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0x66FFF6DA),
              const Color(0x00FFF6DA),
            ]).createShader(Rect.fromCircle(
                center: Offset(w * 0.12, h * 0.05), radius: h * 0.9)));
    }
    _clouds(canvas, w, h, m);

    switch (scene.kind) {
      case SceneKind.coast:
        _coast(canvas, size, m);
      case SceneKind.mountain:
        _mountain(canvas, size, m);
      case SceneKind.city:
        _city(canvas, size, m);
      case SceneKind.road:
      case SceneKind.tunnel:
        _road(canvas, size, m);
    }

    _near(canvas, size, m);

    if (scene.night) {
      // 땅 쪽을 푸른 밤빛으로 곱한다. 하늘 위쪽(흰색 = 변화 없음)은 그대로 둔다
      canvas.drawRect(
          all,
          _band('veil', size, all, const [
            Color(0xFFFFFFFF),
            Color(0xFF6B7BB8),
            Color(0xFF3E4C86),
          ], const [
            0.2,
            0.5,
            1,
          ])
            ..blendMode = BlendMode.multiply);
      if (scene.kind == SceneKind.city) _cityLights(canvas, size, m);
    }
    if (scene.rainLevel > 0) {
      // 빗속 공기: 전체를 살짝 회색 안개로 덮는다
      canvas.drawRect(
          all,
          Paint()
            ..color = _haze.withValues(alpha: 0.08 + scene.rainLevel * 0.05));
    }
  }

  void _stars(Canvas canvas, double w, double h) {
    final p = Paint()..color = const Color(0xFFFFF4D6);
    for (var i = 0; i < 46; i++) {
      final r = 0.6 + _rand(i, 5) * 1.3;
      p.color =
          const Color(0xFFFFF4D6).withValues(alpha: 0.4 + _rand(i, 6) * 0.6);
      canvas.drawCircle(Offset(_rand(i, 3) * w, _rand(i, 4) * h * 0.5), r, p);
    }
    final moon = Offset(w * 0.8, h * 0.18);
    canvas
      ..drawCircle(
          moon,
          h * 0.28,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0x40FFF1C8),
              const Color(0x00FFF1C8),
            ]).createShader(Rect.fromCircle(center: moon, radius: h * 0.28)))
      ..drawCircle(moon, 13, Paint()..color = const Color(0xFFFFF3D0))
      ..drawCircle(moon + const Offset(-3, -3), 4,
          Paint()..color = const Color(0x22B8A57A))
      ..drawCircle(moon + const Offset(4, 3), 2.6,
          Paint()..color = const Color(0x22B8A57A));
  }

  /// 뭉게구름: 밑이 평평한 덩어리를 그늘색으로 깔고, 해 쪽(왼쪽 위)으로 조금씩 밀어
  /// 줄인 같은 덩어리를 밝은색으로 얹는다. 애니메이션 배경의 2단 셀 셰이딩이다.
  void _clouds(Canvas canvas, double w, double h, double m) {
    final rainy = scene.rainLevel > 0;
    final (lit, shade) = scene.night
        ? (const Color(0xFF41548A), const Color(0xFF26355F))
        : rainy
            ? (const Color(0xFFBCC4CC), const Color(0xFF8C97A4))
            : (const Color(0xFFFFFFFF), const Color(0xFFC3CCE2));
    final shadePaint = Paint()..color = shade;
    final litPaint = Paint()..color = lit;
    // 지평선 근처의 옅은 띠구름: 멀리 있어서 느리게 흐르고 하늘색에 묻힌다
    final wisp = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
      ..color =
          Color.lerp(lit, _haze, 0.3)!.withValues(alpha: rainy ? 0.35 : 0.7);
    _repeat(w, 190, m * _cloudPx * 0.5 + motion.seconds * 1.5, (x, i) {
      if (_rand(i, 41) < 0.3) return;
      final ww = 60 + _rand(i, 42) * 110;
      final y = h * (0.46 + _rand(i, 43) * 0.1);
      canvas
        ..drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, ww, 5 + _rand(i, 44) * 4),
                const Radius.circular(5)),
            wisp)
        ..drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x + ww * 0.2, y - 4, ww * 0.45, 6),
                const Radius.circular(4)),
            wisp);
    });
    _repeat(w, rainy ? 230 : 280, m * _cloudPx + motion.seconds * 3, (x, i) {
      if (!rainy && _rand(i, 11) < 0.3) return;
      // 크기는 창 높이에 비례한다. 창이 낮아도 구름 꼭대기가 잘리지 않게 한다
      final cw =
          h * (rainy ? 0.75 + _rand(i, 12) * 0.4 : 0.36 + _rand(i, 12) * 0.2);
      final ch = cw * (rainy ? 0.3 : 0.5);
      final cx = x + _rand(i, 14) * 70;
      final by = math.max(
          h * (rainy ? 0.3 : 0.33 + _rand(i, 13) * 0.1), ch * 1.35 + 2);
      const n = 9;
      final lobes = <(Offset, double)>[];
      for (var k = 0; k < n; k++) {
        // 가운데가 높은 돔 곡선을 따라 서로 겹치게 놓는다
        final t = k / (n - 1);
        final dome = math.sin(t * math.pi);
        final j = 0.85 + _rand(i * 13 + k, 31) * 0.3;
        lobes.add((
          Offset(cx + cw * (0.1 + t * 0.8), by - ch * (0.25 + 0.45 * dome * j)),
          ch * (0.22 + 0.25 * dome) * j,
        ));
      }
      // 꼭대기에 작은 봉우리 두세 개를 더 얹어 뭉게뭉게하게 만든다
      for (var k = 0; k < 3; k++) {
        if (rainy) break;
        final t = 0.3 + k * 0.2 + (_rand(i, k + 33) - 0.5) * 0.1;
        lobes.add((
          Offset(cx + cw * t, by - ch * (0.8 + _rand(i, k + 34) * 0.15)),
          ch * (0.2 + _rand(i, k + 35) * 0.08),
        ));
      }
      final body = Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(cx + cw * 0.04, by - ch * 0.32, cx + cw * 0.96, by),
            Radius.circular(ch * 0.16)));
      for (final (c, r) in lobes) {
        body.addOval(Rect.fromCircle(center: c, radius: r));
      }
      canvas
        ..save()
        ..clipPath(body)
        ..drawPath(body, shadePaint);
      for (final (c, r) in lobes) {
        canvas.drawCircle(c + Offset(-r * 0.22, -r * 0.24), r * 0.86, litPaint);
      }
      canvas.restore();
    });
  }

  /// 먼 산 능선 한 겹. [top] 은 가장 높은 봉우리, [base] 는 능선이 끝나는 높이.
  void _range(Canvas canvas, Size size, double offset, int seed, double top,
      double base, Color color, String key,
      {double scale = 1, double mistAt = 1, bool wooded = false}) {
    final w = size.width;
    final h = size.height;
    final path = _profile(w, h,
        (x) => base - (base - top) * _ridge(x + offset, seed, scale: scale));
    final r = Rect.fromLTRB(0, top, w, base + (h - base) * mistAt);
    canvas.drawPath(path, _band(key, size, r, [color, _far(color, 0.55)]));
    if (wooded) {
      // 산허리를 덮은 숲: 능선보다 조금 아래에서 잔 굴곡이 많은 더 짙은 면
      final depth = (base - top) * 0.28;
      canvas.drawPath(
          _profile(
              w,
              h,
              (x) =>
                  base -
                  (base - top) * _ridge(x + offset, seed, scale: scale) +
                  depth +
                  depth * 0.5 * _noise((x + offset) / 9, seed + 40),
              step: 3),
          Paint()
            ..color = Color.lerp(color, _Palette.forest, 0.35)!
                .withValues(alpha: 0.7));
    }
    // 해 쪽 능선에 가는 림라이트
    canvas.drawPath(
        _rim(
            w,
            (x) =>
                base - (base - top) * _ridge(x + offset, seed, scale: scale)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color =
              Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: 0.6));
  }

  Path _rim(double w, double Function(double x) yAt) {
    final p = Path()..moveTo(0, yAt(0));
    for (var x = 5.0; x <= w; x += 5) {
      p.lineTo(x, yAt(x));
    }
    return p;
  }

  /// 둥글둥글한 잎 덩어리가 이어진 숲 띠.
  void _forestBand(Canvas canvas, Size size, double offset, double y,
      double bump, Color dark, Color lit) {
    final w = size.width;
    final h = size.height;
    final dp = Paint()..color = dark;
    final mid = Paint()..color = Color.lerp(dark, lit, 0.45)!;
    final lp = Paint()..color = lit;
    canvas.drawRect(Rect.fromLTRB(0, y, w, h), dp);
    _repeat(w, bump * 0.8, offset, (x, i) {
      final r = bump * (0.5 + _rand(i, 61) * 0.6);
      final c = Offset(x + _rand(i, 63) * bump * 0.4,
          y - r * 0.25 + _rand(i, 62) * bump * 0.35);
      canvas.drawCircle(c, r, dp);
      // 잎 덩어리 위쪽만 햇빛을 받는다: 중간색 → 밝은색 두 단계
      canvas
        ..save()
        ..clipRect(Rect.fromLTRB(c.dx - r, c.dy - r, c.dx + r, c.dy + r * 0.1))
        ..drawCircle(c + Offset(-r * 0.18, -r * 0.12), r * 0.78, mid)
        ..restore()
        ..drawCircle(c + Offset(-r * (0.2 + _rand(i, 64) * 0.2), -r * 0.45),
            r * (0.28 + _rand(i, 65) * 0.14), lp);
    });
  }

  void _mountain(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    _range(canvas, size, m * _farPx * 0.6, 7, h * 0.12, h * 0.56,
        _far(_Palette.farBlue, 0.25), 'm1',
        scale: 1.4);
    _range(canvas, size, m * _farPx, 8, h * 0.3, h * 0.66,
        _far(_Palette.midGreen, 0.25), 'm2',
        wooded: true);
    // 골짜기 안개
    final mist = Rect.fromLTRB(0, h * 0.55, w, h * 0.72);
    canvas.drawRect(
        mist,
        _band('mist', size, mist, [
          _haze.withValues(alpha: 0),
          _haze.withValues(alpha: 0.55),
          _haze.withValues(alpha: 0)
        ]));
    _forestBand(canvas, size, m * _midPx * 0.3, h * 0.64, h * 0.04,
        _far(_Palette.forest, 0.35), _far(_Palette.forestLit, 0.35));
    _forestBand(canvas, size, m * _midPx * 0.5, h * 0.7, h * 0.065,
        _Palette.forest, _Palette.forestLit);
    final ground = Rect.fromLTRB(0, h * 0.8, w, h);
    canvas.drawRect(
        ground,
        _band('meadow', size, ground,
            const [_Palette.meadow, _Palette.meadowDeep]));
    // 들꽃
    const petals = [
      Color(0xFFFFFFFF),
      Color(0xFFFFE27A),
      Color(0xFFF6A35B),
      Color(0xFFE79BC1)
    ];
    _repeat(w, 9, m * _midPx, (x, i) {
      if (_rand(i, 161) < 0.4) return;
      canvas.drawCircle(
          Offset(x + _rand(i, 162) * 6, h * (0.81 + _rand(i, 163) * 0.06)),
          h * 0.008,
          Paint()..color = petals[i % 4]);
    });
    final trunk = Paint()..color = _Palette.trunk;
    final dark = Paint()..color = _Palette.forest;
    final lit = Paint()..color = _Palette.forestLit;
    _repeat(w, 210, m * _midPx, (x, i) {
      if (_rand(i, 2) < 0.2) return;
      _tree(canvas, x + _rand(i, 3) * 80, h * 0.79,
          h * (0.2 + _rand(i, 4) * 0.08), i, trunk, dark, lit);
    });
  }

  void _coast(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.55;
    // 먼 섬
    _repeat(w, 340, m * _farPx, (x, i) {
      if (_rand(i, 9) < 0.35) return;
      final iw = 90 + _rand(i, 1) * 140;
      final ih = 14 + _rand(i, 2) * 26;
      final p = _profile(iw, horizon + 1, (t) {
        final u = t / iw;
        return horizon -
            ih *
                math.sin(u.clamp(0, 1) * math.pi) *
                (0.75 + 0.25 * _noise(t / 16, i));
      });
      canvas
        ..save()
        ..translate(x, 0)
        ..drawPath(p, Paint()..color = _far(_Palette.midGreen, 0.4))
        ..restore();
    });
    final sea = Rect.fromLTRB(0, horizon, w, h);
    canvas.drawRect(sea,
        _band('sea', size, sea, const [_Palette.seaHorizon, _Palette.sea]));
    canvas.drawLine(
        Offset(0, horizon),
        Offset(w, horizon),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1);
    // 수평선의 돛단배·고깃배와 섬 위 등대
    _repeat(w, 120, m * _farPx * 0.8 + motion.seconds * 1.2, (x, i) {
      if (_rand(i, 151) < 0.4) return;
      final y = horizon + 4 + _rand(i, 152) * h * 0.06;
      final s = h * (0.025 + _rand(i, 153) * 0.025);
      canvas
        ..drawPath(
            Path()
              ..moveTo(x - s * 1.4, y)
              ..lineTo(x + s * 1.4, y)
              ..lineTo(x + s, y + s * 0.45)
              ..lineTo(x - s, y + s * 0.45)
              ..close(),
            Paint()..color = _far(const Color(0xFF5A4636), 0.3))
        ..drawPath(
            Path()
              ..moveTo(x, y - s * 2.6)
              ..lineTo(x + s * 1.2, y - s * 0.1)
              ..lineTo(x, y - s * 0.1)
              ..close(),
            Paint()..color = _far(Colors.white, 0.15));
    });
    _repeat(w, 520, m * _farPx, (x, i) {
      if (_rand(i, 154) < 0.5) return;
      final b = Offset(x + 120, horizon - h * 0.02);
      final s = h * 0.012;
      canvas
        ..drawRect(Rect.fromLTRB(b.dx - s, b.dy - s * 9, b.dx + s, b.dy),
            Paint()..color = _far(Colors.white, 0.2))
        ..drawRect(
            Rect.fromLTRB(b.dx - s, b.dy - s * 6, b.dx + s, b.dy - s * 4),
            Paint()..color = _far(const Color(0xFFD9473A), 0.2));
    });
    // 반짝이는 물결: 가까울수록 굵고 빠르다
    final glint = Paint()..strokeCap = StrokeCap.round;
    for (var row = 0; row < 5; row++) {
      final y = horizon + 6 + row * row * 4.5 + row * 4;
      glint
        ..strokeWidth = 1 + row * 0.5
        ..color = Colors.white.withValues(alpha: 0.35 + row * 0.08);
      _repeat(w, 46 + row * 14, m * _midPx * (0.3 + row * 0.25), (x, i) {
        if (_rand(i, row + 70) < 0.35) return;
        final len = 6 + _rand(i, row) * (8 + row * 5);
        final xx = x + _rand(i, row + 5) * 30;
        canvas.drawLine(Offset(xx, y), Offset(xx + len, y), glint);
      });
    }
    // 앞쪽 모래 언덕과 풀
    final dune =
        _profile(w, h, (x) => h * 0.8 - 10 * _noise((x + m * _midPx) / 90, 31));
    final duneR = Rect.fromLTRB(0, h * 0.76, w, h);
    canvas.drawPath(dune,
        _band('sand', size, duneR, const [_Palette.sand, _Palette.sandDeep]));
    final grass = Paint()
      ..color = _Palette.meadowDeep
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    _repeat(w, 26, m * _midPx, (x, i) {
      if (_rand(i, 33) < 0.5) return;
      final base = h * 0.8 - 10 * _noise((x + m * _midPx) / 90, 31) + 6;
      for (var k = -1; k <= 1; k++) {
        canvas.drawLine(Offset(x, base),
            Offset(x + k * 5 + 2, base - 10 - _rand(i, k + 35) * 8), grass);
      }
    });
  }

  /// 마을 건물 한 채의 위치·크기. 밤 불빛도 같은 값을 쓴다.
  (Rect, int, bool) _house(int i, double x, double h) {
    final bw = 54 + _rand(i, 1) * 36;
    final top = h * (0.32 + _rand(i, 2) * 0.24);
    return (
      Rect.fromLTRB(x + 6, top, x + 6 + bw, h * 0.88),
      (_rand(i, 6) * _Palette.walls.length).floor() % _Palette.walls.length,
      _rand(i, 7) < 0.45, // 박공지붕
    );
  }

  static const _housePeriod = 104.0;

  void _city(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    // 먼 시가지: 안개에 묻힌 사각 실루엣
    final farA = Paint()..color = _far(const Color(0xFF8DA2B6), 0.45);
    final farB = Paint()..color = _far(const Color(0xFF7D93A8), 0.3);
    _repeat(w, 30, m * _farPx * 0.6, (x, i) {
      final top = h * (0.3 + _rand(i, 1) * 0.22);
      canvas.drawRect(Rect.fromLTRB(x, top, x + 26, h * 0.7), farA);
    });
    _repeat(w, 44, m * _farPx, (x, i) {
      final top = h * (0.38 + _rand(i, 3) * 0.2);
      canvas.drawRect(Rect.fromLTRB(x, top, x + 38, h * 0.74), farB);
      if (_rand(i, 4) < 0.3) {
        canvas.drawLine(Offset(x + 20, top), Offset(x + 20, top - 12),
            farB..strokeWidth = 1.2);
      }
    });
    // 고층 빌딩 한 겹: 창문 격자가 보인다
    _repeat(w, 64, m * _farPx * 1.8, (x, i) {
      if (_rand(i, 171) < 0.25) return;
      final top = h * (0.12 + _rand(i, 172) * 0.2);
      final bw = 34 + _rand(i, 173) * 20;
      final c = _far(
          const [
            Color(0xFFB9C7D3),
            Color(0xFFD8CFC0),
            Color(0xFF9FB2A6)
          ][i % 3],
          0.3);
      canvas.drawRect(
          Rect.fromLTRB(x, top, x + bw, h * 0.8), Paint()..color = c);
      final win = Paint()..color = _far(_Palette.glassDay, 0.4);
      for (var y = top + 6; y < h * 0.7; y += 9) {
        for (var xx = x + 4; xx < x + bw - 6; xx += 8) {
          canvas.drawRect(Rect.fromLTWH(xx, y, 4, 5), win);
        }
      }
    });
    // 가까운 마을: 밝은 정면 + 그늘진 옆면 + 지붕
    final win = Paint()..color = _Palette.glassDay;
    final winLit = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final roof = Paint()..color = _Palette.roof;
    final roofShade = Paint()..color = _Palette.roofShade;
    _repeat(w, _housePeriod, m * _midPx, (x, i) {
      final (r, c, gable) = _house(i, x, h);
      final (face, shade) = _Palette.walls[c];
      final side = r.width * 0.22;
      canvas
        ..drawRect(Rect.fromLTRB(r.right - side, r.top, r.right, r.bottom),
            Paint()..color = shade)
        ..drawRect(Rect.fromLTRB(r.left, r.top, r.right - side, r.bottom),
            Paint()..color = face);
      if (gable) {
        canvas
          ..drawPath(
              Path()
                ..moveTo(r.left - 5, r.top + 2)
                ..lineTo(r.left + (r.width - side) / 2, r.top - 20)
                ..lineTo(r.right - side + 5, r.top + 2)
                ..close(),
              roof)
          ..drawPath(
              Path()
                ..moveTo(r.left + (r.width - side) / 2, r.top - 20)
                ..lineTo(r.right + 3, r.top - 14)
                ..lineTo(r.right + 3, r.top + 2)
                ..lineTo(r.right - side + 5, r.top + 2)
                ..close(),
              roofShade);
      } else {
        // 평지붕 난간과 물탱크
        canvas.drawRect(
            Rect.fromLTRB(r.left - 2, r.top - 4, r.right + 1, r.top),
            Paint()..color = shade);
        if (_rand(i, 8) < 0.5) {
          canvas.drawRect(
              Rect.fromLTWH(r.left + 10, r.top - 14, 14, 10), roofShade);
        }
      }
      for (var wy = r.top + 12; wy < r.bottom - 16; wy += 20) {
        for (var wx = r.left + 8; wx < r.right - side - 12; wx += 16) {
          canvas
            ..drawRect(Rect.fromLTWH(wx, wy, 8, 10), win)
            ..drawRect(Rect.fromLTWH(wx, wy, 3, 10), winLit);
        }
      }
    });
    // 길가 가로수
    final trunk = Paint()..color = _Palette.trunk;
    final dark = Paint()..color = _Palette.forest;
    final lit = Paint()..color = _Palette.forestLit;
    _repeat(w, 170, m * _midPx, (x, i) {
      if (_rand(i, 12) < 0.2) return;
      _tree(canvas, x + 40, h * 0.9, h * 0.15, i + 300, trunk, dark, lit);
    });
  }

  /// 밤 마을: 창문 일부에 따뜻한 불을 켜고 번짐을 준다.
  void _cityLights(Canvas canvas, Size size, double m) {
    final h = size.height;
    final lamp = Paint()..color = _Palette.lamp;
    final glow = Paint()
      ..color = _Palette.lamp.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    _repeat(size.width, _housePeriod, m * _midPx, (x, i) {
      final (r, _, _) = _house(i, x, h);
      final side = r.width * 0.22;
      var k = 0;
      for (var wy = r.top + 12; wy < r.bottom - 16; wy += 20) {
        for (var wx = r.left + 8; wx < r.right - side - 12; wx += 16) {
          if (_rand(i * 31 + k++, 90) < 0.55) {
            final win = Rect.fromLTWH(wx, wy, 8, 10);
            canvas
              ..drawRect(win.inflate(3), glow)
              ..drawRect(win, lamp);
          }
        }
      }
    });
  }

  void _road(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    _range(canvas, size, m * _farPx * 0.5, 17, h * 0.3, h * 0.6,
        _far(_Palette.farBlue, 0.3), 'r1',
        scale: 1.6);
    _range(canvas, size, m * _farPx, 18, h * 0.46, h * 0.66,
        _far(_Palette.midGreen, 0.25), 'r2',
        scale: 1.2, wooded: true);
    // 먼 마을: 언덕 아래 작은 집과 비닐하우스
    final wall = Paint()..color = _far(const Color(0xFFF1E6CF), 0.35);
    final wallShade = Paint()..color = _far(const Color(0xFFCDBFA4), 0.35);
    _repeat(w, 46, m * _farPx * 1.6, (x, i) {
      if (_rand(i, 131) < 0.35) return;
      final y = h * 0.645;
      final s = h * (0.035 + _rand(i, 132) * 0.02);
      if (_rand(i, 133) < 0.3) {
        canvas.drawArc(
            Rect.fromCenter(
                center: Offset(x, y), width: s * 3, height: s * 1.6),
            math.pi,
            math.pi,
            true,
            Paint()..color = _far(const Color(0xFFE8EEF0), 0.3));
        return;
      }
      canvas
        ..drawRect(Rect.fromLTWH(x - s, y - s, s * 2, s), wall)
        ..drawRect(Rect.fromLTWH(x + s * 0.6, y - s, s * 0.4, s), wallShade)
        ..drawPath(
            Path()
              ..moveTo(x - s * 1.3, y - s)
              ..lineTo(x, y - s * 1.9)
              ..lineTo(x + s * 1.3, y - s)
              ..close(),
            Paint()
              ..color = _far(
                  _rand(i, 134) < 0.5 ? _Palette.roof : const Color(0xFF4A7FB0),
                  0.35));
    });
    // 밭: 색이 다른 띠 두 줄
    final field = Rect.fromLTRB(0, h * 0.64, w, h);
    canvas.drawRect(
        field,
        _band('field', size, field,
            const [Color(0xFFA9CB6A), _Palette.meadowDeep]));
    final row = Paint()
      ..color = const Color(0x22355F3A)
      ..strokeWidth = 2;
    for (var y = h * 0.68; y < h * 0.86; y += 7 + (y - h * 0.68) * 0.25) {
      canvas.drawLine(Offset(0, y), Offset(w, y), row);
    }
    // 논밭의 흰 곤포 사일리지
    final bale = Paint()..color = const Color(0xFFF4F3EE);
    final baleShade = Paint()..color = const Color(0xFFD2D4CF);
    _repeat(w, 70, m * _midPx * 0.55, (x, i) {
      if (_rand(i, 141) < 0.45) return;
      final r = h * 0.03;
      final y = h * (0.72 + _rand(i, 142) * 0.05);
      for (var k = 0; k < 1 + (_rand(i, 143) * 3).floor(); k++) {
        final c = Offset(x + k * r * 2.2, y);
        canvas
          ..drawCircle(c + Offset(r * 0.25, r * 0.15), r, baleShade)
          ..drawCircle(c, r, bale);
      }
    });
    // 띄엄띄엄 선 나무
    final trunk = Paint()..color = _Palette.trunk;
    final dark = Paint()..color = _Palette.forest;
    final lit = Paint()..color = _Palette.forestLit;
    _repeat(w, 180, m * _midPx * 0.7, (x, i) {
      if (_rand(i, 2) < 0.15) return;
      _tree(canvas, x + _rand(i, 3) * 90, h * 0.74,
          h * (0.14 + _rand(i, 4) * 0.08), i + 100, trunk, dark, lit);
    });
    // 전봇대와 늘어진 전선
    const pole = 230.0;
    final wood = Paint()..color = const Color(0xFF6A5A4C);
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xAA3A3A3A);
    _repeat(w, pole, m * _midPx, (x, _) {
      final top = h * 0.2;
      final base = h * 0.84;
      canvas
        ..drawRect(Rect.fromLTRB(x - 2.5, top, x + 2.5, base), wood)
        ..drawRect(Rect.fromLTRB(x - 14, top + 8, x + 14, top + 11), wood);
      for (final dx in const [-11.0, 11.0]) {
        canvas.drawPath(
            Path()
              ..moveTo(x + dx, top + 8)
              ..quadraticBezierTo(
                  x + pole / 2 + dx, top + 34, x + pole + dx, top + 8),
            wire);
      }
    });
  }

  void _near(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    final edge = h * 0.88;
    final verge = Rect.fromLTRB(0, edge, w, h);
    canvas.drawRect(
        verge,
        _band(
            'verge', size, verge, const [_Palette.verge, _Palette.vergeDeep]));
    // 빠르게 스치는 풀
    final blade = Paint()
      ..color = const Color(0xFF6F9F4A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    _repeat(w, 18, m * _nearPx, (x, i) {
      canvas.drawLine(Offset(x, edge + 4),
          Offset(x + 3, edge - 4 - _rand(i, 80) * 8), blade);
    });
    if (scene.rainLevel > 0) {
      // 젖은 땅: 하늘빛이 비친다
      canvas.drawRect(Rect.fromLTRB(0, h * 0.95, w, h),
          Paint()..color = _haze.withValues(alpha: 0.25));
    }
    if (scene.highway) {
      // 고속도로 방음벽: 반투명 판 + 철 기둥
      final panel = Paint()..color = const Color(0x77B7D3D6);
      final post = Paint()..color = _Palette.steelShade;
      final glare = Paint()..color = Colors.white.withValues(alpha: 0.28);
      canvas.drawRect(Rect.fromLTRB(0, h * 0.58, w, edge), panel);
      _repeat(w, 70, m * _nearPx, (x, _) {
        canvas
          ..drawRect(Rect.fromLTRB(x, h * 0.56, x + 5, edge + 4), post)
          ..drawPath(
              Path()
                ..moveTo(x + 18, h * 0.58)
                ..lineTo(x + 30, h * 0.58)
                ..lineTo(x + 14, edge)
                ..lineTo(x + 2, edge)
                ..close(),
              glare);
      });
      canvas.drawRect(Rect.fromLTRB(0, h * 0.56, w, h * 0.58), post);
      return;
    }
    // 가드레일: 철 기둥 + 빛을 받는 띠
    final post = Paint()..color = _Palette.steelShade;
    _repeat(w, 52, m * _nearPx, (x, _) {
      canvas.drawRect(Rect.fromLTRB(x, h * 0.8, x + 5, edge + 4), post);
    });
    final rail = Rect.fromLTRB(-10, h * 0.8, w + 10, h * 0.835);
    canvas
      ..drawRect(rail, Paint()..color = _Palette.steel)
      ..drawRect(Rect.fromLTRB(-10, rail.top + 1, w + 10, rail.top + 3),
          Paint()..color = Colors.white.withValues(alpha: 0.7))
      ..drawRect(Rect.fromLTRB(-10, rail.bottom - 3, w + 10, rail.bottom),
          Paint()..color = _Palette.steelShade);
  }

  void _tunnel(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    final all = Offset.zero & size;
    canvas.drawRect(all, _band('tunnel', size, all, _Palette.tunnelWall));
    // 벽 타일 이음매가 빠르게 지나간다
    final seam = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 2;
    _repeat(w, 40, m * _nearPx, (x, _) {
      canvas.drawLine(Offset(x, h * 0.3), Offset(x, h * 0.9), seam);
    });
    // 주황 나트륨등과 벽에 번지는 빛
    final band = Rect.fromLTRB(0, h * 0.08, w, h * 0.5);
    canvas.drawRect(
        band,
        _band('sodiumWash', size, band, [
          _Palette.sodium.withValues(alpha: 0.28),
          _Palette.sodium.withValues(alpha: 0),
        ]));
    final lamp = Paint()..color = const Color(0xFFFFE2A8);
    final glow = Paint()
      ..color = _Palette.sodium.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    _repeat(w, 120, m * _midPx * 2, (x, _) {
      final r = Rect.fromLTWH(x, h * 0.13, 56, 9);
      canvas
        ..drawRect(r.inflate(10), glow)
        ..drawRect(r, lamp);
    });
    canvas.drawRect(Rect.fromLTRB(0, h * 0.88, w, h),
        Paint()..color = const Color(0xFF26231F));
    canvas.drawRect(Rect.fromLTRB(0, h * 0.88, w, h * 0.89),
        Paint()..color = _Palette.sodium.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.mirror != mirror;
}

class _RainPainter extends CustomPainter {
  _RainPainter(this.level, this.speedKph, this.motion, {this.wipers = false})
      : super(repaint: motion);

  final int level;
  final double speedKph;
  final _Motion motion;

  /// 앞유리: 와이퍼가 [wiperCycle] 주기로 닦고, 닦은 직후에는 물방울이 옅다.
  final bool wipers;

  @override
  void paint(Canvas canvas, Size size) {
    if (level <= 0) return;
    final w = size.width;
    final h = size.height;
    // 유리창에 맺힌 물방울: 바깥 풍경이 비쳐 아래가 어둡고 위에 반짝임이 있다
    final body = Paint()..color = Colors.white.withValues(alpha: 0.16);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55203040);
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final (period, sweep) = wiperCycle(level);
    final phase =
        wipers && period > 0 ? (motion.seconds % period) / period : 1.0;
    if (wipers) {
      // 와이퍼가 지나간 뒤로 물방울이 다시 맺힌다
      final a = 0.25 + 0.75 * phase;
      body.color = body.color.withValues(alpha: 0.16 * a);
      rim.color = rim.color.withValues(alpha: 0.33 * a);
      shine.color = shine.color.withValues(alpha: 0.85 * a);
    }
    for (var i = 0; i < level * 9; i++) {
      final c = Offset(_rand(i, 21) * w, _rand(i, 22) * h);
      final r = 2 + _rand(i, 23) * 3.5;
      canvas
        ..drawCircle(c, r, body)
        ..drawArc(Rect.fromCircle(center: c, radius: r), 0.3, 2.5, false, rim)
        ..drawCircle(c + Offset(-r * 0.35, -r * 0.4), r * 0.28, shine);
    }
    // 빗줄기: 가늘고 길다. 빨리 달릴수록 더 눕는다
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final slant = -(3 + speedKph / 100 * 12);
    final t = motion.seconds;
    for (var i = 0; i < level * 34; i++) {
      final fall = 520 + _rand(i, 7) * 260;
      final y = (_rand(i, 8) * h + t * fall) % (h + 30) - 15;
      final x = (_rand(i, 9) * w + t * slant * 20) % w;
      canvas.drawLine(Offset(x, y), Offset(x + slant * 1.2, y + 18), p);
    }
    if (wipers) _wipers(canvas, size, phase, sweep);
  }

  /// 운전석·조수석 와이퍼 두 개. 아래쪽 축을 중심으로 부채꼴로 닦고 돌아온다.
  void _wipers(Canvas canvas, Size size, double phase, double sweep) {
    final w = size.width;
    final h = size.height;
    final s = phase < sweep ? math.sin(phase / sweep * math.pi) : 0.0;
    final angle = 0.12 + s * 1.9; // 누운 상태(0.12) → 거의 세운 상태
    final arm = Paint()
      ..color = const Color(0xFF1E1C1A)
      ..strokeWidth = math.max(2.2, h * 0.025)
      ..strokeCap = StrokeCap.round;
    final blade = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = math.max(1.5, h * 0.016)
      ..strokeCap = StrokeCap.round;
    for (final pivotX in [0.22, 0.6]) {
      final pivot = Offset(w * pivotX, h * 1.02);
      final len = w * 0.42;
      // 오른쪽으로 누운 상태에서 위로 들어 올린다
      final end = pivot + Offset(math.cos(angle), -math.sin(angle)) * len;
      canvas.drawLine(pivot, end, arm);
      final mid = Offset.lerp(pivot, end, 0.35)!;
      canvas.drawLine(mid, end, blade);
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.speedKph != speedKph;
}
