import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';

import '../scene/window_scene.dart';
import '../theme/allo_colors.dart';

/// 차량 신호로 고르는 정지 창밖 그림. 최신 디자인(#49 v4)은 배경 이동을 금지한다.
/// 장면 변경만 페이드하며 [child]의 알·생물은 창 앞에 유지한다.
class WindowView extends StatefulWidget {
  const WindowView({
    super.key,
    required this.vehicle,
    this.child,
    this.height = 240,
    this.nowMs,
  });

  final VehicleState? vehicle;
  final Widget? child;
  final double height;

  /// 장면 유지 시간 계산용 시계. 테스트에서 주입한다.
  final int Function()? nowMs;

  @override
  State<WindowView> createState() => _WindowViewState();
}

class _WindowViewState extends State<WindowView>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: AlloPresentation.fadeDuration,
    animationBehavior: AnimationBehavior.preserve,
  );
  WindowScene? _previous;
  final _stabilizer = SceneStabilizer();
  final _clock = Stopwatch()..start();
  late WindowScene _scene;

  int _now() => widget.nowMs?.call() ?? _clock.elapsedMilliseconds;

  @override
  void initState() {
    super.initState();
    _scene =
        _stabilizer.update(WindowScene.fromVehicle(widget.vehicle), _now());
  }

  @override
  void didUpdateWidget(WindowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vehicle, widget.vehicle)) {
      final next =
          _stabilizer.update(WindowScene.fromVehicle(widget.vehicle), _now());
      if ((_scene.kind, _scene.night, _scene.highway, _scene.rainLevel) !=
          (next.kind, next.night, next.highway, next.rainLevel)) {
        _previous = _scene;
        _fade.forward(from: 0);
      }
      _scene = next;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _scene;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: _describe(s),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            // 차 문 안쪽 패널과 창틀
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AlloColors.softBackground,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              bottom: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedBuilder(
                  animation: _fade,
                  builder: (_, __) {
                    final opacity =
                        AlloPresentation.standardCurve.transform(_fade.value);
                    Widget layer(WindowScene scene) =>
                        Stack(fit: StackFit.expand, children: [
                          CustomPaint(painter: _ScenePainter(scene)),
                          CustomPaint(painter: _RainPainter(scene.rainLevel)),
                        ]);
                    return Stack(fit: StackFit.expand, children: [
                      if (_previous != null && opacity < 1)
                        Opacity(opacity: 1 - opacity, child: layer(_previous!)),
                      Opacity(opacity: opacity, child: layer(s)),
                    ]);
                  },
                ),
              ),
            ),
            if (widget.child != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(child: widget.child),
              ),
          ],
        ),
      ),
    );
  }
}

String _describe(WindowScene s) {
  const names = {
    SceneKind.road: '도로',
    SceneKind.coast: '바다',
    SceneKind.mountain: '산',
    SceneKind.city: '도시',
    SceneKind.tunnel: '터널',
  };
  return [
    '창밖: ${names[s.kind]}',
    if (s.highway) '고속도로',
    if (s.rainLevel > 0) '비',
    if (s.night) '밤',
    if (!s.moving) '멈춤',
  ].join(', ');
}

