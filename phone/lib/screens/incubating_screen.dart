import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:allo_core/allo_core.dart';

import '../game/game_controller.dart';

/// 품기. 알 + 진행도 + 감싸기/노래. 흔들림(harsh 증가)에 알이 반응한다.
class IncubatingScreen extends StatelessWidget {
  const IncubatingScreen({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final g = controller.game;
        final v = controller.vehicle;
        if (g.stage == Stage.hatched) {
          WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/hatching'));
        }
        final remaining = g.hatchAtSec != null
            ? '앞으로 ${((1 - g.progress) * g.hatchAtSec! / 60).ceil()}분'
            : '앞으로 ${((1 - g.progress) * (g.hatchAtM ?? 0) / 1000).toStringAsFixed(1)}km';
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                Text(remaining, style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                // TODO(B/D): 알 스프라이트 3단계 + 흔들림 애니메이션 (v.harshBrake 변화 감지)
                Container(width: 180, height: 220, decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(90))),
                const SizedBox(height: 16),
                if (v != null) Wrap(spacing: 8, children: v.envTags.map((t) => Chip(label: Text(t))).toList()),
                const Spacer(),
                LinearProgressIndicator(value: g.progress, minHeight: 12),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.icon(onPressed: controller.care, icon: const Icon(Icons.favorite), label: Text('감싸기 ${g.careCount}')),
                    FilledButton.tonalIcon(onPressed: controller.care, icon: const Icon(Icons.music_note), label: const Text('노래')),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
