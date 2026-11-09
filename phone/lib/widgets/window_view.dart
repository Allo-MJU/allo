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
/// 그림은 D 아트가 나오기 전까지 코드로 그린 임시 장면이다. 캐릭터(말랑한 비닐 토이)와
/// 맞추려고 둥근 덩어리와 클레이 질감으로 그린다. 장면마다
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

/// 창밖 장면 팔레트. Figma ALLO Design System 변수와 같은 값을 쓴다.
/// 아래 '파생' 색만 장면용으로 섞어 만든 값이다.
abstract final class _Palette {
  // Primitives
  static const shellYellow = Color(0xFFFCCC44);
  static const growthGreen = Color(0xFF1D9965);
  static const actionGreen = Color(0xFF146B49);
  static const logoYellow = Color(0xFFFFD34E);
  static const logoMint = Color(0xFF58D8A0);
  static const logoGround = Color(0xFF1E3A2F);
  static const greenSoft = Color(0xFFF4F7F3);
  // Species
  static const seaBase = Color(0xFFA9DCDA); // sea_mist/base
  static const seaDeep = Color(0xFF4F8790); // sea_mist/deep
  static const rainBase = Color(0xFF4A90D0); // puddle_pip/base
  static const rainTint = Color(0xFFE3EEF8); // puddle_pip/tint
  static const sproutBase = Color(0xFF7F9140); // road_sprout/base
  static const sproutDeep = Color(0xFF4E5A28); // road_sprout/deep
  static const duneBase = Color(0xFFC8734A); // dune_roller/base
  static const duneAccent = Color(0xFFF1C79E); // dune_roller/accent
  static const duneDeep = Color(0xFF6E3D25); // dune_roller/deep
  // 파생
  static const skyTop = Color(0xFFCFEDE8); // sea_mist 를 옅게 푼 낮 하늘
  static const skyBottom = Color(0xFFFCE8D6); // 캐릭터 시트 배경의 크림·피치
  static const rainSkyTop = Color(0xFFC9D8E2); // 비 오는 낮: puddle_pip tint 를 흐리게
  static const rainSkyBottom = Color(0xFFEDEFF0);
  static const sand = Color(0xFFFBE3C2);
  static const nightTop = Color(0xFF1B2A4A); // 따뜻한 남색
  static const tunnelTop = Color(0xFF2E2822);
  static const tunnelRib = Color(0xFF3D352E);
  static const doorTop = Color(0xFF2F5444);
  static const shoulder = Color(0xFF55615A);
}

/// 말랑한 점토(클레이) 질감: 아래로 비낀 짙은 그림자 + 위가 밝은 몸통 + 왼쪽 위 광택.
class _Clay {
  _Clay(Color light, Color base, Color deep, {double shine = 0.35})
      : body = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [light, base],
          ).createShader(_unit),
        shadow = Paint()..color = deep,
        gloss = Paint()..color = Colors.white.withValues(alpha: shine);

  factory _Clay.of(Color base, Color deep, {double shine = 0.35}) =>
      _Clay(Color.lerp(base, Colors.white, 0.3)!, base, deep, shine: shine);

  static const _unit = Rect.fromLTWH(0, 0, 1, 1);

  final Paint body;
  final Paint shadow;
  final Paint gloss;

  static final cloud = _Clay(
      Colors.white, const Color(0xFFFDF1E6), const Color(0xFFF2D3C4),
      shine: 0.7);
  static final cloudNight = _Clay(
      const Color(0xFF3A4A6E), const Color(0xFF2C3B5C), const Color(0xFF1E2A44),
      shine: 0.12);
  static final cloudRain = _Clay(
      const Color(0xFFF1F4F7), const Color(0xFFD5DEE6), const Color(0xFFAEBBC7),
      shine: 0.4);
  static final island = _Clay.of(
      Color.lerp(_Palette.logoMint, _Palette.seaDeep, 0.35)!, _Palette.seaDeep);
  static final ridge = _Clay.of(
      Color.lerp(_Palette.sproutBase, _Palette.skyTop, 0.55)!,
      Color.lerp(_Palette.sproutBase, _Palette.skyTop, 0.3)!,
      shine: 0.25);
  static final ridgeNight = _Clay.of(
      Color.lerp(_Palette.sproutDeep, _Palette.nightTop, 0.45)!,
      Color.lerp(_Palette.sproutDeep, _Palette.nightTop, 0.7)!,
      shine: 0.1);
  static final farHillNight = _Clay.of(
      Color.lerp(_Palette.actionGreen, _Palette.nightTop, 0.45)!,
      Color.lerp(_Palette.actionGreen, _Palette.nightTop, 0.7)!,
      shine: 0.1);
  static final meadow = _Clay.of(_Palette.sproutBase, _Palette.sproutDeep);
  static final pine = _Clay.of(
      Color.lerp(_Palette.sproutBase, _Palette.sproutDeep, 0.45)!,
      Color.lerp(_Palette.sproutDeep, _Palette.logoGround, 0.5)!);
  static final farHill = _Clay.of(
      Color.lerp(_Palette.growthGreen, _Palette.skyBottom, 0.6)!,
      Color.lerp(_Palette.growthGreen, _Palette.skyBottom, 0.35)!,
      shine: 0.25);
  static final leaf = _Clay.of(_Palette.growthGreen, _Palette.actionGreen);
  static final towers = [
    _Palette.duneBase,
    _Palette.rainBase,
    _Palette.seaDeep,
    _Palette.sproutBase,
  ].map((c) => _Clay.of(c, Color.lerp(c, Colors.black, 0.35)!)).toList();
}