/// 같은 장면은 시간·속도가 바뀌어도 같은 그림을 유지한다.
double _rand(int i, int salt) {
  final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

/// 정지 배경에 반복 요소를 일정 간격으로 배치한다.
void _repeat(
    double width, double period, void Function(double x, int index) draw) {
  for (var j = -1; j * period < width + period; j++) {
    draw(j * period, j);
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene);

  final WindowScene scene;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint();

    if (scene.kind == SceneKind.tunnel) {
      _tunnel(canvas, w, h);
      return;
    }

    // 하늘
    final sky = Offset.zero & size;
    fill.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: scene.night
          ? const [Color(0xFF0E1838), Color(0xFF2B3A67)]
          : const [Color(0xFF8FD3F4), Color(0xFFDDF3FB)],
    ).createShader(sky);
    canvas.drawRect(sky, fill);
    fill.shader = null;
    if (scene.night) _stars(canvas, w, h);

    switch (scene.kind) {
      case SceneKind.coast:
        _coast(canvas, w, h);
      case SceneKind.mountain:
        _mountain(canvas, w, h);
      case SceneKind.city:
        _city(canvas, w, h);
      case SceneKind.road:
      case SceneKind.tunnel:
        _road(canvas, w, h);
    }

    _near(canvas, w, h);

    if (scene.night) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = const Color(0xFF0B1230).withValues(alpha: 0.45));
    }
  }

  void _stars(Canvas canvas, double w, double h) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(Offset(_rand(i, 3) * w, _rand(i, 4) * h * 0.45),
          0.8 + _rand(i, 5), p);
    }
    canvas.drawCircle(Offset(w * 0.82, h * 0.16), 12,
        Paint()..color = const Color(0xFFFFF4C2));
  }

  void _coast(Canvas canvas, double w, double h) {
    final horizon = h * 0.5;
    // 먼 섬
    final island = Paint()..color = const Color(0xFF6E8FA3);
    _repeat(w, 260, (x, i) {
      final r = 30 + _rand(i, 1) * 40;
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x + 120, horizon), width: r * 3, height: r),
          island);
    });
    canvas.drawRect(Rect.fromLTRB(0, horizon, w, h),
        Paint()..color = const Color(0xFF2E86C1));
    // 물결
    final wave = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var row = 0; row < 3; row++) {
      final y = horizon + 14 + row * 18.0;
      _repeat(w, 70, (x, i) {
        canvas.drawLine(Offset(x + _rand(i, row) * 30, y),
            Offset(x + _rand(i, row) * 30 + 18, y), wave);
      });
    }
    // 모래사장
    canvas.drawRect(Rect.fromLTRB(0, h * 0.78, w, h),
        Paint()..color = const Color(0xFFE8D3A2));
  }

  void _mountain(Canvas canvas, double w, double h) {
    final ridge = Paint()..color = const Color(0xFF7C93A6);
    _repeat(w, 170, (x, i) {
      final peak = h * (0.18 + _rand(i, 1) * 0.2);
      canvas.drawPath(
          Path()
            ..moveTo(x - 40, h * 0.62)
            ..lineTo(x + 85, peak)
            ..lineTo(x + 210, h * 0.62)
            ..close(),
          ridge);
    });
    canvas.drawRect(Rect.fromLTRB(0, h * 0.6, w, h),
        Paint()..color = const Color(0xFF6FA35A));
    // 숲: 산 장면에 섞는다 (이슈 #45 결정)
    final tree = Paint()..color = const Color(0xFF2F6B3A);
    _repeat(w, 34, (x, i) {
      final th = 34 + _rand(i, 2) * 30;
      final base = h * 0.74;
      canvas.drawPath(
          Path()
            ..moveTo(x, base)
            ..lineTo(x + 14, base - th)
            ..lineTo(x + 28, base)
            ..close(),
          tree);
    });
  }

  void _city(Canvas canvas, double w, double h) {
    final far = Paint()..color = const Color(0xFF9AA6BC);
    _repeat(w, 44, (x, i) {
      final top = h * (0.2 + _rand(i, 1) * 0.3);
      canvas.drawRect(Rect.fromLTRB(x, top, x + 38, h * 0.7), far);
    });
    final near = Paint()..color = const Color(0xFF5D6B82);
    final lit = Paint()
      ..color = scene.night ? const Color(0xFFFFE08A) : const Color(0xFFBFD8EE);
    _repeat(w, 90, (x, i) {
      final top = h * (0.3 + _rand(i, 2) * 0.25);
      final rect = Rect.fromLTRB(x, top, x + 70, h * 0.82);
      canvas.drawRect(rect, near);
      for (var wy = top + 10; wy < h * 0.78; wy += 16) {
        for (var wx = x + 8; wx < x + 62; wx += 14) {
          canvas.drawRect(Rect.fromLTWH(wx, wy, 7, 8), lit);
        }
      }
    });
  }

  void _road(Canvas canvas, double w, double h) {
    final hill = Paint()..color = const Color(0xFF9CC58A);
    _repeat(w, 220, (x, i) {
      final r = 80 + _rand(i, 1) * 60;
      canvas.drawCircle(Offset(x + 110, h * 0.68 + r * 0.6), r, hill);
    });
    canvas.drawRect(Rect.fromLTRB(0, h * 0.66, w, h),
        Paint()..color = const Color(0xFF8DBB6E));
    final trunk = Paint()..color = const Color(0xFF7A5A3A);
    final leaf = Paint()..color = const Color(0xFF4E8F45);
    _repeat(w, 150, (x, i) {
      if (_rand(i, 2) < 0.4) return;
      final base = h * 0.78;
      canvas.drawRect(Rect.fromLTWH(x + 8, base - 26, 6, 26), trunk);
      canvas.drawCircle(Offset(x + 11, base - 34), 16, leaf);
    });
  }

  void _near(Canvas canvas, double w, double h) {
    final edge = h * 0.9;
    canvas.drawRect(
        Rect.fromLTRB(0, edge, w, h), Paint()..color = const Color(0xFF55585E));
    if (scene.highway) {
      // 고속도로: 방음벽
      final panel = Paint()
        ..color = const Color(0xFFB7C7D3).withValues(alpha: 0.75);
      final seam = Paint()
        ..color = const Color(0xFF6D7C88)
        ..strokeWidth = 3;
      canvas.drawRect(Rect.fromLTRB(0, h * 0.62, w, edge), panel);
      _repeat(w, 64, (x, _) {
        canvas.drawLine(Offset(x, h * 0.62), Offset(x, edge), seam);
      });
      return;
    }
    // 일반 도로: 가드레일
    final post = Paint()..color = const Color(0xFF8A9099);
    final rail = Paint()
      ..color = const Color(0xFFC9CED6)
      ..strokeWidth = 5;
    _repeat(w, 40, (x, _) {
      canvas.drawRect(Rect.fromLTWH(x, h * 0.8, 4, edge - h * 0.8), post);
    });
    canvas.drawLine(Offset(0, h * 0.82), Offset(w, h * 0.82), rail);
  }

  void _tunnel(Canvas canvas, double w, double h) {
    canvas.drawRect(
        Rect.fromLTRB(0, 0, w, h), Paint()..color = const Color(0xFF2E2925));
    // 터널 조명은 고정 위치에 표시한다
    final lamp = Paint()..color = const Color(0xFFFFB347);
    final glow = Paint()
      ..color = const Color(0xFFFFB347).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    _repeat(w, 110, (x, _) {
      final r = Rect.fromLTWH(x, h * 0.16, 46, 8);
      canvas.drawRect(r.inflate(8), glow);
      canvas.drawRect(r, lamp);
    });
    final stripe = Paint()..color = const Color(0xFF433B35);
    _repeat(w, 30, (x, _) {
      canvas.drawRect(Rect.fromLTWH(x, h * 0.45, 12, h * 0.45), stripe);
    });
    canvas.drawRect(Rect.fromLTRB(0, h * 0.9, w, h),
        Paint()..color = const Color(0xFF3C3C3C));
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => oldDelegate.scene != scene;
}

class _RainPainter extends CustomPainter {
  _RainPainter(this.level);

  final int level;

  @override
  void paint(Canvas canvas, Size size) {
    if (level <= 0) return;
    final w = size.width;
    final h = size.height;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const slant = -9.0;
    for (var i = 0; i < level * 35; i++) {
      final y = _rand(i, 8) * h;
      final x = _rand(i, 9) * w;
      canvas.drawLine(Offset(x, y), Offset(x + slant, y + 14), p);
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) => oldDelegate.level != level;
}
