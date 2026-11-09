part of '../window_view.dart';

/// 앞유리로 보이는 길. 소실점이 있는 원근 도로에 차선·가로수·건물이 다가와 양옆으로 빠진다.
///
/// 세계 좌표: x 는 오른쪽(+, m), y 는 위(m), d 는 앞쪽 거리(m). 우리 차는 오른쪽 차로 가운데(x=0)다.
class _WindshieldPainter extends CustomPainter {
  _WindshieldPainter(this.scene, this.motion, this.spawner)
      : backdrop = _ScenePainter(scene, motion),
        super(repaint: motion);

  final WindowScene scene;
  final _Motion motion;
  final PasserbySpawner spawner;

  /// 하늘·구름·먼 산은 옆창 장면과 같은 붓으로 그린다
  final _ScenePainter backdrop;

  static const _camH = 1.25;
  static const _far = 260.0;

  late double _vpX, _y0, _f;

  Offset _p(double x, double y, double d) =>
      Offset(_vpX + x * _f / d, _y0 + (_camH - y) * _f / d);

  /// 멀수록 지평선 색에 묻힌다
  Color _air(Color c, double d) =>
      Color.lerp(c, backdrop._haze, (d / _far).clamp(0.0, 1.0) * 0.8)!;

  Path _quad(Offset a, Offset b, Offset c, Offset e) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(e.dx, e.dy)
    ..close();

  /// 길바닥에 깔린 띠 (차선 등). x 는 가운데, wd 는 폭.
  void _stripe(
      Canvas canvas, double x, double wd, double d1, double d2, Paint paint) {
    canvas.drawPath(
        _quad(_p(x - wd / 2, 0, d1), _p(x + wd / 2, 0, d1),
            _p(x + wd / 2, 0, d2), _p(x - wd / 2, 0, d2)),
        paint);
  }

  /// 앞에서 뒤로 [period] m 마다 반복되는 물체를 먼 것부터 그린다.
  /// 물체마다 고정된 번호를 주어 다가와도 모양이 바뀌지 않게 한다.
  void _along(double period, double near, double far,
      void Function(double d, int i) draw) {
    final m = motion.meters;
    final first = ((m + near) / period).ceil();
    final last = ((m + far) / period).floor();
    for (var i = last; i >= first; i--) {
      draw(i * period - m, i);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    _vpX = w * 0.5;
    _y0 = h * 0.46;
    _f = w * 0.42;

    if (scene.kind == SceneKind.tunnel) {
      _tunnel(canvas, size);
      return;
    }

    final all = Offset.zero & size;
    canvas.drawRect(all,
        backdrop._band('sky', size, all, backdrop._sky, const [0, 0.5, 0.92]));
    if (scene.night) {
      backdrop._stars(canvas, w, _y0 * 1.6);
    } else if (scene.rainLevel == 0) {
      canvas.drawCircle(
          Offset(w * 0.2, 0),
          h * 0.9,
          Paint()
            ..shader = const RadialGradient(colors: [
              Color(0x66FFF6DA),
              Color(0x00FFF6DA),
            ]).createShader(
                Rect.fromCircle(center: Offset(w * 0.2, 0), radius: h * 0.9)));
    }
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, w, _y0 + 1));
    backdrop._clouds(canvas, w, _y0 * 1.25, 0);
    _horizon(canvas, size);
    canvas.restore();

    _ground(canvas, size);
    _roadside(canvas, size);

