import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:allo_core/allo_core.dart';

import '../explore/explore_screen.dart';
import '../game/game_controller.dart';
import '../ui_mode.dart';
import '../widgets/window_view.dart';

class IncubatingScreen extends StatefulWidget {
  const IncubatingScreen(
      {super.key, required this.controller, this.enterExplore});
  final GameController controller;

  /// 알을 품기 시작하면 바로 Unity 차 안 탐험으로 들어간다 (둥지의 알을 돌보다 그 안에서 깨어난다).
  /// 탐험을 닫으면 이 화면에 남고, 오른쪽 위 버튼으로 다시 들어간다
  /// null 이면 [autoEnterExplore] 를 따른다
  final bool? enterExplore;

  @override
  State<IncubatingScreen> createState() => _IncubatingScreenState();
}

class _IncubatingScreenState extends State<IncubatingScreen>
    with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  int _harsh = 0;
  bool _singing = false;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    final v = widget.controller.vehicle;
    _harsh = (v?.harshBrake ?? 0) + (v?.harshSteer ?? 0);
    widget.controller.addListener(_onSignal);
    exploreScreenOpen.addListener(_onExploreOpen);
    // 구독 직후 받은 신호로 화면이 열리기 전에 부화했을 수도 있다.
    _onSignal();
    if (_enterExplore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = widget.controller;
        if (mounted &&
            !_routing &&
            !c.sessionEnded &&
            c.game.stage == Stage.incubating) {
          _openExplore();
        }
      });
    }
  }

  void _onSignal() {
    final c = widget.controller;
    if (c.sessionEnded) return;
    final harsh = (c.vehicle?.harshBrake ?? 0) + (c.vehicle?.harshSteer ?? 0);
    if (harsh > _harsh) _shake.forward(from: 0);
    _harsh = harsh;
    // 차 안 탐험이 위에 떠 있으면 부화 화면으로 넘기지 않는다. 탐험 안에서 둥지의 알이 깨어나고,
    // 탐험을 닫을 때 [_openExplore] 가 이어서 처리한다
    if (_exploring) return;
    if (c.game.stage == Stage.hatched && !_routing) {
      _routing = true;
      final eggId = c.eggId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !c.sessionEnded &&
            c.game.stage == Stage.hatched &&
            c.eggId == eggId) {
          context.go('/hatching');
        } else {
          _routing = false;
        }
      });
    }
  }

  bool get _exploring => exploreScreenOpen.value;
  bool _sawExplore = false;

  bool get _enterExplore => widget.enterExplore ?? autoEnterExplore;

  void _openExplore() => context.push('/explore');

  /// 차 안 탐험이 닫혔다. 그 안에서 알이 깨어나는 연출을 봤으면 부화 화면을 건너뛰고 동행 화면으로,
  /// 아니면 평소처럼 신호를 다시 본다 (깨어났으면 부화 화면).
  /// 앱 라우터가 컨트롤러가 바뀔 때마다 경로를 다시 계산해 push 결과가 사라지므로, 결과 대신
  /// [exploreScreenOpen]·[exploreHatchShown] 을 본다
  void _onExploreOpen() {
    if (exploreScreenOpen.value) {
      _sawExplore = true;
      return;
    }
    if (!_sawExplore) return;
    _sawExplore = false;
    final shown = exploreHatchShown;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = widget.controller;
      if (shown &&
          c.game.stage == Stage.hatched &&
          !c.sessionEnded &&
          !_routing) {
        _routing = true;
        context.go('/companion');
        return;
      }
      _onSignal();
    });
  }

  void _care() {
    widget.controller.care();
    _shake.stop();
    _shake.value = 0;
  }

  /// 차 안 화면만 꽉 채운다. 알 탭 = 감싸기, 길게 누르기 = 노래.
  Widget _fullscreen(GameController c, GameState g) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          _fullscreenCabin(c, g),
          if (_enterExplore)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton.filledTonal(
                    tooltip: '차 안 둘러보기',
                    icon: const Icon(Icons.threed_rotation),
                    onPressed: _openExplore,
                  ),
                ),
              ),
            ),
        ]),
      );

  Widget _fullscreenCabin(GameController c, GameState g) => LayoutBuilder(
        builder: (context, box) => WindowView(
          vehicle: c.vehicle,
          friends: c.collectedSpecies,
          height: box.maxHeight,
          rounded: false,
          child: Semantics(
            container: true, // 차 안 화면 라벨과 합쳐지지 않게 따로 둔다
            button: true,
            label: '자라고 있는 알, 돌봄 ${g.careCount}회',
            child: GestureDetector(
              onTap: _care,
              onLongPressStart: (_) {
                _care();
                setState(() => _singing = true);
              },
              onLongPressEnd: (_) => setState(() => _singing = false),
              child: AnimatedBuilder(
                animation: _shake,
                builder: (_, child) => Transform.rotate(
                  angle: math.sin(_shake.value * math.pi * 8) *
                      0.15 *
                      (1 - _shake.value),
                  child: child,
                ),
                child: Icon(Icons.egg,
                    size: box.maxHeight * 0.3,
                    color: _singing
                        ? Colors.teal.shade300
                        : Colors.amber.shade300),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    widget.controller.removeListener(_onSignal);
    exploreScreenOpen.removeListener(_onExploreOpen);
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final g = c.game;
        final remaining = g.stage == Stage.idle
            ? '남은 주행이 짧아 다음 알을 기다리고 있어요'
            : g.hatchAtSec != null
                ? '앞으로 ${((1 - g.progress) * g.hatchAtSec! / 60).ceil()}분'
                : '앞으로 ${((1 - g.progress) * (g.hatchAtM ?? 0) / 1000).toStringAsFixed(1)}km';
        if (fullscreenCabin) return _fullscreen(c, g);
        return Scaffold(
          appBar: AppBar(
              title: const Text('알 품기'),
              automaticallyImplyLeading: false,
              actions: [
                if (c.isFake)
                  TextButton(
                      onPressed: c.endFakeTrip, child: const Text('주행 종료')),
              ]),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(remaining,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                WindowView(
                  vehicle: c.vehicle,
                  friends: c.collectedSpecies,
                  // 가로 화면에서 버튼이 밀려나지 않게 화면 높이의 절반까지만 (가로 2단 개편 전 임시)
                  height:
                      math.min(300, MediaQuery.sizeOf(context).height * 0.5),
                  child: AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) => Transform.rotate(
                      angle: math.sin(_shake.value * math.pi * 8) *
                          0.15 *
                          (1 - _shake.value),
                      child: child,
                    ),
                    child: Semantics(
                        label: '자라고 있는 알',
                        child: Icon(Icons.egg,
                            size: 120,
                            color: _singing
                                ? Colors.teal.shade300
                                : Colors.amber.shade300)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_singing ? '노래를 듣고 편안해졌어요' : '흔들리면 알을 감싸 주세요',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: (c.vehicle?.envTags ?? [])
                        .map((t) => Chip(label: Text(t)))
                        .toList()),
                const SizedBox(height: 24),
                LinearProgressIndicator(
                    value: g.progress,
                    minHeight: 12,
                    semanticsLabel: '알 성장',
                    semanticsValue: '${(g.progress * 100).round()}%'),
                const SizedBox(height: 12),
                Text('성장 ${(g.progress * 100).round()}% · 돌봄 ${g.careCount}회',
                    textAlign: TextAlign.center),
                if (c.error != null) Text(c.error!),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: _care,
                    icon: const Icon(Icons.favorite),
                    label: const Text('감싸기')),
                const SizedBox(height: 12),
                Semantics(
                  button: true,
                  label: '길게 눌러 노래',
                  onLongPress: _care,
                  child: GestureDetector(
                    onLongPressStart: (_) {
                      _care();
                      setState(() => _singing = true);
                    },
                    onLongPressEnd: (_) => setState(() => _singing = false),
                    child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(24)),
                        child: const Text('♫ 길게 눌러 노래',
                            textAlign: TextAlign.center)),
                  ),
                ),
                TextButton.icon(
                    onPressed: _openExplore,
                    icon: const Icon(Icons.threed_rotation),
                    label: const Text('차 안 둘러보기')),
                TextButton(
                    onPressed: () async {
                      final saved = await c.endSession();
                      if (saved && context.mounted) context.go('/pairing');
                    },
                    child: const Text('품기 저장하고 나가기')),
              ],
            ),
          ),
        );
      },
    );
  }
}
