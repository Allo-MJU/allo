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
/// 그림은 D 아트가 나오기 전까지 코드로 그린 임시 장면이다. 지브리풍 배경처럼
/// 현실적인 빛·대기 원근에 면 단위로 칠한 애니메이션 색을 섞는다. 장면마다
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
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_Palette.doorTop, _Palette.logoGround],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border:
                      Border.all(color: const Color(0x24FFFFFF), width: 1.5),
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
            // 창틀 안쪽의 민트 테두리: 창이 문에 박힌 장난감 창처럼 보이게 한다
            const Positioned(
              left: 12,
              right: 12,
              top: 12,
              bottom: 44,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    border: Border.fromBorderSide(
                        BorderSide(color: Color(0x5958D8A0), width: 3)),
                  ),
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

/// 0~1 사이의 부드러운 1차원 노이즈. 능선·숲 윤곽처럼 들쭉날쭉하지만 연속인 선을 만든다.
double _noise(double x, int seed) {
  final i = x.floor();
  final f = x - i;
  final t = f * f * (3 - 2 * f);
  final a = _rand(i, seed);
  return a + (_rand(i + 1, seed) - a) * t;
}

/// 큰 굴곡 + 중간 굴곡 + 잔 굴곡을 섞은 능선 높이(0~1).
double _ridge(double wx, int seed, {double scale = 1}) =>
    0.6 * _noise(wx / (190 * scale), seed) +
    0.3 * _noise(wx / (64 * scale), seed + 1) +
    0.1 * _noise(wx / (19 * scale), seed + 2);

/// 화면 폭만큼 [yAt] 을 따라 위 윤곽을 그리고 [bottom] 까지 채우는 경로.
Path _profile(double w, double bottom, double Function(double x) yAt,
    {double step = 5}) {
  final p = Path()..moveTo(-step, bottom);
  for (var x = -step; x <= w + step; x += step) {
    p.lineTo(x, yAt(x));
  }
  return p
    ..lineTo(w + step, bottom)
    ..close();
}

/// 창밖 장면 팔레트. 지브리풍 배경처럼 맑은 하늘색, 풀색, 크림빛 지평선을 쓴다.
/// 앱 쪽 색(문·창틀·알)은 Figma ALLO Design System 변수 값을 그대로 쓴다.
abstract final class _Palette {
  // Figma 변수
  static const logoGround = Color(0xFF1E3A2F);
  static const doorTop = Color(0xFF2F5444);

  // 하늘 (위 → 가운데 → 지평선)
  static const day = [Color(0xFF4F98D6), Color(0xFF93C6EA), Color(0xFFEFF3E2)];
  static const rain = [Color(0xFF75879A), Color(0xFFA2B0BC), Color(0xFFD3D8D5)];
  static const night = [
    Color(0xFF0E1838),
    Color(0xFF213565),
    Color(0xFF4C5E8E)
  ];

  // 땅
  static const farBlue = Color(0xFF6E97B4); // 먼 산: 대기 원근으로 푸르게 바랜다
  static const midGreen = Color(0xFF5E9150);
  static const forest = Color(0xFF355F3A);
  static const forestLit = Color(0xFF6E9E4C);
  static const meadow = Color(0xFF8CBF57);
  static const meadowDeep = Color(0xFF5A8C3C);
  static const trunk = Color(0xFF5B4434);
  static const sea = Color(0xFF3B88B3);
  static const seaHorizon = Color(0xFF9CCFDD);
  static const sand = Color(0xFFF0DDB4);
  static const sandDeep = Color(0xFFD9BC8A);
  static const verge = Color(0xFF4E7F3A);
  static const vergeDeep = Color(0xFF2F5228);

  // 마을 건물 (밝은 면, 그늘 면)
  static const walls = [
    (Color(0xFFF1E6CF), Color(0xFFCDBFA4)),
    (Color(0xFFE7B98F), Color(0xFFC08E68)),
    (Color(0xFFB9CDB0), Color(0xFF8FA788)),
    (Color(0xFFDCCB8E), Color(0xFFB3A26A)),
    (Color(0xFFAFC2D2), Color(0xFF8699AC)),
  ];
  static const roof = Color(0xFFB8634A);
  static const roofShade = Color(0xFF8E4836);
  static const glassDay = Color(0xFF5E7E9C);
  static const lamp = Color(0xFFFFD98A);

  static const steel = Color(0xFFC9CED0);
  static const steelShade = Color(0xFF7F888C);
  static const tunnelWall = [Color(0xFF6B5E50), Color(0xFF2B2622)];
  static const sodium = Color(0xFFFFB04A);
}

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
  _ScenePainter(this.scene, this.motion) : super(repaint: motion);

  final WindowScene scene;
  final _Motion motion;

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
    _forestBand(canvas, size, m * _midPx * 0.5, h * 0.7, h * 0.065,
        _Palette.forest, _Palette.forestLit);
    final ground = Rect.fromLTRB(0, h * 0.8, w, h);
    canvas.drawRect(
        ground,
        _band('meadow', size, ground,
            const [_Palette.meadow, _Palette.meadowDeep]));
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
    // 유리창에 맺힌 물방울: 바깥 풍경이 비쳐 아래가 어둡고 위에 반짝임이 있다
    final body = Paint()..color = Colors.white.withValues(alpha: 0.16);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55203040);
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.85);
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
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.speedKph != speedKph;
}
