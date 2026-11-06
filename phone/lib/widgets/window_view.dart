import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../scene/window_scene.dart';

/// 창밖이 실제로 움직일지 정한다. 앱 진입점(main)에서만 켠다.
///
/// 기본값은 정지다. 끝나지 않는 스크롤 애니메이션이 있으면 위젯 테스트의
/// pumpAndSettle 이 끝나지 않기 때문이다. 정지 상태에서도 장면·비·밤은 그대로 그린다.
class SceneMotion extends InheritedWidget {
  const SceneMotion({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SceneMotion>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(SceneMotion oldWidget) =>
      oldWidget.enabled != enabled;
}

/// 차 안에서 본 창밖. `/vehicle` 의 envTags·속도에 따라 장면이 바뀐다 (이슈 #45).
///
/// 그림은 D 아트가 나오기 전까지 코드로 그린 임시 장면이다. 장면마다
/// 먼 배경·중간·가까운 배경 3겹을 서로 다른 속도로 흘려 원근감을 낸다.
/// [child] 는 창 앞(차 안)에 놓이는 알·캐릭터다.
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
  final _stabilizer = SceneStabilizer();
  final _motion = _Motion();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  late WindowScene _scene;
  bool _animate = false;

  int _now() => widget.nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _scene =
        _stabilizer.update(WindowScene.fromVehicle(widget.vehicle), _now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = SceneMotion.of(context) &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _syncTicker();
  }

  @override
  void didUpdateWidget(WindowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vehicle, widget.vehicle)) {
      _scene =
          _stabilizer.update(WindowScene.fromVehicle(widget.vehicle), _now());
      _syncTicker();
    }
  }

  void _syncTicker() {
    final run = _animate && (_scene.moving || _scene.rainLevel > 0);
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _motion.advance(_scene.speedKph / 3.6 * dt, dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _scene;
    return Semantics(
      label: _describe(s),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            // 차 문 안쪽 패널과 창틀
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF4A4E5A),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              bottom: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 800),
                      child: SizedBox.expand(
                        key: ValueKey((s.kind, s.night, s.highway)),
                        child: CustomPaint(painter: _ScenePainter(s, _motion)),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: s.rainLevel > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 600),
                      child: CustomPaint(
                          painter:
                              _RainPainter(s.rainLevel, s.speedKph, _motion)),
                    ),
                  ],
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

/// 달린 거리(m)와 흐른 시간(s). 매 프레임 바뀌므로 위젯을 다시 빌드하지 않고 painter 만 다시 그린다.
class _Motion extends ChangeNotifier {
  double meters = 0;
  double seconds = 0;

  void advance(double dm, double dt) {
    meters += dm;
    seconds += dt;
    notifyListeners();
  }
}

