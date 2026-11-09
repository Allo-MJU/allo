import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:allo_core/allo_core.dart';

import '../game/game_controller.dart';
import '../widgets/game_orientation.dart';
import '../widgets/egg_art.dart';
import '../widgets/window_view.dart';
import '../theme/allo_colors.dart';

class IncubatingScreen extends StatefulWidget {
  const IncubatingScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<IncubatingScreen> createState() => _IncubatingScreenState();
}

class _IncubatingScreenState extends State<IncubatingScreen>
    with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  int _harsh = 0;
  bool _singing = false;
  bool _hugging = false;
  Timer? _hugTimer;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    GameOrientation.acquire();
    final v = widget.controller.vehicle;
    _harsh = (v?.harshBrake ?? 0) + (v?.harshSteer ?? 0);
    widget.controller.addListener(_onSignal);
    // 구독 직후 받은 신호로 화면이 열리기 전에 부화했을 수도 있다.
    _onSignal();
  }

  void _onSignal() {
    final c = widget.controller;
    if (c.sessionEnded) return;
    final harsh = (c.vehicle?.harshBrake ?? 0) + (c.vehicle?.harshSteer ?? 0);
    if (harsh > _harsh) _shake.forward(from: 0);
    _harsh = harsh;
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

  bool get _canCare =>
      widget.controller.game.stage == Stage.incubating &&
      !widget.controller.sessionEnded &&
      !widget.controller.endingSession;

  void _hug() {
    if (!_canCare) return;
    _care();
    _hugTimer?.cancel();
    setState(() => _hugging = true);
    _hugTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hugging = false);
    });
  }

  void _care() {
    widget.controller.care();
    _shake.stop();
    _shake.value = 0;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSignal);
    _hugTimer?.cancel();
    _shake.dispose();
    GameOrientation.release();
    super.dispose();
  }

  Widget _scene(GameState g, double height, double width) {
    final targetSize =
        math.min(184.0, math.min(height - 28, width - 24)).clamp(56.0, 184.0);
    return WindowView(
      key: const ValueKey('incubating-game-scene'),
      vehicle: widget.controller.vehicle,
      friends: widget.controller.collectedSpecies,
      height: height,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (_, child) => Transform.rotate(
          angle: MediaQuery.disableAnimationsOf(context)
              ? 0
              : math.sin(_shake.value * math.pi * 8) * .15 * (1 - _shake.value),
          child: child,
        ),
        child: Semantics(
          button: true,
          enabled: _canCare,
          label: '알 감싸기',
          hint: '알을 직접 누르면 감싸 줄 수 있어요',
          onTap: _canCare ? _hug : null,
          child: GestureDetector(
            key: const ValueKey('egg-touch-target'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _canCare ? _hug : null,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AlloPresentation.fadeDuration,
              width: targetSize,
              height: targetSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hugging
                    ? AlloColors.growthGreen.withValues(alpha: .15)
                    : Colors.transparent,
                border: Border.all(
                    width: 3,
                    color:
                        _hugging ? AlloColors.growthGreen : Colors.transparent),
              ),
              alignment: Alignment.center,
              child: EggArt(
                size: targetSize * .79,
                tier: g.eggTier,
                progress: g.progress,
                color: _singing || _hugging
                    ? AlloColors.growthGreen
                    : AlloColors.shellYellow,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(GameState g, String remaining) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(remaining,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Semantics(
              liveRegion: true,
              child: Text(
                  _hugging
                      ? '알을 감싸 주었어요'
                      : _singing
                          ? '노래를 듣고 편안해졌어요'
                          : '알을 직접 눌러 감싸 주세요',
                  textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: g.progress,
            minHeight: 12,
            semanticsLabel: '알 성장',
            semanticsValue: '${(g.progress * 100).round()}%',
          ),
          const SizedBox(height: 8),
          Text('성장 ${(g.progress * 100).round()}% · 돌봄 ${g.careCount}회',
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: (widget.controller.vehicle?.envTags ?? [])
                  .map((t) => Chip(label: Text(t)))
                  .toList()),
          if (widget.controller.error != null)
            Semantics(liveRegion: true, child: Text(widget.controller.error!)),
        ],
      );

  Widget _song() => Semantics(
        button: true,
        enabled: _canCare,
        label: '길게 눌러 노래',
        onLongPress: _canCare ? _care : null,
        child: GestureDetector(
          excludeFromSemantics: true,
          onLongPressStart: !_canCare
              ? null
              : (_) {
                  _care();
                  setState(() => _singing = true);
                },
          onLongPressEnd: (_) => setState(() => _singing = false),
          onLongPressCancel: () => setState(() => _singing = false),
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AlloColors.softBackground,
                borderRadius: BorderRadius.circular(24)),
            child: const Text('♫ 길게 눌러 노래', textAlign: TextAlign.center),
          ),
        ),
      );

  Widget _leave() => TextButton(
        style: TextButton.styleFrom(
            minimumSize: const Size(56, 56),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        onPressed: () async {
          final saved = await widget.controller.endSession();
          if (saved && mounted) context.go('/pairing');
        },
        child: const Text('품기 저장하고 나가기', textAlign: TextAlign.center),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final g = c.game;
          final remaining = g.stage == Stage.idle
              ? '남은 주행이 짧아 다음 알을 기다리고 있어요'
              : g.hatchAtSec != null
                  ? '앞으로 ${((1 - g.progress) * g.hatchAtSec! / 60).ceil()}분'
                  : '앞으로 ${((1 - g.progress) * (g.hatchAtM ?? 0) / 1000).toStringAsFixed(1)}km';
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 56,
              title: const Text('알 품기',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              automaticallyImplyLeading: false,
              actions: [
                if (c.isFake)
                  TextButton(
                      style:
                          TextButton.styleFrom(minimumSize: const Size(56, 56)),
                      onPressed: c.endFakeTrip,
                      child: const Text('주행 종료')),
              ],
            ),
            body: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final panel =
                        (constraints.maxWidth * .28).clamp(192.0, 256.0);
                    final sceneWidth = constraints.maxWidth - panel - 12;
                    final landscape =
                        constraints.maxWidth >= constraints.maxHeight &&
                            sceneWidth >= 220 &&
                            constraints.maxHeight >= 220;
                    if (!landscape) {
                      return ListView(children: [
                        const Text('휴대폰을 가로로 돌리면 장면과 조작을 함께 볼 수 있어요.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        _scene(g, 240, constraints.maxWidth),
                        const SizedBox(height: 12),
                        _details(g, remaining),
                        const SizedBox(height: 16),
                        _song(),
                        _leave(),
                      ]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                            child:
                                _scene(g, constraints.maxHeight, sceneWidth)),
                        const SizedBox(width: 12),
                        SizedBox(
                          key: const ValueKey('incubating-controls'),
                          width: panel,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                  child: SingleChildScrollView(
                                      child: _details(g, remaining))),
                              const SizedBox(height: 8),
                              _song(),
                              const SizedBox(height: 8),
                              _leave(),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                )),
          );
        },
      );
}
