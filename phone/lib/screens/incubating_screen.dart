import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:allo_core/allo_core.dart';

import '../game/game_controller.dart';

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
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    final v = widget.controller.vehicle;
    _harsh = (v?.harshBrake ?? 0) + (v?.harshSteer ?? 0);
    widget.controller.addListener(_onSignal);
  }

  void _onSignal() {
    final c = widget.controller;
    final harsh = (c.vehicle?.harshBrake ?? 0) + (c.vehicle?.harshSteer ?? 0);
    if (harsh > _harsh) _shake.forward(from: 0);
    _harsh = harsh;
    if (c.game.stage == Stage.hatched && !_routing) {
      _routing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/hatching');
      });
    }
  }

  void _care() {
    widget.controller.care();
    _shake.stop();
    _shake.value = 0;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSignal);
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
        final remaining = g.hatchAtSec != null
            ? '앞으로 ${((1 - g.progress) * g.hatchAtSec! / 60).ceil()}분'
            : '앞으로 ${((1 - g.progress) * (g.hatchAtM ?? 0) / 1000).toStringAsFixed(1)}km';
        return Scaffold(
          appBar: AppBar(
              title: const Text('알 품기'), automaticallyImplyLeading: false),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(remaining,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 32),
                AnimatedBuilder(
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
                          size: 180,
                          color: _singing
                              ? Colors.teal.shade300
                              : Colors.amber.shade300)),
                ),
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