/// 0~1 단위 상자 안에 한 번만 만들어 두는 모양. 그릴 때 캔버스 변환으로 크기를 맞춘다.
abstract final class _Shapes {
  static final oval = Path()..addOval(const Rect.fromLTWH(0, 0, 1, 1));

  /// 위가 통통하게 둥근 언덕·섬
  static final gumdrop = Path()
    ..moveTo(0, 1)
    ..cubicTo(0, 0.15, 0.22, 0, 0.5, 0)
    ..cubicTo(0.78, 0, 1, 0.15, 1, 1)
    ..close();

  static final cloud = Path()
    ..addOval(const Rect.fromLTWH(0.0, 0.42, 0.42, 0.52))
    ..addOval(const Rect.fromLTWH(0.18, 0.06, 0.44, 0.8))
    ..addOval(const Rect.fromLTWH(0.46, 0.22, 0.38, 0.66))
    ..addOval(const Rect.fromLTWH(0.64, 0.46, 0.36, 0.5))
    ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.12, 0.6, 0.76, 0.38),
        const Radius.circular(0.19)));

  /// 둥근 덩어리 세 개를 겹친 나무 머리
  static final canopy = Path()
    ..addOval(const Rect.fromLTWH(0.0, 0.34, 0.56, 0.62))
    ..addOval(const Rect.fromLTWH(0.22, 0.0, 0.56, 0.64))
    ..addOval(const Rect.fromLTWH(0.44, 0.32, 0.56, 0.64));

  static final tower = Path()
    ..addRRect(RRect.fromRectAndCorners(
      const Rect.fromLTWH(0, 0, 1, 1),
      topLeft: const Radius.elliptical(0.32, 0.12),
      topRight: const Radius.elliptical(0.32, 0.12),
    ));
}

const _defaultGloss = Rect.fromLTWH(0.24, 0.12, 0.26, 0.16);

