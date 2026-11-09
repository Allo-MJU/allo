import 'dart:async';
import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../scene/passersby.dart';
import '../scene/window_scene.dart';
import '../theme/allo_colors.dart';
import 'cabin_geometry.dart';
import 'species_art.dart';

part 'window/cabin.dart';
part 'window/passersby_painter.dart';
part 'window/side_scene.dart';
part 'window/windshield.dart';

/// 뒷좌석 가운데에서 본 차 안과 창밖. `/vehicle` 의 envTags·속도에 따라 장면이 바뀐다 (이슈 #45).
///
/// 앞유리에는 소실점이 있는 원근 도로가, 양 옆창에는 고정된 풍경이 보인다.
/// 통과 사건의 유한 재생 중 와이퍼가 [VehicleState.wiperLevel] 속도로 움직이고, 급제동·급조향이면
/// 룸미러의 알 장식이 흔들린다. 창밖에는 장면별 생물과 아이가 모은 캐릭터([friends])가
/// 무작위로 지나간다. 그림은 D 아트가 나오기 전까지 코드로 그린 임시 장면이다.
/// [child] 는 가운데 팔걸이 위에 놓이는 알·캐릭터다.
class WindowView extends StatefulWidget {
  const WindowView({
    super.key,
    required this.vehicle,
    this.child,
    this.height = 300,
    this.friends = const [],
    this.nowMs,
    this.random,
    this.animatePassersby = true,
    this.childFillsScene = false,
  });

  final VehicleState? vehicle;
  final Widget? child;
  final double height;

  /// 유한 통과 사건을 켠다. false는 실제 앱과 캡처 모두에서 정지 표시다.
  final bool animatePassersby;

  /// 비율 기반 캐릭터 배치가 필요한 경우 전체 차 안을 child의 제약으로 준다.
  final bool childFillsScene;

  /// 아이가 이미 모은 캐릭터. 이 중에서만 창밖에 나타난다 ([eligibleFriends]).
  final List<Species> friends;

  /// 장면 유지 시간 계산용 시계. 테스트에서 주입한다.
  final int Function()? nowMs;

  /// 지나가는 것들의 무작위 간격. 테스트에서 시드를 고정한다.
  final math.Random? random;

  @override
  State<WindowView> createState() => _WindowViewState();
}