/// 0~1 사이의 고정 난수. 같은 위치의 나무·건물이 스크롤해도 모양이 바뀌지 않게 한다.
double _rand(int i, int salt) {
  final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

/// [period] 간격으로 반복되는 요소를 [offset] 만큼 왼쪽으로 흘려 그린다.
void _repeat(double width, double period, double offset,
    void Function(double x, int index) draw) {
  final shift = offset % period;
  final base = (offset / period).floor();
  for (var j = -1; j * period - shift < width + period; j++) {
    draw(j * period - shift, base + j);
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.motion) : super(repaint: motion);

  final WindowScene scene;
  final _Motion motion;

  // 겹마다 1m 당 흐르는 픽셀. 멀수록 느리다.
  static const _farPx = 0.6;
  static const _midPx = 3.0;
  static const _nearPx = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final m = motion.meters;
    final fill = Paint();

    if (scene.kind == SceneKind.tunnel) {
      _tunnel(canvas, w, h, m);
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
        _coast(canvas, w, h, m);
      case SceneKind.mountain:
        _mountain(canvas, w, h, m);
      case SceneKind.city:
        _city(canvas, w, h, m);
      case SceneKind.road:
      case SceneKind.tunnel:
        _road(canvas, w, h, m);
    }

    _near(canvas, w, h, m);

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

  void _coast(Canvas canvas, double w, double h, double m) {
    final horizon = h * 0.5;
    // 먼 섬
    final island = Paint()..color = const Color(0xFF6E8FA3);
    _repeat(w, 260, m * _farPx, (x, i) {
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
      _repeat(w, 70, m * _midPx * (0.6 + row * 0.3), (x, i) {
        canvas.drawLine(Offset(x + _rand(i, row) * 30, y),
            Offset(x + _rand(i, row) * 30 + 18, y), wave);
      });
    }
    // 모래사장
    canvas.drawRect(Rect.fromLTRB(0, h * 0.78, w, h),
        Paint()..color = const Color(0xFFE8D3A2));
  }

  void _mountain(Canvas canvas, double w, double h, double m) {
    final ridge = Paint()..color = const Color(0xFF7C93A6);
    _repeat(w, 170, m * _farPx, (x, i) {
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
    _repeat(w, 34, m * _midPx, (x, i) {
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

  void _city(Canvas canvas, double w, double h, double m) {
    final far = Paint()..color = const Color(0xFF9AA6BC);
    _repeat(w, 44, m * _farPx, (x, i) {
      final top = h * (0.2 + _rand(i, 1) * 0.3);
      canvas.drawRect(Rect.fromLTRB(x, top, x + 38, h * 0.7), far);
    });
    final near = Paint()..color = const Color(0xFF5D6B82);
    final lit = Paint()
      ..color = scene.night ? const Color(0xFFFFE08A) : const Color(0xFFBFD8EE);
    _repeat(w, 90, m * _midPx, (x, i) {
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

  void _road(Canvas canvas, double w, double h, double m) {
    final hill = Paint()..color = const Color(0xFF9CC58A);
    _repeat(w, 220, m * _farPx, (x, i) {
      final r = 80 + _rand(i, 1) * 60;
      canvas.drawCircle(Offset(x + 110, h * 0.68 + r * 0.6), r, hill);
    });
    canvas.drawRect(Rect.fromLTRB(0, h * 0.66, w, h),
        Paint()..color = const Color(0xFF8DBB6E));
    final trunk = Paint()..color = const Color(0xFF7A5A3A);
    final leaf = Paint()..color = const Color(0xFF4E8F45);
    _repeat(w, 150, m * _midPx, (x, i) {
      if (_rand(i, 2) < 0.4) return;
      final base = h * 0.78;
      canvas.drawRect(Rect.fromLTWH(x + 8, base - 26, 6, 26), trunk);
      canvas.drawCircle(Offset(x + 11, base - 34), 16, leaf);
    });
  }

  void _near(Canvas canvas, double w, double h, double m) {
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
      _repeat(w, 64, m * _nearPx, (x, _) {
        canvas.drawLine(Offset(x, h * 0.62), Offset(x, edge), seam);
      });
      return;
    }
    // 일반 도로: 가드레일
    final post = Paint()..color = const Color(0xFF8A9099);
    final rail = Paint()
      ..color = const Color(0xFFC9CED6)
      ..strokeWidth = 5;
    _repeat(w, 40, m * _nearPx, (x, _) {
      canvas.drawRect(Rect.fromLTWH(x, h * 0.8, 4, edge - h * 0.8), post);
    });
    canvas.drawLine(Offset(0, h * 0.82), Offset(w, h * 0.82), rail);
  }

  void _tunnel(Canvas canvas, double w, double h, double m) {
    canvas.drawRect(
        Rect.fromLTRB(0, 0, w, h), Paint()..color = const Color(0xFF2E2925));
    // 터널 조명이 빠르게 지나간다
    final lamp = Paint()..color = const Color(0xFFFFB347);
    final glow = Paint()
      ..color = const Color(0xFFFFB347).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    _repeat(w, 110, m * _midPx * 2, (x, _) {
      final r = Rect.fromLTWH(x, h * 0.16, 46, 8);
      canvas.drawRect(r.inflate(8), glow);
      canvas.drawRect(r, lamp);
    });
    final stripe = Paint()..color = const Color(0xFF433B35);
    _repeat(w, 30, m * _nearPx, (x, _) {
      canvas.drawRect(Rect.fromLTWH(x, h * 0.45, 12, h * 0.45), stripe);
    });
    canvas.drawRect(Rect.fromLTRB(0, h * 0.9, w, h),
        Paint()..color = const Color(0xFF3C3C3C));
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => oldDelegate.scene != scene;
}

class _RainPainter extends CustomPainter {
  _RainPainter(this.level, this.speedKph, this.motion) : super(repaint: motion);

  final int level;
  final double speedKph;
  final _Motion motion;

  @override
  void paint(Canvas canvas, Size size) {
    if (level <= 0) return;
    final w = size.width;
    final h = size.height;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    // 빨리 달릴수록 빗줄기가 더 눕는다
    final slant = -(3 + speedKph / 100 * 12);
    final t = motion.seconds;
    for (var i = 0; i < level * 35; i++) {
      final fall = 420 + _rand(i, 7) * 220;
      final y = (_rand(i, 8) * h + t * fall) % (h + 20) - 10;
      final x = (_rand(i, 9) * w + t * slant * 20) % w;
      canvas.drawLine(Offset(x, y), Offset(x + slant, y + 14), p);
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.speedKph != speedKph;
}