/// [unit] 모양을 [box] 크기로 늘려 클레이 질감으로 그린다.
void _drawClay(Canvas canvas, Rect box, Path unit, _Clay clay,
    {Rect gloss = _defaultGloss}) {
  canvas
    ..save()
    ..translate(box.left, box.top)
    ..scale(box.width, box.height)
    ..translate(0, 0.06)
    ..drawPath(unit, clay.shadow)
    ..translate(0, -0.06)
    ..drawPath(unit, clay.body)
    ..drawOval(gloss, clay.gloss)
    ..restore();
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
  Paint _band(String key, Size size, Rect r, List<Color> colors) {
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
          ).createShader(r));
  }

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
    final rainy = scene.rainLevel > 0;
    canvas.drawRect(
        all,
        _band(
            scene.night
                ? 'skyN'
                : rainy
                    ? 'skyR'
                    : 'sky',
            size,
            all,
            scene.night
                ? const [_Palette.nightTop, _Palette.logoGround]
                : rainy
                    ? const [_Palette.rainSkyTop, _Palette.rainSkyBottom]
                    : const [_Palette.skyTop, _Palette.skyBottom]));
    if (scene.night) _stars(canvas, w, h);
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
      // 하늘은 그대로 두고 땅 쪽만 어둡게 덮는다. 달·별이 탁해지지 않게 한다
      canvas.drawRect(
          all,
          _band('veil', size, all, [
            _Palette.nightTop.withValues(alpha: 0),
            _Palette.nightTop.withValues(alpha: 0.5),
          ]));
      // 밤 도시 창문은 어둠 위에 다시 켜서 따뜻하게 빛나게 한다
      if (scene.kind == SceneKind.city) {
        _cityWindows(canvas, size, m, Paint()..color = _Palette.logoYellow);
      }
    }
  }

  void _stars(Canvas canvas, double w, double h) {
    final p = Paint()..color = _Palette.logoYellow.withValues(alpha: 0.85);
    for (var i = 0; i < 34; i++) {
      canvas.drawCircle(Offset(_rand(i, 3) * w, _rand(i, 4) * h * 0.45),
          1 + _rand(i, 5) * 1.4, p);
    }
    final moon = Offset(w * 0.82, h * 0.17);
    canvas
      ..drawCircle(moon, 30,
          Paint()..color = _Palette.shellYellow.withValues(alpha: 0.08))
      ..drawCircle(moon, 21,
          Paint()..color = _Palette.shellYellow.withValues(alpha: 0.12))
      ..drawCircle(moon, 14, Paint()..color = _Palette.logoYellow)
      // 초승달: 하늘색 원으로 한쪽을 가린다
      ..drawCircle(
          moon + const Offset(6, -4), 11.5, Paint()..color = _Palette.nightTop);
  }

  void _clouds(Canvas canvas, double w, double h, double m) {
    final clay = scene.night
        ? _Clay.cloudNight
        : scene.rainLevel > 0
            ? _Clay.cloudRain
            : _Clay.cloud;
    _repeat(w, 210, m * _cloudPx + motion.seconds * 3, (x, i) {
      if (_rand(i, 11) < 0.3) return;
      final cw = 64 + _rand(i, 12) * 48;
      final y = h * (0.05 + _rand(i, 13) * 0.16);
      _drawClay(canvas, Rect.fromLTWH(x + _rand(i, 14) * 60, y, cw, cw * 0.5),
          _Shapes.cloud, clay,
          gloss: const Rect.fromLTWH(0.26, 0.16, 0.22, 0.16));
    });
  }

  void _coast(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.52;
    // 먼 섬: 통통한 민트 언덕
    _repeat(w, 260, m * _farPx, (x, i) {
      final iw = 90 + _rand(i, 1) * 90;
      final ih = iw * (0.32 + _rand(i, 2) * 0.14);
      _drawClay(canvas, Rect.fromLTWH(x + 40, horizon - ih + 4, iw, ih),
          _Shapes.gumdrop, _Clay.island,
          gloss: const Rect.fromLTWH(0.28, 0.14, 0.24, 0.16));
    });
    final sea = Rect.fromLTRB(0, horizon, w, h);
    canvas.drawRect(sea,
        _band('sea', size, sea, const [_Palette.seaBase, _Palette.seaDeep]));
    // 물결: 둥근 캡슐
    final cap = Paint()..color = _Palette.greenSoft.withValues(alpha: 0.75);
    for (var row = 0; row < 3; row++) {
      final y = horizon + 12 + row * 16.0;
      _repeat(w, 80, m * _midPx * (0.6 + row * 0.3), (x, i) {
        final len = 14 + _rand(i, row) * 18;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x + _rand(i, row + 5) * 40, y, len, 4.0 + row),
                const Radius.circular(4)),
            cap);
      });
    }
    // 모래사장: 위가 둥근 언덕
    final beach = Rect.fromLTRB(-20, h * 0.76, w + 20, h + 20);
    canvas.drawRRect(
        RRect.fromRectAndCorners(beach,
            topLeft: Radius.elliptical(w * 0.5, 26),
            topRight: Radius.elliptical(w * 0.5, 26)),
        _band('sand', size, beach, const [_Palette.sand, _Palette.duneAccent]));
  }

  void _mountain(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    // 먼 능선: 둥근 봉우리
    _repeat(w, 170, m * _farPx, (x, i) {
      final rh = h * (0.3 + _rand(i, 1) * 0.18);
      final rw = 200 + _rand(i, 3) * 60;
      _drawClay(canvas, Rect.fromLTWH(x - 30, h * 0.64 - rh, rw, rh),
          _Shapes.gumdrop, scene.night ? _Clay.ridgeNight : _Clay.ridge,
          gloss: const Rect.fromLTWH(0.3, 0.1, 0.2, 0.14));
    });
    // 가까운 풀밭 언덕
    _repeat(w, 260, m * _midPx * 0.5, (x, i) {
      final r = 120 + _rand(i, 4) * 50;
      _drawClay(
          canvas,
          Rect.fromCenter(
              center: Offset(x + 130, h * 0.66 + r * 0.45),
              width: r * 2.4,
              height: r),
          _Shapes.oval,
          _Clay.meadow,
          gloss: const Rect.fromLTWH(0.3, 0.06, 0.24, 0.1));
    });
    final ground = Rect.fromLTRB(0, h * 0.72, w, h);
    canvas.drawRect(
        ground,
        _band('meadow', size, ground,
            const [_Palette.sproutBase, _Palette.sproutDeep]));
    // 숲: 산 장면에 섞는다 (이슈 #45 결정). 둥근 덩어리 나무
    final trunk = Paint()..color = _Palette.duneDeep;
    _repeat(w, 38, m * _midPx, (x, i) {
      final s = 28 + _rand(i, 2) * 18;
      final base = h * 0.78;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x + s * 0.42, base - s * 0.34, s * 0.16, s * 0.34),
              const Radius.circular(3)),
          trunk);
      _drawClay(canvas, Rect.fromLTWH(x, base - s * 1.1, s, s * 0.86),
          _Shapes.canopy, _Clay.pine,
          gloss: const Rect.fromLTWH(0.3, 0.1, 0.22, 0.16));
    });
  }

  void _city(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    final far = Paint()
      ..color = scene.night
          ? Color.lerp(_Palette.nightTop, _Palette.seaDeep, 0.45)!
          : Color.lerp(_Palette.rainTint, _Palette.seaBase, 0.4)!;
    _repeat(w, 48, m * _farPx, (x, i) {
      final top = h * (0.22 + _rand(i, 1) * 0.28);
      canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTRB(x, top, x + 40, h * 0.74),
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14)),
          far);
    });
    _repeat(w, 92, m * _midPx, (x, i) {
      final top = h * (0.3 + _rand(i, 2) * 0.22);
      final clay = _Clay.towers[(_rand(i, 6) * 4).floor() % 4];
      _drawClay(
          canvas, Rect.fromLTRB(x, top, x + 72, h * 0.86), _Shapes.tower, clay,
          gloss: const Rect.fromLTWH(0.1, 0.06, 0.14, 0.4));
    });
    if (!scene.night) {
      _cityWindows(canvas, size, m,
          Paint()..color = _Palette.greenSoft.withValues(alpha: 0.85));
    }
  }

  /// 도시 건물의 둥근 창. 낮에는 크림색, 밤에는 어둠 위에 노랗게 켠다.
  void _cityWindows(Canvas canvas, Size size, double m, Paint lit) {
    final h = size.height;
    _repeat(size.width, 92, m * _midPx, (x, i) {
      final top = h * (0.3 + _rand(i, 2) * 0.22);
      for (var wy = top + 16; wy < h * 0.8; wy += 18) {
        for (var wx = x + 24; wx < x + 66; wx += 18) {
          canvas.drawCircle(Offset(wx, wy), 4, lit);
        }
      }
    });
  }

  void _road(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    _repeat(w, 220, m * _farPx, (x, i) {
      final r = 80 + _rand(i, 1) * 60;
      _drawClay(
          canvas,
          Rect.fromCircle(
              center: Offset(x + 110, h * 0.66 + r * 0.55), radius: r),
          _Shapes.oval,
          scene.night ? _Clay.farHillNight : _Clay.farHill,
          gloss: const Rect.fromLTWH(0.28, 0.08, 0.22, 0.1));
    });
    final ground = Rect.fromLTRB(0, h * 0.66, w, h);
    canvas.drawRect(
        ground,
        _band('field', size, ground, [
          Color.lerp(_Palette.growthGreen, _Palette.greenSoft, 0.45)!,
          Color.lerp(_Palette.growthGreen, _Palette.greenSoft, 0.2)!,
        ]));
    // 막대사탕 나무와 둥근 덤불
    final trunk = Paint()..color = _Palette.duneDeep;
    _repeat(w, 150, m * _midPx, (x, i) {
      final base = h * 0.8;
      if (_rand(i, 4) > 0.55) {
        _drawClay(canvas, Rect.fromLTWH(x + 56, base - 20, 44, 22),
            _Shapes.oval, _Clay.leaf);
      }
      if (_rand(i, 2) < 0.35) return;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 9, base - 26, 7, 26),
              const Radius.circular(3.5)),
          trunk);
      _drawClay(
          canvas,
          Rect.fromCircle(center: Offset(x + 12.5, base - 36), radius: 17),
          _Shapes.oval,
          _Clay.leaf);
    });
  }

  void _near(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    final edge = h * 0.9;
    final shoulder = Rect.fromLTRB(0, edge, w, h);
    canvas
      ..drawRect(
          shoulder,
          _band('shoulder', size, shoulder,
              const [_Palette.shoulder, _Palette.logoGround]))
      ..drawLine(
          Offset(0, edge + 1.5),
          Offset(w, edge + 1.5),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.18)
            ..strokeWidth = 3);
    if (scene.highway) {
      // 고속도로: 둥근 반투명 방음벽 판
      final panel = Paint()..color = _Palette.rainTint.withValues(alpha: 0.72);
      final shine = Paint()..color = Colors.white.withValues(alpha: 0.55);
      _repeat(w, 64, m * _nearPx, (x, _) {
        canvas
          ..drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTRB(x + 3, h * 0.6, x + 61, edge + 2),
                  const Radius.circular(10)),
              panel)
          ..drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(x + 11, h * 0.6 + 6, 26, 5),
                  const Radius.circular(3)),
              shine);
      });
      return;
    }
    // 일반 도로: 노란 모자를 쓴 둥근 가드레일
    final post = Paint()..color = _Palette.greenSoft;
    final cap = Paint()..color = _Palette.shellYellow;
    final railShadow = Paint()
      ..color = Color.lerp(_Palette.greenSoft, Colors.black, 0.35)!;
    _repeat(w, 44, m * _nearPx, (x, _) {
      canvas
        ..drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, h * 0.8, 7, edge - h * 0.8 + 4),
                const Radius.circular(3.5)),
            post)
        ..drawCircle(Offset(x + 3.5, h * 0.8), 5, cap);
    });
    final rail = Rect.fromLTRB(-10, h * 0.815, w + 10, h * 0.815 + 8);
    canvas
      ..drawRRect(
          RRect.fromRectAndRadius(
              rail.shift(const Offset(0, 3)), const Radius.circular(4)),
          railShadow)
      ..drawRRect(
          RRect.fromRectAndRadius(rail, const Radius.circular(4)), post);
  }

  void _tunnel(Canvas canvas, Size size, double m) {
    final w = size.width;
    final h = size.height;
    final all = Offset.zero & size;
    canvas.drawRect(
        all,
        _band('tunnel', size, all,
            const [_Palette.tunnelTop, _Palette.logoGround]));
    // 둥근 벽 갈비
    final rib = Paint()..color = _Palette.tunnelRib;
    _repeat(w, 34, m * _nearPx, (x, _) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, h * 0.3, 14, h * 0.62),
              const Radius.circular(7)),
          rib);
    });
    // 터널 조명이 빠르게 지나간다
    final lamp = Paint()..color = _Palette.shellYellow;
    final shine = Paint()..color = _Palette.logoYellow.withValues(alpha: 0.9);
    final glow = Paint()
      ..color = _Palette.shellYellow.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    _repeat(w, 110, m * _midPx * 2, (x, _) {
      final r = Rect.fromLTWH(x, h * 0.14, 50, 12);
      canvas
        ..drawRRect(
            RRect.fromRectAndRadius(r.inflate(8), const Radius.circular(14)),
            glow)
        ..drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), lamp)
        ..drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x + 8, h * 0.14 + 2, 18, 3),
                const Radius.circular(2)),
            shine);
    });
    canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(0, h * 0.9, w, h),
            topLeft: const Radius.circular(10),
            topRight: const Radius.circular(10)),
        Paint()..color = const Color(0xFF2A2A26));
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
    // 창에 맺힌 동그란 물방울 (움직이지 않는다)
    final bead = Paint()..color = _Palette.rainTint.withValues(alpha: 0.35);
    final beadShine = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (var i = 0; i < level * 6; i++) {
      final c = Offset(_rand(i, 21) * w, _rand(i, 22) * h);
      final r = 3 + _rand(i, 23) * 3;
      canvas
        ..drawCircle(c, r, bead)
        ..drawCircle(c + Offset(-r * 0.35, -r * 0.35), r * 0.3, beadShine);
    }
    // 빗줄기: 둥근 끝의 짧은 캡슐. 빨리 달릴수록 더 눕는다
    final p = Paint()
      ..color = _Palette.rainTint.withValues(alpha: 0.8)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final slant = -(3 + speedKph / 100 * 12);
    final t = motion.seconds;
    for (var i = 0; i < level * 28; i++) {
      final fall = 420 + _rand(i, 7) * 220;
      final y = (_rand(i, 8) * h + t * fall) % (h + 20) - 10;
      final x = (_rand(i, 9) * w + t * slant * 20) % w;
      canvas.drawLine(Offset(x, y), Offset(x + slant * 0.7, y + 10), p);
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.speedKph != speedKph;
}