class _WindowViewState extends State<WindowView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _stabilizer = SceneStabilizer();
  final _motion = _Motion();
  late final _spawner = PasserbySpawner(random: widget.random);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  late WindowScene _scene;
  bool _animate = false;
  bool _active = true;
  Timer? _spawnTimer;
  double? _kickUntil;
  final _clock = Stopwatch()..start();
  WindowScene? _previous;
  late final _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: AlloPresentation.fadeDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// 옆창 풍경을 그리는 가상 창 크기. 넓게 그린 뒤 원근을 넣어 사다리꼴 창에 붙인다.
  static const _sideCanvas = Size(300, 240);

  int _now() => widget.nowMs?.call() ?? _clock.elapsedMilliseconds;

  @override
  void initState() {
    super.initState();
    _active = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _scene =
        _stabilizer.update(WindowScene.fromVehicle(widget.vehicle), _now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = TickerMode.valuesOf(context).enabled &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _syncTicker();
  }

  @override
  void didUpdateWidget(WindowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vehicle, widget.vehicle)) {
      final prev = _scene;
      _scene =
          _stabilizer.update(WindowScene.fromVehicle(widget.vehicle), _now());
      if ((prev.kind, prev.night, prev.highway, prev.rainLevel) !=
          (_scene.kind, _scene.night, _scene.highway, _scene.rainLevel)) {
        _previous = prev;
        if (_active && TickerMode.valuesOf(context).enabled) {
          _fade.forward(from: 0);
        } else {
          _fade.value = 1;
        }
      }
      final o = oldWidget.vehicle, n = widget.vehicle;
      if (o != null &&
          n != null &&
          n.ts > o.ts &&
          n.harshBrake + n.harshSteer > o.harshBrake + o.harshSteer) {
        _startKick();
      }
    }
    // 비/고속도로/수집 목록 변경도 기존 통과 개체에 즉시 적용한다.
    _spawner.onSceneChanged(_scene, widget.friends);
    _motion.advance(0, 0);
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  bool get _canAnimate => _active && _animate && widget.animatePassersby;
  bool get _canSpawn => _canAnimate && _scene.moving;

  void _startKick() {
    if (!_canAnimate || _kickUntil != null) return;
    _spawnTimer?.cancel();
    _spawnTimer = null;
    _motion.kickAt = _motion.seconds;
    _kickUntil = _motion.seconds + .6;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _syncTicker() {
    if (!_canAnimate) {
      _spawnTimer?.cancel();
      _spawnTimer = null;
      _ticker.stop();
      _spawner.active.clear();
      _kickUntil = null;
      _motion.kickAt = -100;
      _motion.advance(0, 0);
      if (!_active || !TickerMode.valuesOf(context).enabled) _fade.value = 1;
      return;
    }
    if (!_scene.moving) {
      _spawnTimer?.cancel();
      _spawnTimer = null;
      _spawner.active.clear();
      _motion.advance(0, 0);
    }
    if (_spawner.active.isEmpty && _kickUntil == null && _ticker.isActive) {
      _ticker.stop();
      _queueSpawn(const Duration(seconds: 6));
    } else if (!_ticker.isActive && _spawnTimer == null) {
      _queueSpawn(const Duration(seconds: 2));
    }
  }

  void _queueSpawn(Duration delay) {
    if (_spawnTimer != null || !_canSpawn || _kickUntil != null) return;
    _spawnTimer = Timer(delay, () {
      _spawnTimer = null;
      if (!mounted || !_canSpawn || _kickUntil != null) return;
      final t = _motion.seconds + 8;
      _spawner.update(t, _scene, widget.friends);
      _motion.advance(0, 8);
      if (_spawner.active.isEmpty) {
        _queueSpawn(const Duration(seconds: 6));
        return;
      }
      _last = Duration.zero;
      _ticker.start();
    });
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final next = _motion.seconds + dt;
    _spawner.active.removeWhere((p) => p.done(next));
    if (_kickUntil != null && next >= _kickUntil!) _kickUntil = null;
    // 도로·풍경의 누적 거리는 항상 0. 유한 통과 사건의 시간만 진행한다.
    _motion.advance(0, dt);
    if (_spawner.active.isEmpty && _kickUntil == null) {
      _ticker.stop();
      _queueSpawn(const Duration(seconds: 6));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spawnTimer?.cancel();
    _ticker.dispose();
    _fade.dispose();
    _motion.dispose();
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
        child: LayoutBuilder(builder: (context, box) {
          final layout = CabinLayout(Size(box.maxWidth, widget.height));
          return ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(
                    child: AnimatedBuilder(
                  animation: _fade,
                  builder: (_, __) {
                    final opacity =
                        AlloPresentation.standardCurve.transform(_fade.value);
                    Widget background(WindowScene scene) => Stack(children: [
                          for (final pane in Pane.values)
                            _pane(layout, pane, scene),
                          Positioned.fill(
                              child: IgnorePointer(
                                  child: CustomPaint(
                                      painter: _CabinPainter(
                                          scene, _motion, layout)))),
                        ]);
                    return Stack(children: [
                      if (_previous != null && opacity < 1)
                        Opacity(
                            opacity: 1 - opacity,
                            child: background(_previous!)),
                      Opacity(opacity: opacity, child: background(s)),
                    ]);
                  },
                )),
                if (widget.child != null && widget.childFillsScene)
                  Positioned.fill(child: widget.child!),
                if (widget.child != null && !widget.childFillsScene)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 4,
                    child: Center(child: widget.child),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// 유리창 하나. 앞유리는 창 크기 그대로, 옆창은 넓게 그린 뒤 원근 변환으로 붙인다.
  Widget _pane(CabinLayout layout, Pane pane, WindowScene s) {
    final rain = s.rainLevel > 0;
    if (pane == Pane.windshield) {
      final b = layout.bounds(pane);
      return Positioned.fromRect(
        rect: b,
        child: ClipPath(
          clipper: _PathClipper(layout.path(pane).shift(-b.topLeft)),
          child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _WindshieldPainter(s, _motion, _spawner)),
            CustomPaint(painter: _PasserbyPainter(_spawner, _motion, pane)),
            if (rain)
              CustomPaint(
                  painter: _RainPainter(s.rainLevel, 0, _motion, wipers: true)),
          ]),
        ),
      );
    }
    final mirror = paneFlow(pane) > 0;
    return Positioned.fill(
      child: ClipPath(
        clipper: _PathClipper(layout.path(pane)),
        child: Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            width: _sideCanvas.width,
            height: _sideCanvas.height,
            child: Transform(
              transform: rectToQuad(_sideCanvas, layout.quad(pane)),
              child: Stack(fit: StackFit.expand, children: [
                CustomPaint(painter: _ScenePainter(s, _motion, mirror: mirror)),
                CustomPaint(painter: _PasserbyPainter(_spawner, _motion, pane)),
                _Friends(spawner: _spawner, motion: _motion, pane: pane),
                if (rain)
                  CustomPaint(painter: _RainPainter(s.rainLevel, 0, _motion)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PathClipper extends CustomClipper<Path> {
  _PathClipper(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClipper oldClipper) => true;
}

/// 옆창 밖에서 차를 따라 달리는 친구(모은 캐릭터).
/// 앞쪽에서 들어와 한동안 나란히 달리다가(가끔 손을 흔든다) 뒤로 처진다.
class _Friends extends StatelessWidget {
  const _Friends(
      {required this.spawner, required this.motion, required this.pane});

  final PasserbySpawner spawner;
  final _Motion motion;
  final Pane pane;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: motion,
        builder: (context, _) {
          final t = motion.seconds;
          final flip = paneFlow(pane) > 0;
          return LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            final children = <Widget>[];
            for (final p in spawner.active) {
              if (p.kind != PasserbyKind.friend ||
                  p.pane != pane ||
                  !p.visible(t)) {
                continue;
              }
              final size = h * 0.34 * p.scale;
              final pr = p.progress(t);
              final age = t - p.bornAt;
              // 왼쪽 창 기준: 앞(오른쪽)에서 들어와 가운데쯤 머물다 뒤(왼쪽)로 빠진다
              final double cx;
              if (pr < 0.2) {
                cx = w + size - (w * 0.45 + size) * (pr / 0.2);
              } else if (pr < 0.8) {
                cx = w * 0.55 + math.sin(age * 1.3 + p.seed) * w * 0.06;
              } else {
                cx = w * 0.55 - (w * 0.55 + size * 1.2) * ((pr - 0.8) / 0.2);
              }
              final hop = (math.sin(age * 7)).abs() * h * 0.05;
              final x = flip ? w - cx : cx;
              final wave = p.waves && pr > 0.3 && pr < 0.75
                  ? math.sin(age * 6) * 0.18
                  : 0.0;
              children.add(Positioned(
                left: x - size / 2,
                top: h * (0.86 - p.lane * 0.05) - size - hop,
                width: size,
                height: size,
                child: Transform.rotate(
                  angle: wave,
                  child: Transform.flip(
                    flipX: flip,
                    child: SpeciesArt(species: p.friend!, size: size),
                  ),
                ),
              ));
            }
            return Stack(clipBehavior: Clip.none, children: children);
          });
        },
      );
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

/// 고정 풍경 거리와 유한 사건 시간. 도로 이동은 허용하지 않는다.
class _Motion extends ChangeNotifier {
  double get meters => 0;
  double seconds = 0;

  /// 급제동·급조향이 들어온 시각. 룸미러 알 장식을 크게 흔든다.
  double kickAt = -100;

  void advance(double dm, double dt) {
    assert(dm == 0, '창밖 배경은 이동하지 않습니다.');
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
  static const eggYellow = Color(0xFFFCCC44); // shell-yellow
  static const logoYellowGlow = Color(0xFFFFD34E); // logo-yellow

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