    if (scene.night) {
      // 밤빛을 앞유리 전체에 곱한다. 위쪽(하늘)은 옅게 곱해 별이 남는다
      canvas.drawRect(
          all,
          backdrop._band(
              'fwdVeil',
              size,
              all,
              const [Color(0xFF8E98CC), Color(0xFF5E6CAC), Color(0xFF3A4682)],
              const [0, 0.45, 1])
            ..blendMode = BlendMode.multiply);
      _nightLights(canvas, size);
    }
    if (scene.rainLevel > 0) {
      canvas.drawRect(
          all,
          Paint()
            ..color =
                backdrop._haze.withValues(alpha: 0.1 + scene.rainLevel * 0.05));
    }
  }

  /// 먼 풍경: 장면마다 지평선 위로 보이는 산·바다·도시 윤곽
  void _horizon(Canvas canvas, Size size) {
    final w = size.width;
    final y0 = _y0;
    switch (scene.kind) {
      case SceneKind.mountain:
        // 우뚝 솟은 먼 산맥 두 겹: 뒤는 푸르게 바래고 앞은 숲이 덮었다
        backdrop._range(canvas, size, 300, 27, -y0 * 0.5, y0 + 2,
            backdrop._far(_Palette.farBlue, 0.05), 'f1',
            scale: 0.8);
        backdrop._range(canvas, size, 900, 28, y0 * 0.05, y0 + 2,
            backdrop._far(_Palette.midGreen, 0.12), 'f2',
            scale: 0.6, wooded: true);
      case SceneKind.coast:
        // 왼쪽은 언덕, 오른쪽은 탁 트인 바다
        canvas.drawPath(
            _profile(
                w * 0.5,
                y0 + 2,
                (x) =>
                    y0 - y0 * 0.3 * _ridge(x + 40, 37) * (1 - x / (w * 0.5))),
            Paint()..color = backdrop._far(_Palette.midGreen, 0.35));
      case SceneKind.city:
        final far = Paint()
          ..color = backdrop._far(const Color(0xFF8DA2B6), 0.45);
        for (var x = 0.0; x < w; x += 9) {
          final hh = y0 * (0.12 + 0.3 * _rand(x.toInt(), 51));
          canvas.drawRect(Rect.fromLTRB(x, y0 - hh, x + 8, y0 + 1), far);
        }
      case SceneKind.road:
      case SceneKind.tunnel:
        backdrop._range(canvas, size, 500, 47, y0 * 0.55, y0 + 2,
            backdrop._far(_Palette.farBlue, 0.3), 'f3',
            scale: 1.1);
        backdrop._range(canvas, size, 1300, 48, y0 * 0.78, y0 + 2,
            backdrop._far(_Palette.midGreen, 0.25), 'f4',
            scale: 0.8, wooded: true);
    }
  }

  (double, double) get _roadEdges => scene.highway ? (-9.0, 4.2) : (-5.4, 2.6);

  void _ground(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ground = Rect.fromLTRB(0, _y0, w, h);
    final (sideTop, sideBottom) = switch (scene.kind) {
      SceneKind.coast => (_Palette.sand, _Palette.sandDeep),
      SceneKind.city => (const Color(0xFFC9C4B8), const Color(0xFFA8A296)),
      _ => (_Palette.meadow, _Palette.meadowDeep),
    };
    canvas.drawRect(
        ground,
        backdrop._band('fwdGround', size, ground,
            [backdrop._far(sideTop, 0.5), sideBottom]));
    if (scene.kind == SceneKind.coast) {
      // 오른쪽 바다: 모래사장 너머로 지평선까지
      final shore = 9.0;
      final sea = _quad(_p(shore, 0, _far), Offset(w + 2, _y0),
          Offset(w + 2, h + 2), _p(shore, 0, 1.0));
      canvas.drawPath(
          sea,
          backdrop._band('fwdSea', size, ground,
              const [_Palette.seaHorizon, _Palette.sea]));
      final glint = Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      _along(9, 6, 160, (d, i) {
        final a = _p(shore + 3 + _rand(i, 61) * 30, 0, d);
        if (a.dx > w) return;
        canvas.drawLine(a, a + Offset(3 + 30 / d, 0), glint);
      });
    }
    final (l, r) = _roadEdges;
    canvas.drawPath(
        _quad(_p(l, 0, _far), _p(r, 0, _far), _p(r, 0, 0.8), _p(l, 0, 0.8)),
        backdrop._band('asphalt', size, ground, [
          backdrop._far(const Color(0xFF6F7275), 0.4),
          const Color(0xFF4A4C4F)
        ]));
    final white = Paint()..color = const Color(0xFFEDEDE6);
    final yellow = Paint()..color = const Color(0xFFF2C14E);
    // 길 가장자리 실선
    _stripe(canvas, r - 0.4, 0.14, 0.8, _far, white);
    if (scene.highway) {
      _stripe(canvas, l + 0.5, 0.14, 0.8, _far, yellow);
      for (final lane in [-1.75, -5.25]) {
        _along(15, 0.8, 140,
            (d, _) => _stripe(canvas, lane, 0.13, d, d + 6, white));
      }
    } else {
      // 가운데 노란 겹실선
      _stripe(canvas, -1.82, 0.1, 0.8, _far, yellow);
      _stripe(canvas, -1.62, 0.1, 0.8, _far, yellow);
      _stripe(canvas, l + 0.3, 0.12, 0.8, _far, white);
    }
  }

  /// 길가 물체를 모두 모은 뒤 먼 것부터 그린다. 가까운 것이 먼 것을 자연스럽게 가린다.
  void _roadside(Canvas canvas, Size size) {
    final q = <(double, void Function())>[];
    void add(double d, void Function() draw) => q.add((d, draw));
    final trunk = Paint()..color = _Palette.trunk;
    switch (scene.kind) {
      case SceneKind.city:
        _city(canvas, add);
      case SceneKind.coast:
        _coastProps(canvas, add);
        _trees(canvas, add, trunk, 11, const [-7.5, -12, -17], 0.35);
        _guardPosts(canvas, add, 3.4);
      case SceneKind.mountain:
        _trees(canvas, add, trunk, 5, const [-9, -13, -18, 8, 12, 17], 0.2);
        _rocks(canvas, add);
        _guardPosts(canvas, add, 3.2);
      case SceneKind.road:
      case SceneKind.tunnel:
        _farmland(canvas, add);
        _trees(canvas, add, trunk, 9, const [-8, -14, 6.5, 12], 0.4);
        _poles(canvas, add, 4.2);
    }
    if (scene.highway) {
      _barrier(canvas, add, -9.4, 1.0, const Color(0xFFB9B6AE));
      _barrier(canvas, add, 4.6, 3.6, const Color(0x99B7D3D6));
      _streetLights(canvas, add, 40, const [-9.4]);
      _signs(canvas, add);
    }
    _leadCar(canvas, add);
    _oncoming(canvas, add);
    q.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, draw) in q) {
      draw();
    }
  }

  /// 세계 좌표 상자. 길 쪽을 향한 옆면과 우리 쪽을 향한 앞면을 그린다.
  void _box(Canvas canvas, double x1, double x2, double y1, double y2,
      double d1, double d2, Color front, Color side) {
    final roadSide = x1 > 0 ? x1 : x2; // 길에 가까운 면
    canvas
      ..drawPath(
          _quad(_p(roadSide, y1, d1), _p(roadSide, y2, d1),
              _p(roadSide, y2, d2), _p(roadSide, y1, d2)),
          Paint()..color = _air(side, d1))
      ..drawPath(
          _quad(_p(x1, y1, d1), _p(x2, y1, d1), _p(x2, y2, d1), _p(x1, y2, d1)),
          Paint()..color = _air(front, d1));
  }

  void _person(Canvas canvas, double x, double d, int seed) {
    final t = motion.seconds;
    final bob = (math.sin(t * 6 + seed)).abs() * 0.05;
    final shirt = const [
      Color(0xFFE2614B),
      Color(0xFF4A90D0),
      Color(0xFFF2C14E),
      Color(0xFF58D8A0),
      Color(0xFFF1E6CF),
    ][seed % 5];
    final k = _f / d;
    canvas
      ..drawLine(
          _p(x, 0, d),
          _p(x, 0.85, d),
          Paint()
            ..color = _air(const Color(0xFF3B4A5C), d)
            ..strokeWidth = math.max(0.8, 0.28 * k))
      ..drawLine(
          _p(x, 0.85 + bob, d),
          _p(x, 1.4 + bob, d),
          Paint()
            ..color = _air(shirt, d)
            ..strokeWidth = math.max(1, 0.42 * k)
            ..strokeCap = StrokeCap.round)
      ..drawCircle(_p(x, 1.62 + bob, d), math.max(0.6, 0.14 * k),
          Paint()..color = _air(const Color(0xFF3B2E26), d));
    if (scene.rainLevel > 0) {
      final c = _p(x, 1.85 + bob, d);
      canvas.drawArc(
          Rect.fromCenter(center: c, width: 0.9 * k, height: 0.6 * k),
          math.pi,
          math.pi,
          true,
          Paint()..color = _air(shirt, d));
    }
  }

  void _car(Canvas canvas, double x, double d, int seed, {bool rear = true}) {
    const hw = 0.9;
    final color = const [
      Color(0xFFE9E4DA),
      Color(0xFF7FA6C9),
      Color(0xFFC8654F),
      Color(0xFF59615E),
      Color(0xFFF2C14E),
    ][seed % 5];
    canvas
      ..drawPath(
          _quad(_p(x - hw, 0.25, d), _p(x + hw, 0.25, d), _p(x + hw, 0.95, d),
              _p(x - hw, 0.95, d)),
          Paint()..color = _air(color, d))
      ..drawPath(
          _quad(_p(x - hw * 0.8, 0.95, d), _p(x + hw * 0.8, 0.95, d),
              _p(x + hw * 0.65, 1.45, d), _p(x - hw * 0.65, 1.45, d)),
          Paint()..color = _air(const Color(0xFF3B4650), d));
    final tire = Paint()..color = const Color(0xFF1C1C1C);
    for (final s in [-1, 1]) {
      canvas.drawPath(
          _quad(_p(x + s * hw * 0.9, 0, d), _p(x + s * hw * 0.5, 0, d),
              _p(x + s * hw * 0.5, 0.3, d), _p(x + s * hw * 0.9, 0.3, d)),
          tire);
      if (rear) {
        // 미등
        canvas.drawPath(
            _quad(_p(x + s * hw * 0.85, 0.6, d), _p(x + s * hw * 0.55, 0.6, d),
                _p(x + s * hw * 0.55, 0.78, d), _p(x + s * hw * 0.85, 0.78, d)),
            Paint()..color = const Color(0xFFD9473A));
      }
    }
  }

  /// 도시: 길 양쪽으로 두세 줄 건물이 빽빽하고, 인도에는 가로수·가로등·사람·주차된 차,
  /// 일정 간격으로 교차로(횡단보도·신호등)가 나온다.
  void _city(Canvas canvas, void Function(double, void Function()) add) {
    const block = 96.0; // 교차로 간격
    bool crossing(double s) => (s % block) < 14;
    final m = motion.meters;
    for (final side in [-1, 1]) {
      // 줄마다 건물 깊이·높이가 다르다. 뒷줄이 더 높아 스카이라인을 만든다
      for (final (row, x0, depth, lo, hi) in [
        (2, side < 0 ? -34.0 : 30.0, 14.0, 30.0, 70.0),
        (1, side < 0 ? -21.0 : 17.0, 10.0, 14.0, 40.0),
        (0, side < 0 ? -8.0 : 5.0, 9.0, 6.0, 22.0),
      ]) {
        final x1 = side < 0 ? x0 - depth : x0;
        final x2 = side < 0 ? x0 : x0 + depth;
        final period = 9.0 + row * 4;
        _along(period, 1.0, _far, (d, i) {
          final s = d + m;
          if (row == 0 && crossing(s)) return;
          final idx = i * 7 + row * 3 + (side < 0 ? 0 : 1);
          final hgt = lo + _rand(idx, 81) * (hi - lo);
          final pal = _Palette.walls;
          final (face, shade) =
              pal[(_rand(idx, 82) * pal.length).floor() % pal.length];
          final len = period - 0.6;
          add(d + row * 0.01, () {
            _box(canvas, x1, x2, 0, hgt, d, d + len, side < 0 ? shade : face,
                side < 0 ? face : shade);
            if (row > 0) return;
            final rs = side < 0 ? x2 : x1;
            // 창문 격자 (길 쪽 면)
            final win = Paint()..color = _air(_Palette.glassDay, d);
            for (var fy = 4.2; fy < hgt - 1; fy += 3) {
              for (var fd = 0.8; fd < len - 1; fd += 2.2) {
                canvas.drawPath(
                    _quad(
                        _p(rs, fy, d + fd),
                        _p(rs, fy + 1.3, d + fd),
                        _p(rs, fy + 1.3, d + fd + 1.1),
                        _p(rs, fy, d + fd + 1.1)),
                    win);
              }
            }
            // 1층 가게: 간판과 차양
            final sign = const [
              Color(0xFFE2614B),
              Color(0xFF4A90D0),
              Color(0xFF58D8A0),
              Color(0xFFF2C14E),
              Color(0xFFB487D8),
            ][idx % 5];
            canvas
              ..drawPath(
                  _quad(_p(rs, 2.8, d + 0.4), _p(rs, 3.6, d + 0.4),
                      _p(rs, 3.6, d + len - 0.4), _p(rs, 2.8, d + len - 0.4)),
                  Paint()..color = _air(sign, d))
              ..drawPath(
                  _quad(_p(rs, 0, d + 0.6), _p(rs, 2.4, d + 0.6),
                      _p(rs, 2.4, d + len - 0.6), _p(rs, 0, d + len - 0.6)),
                  Paint()..color = _air(const Color(0xFF6E8FAA), d));
            // 옥상 물탱크·안테나
            if (_rand(idx, 84) < 0.4) {
              final ax = (x1 + x2) / 2;
              canvas.drawLine(
                  _p(ax, hgt, d + 2),
                  _p(ax, hgt + 3, d + 2),
                  Paint()
                    ..color = _air(const Color(0xFF5A5F63), d)
                    ..strokeWidth = math.max(0.5, 0.1 * _f / d));
            }
          });
        });
      }
      // 인도: 가로수, 가로등, 사람
      final walk = side < 0 ? -6.6 : 3.8;
      _along(14, 2, 180, (d, i) {
        if (crossing(d + m)) return;
        add(d, () {
          final base = _p(walk, 0, d);
          _tree(
              canvas,
              base.dx,
              base.dy,
              5 * _f / d,
              i * 3 + side,
              Paint()..color = _air(_Palette.trunk, d),
              Paint()..color = _air(_Palette.forest, d),
              Paint()..color = _air(_Palette.forestLit, d));
        });
      });
      _streetLights(canvas, add, 28, [walk + (side < 0 ? 0.6 : -0.3)]);
      final px = side < 0 ? -7.3 : 4.6;
      _along(5, 1.5, 120, (d, i) {
        final idx = i * 2 + (side < 0 ? 0 : 1);
        if (_rand(idx, 85) < 0.55) return;
        add(d, () => _person(canvas, px + _rand(idx, 86) * 0.8, d, idx));
      });
    }
    // 오른쪽 길가에 주차된 차
    _along(13, 3, 140, (d, i) {
      if (_rand(i, 87) < 0.5 || crossing(d + m)) return;
      add(d, () => _car(canvas, 2.9, d, i, rear: true));
    });
    // 교차로: 횡단보도와 신호등
    _along(block, 2, _far, (d, i) {
      final white = Paint()..color = _air(const Color(0xFFEDEDE6), d);
      add(d + 6, () {
        for (var x = -5.0; x < 2.6; x += 0.9) {
          canvas.drawPath(
              _quad(_p(x, 0, d), _p(x + 0.5, 0, d), _p(x + 0.5, 0, d + 3),
                  _p(x, 0, d + 3)),
              white);
        }
      });
      final green = (motion.seconds ~/ 6 + i).isEven;
      for (final x in [-6.2, 3.4]) {
        add(d - 0.1, () {
          canvas.drawLine(
              _p(x, 0, d),
              _p(x, 4.2, d),
              Paint()
                ..color = _air(const Color(0xFF5A5F63), d)
                ..strokeWidth = math.max(0.6, 0.14 * _f / d));
          final head =
              Rect.fromPoints(_p(x - 0.3, 4.2, d), _p(x + 0.3, 5.6, d));
          canvas
            ..drawRect(head, Paint()..color = const Color(0xFF2E2E2E))
            ..drawCircle(
                _p(x, green ? 4.55 : 5.25, d),
                math.max(0.8, 0.2 * _f / d),
                Paint()
                  ..color = green
                      ? const Color(0xFF58D8A0)
                      : const Color(0xFFE2614B));
        });
      }
    });
  }

  /// 바다: 수평선의 돛단배와 등대, 해안 방파제
  void _coastProps(Canvas canvas, void Function(double, void Function()) add) {
    final t = motion.seconds;
    for (var k = 0; k < 5; k++) {
      final d = 70.0 + k * 35;
      final x = 14 + _rand(k, 101) * 45 + math.sin(t * 0.05 + k) * 2;
      add(d, () {
        final hull = _p(x, 0, d);
        final k2 = _f / d;
        canvas
          ..drawPath(
              Path()
                ..moveTo(hull.dx - 1.6 * k2, hull.dy)
                ..lineTo(hull.dx + 1.6 * k2, hull.dy)
                ..lineTo(hull.dx + 1.2 * k2, hull.dy + 0.5 * k2)
                ..lineTo(hull.dx - 1.2 * k2, hull.dy + 0.5 * k2)
                ..close(),
              Paint()..color = _air(const Color(0xFF5A4636), d))
          ..drawPath(
              Path()
                ..moveTo(hull.dx, hull.dy - 3.2 * k2)
                ..lineTo(hull.dx + 1.4 * k2, hull.dy - 0.2 * k2)
                ..lineTo(hull.dx, hull.dy - 0.2 * k2)
                ..close(),
              Paint()..color = _air(Colors.white, d));
      });
    }
    // 등대: 멀리 오른쪽 곶 위
    add(_far * 0.9, () {
      final d = _far * 0.9;
      final b = _p(26, 0, d), top = _p(26, 14, d);
      final k2 = _f / d;
      canvas
        ..drawRect(
            Rect.fromLTRB(b.dx - 1.2 * k2, top.dy, b.dx + 1.2 * k2, b.dy),
            Paint()..color = _air(Colors.white, d * 0.5))
        ..drawRect(
            Rect.fromLTRB(b.dx - 1.2 * k2, top.dy + 4 * k2, b.dx + 1.2 * k2,
                top.dy + 6.5 * k2),
            Paint()..color = _air(const Color(0xFFD9473A), d * 0.5))
        ..drawCircle(top, 1.0 * k2, Paint()..color = _Palette.lamp);
    });
    // 방파제 테트라포드 줄
    _along(3, 2, 150, (d, i) {
      add(d, () {
        final c = _p(6.5 + _rand(i, 102) * 0.6, 0.4, d);
        canvas.drawCircle(c, math.max(0.6, 0.7 * _f / d),
            Paint()..color = _air(const Color(0xFFBDB8AE), d));
      });
    });
  }

  /// 시골길: 멀리 농가 지붕과 비닐하우스
  void _farmland(Canvas canvas, void Function(double, void Function()) add) {
    _along(37, 20, _far, (d, i) {
      if (_rand(i, 111) < 0.35) return;
      final side = _rand(i, 112) < 0.5 ? -1 : 1;
      final x = side * (22 + _rand(i, 113) * 40);
      final greenhouse = _rand(i, 114) < 0.4;
      add(d, () {
        if (greenhouse) {
          final a = _p(x - 4, 0, d), b = _p(x + 4, 0, d);
          canvas.drawArc(
              Rect.fromLTRB(a.dx, a.dy - (b.dx - a.dx) * 0.5, b.dx,
                  a.dy + (b.dx - a.dx) * 0.5),
              math.pi,
              math.pi,
              true,
              Paint()..color = _air(const Color(0xFFE8EEF0), d));
          return;
        }
        _box(canvas, x - 4, x + 4, 0, 3, d, d + 6, const Color(0xFFF1E6CF),
            const Color(0xFFCDBFA4));
        final l = _p(x - 4.6, 3, d), r = _p(x + 4.6, 3, d), top = _p(x, 5.2, d);
        canvas.drawPath(
            Path()
              ..moveTo(l.dx, l.dy)
              ..lineTo(top.dx, top.dy)
              ..lineTo(r.dx, r.dy)
              ..close(),
            Paint()
              ..color = _air(
                  _rand(i, 115) < 0.5 ? _Palette.roof : const Color(0xFF4A7FB0),
                  d));
      });
    });
  }

  void _rocks(Canvas canvas, void Function(double, void Function()) add) {
    _along(6, 2, 120, (d, i) {
      if (_rand(i, 121) < 0.6) return;
      final x = (_rand(i, 122) < 0.5 ? -1 : 1) * (4 + _rand(i, 123) * 3);
      add(d, () {
        final c = _p(x, 0.2, d);
        canvas.drawOval(
            Rect.fromCenter(
                center: c, width: 1.4 * _f / d, height: 0.8 * _f / d),
            Paint()..color = _air(const Color(0xFF8C8A80), d));
      });
    });
  }

  void _signs(Canvas canvas, void Function(double, void Function()) add) {
    _along(180, 10, _far, (d, i) {
      add(d, () {
        final a = _p(-8, 6, d), b = _p(4, 8.5, d);
        canvas
          ..drawLine(
              _p(-8.5, 0, d),
              _p(-8.5, 8.5, d),
              Paint()
                ..color = _air(const Color(0xFF7B8287), d)
                ..strokeWidth = math.max(0.6, 0.2 * _f / d))
          ..drawLine(
              _p(-8.5, 8.2, d),
              _p(4, 8.2, d),
              Paint()
                ..color = _air(const Color(0xFF7B8287), d)
                ..strokeWidth = math.max(0.6, 0.2 * _f / d))
          ..drawRect(Rect.fromPoints(a, b),
              Paint()..color = _air(const Color(0xFF2F7D52), d))
          ..drawRect(
              Rect.fromPoints(a, b).deflate(math.max(0.3, 0.15 * _f / d)),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(0.5, 0.08 * _f / d)
                ..color = Colors.white.withValues(alpha: 0.8));
      });
    });
  }

  void _trees(Canvas canvas, void Function(double, void Function()) add,
      Paint trunk, double period, List<double> xs, double skip) {
    _along(period, 1.5, _far * 0.8, (d, i) {
      for (var k = 0; k < xs.length; k++) {
        if (_rand(i * 7 + k, 71) < skip) continue;
        if (scene.highway && xs[k].abs() < 9) continue;
        final x = xs[k] + (_rand(i * 7 + k, 72) - 0.5) * 2.5;
        add(d, () {
          final base = _p(x, 0, d);
          final s = (4.5 + _rand(i, 73) * 3) * _f / d;
          _tree(
              canvas,
              base.dx,
              base.dy,
              s,
              i * 7 + k,
              Paint()..color = _air(_Palette.trunk, d),
              Paint()..color = _air(_Palette.forest, d),
              Paint()..color = _air(_Palette.forestLit, d));
        });
      }
    });
  }

  void _guardPosts(
      Canvas canvas, void Function(double, void Function()) add, double x) {
    _along(4, 1.2, 120, (d, _) {
      add(d, () {
        canvas.drawLine(
            _p(x, 0, d),
            _p(x, 0.75, d),
            Paint()
              ..color = _Palette.steelShade
              ..strokeWidth = math.max(1, 0.12 * _f / d));
      });
    });
    add(0.5, () {
      canvas.drawPath(
          _quad(_p(x, 0.75, 1.2), _p(x, 0.75, 120), _p(x, 0.55, 120),
              _p(x, 0.55, 1.2)),
          Paint()..color = _Palette.steel);
    });
  }

  void _poles(
      Canvas canvas, void Function(double, void Function()) add, double x) {
    final wood = const Color(0xFF6A5A4C);
    _along(40, 2, _far, (d, i) {
      add(d, () {
        canvas
          ..drawLine(
              _p(x, 0, d),
              _p(x, 8, d),
              Paint()
                ..color = _air(wood, d)
                ..strokeWidth = math.max(1, 0.28 * _f / d))
          ..drawLine(
              _p(x - 0.8, 7.6, d),
              _p(x + 0.8, 7.6, d),
              Paint()
                ..color = _air(wood, d)
                ..strokeWidth = math.max(0.8, 0.14 * _f / d));
        // 다음 전봇대로 늘어진 전선
        final a = _p(x, 7.6, d), b = _p(x, 7.6, d + 40);
        final mid = Offset.lerp(a, b, 0.5)! + Offset(0, 1.2 * _f / (d + 20));
        canvas.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = const Color(0x993A3A3A));
      });
    });
  }

  void _streetLights(Canvas canvas, void Function(double, void Function()) add,
      double period, List<double> xs) {
    _along(period, 2, 200, (d, i) {
      for (final x in xs) {
        final arm = x < 0 ? 1.4 : -1.4;
        add(d, () {
          final pole = Paint()..color = _air(const Color(0xFF7B8287), d);
          canvas
            ..drawLine(_p(x, 0, d), _p(x, 7, d),
                pole..strokeWidth = math.max(0.8, 0.18 * _f / d))
            ..drawLine(_p(x, 7, d), _p(x + arm, 7.2, d),
                pole..strokeWidth = math.max(0.6, 0.12 * _f / d));
        });
      }
    });
  }

  void _barrier(Canvas canvas, void Function(double, void Function()) add,
      double x, double height, Color c) {
    add(_far, () {
      canvas.drawPath(
          _quad(_p(x, 0, 1.0), _p(x, 0, _far), _p(x, height, _far),
              _p(x, height, 1.0)),
          Paint()..color = c);
    });
    _along(10, 1.2, 150, (d, _) {
      add(d, () {
        canvas.drawLine(
            _p(x, 0, d),
            _p(x, height, d),
            Paint()
              ..color = _Palette.steelShade
              ..strokeWidth = math.max(0.8, 0.15 * _f / d));
      });
    });
  }

  /// 앞차: 도시·고속도로에서 우리 차로 앞에 거리를 두고 달린다
  void _leadCar(Canvas canvas, void Function(double, void Function()) add) {
    if (scene.kind != SceneKind.city && !scene.highway) return;
    final d = 26 + 5 * math.sin(motion.seconds * 0.25);
    add(d, () => _car(canvas, 0.1, d, 3));
    if (scene.highway) {
      final d2 = 48 + 9 * math.sin(motion.seconds * 0.17 + 1);
      add(d2, () => _car(canvas, -3.5, d2, 1));
    }
  }

  /// 마주 오는 차. 왼쪽 차로로 다가와 옆으로 스쳐 지나간다.
  void _oncoming(Canvas canvas, void Function(double, void Function()) add) {
    for (final p in spawner.active) {
      if (p.kind != PasserbyKind.oncomingCar || p.pane != Pane.windshield) {
        continue;
      }
      if (!p.visible(motion.seconds)) continue;
      final d = 2 + (1 - p.progress(motion.seconds)) * 150;
      final x = scene.highway ? -12.5 : -3.6;
      add(d, () => _car(canvas, x, d, p.seed, rear: false));
    }
  }

  /// 마주 오는 차 전조등 (밤·터널)
  void _oncomingLights(Canvas canvas) {
    for (final p in spawner.active) {
      if (p.kind != PasserbyKind.oncomingCar || p.pane != Pane.windshield) {
        continue;
      }
      if (!p.visible(motion.seconds)) continue;
      final d = 2 + (1 - p.progress(motion.seconds)) * 150;
      final x = scene.highway ? -12.5 : -3.6;
      final glow = Paint()
        ..color = const Color(0xCCFFF2C8)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, math.max(1.5, 0.5 * _f / d));
      for (final dx in [-0.65, 0.65]) {
        canvas.drawCircle(
            _p(x + dx, 0.65, d), math.max(1.2, 0.35 * _f / d), glow);
      }
    }
  }

  /// 밤: 우리 차 전조등 빛, 가로등 불빛, 마주 오는 차 불빛
  void _nightLights(Canvas canvas, Size size) {
    canvas.drawPath(
        _quad(
            _p(-1.4, 0, 1.6), _p(1.6, 0, 1.6), _p(3.2, 0, 38), _p(-2.6, 0, 38)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: const [Color(0x55FFF0C8), Color(0x00FFF0C8)],
          ).createShader(
              Rect.fromLTRB(0, _p(0, 0, 38).dy, size.width, size.height))
          ..blendMode = BlendMode.plus);
    if (scene.kind == SceneKind.city || scene.highway) {
      final lamp = Paint()
        ..color = _Palette.lamp.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final xs = scene.highway ? const [-8.0] : const [-5.2, 2.2];
      _along(scene.highway ? 40 : 28, 2, 200, (d, _) {
        for (final x in xs) {
          canvas.drawCircle(_p(x, 7.1, d), math.max(1, 0.45 * _f / d), lamp);
        }
      });
    }
    if (scene.kind == SceneKind.city) {
      // 건물 창에 켜진 불
      final lit = Paint()..color = _Palette.lamp.withValues(alpha: 0.85);
      for (final side in [-1, 1]) {
        final x = side < 0 ? -9.0 : 6.0;
        _along(12, 1.0, 180, (d, i) {
          final idx = i * 2 + (side < 0 ? 0 : 1);
          final hgt = 7 + _rand(idx, 81) * 16;
          var k = 0;
          for (var fy = 2.5; fy < hgt - 1; fy += 3) {
            for (var fd = 1.5; fd < 10; fd += 3) {
              if (_rand(idx * 41 + k++, 83) < 0.45) {
                canvas.drawPath(
                    _quad(_p(x, fy, d + fd), _p(x, fy + 1.2, d + fd),
                        _p(x, fy + 1.2, d + fd + 1.2), _p(x, fy, d + fd + 1.2)),
                    lit);
              }
            }
          }
        });
      }
    }
    _oncomingLights(canvas);
  }

  /// 터널: 둥근 단면이 반복되고, 천장 등이 빠르게 다가오며, 끝에 출구 빛이 보인다.
  void _tunnel(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = const Color(0xFF2B2622));
    Path arch(double d) {
      final l = _p(-6.2, 0, d), r = _p(3.2, 0, d);
      final top = _p(-1.5, 6.3, d);
      final sh = _p(-6.2, 4.3, d).dy;
      return Path()
        ..moveTo(l.dx, l.dy)
        ..lineTo(l.dx, sh)
        ..quadraticBezierTo(l.dx, top.dy, top.dx, top.dy)
        ..quadraticBezierTo(r.dx, top.dy, r.dx, sh)
        ..lineTo(r.dx, r.dy)
        ..close();
    }

    // 출구 빛
    canvas.drawPath(
        arch(230),
        Paint()
          ..color = const Color(0xFFFFF4DA)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    // 벽 단면 고리: 멀수록 어둡고 주황빛이 옅다
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _along(10, 1.5, 200, (d, _) {
      ring.color = Color.lerp(const Color(0xFF8A6A48), const Color(0xFF2B2622),
          (d / 200).clamp(0.0, 1.0))!;
      canvas.drawPath(arch(d), ring);
    });
    canvas.drawPath(
        _quad(_p(-6.2, 0, 230), _p(3.2, 0, 230), Offset(w * 1.2, h),
            Offset(-w * 0.2, h)),
        Paint()..color = const Color(0xFF3A3530));
    _along(8, 1.2, 160, (d, _) {
      _stripe(canvas, -1.7, 0.12, d, d + 4,
          Paint()..color = const Color(0xFFD9C9A8));
    });
    final lamp = Paint()..color = const Color(0xFFFFE2A8);
    final glow = Paint()
      ..color = _Palette.sodium.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    _along(8, 1.5, 200, (d, _) {
      for (final x in const [-4.2, 1.2]) {
        final a = _p(x, 5.4, d), b = _p(x, 5.4, d + 2.5);
        canvas
          ..drawLine(a, b, glow..strokeWidth = math.max(2, 1.2 * _f / d))
          ..drawLine(a, b, lamp..strokeWidth = math.max(1, 0.4 * _f / d));
      }
    });
    _oncomingLights(canvas);
  }

  @override
  bool shouldRepaint(_WindshieldPainter oldDelegate) =>
      oldDelegate.scene != scene;
}
